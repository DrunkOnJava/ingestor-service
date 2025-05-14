#!/bin/bash
# Error handling and recovery module for ingestor
# This module provides consistent error handling, tracing, and recovery mechanisms

# Constants for exit code categories
readonly ERR_GENERAL=1            # General errors
readonly ERR_CONFIG=10            # Configuration errors (10-19)
readonly ERR_PERMISSION=20        # Permission errors (20-29)
readonly ERR_FILE=30              # File operation errors (30-39)
readonly ERR_NETWORK=40           # Network operation errors (40-49)
readonly ERR_DATABASE=50          # Database operation errors (50-59)
readonly ERR_API=60               # API operation errors (60-69)
readonly ERR_DEPENDENCY=70        # Missing dependency errors (70-79)
readonly ERR_VALIDATION=80        # Input validation errors (80-89)
readonly ERR_TIMEOUT=90           # Timeout errors (90-99)

# Maps error codes to human-readable descriptions
declare -A ERROR_DESCRIPTIONS=(
  [$ERR_GENERAL]="General error"
  [$ERR_CONFIG]="Configuration error"
  [$ERR_PERMISSION]="Permission denied"
  [$ERR_FILE]="File operation error"
  [$ERR_NETWORK]="Network operation error"
  [$ERR_DATABASE]="Database operation error"
  [$ERR_API]="API operation error"
  [$ERR_DEPENDENCY]="Missing dependency"
  [$ERR_VALIDATION]="Input validation error"
  [$ERR_TIMEOUT]="Operation timed out"
)

# Default retry settings
DEFAULT_MAX_RETRIES=3
DEFAULT_RETRY_DELAY=2
DEFAULT_TIMEOUT=30

# Initialize error handling
init_error_handling() {
  # Set global error handling options
  set -o pipefail
  
  log_debug "Error handling initialized"
  
  # Register global error handler
  trap 'error_trap ${LINENO} ${FUNCNAME[0]:-main} $?' ERR
  
  # Register cleanup handler
  trap 'cleanup_handler' EXIT
}

# Error trap for capturing errors
error_trap() {
  local line=$1
  local func=$2
  local exit_code=$3
  
  # Log the error with context
  log_error "Error in function '$func' at line $line (exit code: $exit_code)"
  
  # Get the error description if available
  local error_desc="${ERROR_DESCRIPTIONS[$exit_code]:-Unknown error}"
  log_error "Error description: $error_desc"
}

# Cleanup handler for exit
cleanup_handler() {
  local exit_code=$?
  
  # Only run cleanup for non-zero exit codes
  if [[ $exit_code -ne 0 ]]; then
    log_debug "Running cleanup for exit code $exit_code"
    # Add cleanup operations here (temp files, connections, etc.)
  fi
}

# Validate that all required commands are available
check_dependencies() {
  local missing=0
  
  for cmd in "$@"; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "Required dependency not found: $cmd"
      missing=$((missing + 1))
    fi
  done
  
  if [[ $missing -gt 0 ]]; then
    log_error "Missing $missing required dependencies"
    return $ERR_DEPENDENCY
  fi
  
  return 0
}

# Verify file exists and is readable
check_file_readable() {
  local file_path="$1"
  
  if [[ ! -f "$file_path" ]]; then
    log_error "File not found: $file_path"
    return $ERR_FILE
  fi
  
  if [[ ! -r "$file_path" ]]; then
    log_error "File not readable: $file_path"
    return $ERR_PERMISSION
  fi
  
  return 0
}

# Verify file exists and is writable
check_file_writable() {
  local file_path="$1"
  
  if [[ -f "$file_path" ]]; then
    if [[ ! -w "$file_path" ]]; then
      log_error "File not writable: $file_path"
      return $ERR_PERMISSION
    fi
  else
    # File doesn't exist, check if directory is writable
    local dir_path
    dir_path=$(dirname "$file_path")
    
    if [[ ! -d "$dir_path" ]]; then
      log_error "Parent directory not found: $dir_path"
      return $ERR_FILE
    fi
    
    if [[ ! -w "$dir_path" ]]; then
      log_error "Parent directory not writable: $dir_path"
      return $ERR_PERMISSION
    fi
  fi
  
  return 0
}

# Verify directory exists or create it
ensure_directory() {
  local dir_path="$1"
  local create_if_missing="${2:-true}"
  
  if [[ ! -d "$dir_path" ]]; then
    log_debug "Directory not found: $dir_path"
    
    if [[ "$create_if_missing" == "true" ]]; then
      log_debug "Creating directory: $dir_path"
      if ! mkdir -p "$dir_path"; then
        log_error "Failed to create directory: $dir_path"
        return $ERR_FILE
      fi
    else
      log_error "Directory not found: $dir_path"
      return $ERR_FILE
    fi
  fi
  
  if [[ ! -w "$dir_path" ]]; then
    log_error "Directory not writable: $dir_path"
    return $ERR_PERMISSION
  fi
  
  return 0
}

# Validate variable is not empty
require_variable() {
  local var_name="$1"
  local var_value="$2"
  local error_message="${3:-Required variable $var_name is empty}"
  
  if [[ -z "$var_value" ]]; then
    log_error "$error_message"
    return $ERR_VALIDATION
  fi
  
  return 0
}

# Execute command with retry logic
retry_command() {
  local cmd="$1"
  local max_retries="${2:-$DEFAULT_MAX_RETRIES}"
  local retry_delay="${3:-$DEFAULT_RETRY_DELAY}"
  local timeout="${4:-$DEFAULT_TIMEOUT}"
  local retry_count=0
  local result=0
  
  log_debug "Executing command with retry: $cmd"
  log_debug "Retry settings: max_retries=$max_retries, retry_delay=$retry_delay, timeout=$timeout"
  
  # Keep trying until max retries is reached
  while [[ $retry_count -lt $max_retries ]]; do
    # Use timeout command if available
    if command -v timeout &> /dev/null; then
      timeout "$timeout" bash -c "$cmd" && result=0 || result=$?
    else
      # Fallback if timeout command is not available
      bash -c "$cmd" && result=0 || result=$?
    fi
    
    # If command succeeded, return success
    if [[ $result -eq 0 ]]; then
      if [[ $retry_count -gt 0 ]]; then
        log_info "Command succeeded after $retry_count retries"
      fi
      return 0
    fi
    
    # Command failed, increment retry counter
    retry_count=$((retry_count + 1))
    
    # If max retries reached, exit with error
    if [[ $retry_count -ge $max_retries ]]; then
      log_error "Command failed after $max_retries retries: $cmd (exit code: $result)"
      return $result
    fi
    
    # Retry with exponential backoff
    local wait_time=$((retry_delay * 2 ** (retry_count - 1)))
    log_warning "Command failed (attempt $retry_count/$max_retries), retrying in $wait_time seconds: $cmd"
    sleep "$wait_time"
  done
  
  # Should never reach here, but just in case
  return $result
}

# Execute function with retry logic
retry_function() {
  local func="$1"
  local max_retries="${2:-$DEFAULT_MAX_RETRIES}"
  local retry_delay="${3:-$DEFAULT_RETRY_DELAY}"
  local retry_count=0
  local result=0
  
  # Shift the first three arguments
  shift 3
  
  log_debug "Executing function with retry: $func"
  log_debug "Retry settings: max_retries=$max_retries, retry_delay=$retry_delay"
  
  # Keep trying until max retries is reached
  while [[ $retry_count -lt $max_retries ]]; do
    "$func" "$@" && result=0 || result=$?
    
    # If function succeeded, return success
    if [[ $result -eq 0 ]]; then
      if [[ $retry_count -gt 0 ]]; then
        log_info "Function $func succeeded after $retry_count retries"
      fi
      return 0
    fi
    
    # Function failed, increment retry counter
    retry_count=$((retry_count + 1))
    
    # If max retries reached, exit with error
    if [[ $retry_count -ge $max_retries ]]; then
      log_error "Function $func failed after $max_retries retries (exit code: $result)"
      return $result
    fi
    
    # Retry with exponential backoff
    local wait_time=$((retry_delay * 2 ** (retry_count - 1)))
    log_warning "Function $func failed (attempt $retry_count/$max_retries), retrying in $wait_time seconds"
    sleep "$wait_time"
  done
  
  # Should never reach here, but just in case
  return $result
}

# Run a command with a timeout
run_with_timeout() {
  local cmd="$1"
  local timeout_seconds="${2:-$DEFAULT_TIMEOUT}"
  local result=0
  
  log_debug "Running command with ${timeout_seconds}s timeout: $cmd"
  
  # Use timeout command if available
  if command -v timeout &> /dev/null; then
    timeout "$timeout_seconds" bash -c "$cmd" && result=0 || result=$?
    
    if [[ $result -eq 124 ]]; then
      log_error "Command timed out after ${timeout_seconds}s: $cmd"
      return $ERR_TIMEOUT
    elif [[ $result -ne 0 ]]; then
      log_error "Command failed: $cmd (exit code: $result)"
      return $result
    fi
  else
    # Fallback if timeout command is not available
    # This is a very basic implementation
    bash -c "$cmd" & 
    local pid=$!
    
    # Wait for process to complete or timeout
    local count=0
    while [[ $count -lt $timeout_seconds ]]; do
      if ! kill -0 $pid &>/dev/null; then
        # Process finished
        wait $pid
        result=$?
        if [[ $result -ne 0 ]]; then
          log_error "Command failed: $cmd (exit code: $result)"
          return $result
        fi
        return 0
      fi
      sleep 1
      count=$((count + 1))
    done
    
    # If we're here, the process timed out
    kill -9 $pid &>/dev/null
    log_error "Command timed out after ${timeout_seconds}s: $cmd"
    return $ERR_TIMEOUT
  fi
  
  return 0
}

# Validate config has all required fields
validate_config() {
  local config_file="$1"
  shift
  local required_fields=("$@")
  local missing=0
  
  if [[ ! -f "$config_file" ]]; then
    log_error "Config file not found: $config_file"
    return $ERR_CONFIG
  fi
  
  for field in "${required_fields[@]}"; do
    if ! grep -q "^$field:" "$config_file"; then
      log_error "Required config field missing: $field"
      missing=$((missing + 1))
    fi
  done
  
  if [[ $missing -gt 0 ]]; then
    log_error "Config validation failed: $missing required fields missing"
    return $ERR_CONFIG
  fi
  
  return 0
}

# Check SQLite database connectivity
check_database_connection() {
  local db_path="$1"
  
  if [[ ! -f "$db_path" ]]; then
    log_error "Database file not found: $db_path"
    return $ERR_DATABASE
  fi
  
  if ! sqlite3 "$db_path" "SELECT 1;" &>/dev/null; then
    log_error "Failed to connect to database: $db_path"
    return $ERR_DATABASE
  fi
  
  return 0
}

# Get the error description for a given error code
get_error_description() {
  local error_code="$1"
  
  echo "${ERROR_DESCRIPTIONS[$error_code]:-Unknown error}"
}

# Handle critical error and exit
handle_critical_error() {
  local message="$1"
  local exit_code="${2:-$ERR_GENERAL}"
  
  log_exception "$message" "$exit_code"
  
  # Perform any necessary cleanup here
  
  # Exit with the provided code
  exit "$exit_code"
}

# Alias functions for backward compatibility
exit_with_error() {
  handle_critical_error "$1" "$2"
}

check_command_exists() {
  local cmd="$1"
  check_dependencies "$cmd"
}