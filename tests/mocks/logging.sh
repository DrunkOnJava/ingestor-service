#!/bin/bash
# Mock logging module for tests

# Log levels
declare -A LOG_LEVELS=( ["debug"]=0 ["info"]=1 ["warning"]=2 ["error"]=3 )

# Set default log level if not already set
LOG_LEVEL="${LOG_LEVEL:-info}"

# Log debug message
log_debug() {
    echo "DEBUG: $1" >&2
}

# Log info message
log_info() {
    echo "INFO: $1" >&2
}

# Log warning message
log_warning() {
    echo "WARNING: $1" >&2
}

# Log error message
log_error() {
    echo "ERROR: $1" >&2
}

# No-op functions for compatibility
init_logging() {
    echo "Mock logging initialized" >&2
}

log_exception() {
    echo "EXCEPTION: $1 (code: ${2:-1})" >&2
}