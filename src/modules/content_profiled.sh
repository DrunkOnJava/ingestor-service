#!/bin/bash
# Performance profiled content module for ingestor-system
# Integrates profiling capabilities with content processing operations

# First import the normal content module
if [[ -f "${BASH_SOURCE%/*}/content.sh" ]]; then
    source "${BASH_SOURCE%/*}/content.sh"
else
    echo "Error: content.sh not found!" >&2
    exit 1
fi

# Import the profiler module
if [[ -f "${BASH_SOURCE%/*}/profiler.sh" ]]; then
    source "${BASH_SOURCE%/*}/profiler.sh"
else
    echo "Error: profiler.sh not found!" >&2
    exit 1
fi

# Override content functions with profiled versions
# Each function will preserve the original functionality but add profiling

# Profiled version of detect_content_type
detect_content_type_profiled() {
    local input="$1"
    
    # Start profiling
    start_profile "content_detect_type"
    
    # Call original function
    local result
    result=$(detect_content_type "$@")
    local rc=$?
    
    # Capture file size for better profiling context
    local file_size="unknown"
    if [[ -f "$input" ]]; then
        file_size=$(stat -f%z "$input" 2>/dev/null || echo "unknown")
    fi
    
    # End profiling with additional info
    end_profile "content_detect_type" "${result}:${file_size}b"
    
    echo "$result"
    return $rc
}

# Profiled version of process_content
process_content_profiled() {
    local content_path="$1"
    local database="$2"
    local enable_chunking="${3:-$ENABLE_CHUNKING}"
    local chunk_size="${4:-$CHUNK_SIZE}"
    local chunk_overlap="${5:-$CHUNK_OVERLAP}"
    local chunk_strategy="${6:-$CHUNK_STRATEGY}"
    
    # Start profiling
    start_profile "content_process"
    
    # Call original function
    process_content "$@"
    local result=$?
    
    # Get content type and size for better profiling context
    local content_type
    content_type=$(detect_content_type "$content_path")
    
    local file_size
    if [[ -f "$content_path" ]]; then
        file_size=$(stat -f%z "$content_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process" "${content_type}:${file_size}b:${database}"
    
    return $result
}

# Profiled version of process_image
process_image_profiled() {
    local image_path="$1"
    local database="$2"
    
    # Start profiling
    start_profile "content_process_image"
    
    # Call original function
    process_image "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$image_path" ]]; then
        file_size=$(stat -f%z "$image_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_image" "${file_size}b:${database}"
    
    return $result
}

# Profiled version of process_video
process_video_profiled() {
    local video_path="$1"
    local database="$2"
    
    # Start profiling
    start_profile "content_process_video"
    
    # Call original function
    process_video "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$video_path" ]]; then
        file_size=$(stat -f%z "$video_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_video" "${file_size}b:${database}"
    
    return $result
}

# Profiled version of process_pdf
process_pdf_profiled() {
    local pdf_path="$1"
    local database="$2"
    
    # Start profiling
    start_profile "content_process_pdf"
    
    # Call original function
    process_pdf "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$pdf_path" ]]; then
        file_size=$(stat -f%z "$pdf_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_pdf" "${file_size}b:${database}"
    
    return $result
}

# Profiled version of process_pdf_with_chunking
process_pdf_with_chunking_profiled() {
    local pdf_path="$1"
    local database="$2"
    local chunk_size="$3"
    local chunk_overlap="$4"
    local chunk_strategy="$5"
    
    # Start profiling
    start_profile "content_process_pdf_chunked"
    
    # Call original function
    process_pdf_with_chunking "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$pdf_path" ]]; then
        file_size=$(stat -f%z "$pdf_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_pdf_chunked" "${file_size}b:${chunk_size}:${database}"
    
    return $result
}

# Profiled version of process_text
process_text_profiled() {
    local text_path="$1"
    local database="$2"
    
    # Start profiling
    start_profile "content_process_text"
    
    # Call original function
    process_text "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$text_path" ]]; then
        file_size=$(stat -f%z "$text_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_text" "${file_size}b:${database}"
    
    return $result
}

# Profiled version of process_text_with_chunking
process_text_with_chunking_profiled() {
    local text_path="$1"
    local database="$2"
    local chunk_size="$3"
    local chunk_overlap="$4"
    local chunk_strategy="$5"
    
    # Start profiling
    start_profile "content_process_text_chunked"
    
    # Call original function
    process_text_with_chunking "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$text_path" ]]; then
        file_size=$(stat -f%z "$text_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_text_chunked" "${file_size}b:${chunk_size}:${database}"
    
    return $result
}

# Profiled version of process_code
process_code_profiled() {
    local code_path="$1"
    local database="$2"
    local content_type="$3"
    
    # Start profiling
    start_profile "content_process_code"
    
    # Call original function
    process_code "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$code_path" ]]; then
        file_size=$(stat -f%z "$code_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_code" "${content_type}:${file_size}b:${database}"
    
    return $result
}

# Profiled version of process_code_with_chunking
process_code_with_chunking_profiled() {
    local code_path="$1"
    local database="$2"
    local content_type="$3"
    local chunk_size="$4"
    local chunk_overlap="$5"
    local chunk_strategy="$6"
    
    # Start profiling
    start_profile "content_process_code_chunked"
    
    # Call original function
    process_code_with_chunking "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$code_path" ]]; then
        file_size=$(stat -f%z "$code_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_code_chunked" "${content_type}:${file_size}b:${chunk_size}:${database}"
    
    return $result
}

# Profiled version of process_generic
process_generic_profiled() {
    local file_path="$1"
    local database="$2"
    local content_type="$3"
    
    # Start profiling
    start_profile "content_process_generic"
    
    # Call original function
    process_generic "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$file_path" ]]; then
        file_size=$(stat -f%z "$file_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # End profiling with additional info
    end_profile "content_process_generic" "${content_type}:${file_size}b:${database}"
    
    return $result
}

# Profiled version of chunk_text_file
chunk_text_file_profiled() {
    local file_path="$1"
    local chunk_size="${2:-500000}"
    local chunk_overlap="${3:-5000}"
    local chunk_strategy="${4:-size}"
    local output_dir="${TEMP_DIR}"
    
    # Start profiling
    start_profile "content_chunk_text"
    
    # Call original function
    chunk_text_file "$@"
    local result=$?
    
    # Get file size for better profiling context
    local file_size
    if [[ -f "$file_path" ]]; then
        file_size=$(stat -f%z "$file_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # Count output chunks
    local chunk_count=0
    local basename
    basename=$(basename "$file_path")
    chunk_count=$(find "$output_dir" -name "chunk_${basename}_*" -type f | wc -l)
    
    # End profiling with additional info
    end_profile "content_chunk_text" "${chunk_strategy}:${file_size}b:${chunk_count}chunks"
    
    return $result
}

# Replace original functions with profiled versions
enable_content_profiling() {
    # Save original functions if not already saved
    if [[ -z "$CONTENT_PROFILING_ENABLED" ]]; then
        # Original function references
        declare -f detect_content_type > /dev/null && detect_content_type_original=$(declare -f detect_content_type)
        declare -f process_content > /dev/null && process_content_original=$(declare -f process_content)
        declare -f process_image > /dev/null && process_image_original=$(declare -f process_image)
        declare -f process_video > /dev/null && process_video_original=$(declare -f process_video)
        declare -f process_pdf > /dev/null && process_pdf_original=$(declare -f process_pdf)
        declare -f process_pdf_with_chunking > /dev/null && process_pdf_with_chunking_original=$(declare -f process_pdf_with_chunking)
        declare -f process_text > /dev/null && process_text_original=$(declare -f process_text)
        declare -f process_text_with_chunking > /dev/null && process_text_with_chunking_original=$(declare -f process_text_with_chunking)
        declare -f process_code > /dev/null && process_code_original=$(declare -f process_code)
        declare -f process_code_with_chunking > /dev/null && process_code_with_chunking_original=$(declare -f process_code_with_chunking)
        declare -f process_generic > /dev/null && process_generic_original=$(declare -f process_generic)
        declare -f chunk_text_file > /dev/null && chunk_text_file_original=$(declare -f chunk_text_file)
    fi

    # Replace with profiled versions
    eval "detect_content_type() { detect_content_type_profiled \"\$@\"; }"
    eval "process_content() { process_content_profiled \"\$@\"; }"
    eval "process_image() { process_image_profiled \"\$@\"; }"
    eval "process_video() { process_video_profiled \"\$@\"; }"
    eval "process_pdf() { process_pdf_profiled \"\$@\"; }"
    eval "process_pdf_with_chunking() { process_pdf_with_chunking_profiled \"\$@\"; }"
    eval "process_text() { process_text_profiled \"\$@\"; }"
    eval "process_text_with_chunking() { process_text_with_chunking_profiled \"\$@\"; }"
    eval "process_code() { process_code_profiled \"\$@\"; }"
    eval "process_code_with_chunking() { process_code_with_chunking_profiled \"\$@\"; }"
    eval "process_generic() { process_generic_profiled \"\$@\"; }"
    eval "chunk_text_file() { chunk_text_file_profiled \"\$@\"; }"
    
    CONTENT_PROFILING_ENABLED="true"
    if type log_info &>/dev/null; then
        log_info "Content processing profiling enabled"
    else
        echo "Content processing profiling enabled"
    fi
}

# Restore original functions
disable_content_profiling() {
    if [[ "$CONTENT_PROFILING_ENABLED" == "true" ]]; then
        # Restore original functions
        [[ -n "$detect_content_type_original" ]] && eval "$detect_content_type_original"
        [[ -n "$process_content_original" ]] && eval "$process_content_original"
        [[ -n "$process_image_original" ]] && eval "$process_image_original"
        [[ -n "$process_video_original" ]] && eval "$process_video_original"
        [[ -n "$process_pdf_original" ]] && eval "$process_pdf_original"
        [[ -n "$process_pdf_with_chunking_original" ]] && eval "$process_pdf_with_chunking_original"
        [[ -n "$process_text_original" ]] && eval "$process_text_original"
        [[ -n "$process_text_with_chunking_original" ]] && eval "$process_text_with_chunking_original"
        [[ -n "$process_code_original" ]] && eval "$process_code_original"
        [[ -n "$process_code_with_chunking_original" ]] && eval "$process_code_with_chunking_original"
        [[ -n "$process_generic_original" ]] && eval "$process_generic_original"
        [[ -n "$chunk_text_file_original" ]] && eval "$chunk_text_file_original"
        
        CONTENT_PROFILING_ENABLED="false"
        if type log_info &>/dev/null; then
            log_info "Content processing profiling disabled"
        else
            echo "Content processing profiling disabled"
        fi
    fi
}

# Enable profiling by default if PROFILING_ENABLED is set
if [[ "$PROFILING_ENABLED" == "true" ]]; then
    enable_content_profiling
fi