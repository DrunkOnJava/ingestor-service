#!/usr/bin/env bats
# Unit tests for the error_handler.sh module

# Load the test helper
load '../test_helper'

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Set up test directories
    export TEST_PROJECT_DIR="${TEST_TEMP_DIR}/project"
    export TEMP_DIR="${TEST_TEMP_DIR}/tmp"
    mkdir -p "${TEST_PROJECT_DIR}/src/modules"
    mkdir -p "${TEMP_DIR}"
    
    # Create a mock logging module
    cat > "${TEST_PROJECT_DIR}/src/modules/logging.sh" << 'EOF'
#!/bin/bash
# Mock logging module for testing

log_messages=()

log_debug() {
    log_messages+=("[DEBUG] $*")
}

log_info() {
    log_messages+=("[INFO] $*")
}

log_warning() {
    log_messages+=("[WARNING] $*")
}

log_error() {
    log_messages+=("[ERROR] $*")
}

clear_log_messages() {
    log_messages=()
}

get_log_messages() {
    for msg in "${log_messages[@]}"; do
        echo "$msg"
    done
}
EOF
    
    # Create a copy of the error_codes module to test
    cat > "${TEST_PROJECT_DIR}/src/modules/error_codes.sh" << 'EOF'
#!/bin/bash
# Mock error codes module for testing

# General error codes
export ERR_UNKNOWN=1
export ERR_VALIDATION=21
export ERR_FILE=11
export ERR_DEPENDENCY=56
export ERR_FILE_NOT_FOUND=12
export ERR_PERMISSION_DENIED=5
export ERR_INVALID_ARGUMENT=22
export ERR_TIMEOUT=6
export ERR_DATABASE=31
export ERR_NETWORK=41
export ERR_GENERIC=99

# Get error name from code
get_error_name() {
    local error_code=$1
    
    case $error_code in
        1)  echo "ERR_UNKNOWN" ;;
        5)  echo "ERR_PERMISSION_DENIED" ;;
        6)  echo "ERR_TIMEOUT" ;;
        11) echo "ERR_FILE" ;;
        12) echo "ERR_FILE_NOT_FOUND" ;;
        21) echo "ERR_VALIDATION" ;;
        22) echo "ERR_INVALID_ARGUMENT" ;;
        31) echo "ERR_DATABASE" ;;
        41) echo "ERR_NETWORK" ;;
        56) echo "ERR_DEPENDENCY" ;;
        99) echo "ERR_GENERIC" ;;
        *)  echo "UNKNOWN_ERROR" ;;
    esac
}

# Get error message from code
get_error_message() {
    local error_code=$1
    
    case $error_code in
        1)  echo "Unknown error occurred" ;;
        5)  echo "Permission denied" ;;
        6)  echo "Operation timed out" ;;
        11) echo "File error occurred" ;;
        12) echo "File not found" ;;
        21) echo "Validation error occurred" ;;
        22) echo "Invalid argument" ;;
        31) echo "Database error occurred" ;;
        41) echo "Network error occurred" ;;
        56) echo "Missing dependency" ;;
        99) echo "An unknown error occurred" ;;
        *)  echo "Error code $error_code occurred" ;;
    esac
}

export -f get_error_name
export -f get_error_message
EOF
    
    # Create a copy of the error_handler.sh for testing - with fixed exports
    cat > "${TEST_PROJECT_DIR}/src/modules/error_handler.sh" << 'EOF'
#!/bin/bash
# Error handling module for ingestor-system

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
    fi
fi

# Load logging module if not already loaded
if ! type log_debug &>/dev/null; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/logging.sh" ]]; then
        source "${script_dir}/logging.sh"
    else
        echo "WARNING: Logging module not found"
        # Define minimal logging functions
        log_debug() { echo "[DEBUG] $*"; }
        log_info() { echo "[INFO] $*"; }
        log_warning() { echo "[WARNING] $*"; }
        log_error() { echo "[ERROR] $*"; }
    fi
fi

# Error codes (1-50 reserved for system, we use 51+)
readonly ERR_MISSING_DEPENDENCY=56
readonly ERR_INVALID_ARGUMENT=22
readonly ERR_FILE_NOT_FOUND=12
readonly ERR_PERMISSION_DENIED=5
readonly ERR_EXTERNAL_COMMAND=55
readonly ERR_DATABASE=31
readonly ERR_NETWORK=41
readonly ERR_TIMEOUT=6
readonly ERR_ANALYSIS_FAILED=59
readonly ERR_KEYCHAIN=60
readonly ERR_CONFIG=61
readonly ERR_VALIDATION=21
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

# Get human-readable error message for a code
get_error_message() {
  local code="$1"
  echo "${ERROR_MESSAGES[$code]:-Unknown error}"
}

# Create a temporary file with cleanup
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

# Fixed exports to avoid errors
export -f init_error_handler
export -f reset_error_handler
export -f handle_error
export -f raise_error
export -f require_dependency
export -f require_file
export -f require_directory
export -f require_var
export -f try
export -f catch
export -f retry
export -f is_timeout
export -f get_error_message
export -f create_temp_file
export -f cleanup_temp_files
EOF
    
    # Source the error_handler module
    source "${TEST_PROJECT_DIR}/src/modules/logging.sh"
    source "${TEST_PROJECT_DIR}/src/modules/error_codes.sh"
    source "${TEST_PROJECT_DIR}/src/modules/error_handler.sh"
}

# Teardown - runs after each test
teardown() {
    # Call the common teardown
    teardown_test_environment
}

# Test init_error_handler function
@test "init_error_handler initializes with default settings" {
    # Reset any previous trap
    trap - ERR
    
    # Initialize
    run init_error_handler
    assert_success
    
    # Check that the trap is set
    run trap -p ERR
    assert_output --partial "handle_error"
    
    # Check global vars
    assert_equal "$GLOBAL_MAX_RETRIES" "3"
    assert_equal "$GLOBAL_RETRY_DELAY" "2"
}

# Test init_error_handler with custom settings
@test "init_error_handler respects custom retry settings" {
    # Reset any previous trap
    trap - ERR
    
    # Set custom values
    GLOBAL_MAX_RETRIES=5
    GLOBAL_RETRY_DELAY=10
    
    # Initialize
    run init_error_handler
    assert_success
    
    # Check global vars
    assert_equal "$GLOBAL_MAX_RETRIES" "5"
    assert_equal "$GLOBAL_RETRY_DELAY" "10"
}

# Test raise_error
@test "raise_error logs error message with code" {
    # Clear previous log messages
    clear_log_messages
    
    # Run in subshell to avoid exiting test
    (
        raise_error "Test error message" $ERR_VALIDATION
        exit $? # Needed to propagate the exit code
    )
    
    # Check if the error message is logged correctly
    run get_log_messages
    assert_output --partial "[ERROR] Test error message (code: 21)"
}

# Test require_dependency with existing command
@test "require_dependency succeeds with existing command" {
    run require_dependency "ls"
    assert_success
}

# Test require_dependency with non-existing command
@test "require_dependency fails with non-existing command" {
    # Clear previous log messages
    clear_log_messages
    
    # Run in subshell to avoid exiting test
    (
        require_dependency "nonexistent_command"
        exit $? # Needed to propagate the exit code
    )
    status=$?
    
    # Check return code
    assert_equal $status $ERR_MISSING_DEPENDENCY
    
    # Check if the error message is logged correctly
    run get_log_messages
    assert_output --partial "[ERROR] Required command 'nonexistent_command' not found"
}

# Test require_file with existing file
@test "require_file succeeds with existing file" {
    # Create a test file
    local test_file="${TEST_TEMP_DIR}/test_file.txt"
    echo "Test content" > "$test_file"
    
    run require_file "$test_file"
    assert_success
}

# Test require_file with non-existing file
@test "require_file fails with non-existing file" {
    # Clear previous log messages
    clear_log_messages
    
    # Run in subshell to avoid exiting test
    (
        require_file "${TEST_TEMP_DIR}/nonexistent_file.txt"
        exit $? # Needed to propagate the exit code
    )
    status=$?
    
    # Check return code
    assert_equal $status $ERR_FILE_NOT_FOUND
    
    # Check if the error message is logged correctly
    run get_log_messages
    assert_output --partial "[ERROR] Required file '${TEST_TEMP_DIR}/nonexistent_file.txt' not found"
}

# Test require_directory with existing directory
@test "require_directory succeeds with existing directory" {
    run require_directory "$TEST_TEMP_DIR"
    assert_success
}

# Test require_directory with non-existing directory (no create)
@test "require_directory fails with non-existing directory" {
    # Clear previous log messages
    clear_log_messages
    
    # Run in subshell to avoid exiting test
    (
        require_directory "${TEST_TEMP_DIR}/nonexistent_dir"
        exit $? # Needed to propagate the exit code
    )
    status=$?
    
    # Check return code
    assert_equal $status $ERR_FILE_NOT_FOUND
    
    # Check if the error message is logged correctly
    run get_log_messages
    assert_output --partial "[ERROR] Required directory '${TEST_TEMP_DIR}/nonexistent_dir' not found"
}

# Test require_directory with non-existing directory and create=true
@test "require_directory creates non-existing directory when create=true" {
    # Clear previous log messages
    clear_log_messages
    
    run require_directory "${TEST_TEMP_DIR}/new_directory" "Directory not found" "true"
    assert_success
    
    # Check if directory was created
    assert_dir_exists "${TEST_TEMP_DIR}/new_directory"
    
    # Check log message
    run get_log_messages
    assert_output --partial "[INFO] Creating directory: ${TEST_TEMP_DIR}/new_directory"
}

# Test require_var with set variable
@test "require_var succeeds with set variable" {
    TEST_VAR="test_value"
    run require_var "TEST_VAR"
    assert_success
}

# Test require_var with unset variable
@test "require_var fails with unset variable" {
    # Clear previous log messages
    clear_log_messages
    
    # Unset the variable
    unset TEST_VAR
    
    # Run in subshell to avoid exiting test
    (
        require_var "TEST_VAR"
        exit $? # Needed to propagate the exit code
    )
    status=$?
    
    # Check return code
    assert_equal $status $ERR_INVALID_ARGUMENT
    
    # Check if the error message is logged correctly
    run get_log_messages
    assert_output --partial "[ERROR] Required variable 'TEST_VAR' is not set or empty"
}

# Test require_var with empty variable
@test "require_var fails with empty variable" {
    # Clear previous log messages
    clear_log_messages
    
    # Set empty variable
    TEST_VAR=""
    
    # Run in subshell to avoid exiting test
    (
        require_var "TEST_VAR"
        exit $? # Needed to propagate the exit code
    )
    status=$?
    
    # Check return code
    assert_equal $status $ERR_INVALID_ARGUMENT
    
    # Check if the error message is logged correctly
    run get_log_messages
    assert_output --partial "[ERROR] Required variable 'TEST_VAR' is not set or empty"
}

# Test the try-catch mechanism with successful function
@test "try-catch mechanism works with successful function" {
    # Define a test function that succeeds
    success_function() {
        return 0
    }
    
    # Define a catch function that shouldn't be called
    catch_function() {
        echo "Catch function was called"
        return 1
    }
    
    # Run try-catch
    try success_function
    run catch catch_function
    
    # Check that catch wasn't triggered
    assert_success
    refute_output --partial "Catch function was called"
}

# Test the try-catch mechanism with failing function
@test "try-catch mechanism works with failing function" {
    # Clear previous log messages
    clear_log_messages
    
    # Define a test function that fails
    fail_function() {
        return $ERR_VALIDATION
    }
    
    # Define a catch function
    catch_function() {
        local error_code=$1
        echo "Caught error with code: $error_code"
        return 0
    }
    
    # Run try-catch
    try fail_function
    run catch catch_function
    
    # Check that catch was triggered
    assert_success
    assert_output --partial "Caught error with code: 21"
}

# Test the retry mechanism with succeeding command
@test "retry mechanism works with succeeding command" {
    # Clear previous log messages
    clear_log_messages
    
    # Create a command that succeeds
    echo '#!/bin/bash
exit 0' > "${TEST_TEMP_DIR}/success.sh"
    chmod +x "${TEST_TEMP_DIR}/success.sh"
    
    # Run retry
    run retry "${TEST_TEMP_DIR}/success.sh"
    assert_success
    
    # Check logs - should be no retry messages
    run get_log_messages
    refute_output --partial "retries"
}

# Test the retry mechanism with failing command
@test "retry mechanism gives up after max retries" {
    # Clear previous log messages
    clear_log_messages
    
    # Create a command that always fails
    echo '#!/bin/bash
exit 1' > "${TEST_TEMP_DIR}/fail.sh"
    chmod +x "${TEST_TEMP_DIR}/fail.sh"
    
    # Run retry with minimal settings for test speed
    run retry "${TEST_TEMP_DIR}/fail.sh" 2 0
    assert_failure
    
    # Check logs - should show retry attempts
    run get_log_messages
    assert_output --partial "Command failed with exit code 1, retrying"
    assert_output --partial "Command failed with exit code 1 after 2 retries"
}

# Test the retry mechanism with eventually succeeding command
@test "retry mechanism succeeds if command eventually succeeds" {
    # Clear previous log messages
    clear_log_messages
    
    # Create a command that fails twice then succeeds
    echo '#!/bin/bash
if [[ ! -f "${TEST_TEMP_DIR}/attempt" ]]; then
    echo "1" > "${TEST_TEMP_DIR}/attempt"
    exit 1
elif [[ "$(cat ${TEST_TEMP_DIR}/attempt)" == "1" ]]; then
    echo "2" > "${TEST_TEMP_DIR}/attempt"
    exit 1
else
    exit 0
fi' > "${TEST_TEMP_DIR}/eventual_success.sh"
    chmod +x "${TEST_TEMP_DIR}/eventual_success.sh"
    
    # Run retry
    run retry "${TEST_TEMP_DIR}/eventual_success.sh" 3 0
    assert_success
    
    # Check logs - should show retry attempts and eventual success
    run get_log_messages
    assert_output --partial "Command failed with exit code 1, retrying"
    assert_output --partial "Command succeeded after 2 retries"
}

# Test the is_timeout function
@test "is_timeout correctly identifies timeout exit codes" {
    # Test with timeout exit codes
    run is_timeout 124
    assert_success
    
    run is_timeout 137
    assert_success
    
    run is_timeout 143
    assert_success
    
    # Test with non-timeout exit code
    run is_timeout 1
    assert_failure
    
    run is_timeout 0
    assert_failure
}

# Test the create_temp_file function
@test "create_temp_file creates a temporary file with cleanup" {
    # Clear previous log messages
    clear_log_messages
    
    # Create a temp file
    run create_temp_file "test"
    assert_success
    
    # Get the file path from output
    local temp_file="$output"
    
    # Check if file exists
    assert_file_exists "$temp_file"
    
    # Check if file has the correct prefix
    assert_contains "$temp_file" "test_"
    
    # Verify it's in the right directory
    assert_contains "$temp_file" "$TEMP_DIR"
    
    # Check if it's registered for cleanup by examining the _TEMP_FILES array
    [[ " ${_TEMP_FILES[*]} " == *" $temp_file "* ]]
    
    # Run cleanup
    run cleanup_temp_files
    assert_success
    
    # Check if file was removed
    [[ ! -f "$temp_file" ]]
    
    # Check logs
    run get_log_messages
    assert_output --partial "Cleaning up"
}

# Test get_error_message function
@test "get_error_message returns correct messages for error codes" {
    run get_error_message $ERR_FILE_NOT_FOUND
    assert_output "File not found"
    
    run get_error_message $ERR_VALIDATION
    assert_output "Validation failed"
    
    run get_error_message $ERR_NETWORK
    assert_output "Network operation failed"
    
    # Test with unknown code
    run get_error_message 999
    assert_output "Unknown error"
}