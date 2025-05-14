#!/bin/bash
# Performance profiled database module for ingestor-system
# Integrates profiling capabilities with database operations

# First import the normal database module
if [[ -f "${BASH_SOURCE%/*}/database.sh" ]]; then
    source "${BASH_SOURCE%/*}/database.sh"
else
    echo "Error: database.sh not found!" >&2
    exit 1
fi

# Import the profiler module
if [[ -f "${BASH_SOURCE%/*}/profiler.sh" ]]; then
    source "${BASH_SOURCE%/*}/profiler.sh"
else
    echo "Error: profiler.sh not found!" >&2
    exit 1
fi

# Override database functions with profiled versions
# Each function will preserve the original functionality but add profiling

# Profiled version of init_database
init_database_profiled() {
    local db_path="$1"
    local schema_file="$2"
    local force_recreate="${3:-false}"
    
    # Additional data to include in profile
    local db_name=$(basename "$db_path" .sqlite)
    
    # Start profiling
    start_profile "db_init"
    
    # Call original function
    init_database "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_init" "$db_name"
    
    return $result
}

# Profiled version of store_image_data
store_image_data_profiled() {
    local db_name="$1"
    local image_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    # Additional data to include in profile
    local file_size
    if [[ -f "$image_path" ]]; then
        file_size=$(stat -f%z "$image_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_image"
    
    # Call original function
    store_image_data "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_image" "${db_name}:${file_size}b"
    
    return $result
}

# Profiled version of store_video_data
store_video_data_profiled() {
    local db_name="$1"
    local video_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    # Additional data to include in profile
    local file_size
    if [[ -f "$video_path" ]]; then
        file_size=$(stat -f%z "$video_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_video"
    
    # Call original function
    store_video_data "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_video" "${db_name}:${file_size}b"
    
    return $result
}

# Profiled version of store_document_data
store_document_data_profiled() {
    local db_name="$1"
    local document_path="$2"
    local text_file="$3"
    local analysis_file="$4"
    
    # Additional data to include in profile
    local file_size
    if [[ -f "$document_path" ]]; then
        file_size=$(stat -f%z "$document_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_document"
    
    # Call original function
    store_document_data "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_document" "${db_name}:${file_size}b"
    
    return $result
}

# Profiled version of store_document_chunk
store_document_chunk_profiled() {
    local db_name="$1"
    local document_path="$2"
    local chunk_file="$3"
    local analysis_file="$4"
    
    # Additional data to include in profile
    local chunk_size
    if [[ -f "$chunk_file" ]]; then
        chunk_size=$(stat -f%z "$chunk_file" 2>/dev/null || echo "unknown")
    else
        chunk_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_doc_chunk"
    
    # Call original function
    store_document_chunk "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_doc_chunk" "${db_name}:${chunk_size}b"
    
    return $result
}

# Profiled version of store_text_data
store_text_data_profiled() {
    local db_name="$1"
    local text_path="$2"
    local analysis_file="$3"
    
    # Additional data to include in profile
    local file_size
    if [[ -f "$text_path" ]]; then
        file_size=$(stat -f%z "$text_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_text"
    
    # Call original function
    store_text_data "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_text" "${db_name}:${file_size}b"
    
    return $result
}

# Profiled version of store_text_chunk
store_text_chunk_profiled() {
    local db_name="$1"
    local text_path="$2"
    local chunk_file="$3"
    local analysis_file="$4"
    
    # Additional data to include in profile
    local chunk_size
    if [[ -f "$chunk_file" ]]; then
        chunk_size=$(stat -f%z "$chunk_file" 2>/dev/null || echo "unknown")
    else
        chunk_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_text_chunk"
    
    # Call original function
    store_text_chunk "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_text_chunk" "${db_name}:${chunk_size}b"
    
    return $result
}

# Profiled version of store_code_data
store_code_data_profiled() {
    local db_name="$1"
    local code_path="$2"
    local language="$3"
    local analysis_file="$4"
    
    # Additional data to include in profile
    local file_size
    if [[ -f "$code_path" ]]; then
        file_size=$(stat -f%z "$code_path" 2>/dev/null || echo "unknown")
    else
        file_size="unknown"
    fi
    
    # Start profiling
    start_profile "db_store_code"
    
    # Call original function
    store_code_data "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_store_code" "${db_name}:${language}:${file_size}b"
    
    return $result
}

# Profiled version of run_custom_query
run_custom_query_profiled() {
    local db_name="$1"
    local query="$2"
    
    # Start profiling
    start_profile "db_custom_query"
    
    # Call original function
    run_custom_query "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_custom_query" "$db_name"
    
    return $result
}

# Profiled version of backup_database
backup_database_profiled() {
    local db_name="$1"
    local backup_dir="${2:-${DB_DIR}/backups}"
    local verify_backup="${3:-true}"
    
    # Start profiling
    start_profile "db_backup"
    
    # Call original function
    backup_database "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_backup" "$db_name"
    
    return $result
}

# Profiled version of restore_database
restore_database_profiled() {
    local backup_file="$1"
    local db_name="$2"
    
    # Start profiling
    start_profile "db_restore"
    
    # Call original function
    restore_database "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_restore" "$db_name"
    
    return $result
}

# Profiled version of vacuum_database
vacuum_database_profiled() {
    local db_name="$1"
    
    # Start profiling
    start_profile "db_vacuum"
    
    # Call original function
    vacuum_database "$@"
    local result=$?
    
    # End profiling with additional info
    end_profile "db_vacuum" "$db_name"
    
    return $result
}

# Profiled version of safe_db_query
safe_db_query_profiled() {
    local db_path="$1"
    local query="$2"
    
    # Start profiling
    start_profile "db_safe_query"
    
    # Call original function
    safe_db_query "$@"
    local result=$?
    
    # End profiling with additional info
    local db_name=$(basename "$db_path" .sqlite)
    end_profile "db_safe_query" "$db_name"
    
    return $result
}

# Replace original functions with profiled versions when profiling is enabled
enable_database_profiling() {
    # Save original functions if not already saved
    if [[ -z "$DATABASE_PROFILING_ENABLED" ]]; then
        # Original function references
        declare -f init_database > /dev/null && init_database_original=$(declare -f init_database)
        declare -f store_image_data > /dev/null && store_image_data_original=$(declare -f store_image_data)
        declare -f store_video_data > /dev/null && store_video_data_original=$(declare -f store_video_data)
        declare -f store_document_data > /dev/null && store_document_data_original=$(declare -f store_document_data)
        declare -f store_document_chunk > /dev/null && store_document_chunk_original=$(declare -f store_document_chunk)
        declare -f store_text_data > /dev/null && store_text_data_original=$(declare -f store_text_data)
        declare -f store_text_chunk > /dev/null && store_text_chunk_original=$(declare -f store_text_chunk)
        declare -f store_code_data > /dev/null && store_code_data_original=$(declare -f store_code_data)
        declare -f run_custom_query > /dev/null && run_custom_query_original=$(declare -f run_custom_query)
        declare -f backup_database > /dev/null && backup_database_original=$(declare -f backup_database)
        declare -f restore_database > /dev/null && restore_database_original=$(declare -f restore_database)
        declare -f vacuum_database > /dev/null && vacuum_database_original=$(declare -f vacuum_database)
        declare -f safe_db_query > /dev/null && safe_db_query_original=$(declare -f safe_db_query)
    fi

    # Replace with profiled versions
    eval "init_database() { init_database_profiled \"\$@\"; }"
    eval "store_image_data() { store_image_data_profiled \"\$@\"; }"
    eval "store_video_data() { store_video_data_profiled \"\$@\"; }"
    eval "store_document_data() { store_document_data_profiled \"\$@\"; }"
    eval "store_document_chunk() { store_document_chunk_profiled \"\$@\"; }"
    eval "store_text_data() { store_text_data_profiled \"\$@\"; }"
    eval "store_text_chunk() { store_text_chunk_profiled \"\$@\"; }"
    eval "store_code_data() { store_code_data_profiled \"\$@\"; }"
    eval "run_custom_query() { run_custom_query_profiled \"\$@\"; }"
    eval "backup_database() { backup_database_profiled \"\$@\"; }"
    eval "restore_database() { restore_database_profiled \"\$@\"; }"
    eval "vacuum_database() { vacuum_database_profiled \"\$@\"; }"
    eval "safe_db_query() { safe_db_query_profiled \"\$@\"; }"
    
    DATABASE_PROFILING_ENABLED="true"
    if type log_info &>/dev/null; then
        log_info "Database profiling enabled"
    else
        echo "Database profiling enabled"
    fi
}

# Restore original functions (disable profiling)
disable_database_profiling() {
    if [[ "$DATABASE_PROFILING_ENABLED" == "true" ]]; then
        # Restore original functions
        [[ -n "$init_database_original" ]] && eval "$init_database_original"
        [[ -n "$store_image_data_original" ]] && eval "$store_image_data_original"
        [[ -n "$store_video_data_original" ]] && eval "$store_video_data_original"
        [[ -n "$store_document_data_original" ]] && eval "$store_document_data_original"
        [[ -n "$store_document_chunk_original" ]] && eval "$store_document_chunk_original"
        [[ -n "$store_text_data_original" ]] && eval "$store_text_data_original"
        [[ -n "$store_text_chunk_original" ]] && eval "$store_text_chunk_original"
        [[ -n "$store_code_data_original" ]] && eval "$store_code_data_original"
        [[ -n "$run_custom_query_original" ]] && eval "$run_custom_query_original"
        [[ -n "$backup_database_original" ]] && eval "$backup_database_original"
        [[ -n "$restore_database_original" ]] && eval "$restore_database_original"
        [[ -n "$vacuum_database_original" ]] && eval "$vacuum_database_original"
        [[ -n "$safe_db_query_original" ]] && eval "$safe_db_query_original"
        
        DATABASE_PROFILING_ENABLED="false"
        if type log_info &>/dev/null; then
            log_info "Database profiling disabled"
        else
            echo "Database profiling disabled"
        fi
    fi
}

# Enable profiling by default if PROFILING_ENABLED is set
if [[ "$PROFILING_ENABLED" == "true" ]]; then
    enable_database_profiling
fi