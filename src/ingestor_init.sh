#!/bin/bash
# Initialization script for ingestor system
# Sets up the environment, initializes modules, and provides centralized error handling

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load environment variables
set -a
[[ -f "${PROJECT_ROOT}/.env" ]] && source "${PROJECT_ROOT}/.env"
set +a

# Set default paths
export CONFIG_DIR="${PROJECT_ROOT}/config"
export LOG_DIR="${PROJECT_ROOT}/logs"
export TEMP_DIR="${PROJECT_ROOT}/tmp"
export DB_DIR="${PROJECT_ROOT}/data"

# Create necessary directories
mkdir -p "$LOG_DIR" "$TEMP_DIR" "$DB_DIR"

# Source basic logging first (needed for error handler)
source "${SCRIPT_DIR}/modules/logging.sh"

# Initialize logging
LOG_LEVEL=${LOG_LEVEL:-info}
init_logging

# Source error handler
source "${SCRIPT_DIR}/modules/error_handler.sh"
init_error_handler

# Function to load and initialize a module
load_module() {
    local module_name="$1"
    local module_path="${SCRIPT_DIR}/modules/${module_name}.sh"
    
    log_debug "Loading module: $module_name"
    
    if [[ ! -f "$module_path" ]]; then
        log_error "Module not found: $module_name at $module_path"
        return 1
    fi
    
    # Source the module
    source "$module_path"
    
    # Call init function if it exists
    local init_func="init_${module_name}"
    if [[ "$(type -t "$init_func")" == "function" ]]; then
        log_debug "Initializing module: $module_name"
        "$init_func" || {
            log_error "Failed to initialize module: $module_name"
            return 1
        }
    fi
    
    log_debug "Module loaded successfully: $module_name"
    return 0
}

# Setup signal handling for cleanup
setup_signal_handlers() {
    trap 'handle_exit' EXIT
    trap 'handle_signal SIGHUP' SIGHUP
    trap 'handle_signal SIGINT' SIGINT
    trap 'handle_signal SIGTERM' SIGTERM
}

# Handle exit
handle_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Ingestor exiting with non-zero status: $exit_code"
    else
        log_debug "Ingestor exiting normally"
    fi
    
    cleanup
    exit $exit_code
}

# Handle signals
handle_signal() {
    local signal="$1"
    log_warning "Received signal: $signal"
    
    case "$signal" in
        SIGINT|SIGTERM)
            log_info "Shutting down ingestor due to signal: $signal"
            cleanup
            exit 130
            ;;
        SIGHUP)
            log_info "Reloading configuration due to SIGHUP"
            reload_config
            ;;
    esac
}

# Cleanup function
cleanup() {
    log_info "Running cleanup tasks"
    
    # Cleanup temp files
    if [[ -d "$TEMP_DIR" ]]; then
        find "$TEMP_DIR" -type f -mmin +60 -delete 2>/dev/null
        log_debug "Cleaned up temporary files"
    fi
    
    # Add other cleanup tasks as needed
}

# Reload configuration
reload_config() {
    log_info "Reloading configuration"
    
    # Reload main configuration
    if load_module "config"; then
        log_info "Configuration reloaded successfully"
    else
        log_error "Failed to reload configuration"
    fi
}

# Main initialization function
init_ingestor() {
    log_info "Initializing ingestor system"
    
    # Setup signal handlers
    setup_signal_handlers
    
    # Load required modules
    local required_modules=("config" "keychain" "database" "content" "network")
    local failed_modules=0
    
    for module in "${required_modules[@]}"; do
        if ! load_module "$module"; then
            log_error "Failed to load required module: $module"
            ((failed_modules++))
        fi
    done
    
    if [[ $failed_modules -gt 0 ]]; then
        handle_critical_error "$failed_modules required modules failed to load" 1
        return 1
    fi
    
    # Check system dependencies
    if ! check_system_dependencies; then
        handle_critical_error "Missing required system dependencies" 2
        return 1
    }
    
    log_info "Ingestor system initialized successfully"
    return 0
}

# Check system dependencies
check_system_dependencies() {
    log_info "Checking system dependencies"
    
    local dependencies=("sqlite3" "curl" "file" "jq")
    local missing_dependencies=0
    
    for dependency in "${dependencies[@]}"; do
        if ! check_command "$dependency"; then
            log_error "Missing required dependency: $dependency"
            ((missing_dependencies++))
        fi
    done
    
    # Check for optional dependencies
    if ! check_command "exiftool" "exiftool" || ! check_command "ffmpeg" "ffmpeg"; then
        log_warning "Some optional dependencies are missing. Limited functionality available."
    fi
    
    return $missing_dependencies
}

# Export functions for use by other scripts
export -f load_module
export -f cleanup

# If this script is called directly, initialize the system
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_ingestor "$@"
    exit $?
fi