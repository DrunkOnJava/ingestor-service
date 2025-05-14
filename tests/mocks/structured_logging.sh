#!/bin/bash
# Mock structured logging module for tests

# Re-export log levels from mock logging
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

# Set default log level if not already set
LOG_LEVEL="${LOG_LEVEL:-info}"

# Initialize structured logging (mock)
init_structured_logging() {
    echo "Mock structured logging initialized" >&2
}

# Extended log functions (mocks)
log_structured_debug() {
    local message="$1"
    local module="$2"
    local function_name="$3"
    echo "DEBUG [$module:$function_name]: $message" >&2
}

log_structured_info() {
    local message="$1"
    local module="$2"
    local function_name="$3"
    echo "INFO [$module:$function_name]: $message" >&2
}

log_structured_warning() {
    local message="$1"
    local module="$2"
    local function_name="$3"
    echo "WARNING [$module:$function_name]: $message" >&2
}

log_structured_error() {
    local message="$1"
    local module="$2"
    local function_name="$3"
    echo "ERROR [$module:$function_name]: $message" >&2
}

# Mock functions for compatibility
log_metric() {
    echo "METRIC: $1=$2$3" >&2
}

log_event() {
    echo "EVENT: $1 ($2)" >&2
}

log_structured_exception() {
    echo "EXCEPTION: $1 (code: ${2:-1})" >&2
}

configure_logging() {
    echo "MOCK: Logging configured with $1, $2, $3" >&2
}

# Export log levels
export LOG_LEVELS