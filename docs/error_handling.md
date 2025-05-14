# Error Handling in Ingestor System

This document describes the error handling mechanisms implemented in the Ingestor System project.

## Overview

The Ingestor System now includes a robust error handling module that provides consistent error handling, detailed error reporting, categorized error codes, and retry mechanisms for transient failures. The error handling module is designed to be used throughout the codebase, providing a uniform approach to error management.

## Key Components

### 1. Error Handling Module (`src/modules/error_handling.sh`)

The core of the error handling system is the new `error_handling.sh` module, which provides:

- **Categorized Error Codes**: Specific error code ranges for different types of errors (configuration, permission, file operation, network, database, API, dependency, validation, timeout)
- **Human-Readable Error Descriptions**: Mapping between error codes and descriptive error messages
- **Retry Mechanisms**: Functions for retrying commands and operations with configurable retry counts and exponential backoff
- **Resource Validation**: Functions to check if files, directories, and dependencies exist and are accessible
- **Error Trapping**: Global error trap handler to capture and log errors with context
- **Cleanup Handling**: Automatic cleanup on exit to ensure resources are properly released

### 2. Updated Database Module

The database module has been enhanced with:

- **Input validation**: Checking for required parameters before proceeding
- **Resource verification**: Ensuring database files and directories exist and are accessible
- **Dependency checking**: Verifying SQLite and other required tools are available
- **Retry logic**: Adding retry capabilities for database operations that might fail due to transient issues
- **Detailed error reporting**: Providing specific error codes and messages for different failure scenarios
- **Graceful failure handling**: Ensuring proper cleanup and resource release on errors

### 3. Updated Keychain Module

The keychain module now features:

- **Credential validation**: Ensuring credential names and values are valid before storing
- **Retry mechanisms**: Adding retry capabilities for keychain operations that might be affected by transient issues
- **Enhanced security**: Better handling of sensitive information with proper validation and cleanup
- **Interactive retry**: Implementing retry logic for user prompts with clear feedback
- **Verification steps**: Validating that credentials are actually retrievable after storage
- **Consistent error codes**: Using standardized error codes for different types of failures

## Usage Examples

### Basic Error Handling

```bash
# Validate a required parameter
require_variable "filename" "$filename" "Filename is required" || return $ERR_VALIDATION

# Check if a file exists and is readable
check_file_readable "$input_file" || return $ERR_FILE

# Ensure a directory exists or create it
ensure_directory "$output_dir" || return $ERR_FILE
```

### Retry Mechanisms

```bash
# Retry a command with default settings (3 retries, 2 second initial delay)
retry_command "curl -s https://example.com/api" || return $ERR_NETWORK

# Retry with custom settings (5 retries, 1 second initial delay)
retry_command "curl -s https://example.com/api" 5 1 || return $ERR_NETWORK

# Retry a function call
retry_function "my_network_function" 3 2 "arg1" "arg2" || return $ERR_NETWORK
```

### Timeout Handling

```bash
# Run a command with a timeout (10 seconds)
run_with_timeout "process_large_file $file" 10 || return $ERR_TIMEOUT
```

## Error Code Categories

| Code Range | Category      | Description                                   |
|------------|---------------|-----------------------------------------------|
| 1          | General       | General errors                                |
| 10-19      | Configuration | Configuration loading or parsing errors       |
| 20-29      | Permission    | Permission or access denied errors            |
| 30-39      | File          | File operation errors (read, write, delete)   |
| 40-49      | Network       | Network operation errors                      |
| 50-59      | Database      | Database operation errors                     |
| 60-69      | API           | API interaction errors                        |
| 70-79      | Dependency    | Missing dependency errors                     |
| 80-89      | Validation    | Input validation errors                       |
| 90-99      | Timeout       | Operation timeout errors                      |

## Testing

The error handling module comes with comprehensive unit tests (`tests/unit/error_handling.bats`) that verify:

- Dependency checking functionality
- File and directory validation
- Variable requirement validation
- Retry mechanisms
- Error code and description mapping

## Integration Into Existing Codebase

The error handling module has been integrated into key parts of the codebase:

1. **Database Module**: Enhanced with input validation, resource verification, and retry capabilities
2. **Keychain Module**: Updated with credential validation, secure handling, and interactive retry logic

## Future Improvements

1. **Expand Coverage**: Integrate error handling into remaining modules
2. **Error Reporting**: Implement centralized error reporting and analytics
3. **Recovery Mechanisms**: Add automatic recovery procedures for known error patterns
4. **User-Facing Messages**: Improve user-facing error messages for better UX
5. **Configuration**: Make retry counts and timeouts configurable via config files