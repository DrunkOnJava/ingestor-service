#!/usr/bin/env bats
# Unit tests for enhanced error handling

load '../test_helper'
load '../libs/bats-support/load'
load '../libs/bats-assert/load'

# Setup - executed before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Source appropriate error handlers for testing
    source "${BATS_TEST_DIRNAME}/../../src/modules/error_codes.sh"
    source "${BATS_TEST_DIRNAME}/../../src/modules/error_handler.sh"
    
    # Initialize error handler with test-specific settings
    export ERROR_LOG_DIR="/tmp/ingestor-test-errors"
    export ERROR_LOG_FILE="${ERROR_LOG_DIR}/test_errors.log"
    mkdir -p "$ERROR_LOG_DIR" || true
    
    # Create mock log functions if not available
    if ! type log_debug &>/dev/null; then
        log_debug() { :; }
        log_info() { :; }
        log_warning() { :; }
        log_error() { :; }
    fi
}

# Teardown - executed after each test
teardown() {
    # Clean up test log files
    rm -rf "$ERROR_LOG_DIR" || true
}

# Test error code descriptions
@test "get_error_name returns correct name for known error code" {
    result=$(get_error_name $ERR_FILE_NOT_FOUND)
    assert_equal "$result" "ERR_FILE_NOT_FOUND"
}

@test "get_error_message returns correct message for known error code" {
    result=$(get_error_message $ERR_FILE_NOT_FOUND)
    assert_equal "$result" "File not found"
}

# Test try-catch mechanism
@test "try-catch can catch errors" {
    # Define a test function that fails
    test_function() {
        return $ERR_VALIDATION
    }
    
    # Define error handler
    handle_test_error() {
        local error_code="$1"
        # Set a variable to indicate error was caught
        ERROR_CAUGHT=1
        ERROR_CODE=$error_code
        return 0 # Handle the error successfully
    }
    
    # Execute with try-catch
    ERROR_CAUGHT=0
    ERROR_CODE=0
    
    try test_function
    catch handle_test_error
    
    # Verify error was caught
    assert_equal $ERROR_CAUGHT 1
    assert_equal $ERROR_CODE $ERR_VALIDATION
}

@test "finally block executes regardless of error" {
    # Define test functions
    test_success() { return 0; }
    test_failure() { return $ERR_VALIDATION; }
    
    handle_error() { return 0; }
    
    cleanup_executed=0
    cleanup() { cleanup_executed=1; }
    
    # Test with success
    cleanup_executed=0
    try test_success
    finally cleanup
    assert_equal $cleanup_executed 1
    
    # Test with failure
    cleanup_executed=0
    try test_failure
    catch handle_error
    finally cleanup
    assert_equal $cleanup_executed 1
}

# Test retry mechanism
@test "retry_with_backoff retries the correct number of times" {
    # Create a temporary file to track retry count
    RETRY_COUNT_FILE=$(mktemp)
    echo "0" > "$RETRY_COUNT_FILE"
    
    # Function that fails N times then succeeds
    test_retry() {
        local count=$(cat "$RETRY_COUNT_FILE")
        if [[ $count -lt 2 ]]; then
            echo $((count + 1)) > "$RETRY_COUNT_FILE"
            return 1
        else
            echo "SUCCESS" > "$RETRY_COUNT_FILE"
            return 0
        fi
    }
    
    # Run with retry
    run retry_function test_retry 3 0.1 0.5
    
    # Assert success and correct number of tries
    assert_success
    assert_equal "$(cat "$RETRY_COUNT_FILE")" "SUCCESS"
    
    # Clean up
    rm -f "$RETRY_COUNT_FILE"
}

@test "retry_with_backoff gives up after max retries" {
    # Create a temporary file to track retry count
    RETRY_COUNT_FILE=$(mktemp)
    echo "0" > "$RETRY_COUNT_FILE"
    
    # Function that always fails
    test_always_fail() {
        local count=$(cat "$RETRY_COUNT_FILE")
        echo $((count + 1)) > "$RETRY_COUNT_FILE"
        return 1
    }
    
    # Run with retry (using a short timeout for faster tests)
    run retry_function test_always_fail 3 0.1 0.2
    
    # Assert failure and correct number of tries
    assert_failure
    assert_equal "$(cat "$RETRY_COUNT_FILE")" "3"
    
    # Clean up
    rm -f "$RETRY_COUNT_FILE"
}

# Test file locking
@test "acquire_lock and release_lock work correctly" {
    local lock_file="/tmp/test_lock_$$"
    
    # Clean up any existing lock
    rm -f "$lock_file" || true
    
    # Acquire lock
    run acquire_lock "$lock_file" 1
    assert_success
    assert [ -f "$lock_file" ]
    
    # Verify lock contains our PID
    run cat "$lock_file"
    assert_output "$$"
    
    # Release lock
    run release_lock "$lock_file"
    assert_success
    assert [ ! -f "$lock_file" ]
}

# Test transaction management
@test "transaction management functions" {
    # Create test database
    local test_db="/tmp/test_transaction_$$.sqlite"
    rm -f "$test_db" || true
    
    # Initialize database
    run sqlite3 "$test_db" "CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);"
    assert_success
    
    # Test begin transaction
    run begin_transaction "$test_db"
    assert_success
    
    # Insert data
    run sqlite3 "$test_db" "INSERT INTO test (value) VALUES ('test data');"
    assert_success
    
    # Verify data exists within transaction
    run sqlite3 "$test_db" "SELECT value FROM test WHERE id = 1;"
    assert_output "test data"
    
    # Test rollback
    run rollback_transaction "$test_db"
    assert_success
    
    # Verify data is gone after rollback
    run sqlite3 "$test_db" "SELECT COUNT(*) FROM test;"
    assert_output "0"
    
    # Begin new transaction
    run begin_transaction "$test_db"
    assert_success
    
    # Insert data again
    run sqlite3 "$test_db" "INSERT INTO test (value) VALUES ('test data 2');"
    assert_success
    
    # Commit transaction
    run commit_transaction "$test_db"
    assert_success
    
    # Verify data persists after commit
    run sqlite3 "$test_db" "SELECT value FROM test WHERE id = 1;"
    assert_output "test data 2"
    
    # Clean up
    rm -f "$test_db" || true
}

# Test resource checking
@test "check_system_resources validates disk space correctly" {
    # Get actual available disk space
    local available_space
    available_space=$(df -m . | awk 'NR==2 {print $4}')
    
    # Test with much less than available (should succeed)
    run check_system_resources $((available_space / 2)) 1
    assert_success
    
    # Test with more than available (should fail)
    run check_system_resources $((available_space * 2)) 1
    assert_failure
}

# Test validation
@test "validate_conditions detects missing values" {
    # Define variables for testing
    local name="Test User"
    local email=""
    local age="30"
    
    # Test validation with missing email
    run validate_conditions "test_function" \
        "name" "$name" "Name is required" \
        "email" "$email" "Email is required" \
        "age" "$age" "Age is required"
    
    # Should fail because email is empty
    assert_failure
    
    # Set email and try again
    email="test@example.com"
    run validate_conditions "test_function" \
        "name" "$name" "Name is required" \
        "email" "$email" "Email is required" \
        "age" "$age" "Age is required"
    
    # Should succeed with all values present
    assert_success
}