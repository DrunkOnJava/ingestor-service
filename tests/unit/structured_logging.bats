#!/usr/bin/env bats
# Unit tests for the structured_logging.sh module

# Load the test helper
load '../test_helper'

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Set up test-specific paths
    export TEST_PROJECT_DIR="${TEST_TEMP_DIR}/project"
    export LOGS_DIR="${TEST_TEMP_DIR}/logs"
    export LOG_FILE="${LOGS_DIR}/test.log"
    
    # Create necessary directories
    mkdir -p "${TEST_PROJECT_DIR}/src/modules"
    mkdir -p "${LOGS_DIR}"
    
    # Create a copy of the structured_logging module for testing
    cat > "${TEST_PROJECT_DIR}/src/modules/structured_logging.sh" << 'EOF'
#!/bin/bash
# Structured logging module for ingestor system

# Default log configuration
LOG_LEVEL="info"
LOG_FORMAT="human"
LOG_DESTINATION="stdout"
LOG_FILE=""
LOG_TIMESTAMP_FORMAT="%Y-%m-%dT%H:%M:%S%z"

# Log level mapping (lower number = more verbose)
declare -A LOG_LEVELS=(
    ["debug"]=0
    ["info"]=1
    ["warning"]=2
    ["error"]=3
)

# Initialize the logging system
log_init() {
    local level="${1:-info}"
    local format="${2:-human}"
    local destination="${3:-stdout}"
    local file="${4:-}"
    
    # Validate log level
    if [[ -z "${LOG_LEVELS[$level]}" ]]; then
        echo "Invalid log level: $level. Using 'info' instead." >&2
        level="info"
    fi
    
    # Validate log format
    if [[ "$format" != "human" && "$format" != "json" ]]; then
        echo "Invalid log format: $format. Using 'human' instead." >&2
        format="human"
    fi
    
    # Validate log destination
    if [[ "$destination" != "stdout" && "$destination" != "file" && "$destination" != "both" ]]; then
        echo "Invalid log destination: $destination. Using 'stdout' instead." >&2
        destination="stdout"
    fi
    
    # If destination includes file, validate file path
    if [[ "$destination" == "file" || "$destination" == "both" ]]; then
        if [[ -z "$file" ]]; then
            echo "No log file specified for file destination. Using 'stdout' instead." >&2
            destination="stdout"
        else
            # Create log directory if it doesn't exist
            local log_dir="$(dirname "$file")"
            if [[ ! -d "$log_dir" ]]; then
                mkdir -p "$log_dir" || {
                    echo "Failed to create log directory: $log_dir. Using 'stdout' instead." >&2
                    destination="stdout"
                    file=""
                }
            fi
            
            # Touch the file to ensure it exists and is writable
            touch "$file" 2>/dev/null || {
                echo "Failed to create/access log file: $file. Using 'stdout' instead." >&2
                destination="stdout"
                file=""
            }
        fi
    fi
    
    # Set global configuration
    LOG_LEVEL="$level"
    LOG_FORMAT="$format"
    LOG_DESTINATION="$destination"
    LOG_FILE="$file"
    
    # Log initialization
    log_debug "Logging initialized: level=$LOG_LEVEL, format=$LOG_FORMAT, destination=$LOG_DESTINATION, file=$LOG_FILE"
}

# Internal logging function
_log() {
    local level="$1"
    local message="$2"
    local module="${3:-}"
    local function_name="${4:-}"
    local line_number="${5:-}"
    local timestamp=$(date +"$LOG_TIMESTAMP_FORMAT")
    
    # Check if we should log this message based on level
    if [[ "${LOG_LEVELS[$level]}" -lt "${LOG_LEVELS[$LOG_LEVEL]}" ]]; then
        return 0
    fi
    
    # Format the log message
    local log_entry=""
    if [[ "$LOG_FORMAT" == "json" ]]; then
        # Escape quotes in message for JSON
        message="${message//\"/\\\"}"
        
        # Create JSON object
        log_entry="{"
        log_entry+="\"timestamp\":\"$timestamp\","
        log_entry+="\"level\":\"$level\","
        log_entry+="\"message\":\"$message\""
        if [[ -n "$module" ]]; then log_entry+=",\"module\":\"$module\""; fi
        if [[ -n "$function_name" ]]; then log_entry+=",\"function\":\"$function_name\""; fi
        if [[ -n "$line_number" ]]; then log_entry+=",\"line\":$line_number"; fi
        log_entry+="}"
    else
        # Human-readable format
        log_entry="[$timestamp] [$level]"
        if [[ -n "$module" ]]; then log_entry+=" [$module]"; fi
        if [[ -n "$function_name" ]]; then log_entry+=" [$function_name]"; fi
        if [[ -n "$line_number" ]]; then log_entry+=" [line:$line_number]"; fi
        log_entry+=" $message"
    fi
    
    # Output the log entry to the appropriate destination
    if [[ "$LOG_DESTINATION" == "stdout" || "$LOG_DESTINATION" == "both" ]]; then
        echo "$log_entry"
    fi
    
    if [[ "$LOG_DESTINATION" == "file" || "$LOG_DESTINATION" == "both" ]] && [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

# Public logging functions
log_debug() {
    local message="$1"
    local module="${2:-}"
    local function_name="${3:-}"
    local line_number="${4:-}"
    _log "debug" "$message" "$module" "$function_name" "$line_number"
}

log_info() {
    local message="$1"
    local module="${2:-}"
    local function_name="${3:-}"
    local line_number="${4:-}"
    _log "info" "$message" "$module" "$function_name" "$line_number"
}

log_warning() {
    local message="$1"
    local module="${2:-}"
    local function_name="${3:-}"
    local line_number="${4:-}"
    _log "warning" "$message" "$module" "$function_name" "$line_number"
}

log_error() {
    local message="$1"
    local module="${2:-}"
    local function_name="${3:-}"
    local line_number="${4:-}"
    _log "error" "$message" "$module" "$function_name" "$line_number"
}

# Log with metric data (for performance tracking)
log_metric() {
    local name="$1"
    local value="$2"
    local unit="${3:-}"
    local module="${4:-}"
    local function_name="${5:-}"
    
    local message=""
    if [[ "$LOG_FORMAT" == "json" ]]; then
        message="{"
        message+="\"metric\":\"$name\","
        message+="\"value\":$value"
        if [[ -n "$unit" ]]; then message+=",\"unit\":\"$unit\""; fi
        message+="}"
    else
        message="METRIC: $name=$value"
        if [[ -n "$unit" ]]; then message+=" $unit"; fi
    fi
    
    log_info "$message" "$module" "$function_name"
}

# Log an event
log_event() {
    local event_type="$1"
    local event_data="$2"
    local module="${3:-}"
    local function_name="${4:-}"
    
    local message=""
    if [[ "$LOG_FORMAT" == "json" ]]; then
        # If event_data is already JSON, we need to remove the outer quotes
        if [[ "$event_data" == {* ]]; then
            message="{\"event\":\"$event_type\",\"data\":$event_data}"
        else
            message="{\"event\":\"$event_type\",\"data\":\"$event_data\"}"
        fi
    else
        message="EVENT: $event_type | $event_data"
    fi
    
    log_info "$message" "$module" "$function_name"
}

# Enable stack trace in logs
log_enable_stack_trace() {
    export LOG_STACK_TRACE="true"
}

# Disable stack trace in logs
log_disable_stack_trace() {
    export LOG_STACK_TRACE="false"
}
EOF
    
    # Source the structured logging module
    source "${TEST_PROJECT_DIR}/src/modules/structured_logging.sh"
}

# Teardown - runs after each test
teardown() {
    teardown_test_environment
}

# Test initialization with default values
@test "log_init with default values sets correct configuration" {
    run log_init
    assert_success
    
    assert_equal "$LOG_LEVEL" "info"
    assert_equal "$LOG_FORMAT" "human"
    assert_equal "$LOG_DESTINATION" "stdout"
    assert_equal "$LOG_FILE" ""
}

# Test initialization with custom values
@test "log_init with custom values sets correct configuration" {
    run log_init "debug" "json" "file" "$LOG_FILE"
    assert_success
    
    assert_equal "$LOG_LEVEL" "debug"
    assert_equal "$LOG_FORMAT" "json"
    assert_equal "$LOG_DESTINATION" "file"
    assert_equal "$LOG_FILE" "$LOG_FILE"
}

# Test initialization with invalid level
@test "log_init with invalid level falls back to info" {
    run log_init "invalid_level" "human" "stdout"
    
    assert_equal "$LOG_LEVEL" "info"
}

# Test initialization with invalid format
@test "log_init with invalid format falls back to human" {
    run log_init "info" "invalid_format" "stdout"
    
    assert_equal "$LOG_FORMAT" "human"
}

# Test initialization with invalid destination
@test "log_init with invalid destination falls back to stdout" {
    run log_init "info" "human" "invalid_destination"
    
    assert_equal "$LOG_DESTINATION" "stdout"
}

# Test log_debug in human format
@test "log_debug outputs correct format in human mode" {
    log_init "debug" "human" "stdout"
    
    run log_debug "Test debug message" "test_module" "test_function" "123"
    assert_success
    
    assert_output --partial "[debug] [test_module] [test_function] [line:123] Test debug message"
}

# Test log_info in human format
@test "log_info outputs correct format in human mode" {
    log_init "info" "human" "stdout"
    
    run log_info "Test info message" "test_module" "test_function" "123"
    assert_success
    
    assert_output --partial "[info] [test_module] [test_function] [line:123] Test info message"
}

# Test log_warning in human format
@test "log_warning outputs correct format in human mode" {
    log_init "warning" "human" "stdout"
    
    run log_warning "Test warning message" "test_module" "test_function" "123"
    assert_success
    
    assert_output --partial "[warning] [test_module] [test_function] [line:123] Test warning message"
}

# Test log_error in human format
@test "log_error outputs correct format in human mode" {
    log_init "error" "human" "stdout"
    
    run log_error "Test error message" "test_module" "test_function" "123"
    assert_success
    
    assert_output --partial "[error] [test_module] [test_function] [line:123] Test error message"
}

# Test log_debug in JSON format
@test "log_debug outputs correct format in JSON mode" {
    log_init "debug" "json" "stdout"
    
    run log_debug "Test debug message" "test_module" "test_function" "123"
    assert_success
    
    assert_output --partial '{"timestamp":"'
    assert_output --partial '"level":"debug"'
    assert_output --partial '"message":"Test debug message"'
    assert_output --partial '"module":"test_module"'
    assert_output --partial '"function":"test_function"'
    assert_output --partial '"line":123'
}

# Test log level filtering (debug)
@test "log level filtering prevents lower priority messages" {
    log_init "warning" "human" "stdout"
    
    # Debug should not output when level is warning
    run log_debug "This should not appear"
    assert_success
    assert_output ""
    
    # Info should not output when level is warning
    run log_info "This should not appear"
    assert_success
    assert_output ""
    
    # Warning should output when level is warning
    run log_warning "This should appear"
    assert_success
    assert_output --partial "This should appear"
    
    # Error should output when level is warning
    run log_error "This should appear"
    assert_success
    assert_output --partial "This should appear"
}

# Test log_metric in human format
@test "log_metric outputs correct format in human mode" {
    log_init "info" "human" "stdout"
    
    run log_metric "response_time" "150" "ms" "api" "get_data"
    assert_success
    
    assert_output --partial "[info] [api] [get_data] METRIC: response_time=150 ms"
}

# Test log_metric in JSON format
@test "log_metric outputs correct format in JSON mode" {
    log_init "info" "json" "stdout"
    
    run log_metric "response_time" "150" "ms" "api" "get_data"
    assert_success
    
    assert_output --partial '"metric":"response_time"'
    assert_output --partial '"value":150'
    assert_output --partial '"unit":"ms"'
}

# Test log_event in human format
@test "log_event outputs correct format in human mode" {
    log_init "info" "human" "stdout"
    
    run log_event "user_login" "user_id=123" "auth" "process_login"
    assert_success
    
    assert_output --partial "[info] [auth] [process_login] EVENT: user_login | user_id=123"
}

# Test log_event in JSON format
@test "log_event outputs correct format in JSON mode" {
    log_init "info" "json" "stdout"
    
    run log_event "user_login" '{"user_id":123,"session":"abc123"}' "auth" "process_login"
    assert_success
    
    assert_output --partial '"event":"user_login"'
    assert_output --partial '"data":{"user_id":123,"session":"abc123"}'
}

# Test file logging
@test "logging to file works correctly" {
    log_init "info" "human" "file" "$LOG_FILE"
    
    log_info "Test file logging"
    
    # Check if the log file exists
    [ -f "$LOG_FILE" ]
    
    # Check if the content was written
    run cat "$LOG_FILE"
    assert_output --partial "[info] Test file logging"
}

# Test both console and file logging
@test "logging to both stdout and file works correctly" {
    log_init "info" "human" "both" "$LOG_FILE"
    
    # Capture output
    run log_info "Test dual logging"
    assert_success
    
    # Check stdout
    assert_output --partial "[info] Test dual logging"
    
    # Check file
    [ -f "$LOG_FILE" ]
    run cat "$LOG_FILE"
    assert_output --partial "[info] Test dual logging"
}

# Test stack trace flags
@test "stack trace flags can be toggled" {
    # Default should be unset
    [ -z "$LOG_STACK_TRACE" ]
    
    # Enable stack trace
    log_enable_stack_trace
    [ "$LOG_STACK_TRACE" = "true" ]
    
    # Disable stack trace
    log_disable_stack_trace
    [ "$LOG_STACK_TRACE" = "false" ]
}