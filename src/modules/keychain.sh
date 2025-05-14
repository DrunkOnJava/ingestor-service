#!/bin/bash
# Keychain integration module for secure credential management

# Load error handling module if not already loaded
if [[ -z "$ERROR_HANDLING_LOADED" ]]; then
    source "${PROJECT_ROOT}/src/modules/error_handling.sh"
    ERROR_HANDLING_LOADED=1
fi

# Service name used in the keychain
KEYCHAIN_SERVICE="ingestor-system"

# Check if keychain is available
keychain_available() {
    if command -v security &> /dev/null; then
        log_debug "Keychain is available (macOS security tool found)"
        return 0
    else
        log_debug "Keychain is not available (macOS security tool not found)"
        return 1
    fi
}

# Get a credential from the keychain
get_keychain_credential() {
    local credential_name="$1"
    local default_value="${2:-}"
    
    # Validate parameters
    require_variable "credential_name" "$credential_name" "Credential name is required" || return $ERR_VALIDATION
    
    if ! keychain_available; then
        log_warning "Keychain not available, returning default value"
        echo "$default_value"
        return $ERR_DEPENDENCY
    fi
    
    log_debug "Getting credential from keychain: $credential_name"
    
    # Use retry mechanism for potential transient keychain access issues
    local credential
    if ! credential=$(retry_command "security find-generic-password -a \"$USER\" -s \"${KEYCHAIN_SERVICE}-${credential_name}\" -w 2>/dev/null" 3 1); then
        # Security command failed or returned empty result
        log_debug "Credential not found in keychain: $credential_name"
        echo "$default_value"
        return $ERR_FILE
    fi
    
    if [[ -n "$credential" ]]; then
        # Successfully retrieved credential
        return 0
    else
        # Security command succeeded but returned empty string
        log_debug "Credential found but empty in keychain: $credential_name"
        echo "$default_value"
        return $ERR_FILE
    fi
    
    echo "$credential"
}

# Store a credential in the keychain
store_keychain_credential() {
    local credential_name="$1"
    local credential_value="$2"
    
    # Validate parameters
    require_variable "credential_name" "$credential_name" "Credential name is required" || return $ERR_VALIDATION
    require_variable "credential_value" "$credential_value" "Credential value is required" || return $ERR_VALIDATION
    
    if ! keychain_available; then
        log_error "Keychain not available, cannot store credential"
        return $ERR_DEPENDENCY
    fi
    
    log_debug "Storing credential in keychain: $credential_name"
    
    # First try to delete any existing credential (ignore errors)
    retry_command "security delete-generic-password -a \"$USER\" -s \"${KEYCHAIN_SERVICE}-${credential_name}\" &>/dev/null || true" 2 1
    
    # Add new credential with retry logic
    if retry_command "security add-generic-password -a \"$USER\" -s \"${KEYCHAIN_SERVICE}-${credential_name}\" -w \"$credential_value\"" 3 2; then
        log_info "Credential stored in keychain: $credential_name"
        return 0
    else
        log_error "Failed to store credential in keychain: $credential_name (after retries)"
        return $ERR_FILE
    fi
}

# Test if a credential exists in the keychain
keychain_credential_exists() {
    local credential_name="$1"
    
    # Validate parameters
    require_variable "credential_name" "$credential_name" "Credential name is required" || return $ERR_VALIDATION
    
    if ! keychain_available; then
        log_debug "Keychain not available, cannot check if credential exists"
        return $ERR_DEPENDENCY
    fi
    
    # Add retry logic for transient keychain access issues
    retry_command "security find-generic-password -a \"$USER\" -s \"${KEYCHAIN_SERVICE}-${credential_name}\" &>/dev/null" 2 1
}

# Get credential with interactive prompt if not found
get_credential_with_prompt() {
    local credential_name="$1"
    local prompt_message="$2"
    local default_value="${3:-}"
    local credential
    local retry_attempts=0
    local max_retries=3
    
    # Validate parameters
    require_variable "credential_name" "$credential_name" "Credential name is required" || return $ERR_VALIDATION
    require_variable "prompt_message" "$prompt_message" "Prompt message is required" || return $ERR_VALIDATION
    
    # First, try to get from keychain
    credential=$(get_keychain_credential "$credential_name" "")
    local keychain_status=$?
    
    # If not found or error occurred, prompt user
    if [[ -z "$credential" || $keychain_status -ne 0 ]]; then
        # If keychain error, let the user know
        if [[ $keychain_status -ne 0 && $keychain_status -ne $ERR_FILE ]]; then
            log_warning "Error accessing keychain (code: $keychain_status): $(get_error_description $keychain_status)"
        fi
        
        log_info "Credential '$credential_name' not found in keychain, prompting user"
        
        # Prompt with retry logic in case of empty input (if no default)
        while [[ $retry_attempts -lt $max_retries ]]; do
            echo -n "$prompt_message: "
            read -r credential
            
            # Use default if nothing entered
            if [[ -z "$credential" ]]; then
                if [[ -n "$default_value" ]]; then
                    log_debug "Using default value for '$credential_name'"
                    credential="$default_value"
                    break
                else
                    log_warning "Empty credential provided, please try again"
                    retry_attempts=$((retry_attempts + 1))
                    if [[ $retry_attempts -ge $max_retries ]]; then
                        log_error "Max retry attempts reached for credential input"
                        return $ERR_VALIDATION
                    fi
                    continue
                fi
            else
                # Non-empty credential provided
                break
            fi
        done
        
        # Store to keychain if provided
        if [[ -n "$credential" && "$credential" != "$default_value" ]]; then
            if store_keychain_credential "$credential_name" "$credential"; then
                log_info "Credential '$credential_name' stored in keychain"
            else
                log_warning "Failed to store credential in keychain, continuing with provided value"
            fi
        fi
    fi
    
    # Return the credential
    echo "$credential"
    
    if [[ -n "$credential" ]]; then
        return 0
    else
        return $ERR_VALIDATION
    fi
}

# Manage API key with keychain integration
manage_api_key() {
    local key_name="$1"
    local current_value="$2"
    local prompt_message="$3"
    
    # Validate parameters
    require_variable "key_name" "$key_name" "Key name is required" || return $ERR_VALIDATION
    require_variable "current_value" "$current_value" "Current value is required" || return $ERR_VALIDATION
    # prompt_message is optional if current_value is not KEYCHAIN
    
    # Check if value is KEYCHAIN
    if [[ "$current_value" == "KEYCHAIN" ]]; then
        # Validate prompt message if needed
        require_variable "prompt_message" "$prompt_message" "Prompt message is required for KEYCHAIN value" || return $ERR_VALIDATION
        
        # Try to get from keychain
        local keychain_value
        keychain_value=$(get_keychain_credential "$key_name" "")
        local keychain_status=$?
        
        if [[ -n "$keychain_value" && $keychain_status -eq 0 ]]; then
            log_debug "Retrieved $key_name from keychain"
            echo "$keychain_value"
            return 0
        else
            # Log detailed error if applicable
            if [[ $keychain_status -ne 0 && $keychain_status -ne $ERR_FILE ]]; then
                log_warning "Error accessing keychain (code: $keychain_status): $(get_error_description $keychain_status)"
            fi
            
            # Prompt if not found
            log_info "API key '$key_name' not found in keychain, prompting user"
            local new_value
            if ! new_value=$(get_credential_with_prompt "$key_name" "$prompt_message" ""); then
                log_error "Failed to get credential with prompt for $key_name"
                return $ERR_VALIDATION
            fi
            
            echo "$new_value"
            
            if [[ -n "$new_value" ]]; then
                return 0
            else
                return $ERR_VALIDATION
            fi
        fi
    else
        # Return existing value
        log_debug "Using provided value for $key_name (not using keychain)"
        echo "$current_value"
        return 0
    fi
}

# Setup initial keychain credentials
setup_keychain_credentials() {
    log_info "Setting up keychain credentials"
    
    # Check if keychain is available
    if ! keychain_available; then
        log_warning "Keychain is not available. Credentials will not be stored securely."
        return $ERR_DEPENDENCY
    fi
    
    local setup_success=true
    
    # Prompt for Claude API key if not already stored
    if ! keychain_credential_exists "claude_api_key"; then
        log_info "Claude API key setup required for content analysis"
        
        # Use get_credential_with_prompt for consistent error handling and retry logic
        local api_key
        if ! api_key=$(get_credential_with_prompt "claude_api_key" "Enter your Claude API key" ""); then
            log_error "Failed to obtain Claude API key"
            setup_success=false
        else
            if [[ -n "$api_key" ]]; then
                if ! store_keychain_credential "claude_api_key" "$api_key"; then
                    log_error "Failed to store Claude API key in keychain"
                    setup_success=false
                else
                    log_info "Claude API key stored in keychain"
                fi
            else
                log_warning "No API key provided, some features may not work properly"
                setup_success=false
            fi
        fi
    else
        log_info "Claude API key already exists in keychain"
        
        # Validate that the key is actually retrievable
        local api_key
        if ! api_key=$(get_keychain_credential "claude_api_key" ""); then
            log_warning "Claude API key exists but could not be retrieved, may need to be reset"
            setup_success=false
        else
            log_debug "Claude API key verified in keychain"
        fi
    fi
    
    # Add other credentials here if needed
    
    if $setup_success; then
        log_info "Keychain credential setup completed successfully"
        return 0
    else
        log_warning "Keychain credential setup completed with warnings or errors"
        return $ERR_GENERAL
    fi
}