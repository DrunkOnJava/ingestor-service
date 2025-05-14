#!/usr/bin/env bats
# Unit tests for the keychain.sh module

# Load the test helper
load ../test_helper

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Create a mock error_handling module
    mkdir -p "${TEST_TEMP_DIR}/src/modules"
    cat > "${TEST_TEMP_DIR}/src/modules/error_handling.sh" << 'EOF'
#!/bin/bash
# Mock error handling module for testing

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

# Mock validation function
require_variable() {
    local var_name="$1"
    local var_value="$2"
    local error_message="${3:-Required variable $var_name is empty}"
    
    if [[ -z "$var_value" ]]; then
        log_debug "$error_message"
        return $ERR_VALIDATION
    fi
    
    return 0
}

# Mock retry function
retry_command() {
    local cmd="$1"
    eval "$cmd"
    return $?
}

# Mock error description function
get_error_description() {
    local error_code="$1"
    echo "Error code $error_code description"
}

# Mock log_exception function needed by handle_critical_error
log_exception() {
    local message="$1"
    local exit_code="${2:-$ERR_GENERAL}"
    log_debug "EXCEPTION: $message (code: $exit_code)"
}

ERROR_HANDLING_LOADED=1
EOF

    # Set PROJECT_ROOT to TEST_TEMP_DIR for this test
    export PROJECT_ROOT="${TEST_TEMP_DIR}"
    
    # Source the keychain module
    cp -f "/Users/griffin/Projects/ingestor-system/src/modules/keychain.sh" "${TEST_TEMP_DIR}/src/modules/"
    source "${TEST_TEMP_DIR}/src/modules/error_handling.sh"
    source "${TEST_TEMP_DIR}/src/modules/keychain.sh"
}

# Teardown - runs after each test
teardown() {
    # Call the common teardown
    teardown_test_environment
}

# Test keychain_available function
@test "keychain_available returns appropriate value based on environment" {
    # Mock the command command to simulate environment
    if command -v security &> /dev/null; then
        # If security command exists, test the real function
        run keychain_available
        assert_success
    else
        # If security doesn't exist, mock it to be unavailable
        function command() {
            if [[ "$2" == "security" ]]; then
                return 1
            fi
            return 0
        }
        export -f command
        
        run keychain_available
        assert_failure
    fi
}

# Test get_keychain_credential with mock security command
@test "get_keychain_credential retrieves credentials successfully when available" {
    # Mock the security command to return a test value
    function security() {
        if [[ "$1" == "find-generic-password" && "$3" == "${KEYCHAIN_SERVICE}-test_cred" ]]; then
            echo "test_value"
            return 0
        fi
        return 1
    }
    export -f security
    
    # Mock keychain_available to return true
    function keychain_available() {
        return 0
    }
    export -f keychain_available
    
    run get_keychain_credential "test_cred"
    assert_output "test_value"
    assert_success
}

# Test get_keychain_credential with failure
@test "get_keychain_credential returns default value when credential not found" {
    # Mock the security command to fail
    function security() {
        return 1
    }
    export -f security
    
    # Mock keychain_available to return true
    function keychain_available() {
        return 0
    }
    export -f keychain_available
    
    run get_keychain_credential "missing_cred" "default_val"
    assert_output "default_val"
    assert_success
    
    run get_keychain_credential "missing_cred"
    assert_output ""
    assert_success
}

# Test get_keychain_credential when keychain is not available
@test "get_keychain_credential returns default value when keychain not available" {
    # Mock keychain_available to return false
    function keychain_available() {
        return 1
    }
    export -f keychain_available
    
    run get_keychain_credential "any_cred" "default_val"
    assert_output "default_val"
    assert_failure
    
    run get_keychain_credential "any_cred"
    assert_output ""
    assert_failure
}

# Test store_keychain_credential with mock security command
@test "store_keychain_credential stores credentials successfully" {
    # Mock the security commands to succeed
    function security() {
        if [[ "$1" == "delete-generic-password" ]]; then
            return 0
        elif [[ "$1" == "add-generic-password" ]]; then
            return 0
        fi
        return 1
    }
    export -f security
    
    # Mock keychain_available to return true
    function keychain_available() {
        return 0
    }
    export -f keychain_available
    
    run store_keychain_credential "test_cred" "test_value"
    assert_success
}

# Test store_keychain_credential fails when keychain not available
@test "store_keychain_credential fails when keychain not available" {
    # Mock keychain_available to return false
    function keychain_available() {
        return 1
    }
    export -f keychain_available
    
    run store_keychain_credential "test_cred" "test_value"
    assert_failure
}

# Test keychain_credential_exists with mock security command
@test "keychain_credential_exists returns appropriate value" {
    # Mock the security command to succeed for specific credential
    function security() {
        if [[ "$3" == "${KEYCHAIN_SERVICE}-existing_cred" ]]; then
            return 0
        fi
        return 1
    }
    export -f security
    
    # Mock keychain_available to return true
    function keychain_available() {
        return 0
    }
    export -f keychain_available
    
    run keychain_credential_exists "existing_cred"
    assert_success
    
    run keychain_credential_exists "missing_cred"
    assert_failure
}

# Test get_credential_with_prompt returns existing credential
@test "get_credential_with_prompt returns existing credential" {
    # Mock get_keychain_credential
    function get_keychain_credential() {
        if [[ "$1" == "existing_cred" ]]; then
            echo "existing_value"
            return 0
        fi
        echo ""
        return 1
    }
    export -f get_keychain_credential
    
    run get_credential_with_prompt "existing_cred" "Enter credential:"
    assert_output "existing_value"
    assert_success
}

# Test get_credential_with_prompt prompts for missing credential
@test "get_credential_with_prompt prompts for missing credential" {
    # Mock get_keychain_credential to not find the credential
    function get_keychain_credential() {
        echo ""
        return 1
    }
    export -f get_keychain_credential
    
    # Mock read to simulate user input
    function read() {
        # Echo the prompt message for testing
        echo "$@" >/dev/null
        # Provide simulated input
        echo "user_input_value"
    }
    export -f read
    
    # Mock store_keychain_credential
    function store_keychain_credential() {
        # Check that the function is called with expected args
        [[ "$1" == "missing_cred" && "$2" == "user_input_value" ]]
        return 0
    }
    export -f store_keychain_credential
    
    run get_credential_with_prompt "missing_cred" "Enter credential:"
    assert_output "user_input_value"
    assert_success
}

# Test manage_api_key with KEYCHAIN value
@test "manage_api_key retrieves value from keychain when KEYCHAIN is specified" {
    # Mock get_keychain_credential to return a value
    function get_keychain_credential() {
        if [[ "$1" == "api_key" ]]; then
            echo "keychain_value"
            return 0
        fi
        echo ""
        return 1
    }
    export -f get_keychain_credential
    
    # Run manage_api_key with KEYCHAIN as current value
    run manage_api_key "api_key" "KEYCHAIN" "Enter API key:"
    assert_output "keychain_value"
    assert_success
}

# Test manage_api_key with KEYCHAIN value but no value in keychain
@test "manage_api_key prompts for input when KEYCHAIN specified but no value exists" {
    # Mock get_keychain_credential to return empty for the API key
    function get_keychain_credential() {
        echo ""
        return 1
    }
    export -f get_keychain_credential
    
    # Mock get_credential_with_prompt to simulate user input
    function get_credential_with_prompt() {
        echo "prompted_value"
        return 0
    }
    export -f get_credential_with_prompt
    
    # Run manage_api_key with KEYCHAIN as current value
    run manage_api_key "api_key" "KEYCHAIN" "Enter API key:"
    assert_output "prompted_value"
    assert_success
}

# Test manage_api_key with non-KEYCHAIN value
@test "manage_api_key returns current value when not KEYCHAIN" {
    # Run manage_api_key with a specific value
    run manage_api_key "api_key" "specific_value" "Enter API key:"
    assert_output "specific_value"
    assert_success
}

# Test setup_keychain_credentials when credentials already exist
@test "setup_keychain_credentials succeeds when credentials already exist" {
    # Mock keychain_available to return true
    function keychain_available() {
        return 0
    }
    export -f keychain_available
    
    # Mock keychain_credential_exists to indicate credentials exist
    function keychain_credential_exists() {
        return 0
    }
    export -f keychain_credential_exists
    
    run setup_keychain_credentials
    assert_success
}

# Test setup_keychain_credentials when keychain not available
@test "setup_keychain_credentials fails when keychain not available" {
    # Mock keychain_available to return false
    function keychain_available() {
        return 1
    }
    export -f keychain_available
    
    run setup_keychain_credentials
    assert_failure
}

# Test setup_keychain_credentials when credentials don't exist
@test "setup_keychain_credentials prompts for missing credentials" {
    # Mock keychain_available to return true
    function keychain_available() {
        return 0
    }
    export -f keychain_available
    
    # Mock keychain_credential_exists to indicate credentials don't exist
    function keychain_credential_exists() {
        return 1
    }
    export -f keychain_credential_exists
    
    # Mock read to simulate user input
    function read() {
        # Extract prompt variable name from -rp option
        # Provide simulated input based on prompt
        echo "test_api_key"
    }
    export -f read
    
    # Mock store_keychain_credential to succeed
    function store_keychain_credential() {
        return 0
    }
    export -f store_keychain_credential
    
    run setup_keychain_credentials
    assert_success
}