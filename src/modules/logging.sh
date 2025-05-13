#!/bin/bash
# Logging module for ingestor

# Log levels
declare -A LOG_LEVELS=( ["debug"]=0 ["info"]=1 ["warning"]=2 ["error"]=3 )

# Initialize logging
init_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Set log file path
    LOG_FILE="${LOG_DIR}/ingestor_$(date +%Y%m%d).log"
    
    log_debug "Logging initialized to: $LOG_FILE"
}

# Internal log function
_log() {
    local level="$1"
    local message="$2"
    local level_num=${LOG_LEVELS[$level]}
    local current_level_num=${LOG_LEVELS[$LOG_LEVEL]}
    
    # Only log if level is high enough
    if [[ $level_num -ge $current_level_num ]]; then
        local timestamp
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        
        # Format for console output
        if [[ -t 1 && "$level" != "debug" ]]; then
            case "$level" in
                info)    echo -e "\033[0;32m[INFO]\033[0m $message" ;;
                warning) echo -e "\033[0;33m[WARN]\033[0m $message" ;;
                error)   echo -e "\033[0;31m[ERROR]\033[0m $message" ;;
                *)       echo "[$level] $message" ;;
            esac
        fi
        
        # Always write to log file
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# Log debug message
log_debug() {
    _log "debug" "$1"
}

# Log info message
log_info() {
    _log "info" "$1"
}

# Log warning message
log_warning() {
    _log "warning" "$1"
}

# Log error message
log_error() {
    _log "error" "$1"
}

# Log exception with stack trace
log_exception() {
    local message="$1"
    local error_code="${2:-1}"
    
    # Get stack trace
    local stack=""
    local i=1
    
    while caller $i > /dev/null; do
        local frame=$(caller $i)
        stack+=" > $(echo "$frame" | awk '{print $3 ":" $1 " in " $2}')"
        ((i++))
    done
    
    # Log error with stack trace
    log_error "$message (exit code: $error_code)"
    log_error "Stack trace:$stack"
}