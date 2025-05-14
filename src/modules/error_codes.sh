#!/bin/bash
# Error codes module for ingestor system
# Defines standardized error codes and messages

# General error codes (1-10)
export ERR_UNKNOWN=1         # Unknown error
export ERR_USAGE=2           # Incorrect usage
export ERR_INIT=3            # Initialization error
export ERR_CONFIG=4          # Configuration error
export ERR_PERMISSION=5      # Permission denied
export ERR_TIMEOUT=6         # Operation timed out
export ERR_INTERRUPTED=7     # Operation interrupted
export ERR_CANCELED=8        # Operation canceled
export ERR_NOT_IMPLEMENTED=9 # Feature not implemented
export ERR_FAILED=10         # Generic operation failed

# File and I/O errors (11-20)
export ERR_FILE=11           # File error (generic)
export ERR_FILE_NOT_FOUND=12 # File not found
export ERR_FILE_UNREADABLE=13 # Cannot read file
export ERR_FILE_UNWRITABLE=14 # Cannot write to file
export ERR_DIR_NOT_FOUND=15  # Directory not found
export ERR_DIR_UNWRITABLE=16 # Cannot write to directory
export ERR_IO=17             # I/O error
export ERR_FILE_FORMAT=18    # Invalid file format
export ERR_FILE_TOO_LARGE=19 # File too large
export ERR_FILE_CORRUPT=20   # File corrupted

# Validation errors (21-30)
export ERR_VALIDATION=21     # Validation error (generic)
export ERR_INVALID_ARG=22    # Invalid argument
export ERR_MISSING_ARG=23    # Missing argument
export ERR_INVALID_FORMAT=24 # Invalid format
export ERR_INVALID_STATE=25  # Invalid state
export ERR_INVALID_DATA=26   # Invalid data
export ERR_NOT_FOUND=27      # Resource not found
export ERR_DUPLICATE=28      # Duplicate resource
export ERR_LIMIT_EXCEEDED=29 # Limit exceeded
export ERR_OUT_OF_RANGE=30   # Value out of range

# Database errors (31-40)
export ERR_DATABASE=31       # Database error (generic)
export ERR_DB_CONNECTION=32  # Database connection error
export ERR_DB_QUERY=33       # Database query error
export ERR_DB_CONSTRAINT=34  # Database constraint violation
export ERR_DB_INTEGRITY=35   # Database integrity error
export ERR_DB_CORRUPT=36     # Database corruption
export ERR_DB_LOCKED=37      # Database locked
export ERR_DB_NOT_FOUND=38   # Database not found
export ERR_DB_DUPLICATE=39   # Duplicate key/entry
export ERR_DB_SCHEMA=40      # Invalid database schema

# Network errors (41-50)
export ERR_NETWORK=41        # Network error (generic)
export ERR_NETWORK_DOWN=42   # Network is down
export ERR_NETWORK_TIMEOUT=43 # Network timeout
export ERR_HOST_UNREACHABLE=44 # Host unreachable
export ERR_CONNECTION_REFUSED=45 # Connection refused
export ERR_DNS_FAILURE=46    # DNS resolution failure
export ERR_SSL_ERROR=47      # SSL/TLS error
export ERR_API_ERROR=48      # API error
export ERR_HTTP_ERROR=49     # HTTP error
export ERR_UNAUTHORIZED=50   # Authentication/authorization error

# System and resource errors (51-60)
export ERR_SYSTEM=51         # System error (generic)
export ERR_MEMORY=52         # Out of memory
export ERR_DISK_SPACE=53     # Out of disk space
export ERR_CPU_LIMIT=54      # CPU limit exceeded
export ERR_PROCESS_LIMIT=55  # Process limit exceeded
export ERR_DEPENDENCY=56     # Missing dependency
export ERR_ENVIRONMENT=57    # Invalid environment
export ERR_OS_NOT_SUPPORTED=58 # OS not supported
export ERR_RESOURCE_LIMIT=59 # Resource limit exceeded
export ERR_CONCURRENCY=60    # Concurrency error

# Content processing errors (61-70)
export ERR_CONTENT=61        # Content error (generic)
export ERR_CONTENT_TYPE=62   # Unsupported content type
export ERR_CONTENT_SIZE=63   # Content size limit exceeded
export ERR_CONTENT_FORMAT=64 # Invalid content format
export ERR_CONTENT_ENCODING=65 # Invalid content encoding
export ERR_CONTENT_PARSE=66  # Content parsing error
export ERR_CONTENT_EXTRACT=67 # Content extraction error
export ERR_CONTENT_ANALYZE=68 # Content analysis error
export ERR_CONTENT_TRANSFORM=69 # Content transformation error
export ERR_CONTENT_VALIDATION=70 # Content validation error

# AI/Claude API errors (71-80)
export ERR_API_CLAUDE=71     # Claude API error (generic)
export ERR_API_INVALID_KEY=72 # Invalid API key
export ERR_API_RATE_LIMIT=73 # API rate limit exceeded
export ERR_API_QUOTA=74      # API quota exceeded
export ERR_API_UNAVAILABLE=75 # API service unavailable
export ERR_API_RESPONSE=76   # Invalid API response
export ERR_API_REQUEST=77    # Invalid API request
export ERR_API_TIMEOUT=78    # API request timeout
export ERR_API_MODEL=79      # Model error
export ERR_API_TOKEN_LIMIT=80 # Token limit exceeded

# Get error name from code
get_error_name() {
    local error_code=$1
    
    case $error_code in
        1)  echo "ERR_UNKNOWN" ;;
        2)  echo "ERR_USAGE" ;;
        3)  echo "ERR_INIT" ;;
        4)  echo "ERR_CONFIG" ;;
        5)  echo "ERR_PERMISSION" ;;
        6)  echo "ERR_TIMEOUT" ;;
        7)  echo "ERR_INTERRUPTED" ;;
        8)  echo "ERR_CANCELED" ;;
        9)  echo "ERR_NOT_IMPLEMENTED" ;;
        10) echo "ERR_FAILED" ;;
        11) echo "ERR_FILE" ;;
        12) echo "ERR_FILE_NOT_FOUND" ;;
        13) echo "ERR_FILE_UNREADABLE" ;;
        14) echo "ERR_FILE_UNWRITABLE" ;;
        15) echo "ERR_DIR_NOT_FOUND" ;;
        16) echo "ERR_DIR_UNWRITABLE" ;;
        17) echo "ERR_IO" ;;
        18) echo "ERR_FILE_FORMAT" ;;
        19) echo "ERR_FILE_TOO_LARGE" ;;
        20) echo "ERR_FILE_CORRUPT" ;;
        21) echo "ERR_VALIDATION" ;;
        22) echo "ERR_INVALID_ARG" ;;
        23) echo "ERR_MISSING_ARG" ;;
        24) echo "ERR_INVALID_FORMAT" ;;
        25) echo "ERR_INVALID_STATE" ;;
        26) echo "ERR_INVALID_DATA" ;;
        27) echo "ERR_NOT_FOUND" ;;
        28) echo "ERR_DUPLICATE" ;;
        29) echo "ERR_LIMIT_EXCEEDED" ;;
        30) echo "ERR_OUT_OF_RANGE" ;;
        31) echo "ERR_DATABASE" ;;
        32) echo "ERR_DB_CONNECTION" ;;
        33) echo "ERR_DB_QUERY" ;;
        34) echo "ERR_DB_CONSTRAINT" ;;
        35) echo "ERR_DB_INTEGRITY" ;;
        36) echo "ERR_DB_CORRUPT" ;;
        37) echo "ERR_DB_LOCKED" ;;
        38) echo "ERR_DB_NOT_FOUND" ;;
        39) echo "ERR_DB_DUPLICATE" ;;
        40) echo "ERR_DB_SCHEMA" ;;
        41) echo "ERR_NETWORK" ;;
        42) echo "ERR_NETWORK_DOWN" ;;
        43) echo "ERR_NETWORK_TIMEOUT" ;;
        44) echo "ERR_HOST_UNREACHABLE" ;;
        45) echo "ERR_CONNECTION_REFUSED" ;;
        46) echo "ERR_DNS_FAILURE" ;;
        47) echo "ERR_SSL_ERROR" ;;
        48) echo "ERR_API_ERROR" ;;
        49) echo "ERR_HTTP_ERROR" ;;
        50) echo "ERR_UNAUTHORIZED" ;;
        51) echo "ERR_SYSTEM" ;;
        52) echo "ERR_MEMORY" ;;
        53) echo "ERR_DISK_SPACE" ;;
        54) echo "ERR_CPU_LIMIT" ;;
        55) echo "ERR_PROCESS_LIMIT" ;;
        56) echo "ERR_DEPENDENCY" ;;
        57) echo "ERR_ENVIRONMENT" ;;
        58) echo "ERR_OS_NOT_SUPPORTED" ;;
        59) echo "ERR_RESOURCE_LIMIT" ;;
        60) echo "ERR_CONCURRENCY" ;;
        61) echo "ERR_CONTENT" ;;
        62) echo "ERR_CONTENT_TYPE" ;;
        63) echo "ERR_CONTENT_SIZE" ;;
        64) echo "ERR_CONTENT_FORMAT" ;;
        65) echo "ERR_CONTENT_ENCODING" ;;
        66) echo "ERR_CONTENT_PARSE" ;;
        67) echo "ERR_CONTENT_EXTRACT" ;;
        68) echo "ERR_CONTENT_ANALYZE" ;;
        69) echo "ERR_CONTENT_TRANSFORM" ;;
        70) echo "ERR_CONTENT_VALIDATION" ;;
        71) echo "ERR_API_CLAUDE" ;;
        72) echo "ERR_API_INVALID_KEY" ;;
        73) echo "ERR_API_RATE_LIMIT" ;;
        74) echo "ERR_API_QUOTA" ;;
        75) echo "ERR_API_UNAVAILABLE" ;;
        76) echo "ERR_API_RESPONSE" ;;
        77) echo "ERR_API_REQUEST" ;;
        78) echo "ERR_API_TIMEOUT" ;;
        79) echo "ERR_API_MODEL" ;;
        80) echo "ERR_API_TOKEN_LIMIT" ;;
        *)  echo "UNKNOWN_ERROR" ;;
    esac
}

# Get error message from code
get_error_message() {
    local error_code=$1
    
    case $error_code in
        1)  echo "Unknown error occurred" ;;
        2)  echo "Incorrect usage" ;;
        3)  echo "Initialization error occurred" ;;
        4)  echo "Configuration error occurred" ;;
        5)  echo "Permission denied" ;;
        6)  echo "Operation timed out" ;;
        7)  echo "Operation interrupted" ;;
        8)  echo "Operation canceled" ;;
        9)  echo "Feature not implemented" ;;
        10) echo "Operation failed" ;;
        11) echo "File error occurred" ;;
        12) echo "File not found" ;;
        13) echo "Cannot read file" ;;
        14) echo "Cannot write to file" ;;
        15) echo "Directory not found" ;;
        16) echo "Cannot write to directory" ;;
        17) echo "I/O error occurred" ;;
        18) echo "Invalid file format" ;;
        19) echo "File too large" ;;
        20) echo "File corrupted" ;;
        21) echo "Validation error occurred" ;;
        22) echo "Invalid argument" ;;
        23) echo "Missing argument" ;;
        24) echo "Invalid format" ;;
        25) echo "Invalid state" ;;
        26) echo "Invalid data" ;;
        27) echo "Resource not found" ;;
        28) echo "Duplicate resource" ;;
        29) echo "Limit exceeded" ;;
        30) echo "Value out of range" ;;
        31) echo "Database error occurred" ;;
        32) echo "Database connection error" ;;
        33) echo "Database query error" ;;
        34) echo "Database constraint violation" ;;
        35) echo "Database integrity error" ;;
        36) echo "Database corruption" ;;
        37) echo "Database locked" ;;
        38) echo "Database not found" ;;
        39) echo "Duplicate key/entry in database" ;;
        40) echo "Invalid database schema" ;;
        41) echo "Network error occurred" ;;
        42) echo "Network is down" ;;
        43) echo "Network timeout" ;;
        44) echo "Host unreachable" ;;
        45) echo "Connection refused" ;;
        46) echo "DNS resolution failure" ;;
        47) echo "SSL/TLS error" ;;
        48) echo "API error" ;;
        49) echo "HTTP error" ;;
        50) echo "Authentication/authorization error" ;;
        51) echo "System error occurred" ;;
        52) echo "Out of memory" ;;
        53) echo "Out of disk space" ;;
        54) echo "CPU limit exceeded" ;;
        55) echo "Process limit exceeded" ;;
        56) echo "Missing dependency" ;;
        57) echo "Invalid environment" ;;
        58) echo "OS not supported" ;;
        59) echo "Resource limit exceeded" ;;
        60) echo "Concurrency error" ;;
        61) echo "Content error occurred" ;;
        62) echo "Unsupported content type" ;;
        63) echo "Content size limit exceeded" ;;
        64) echo "Invalid content format" ;;
        65) echo "Invalid content encoding" ;;
        66) echo "Content parsing error" ;;
        67) echo "Content extraction error" ;;
        68) echo "Content analysis error" ;;
        69) echo "Content transformation error" ;;
        70) echo "Content validation error" ;;
        71) echo "Claude API error occurred" ;;
        72) echo "Invalid API key" ;;
        73) echo "API rate limit exceeded" ;;
        74) echo "API quota exceeded" ;;
        75) echo "API service unavailable" ;;
        76) echo "Invalid API response" ;;
        77) echo "Invalid API request" ;;
        78) echo "API request timeout" ;;
        79) echo "Model error" ;;
        80) echo "Token limit exceeded" ;;
        *)  echo "Error code $error_code occurred" ;;
    esac
}

# Export functions
export -f get_error_name
export -f get_error_message