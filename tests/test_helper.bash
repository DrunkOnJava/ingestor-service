#!/usr/bin/env bash
# Test helper functions for BATS tests

# Determine the project root directory
if [[ -z "${PROJECT_ROOT}" ]]; then
    PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    export PROJECT_ROOT
fi

# Ensure TEST_TEMP_DIR is always defined and created
setup_test_temp_dir() {
    TEST_TEMP_DIR=$(mktemp -d -t "ingestor-test-XXXXXX")
    
    if [[ ! -d "${TEST_TEMP_DIR}" ]]; then
        echo "Error: Failed to create temporary directory" >&2
        return 1
    fi
    
    export TEST_TEMP_DIR
}

# Setup test environment
setup_test_environment() {
    # Create a temporary directory for this test
    setup_test_temp_dir
    
    # Load the logging module with mocked functions to prevent actual logging
    function log_debug() { echo "[DEBUG] $*" >/dev/null; }
    function log_info() { echo "[INFO] $*" >/dev/null; }
    function log_warning() { echo "[WARNING] $*" >/dev/null; }
    function log_error() { echo "[ERROR] $*" >/dev/null; }
    
    export -f log_debug log_info log_warning log_error
    
    # Set up test-specific environment variables
    export USER="test_user"
    export TEST_MODE=true
    
    # Create temp directory for test artifacts
    TEST_TEMP_DIR=$(mktemp -d -t "ingestor-test-XXXXXX")
    export TEST_TEMP_DIR
}

# Teardown test environment
teardown_test_environment() {
    # Clean up temp directory if it exists
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    
    # Unset test-specific environment variables
    unset USER
    unset TEST_MODE
    unset TEST_TEMP_DIR
    
    # Unset function exports if they exist
    if type -t log_debug >/dev/null 2>&1; then
        unset -f log_debug
    fi
    if type -t log_info >/dev/null 2>&1; then
        unset -f log_info
    fi
    if type -t log_warning >/dev/null 2>&1; then
        unset -f log_warning
    fi
    if type -t log_error >/dev/null 2>&1; then
        unset -f log_error
    fi
}

# Source a module with proper environment
source_module() {
    local module_path="$1"
    
    # Check if file exists
    if [[ ! -f "$module_path" ]]; then
        echo "Error: Module not found: $module_path" >&2
        return 1
    fi
    
    # Source the module
    source "$module_path"
}

# Create a mock function that can be used to override real functions
# Usage: mock_function "function_name" "return_value" [output]
mock_function() {
    local function_name="$1"
    local return_value="${2:-0}"
    local output="${3:-}"
    
    eval "function $function_name() { 
        echo \"$output\"
        return $return_value
    }"
    export -f "$function_name"
}

# Create a mock command that can be used to override real commands
# Usage: mock_command "command_name" "return_value" [output]
mock_command() {
    local command_name="$1"
    local return_value="${2:-0}"
    local output="${3:-}"
    
    eval "function $command_name() { 
        echo \"$output\"
        return $return_value
    }"
    export -f "$command_name"
}

# Mock a file by creating it in the test temp directory
# Usage: mock_file "file_path" "content"
mock_file() {
    local file_path="$1"
    local content="${2:-}"
    local temp_file="${TEST_TEMP_DIR}/$(basename "$file_path")"
    
    mkdir -p "$(dirname "$temp_file")"
    echo "$content" > "$temp_file"
    
    echo "$temp_file"
}

# Load BATS assertion functions
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
load "${DIR}/assertions"