#!/bin/bash
# Performance profiled Claude AI module for ingestor-system
# Integrates profiling capabilities with Claude AI operations

# First import the normal claude module
if [[ -f "${BASH_SOURCE%/*}/claude.sh" ]]; then
    source "${BASH_SOURCE%/*}/claude.sh"
else
    echo "Error: claude.sh not found!" >&2
    exit 1
fi

# Import the profiler module
if [[ -f "${BASH_SOURCE%/*}/profiler.sh" ]]; then
    source "${BASH_SOURCE%/*}/profiler.sh"
else
    echo "Error: profiler.sh not found!" >&2
    exit 1
fi

# Override claude functions with profiled versions
# Each function will preserve the original functionality but add profiling

# Profiled version of analyze_with_claude
analyze_with_claude_profiled() {
    local content_path="$1"
    local content_type="$2"
    local model="${3:-claude-3-haiku-20240307}"
    
    # Start profiling
    start_profile "claude_analyze"
    
    # Call original function
    local result
    result=$(analyze_with_claude "$@")
    local rc=$?
    
    # Get file size for better profiling context
    local file_size="unknown"
    if [[ -f "$content_path" ]]; then
        file_size=$(stat -f%z "$content_path" 2>/dev/null || echo "unknown")
    fi
    
    # Get token count estimate (crude approximation)
    local token_estimate="unknown"
    if [[ -f "$content_path" ]]; then
        # Very rough estimation: ~4 chars per token
        token_estimate=$(echo "scale=0; $(wc -c < "$content_path") / 4" | bc)
    fi
    
    # End profiling with additional info
    end_profile "claude_analyze" "${content_type}:${model}:${file_size}b:~${token_estimate}tokens"
    
    # Return the original result
    if [[ $rc -eq 0 ]]; then
        echo "$result"
    fi
    return $rc
}

# Profiled version of claude_batch_analyze
claude_batch_analyze_profiled() {
    local contents_json="$1"
    local model="${2:-claude-3-haiku-20240307}"
    
    # Start profiling
    start_profile "claude_batch_analyze"
    
    # Call original function
    local result
    result=$(claude_batch_analyze "$@")
    local rc=$?
    
    # Get size of input JSON for profiling context
    local input_size="unknown"
    if [[ -f "$contents_json" ]]; then
        input_size=$(stat -f%z "$contents_json" 2>/dev/null || echo "unknown")
    elif [[ -n "$contents_json" ]]; then
        input_size=${#contents_json}
    fi
    
    # Get batch size (number of items)
    local batch_count="unknown"
    if [[ -f "$contents_json" ]]; then
        # Count array items if file exists
        if command -v jq &>/dev/null; then
            batch_count=$(jq 'length' < "$contents_json" 2>/dev/null || echo "unknown")
        else
            # Crude count of opening braces if jq not available
            batch_count=$(grep -o '{' "$contents_json" | wc -l)
        fi
    elif [[ -n "$contents_json" ]]; then
        # Crude count of opening braces if string provided directly
        batch_count=$(echo "$contents_json" | grep -o '{' | wc -l)
    fi
    
    # End profiling with additional info
    end_profile "claude_batch_analyze" "${model}:${batch_count}items:${input_size}b"
    
    # Return the original result
    if [[ $rc -eq 0 ]]; then
        echo "$result"
    fi
    return $rc
}

# Profiled version of generate_embeddings
generate_embeddings_profiled() {
    local content="$1"
    local model="${2:-claude-3-haiku-20240307}"
    
    # Start profiling
    start_profile "claude_embeddings"
    
    # Call original function
    local result
    result=$(generate_embeddings "$@")
    local rc=$?
    
    # Get input size for profiling context
    local content_size=${#content}
    
    # Get token count estimate (crude approximation)
    local token_estimate=$(echo "scale=0; $content_size / 4" | bc)
    
    # End profiling with additional info
    end_profile "claude_embeddings" "${model}:${content_size}chars:~${token_estimate}tokens"
    
    # Return the original result
    if [[ $rc -eq 0 ]]; then
        echo "$result"
    fi
    return $rc
}

# Profiled version of claude_summarize
claude_summarize_profiled() {
    local content="$1"
    local model="${2:-claude-3-haiku-20240307}"
    
    # Start profiling
    start_profile "claude_summarize"
    
    # Call original function
    local result
    result=$(claude_summarize "$@")
    local rc=$?
    
    # Get input size for profiling context
    local content_size=${#content}
    
    # Get token count estimate (crude approximation)
    local token_estimate=$(echo "scale=0; $content_size / 4" | bc)
    
    # End profiling with additional info
    end_profile "claude_summarize" "${model}:${content_size}chars:~${token_estimate}tokens"
    
    # Return the original result
    if [[ $rc -eq 0 ]]; then
        echo "$result"
    fi
    return $rc
}

# Profiled version of claude_extract_metadata
claude_extract_metadata_profiled() {
    local content="$1"
    local content_type="$2"
    local model="${3:-claude-3-haiku-20240307}"
    
    # Start profiling
    start_profile "claude_extract_metadata"
    
    # Call original function
    local result
    result=$(claude_extract_metadata "$@")
    local rc=$?
    
    # Get input size for profiling context
    local content_size=${#content}
    
    # Get token count estimate (crude approximation)
    local token_estimate=$(echo "scale=0; $content_size / 4" | bc)
    
    # End profiling with additional info
    end_profile "claude_extract_metadata" "${content_type}:${model}:${content_size}chars:~${token_estimate}tokens"
    
    # Return the original result
    if [[ $rc -eq 0 ]]; then
        echo "$result"
    fi
    return $rc
}

# Replace original functions with profiled versions
enable_claude_profiling() {
    # Save original functions if not already saved
    if [[ -z "$CLAUDE_PROFILING_ENABLED" ]]; then
        # Original function references
        declare -f analyze_with_claude > /dev/null && analyze_with_claude_original=$(declare -f analyze_with_claude)
        declare -f claude_batch_analyze > /dev/null && claude_batch_analyze_original=$(declare -f claude_batch_analyze)
        declare -f generate_embeddings > /dev/null && generate_embeddings_original=$(declare -f generate_embeddings)
        declare -f claude_summarize > /dev/null && claude_summarize_original=$(declare -f claude_summarize)
        declare -f claude_extract_metadata > /dev/null && claude_extract_metadata_original=$(declare -f claude_extract_metadata)
    fi

    # Replace with profiled versions
    eval "analyze_with_claude() { analyze_with_claude_profiled \"\$@\"; }"
    eval "claude_batch_analyze() { claude_batch_analyze_profiled \"\$@\"; }"
    eval "generate_embeddings() { generate_embeddings_profiled \"\$@\"; }"
    eval "claude_summarize() { claude_summarize_profiled \"\$@\"; }"
    eval "claude_extract_metadata() { claude_extract_metadata_profiled \"\$@\"; }"
    
    CLAUDE_PROFILING_ENABLED="true"
    if type log_info &>/dev/null; then
        log_info "Claude AI profiling enabled"
    else
        echo "Claude AI profiling enabled"
    fi
}

# Restore original functions
disable_claude_profiling() {
    if [[ "$CLAUDE_PROFILING_ENABLED" == "true" ]]; then
        # Restore original functions
        [[ -n "$analyze_with_claude_original" ]] && eval "$analyze_with_claude_original"
        [[ -n "$claude_batch_analyze_original" ]] && eval "$claude_batch_analyze_original"
        [[ -n "$generate_embeddings_original" ]] && eval "$generate_embeddings_original"
        [[ -n "$claude_summarize_original" ]] && eval "$claude_summarize_original"
        [[ -n "$claude_extract_metadata_original" ]] && eval "$claude_extract_metadata_original"
        
        CLAUDE_PROFILING_ENABLED="false"
        if type log_info &>/dev/null; then
            log_info "Claude AI profiling disabled"
        else
            echo "Claude AI profiling disabled"
        fi
    fi
}

# Enable profiling by default if PROFILING_ENABLED is set
if [[ "$PROFILING_ENABLED" == "true" ]]; then
    enable_claude_profiling
fi