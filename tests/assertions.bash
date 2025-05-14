#!/usr/bin/env bash
# BATS assertion functions

# Determine tests directory if not defined
if [[ -z "${TESTS_DIR}" ]]; then
    # Try to determine the tests directory
    if [[ -n "${DIR}" ]]; then
        TESTS_DIR="${DIR}"
    else
        TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi

# Make sure the BATS libraries exist
if [[ ! -d "${TESTS_DIR}/libs/bats-support" ]]; then
    echo "Error: BATS libraries not found in ${TESTS_DIR}/libs"
    echo "Please run the install_test_deps.sh script first."
    return 1
fi

# Load BATS libraries
load "${TESTS_DIR}/libs/bats-support/load"
load "${TESTS_DIR}/libs/bats-assert/load"
load "${TESTS_DIR}/libs/bats-file/load"

# Assert that command was successful (return code 0)
assert_success() {
    if [[ "$status" -ne 0 ]]; then
        echo "expected success, got failure: exit status $status"
        echo "output: $output"
        return 1
    fi
}

# Assert that command failed (return code not 0)
assert_failure() {
    if [[ "$status" -eq 0 ]]; then
        echo "expected failure, got success"
        echo "output: $output"
        return 1
    fi
}

# Assert that output equals expected value
assert_output() {
    local expected="$1"
    if [[ "$output" != "$expected" ]]; then
        echo "expected: $expected"
        echo "actual  : $output"
        return 1
    fi
}

# Assert that output contains expected substring
assert_output_contains() {
    local expected="$1"
    if [[ ! "$output" =~ $expected ]]; then
        echo "expected to contain: $expected"
        echo "actual output: $output"
        return 1
    fi
}

# Assert that output matches regex pattern
assert_output_matches() {
    local pattern="$1"
    if [[ ! "$output" =~ $pattern ]]; then
        echo "expected to match pattern: $pattern"
        echo "actual output: $output"
        return 1
    fi
}

# Assert that a variable equals expected value
assert_equal() {
    local actual="$1"
    local expected="$2"
    local message="${3:-}"
    
    if [[ "$actual" != "$expected" ]]; then
        echo "${message}expected: $expected"
        echo "${message}actual  : $actual"
        return 1
    fi
}

# Assert that a variable contains expected substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    if [[ ! "$haystack" =~ $needle ]]; then
        echo "${message}expected to contain: $needle"
        echo "${message}actual: $haystack"
        return 1
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file="$1"
    local message="${2:-}"
    
    if [[ ! -f "$file" ]]; then
        echo "${message}expected file to exist: $file"
        return 1
    fi
}

# Assert that a directory exists
assert_dir_exists() {
    local dir="$1"
    local message="${2:-}"
    
    if [[ ! -d "$dir" ]]; then
        echo "${message}expected directory to exist: $dir"
        return 1
    fi
}

# Assert that a variable is empty
assert_empty() {
    local value="$1"
    local message="${2:-}"
    
    if [[ -n "$value" ]]; then
        echo "${message}expected empty value"
        echo "${message}actual: $value"
        return 1
    fi
}

# Assert that a variable is not empty
assert_not_empty() {
    local value="$1"
    local message="${2:-}"
    
    if [[ -z "$value" ]]; then
        echo "${message}expected non-empty value"
        return 1
    fi
}

# Assert that a file contains specific content
# Usage: assert_file_contains "/path/to/file" "expected content"
assert_file_contains() {
    local file_path="$1"
    local expected_content="$2"
    local message="${3:-}"
    
    if [[ -z "$message" ]]; then
        message="File '$file_path' should contain '$expected_content'"
    fi
    
    if [[ ! -f "$file_path" ]]; then
        echo "File '$file_path' does not exist"
        return 1
    fi
    
    if ! grep -q "$expected_content" "$file_path"; then
        echo "$message"
        return 1
    fi
}

# Assert that a file does not contain specific content
# Usage: assert_file_not_contains "/path/to/file" "unexpected content"
assert_file_not_contains() {
    local file_path="$1"
    local unexpected_content="$2"
    local message="${3:-}"
    
    if [[ -z "$message" ]]; then
        message="File '$file_path' should not contain '$unexpected_content'"
    fi
    
    if [[ ! -f "$file_path" ]]; then
        echo "File '$file_path' does not exist"
        return 1
    fi
    
    if grep -q "$unexpected_content" "$file_path"; then
        echo "$message"
        return 1
    fi
}

# Assert that two files are identical
# Usage: assert_files_equal "/path/to/file1" "/path/to/file2"
assert_files_equal() {
    local file1="$1"
    local file2="$2"
    local message="${3:-}"
    
    if [[ -z "$message" ]]; then
        message="Files '$file1' and '$file2' should be identical"
    fi
    
    if [[ ! -f "$file1" ]]; then
        echo "File '$file1' does not exist"
        return 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        echo "File '$file2' does not exist"
        return 1
    fi
    
    if ! cmp -s "$file1" "$file2"; then
        echo "$message"
        return 1
    fi
}

# Assert that a database exists
# Usage: assert_database_exists "/path/to/database.db"
assert_database_exists() {
    local db_path="$1"
    local message="${2:-}"
    
    if [[ -z "$message" ]]; then
        message="Database '$db_path' should exist"
    fi
    
    assert_file_exists "$db_path" "$message"
    
    # Check if it's a valid SQLite database
    if ! sqlite3 "$db_path" "SELECT 1;" &>/dev/null; then
        echo "File '$db_path' exists but is not a valid SQLite database"
        return 1
    fi
}

# Assert that a database table exists
# Usage: assert_table_exists "/path/to/database.db" "table_name"
assert_table_exists() {
    local db_path="$1"
    local table_name="$2"
    local message="${3:-}"
    
    if [[ -z "$message" ]]; then
        message="Table '$table_name' should exist in database '$db_path'"
    fi
    
    # Check if database exists
    assert_database_exists "$db_path"
    
    # Check if table exists
    if ! sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table_name';" | grep -q "$table_name"; then
        echo "$message"
        return 1
    fi
}