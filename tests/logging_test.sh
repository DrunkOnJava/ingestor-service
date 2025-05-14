#!/bin/bash
# Test script for structured logging

# Load modules
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../src/modules/structured_logging.sh"

# Test function that will generate logs
test_logging() {
    # Initialize with defaults
    init_structured_logging
    
    echo "Testing default logging (human-readable format):"
    log_structured_debug "This is a debug message"
    log_structured_info "This is an info message"
    log_structured_warning "This is a warning message"
    log_structured_error "This is an error message"
    
    echo ""
    echo "Testing JSON logging:"
    configure_logging "json" "both" "true"
    
    log_structured_debug "This is a debug message in JSON format"
    log_structured_info "This is an info message in JSON format"
    
    # Log with additional fields
    log_structured_info "User action performed" "$(build_log_fields "user" "\"test_user\"" "action" "\"login\"" "status" "\"success\"")"
    
    # Log a metric
    log_metric "request_time" "150" "ms"
    
    # Log an event
    log_event "user_login" "info" "{\"user\":\"test_user\",\"method\":\"password\"}"
    
    # Test error with stack trace
    nested_function_with_error
}

# Function to test stack traces
nested_function_with_error() {
    another_level_of_nesting
}

another_level_of_nesting() {
    log_structured_exception "Something went wrong" "42" "TestError"
}

# Run the test
test_logging

# Print log file path
echo ""
echo "Log file written to: $STRUCTURED_LOG_FILE"
echo "You can examine it with: cat $STRUCTURED_LOG_FILE"

# Print a sample of the log file
echo ""
echo "Sample JSON logs from file:"
if [ -f "$STRUCTURED_LOG_FILE" ]; then
    grep "json format" "$STRUCTURED_LOG_FILE" | head -2
fi