#!/usr/bin/env bats
# Unit tests for error handling module

load '../test_helper'

setup() {
  # Set up the environment for tests
  export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
  export LOG_DIR="$BATS_TEST_DIRNAME/fixtures/logs"
  mkdir -p "$LOG_DIR"
  
  # Source the required modules
  source "$PROJECT_ROOT/src/modules/logging.sh"
  source "$PROJECT_ROOT/src/modules/error_handling.sh"
  
  # Initialize logging for tests
  init_logging
}

teardown() {
  # Clean up after tests
  rm -rf "$LOG_DIR"
}

@test "init_error_handling should not throw errors" {
  run init_error_handling
  assert_success
}

@test "check_dependencies should succeed with existing commands" {
  run check_dependencies "ls" "cat"
  assert_success
}

@test "check_dependencies should fail with non-existing commands" {
  run check_dependencies "this_command_does_not_exist_12345"
  assert_failure
  assert_output --partial "Required dependency not found"
  assert [ $status -eq $ERR_DEPENDENCY ]
}

@test "check_file_readable should succeed with readable file" {
  # Create a readable test file
  local test_file="$BATS_TEST_TMPDIR/readable.txt"
  touch "$test_file"
  chmod +r "$test_file"
  
  run check_file_readable "$test_file"
  assert_success
}

@test "check_file_readable should fail with non-existent file" {
  run check_file_readable "/path/to/nonexistent/file_12345.txt"
  assert_failure
  assert_output --partial "File not found"
  assert [ $status -eq $ERR_FILE ]
}

@test "check_file_readable should fail with unreadable file" {
  # Create an unreadable test file
  local test_file="$BATS_TEST_TMPDIR/unreadable.txt"
  touch "$test_file"
  chmod -r "$test_file"
  
  run check_file_readable "$test_file"
  assert_failure
  assert_output --partial "File not readable"
  assert [ $status -eq $ERR_PERMISSION ]
  
  # Clean up (need to make it writable first to delete)
  chmod +r "$test_file"
}

@test "ensure_directory should create directory if missing" {
  local test_dir="$BATS_TEST_TMPDIR/new_dir"
  
  run ensure_directory "$test_dir"
  assert_success
  assert [ -d "$test_dir" ]
}

@test "ensure_directory should succeed if directory exists" {
  local test_dir="$BATS_TEST_TMPDIR/existing_dir"
  mkdir -p "$test_dir"
  
  run ensure_directory "$test_dir"
  assert_success
}

@test "require_variable should succeed with non-empty variable" {
  run require_variable "TEST_VAR" "test_value"
  assert_success
}

@test "require_variable should fail with empty variable" {
  run require_variable "TEST_VAR" ""
  assert_failure
  assert_output --partial "Required variable TEST_VAR is empty"
  assert [ $status -eq $ERR_VALIDATION ]
}

@test "retry_command should succeed with successful command" {
  run retry_command "echo success"
  assert_success
  assert_output "success"
}

@test "retry_command should fail with failing command after retries" {
  run retry_command "false" 2 1
  assert_failure
  assert_output --partial "Command failed after 2 retries"
}

@test "get_error_description should return description for known error code" {
  local description=$(get_error_description $ERR_FILE)
  assert_equal "$description" "File operation error"
}

@test "get_error_description should return 'Unknown error' for unknown error code" {
  local description=$(get_error_description 999)
  assert_equal "$description" "Unknown error"
}