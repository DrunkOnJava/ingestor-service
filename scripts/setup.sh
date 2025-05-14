#!/bin/bash
# Setup script for ingestor system
# Creates initial directory structure and configuration

set -euo pipefail

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
RESET="\033[0m"

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config"

# User home directory for ingestor
INGESTOR_HOME="${HOME}/.ingestor"
INGESTOR_CONFIG="${INGESTOR_HOME}/config"
INGESTOR_DATABASES="${INGESTOR_HOME}/databases"
INGESTOR_LOGS="${INGESTOR_HOME}/logs"
INGESTOR_TEMP="${INGESTOR_HOME}/tmp"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}     Ingestor System - Initial Setup               ${RESET}"
echo -e "${GREEN}====================================================${RESET}"
echo

# Check if dependencies are installed
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${RESET}"
    
    local missing_deps=0
    
    # List of required commands
    local required_commands=(
        "sqlite3"
        "jq"
        "curl"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed.${RESET}"
            missing_deps=$((missing_deps + 1))
        else
            echo -e "${GREEN}✓ $cmd installed${RESET}"
        fi
    done
    
    if [[ $missing_deps -gt 0 ]]; then
        echo
        echo -e "${YELLOW}Please install the missing dependencies and run this script again.${RESET}"
        echo
        echo -e "On macOS, you can install them with:\n  brew install sqlite jq curl"
        echo -e "On Ubuntu, you can install them with:\n  sudo apt-get install sqlite3 jq curl"
        exit 1
    fi
    
    echo -e "${GREEN}All dependencies are installed.${RESET}"
    echo
}

# Create directory structure
create_directories() {
    echo -e "${BLUE}Creating directory structure...${RESET}"
    
    mkdir -p "${INGESTOR_CONFIG}"
    mkdir -p "${INGESTOR_CONFIG}/databases"
    mkdir -p "${INGESTOR_DATABASES}"
    mkdir -p "${INGESTOR_LOGS}"
    mkdir -p "${INGESTOR_TEMP}"
    
    echo -e "${GREEN}Directory structure created at $INGESTOR_HOME${RESET}"
    echo
}

# Create default configuration
create_default_config() {
    echo -e "${BLUE}Creating default configuration...${RESET}"
    
    # Create settings.yml
    cat > "${INGESTOR_CONFIG}/settings.yml" << EOF
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
    
    # Create default database profile
    cat > "${INGESTOR_CONFIG}/databases/general.yml" << EOF
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
    
    # Create research database profile
    cat > "${INGESTOR_CONFIG}/databases/research.yml" << EOF
# Research database profile

name: Research Database
description: Specialized database for research papers and academic content

# Content types to process
content_types:
  - text/plain
  - application/pdf
  - application/msword
  
# Extraction focus
extraction:
  # General topics of interest
  topics:
    - research methodology
    - scientific findings
    - academic citations
  
  # Entities to extract
  entities:
    - authors
    - institutions
    - dates
    - citations
  
  # Metadata to extract
  metadata:
    - title
    - abstract
    - publication_date
    - keywords
EOF
    
    # Create code database profile
    cat > "${INGESTOR_CONFIG}/databases/code.yml" << EOF
# Code database profile

name: Code Database
description: Specialized database for code and technical content

# Content types to process
content_types:
  - text/x-python
  - text/x-c
  - text/x-java
  - text/x-javascript
  - text/x-typescript
  - application/json
  - application/xml
  
# Extraction focus
extraction:
  # General topics of interest
  topics:
    - algorithms
    - data structures
    - design patterns
    - architecture
  
  # Entities to extract
  entities:
    - functions
    - classes
    - methods
    - variables
    - imports
  
  # Metadata to extract
  metadata:
    - language
    - complexity
    - dependencies
    - author
    - license
EOF
    
    echo -e "${GREEN}Default configuration created.${RESET}"
    echo
}

# Initialize default databases
initialize_databases() {
    echo -e "${BLUE}Initializing databases...${RESET}"
    
    # Copy schema files from project
    cp -r "${CONFIG_DIR}/schemas/"* "${INGESTOR_CONFIG}/schemas/"
    
    # Initialize general database
    sqlite3 "${INGESTOR_DATABASES}/general.sqlite" < "${INGESTOR_CONFIG}/schemas/general.sql"
    echo -e "${GREEN}✓ Initialized general database${RESET}"
    
    # Initialize research database
    sqlite3 "${INGESTOR_DATABASES}/research.sqlite" < "${INGESTOR_CONFIG}/schemas/general.sql"
    echo -e "${GREEN}✓ Initialized research database${RESET}"
    
    # Initialize code database
    sqlite3 "${INGESTOR_DATABASES}/code.sqlite" < "${INGESTOR_CONFIG}/schemas/general.sql"
    echo -e "${GREEN}✓ Initialized code database${RESET}"
    
    echo -e "${GREEN}All databases initialized.${RESET}"
    echo
}

# Set up MCP server integration
setup_mcp_server() {
    echo -e "${BLUE}Setting up MCP server integration...${RESET}"
    
    # Determine Claude CLI config directory
    local claude_mcp_dir="${HOME}/.claude/mcp/servers"
    if [[ -d "${HOME}/.config/claude/mcp/servers" ]]; then
        claude_mcp_dir="${HOME}/.config/claude/mcp/servers"
    elif [[ ! -d "${claude_mcp_dir}" ]]; then
        mkdir -p "${claude_mcp_dir}"
    fi
    
    # Create MCP server config
    local mcp_config_file="${claude_mcp_dir}/ingestor.json"
    
    cat > "${mcp_config_file}" << EOF
{
  "name": "ingestor",
  "command": "${PROJECT_ROOT}/scripts/start_mcp_server.sh",
  "args": [],
  "env": {
    "INGESTOR_MCP_MODE": "true",
    "INGESTOR_CONFIG_DIR": "${INGESTOR_CONFIG}",
    "INGESTOR_HOME": "${INGESTOR_HOME}"
  },
  "transport": "stdio",
  "disabled": false,
  "autoApprove": ["*"],
  "description": "Content ingestion system for Claude integration",
  "errorHandling": {
    "maxRetries": 3,
    "retryDelay": 2000,
    "timeout": 15000
  },
  "logging": {
    "level": "info",
    "file": "${INGESTOR_LOGS}/mcp-server.log"
  }
}
EOF
    
    # Create HTTP variant
    local mcp_http_config_file="${claude_mcp_dir}/ingestor-http.json"
    
    cat > "${mcp_http_config_file}" << EOF
{
  "name": "ingestor-http",
  "command": "${PROJECT_ROOT}/scripts/start_mcp_server.sh",
  "args": ["--http", "--port", "8765"],
  "env": {
    "INGESTOR_MCP_MODE": "true",
    "INGESTOR_CONFIG_DIR": "${INGESTOR_CONFIG}",
    "INGESTOR_HOME": "${INGESTOR_HOME}"
  },
  "transport": "http",
  "url": "http://localhost:8765",
  "disabled": false,
  "autoApprove": ["*"],
  "description": "Content ingestion system for Claude integration (HTTP)",
  "errorHandling": {
    "maxRetries": 3,
    "retryDelay": 2000,
    "timeout": 15000
  },
  "logging": {
    "level": "info",
    "file": "${INGESTOR_LOGS}/mcp-http-server.log"
  }
}
EOF
    
    echo -e "${GREEN}MCP server configuration created at:${RESET}"
    echo -e "  ${YELLOW}${mcp_config_file}${RESET}"
    echo -e "  ${YELLOW}${mcp_http_config_file}${RESET}"
    echo
}

# Configure API key (optional)
configure_api_key() {
    echo -e "${BLUE}Configuring Claude API key...${RESET}"
    
    # Check if keychain is available (macOS)
    if command -v security &> /dev/null; then
        echo -e "${YELLOW}macOS Keychain detected.${RESET}"
        echo -e "Would you like to store your Claude API key in the Keychain? (y/n) "
        read -r use_keychain
        
        if [[ "$use_keychain" =~ ^[Yy]$ ]]; then
            echo -e "Enter your Claude API key (will not be displayed): "
            read -rs api_key
            
            # Delete any existing entry
            security delete-generic-password -a "$USER" -s "ingestor-system-claude_api_key" 2>/dev/null || true
            
            # Store the API key
            security add-generic-password -a "$USER" -s "ingestor-system-claude_api_key" -w "$api_key"
            
            echo -e "${GREEN}API key stored in Keychain.${RESET}"
            
            # Update config to use keychain
            sed -i'.bak' 's/^claude_api_key:.*/claude_api_key: KEYCHAIN/' "${INGESTOR_CONFIG}/settings.yml"
            rm -f "${INGESTOR_CONFIG}/settings.yml.bak"
        else
            echo -e "Enter your Claude API key (will not be displayed): "
            read -rs api_key
            
            # Update config with the API key
            sed -i'.bak' "s/^claude_api_key:.*/claude_api_key: $api_key/" "${INGESTOR_CONFIG}/settings.yml"
            rm -f "${INGESTOR_CONFIG}/settings.yml.bak"
            
            echo -e "${YELLOW}API key stored directly in configuration file.${RESET}"
            echo -e "${YELLOW}Note: This is less secure than using the Keychain.${RESET}"
        fi
    else
        # Non-macOS systems
        echo -e "${YELLOW}Keychain not available on this system.${RESET}"
        echo -e "Enter your Claude API key (will not be displayed): "
        read -rs api_key
        
        # Update config with the API key
        sed -i'.bak' "s/^claude_api_key:.*/claude_api_key: $api_key/" "${INGESTOR_CONFIG}/settings.yml"
        rm -f "${INGESTOR_CONFIG}/settings.yml.bak" 2>/dev/null || true
        
        echo -e "${YELLOW}API key stored directly in configuration file.${RESET}"
        echo -e "${YELLOW}Warning: This method is less secure.${RESET}"
    fi
    
    echo
}

# Main function
main() {
    # Check dependencies
    check_dependencies
    
    # Create directories
    create_directories
    
    # Create default configuration
    create_default_config
    
    # Set up MCP server
    setup_mcp_server
    
    # Configure API key (optional)
    if [[ "${1:-}" != "--no-api-key" ]]; then
        configure_api_key
    fi
    
    # Initialize databases
    initialize_databases
    
    echo -e "${GREEN}====================================================${RESET}"
    echo -e "${GREEN}     Ingestor System Setup Complete!               ${RESET}"
    echo -e "${GREEN}====================================================${RESET}"
    echo
    echo -e "${BLUE}What's next?${RESET}"
    echo
    echo -e "1. Start the Ingestor MCP server:"
    echo -e "   ${YELLOW}${PROJECT_ROOT}/scripts/start_mcp_server.sh${RESET}"
    echo
    echo -e "2. Use the Ingestor CLI:"
    echo -e "   ${YELLOW}${PROJECT_ROOT}/src/ingestor --help${RESET}"
    echo
    echo -e "3. Use with Claude CLI:"
    echo -e "   ${YELLOW}claude --mcp ingestor${RESET}"
    echo
    echo -e "4. Use the HTTP MCP server:"
    echo -e "   ${YELLOW}${PROJECT_ROOT}/scripts/start_mcp_server.sh --http${RESET}"
    echo -e "   Then connect to: http://localhost:8765"
    echo
}

# Run the main function with all arguments
main "$@"