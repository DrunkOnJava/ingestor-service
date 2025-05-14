#!/bin/bash
# Configuration module for ingestor

# Global config variables
CONFIG_FILE="${CONFIG_DIR}/settings.yml"
DATABASE_PROFILES_DIR="${CONFIG_DIR}/databases"
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
    if [[ -f "${PROJECT_ROOT}/src/modules/keychain.sh" ]]; then
        # Only source if we haven't already
        if [[ -z "$KEYCHAIN_LOADED" ]]; then
            source "${PROJECT_ROOT}/src/modules/keychain.sh"
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
    log_debug "Creating default configuration"
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATABASE_PROFILES_DIR"
    
    # Create default settings file
    cat > "$CONFIG_FILE" << EOF
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
    mkdir -p "$DATABASE_PROFILES_DIR"
    cat > "${DATABASE_PROFILES_DIR}/general.yml" << EOF
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