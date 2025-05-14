# Enhanced Error Handling in Ingestor System

This document describes the enhanced error handling mechanisms implemented in the Ingestor system.

## Overview

The enhanced error handling framework provides robust error detection, reporting, and recovery features to ensure
that the Ingestor system is resilient to failures and can provide detailed diagnostics when issues occur.

## Key Features

- **Standardized Error Codes**: Clear error code categories for different types of issues.
- **Comprehensive Error Messages**: Human-readable descriptions of error conditions.
- **Robust Retry Mechanisms**: Automatic retry for transient failures with exponential backoff.
- **Transaction Support**: Database transactions to ensure atomicity of operations.
- **Resource Validation**: Proactive validation of system resources before critical operations.
- **Detailed Logging**: Comprehensive logging of error states with contextual information.
- **Error Recovery**: Structured approach to recovering from common error conditions.
- **Try-Catch-Finally Pattern**: Support for structured error handling similar to other programming languages.
- **Gradual Degradation**: Fallback mechanisms when enhanced features aren't available.

## Error Code Categories

Error codes in the Ingestor system are organized by category:

| Category | Range | Description |
|----------|-------|-------------|
| General | 1-10 | General errors and unknown issues |
| File/IO | 11-20 | File system operations, permissions, and IO errors |
| Validation | 21-30 | Input validation and data integrity issues |
| Database | 31-40 | Database operations and integrity problems |
| Network | 41-50 | Network connectivity and API communication issues |
| System | 51-60 | System resource and environment issues |
| Content | 61-70 | Content processing and transformation issues |
| AI/Claude | 71-80 | AI-related operations and API errors |

## Using Enhanced Error Handling

### Setting Up

To use the enhanced error handling in your module, source the `enhanced_error_handler.sh` module:

```bash
#!/bin/bash
# Your module

# Source the enhanced error handler
if ! type init_enhanced_error_handler &>/dev/null; then
    if [[ -f "${BASH_SOURCE%/*}/enhanced_error_handler.sh" ]]; then
        source "${BASH_SOURCE%/*}/enhanced_error_handler.sh"
        init_enhanced_error_handler
    else
        echo "Error: Enhanced error handler not found" >&2
        exit 1
    fi
fi
```

### Function Error Handling

Use the `try`, `catch`, and `finally` functions for structured error handling:

```bash
# Example function using try-catch
process_data() {
    local input_file="$1"
    local output_file="$2"
    
    try some_operation "$input_file" "$output_file"
    
    catch handle_error "Failed to process data"
    
    finally cleanup_resources
    
    if [[ ${_ENHANCED_ERROR_HANDLER_CODE:-0} -eq 0 ]]; then
        log_info "Processing completed successfully"
        return 0
    else
        return ${_ENHANCED_ERROR_HANDLER_CODE}
    fi
}

# Error handler function
handle_error() {
    local message="$1"
    local error_code="$2"
    local line="$3"
    local func="$4"
    local file="$5"
    
    log_error "$message: error $error_code at $file:$line in $func"
    return $error_code
}

# Cleanup function
cleanup_resources() {
    # Cleanup code here
    log_debug "Cleaned up resources"
}
```

### Retry Mechanisms

Use retries for operations that might experience transient failures:

```bash
# Example of retry with backoff
download_file() {
    local url="$1"
    local output_file="$2"
    
    retry_with_backoff "curl -s -o '$output_file' '$url'" 5 2 30 60
    return $?
}
```

### Input Validation

Use enhanced validation for function inputs:

```bash
process_user() {
    local username="$1"
    local email="$2"
    local age="$3"
    
    validate_conditions "process_user" \
        "username" "$username" "Username is required" \
        "email" "$email" "Email is required" \
        "age" "$age" "Age is required"
    
    if [[ $? -ne 0 ]]; then
        return $ERR_VALIDATION
    fi
    
    # Process user data
}
```

### Database Transaction Support

Use transaction support for database operations:

```bash
update_record() {
    local db_path="$1"
    local id="$2"
    local data="$3"
    
    begin_transaction "$db_path"
    local transaction_started=$?
    
    if [[ $transaction_started -ne 0 ]]; then
        log_error "Failed to start transaction"
        return $transaction_started
    fi
    
    # Execute queries
    local result=0
    safe_sql_query "$db_path" "UPDATE records SET data='$data' WHERE id=$id" > /dev/null
    result=$?
    
    if [[ $result -eq 0 ]]; then
        commit_transaction "$db_path"
        log_info "Record updated successfully"
        return 0
    else
        rollback_transaction "$db_path"
        log_error "Failed to update record"
        return $result
    fi
}
```

### Resource Checking

Check system resources before operations:

```bash
process_large_file() {
    local file="$1"
    
    # Check for sufficient resources
    check_system_resources 500 256  # Need 500MB disk space, 256MB RAM
    if [[ $? -ne 0 ]]; then
        log_error "Insufficient system resources for processing"
        return $ERR_RESOURCE_LIMIT
    fi
    
    # Process the file
}
```

## Error Documentation and Analysis

Errors in the Ingestor system are documented in the error log file at `$ERROR_LOG_DIR/ingestor_errors_*.log`.
Each error entry includes:

- Timestamp
- Error code and name
- Source file, line number, and function
- Detailed error description
- Stack trace (if enabled)
- System diagnostics (if enabled)

You can analyze error patterns using standard text processing tools:

```bash
# Example: Count errors by type
grep "\[ERROR\]" $ERROR_LOG_DIR/ingestor_errors_*.log | sort | uniq -c | sort -nr

# Example: Find most common error locations
grep -o "at [^:]\+:[0-9]\+" $ERROR_LOG_DIR/ingestor_errors_*.log | sort | uniq -c | sort -nr
```

## Integration with Logging

The enhanced error handler integrates with the existing logging system, ensuring that all
errors are properly logged. If the logging module is not available, it falls back to basic
error output using `echo` to stderr.

## Best Practices

1. **Always check return codes** from functions that may fail.
2. **Use retry for transient failures** like network operations.
3. **Validate all inputs** at the beginning of functions.
4. **Use transactions** for database operations that modify data.
5. **Check resources** before executing resource-intensive operations.
6. **Document errors** with sufficient context for debugging.
7. **Provide recovery mechanisms** for common error conditions.
8. **Use try-catch-finally** for complex error handling scenarios.
9. **Add clear error messages** that explain what went wrong and how to fix it.
10. **Use timeouts** for operations that may hang.

## Error Handling in Scripts

For standalone scripts, initialize error handling at the beginning:

```bash
#!/bin/bash
# Script description

# Source enhanced error handler
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../src/modules/enhanced_error_handler.sh" ]]; then
    source "$SCRIPT_DIR/../src/modules/enhanced_error_handler.sh"
    init_enhanced_error_handler
else
    echo "Error: Enhanced error handler not found" >&2
    exit 1
fi

# Rest of the script
```

## Backward Compatibility

The enhanced error handler maintains backward compatibility with existing code by:

1. Providing fallback mechanisms when enhanced functions aren't available.
2. Preserving the same function signatures for common operations.
3. Supporting both old-style error handling and the new try-catch pattern.

## Troubleshooting Common Issues

### Handler Not Initialized

If you see "function not found" errors for enhanced error functions, make sure you've:

1. Sourced the enhanced_error_handler.sh file
2. Called init_enhanced_error_handler
3. Checked for typos in function names

### Database Connection Issues

For database-related errors:

1. Check database file permissions
2. Verify SQLite is installed
3. Look for database locks from other processes
4. Ensure sufficient disk space

### Network Failures

For network-related errors:

1. Verify connectivity to the target server
2. Check for firewall or proxy settings
3. Ensure proper credentials are provided
4. Look for rate-limiting or quota issues

## Advanced Error Recovery

For automated recovery from common errors:

1. **Disk Space Issues**: Clean up temporary files and old logs
2. **Database Locks**: Wait and retry after a timeout
3. **Network Issues**: Check connection and retry with backoff
4. **API Rate Limits**: Implement token bucket algorithm for rate limiting

## Monitoring and Alerting

To set up monitoring for critical errors:

1. Configure log file rotation and archiving
2. Set up log analysis to identify error patterns
3. Create alerts for persistent or high-frequency errors
4. Document recovery procedures for common error scenarios

## Conclusion

The enhanced error handling framework provides comprehensive tools for detecting, reporting,
and recovering from errors in the Ingestor system. By following the guidelines in this document,
you can ensure your code is robust, resilient, and maintainable.