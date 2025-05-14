#!/bin/bash
# Structured logging module for ingestor-system
# Provides JSON-formatted logging with support for different log levels,
# timestamps, and contextual information.

# Load original logging module if available
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${script_dir}/logging.sh" ]]; then
    source "${script_dir}/logging.sh"
fi

# Log levels with their numeric values for comparison
declare -A LOG_LEVELS=( ["debug"]=0 ["info"]=1 ["warning"]=2 ["error"]=3 )

# Default configuration
LOG_FORMAT="${LOG_FORMAT:-human}" # human or json
LOG_DESTINATION="${LOG_DESTINATION:-both}" # file, stdout, or both
LOG_CONTEXT_ENABLED="${LOG_CONTEXT_ENABLED:-true}" # Include context info in logs

# Initialize structured logging
init_structured_logging() {
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Set log file path
    STRUCTURED_LOG_FILE="${LOG_DIR}/ingestor_structured_$(date +%Y%m%d).log"
    
    log_debug "Structured logging initialized to: $STRUCTURED_LOG_FILE"
    
    # Log system info at startup for troubleshooting
    if [[ "$LOG_FORMAT" == "json" ]]; then
        local system_info
        system_info=$(get_system_info_json)
        echo "$system_info" >> "$STRUCTURED_LOG_FILE"
    fi
}

# Get basic system information as JSON
get_system_info_json() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local hostname
    hostname=$(hostname)
    local os
    os=$(uname -s)
    local kernel
    kernel=$(uname -r)
    local pid=$$
    
    # Format as JSON
    echo "{\"timestamp\":\"$timestamp\",\"level\":\"info\",\"message\":\"Logging initialized\",\"context\":{\"system\":{\"hostname\":\"$hostname\",\"os\":\"$os\",\"kernel\":\"$kernel\",\"pid\":$pid}}}"
}

# Get calling context information
get_context_info() {
    local module="${BASH_SOURCE[2]:-unknown}"
    local function_name="${FUNCNAME[2]:-main}"
    local line_number="${BASH_LINENO[1]:-0}"
    local module_name
    module_name=$(basename "$module" .sh)
    
    echo "$module_name:$function_name:$line_number"
}

# Format log entry as JSON
format_json_log() {
    local level="$1"
    local message="$2"
    local context="$3"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ") # ISO 8601 format with milliseconds
    
    # Escape special characters in the message for JSON
    local escaped_message
    escaped_message=$(echo "$message" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/\\t/g' | sed 's/\n/\\n/g' | sed 's/\r/\\r/g')
    
    # Extract context components if available
    if [[ -n "$context" && "$LOG_CONTEXT_ENABLED" == "true" ]]; then
        IFS=':' read -r module function line <<< "$context"
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$escaped_message\",\"context\":{\"module\":\"$module\",\"function\":\"$function\",\"line\":$line}}"
    else
        echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$escaped_message\"}"
    fi
}

# Format log entry as human-readable text
format_human_log() {
    local level="$1"
    local message="$2"
    local context="$3"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    if [[ -n "$context" && "$LOG_CONTEXT_ENABLED" == "true" ]]; then
        echo "[$timestamp] [$level] [$context] $message"
    else
        echo "[$timestamp] [$level] $message"
    fi
}

# Internal log function
_structured_log() {
    local level="$1"
    local message="$2"
    local additional_fields="$3"
    local level_num=${LOG_LEVELS[$level]}
    local current_level_num=${LOG_LEVELS[$LOG_LEVEL]}
    
    # Only log if level is high enough
    if [[ $level_num -ge $current_level_num ]]; then
        # Get calling context information
        local context
        context=$(get_context_info)
        
        # Format log message based on configuration
        local formatted_log
        if [[ "$LOG_FORMAT" == "json" ]]; then
            formatted_log=$(format_json_log "$level" "$message" "$context")
            
            # Add additional fields if provided
            if [[ -n "$additional_fields" ]]; then
                # Remove closing brace, add additional fields, and close
                formatted_log="${formatted_log%\}},\"$additional_fields\"}"
            fi
        else
            formatted_log=$(format_human_log "$level" "$message" "$context")
        fi
        
        # Output based on destination configuration
        if [[ "$LOG_DESTINATION" == "file" || "$LOG_DESTINATION" == "both" ]]; then
            echo "$formatted_log" >> "$STRUCTURED_LOG_FILE"
        fi
        
        if [[ "$LOG_DESTINATION" == "stdout" || "$LOG_DESTINATION" == "both" ]]; then
            # Format for console output with colors if human format and terminal
            if [[ "$LOG_FORMAT" == "human" && -t 1 ]]; then
                case "$level" in
                    debug)   echo -e "\033[0;36m[DEBUG]\033[0m $message" ;;
                    info)    echo -e "\033[0;32m[INFO]\033[0m $message" ;;
                    warning) echo -e "\033[0;33m[WARN]\033[0m $message" ;;
                    error)   echo -e "\033[0;31m[ERROR]\033[0m $message" ;;
                    *)       echo "[$level] $message" ;;
                esac
            else
                echo "$formatted_log"
            fi
        fi
    fi
}

# Extended log functions
log_structured_debug() {
    local message="$1"
    local additional_fields="${2:-}"
    _structured_log "debug" "$message" "$additional_fields"
}

log_structured_info() {
    local message="$1"
    local additional_fields="${2:-}"
    _structured_log "info" "$message" "$additional_fields"
}

log_structured_warning() {
    local message="$1"
    local additional_fields="${2:-}"
    _structured_log "warning" "$message" "$additional_fields"
}

log_structured_error() {
    local message="$1"
    local additional_fields="${2:-}"
    _structured_log "error" "$message" "$additional_fields"
}

# Utility function to build additional fields JSON string
build_log_fields() {
    local result="{"
    local delimiter=""
    
    # Process all key-value pairs
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        # Skip if out of arguments
        [[ -z "$value" ]] && break
        
        # Escape value if it's a string (not starting with { or [)
        if [[ "$value" != "{"* && "$value" != "["* && "$value" != "true" && "$value" != "false" && "$value" != "null" && ! "$value" =~ ^[0-9]+$ ]]; then
            value="\"$(echo "$value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/\\t/g' | sed 's/\n/\\n/g' | sed 's/\r/\\r/g')\""
        fi
        
        result+="$delimiter\"$key\":$value"
        delimiter=","
    done
    
    result+="}"
    echo "$result"
}

# Log a metric (for performance tracking)
log_metric() {
    local name="$1"
    local value="$2"
    local unit="${3:-ms}"
    local context="${4:-}"
    
    local additional_fields
    additional_fields=$(build_log_fields "metric" "{\"name\":\"$name\",\"value\":$value,\"unit\":\"$unit\"}")
    
    log_structured_info "Metric: $name=$value$unit" "$additional_fields"
}

# Log an event (for important system events)
log_event() {
    local event_name="$1"
    local severity="${2:-info}"
    local details="${3:-}"
    
    local additional_fields
    if [[ -n "$details" ]]; then
        additional_fields=$(build_log_fields "event" "{\"name\":\"$event_name\",\"severity\":\"$severity\",\"details\":$details}")
    else
        additional_fields=$(build_log_fields "event" "{\"name\":\"$event_name\",\"severity\":\"$severity\"}")
    fi
    
    log_structured_info "Event: $event_name" "$additional_fields"
}

# Log a structured exception with stack trace
log_structured_exception() {
    local message="$1"
    local error_code="${2:-1}"
    local error_type="${3:-Error}"
    
    # Get stack trace
    local stack=""
    local i=1
    local stack_array="["
    
    while caller $i > /dev/null; do
        local frame=$(caller $i)
        local func=$(echo "$frame" | awk '{print $2}')
        local line=$(echo "$frame" | awk '{print $1}')
        local file=$(echo "$frame" | awk '{print $3}')
        
        # Add to plain text stack trace
        stack+=" > $(echo "$frame" | awk '{print $3 ":" $1 " in " $2}')"
        
        # Add to JSON array
        if [[ $i -gt 1 ]]; then
            stack_array+=","
        fi
        stack_array+="{\"file\":\"$file\",\"line\":$line,\"function\":\"$func\"}"
        
        ((i++))
    done
    
    stack_array+="]"
    
    # Create exception JSON
    local exception_json
    exception_json=$(build_log_fields "exception" "{\"message\":\"$message\",\"code\":$error_code,\"type\":\"$error_type\",\"stacktrace\":$stack_array}")
    
    # Log error with stack trace
    log_structured_error "$message (exit code: $error_code)" "$exception_json"
    
    # Also log to original logging system if available
    if type log_error &>/dev/null; then
        log_error "$message (exit code: $error_code)"
        if [[ -n "$stack" ]]; then
            log_error "Stack trace:$stack"
        fi
    fi
}

# Configure logging format and destination
configure_logging() {
    local format="${1:-$LOG_FORMAT}"
    local destination="${2:-$LOG_DESTINATION}"
    local context_enabled="${3:-$LOG_CONTEXT_ENABLED}"
    
    # Validate format
    if [[ "$format" != "human" && "$format" != "json" ]]; then
        log_warning "Invalid log format: $format. Using default: human"
        format="human"
    fi
    
    # Validate destination
    if [[ "$destination" != "file" && "$destination" != "stdout" && "$destination" != "both" ]]; then
        log_warning "Invalid log destination: $destination. Using default: both"
        destination="both"
    fi
    
    # Set configuration
    LOG_FORMAT="$format"
    LOG_DESTINATION="$destination"
    LOG_CONTEXT_ENABLED="$context_enabled"
    
    log_info "Logging configured: format=$format, destination=$destination, context=$context_enabled"
}

# Retrieve logs that match a pattern
grep_logs() {
    local pattern="$1"
    local log_file="${2:-$STRUCTURED_LOG_FILE}"
    local max_results="${3:-100}"
    
    if [[ ! -f "$log_file" ]]; then
        echo "Log file not found: $log_file"
        return 1
    fi
    
    # Use grep for searching with context
    grep -A 1 -B 1 "$pattern" "$log_file" | head -n "$max_results"
}

# Parse JSON logs and extract structured data
parse_json_logs() {
    local field="$1"
    local value="$2"
    local log_file="${3:-$STRUCTURED_LOG_FILE}"
    
    if [[ ! -f "$log_file" ]]; then
        echo "Log file not found: $log_file"
        return 1
    fi
    
    # Use grep and awk to extract matching JSON objects
    grep "\"$field\":\"$value\"" "$log_file"
}

# Export log levels
export LOG_LEVELS

# Export functions
export -f init_structured_logging
export -f log_structured_debug
export -f log_structured_info
export -f log_structured_warning
export -f log_structured_error
export -f log_metric
export -f log_event
export -f log_structured_exception
export -f configure_logging
export -f grep_logs
export -f parse_json_logs
export -f build_log_fields

# Initialize structured logging if this file is being sourced directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Display help message
    echo "Structured Logging Module for Ingestor System"
    echo "This script should be sourced, not executed directly."
    echo ""
    echo "Usage:"
    echo "  source structured_logging.sh"
    echo ""
    echo "Configuration variables:"
    echo "  LOG_FORMAT: 'human' or 'json' (default: human)"
    echo "  LOG_DESTINATION: 'file', 'stdout', or 'both' (default: both)"
    echo "  LOG_CONTEXT_ENABLED: 'true' or 'false' (default: true)"
    exit 1
fi