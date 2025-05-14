#!/usr/bin/env bats
# Unit tests for the config.sh module

# Load the test helper
load '../test_helper'

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # TEST_TEMP_DIR is now set and created by setup_test_environment
    
    # Set up mock variables with absolute paths
    export CONFIG_DIR="${TEST_TEMP_DIR}/config"
    export DATABASE_PROFILES_DIR="${CONFIG_DIR}/databases"
    export CONFIG_FILE="${CONFIG_DIR}/settings.yml"
    # Use a distinct variable name to avoid conflicts with the real PROJECT_ROOT
    export TEST_PROJECT_DIR="${TEST_TEMP_DIR}/project"
    
    # Create necessary directories with proper debugging
    echo "Creating directories: CONFIG_DIR=${CONFIG_DIR}, DATABASE_PROFILES_DIR=${DATABASE_PROFILES_DIR}, TEST_PROJECT_DIR=${TEST_PROJECT_DIR}" >&2
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${DATABASE_PROFILES_DIR}"
    mkdir -p "${TEST_PROJECT_DIR}/src/modules"
    
    # Debug check
    if [[ ! -d "${TEST_PROJECT_DIR}/src/modules" ]]; then
        echo "Error: Failed to create ${TEST_PROJECT_DIR}/src/modules directory" >&2
        return 1
    fi
    
    # Create a mock logging module with mock functions
    mkdir -p "${TEST_PROJECT_DIR}/src/modules"
    cat > "${TEST_PROJECT_DIR}/src/modules/logging.sh" << 'EOF'
#!/bin/bash
# Mock logging module for testing

log_debug() {
    echo "[DEBUG] $*" >/dev/null
}

log_info() {
    echo "[INFO] $*" >/dev/null
}

log_warning() {
    echo "[WARNING] $*" >/dev/null
}

log_error() {
    echo "[ERROR] $*" >/dev/null
}
EOF
    
    # Source the mock logging module
    source "${TEST_PROJECT_DIR}/src/modules/logging.sh"
    
    # Create a mock keychain module
    cat > "${TEST_PROJECT_DIR}/src/modules/keychain.sh" << 'EOF'
#!/bin/bash
# Mock keychain module for testing

# Service name used in the keychain
KEYCHAIN_SERVICE="ingestor-system"

keychain_available() {
    return 0
}

get_keychain_credential() {
    local credential_name="$1"
    local default_value="${2:-}"
    
    if [[ "$credential_name" == "claude_api_key" ]]; then
        echo "mock_api_key_from_keychain"
        return 0
    fi
    
    echo "$default_value"
    return 1
}

store_keychain_credential() {
    local credential_name="$1"
    local credential_value="$2"
    return 0
}

keychain_credential_exists() {
    local credential_name="$1"
    
    if [[ "$credential_name" == "claude_api_key" ]]; then
        return 0
    fi
    return 1
}

get_credential_with_prompt() {
    local credential_name="$1"
    local prompt_message="$2"
    local default_value="${3:-}"
    
    echo "mock_prompted_credential"
    return 0
}

manage_api_key() {
    local key_name="$1"
    local current_value="$2"
    local prompt_message="$3"
    
    if [[ "$current_value" == "KEYCHAIN" ]]; then
        echo "mock_keychain_api_key"
        return 0
    else
        echo "$current_value"
        return 0
    fi
}
EOF
    
    # No need to create additional directories, they're created above
    
    # Create a copy of the config module to test
    cat > "${TEST_PROJECT_DIR}/src/modules/config.sh" << EOF
#!/bin/bash
# Configuration module for ingestor

# Global config variables - using the variables from parent shell
CONFIG_DIR="${CONFIG_DIR}"
DATABASE_PROFILES_DIR="${DATABASE_PROFILES_DIR}"
CONFIG_FILE="${CONFIG_FILE}"
CLAUDE_API_KEY=""
DEFAULT_DATABASE=""
LOG_LEVEL="info"

# Load configuration
load_config() {
    log_debug "Loading configuration from: $CONFIG_FILE"
    
    # Create default config if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "Config file not found, creating default configuration"
        create_default_config
    fi
    
    # Parse YAML configuration
    # This is a simplified version - for production you'd want to use a proper YAML parser
    # or convert YAML to JSON and use jq
    
    # Read API key
    CLAUDE_API_KEY=$(grep "claude_api_key:" "$CONFIG_FILE" | cut -d ':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Use keychain module to manage API key
    if [[ -f "${TEST_PROJECT_DIR}/src/modules/keychain.sh" ]]; then
        # Only source if we haven't already
        if [[ -z "$KEYCHAIN_LOADED" ]]; then
            source "${TEST_PROJECT_DIR}/src/modules/keychain.sh"
            KEYCHAIN_LOADED=1
        fi
        
        # Manage API key with keychain integration
        CLAUDE_API_KEY=$(manage_api_key "claude_api_key" "$CLAUDE_API_KEY" "Enter your Claude API key")
    else
        # Fallback to the old method if keychain module is not available
        if [[ "$CLAUDE_API_KEY" == "KEYCHAIN" ]]; then
            if command -v security &> /dev/null; then
                CLAUDE_API_KEY=$(security find-generic-password -a "$USER" -s "ingestor-system-claude_api_key" -w 2>/dev/null)
            fi
        fi
    fi
    
    # Read default database
    DEFAULT_DATABASE=$(grep "default_database:" "$CONFIG_FILE" | cut -d ':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Read log level
    config_log_level=$(grep "log_level:" "$CONFIG_FILE" | cut -d ':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$config_log_level" ]]; then
        LOG_LEVEL="$config_log_level"
    fi
    
    log_debug "Configuration loaded successfully"
}

# Create default configuration file
create_default_config() {
    local config_dir="${CONFIG_DIR}"
    local db_profiles_dir="${DATABASE_PROFILES_DIR}"
    local config_file="${CONFIG_FILE}"
    
    log_debug "Creating default configuration (config_dir: $config_dir)"
    
    # Create config directory if it doesn't exist
    mkdir -p "$config_dir"
    mkdir -p "$db_profiles_dir"
    
    # Create default settings file
    cat > "$config_file" << EOF
# Ingestor Configuration

# Claude API Key (or use KEYCHAIN to retrieve from system keychain)
claude_api_key: KEYCHAIN

# Default database to use if none specified
default_database: general

# Log level (debug, info, warning, error)
log_level: info

# Content processing settings
content:
  # Maximum file size in bytes for direct processing
  max_file_size: 10485760 # 10MB
  
  # Chunk size for large files
  chunk_size: 524288 # 512KB
  
  # Temporary file handling
  keep_temp_files: false

# Database settings
database:
  # Directory for database files relative to ~/.ingestor
  directory: databases
  
  # Whether to compress databases automatically
  auto_vacuum: true
  
  # Journal mode for databases
  journal_mode: WAL

# Claude integration settings
claude:
  # Model to use
  model: claude-3-opus-20240229
  
  # Maximum tokens per request
  max_tokens: 4096
  
  # Temperature for generation
  temperature: 0.7
  
  # Request timeout in seconds
  timeout: 60
  
  # Maximum retries on failure
  max_retries: 3
EOF
    
    # Create a default general database profile
    cat > "${db_profiles_dir}/general.yml" << EOF
# General content database profile

name: General Content Database
description: A general-purpose database for mixed content types

# Content types to process
content_types:
  - text/plain
  - image/*
  - video/*
  - application/pdf
  
# Extraction focus
extraction:
  # General topics of interest
  topics:
    - general knowledge
    - factual information
    - key concepts
  
  # Entities to extract
  entities:
    - people
    - places
    - organizations
    - dates
    - events
  
  # Metadata to extract
  metadata:
    - title
    - summary
    - creation_date
    - categories
    - keywords
EOF
    
    log_info "Default configuration created at: $CONFIG_FILE"
}

# Get database profile
get_database_profile() {
    local db_name="$1"
    local profile_file="${DATABASE_PROFILES_DIR}/${db_name}.yml"
    
    if [[ ! -f "$profile_file" ]]; then
        log_warning "Database profile not found for: $db_name"
        return 1
    fi
    
    echo "$profile_file"
}
    
    # Source the config module
    source "${TEST_PROJECT_DIR}/src/modules/config.sh"

# Teardown - runs after each test
teardown() {
    # Call the common teardown
    teardown_test_environment
}

# Test config file creation
@test "create_default_config creates the config directories and files" {
    # Make sure the temp dir is available
    mkdir -p "${TEST_TEMP_DIR}/config"
    
    create_default_config
    
    # Check if directories were created
    assert_dir_exists "${TEST_TEMP_DIR}/config"
    assert_dir_exists "${TEST_TEMP_DIR}/config/databases"
    
    # Check if config file was created - using assertions
    assert_file_exists "${TEST_TEMP_DIR}/config/settings.yml"
    
    # Check if database profile was created - using assertions
    assert_file_exists "${TEST_TEMP_DIR}/config/databases/general.yml"
    
    # Check content of config file
    run grep "claude_api_key: KEYCHAIN" "${TEST_TEMP_DIR}/config/settings.yml"
    assert_success
    
    run grep "default_database: general" "${TEST_TEMP_DIR}/config/settings.yml"
    assert_success
    
    run grep "log_level: info" "${TEST_TEMP_DIR}/config/settings.yml"
    assert_success
}

# Test load_config with existing config
@test "load_config loads existing configuration correctly" {
    # Create a custom config file
    mkdir -p "${TEST_TEMP_DIR}/config"
    cat > "${TEST_TEMP_DIR}/config/settings.yml" << 'EOFCUSTOM'
# Custom Ingestor Configuration
claude_api_key: test_api_key
default_database: custom_db
log_level: debug
EOFCUSTOM
    
    # Run load_config
    run load_config
    assert_success
    
    # Check if values were loaded correctly
    assert_equal "$CLAUDE_API_KEY" "test_api_key"
    assert_equal "$DEFAULT_DATABASE" "custom_db"
    assert_equal "$LOG_LEVEL" "debug"
}

# Test load_config with KEYCHAIN api key
@test "load_config retrieves API key from keychain when configured" {
    # Create a config file with KEYCHAIN setting
    mkdir -p "${TEST_TEMP_DIR}/config"
    cat > "${TEST_TEMP_DIR}/config/settings.yml" << 'EOFKEYCHAIN'
# Keychain Ingestor Configuration
claude_api_key: KEYCHAIN
default_database: general
log_level: info
EOFKEYCHAIN
    
    # Run load_config
    run load_config
    assert_success
    
    # Check if API key was retrieved from keychain
    assert_equal "$CLAUDE_API_KEY" "mock_keychain_api_key"
}

# Test get_database_profile with existing profile
@test "get_database_profile returns path for existing profile" {
    # Create a database profile
    mkdir -p "${TEST_TEMP_DIR}/config/databases"
    touch "${TEST_TEMP_DIR}/config/databases/test_db.yml"
    
    # Call get_database_profile
    run get_database_profile "test_db"
    assert_success
    
    # Check if the correct path was returned
    assert_output "${TEST_TEMP_DIR}/config/databases/test_db.yml"
}

# Test get_database_profile with missing profile
@test "get_database_profile fails for missing profile" {
    # Call get_database_profile with non-existent profile
    run get_database_profile "missing_db"
    assert_failure
}

# Test load_config with missing config creates default config
@test "load_config creates default config when file missing" {
    # Ensure config file doesn't exist
    rm -f "${TEST_TEMP_DIR}/config/settings.yml" || true
    
    # Run load_config
    run load_config
    assert_success
    
    # Check if config file was created
    assert_file_exists "${TEST_TEMP_DIR}/config/settings.yml"
    
    # Verify default values were loaded
    assert_equal "$CLAUDE_API_KEY" "mock_keychain_api_key" # Since default is KEYCHAIN which gets transformed
    assert_equal "$DEFAULT_DATABASE" "general"
    assert_equal "$LOG_LEVEL" "info"
}

# Test load_config loads different log levels correctly
@test "load_config properly sets different log levels" {
    # Test various log levels
    for level in debug info warning error; do
        # Create config file with specific log level
        mkdir -p "${TEST_TEMP_DIR}/config"
        cat > "${TEST_TEMP_DIR}/config/settings.yml" << EOF
# Log Level Test Configuration
claude_api_key: test_api_key
default_database: general
log_level: $level
EOF
        
        # Run load_config
        LOG_LEVEL="default" # Reset to ensure it's changed
        run load_config
        assert_success
        
        # Verify log level was set correctly
        assert_equal "$LOG_LEVEL" "$level"
    done
}