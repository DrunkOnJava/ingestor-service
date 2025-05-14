#!/bin/bash
# Credential management module for ingestor

# Manage credentials interactively
manage_credentials_interactive() {
    echo "===== Ingestor Credential Management ====="
    
    # Check if keychain is available
    if ! keychain_available; then
        echo "Warning: Keychain is not available on this system."
        echo "Credentials will not be stored securely."
        echo
    fi
    
    while true; do
        echo
        echo "Available options:"
        echo "1. Set Claude API key"
        echo "2. Test Claude API connection"
        echo "3. View credentials status"
        echo "4. Exit"
        echo
        
        read -rp "Select an option (1-4): " choice
        
        case "$choice" in
            1)
                set_claude_api_key_interactive
                ;;
            2)
                test_claude_api_connection
                ;;
            3)
                view_credentials_status
                ;;
            4)
                echo "Exiting credential management."
                return 0
                ;;
            *)
                echo "Invalid option. Please select 1-4."
                ;;
        esac
    done
}

# Set Claude API key interactively
set_claude_api_key_interactive() {
    echo
    echo "===== Set Claude API Key ====="
    
    # Check if API key already exists in keychain
    local current_key
    if keychain_available && keychain_credential_exists "claude_api_key"; then
        echo "A Claude API key is already stored in the keychain."
        read -rp "Do you want to replace it? (y/N): " confirm
        
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "Operation cancelled."
            return
        fi
        
        current_key=$(get_keychain_credential "claude_api_key" "")
        if [[ -n "$current_key" ]]; then
            echo "Current key: ${current_key:0:4}...${current_key: -4}"
        fi
    fi
    
    # Get new API key
    echo
    echo "Enter your Claude API key (input will be hidden):"
    read -rs api_key
    
    if [[ -z "$api_key" ]]; then
        echo "No API key provided. Operation cancelled."
        return
    fi
    
    # Store the key
    if keychain_available; then
        if store_keychain_credential "claude_api_key" "$api_key"; then
            echo "API key stored successfully in the keychain."
            
            # Update config file to use keychain
            update_config_for_keychain
        else
            echo "Failed to store API key in keychain."
            
            # Offer to store in config file
            echo
            read -rp "Do you want to store the API key in the config file? (not recommended) (y/N): " confirm
            
            if [[ "$confirm" =~ ^[Yy] ]]; then
                store_key_in_config "$api_key"
            else
                echo "API key not stored."
            fi
        fi
    else
        # Store in config file
        store_key_in_config "$api_key"
    fi
}

# Test Claude API connection
test_claude_api_connection() {
    echo
    echo "===== Testing Claude API Connection ====="
    
    # Initialize Claude API
    if ! init_claude; then
        echo "Failed to initialize Claude API. Check your API key."
        return 1
    fi
    
    # Create a simple test prompt
    local test_content="Hello, this is a test."
    local test_prompt="text"
    
    echo "Sending test request to Claude API..."
    local response
    
    # Capture start time
    local start_time
    start_time=$(date +%s)
    
    # Make API call
    response=$(claude_api_call "$test_content" "$test_prompt" 1 1)
    local status=$?
    
    # Capture end time
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    if [[ $status -eq 0 && -n "$response" ]]; then
        echo "✅ Claude API connection successful! (${elapsed}s)"
        echo
        echo "Response excerpt:"
        echo "${response:0:100}..."
    else
        echo "❌ Claude API connection failed."
        echo "Please check your API key and internet connection."
    fi
}

# View credentials status
view_credentials_status() {
    echo
    echo "===== Credentials Status ====="
    
    # Check keychain status
    echo "Keychain availability: $(keychain_available && echo "Available" || echo "Not available")"
    
    # Check Claude API key
    local config_key
    config_key=$(grep "claude_api_key:" "$CONFIG_FILE" | cut -d ':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "Claude API key in config: $(
        if [[ -z "$config_key" ]]; then 
            echo "Not set"
        elif [[ "$config_key" == "KEYCHAIN" ]]; then
            echo "Using keychain"
        else
            echo "Set directly (${#config_key} characters)"
        fi
    )"
    
    # Check keychain status
    if keychain_available; then
        echo "Claude API key in keychain: $(
            if keychain_credential_exists "claude_api_key"; then
                local key
                key=$(get_keychain_credential "claude_api_key" "")
                if [[ -n "$key" ]]; then
                    echo "Stored (${key:0:4}...${key: -4})"
                else
                    echo "Error retrieving"
                fi
            else
                echo "Not stored"
            fi
        )"
    fi
    
    # Show current status
    local current_key="$CLAUDE_API_KEY"
    echo "Currently loaded API key: $(
        if [[ -n "$current_key" ]]; then
            echo "Loaded (${current_key:0:4}...${current_key: -4})"
        else
            echo "Not loaded"
        fi
    )"
}

# Update config file to use keychain
update_config_for_keychain() {
    # Check if config already uses keychain
    local current_setting
    current_setting=$(grep "claude_api_key:" "$CONFIG_FILE" | cut -d ':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [[ "$current_setting" == "KEYCHAIN" ]]; then
        # Already set to use keychain
        return 0
    fi
    
    # Create a backup of the config file
    local backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    
    # Update the config file
    sed -i.tmp "s/claude_api_key:.*$/claude_api_key: KEYCHAIN/" "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.tmp"
    
    echo "Updated config file to use keychain for Claude API key."
    echo "Backup created at: $backup_file"
}

# Store API key directly in config file
store_key_in_config() {
    local api_key="$1"
    
    # Create a backup of the config file
    local backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    
    # Update the config file
    sed -i.tmp "s/claude_api_key:.*$/claude_api_key: $api_key/" "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.tmp"
    
    echo "API key stored in config file."
    echo "Backup created at: $backup_file"
    echo "Warning: Storing API keys in plain text is not recommended."
}