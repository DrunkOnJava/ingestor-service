#!/bin/bash
# Enhanced error handling module for ingestor-system
# Provides advanced error handling, recovery, and diagnosis capabilities

# Source existing error codes if not already loaded
if [[ -z "${ERR_UNKNOWN+x}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/error_codes.sh" ]]; then
        source "${script_dir}/error_codes.sh"
    else
        echo "ERROR: Error codes module not found" >&2
        exit 1
    fi
fi

# Global configuration for error handling
ENHANCED_ERROR_HANDLER_INITIALIZED=false
ERROR_LOG_DIR="${ERROR_LOG_DIR:-/tmp/ingestor-errors}"
MAX_RETRY_COUNT=${MAX_RETRY_COUNT:-3}
DEFAULT_RETRY_DELAY=${DEFAULT_RETRY_DELAY:-2}
MAX_RETRY_DELAY=${MAX_RETRY_DELAY:-30}
ENABLE_RECOVERY=${ENABLE_RECOVERY:-true}
ENABLE_DIAGNOSTICS=${ENABLE_DIAGNOSTICS:-true}
ENABLE_STACK_TRACES=${ENABLE_STACK_TRACES:-true}
ENABLE_ERROR_REPORTING=${ENABLE_ERROR_REPORTING:-true}
DEFAULT_NETWORK_TIMEOUT=${DEFAULT_NETWORK_TIMEOUT:-30}
RETRY_JITTER_PERCENTAGE=${RETRY_JITTER_PERCENTAGE:-10}  # Jitter percentage for retry delays

# Store error statistics
declare -A ERROR_STATS
ERROR_STATS["total"]=0

# Initialize error handler
init_enhanced_error_handler() {
    local error_log_disabled="${1:-false}"

    # Enable advanced error trapping
    set -o errexit   # Exit on error
    set -o pipefail  # Exit on pipe failure
    set -o nounset   # Exit on unset variables
    
    # Create error log directory if it doesn't exist and logging is enabled
    if [[ "$error_log_disabled" != "true" && ! -d "$ERROR_LOG_DIR" ]]; then
        mkdir -p "$ERROR_LOG_DIR" || {
            echo "WARNING: Could not create error log directory: $ERROR_LOG_DIR. Error logging will be disabled." >&2
            error_log_disabled="true"
        }
    fi
    
    # Set error log file if enabled
    if [[ "$error_log_disabled" != "true" ]]; then
        ERROR_LOG_FILE="${ERROR_LOG_DIR}/ingestor_errors_$(date +%Y%m%d_%H%M%S).log"
        touch "$ERROR_LOG_FILE" || {
            echo "WARNING: Could not create error log file: $ERROR_LOG_FILE. Error logging will be disabled." >&2
            error_log_disabled="true"
        }
    else
        ERROR_LOG_FILE=""
    fi
    
    # Configure error traps
    trap 'enhanced_error_trap ${LINENO} ${FUNCNAME[0]:-main} $? "${BASH_SOURCE[0]:-script}"' ERR
    trap 'cleanup_handler' EXIT
    
    # Register signal handlers for graceful termination
    trap 'handle_sigint' INT
    trap 'handle_sigterm' TERM
    
    # Initialize retry configuration
    NEXT_RETRY_DELAY=$DEFAULT_RETRY_DELAY
    
    # Mark as initialized
    ENHANCED_ERROR_HANDLER_INITIALIZED=true
    
    # Log initialization
    if type log_info &>/dev/null; then
        log_info "Enhanced error handler initialized with logs at: ${ERROR_LOG_FILE:-disabled}"
    else
        echo "Enhanced error handler initialized with logs at: ${ERROR_LOG_FILE:-disabled}" >&2
    fi
}

# Handle errors from ERR trap
enhanced_error_trap() {
    local line_number="$1"
    local function_name="${2:-unknown}"
    local exit_code="$3"
    local source_file="${4:-unknown}"
    
    # Increment error counter
    ERROR_STATS["total"]=$((ERROR_STATS["total"] + 1))
    
    # Get error type counter or initialize to 1
    local error_type=$(get_error_name "$exit_code")
    ERROR_STATS["${error_type}"]=$((${ERROR_STATS["${error_type}"]:-0} + 1))
    
    # Get error description
    local error_message=$(get_error_message "$exit_code")
    
    # Format error log message
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local error_log_message="[$timestamp] [ERROR] [$error_type/$exit_code] in $source_file:$line_number ($function_name): $error_message"
    
    # Log error
    if type log_error &>/dev/null; then
        log_error "$error_message in $function_name at $source_file:$line_number (error code: $exit_code)"
    else
        echo -e "\033[0;31m$error_log_message\033[0m" >&2
    fi
    
    # Write to error log file if enabled
    if [[ -n "${ERROR_LOG_FILE:-}" && -w "${ERROR_LOG_FILE}" ]]; then
        echo "$error_log_message" >> "$ERROR_LOG_FILE"
        
        # Add stack trace if enabled
        if [[ "$ENABLE_STACK_TRACES" == "true" ]]; then
            echo "Stack trace:" >> "$ERROR_LOG_FILE"
            local frame_idx=0
            while caller $frame_idx >/dev/null 2>&1; do
                local frame_info=$(caller $frame_idx)
                local line_num=$(echo "$frame_info" | awk '{print $1}')
                local func_name=$(echo "$frame_info" | awk '{print $2}')
                local src_file=$(echo "$frame_info" | awk '{print $3}')
                echo "  #$frame_idx: $src_file:$line_num in function $func_name" >> "$ERROR_LOG_FILE"
                ((frame_idx++))
            done
        fi
        
        # Add system information for diagnostics if enabled
        if [[ "$ENABLE_DIAGNOSTICS" == "true" ]]; then
            echo "System diagnostics:" >> "$ERROR_LOG_FILE"
            echo "  Time: $(date)" >> "$ERROR_LOG_FILE"
            echo "  Hostname: $(hostname)" >> "$ERROR_LOG_FILE"
            echo "  User: $(whoami)" >> "$ERROR_LOG_FILE"
            echo "  Working directory: $(pwd)" >> "$ERROR_LOG_FILE"
            echo "  Free disk space: $(df -h . | awk 'NR==2 {print $4}')" >> "$ERROR_LOG_FILE"
            echo "  Free memory: $(vm_stat | grep "Pages free" | awk '{print $3*4096/1048576 " MB"}')" >> "$ERROR_LOG_FILE"
            echo "  Load averages: $(uptime | awk -F'[a-z]:' '{print $2}')" >> "$ERROR_LOG_FILE"
        fi
    fi
    
    # Don't execute when sourcing
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return $exit_code

    # Check if we're within a try block
    if [[ -n "${_ENHANCED_ERROR_HANDLER_IN_TRY:-}" ]]; then
        # Just capture error details for catch block
        _ENHANCED_ERROR_HANDLER_TRAPPED_CODE=$exit_code
        _ENHANCED_ERROR_HANDLER_TRAPPED_LINE=$line_number
        _ENHANCED_ERROR_HANDLER_TRAPPED_FUNC=$function_name
        _ENHANCED_ERROR_HANDLER_TRAPPED_FILE=$source_file
        _ENHANCED_ERROR_HANDLER_TRAPPED_MESSAGE=$error_message
        return $exit_code
    fi
    
    # When not in a try block, attempt recovery or terminate
    if [[ "$ENABLE_RECOVERY" == "true" ]]; then
        if ! attempt_error_recovery "$exit_code" "$line_number" "$function_name" "$source_file"; then
            # If recovery fails, terminate
            enhanced_exit "$exit_code" "$error_message"
        fi
    else
        # No recovery enabled, terminate
        enhanced_exit "$exit_code" "$error_message"
    fi
}

# Cleanup handler for EXIT trap
cleanup_handler() {
    local exit_code=$?
    
    # Only run specific cleanup for non-zero exit codes
    if [[ $exit_code -ne 0 ]]; then
        if type log_debug &>/dev/null; then
            log_debug "Running cleanup for exit code $exit_code"
        fi
        
        # Remove any temporary files
        if [[ -n "${_ENHANCED_TEMP_FILES+x}" ]]; then
            for temp_file in "${_ENHANCED_TEMP_FILES[@]}"; do
                if [[ -f "$temp_file" ]]; then
                    rm -f "$temp_file" || true
                fi
            done
        fi
        
        # Terminate any background processes
        if [[ -n "${_ENHANCED_BACKGROUND_PIDS+x}" ]]; then
            for pid in "${_ENHANCED_BACKGROUND_PIDS[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill -TERM "$pid" 2>/dev/null || true
                fi
            done
        fi
    fi
    
    # Generate error report if enabled
    if [[ "$ENABLE_ERROR_REPORTING" == "true" && $exit_code -ne 0 && -n "${ERROR_LOG_FILE:-}" && -w "${ERROR_LOG_FILE}" ]]; then
        echo "Error summary:" >> "$ERROR_LOG_FILE"
        echo "  Total errors: ${ERROR_STATS["total"]}" >> "$ERROR_LOG_FILE"
        
        # Add breakdown by error type
        for error_type in "${!ERROR_STATS[@]}"; do
            if [[ "$error_type" != "total" ]]; then
                echo "  $error_type: ${ERROR_STATS["$error_type"]}" >> "$ERROR_LOG_FILE"
            fi
        done
    fi
}

# Handle SIGINT (Ctrl+C)
handle_sigint() {
    if type log_warning &>/dev/null; then
        log_warning "Received interrupt signal (SIGINT). Terminating..."
    else
        echo -e "\033[0;33mReceived interrupt signal (SIGINT). Terminating...\033[0m" >&2
    fi
    
    # Run cleanup and exit
    trap - INT
    exit $ERR_INTERRUPTED
}

# Handle SIGTERM
handle_sigterm() {
    if type log_warning &>/dev/null; then
        log_warning "Received termination signal (SIGTERM). Terminating..."
    else
        echo -e "\033[0;33mReceived termination signal (SIGTERM). Terminating...\033[0m" >&2
    fi
    
    # Run cleanup and exit
    trap - TERM
    exit $ERR_INTERRUPTED
}

# Attempt to recover from an error
attempt_error_recovery() {
    local error_code="$1"
    local line_number="$2"
    local function_name="$3"
    local source_file="$4"
    
    # Check if this is a recoverable error
    case $error_code in
        # Network errors - could be temporary
        $ERR_NETWORK|$ERR_NETWORK_DOWN|$ERR_NETWORK_TIMEOUT|$ERR_HOST_UNREACHABLE|$ERR_CONNECTION_REFUSED|$ERR_DNS_FAILURE)
            if type log_warning &>/dev/null; then
                log_warning "Network error detected. Checking network status..."
            fi
            
            # Check if network is available
            if type check_network &>/dev/null && check_network; then
                if type log_info &>/dev/null; then
                    log_info "Network appears to be available. Consider retrying the operation."
                fi
            else
                if type log_error &>/dev/null; then
                    log_error "Network is unavailable. Cannot recover automatically."
                fi
                return 1
            fi
            ;;
        
        # Database errors - some might be recoverable
        $ERR_DB_LOCKED)
            if type log_warning &>/dev/null; then
                log_warning "Database locked error detected. This might resolve itself if retried."
            fi
            return 0  # Indicate that retry might work
            ;;
        
        # Timeout errors - might succeed if retried
        $ERR_TIMEOUT)
            if type log_warning &>/dev/null; then
                log_warning "Timeout error detected. Operation might succeed if retried with a longer timeout."
            fi
            return 0  # Indicate that retry might work
            ;;
        
        # Resource errors - check if resources are available
        $ERR_DISK_SPACE)
            if type log_warning &>/dev/null; then
                log_warning "Disk space error detected. Checking available space..."
            fi
            
            # Check available disk space
            local available_space
            available_space=$(df -k . | awk 'NR==2 {print $4}')
            if [[ $available_space -gt 102400 ]]; then  # > 100MB
                if type log_info &>/dev/null; then
                    log_info "Some disk space is available ($available_space KB). Consider cleaning up unnecessary files."
                fi
            else
                if type log_error &>/dev/null; then
                    log_error "Critical disk space shortage ($available_space KB). Cannot recover automatically."
                fi
                return 1
            fi
            ;;
        
        # By default, assume error is not recoverable
        *)
            return 1
            ;;
    esac
    
    # For recoverable errors, log diagnostic info
    if type log_info &>/dev/null; then
        log_info "Error may be recoverable through retry or with user intervention."
    fi
    
    return 0  # Indicate recovery might be possible
}

# Enhanced exit function
enhanced_exit() {
    local exit_code="$1"
    local message="$2"
    
    # Log final error message
    if type log_error &>/dev/null; then
        log_error "Process terminating with error code $exit_code: $message"
    else
        echo -e "\033[0;31mProcess terminating with error code $exit_code: $message\033[0m" >&2
    fi
    
    # Run cleanup handler
    cleanup_handler
    
    # Exit with appropriate code
    exit $exit_code
}

# Enhanced try-catch-finally mechanism
try() {
    # Reset any previous error state
    _ENHANCED_ERROR_HANDLER_TRAPPED_CODE=0
    _ENHANCED_ERROR_HANDLER_TRAPPED_LINE=0
    _ENHANCED_ERROR_HANDLER_TRAPPED_FUNC=""
    _ENHANCED_ERROR_HANDLER_TRAPPED_FILE=""
    _ENHANCED_ERROR_HANDLER_TRAPPED_MESSAGE=""
    _ENHANCED_ERROR_HANDLER_IN_TRY=1
    
    # Execute the command or function
    "$@"
    
    # Save exit code
    local exit_code=$?
    _ENHANCED_ERROR_HANDLER_CODE=$exit_code
    
    return $exit_code
}

# Enhanced catch
catch() {
    # Only execute if there was an error
    if [[ ${_ENHANCED_ERROR_HANDLER_CODE:-0} -ne 0 ]]; then
        # Execute the provided error handler with details
        "$@" "${_ENHANCED_ERROR_HANDLER_CODE}" \
              "${_ENHANCED_ERROR_HANDLER_TRAPPED_LINE}" \
              "${_ENHANCED_ERROR_HANDLER_TRAPPED_FUNC}" \
              "${_ENHANCED_ERROR_HANDLER_TRAPPED_FILE}" \
              "${_ENHANCED_ERROR_HANDLER_TRAPPED_MESSAGE}"
        return $?
    fi
    
    # No error occurred, so skip catch
    return 0
}

# Finally block that executes regardless of error
finally() {
    # Capture current try-catch state
    local saved_code=${_ENHANCED_ERROR_HANDLER_CODE:-0}
    
    # Execute the cleanup function
    "$@"
    
    # Clear try-catch state
    unset _ENHANCED_ERROR_HANDLER_IN_TRY
    unset _ENHANCED_ERROR_HANDLER_CODE
    unset _ENHANCED_ERROR_HANDLER_TRAPPED_CODE
    unset _ENHANCED_ERROR_HANDLER_TRAPPED_LINE
    unset _ENHANCED_ERROR_HANDLER_TRAPPED_FUNC
    unset _ENHANCED_ERROR_HANDLER_TRAPPED_FILE
    unset _ENHANCED_ERROR_HANDLER_TRAPPED_MESSAGE
    
    # Return the original error code
    return $saved_code
}

# Enhanced retry mechanism with exponential backoff and jitter
retry_with_backoff() {
    local cmd="$1"
    local max_attempts="${2:-$MAX_RETRY_COUNT}"
    local base_delay="${3:-$DEFAULT_RETRY_DELAY}"
    local max_delay="${4:-$MAX_RETRY_DELAY}"
    local timeout="${5:-$DEFAULT_NETWORK_TIMEOUT}"
    local attempt=1
    local exit_code=0
    local delay=$base_delay
    
    # Log retry attempt
    if type log_debug &>/dev/null; then
        log_debug "Executing with retry (max $max_attempts attempts, initial delay $base_delay seconds): $cmd"
    fi
    
    while [[ $attempt -le $max_attempts ]]; do
        # Log attempt number if not the first
        if [[ $attempt -gt 1 ]] && type log_info &>/dev/null; then
            log_info "Retry attempt $attempt/$max_attempts with delay of $delay seconds"
        fi
        
        # Execute the command
        if [[ $timeout -gt 0 ]]; then
            # With timeout
            if command -v timeout &>/dev/null; then
                timeout --preserve-status $timeout bash -c "$cmd"
                exit_code=$?
            else
                # Fallback if timeout command is not available
                local pid
                bash -c "$cmd" & pid=$!
                
                # Wait for up to timeout seconds
                local waited=0
                while [[ $waited -lt $timeout ]] && kill -0 $pid 2>/dev/null; do
                    sleep 1
                    ((waited++))
                done
                
                # Check if still running after timeout
                if kill -0 $pid 2>/dev/null; then
                    kill -TERM $pid 2>/dev/null || kill -KILL $pid 2>/dev/null
                    exit_code=$ERR_TIMEOUT
                else
                    # Process completed, get its exit code
                    wait $pid
                    exit_code=$?
                fi
            fi
        else
            # Without timeout
            bash -c "$cmd"
            exit_code=$?
        fi
        
        # Check exit code
        if [[ $exit_code -eq 0 ]]; then
            # Success
            if [[ $attempt -gt 1 ]] && type log_info &>/dev/null; then
                log_info "Command succeeded on attempt $attempt/$max_attempts"
            fi
            return 0
        fi
        
        # Check if we've hit max attempts
        if [[ $attempt -ge $max_attempts ]]; then
            break
        fi
        
        # Log failure and prepare for retry
        if type log_warning &>/dev/null; then
            local error_name="$(get_error_name $exit_code 2>/dev/null || echo "Error")"
            log_warning "Command failed with $error_name (code $exit_code) on attempt $attempt/$max_attempts"
        fi
        
        # Calculate next delay with jitter (exponential backoff + random jitter)
        # Formula: delay = min(max_delay, base_delay * 2^(attempt-1)) * (1 ± jitter%)
        delay=$(echo "scale=2; $base_delay * (2 ^ (($attempt - 1)))" | bc)
        delay=$(echo "$delay > $max_delay ? $max_delay : $delay" | bc)
        
        # Add jitter (± percentage)
        if [[ $RETRY_JITTER_PERCENTAGE -gt 0 ]]; then
            local jitter_factor
            # Generate random number between -JITTER% and +JITTER%
            jitter_factor=$(echo "scale=2; 1 + (($RANDOM % (2*$RETRY_JITTER_PERCENTAGE + 1) - $RETRY_JITTER_PERCENTAGE) / 100)" | bc)
            delay=$(echo "$delay * $jitter_factor" | bc | awk '{printf "%.1f", $0}')
        fi
        
        # If delay is invalid, use a safe default
        if [[ -z "$delay" || "$delay" == "0" || "$delay" == "0.0" ]]; then
            delay=$base_delay
        fi
        
        # Log the delay
        if type log_debug &>/dev/null; then
            log_debug "Waiting $delay seconds before next retry attempt"
        fi
        
        # Sleep before retry
        sleep $delay
        
        # Increment attempt counter
        ((attempt++))
    done
    
    # If we're here, we've exceeded max attempts
    if type log_error &>/dev/null; then
        log_error "Command failed after $max_attempts attempts with exit code $exit_code: $cmd"
    fi
    
    return $exit_code
}

# Enhanced function retry
retry_function() {
    local func="$1"
    local max_attempts="${2:-$MAX_RETRY_COUNT}"
    local base_delay="${3:-$DEFAULT_RETRY_DELAY}"
    local max_delay="${4:-$MAX_RETRY_DELAY}"
    local attempt=1
    local exit_code=0
    local delay=$base_delay
    
    # Shift the first 4 arguments
    shift 4
    
    # Log retry attempt
    if type log_debug &>/dev/null; then
        log_debug "Executing function with retry (max $max_attempts attempts, initial delay $base_delay seconds): $func"
    fi
    
    while [[ $attempt -le $max_attempts ]]; do
        # Log attempt number if not the first
        if [[ $attempt -gt 1 ]] && type log_info &>/dev/null; then
            log_info "Retry attempt $attempt/$max_attempts with delay of $delay seconds"
        fi
        
        # Execute the function
        "$func" "$@"
        exit_code=$?
        
        # Check exit code
        if [[ $exit_code -eq 0 ]]; then
            # Success
            if [[ $attempt -gt 1 ]] && type log_info &>/dev/null; then
                log_info "Function succeeded on attempt $attempt/$max_attempts"
            fi
            return 0
        fi
        
        # Check if we've hit max attempts
        if [[ $attempt -ge $max_attempts ]]; then
            break
        fi
        
        # Log failure and prepare for retry
        if type log_warning &>/dev/null; then
            local error_name="$(get_error_name $exit_code 2>/dev/null || echo "Error")"
            log_warning "Function failed with $error_name (code $exit_code) on attempt $attempt/$max_attempts"
        fi
        
        # Calculate next delay with jitter (exponential backoff + random jitter)
        delay=$(echo "scale=2; $base_delay * (2 ^ (($attempt - 1)))" | bc)
        delay=$(echo "$delay > $max_delay ? $max_delay : $delay" | bc)
        
        # Add jitter (± percentage)
        if [[ $RETRY_JITTER_PERCENTAGE -gt 0 ]]; then
            local jitter_factor
            jitter_factor=$(echo "scale=2; 1 + (($RANDOM % (2*$RETRY_JITTER_PERCENTAGE + 1) - $RETRY_JITTER_PERCENTAGE) / 100)" | bc)
            delay=$(echo "$delay * $jitter_factor" | bc | awk '{printf "%.1f", $0}')
        fi
        
        # If delay is invalid, use a safe default
        if [[ -z "$delay" || "$delay" == "0" || "$delay" == "0.0" ]]; then
            delay=$base_delay
        fi
        
        # Log the delay
        if type log_debug &>/dev/null; then
            log_debug "Waiting $delay seconds before next retry attempt"
        fi
        
        # Sleep before retry
        sleep $delay
        
        # Increment attempt counter
        ((attempt++))
    done
    
    # If we're here, we've exceeded max attempts
    if type log_error &>/dev/null; then
        log_error "Function $func failed after $max_attempts attempts with exit code $exit_code"
    fi
    
    return $exit_code
}

# Enhanced file lock mechanism to prevent race conditions
acquire_lock() {
    local lock_file="$1"
    local timeout="${2:-30}"  # Default 30 seconds timeout
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    # Ensure lock directory exists
    local lock_dir
    lock_dir=$(dirname "$lock_file")
    if [[ ! -d "$lock_dir" ]]; then
        mkdir -p "$lock_dir" || {
            if type log_error &>/dev/null; then
                log_error "Failed to create lock directory: $lock_dir"
            fi
            return $ERR_FILE
        }
    fi
    
    # Try to acquire lock
    while [[ $(date +%s) -lt $end_time ]]; do
        if ( set -o noclobber; echo "$$" > "$lock_file" ) 2>/dev/null; then
            # Lock acquired
            if type log_debug &>/dev/null; then
                log_debug "Lock acquired: $lock_file (PID: $$)"
            fi
            
            # Register cleanup to remove lock on exit
            trap 'release_lock "'"$lock_file"'"' EXIT
            
            return 0
        fi
        
        # Check if the lock is stale
        if [[ -f "$lock_file" ]]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null)
            if [[ -n "$lock_pid" && ! -d "/proc/$lock_pid" && ! -d "/proc/$lock_pid" ]]; then
                # Stale lock detected - previous process is gone
                if type log_warning &>/dev/null; then
                    log_warning "Removing stale lock: $lock_file (PID: $lock_pid)"
                fi
                rm -f "$lock_file" || true
            fi
        fi
        
        # Wait before retrying
        sleep 0.5
    done
    
    # Timeout expired
    if type log_error &>/dev/null; then
        log_error "Failed to acquire lock: $lock_file (timeout: ${timeout}s)"
    fi
    
    return $ERR_TIMEOUT
}

# Release a previously acquired lock
release_lock() {
    local lock_file="$1"
    
    # Only release if lock file exists and belongs to this process
    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [[ "$lock_pid" == "$$" ]]; then
            # Lock belongs to this process, release it
            rm -f "$lock_file" || true
            
            if type log_debug &>/dev/null; then
                log_debug "Lock released: $lock_file (PID: $$)"
            fi
            
            # Remove the exit trap specifically for this lock
            trap - EXIT
            
            return 0
        fi
    fi
    
    # Lock doesn't exist or belongs to another process
    if type log_warning &>/dev/null; then
        log_warning "Cannot release lock: $lock_file (not owner or doesn't exist)"
    fi
    
    return 1
}

# Enhanced database transaction management
begin_transaction() {
    local db_path="$1"
    local isolation_level="${2:-IMMEDIATE}"  # DEFERRED, IMMEDIATE, or EXCLUSIVE
    
    # Validate inputs
    if [[ -z "$db_path" ]]; then
        if type log_error &>/dev/null; then
            log_error "Database path is required for transaction"
        fi
        return $ERR_INVALID_ARG
    fi
    
    # Check if database exists
    if [[ ! -f "$db_path" ]]; then
        if type log_error &>/dev/null; then
            log_error "Database file not found: $db_path"
        fi
        return $ERR_FILE_NOT_FOUND
    fi
    
    # Begin transaction
    local query="BEGIN $isolation_level TRANSACTION;"
    
    # Execute the query
    if sqlite3 "$db_path" "$query" &>/dev/null; then
        # Transaction started
        if type log_debug &>/dev/null; then
            log_debug "Transaction started on database: $db_path"
        fi
        
        # Mark transaction as started
        export _TRANSACTION_DB_PATH="$db_path"
        return 0
    else
        # Transaction failed to start
        if type log_error &>/dev/null; then
            log_error "Failed to start transaction on database: $db_path"
        fi
        return $ERR_DATABASE
    fi
}

# Commit an active transaction
commit_transaction() {
    local db_path="${1:-$_TRANSACTION_DB_PATH}"
    
    # Validate transaction is active
    if [[ -z "$db_path" ]]; then
        if type log_error &>/dev/null; then
            log_error "No active transaction to commit"
        fi
        return $ERR_INVALID_STATE
    fi
    
    # Commit transaction
    local query="COMMIT;"
    
    # Execute the query
    if sqlite3 "$db_path" "$query" &>/dev/null; then
        # Transaction committed
        if type log_debug &>/dev/null; then
            log_debug "Transaction committed on database: $db_path"
        fi
        
        # Clear transaction state
        unset _TRANSACTION_DB_PATH
        return 0
    else
        # Transaction failed to commit
        if type log_error &>/dev/null; then
            log_error "Failed to commit transaction on database: $db_path"
        fi
        return $ERR_DATABASE
    fi
}

# Rollback an active transaction
rollback_transaction() {
    local db_path="${1:-$_TRANSACTION_DB_PATH}"
    
    # Validate transaction is active
    if [[ -z "$db_path" ]]; then
        if type log_warning &>/dev/null; then
            log_warning "No active transaction to rollback"
        fi
        return $ERR_INVALID_STATE
    fi
    
    # Rollback transaction
    local query="ROLLBACK;"
    
    # Execute the query
    if sqlite3 "$db_path" "$query" &>/dev/null; then
        # Transaction rolled back
        if type log_debug &>/dev/null; then
            log_debug "Transaction rolled back on database: $db_path"
        fi
        
        # Clear transaction state
        unset _TRANSACTION_DB_PATH
        return 0
    else
        # Transaction failed to rollback
        if type log_error &>/dev/null; then
            log_error "Failed to rollback transaction on database: $db_path"
        fi
        return $ERR_DATABASE
    fi
}

# Enhanced network request with comprehensive error handling
enhanced_http_request() {
    local url="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    local headers="${4:-}"
    local output_file="${5:-}"
    local max_attempts="${6:-$MAX_RETRY_COUNT}"
    local timeout="${7:-$DEFAULT_NETWORK_TIMEOUT}"
    
    # Validate inputs
    if [[ -z "$url" ]]; then
        if type log_error &>/dev/null; then
            log_error "URL is required for HTTP request"
        fi
        return $ERR_INVALID_ARG
    fi
    
    # Log request details
    if type log_debug &>/dev/null; then
        log_debug "Making $method request to $url"
    fi
    
    # Check curl dependency
    if ! command -v curl &>/dev/null; then
        if type log_error &>/dev/null; then
            log_error "curl command not found, required for HTTP requests"
        fi
        return $ERR_DEPENDENCY
    fi
    
    # Build curl command
    local curl_cmd="curl -s -S -X $method"
    
    # Add timeout
    curl_cmd="$curl_cmd --connect-timeout 10 --max-time $timeout"
    
    # Add failure reporting
    curl_cmd="$curl_cmd -f"
    
    # Add output file or stdout
    if [[ -n "$output_file" ]]; then
        # Create directory if needed
        local output_dir
        output_dir=$(dirname "$output_file")
        if [[ ! -d "$output_dir" ]]; then
            mkdir -p "$output_dir" || {
                if type log_error &>/dev/null; then
                    log_error "Failed to create output directory: $output_dir"
                fi
                return $ERR_FILE
            }
        }
        curl_cmd="$curl_cmd -o $output_file"
    else
        curl_cmd="$curl_cmd -o -"
    fi
    
    # Add headers if provided
    if [[ -n "$headers" ]]; then
        # Split headers by comma and add each one
        local IFS=','
        for header in $headers; do
            curl_cmd="$curl_cmd -H \"${header}\""
        done
    fi
    
    # Add data if provided
    if [[ -n "$data" ]]; then
        if [[ "$method" == "GET" ]]; then
            # For GET, append data as query string
            if [[ "$url" == *\?* ]]; then
                url="${url}&${data}"
            else
                url="${url}?${data}"
            fi
        else
            # For other methods, add as request body
            curl_cmd="$curl_cmd -d '$data'"
        fi
    fi
    
    # Add URL
    curl_cmd="$curl_cmd '$url'"
    
    # Execute with retry
    local result
    if result=$(retry_with_backoff "$curl_cmd" "$max_attempts" "$DEFAULT_RETRY_DELAY" "$MAX_RETRY_DELAY" "$timeout"); then
        # Request succeeded
        if type log_debug &>/dev/null; then
            log_debug "HTTP request succeeded: $url"
        fi
        
        # If output to file was requested, just return success
        if [[ -n "$output_file" ]]; then
            return 0
        fi
        
        # Otherwise, output the result
        echo "$result"
        return 0
    else
        # Request failed
        local exit_code=$?
        local error_type=""
        
        # Map curl exit codes to our error codes
        case $exit_code in
            6)  error_type="DNS resolution failure"; exit_code=$ERR_DNS_FAILURE ;;
            7)  error_type="Failed to connect"; exit_code=$ERR_CONNECTION_REFUSED ;;
            22) error_type="HTTP error response"; exit_code=$ERR_HTTP_ERROR ;;
            28) error_type="Request timed out"; exit_code=$ERR_NETWORK_TIMEOUT ;;
            35) error_type="SSL/TLS error"; exit_code=$ERR_SSL_ERROR ;;
            *)  error_type="Request failed (code $exit_code)"; exit_code=$ERR_NETWORK ;;
        esac
        
        if type log_error &>/dev/null; then
            log_error "$error_type: $url"
        fi
        
        return $exit_code
    fi
}

# Enhanced temp file creation with automatic cleanup
create_temp_file() {
    local prefix="${1:-ingestor}"
    local suffix="${2:-}"
    local dir="${3:-/tmp/ingestor}"
    
    # Create directory if it doesn't exist
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            if type log_error &>/dev/null; then
                log_error "Failed to create temporary directory: $dir"
            fi
            return $ERR_FILE
        }
    fi
    
    # Create temp file
    local temp_file
    temp_file=$(mktemp "${dir}/${prefix}_XXXXXX${suffix}")
    if [[ $? -ne 0 || ! -f "$temp_file" ]]; then
        if type log_error &>/dev/null; then
            log_error "Failed to create temporary file"
        fi
        return $ERR_FILE
    fi
    
    # Register for cleanup
    if [[ -z "${_ENHANCED_TEMP_FILES+x}" ]]; then
        _ENHANCED_TEMP_FILES=()
    fi
    _ENHANCED_TEMP_FILES+=("$temp_file")
    
    # Return the path
    echo "$temp_file"
    return 0
}

# Enhanced validation function that provides detailed error messages
validate_conditions() {
    local function_name="$1"
    shift
    
    local error_count=0
    local error_details=""
    
    # Process each condition
    while [[ $# -ge 3 ]]; do
        local condition_name="$1"
        local condition_value="$2"
        local error_message="$3"
        local error_code="${4:-$ERR_VALIDATION}"
        shift 4
        
        # Check the condition
        if [[ -z "${condition_value}" ]]; then
            error_count=$((error_count + 1))
            error_details+=$'\n'"• $error_message"
            
            # Log individual errors
            if type log_warning &>/dev/null; then
                log_warning "Validation error in $function_name: $error_message"
            fi
        fi
    done
    
    # Return success if no errors
    if [[ $error_count -eq 0 ]]; then
        return 0
    fi
    
    # Log aggregated errors
    if type log_error &>/dev/null; then
        log_error "Validation failed in $function_name with $error_count error(s):$error_details"
    fi
    
    return $ERR_VALIDATION
}

# Enhanced error handling for external command execution
run_safe_command() {
    local cmd="$1"
    local error_message="${2:-Command execution failed}"
    local error_code="${3:-$ERR_EXTERNAL_COMMAND}"
    local timeout="${4:-0}"  # 0 means no timeout
    
    # Log command execution
    if type log_debug &>/dev/null; then
        log_debug "Executing command: $cmd"
    fi
    
    # Prepare command execution
    local output=""
    local exit_code=0
    
    # Execute with or without timeout
    if [[ $timeout -gt 0 ]]; then
        # With timeout
        if command -v timeout &>/dev/null; then
            output=$(timeout --preserve-status $timeout bash -c "$cmd" 2>&1)
            exit_code=$?
            
            # Check for timeout
            if [[ $exit_code -eq 124 || $exit_code -eq 137 || $exit_code -eq 143 ]]; then
                if type log_error &>/dev/null; then
                    log_error "Command timed out after ${timeout}s: $cmd"
                fi
                return $ERR_TIMEOUT
            fi
        else
            # Fallback if timeout command is not available
            output=$(bash -c "$cmd" 2>&1)
            exit_code=$?
        fi
    else
        # Without timeout
        output=$(bash -c "$cmd" 2>&1)
        exit_code=$?
    fi
    
    # Check exit code
    if [[ $exit_code -eq 0 ]]; then
        # Command succeeded
        echo "$output"
        return 0
    else
        # Command failed
        if type log_error &>/dev/null; then
            log_error "$error_message (exit code: $exit_code)"
            log_error "Command output: $output"
        fi
        return $error_code
    fi
}

# Safe environment checking and validation
ensure_environment() {
    local required_vars=("$@")
    local missing_vars=()
    
    # Check each required variable
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var+x}" || -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    # Report missing variables
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        local missing_list
        missing_list=$(printf ", %s" "${missing_vars[@]}")
        missing_list=${missing_list:2}  # Remove leading comma and space
        
        if type log_error &>/dev/null; then
            log_error "Missing required environment variables: $missing_list"
        fi
        
        return $ERR_ENVIRONMENT
    fi
    
    return 0
}

# Get exit code description (combination of name and message)
get_exit_code_description() {
    local exit_code="$1"
    local error_name
    local error_message
    
    error_name="$(get_error_name "$exit_code" 2>/dev/null || echo "UNKNOWN_ERROR")"
    error_message="$(get_error_message "$exit_code" 2>/dev/null || echo "Unknown error (code $exit_code)")"
    
    echo "$error_name ($exit_code): $error_message"
}

# Check system resources before performing resource-intensive operations
check_system_resources() {
    local required_disk_space="${1:-100}"  # MB
    local required_memory="${2:-100}"     # MB
    
    # Check disk space
    local available_disk
    available_disk=$(df -m . | awk 'NR==2 {print $4}')
    
    if [[ -z "$available_disk" || "$available_disk" -lt "$required_disk_space" ]]; then
        if type log_error &>/dev/null; then
            log_error "Insufficient disk space. Required: ${required_disk_space}MB, Available: ${available_disk:-unknown}MB"
        fi
        return $ERR_DISK_SPACE
    fi
    
    # Check memory on macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        local available_memory
        available_memory=$(vm_stat | grep "Pages free" | awk '{print $3*4096/1048576}' | cut -d. -f1)
        
        if [[ -z "$available_memory" || "$available_memory" -lt "$required_memory" ]]; then
            if type log_warning &>/dev/null; then
                log_warning "Low memory. Required: ${required_memory}MB, Available: ${available_memory:-unknown}MB"
            fi
            # Not returning error, just a warning for memory
        fi
    fi
    
    # All checks passed
    return 0
}

# Safely execute SQL queries with proper escaping and error handling
safe_sql_query() {
    local db_path="$1"
    local query="$2"
    local return_rowid="${3:-false}"
    
    # Validate inputs
    if [[ -z "$db_path" || -z "$query" ]]; then
        if type log_error &>/dev/null; then
            log_error "Database path and query are required for SQL execution"
        fi
        return $ERR_INVALID_ARG
    fi
    
    # Check if database exists or its directory exists for new databases
    if [[ ! -f "$db_path" ]]; then
        local db_dir
        db_dir=$(dirname "$db_path")
        if [[ ! -d "$db_dir" ]]; then
            if type log_error &>/dev/null; then
                log_error "Database directory not found: $db_dir"
            fi
            return $ERR_FILE_NOT_FOUND
        fi
    fi
    
    # Log query (sanitized)
    if type log_debug &>/dev/null; then
        log_debug "Executing SQL query on $db_path: ${query:0:100}${#query>100?'...':''}"
    fi
    
    # Execute query with retry
    local output
    local exit_code=0
    
    # Use retry for better resilience against temporary issues
    if ! output=$(retry_with_backoff "sqlite3 '$db_path' '$query'" "$MAX_RETRY_COUNT" "$DEFAULT_RETRY_DELAY" "$MAX_RETRY_DELAY" 30); then
        exit_code=$?
        
        # Log detailed error
        if type log_error &>/dev/null; then
            log_error "SQL query failed with code $exit_code: $output"
        fi
        
        # Parse specific error types for better diagnostics
        if [[ "$output" == *"database is locked"* ]]; then
            return $ERR_DB_LOCKED
        elif [[ "$output" == *"no such table"* ]]; then
            return $ERR_DB_SCHEMA
        elif [[ "$output" == *"constraint failed"* ]]; then
            return $ERR_DB_CONSTRAINT
        elif [[ "$output" == *"disk I/O error"* ]]; then
            return $ERR_IO
        else
            return $ERR_DATABASE
        fi
    fi
    
    # If we need to return the last inserted rowid
    if [[ "$return_rowid" == "true" ]]; then
        local rowid
        rowid=$(sqlite3 "$db_path" "SELECT last_insert_rowid();")
        echo "$rowid"
        return 0
    fi
    
    # Return query output
    echo "$output"
    return 0
}

# Escape a string for safe inclusion in SQL
sql_escape() {
    local input="$1"
    # Replace single quotes with double single quotes
    echo "${input//\'/\'\'}"
}

# Document significant errors with detailed diagnostics
document_error() {
    local error_code="$1"
    local function_name="$2"
    local description="$3"
    local source_file="${4:-${BASH_SOURCE[1]:-unknown}}"
    local line_number="${5:-${BASH_LINENO[0]:-0}}"
    
    # Only document if error log is enabled
    if [[ -n "${ERROR_LOG_FILE:-}" && -w "${ERROR_LOG_FILE}" ]]; then
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        local error_name=$(get_error_name "$error_code" 2>/dev/null || echo "UNKNOWN_ERROR")
        
        # Format detailed error report
        {
            echo "====== ERROR REPORT ======="
            echo "Time: $timestamp"
            echo "Error Code: $error_code ($error_name)"
            echo "Location: $source_file:$line_number in function $function_name"
            echo "Description: $description"
            echo "Call Stack:"
            
            # Generate a stack trace
            local i=0
            while caller $i > /dev/null 2>&1; do
                local frame_info=$(caller $i)
                local line_num=$(echo "$frame_info" | awk '{print $1}')
                local func_name=$(echo "$frame_info" | awk '{print $2}')
                local src_file=$(echo "$frame_info" | awk '{print $3}')
                echo "  #$i: $src_file:$line_num in function $func_name"
                ((i++))
            done
            
            echo "Environment:"
            echo "  Shell: $SHELL"
            echo "  User: $(whoami)"
            echo "  Working Directory: $(pwd)"
            echo "  PID: $$"
            echo "=========================="
            echo ""
        } >> "$ERROR_LOG_FILE"
    fi
    
    # Log a summary message
    if type log_error &>/dev/null; then
        log_error "Error $error_code in $function_name: $description (see $ERROR_LOG_FILE for details)"
    fi
}

# Export functions for use by other modules
export -f init_enhanced_error_handler
export -f enhanced_error_trap
export -f cleanup_handler
export -f handle_sigint
export -f handle_sigterm
export -f attempt_error_recovery
export -f enhanced_exit
export -f try
export -f catch
export -f finally
export -f retry_with_backoff
export -f retry_function
export -f acquire_lock
export -f release_lock
export -f begin_transaction
export -f commit_transaction
export -f rollback_transaction
export -f enhanced_http_request
export -f create_temp_file
export -f validate_conditions
export -f run_safe_command
export -f ensure_environment
export -f get_exit_code_description
export -f check_system_resources
export -f safe_sql_query
export -f sql_escape
export -f document_error