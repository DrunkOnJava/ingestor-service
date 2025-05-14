#!/bin/bash
# Performance profiling module for ingestor-system
# Provides tools for measuring execution time and resource usage of operations

# Ensure this script can be sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This script should be sourced, not executed directly."
    exit 1
fi

# Dependencies
if ! command -v date &>/dev/null; then
    echo "Error: 'date' command not found. Required for profiling."
    return 1
fi

# Import logging module if available
if [[ -f "${BASH_SOURCE%/*}/logging.sh" ]]; then
    source "${BASH_SOURCE%/*}/logging.sh"
fi

# Initialize profiling module
PROFILER_INITIALIZED=false
PROFILING_ENABLED=false
PROFILING_LOG_DIR="${HOME}/.ingestor/logs/profiling"
PROFILING_LOG_FILE=""
PROFILING_RESULTS=()
PROFILING_TIMESTAMP_FORMAT="%s%N"  # Format for high-precision timestamps

# Benchmark reference values
declare -A BENCHMARK_TIMES

# Initialize the profiler
init_profiler() {
    local enabled="${1:-true}"
    local log_dir="${2:-$PROFILING_LOG_DIR}"
    
    # Create profiling directory if it doesn't exist
    mkdir -p "$log_dir"
    
    # Initialize timestamp-based log file name
    PROFILING_LOG_FILE="${log_dir}/profiling_$(date +%Y%m%d_%H%M%S).log"
    PROFILING_ENABLED="$enabled"
    
    # Initialize benchmarks from stored values if available
    local benchmark_file="${log_dir}/benchmarks.json"
    if [[ -f "$benchmark_file" ]]; then
        if command -v jq &>/dev/null; then
            # Use jq to parse benchmark values
            while read -r line; do
                IFS='=' read -r key value <<< "$line"
                BENCHMARK_TIMES["$key"]="$value"
            done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$benchmark_file")
        else
            # Fallback to simple parsing
            while IFS=":" read -r key value; do
                key=$(echo "$key" | tr -d ' "')
                value=$(echo "$value" | tr -d ' ",')
                [[ -n "$key" && -n "$value" ]] && BENCHMARK_TIMES["$key"]="$value"
            done < "$benchmark_file"
        fi
    fi
    
    # Write header to log file
    {
        echo "# Ingestor System Performance Profiling"
        echo "# Started: $(date)"
        echo "# System: $(uname -a)"
        echo "# --------------------------------------"
        echo "operation,duration_ms,timestamp,memory_kb,cpu_percent"
    } > "$PROFILING_LOG_FILE"
    
    PROFILER_INITIALIZED=true
    
    if type log_info &>/dev/null; then
        log_info "Performance profiler initialized. Profiling $(if [[ "$PROFILING_ENABLED" = "true" ]]; then echo "enabled"; else echo "disabled"; fi)"
    else
        echo "Performance profiler initialized. Profiling $(if [[ "$PROFILING_ENABLED" = "true" ]]; then echo "enabled"; else echo "disabled"; fi)"
    fi
}

# Get current high-precision timestamp in nanoseconds
get_timestamp_ns() {
    date +$PROFILING_TIMESTAMP_FORMAT
}

# Convert nanosecond duration to milliseconds
ns_to_ms() {
    local ns="$1"
    echo "$ns / 1000000" | bc
}

# Start profiling a specific operation
start_profile() {
    local operation="$1"
    local result
    
    if [[ "$PROFILER_INITIALIZED" != "true" ]]; then
        init_profiler
    fi
    
    if [[ "$PROFILING_ENABLED" != "true" ]]; then
        return 0
    fi
    
    # Store timestamp
    result=$(get_timestamp_ns)
    
    # Store memory usage
    local mem_usage
    mem_usage=$(ps -o rss= -p $$)
    
    echo "$operation:$result:$mem_usage" > "/tmp/ingestor_profile_${operation}_$$"
}

# End profiling for an operation and log results
end_profile() {
    local operation="$1"
    local additional_info="${2:-}"
    local temp_file="/tmp/ingestor_profile_${operation}_$$"
    
    if [[ "$PROFILING_ENABLED" != "true" ]]; then
        rm -f "$temp_file" 2>/dev/null
        return 0
    fi
    
    if [[ ! -f "$temp_file" ]]; then
        if type log_warning &>/dev/null; then
            log_warning "No profile start data found for operation: $operation"
        fi
        return 1
    fi
    
    # Read start timestamp and memory
    local start_data
    start_data=$(cat "$temp_file")
    rm -f "$temp_file"
    
    IFS=':' read -r op start_time start_mem <<< "$start_data"
    
    # Get end data
    local end_time
    end_time=$(get_timestamp_ns)
    
    # Calculate duration in nanoseconds
    local duration_ns=$((end_time - start_time))
    
    # Convert to milliseconds
    local duration_ms
    duration_ms=$(ns_to_ms "$duration_ns")
    
    # Get current memory and calculate diff
    local end_mem
    end_mem=$(ps -o rss= -p $$)
    local mem_diff=$((end_mem - start_mem))
    
    # Get CPU usage (simplistic approach)
    local cpu_percent
    cpu_percent=$(ps -o %cpu= -p $$)
    
    # Append operation info if provided
    local extended_operation="$operation"
    [[ -n "$additional_info" ]] && extended_operation="${operation}:${additional_info}"
    
    # Log results
    echo "${extended_operation},${duration_ms},$(date +%s),${mem_diff},${cpu_percent}" >> "$PROFILING_LOG_FILE"
    
    # Store results in memory
    PROFILING_RESULTS+=("${extended_operation},${duration_ms},$(date +%s),${mem_diff},${cpu_percent}")
    
    # Add to running average
    update_benchmark "$operation" "$duration_ms"
    
    # Return the duration for potential use
    echo "$duration_ms"
}

# Profile a command execution
profile_command() {
    local operation="$1"
    shift
    local command="$@"
    
    if [[ "$PROFILING_ENABLED" != "true" ]]; then
        # Just execute the command if profiling is disabled
        eval "$command"
        return $?
    fi
    
    # Start profiling
    start_profile "$operation"
    
    # Execute the command
    eval "$command"
    local cmd_result=$?
    
    # End profiling
    end_profile "$operation"
    
    return $cmd_result
}

# Profile a function or code block
profile_function() {
    local operation="$1"
    local function_name="$2"
    shift 2
    
    if [[ "$PROFILING_ENABLED" != "true" ]]; then
        # Just execute the function if profiling is disabled
        "$function_name" "$@"
        return $?
    fi
    
    # Start profiling
    start_profile "$operation"
    
    # Execute the function
    "$function_name" "$@"
    local func_result=$?
    
    # End profiling
    end_profile "$operation"
    
    return $func_result
}

# Update benchmark data for an operation
update_benchmark() {
    local operation="$1"
    local duration="$2"
    
    if [[ -z "${BENCHMARK_TIMES[$operation]}" ]]; then
        BENCHMARK_TIMES["$operation"]="$duration"
    else
        # Update running average (80% old value, 20% new value for smoothing)
        local current_avg="${BENCHMARK_TIMES[$operation]}"
        local new_avg
        new_avg=$(echo "scale=2; ($current_avg * 0.8) + ($duration * 0.2)" | bc)
        BENCHMARK_TIMES["$operation"]="$new_avg"
    fi
}

# Compare current execution to benchmark
compare_to_benchmark() {
    local operation="$1"
    local duration="$2"
    
    if [[ -z "${BENCHMARK_TIMES[$operation]}" ]]; then
        echo "No benchmark data for $operation"
        return 0
    fi
    
    local benchmark="${BENCHMARK_TIMES[$operation]}"
    local ratio
    ratio=$(echo "scale=2; $duration / $benchmark" | bc)
    
    echo "$ratio"
}

# Save benchmarks to file
save_benchmarks() {
    local benchmark_file="${PROFILING_LOG_DIR}/benchmarks.json"
    
    if command -v jq &>/dev/null; then
        # Create JSON structure with jq
        (
            echo "{"
            local first=true
            for key in "${!BENCHMARK_TIMES[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                echo "  \"$key\": ${BENCHMARK_TIMES[$key]}"
            done
            echo "}"
        ) | jq '.' > "$benchmark_file"
    else
        # Fallback to manual JSON creation
        (
            echo "{"
            local first=true
            for key in "${!BENCHMARK_TIMES[@]}"; do
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                echo "  \"$key\": ${BENCHMARK_TIMES[$key]}"
            done
            echo "}"
        ) > "$benchmark_file"
    fi
}

# Generate a profiling report
generate_profiling_report() {
    local report_file="${1:-${PROFILING_LOG_DIR}/profiling_report_$(date +%Y%m%d_%H%M%S).md}"
    
    # Create report header
    {
        echo "# Ingestor System Performance Report"
        echo "## Generated: $(date)"
        echo "## System: $(uname -a)"
        echo
        echo "## Summary"
        echo
        echo "| Operation | Avg Duration (ms) | Current vs Benchmark | Memory Usage (KB) | CPU (%) |"
        echo "|-----------|------------------:|---------------------:|-----------------:|--------:|"
    } > "$report_file"
    
    # Process results
    declare -A operation_times
    declare -A operation_count
    declare -A operation_memory
    declare -A operation_cpu
    
    # Collect data from profiling results
    for result in "${PROFILING_RESULTS[@]}"; do
        IFS=',' read -r op duration timestamp memory cpu <<< "$result"
        
        # Remove additional info from operation name if present
        operation="${op%%:*}"
        
        # Initialize if not exists
        [[ -z "${operation_times[$operation]}" ]] && operation_times["$operation"]=0
        [[ -z "${operation_count[$operation]}" ]] && operation_count["$operation"]=0
        [[ -z "${operation_memory[$operation]}" ]] && operation_memory["$operation"]=0
        [[ -z "${operation_cpu[$operation]}" ]] && operation_cpu["$operation"]=0
        
        # Update values
        operation_times["$operation"]=$((operation_times["$operation"] + duration))
        operation_count["$operation"]=$((operation_count["$operation"] + 1))
        operation_memory["$operation"]=$((operation_memory["$operation"] + memory))
        operation_cpu["$operation"]=$(echo "scale=2; ${operation_cpu[$operation]} + $cpu" | bc)
    done
    
    # Generate summary table
    for op in "${!operation_count[@]}"; do
        local avg_time
        avg_time=$(echo "scale=2; ${operation_times[$op]} / ${operation_count[$op]}" | bc)
        
        local avg_memory
        avg_memory=$(echo "scale=2; ${operation_memory[$op]} / ${operation_count[$op]}" | bc)
        
        local avg_cpu
        avg_cpu=$(echo "scale=2; ${operation_cpu[$op]} / ${operation_count[$op]}" | bc)
        
        local comparison=""
        if [[ -n "${BENCHMARK_TIMES[$op]}" ]]; then
            local ratio
            ratio=$(echo "scale=2; $avg_time / ${BENCHMARK_TIMES[$op]}" | bc)
            
            if (( $(echo "$ratio > 1.5" | bc -l) )); then
                comparison="❌ $ratio× (slower)"
            elif (( $(echo "$ratio < 0.8" | bc -l) )); then
                comparison="✅ $ratio× (faster)"
            else
                comparison="✓ $ratio× (normal)"
            fi
        else
            comparison="N/A (no benchmark)"
        fi
        
        echo "| $op | $avg_time | $comparison | $avg_memory | $avg_cpu |" >> "$report_file"
    done
    
    # Add details section
    {
        echo
        echo "## Operation Details"
        echo
        
        # Add a section for each operation
        for op in "${!operation_count[@]}"; do
            echo "### $op"
            echo
            echo "- **Count:** ${operation_count[$op]} executions"
            echo "- **Average Duration:** $(echo "scale=2; ${operation_times[$op]} / ${operation_count[$op]}" | bc) ms"
            echo "- **Total Duration:** ${operation_times[$op]} ms"
            
            if [[ -n "${BENCHMARK_TIMES[$op]}" ]]; then
                echo "- **Benchmark Value:** ${BENCHMARK_TIMES[$op]} ms"
                
                local ratio
                ratio=$(echo "scale=2; (${operation_times[$op]} / ${operation_count[$op]}) / ${BENCHMARK_TIMES[$op]}" | bc)
                local comp_text="normal performance"
                
                if (( $(echo "$ratio > 1.5" | bc -l) )); then
                    comp_text="significantly slower than benchmark"
                elif (( $(echo "$ratio < 0.8" | bc -l) )); then
                    comp_text="significantly faster than benchmark"
                fi
                
                echo "- **Performance Assessment:** $comp_text ($ratio× benchmark)"
            else
                echo "- **Performance Assessment:** No benchmark available"
            fi
            
            echo
        done
        
        # Add optimization recommendations
        echo "## Optimization Recommendations"
        echo
        
        # Sort operations by average time (slowest first)
        declare -a sorted_operations
        for op in "${!operation_count[@]}"; do
            sorted_operations+=("$op")
        done
        
        # Create a temp file for sorting
        local temp_sort_file="/tmp/ingestor_profiling_sort_$$"
        for op in "${sorted_operations[@]}"; do
            local avg_time
            avg_time=$(echo "scale=2; ${operation_times[$op]} / ${operation_count[$op]}" | bc)
            echo "$avg_time $op" >> "$temp_sort_file"
        done
        
        # Sort by time (numeric, reverse)
        local sorted
        sorted=$(sort -nr "$temp_sort_file")
        rm -f "$temp_sort_file"
        
        # Process sorted list
        local recommendations_added=false
        while IFS=' ' read -r avg_time op; do
            # Only recommend optimizing if significantly slower than benchmark or taking >100ms
            if [[ -n "${BENCHMARK_TIMES[$op]}" ]]; then
                local ratio
                ratio=$(echo "scale=2; $avg_time / ${BENCHMARK_TIMES[$op]}" | bc)
                
                if (( $(echo "$ratio > 1.5" | bc -l) )); then
                    recommendations_added=true
                    echo "1. **$op**: Taking $avg_time ms (${ratio}× benchmark)"
                    echo "   - This operation is significantly slower than normal and should be prioritized for optimization."
                    echo
                fi
            elif (( $(echo "$avg_time > 100" | bc -l) )); then
                # If no benchmark but operation is slow
                recommendations_added=true
                echo "1. **$op**: Taking $avg_time ms"
                echo "   - This operation is relatively slow but has no benchmark for comparison."
                echo "   - Consider establishing a benchmark or investigating optimization opportunities."
                echo
            fi
        done <<< "$sorted"
        
        # If no slow operations found
        if [[ "$recommendations_added" != "true" ]]; then
            echo "No specific performance issues identified. All operations are within normal performance thresholds."
        fi
    } >> "$report_file"
    
    echo "$report_file"
}

# Enable profiling
enable_profiling() {
    PROFILING_ENABLED=true
    if type log_info &>/dev/null; then
        log_info "Performance profiling enabled"
    else
        echo "Performance profiling enabled"
    fi
}

# Disable profiling
disable_profiling() {
    PROFILING_ENABLED=false
    if type log_info &>/dev/null; then
        log_info "Performance profiling disabled"
    else
        echo "Performance profiling disabled"
    fi
}

# Check if profiling is initialized
if [[ "$PROFILER_INITIALIZED" != "true" ]]; then
    # Auto-initialize with profiling disabled by default
    init_profiler false
fi