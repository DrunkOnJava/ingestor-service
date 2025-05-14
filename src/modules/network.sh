#!/bin/bash
# Network operations module for ingestor system
# Provides robust networking functions with retry logic and error handling

# Source error handling module if not already sourced
if [[ -z "${ERROR_HANDLER_INITIALIZED+x}" ]]; then
    if [[ -f "${PROJECT_ROOT}/src/modules/error_handler.sh" ]]; then
        source "${PROJECT_ROOT}/src/modules/error_handler.sh"
        init_error_handler
    else
        echo "ERROR: Error handler module not found"
        exit 1
    fi
fi

# Initialize the network module
init_network() {
    log_info "Initializing network module"
    
    # Check for required dependencies
    if ! check_command "curl" "curl"; then
        handle_critical_error "curl command not found, required for network operations" 2
        return 1
    fi
    
    # Set default values if not already set
    NETWORK_TIMEOUT=${NETWORK_TIMEOUT:-30}
    NETWORK_MAX_RETRIES=${NETWORK_MAX_RETRIES:-3}
    NETWORK_RETRY_DELAY=${NETWORK_RETRY_DELAY:-2}
    NETWORK_USER_AGENT=${NETWORK_USER_AGENT:-"Ingestor/1.0"}
    
    log_debug "Network module initialized with timeout: ${NETWORK_TIMEOUT}s, retries: ${NETWORK_MAX_RETRIES}"
    return 0
}

# Make a HTTP GET request with robust error handling
http_get() {
    local url="$1"
    local output_file="${2:-}"
    local headers="${3:-}"
    
    if [[ -z "$url" ]]; then
        log_error "URL is required for http_get"
        return 1
    fi
    
    log_debug "Making HTTP GET request to: $url"
    
    # Construct curl command
    local curl_cmd="curl -s -S -L -A \"${NETWORK_USER_AGENT}\""
    
    # Add headers if provided
    if [[ -n "$headers" ]]; then
        # Parse headers string into individual -H arguments
        local IFS=','
        for header in $headers; do
            curl_cmd="$curl_cmd -H \"${header}\""
        done
    fi
    
    # Add output file if provided
    if [[ -n "$output_file" ]]; then
        # Create directory if it doesn't exist
        local output_dir
        output_dir=$(dirname "$output_file")
        if ! check_directory "$output_dir" "output directory"; then
            return 1
        fi
        curl_cmd="$curl_cmd -o \"${output_file}\""
    else
        # If no output file, print to stdout
        curl_cmd="$curl_cmd -o -"
    fi
    
    # Add error reporting and timeouts
    curl_cmd="$curl_cmd -f --connect-timeout 10 --max-time ${NETWORK_TIMEOUT}"
    
    # Add URL
    curl_cmd="$curl_cmd \"${url}\""
    
    # Execute with retry mechanism
    if retry_command "$curl_cmd" "${NETWORK_MAX_RETRIES}" "${NETWORK_RETRY_DELAY}" "${NETWORK_TIMEOUT}" "HTTP GET request to ${url}"; then
        log_debug "HTTP GET request successful: $url"
        return 0
    else
        local exit_code=$?
        log_error "HTTP GET request failed with code $exit_code: $url"
        
        # Check specific error codes
        case $exit_code in
            6)  log_error "Could not resolve host: $url" ;;
            7)  log_error "Failed to connect to host: $url" ;;
            22) log_error "HTTP error response (4xx/5xx): $url" ;;
            28) log_error "Operation timed out: $url" ;;
            *)  log_error "Unknown error: $url" ;;
        esac
        
        return $exit_code
    fi
}

# Make a HTTP POST request with robust error handling
http_post() {
    local url="$1"
    local data="$2"
    local output_file="${3:-}"
    local headers="${4:-}"
    local content_type="${5:-application/json}"
    
    if [[ -z "$url" ]]; then
        log_error "URL is required for http_post"
        return 1
    fi
    
    log_debug "Making HTTP POST request to: $url"
    
    # Construct curl command
    local curl_cmd="curl -s -S -L -X POST -A \"${NETWORK_USER_AGENT}\""
    
    # Add content type header
    curl_cmd="$curl_cmd -H \"Content-Type: ${content_type}\""
    
    # Add headers if provided
    if [[ -n "$headers" ]]; then
        # Parse headers string into individual -H arguments
        local IFS=','
        for header in $headers; do
            curl_cmd="$curl_cmd -H \"${header}\""
        done
    fi
    
    # Add data if provided
    if [[ -n "$data" ]]; then
        if [[ -f "$data" ]]; then
            # If data is a file, use --data-binary @file
            curl_cmd="$curl_cmd --data-binary @\"${data}\""
        else
            # Otherwise use -d for string data
            curl_cmd="$curl_cmd -d '${data}'"
        fi
    fi
    
    # Add output file if provided
    if [[ -n "$output_file" ]]; then
        # Create directory if it doesn't exist
        local output_dir
        output_dir=$(dirname "$output_file")
        if ! check_directory "$output_dir" "output directory"; then
            return 1
        fi
        curl_cmd="$curl_cmd -o \"${output_file}\""
    else
        # If no output file, print to stdout
        curl_cmd="$curl_cmd -o -"
    fi
    
    # Add error reporting and timeouts
    curl_cmd="$curl_cmd -f --connect-timeout 10 --max-time ${NETWORK_TIMEOUT}"
    
    # Add URL
    curl_cmd="$curl_cmd \"${url}\""
    
    # Execute with retry mechanism
    if retry_command "$curl_cmd" "${NETWORK_MAX_RETRIES}" "${NETWORK_RETRY_DELAY}" "${NETWORK_TIMEOUT}" "HTTP POST request to ${url}"; then
        log_debug "HTTP POST request successful: $url"
        return 0
    else
        local exit_code=$?
        log_error "HTTP POST request failed with code $exit_code: $url"
        
        # Check specific error codes
        case $exit_code in
            6)  log_error "Could not resolve host: $url" ;;
            7)  log_error "Failed to connect to host: $url" ;;
            22) log_error "HTTP error response (4xx/5xx): $url" ;;
            28) log_error "Operation timed out: $url" ;;
            *)  log_error "Unknown error: $url" ;;
        esac
        
        return $exit_code
    fi
}

# Download a file with progress reporting
download_file() {
    local url="$1"
    local output_file="$2"
    local show_progress="${3:-true}"
    
    if [[ -z "$url" || -z "$output_file" ]]; then
        log_error "URL and output file are required for download_file"
        return 1
    fi
    
    log_info "Downloading file from $url to $output_file"
    
    # Create directory if it doesn't exist
    local output_dir
    output_dir=$(dirname "$output_file")
    if ! check_directory "$output_dir" "output directory"; then
        return 1
    fi
    
    # Construct curl command
    local curl_cmd="curl -L -A \"${NETWORK_USER_AGENT}\" --connect-timeout 10 --max-time ${NETWORK_TIMEOUT}"
    
    # Add progress reporting if requested
    if [[ "$show_progress" == "true" ]]; then
        if [[ -t 1 ]]; then  # Check if stdout is a terminal
            curl_cmd="$curl_cmd --progress-bar"
        else
            # If not a terminal, provide progress in a way that works for logs
            curl_cmd="$curl_cmd -v"
        fi
    else
        curl_cmd="$curl_cmd -s -S"
    fi
    
    # Use resume option (-C -) to continue interrupted downloads
    curl_cmd="$curl_cmd -C - -o \"${output_file}\" \"${url}\""
    
    # Execute with retry mechanism
    begin_transaction "download_file"
    
    # Create a temporary file for download to avoid incomplete files
    local temp_file="${output_file}.download"
    local final_cmd="${curl_cmd//${output_file}/${temp_file}}"
    
    if retry_command "$final_cmd" "${NETWORK_MAX_RETRIES}" "${NETWORK_RETRY_DELAY}" "${NETWORK_TIMEOUT}" "Download from ${url}"; then
        # Verify file was downloaded
        if [[ -f "$temp_file" ]]; then
            # Check if file is not empty
            if [[ -s "$temp_file" ]]; then
                # Move temporary file to final destination
                if mv "$temp_file" "$output_file"; then
                    log_info "Download completed successfully: $output_file"
                    end_transaction
                    return 0
                else
                    fail_transaction "Failed to move temporary file to final destination"
                    log_error "Failed to move temporary file to final destination"
                    end_transaction
                    return 1
                fi
            else
                fail_transaction "Downloaded file is empty"
                log_error "Downloaded file is empty: $temp_file"
                rm -f "$temp_file"
                end_transaction
                return 1
            fi
        else
            fail_transaction "Temporary file not created"
            log_error "Temporary file not created: $temp_file"
            end_transaction
            return 1
        fi
    else
        fail_transaction "Download failed"
        rm -f "$temp_file"
        log_error "Failed to download file from $url"
        end_transaction
        return 1
    fi
}

# Check if a URL is accessible
check_url() {
    local url="$1"
    local timeout="${2:-5}"
    
    if [[ -z "$url" ]]; then
        log_error "URL is required for check_url"
        return 1
    fi
    
    log_debug "Checking URL accessibility: $url"
    
    # Use curl to check URL
    local curl_cmd="curl -s -S -L -o /dev/null -w '%{http_code}' --connect-timeout ${timeout} --max-time ${timeout} \"${url}\""
    
    # Execute command
    local http_code
    http_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
    
    # Check HTTP status code
    if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
        log_debug "URL is accessible: $url (HTTP $http_code)"
        return 0
    else
        log_warning "URL is not accessible: $url (HTTP $http_code)"
        return 1
    fi
}

# Check if network is available
check_network() {
    local test_url="${1:-https://www.google.com}"
    local timeout="${2:-5}"
    
    log_debug "Checking network connectivity using $test_url"
    
    if check_url "$test_url" "$timeout"; then
        log_info "Network is available"
        return 0
    else
        log_warning "Network is not available"
        return 1
    fi
}

# Export functions
export -f http_get
export -f http_post
export -f download_file
export -f check_url
export -f check_network