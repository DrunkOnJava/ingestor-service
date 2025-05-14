#!/bin/bash
# Error handling module for ingestor-system
# This module provides comprehensive error handling utilities to be used throughout the codebase

# Load error codes if not already loaded
if [[ -z "${ERR_UNKNOWN+x}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/error_codes.sh" ]]; then
        source "${script_dir}/error_codes.sh"
    else
        echo "WARNING: Error codes module not found"
        # Define minimal set of error codes
        export ERR_UNKNOWN=1
        export ERR_VALIDATION=21
        export ERR_FILE=11
        export ERR_DEPENDENCY=56
        export ERR_DATABASE=31
    fi
fi

# Error codes (1-50 reserved for system, we use 51+)
readonly ERR_MISSING_DEPENDENCY=51
readonly ERR_INVALID_ARGUMENT=52
readonly ERR_FILE_NOT_FOUND=53
readonly ERR_PERMISSION_DENIED=54
readonly ERR_EXTERNAL_COMMAND=55
readonly ERR_DATABASE=56
readonly ERR_NETWORK=57
readonly ERR_TIMEOUT=58
readonly ERR_ANALYSIS_FAILED=59
readonly ERR_KEYCHAIN=60
readonly ERR_CONFIG=61
readonly ERR_VALIDATION=62
readonly ERR_GENERIC=99

# Associative array to map error codes to messages
declare -A ERROR_MESSAGES=(
  [$ERR_MISSING_DEPENDENCY]="Missing required dependency"
  [$ERR_INVALID_ARGUMENT]="Invalid argument provided"
  [$ERR_FILE_NOT_FOUND]="File not found"
  [$ERR_PERMISSION_DENIED]="Permission denied"
  [$ERR_EXTERNAL_COMMAND]="External command failed"
  [$ERR_DATABASE]="Database operation failed"
  [$ERR_NETWORK]="Network operation failed"
  [$ERR_TIMEOUT]="Operation timed out"
  [$ERR_ANALYSIS_FAILED]="Analysis failed"
  [$ERR_KEYCHAIN]="Keychain operation failed"
  [$ERR_CONFIG]="Configuration error"
  [$ERR_VALIDATION]="Validation failed"
  [$ERR_GENERIC]="An unknown error occurred"
)

# Default retry settings
readonly DEFAULT_MAX_RETRIES=3
readonly DEFAULT_RETRY_DELAY=2

# Initialize error handler
init_error_handler() {
  # Enable bash error handling features
  set -o errexit   # Exit immediately on command errors
  set -o pipefail  # Exit when pipes fail
  set -o nounset   # Exit on unset variables
  
  # Trap errors so we can handle them gracefully
  trap 'handle_error ${LINENO} $?' ERR
  
  # Set global defaults for retries
  GLOBAL_MAX_RETRIES=${GLOBAL_MAX_RETRIES:-$DEFAULT_MAX_RETRIES}
  GLOBAL_RETRY_DELAY=${GLOBAL_RETRY_DELAY:-$DEFAULT_RETRY_DELAY}
  
  log_debug "Error handler initialized with max retries: $GLOBAL_MAX_RETRIES, retry delay: $GLOBAL_RETRY_DELAY"
}

# Reset error handler (unset traps)
reset_error_handler() {
  trap - ERR
  log_debug "Error handler reset"
}

# Handle errors from trap
handle_error() {
  local line_number="$1"
  local error_code="${2:-1}"
  local error_source="${BASH_SOURCE[1]:-unknown}"
  local error_message="${ERROR_MESSAGES[$error_code]:-${ERROR_MESSAGES[$ERR_GENERIC]}}"
  
  # Don't execute when sourcing
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return $error_code
  
  log_error "Error at ${error_source}:${line_number} - ${error_message} (code: ${error_code})"
  
  # Log stack trace if it exists
  local stack=""
  local i=1
  while caller $i > /dev/null; do
    local frame=$(caller $i)
    stack+=" > $(echo "$frame" | awk '{print $3 ":" $1 " in " $2}')"
    ((i++))
  done
  
  if [[ -n "$stack" ]]; then
    log_error "Stack trace:$stack"
  fi
  
  # If we're in a try block, just set the error flag
  if [[ -n "${_ERROR_HANDLER_IN_TRY:-}" ]]; then
    _ERROR_HANDLER_TRAPPED_CODE=$error_code
    _ERROR_HANDLER_TRAPPED_LINE=$line_number
    _ERROR_HANDLER_TRAPPED_SOURCE=$error_source
    return $error_code
  fi
  
  # If not, exit with the error code
  exit $error_code
}

# Raise a custom error
raise_error() {
  local message="$1"
  local code="${2:-$ERR_GENERIC}"
  
  log_error "$message (code: $code)"
  
  # If we're in a try block, just set the error flag
  if [[ -n "${_ERROR_HANDLER_IN_TRY:-}" ]]; then
    _ERROR_HANDLER_TRAPPED_CODE=$code
    _ERROR_HANDLER_TRAPPED_LINE=$LINENO
    _ERROR_HANDLER_TRAPPED_SOURCE=${BASH_SOURCE[1]:-unknown}
    return $code
  fi
  
  exit $code
}

# Validate that a command/dependency exists
require_dependency() {
  local cmd="$1"
  local message="${2:-Required command '$cmd' not found}"
  
  if ! command -v "$cmd" &>/dev/null; then
    raise_error "$message" $ERR_MISSING_DEPENDENCY
    return $ERR_MISSING_DEPENDENCY
  fi
  
  return 0
}

# Validate that a file exists
require_file() {
  local file="$1"
  local message="${2:-Required file '$file' not found}"
  
  if [[ ! -f "$file" ]]; then
    raise_error "$message" $ERR_FILE_NOT_FOUND
    return $ERR_FILE_NOT_FOUND
  fi
  
  return 0
}

# Validate that a directory exists
require_directory() {
  local dir="$1"
  local message="${2:-Required directory '$dir' not found}"
  local create="${3:-false}"
  
  if [[ ! -d "$dir" ]]; then
    if [[ "$create" == "true" ]]; then
      log_info "Creating directory: $dir"
      if ! mkdir -p "$dir"; then
        raise_error "Failed to create directory: $dir" $ERR_PERMISSION_DENIED
        return $ERR_PERMISSION_DENIED
      fi
    else
      raise_error "$message" $ERR_FILE_NOT_FOUND
      return $ERR_FILE_NOT_FOUND
    fi
  fi
  
  return 0
}

# Validate that a non-empty variable is set
require_var() {
  local var_name="$1"
  local message="${2:-Required variable '$var_name' is not set or empty}"
  
  if [[ -z "${!var_name:-}" ]]; then
    raise_error "$message" $ERR_INVALID_ARGUMENT
    return $ERR_INVALID_ARGUMENT
  fi
  
  return 0
}

# Try-catch mechanism for bash
try() {
  # Reset any previous error
  _ERROR_HANDLER_TRAPPED_CODE=0
  _ERROR_HANDLER_TRAPPED_LINE=0
  _ERROR_HANDLER_TRAPPED_SOURCE=""
  _ERROR_HANDLER_IN_TRY=1
  
  # Run the code in a subshell to capture errors
  (
    # Run the code
    "$@"
  )
  
  # Capture exit code
  local exit_code=$?
  
  # Save it for catch block
  _ERROR_HANDLER_CODE=$exit_code
  
  # Return the exit code to caller
  return $exit_code
}

# Catch mechanism for bash
catch() {
  # Only run if try has failed
  if [[ ${_ERROR_HANDLER_CODE:-0} -ne 0 ]]; then
    # Run the error handler function
    "$@" ${_ERROR_HANDLER_CODE} "${_ERROR_HANDLER_TRAPPED_LINE}" "${_ERROR_HANDLER_TRAPPED_SOURCE}"
    return $?
  fi
  
  # If we get here, try succeeded
  unset _ERROR_HANDLER_IN_TRY
  unset _ERROR_HANDLER_CODE
  unset _ERROR_HANDLER_TRAPPED_CODE
  unset _ERROR_HANDLER_TRAPPED_LINE
  unset _ERROR_HANDLER_TRAPPED_SOURCE
  return 0
}

# Retry mechanism for commands that may fail due to transient issues
retry() {
  local cmd="$1"
  local max_retries="${2:-$GLOBAL_MAX_RETRIES}"
  local delay="${3:-$GLOBAL_RETRY_DELAY}"
  local timeout="${4:-0}"
  local retry_count=0
  local exit_code=0
  
  log_debug "Running command with retry (max: $max_retries, delay: $delay): $cmd"
  
  while [[ $retry_count -lt $max_retries ]]; do
    # Run the command
    if [[ $timeout -gt 0 ]]; then
      # With timeout
      { timeout $timeout $cmd; exit_code=$?; } 2>&1
    else
      # Without timeout
      { $cmd; exit_code=$?; } 2>&1
    fi
    
    # Check exit code
    if [[ $exit_code -eq 0 ]]; then
      # Success
      [[ $retry_count -gt 0 ]] && log_info "Command succeeded after $retry_count retries"
      return 0
    else
      # Failed
      retry_count=$((retry_count + 1))
      
      if [[ $retry_count -lt $max_retries ]]; then
        log_warning "Command failed with exit code $exit_code, retrying in $delay seconds (attempt $retry_count/$max_retries)..."
        sleep $delay
        # Exponential backoff
        delay=$((delay * 2))
      else
        log_error "Command failed with exit code $exit_code after $retry_count retries"
        return $exit_code
      fi
    fi
  done
  
  # Should never get here
  return $exit_code
}

# Check if a command timed out
is_timeout() {
  local exit_code="$1"
  
  # Check for timeout exit codes
  if [[ $exit_code -eq 124 || $exit_code -eq 137 || $exit_code -eq 143 ]]; then
    return 0
  fi
  
  return 1
}

# Run a command with timeout and proper error handling
run_with_timeout() {
  local cmd="$1"
  local seconds="$2"
  local error_message="${3:-Command timed out after $seconds seconds}"
  local error_code="${4:-$ERR_TIMEOUT}"
  
  # Check if timeout command exists
  if ! command -v timeout &>/dev/null; then
    log_warning "Timeout command not available, running without timeout: $cmd"
    $cmd
    return $?
  fi
  
  # Run with timeout
  local output
  local exit_code
  
  output=$(timeout "$seconds" $cmd 2>&1)
  exit_code=$?
  
  # Check for timeout
  if is_timeout $exit_code; then
    log_error "$error_message"
    return $error_code
  elif [[ $exit_code -ne 0 ]]; then
    log_error "Command failed: $cmd (exit code: $exit_code)"
    log_error "Output: $output"
    return $exit_code
  fi
  
  echo "$output"
  return 0
}

# Safe database query execution with retry
safe_db_query() {
  local db_path="$1"
  local query="$2"
  local max_retries="${3:-$GLOBAL_MAX_RETRIES}"
  local delay="${4:-$GLOBAL_RETRY_DELAY}"
  
  # First verify that the db file exists (or its parent directory for new DBs)
  local db_dir
  db_dir=$(dirname "$db_path")
  
  require_directory "$db_dir" "Database directory not found: $db_dir" true

  # Now run the query with retries
  local retry_count=0
  local exit_code=0
  
  while [[ $retry_count -lt $max_retries ]]; do
    local result
    result=$(sqlite3 "$db_path" "$query" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
      [[ $retry_count -gt 0 ]] && log_info "Database query succeeded after $retry_count retries"
      echo "$result"
      return 0
    else
      retry_count=$((retry_count + 1))
      
      # Check for database locked errors
      if [[ "$result" == *"database is locked"* ]]; then
        log_warning "Database is locked, retrying in $delay seconds (attempt $retry_count/$max_retries)..."
        sleep $delay
        delay=$((delay * 2))  # Exponential backoff
      elif [[ "$result" == *"no such table"* ]]; then
        # Schema issue - we can't retry
        log_error "Database schema error: $result"
        return $ERR_DATABASE
      else
        # Other database error
        if [[ $retry_count -lt $max_retries ]]; then
          log_warning "Database query failed: $result, retrying in $delay seconds (attempt $retry_count/$max_retries)..."
          sleep $delay
          delay=$((delay * 2))  # Exponential backoff
        else
          log_error "Database query failed after $retry_count retries: $result"
          return $ERR_DATABASE
        fi
      fi
    fi
  done
  
  return $ERR_DATABASE
}

# Safe network request with retry
safe_network_request() {
  local url="$1"
  local method="${2:-GET}"
  local data="${3:-}"
  local headers="${4:-}"
  local timeout="${5:-30}"
  local max_retries="${6:-$GLOBAL_MAX_RETRIES}"
  local delay="${7:-$GLOBAL_RETRY_DELAY}"
  
  # Require curl
  require_dependency "curl" "Curl is required for network requests"
  
  # Build curl command
  local curl_cmd="curl -s -S -X $method"
  
  # Add timeout
  curl_cmd="$curl_cmd --connect-timeout $timeout --max-time $((timeout * 2))"
  
  # Add headers if provided
  if [[ -n "$headers" ]]; then
    curl_cmd="$curl_cmd -H \"$headers\""
  fi
  
  # Add data if provided
  if [[ -n "$data" ]]; then
    curl_cmd="$curl_cmd -d '$data'"
  fi
  
  # Add URL
  curl_cmd="$curl_cmd '$url'"
  
  # Run with retry
  local retry_count=0
  local exit_code=0
  
  while [[ $retry_count -lt $max_retries ]]; do
    local result
    eval "result=\$(${curl_cmd} 2>&1)"
    exit_code=$?
    
    # Check for curl exit codes
    if [[ $exit_code -eq 0 ]]; then
      # Check for HTTP errors in the response
      if [[ "$result" == *"\"error\""* || "$result" == *"\"errors\""* ]]; then
        retry_count=$((retry_count + 1))
        
        if [[ $retry_count -lt $max_retries ]]; then
          log_warning "API returned error response, retrying in $delay seconds (attempt $retry_count/$max_retries)..."
          sleep $delay
          delay=$((delay * 2))  # Exponential backoff
        else
          log_error "API request failed after $retry_count retries: $result"
          return $ERR_NETWORK
        fi
      else
        # Success
        [[ $retry_count -gt 0 ]] && log_info "Network request succeeded after $retry_count retries"
        echo "$result"
        return 0
      fi
    else
      # Connection error
      retry_count=$((retry_count + 1))
      
      if [[ $retry_count -lt $max_retries ]]; then
        log_warning "Network request failed with exit code $exit_code, retrying in $delay seconds (attempt $retry_count/$max_retries)..."
        sleep $delay
        delay=$((delay * 2))  # Exponential backoff
      else
        log_error "Network request failed after $retry_count retries: $result"
        return $ERR_NETWORK
      fi
    fi
  done
  
  return $ERR_NETWORK
}

# Validate inputs for a function
validate_inputs() {
  local func_name="$1"
  shift
  local expected_args=("$@")
  local args_count=${#expected_args[@]}
  local caller_args_count=${BASH_ARGC[1]:-0}
  
  # Check argument count
  if [[ $caller_args_count -lt $args_count ]]; then
    local missing=$((args_count - caller_args_count))
    raise_error "Function $func_name missing $missing required argument(s)" $ERR_INVALID_ARGUMENT
    return $ERR_INVALID_ARGUMENT
  fi
  
  # Validate each argument
  for i in "${!expected_args[@]}"; do
    local arg_name="${expected_args[$i]}"
    # Get the actual argument value from the caller's stack
    local arg_value=""
    local arg_index=$((i + 1))
    
    # Need to handle positional parameters correctly
    if [[ $caller_args_count -ge $arg_index ]]; then
      # This is a bit complex in bash - we need to get the arg from the caller frame
      arg_value="${BASH_ARGV[$(($caller_args_count - $arg_index))]:-}"
    fi
    
    if [[ -z "$arg_value" ]]; then
      raise_error "Function $func_name received empty value for required argument: $arg_name" $ERR_INVALID_ARGUMENT
      return $ERR_INVALID_ARGUMENT
    fi
  done
  
  return 0
}

# Safely create a temporary file with proper cleanup
create_temp_file() {
  local prefix="${1:-ingestor}"
  local suffix="${2:-}"
  local dir="${3:-$TEMP_DIR}"
  
  # Make sure temp dir exists
  require_directory "$dir" "Temporary directory not found: $dir" true
  
  # Create temp file
  local temp_file
  temp_file=$(mktemp "${dir}/${prefix}_XXXXXX${suffix}")
  
  if [[ $? -ne 0 || ! -f "$temp_file" ]]; then
    raise_error "Failed to create temporary file" $ERR_PERMISSION_DENIED
    return $ERR_PERMISSION_DENIED
  fi
  
  # Register cleanup handler if not already registered
  if [[ -z "${_TEMP_FILES:-}" ]]; then
    _TEMP_FILES=()
    trap cleanup_temp_files EXIT
  fi
  
  # Add to list of files to clean up
  _TEMP_FILES+=("$temp_file")
  
  echo "$temp_file"
}

# Clean up temporary files
cleanup_temp_files() {
  if [[ -n "${_TEMP_FILES:-}" ]]; then
    log_debug "Cleaning up ${#_TEMP_FILES[@]} temporary files"
    for temp_file in "${_TEMP_FILES[@]}"; do
      if [[ -f "$temp_file" ]]; then
        rm -f "$temp_file"
      fi
    done
    _TEMP_FILES=()
  fi
}

# Get human-readable error message for a code
get_error_message() {
  local code="$1"
  echo "${ERROR_MESSAGES[$code]:-Unknown error}"
}

# Check if an operation succeeded within a timeout
wait_for_operation() {
  local check_cmd="$1"
  local timeout="${2:-30}"
  local message="${3:-Operation timed out after $timeout seconds}"
  local interval="${4:-1}"
  local error_code="${5:-$ERR_TIMEOUT}"
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))
  
  log_debug "Waiting for operation: $check_cmd (timeout: ${timeout}s)"
  
  while [[ $(date +%s) -lt $end_time ]]; do
    if eval "$check_cmd" &>/dev/null; then
      log_debug "Operation completed successfully"
      return 0
    fi
    
    sleep $interval
  done
  
  log_error "$message"
  return $error_code
}

# Handle a critical error with custom message and exit code
handle_critical_error() {
  local message="$1"
  local exit_code="${2:-$ERR_UNKNOWN}"
  local cleanup_func="${3:-}"
  
  # Get a coded error message if available
  local error_name="Unknown error"
  local error_description="Unknown error occurred"
  
  if type -t get_error_name >/dev/null; then
    error_name=$(get_error_name "$exit_code")
  fi
  
  if type -t get_error_message >/dev/null; then
    error_description=$(get_error_message "$exit_code")
  fi
  
  log_error "CRITICAL ERROR: $message"
  log_error "Error code: $exit_code ($error_name)"
  log_error "Error description: $error_description"
  
  # Generate a traceback
  local i=0
  local stack=""
  
  while caller $i > /dev/null; do
    local frame=$(caller $i)
    local func=$(echo "$frame" | awk '{print $2}')
    local line=$(echo "$frame" | awk '{print $1}')
    local file=$(echo "$frame" | awk '{print $3}')
    
    stack+="\\n  #$i: $file:$line in function $func"
    i=$((i + 1))
  done
  
  if [[ -n "$stack" ]]; then
    log_error "Stack trace: $stack"
  fi
  
  # Run cleanup function if provided
  if [[ -n "$cleanup_func" && $(type -t "$cleanup_func") == "function" ]]; then
    log_info "Running cleanup function: $cleanup_func"
    $cleanup_func
  fi
  
  # Exit with provided code
  log_error "Exiting with code $exit_code"
  exit $exit_code
}

# Export common functions
export -f retry_command
export -f handle_critical_error
export -f check_command
export -f check_file
export -f check_directory
export -f validate_env
export -f escape_sql
export -f escape_shell
export -f check_error_handler
export -f run_with_timeout
export -f begin_transaction
export -f end_transaction
export -f fail_transaction
export -f check_system_resources
export -f handle_network_request
export -f test_service_connection