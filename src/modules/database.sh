#!/bin/bash
# Database management module for ingestor-system
# Enhanced with robust error handling

# Source error handler if not already loaded
if ! type require_dependency &>/dev/null; then
    # Locate the error_handler.sh module
    if [[ -f "${BASH_SOURCE%/*}/error_handler.sh" ]]; then
        source "${BASH_SOURCE%/*}/error_handler.sh"
        init_error_handler
    else
        echo "Error: error_handler.sh module not found" >&2
        exit 1
    fi
fi

# Check for required dependencies
require_dependency "sqlite3" "SQLite3 command-line tool is required for database operations"

# Initialize database with schema
init_database() {
    local db_path="$1"
    local schema_file="$2"
    
    # Validate inputs
    validate_inputs "init_database" "db_path" "schema_file"
    
    log_info "Initializing database at: $db_path with schema: $schema_file"
    
    # Ensure the database directory exists
    local db_dir
    db_dir=$(dirname "$db_path")
    require_directory "$db_dir" "Database directory not found: $db_dir" true
    
    # Verify schema file exists
    require_file "$schema_file" "Schema file not found: $schema_file"
    
    # Initialize database with schema
    log_info "Applying schema from $schema_file to database at $db_path"
    
    # Use safe_db_query from error_handler.sh
    if safe_db_query "$db_path" ".read $schema_file" > /dev/null; then
        log_info "Database initialized successfully"
        return 0
    else
        raise_error "Failed to initialize database with schema: $schema_file" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Check if database exists and is properly initialized
database_exists() {
    local db_name="$1"
    
    # Validate inputs
    validate_inputs "database_exists" "db_name"
    
    local db_path="${DB_DIR}/${db_name}.sqlite"
    
    # Check if file exists
    if [[ ! -f "$db_path" ]]; then
        log_debug "Database file does not exist: $db_path"
        return 1
    fi
    
    # Also check if the database is valid by running a simple query
    if safe_db_query "$db_path" "PRAGMA integrity_check;" &>/dev/null; then
        log_debug "Database integrity check passed: $db_path"
        return 0
    else
        log_warning "Database exists but failed integrity check: $db_path"
        return 1
    fi
}

# Get database path for a given database name
get_database_path() {
    local db_name="$1"
    
    # Validate inputs
    validate_inputs "get_database_path" "db_name"
    
    echo "${DB_DIR}/${db_name}.sqlite"
}

# Store image data in database
store_image_data() {
    local db_name="$1"
    local image_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    # Validate inputs
    validate_inputs "store_image_data" "db_name" "image_path"
    
    # Verify files exist
    require_file "$image_path" "Image file not found: $image_path"
    require_file "$metadata_file" "Metadata file not found: $metadata_file"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing image data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$image_path")
    local file_size
    if ! file_size=$(stat -f%z "$image_path" 2>/dev/null); then
        raise_error "Failed to get file size for: $image_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    local mime_type
    mime_type=$(file --mime-type -b "$image_path" 2>/dev/null || echo "application/octet-stream")
    
    # Extract specific metadata fields with error handling
    local width height creation_date
    width=$(extract_image_metadata "$image_path" "ImageWidth" 2>/dev/null || echo "0")
    height=$(extract_image_metadata "$image_path" "ImageHeight" 2>/dev/null || echo "0")
    creation_date=$(extract_image_metadata "$image_path" "CreateDate" 2>/dev/null || date -r "$image_path" +"%Y:%m:%d %H:%M:%S")
    
    # Get metadata and analysis as JSON strings
    local metadata_json analysis_json
    metadata_json=$(cat "$metadata_file" 2>/dev/null || echo "{}")
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes in JSON
    metadata_json="${metadata_json//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO images (file_path, filename, file_size, mime_type, width, height, creation_date, metadata, analysis, imported_at)
           VALUES ('$image_path', '$filename', $file_size, '$mime_type', $width, $height, '$creation_date', '$metadata_json', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Image data stored successfully: $filename"
        return 0
    else
        raise_error "Failed to store image data in database for: $filename" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store video data in database
store_video_data() {
    local db_name="$1"
    local video_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    # Validate inputs
    validate_inputs "store_video_data" "db_name" "video_path"
    
    # Verify files exist
    require_file "$video_path" "Video file not found: $video_path"
    require_file "$metadata_file" "Metadata file not found: $metadata_file"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing video data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$video_path")
    local file_size
    if ! file_size=$(stat -f%z "$video_path" 2>/dev/null); then
        raise_error "Failed to get file size for: $video_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    local mime_type
    mime_type=$(file --mime-type -b "$video_path" 2>/dev/null || echo "application/octet-stream")
    
    # Get metadata and analysis as JSON strings
    local metadata_json analysis_json
    metadata_json=$(cat "$metadata_file" 2>/dev/null || echo "{}")
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes in JSON
    metadata_json="${metadata_json//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # Extract duration and dimensions from metadata if available
    local duration width height
    
    # Use safe JSON extraction with error handling
    if command -v jq &>/dev/null; then
        duration=$(jq -r '.format.duration // "0"' "$metadata_file" 2>/dev/null || echo "0")
        width=$(jq -r '.streams[0].width // "0"' "$metadata_file" 2>/dev/null || echo "0")
        height=$(jq -r '.streams[0].height // "0"' "$metadata_file" 2>/dev/null || echo "0")
    else
        log_warning "jq command not found, defaulting duration, width, and height to 0"
        duration="0"
        width="0"
        height="0"
    fi
    
    # SQLite query to insert data
    local query
    query="INSERT INTO videos (file_path, filename, file_size, mime_type, duration, width, height, metadata, analysis, imported_at)
           VALUES ('$video_path', '$filename', $file_size, '$mime_type', $duration, $width, $height, '$metadata_json', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Video data stored successfully: $filename"
        return 0
    else
        raise_error "Failed to store video data in database for: $filename" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store document data in database
store_document_data() {
    local db_name="$1"
    local document_path="$2"
    local text_file="$3"
    local analysis_file="$4"
    
    # Validate inputs
    validate_inputs "store_document_data" "db_name" "document_path"
    
    # Verify files exist
    require_file "$document_path" "Document file not found: $document_path"
    require_file "$text_file" "Text extraction file not found: $text_file"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing document data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$document_path")
    local file_size
    if ! file_size=$(stat -f%z "$document_path" 2>/dev/null); then
        raise_error "Failed to get file size for: $document_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    local mime_type
    mime_type=$(file --mime-type -b "$document_path" 2>/dev/null || echo "application/octet-stream")
    
    # Get text content and analysis as strings
    local text_content analysis_json
    
    # Try to read text content with error handling
    if [[ -s "$text_file" ]]; then
        text_content=$(cat "$text_file" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to read text content file: $text_file, using empty content"
            text_content=""
        fi
    else
        log_warning "Text content file is empty: $text_file"
        text_content=""
    fi
    
    # Read analysis file with error handling
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes for SQL safety
    text_content="${text_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO documents (file_path, filename, file_size, mime_type, content, analysis, imported_at)
           VALUES ('$document_path', '$filename', $file_size, '$mime_type', '$text_content', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Document data stored successfully: $filename"
        return 0
    else
        raise_error "Failed to store document data in database for: $filename" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store document chunk data in database
store_document_chunk() {
    local db_name="$1"
    local document_path="$2"
    local chunk_file="$3"
    local analysis_file="$4"
    
    # Validate inputs
    validate_inputs "store_document_chunk" "db_name" "document_path" "chunk_file"
    
    # Verify files exist
    require_file "$document_path" "Document file not found: $document_path"
    require_file "$chunk_file" "Chunk file not found: $chunk_file"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing document chunk in database: $db_path"
    
    # Extract metadata
    local filename
    filename=$(basename "$document_path")
    local chunk_number
    chunk_number=$(basename "$chunk_file" | grep -o '[0-9]*' || echo "0")
    
    # Get chunk content and analysis
    local chunk_content analysis_json
    
    # Read chunk content with error handling
    if [[ -s "$chunk_file" ]]; then
        chunk_content=$(cat "$chunk_file" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to read chunk file: $chunk_file, using empty content"
            chunk_content=""
        fi
    else
        log_warning "Chunk file is empty: $chunk_file"
        chunk_content=""
    fi
    
    # Read analysis file with error handling
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes for SQL safety
    chunk_content="${chunk_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert chunk
    local query
    query="INSERT INTO document_chunks (document_path, filename, chunk_number, content, analysis, imported_at)
           VALUES ('$document_path', '$filename', $chunk_number, '$chunk_content', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Document chunk stored successfully: $filename (chunk $chunk_number)"
        return 0
    else
        raise_error "Failed to store document chunk in database: $filename (chunk $chunk_number)" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store text data in database
store_text_data() {
    local db_name="$1"
    local text_path="$2"
    local analysis_file="$3"
    
    # Validate inputs
    validate_inputs "store_text_data" "db_name" "text_path"
    
    # Verify files exist
    require_file "$text_path" "Text file not found: $text_path"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing text data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$text_path")
    local file_size
    if ! file_size=$(stat -f%z "$text_path" 2>/dev/null); then
        raise_error "Failed to get file size for: $text_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    # Get text content and analysis
    local text_content analysis_json
    
    # Read text content with error handling
    if [[ -s "$text_path" ]]; then
        text_content=$(cat "$text_path" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to read text file: $text_path, using empty content"
            text_content=""
        fi
    else
        log_warning "Text file is empty: $text_path"
        text_content=""
    fi
    
    # Read analysis file with error handling
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes for SQL safety
    text_content="${text_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO texts (file_path, filename, file_size, content, analysis, imported_at)
           VALUES ('$text_path', '$filename', $file_size, '$text_content', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Text data stored successfully: $filename"
        return 0
    else
        raise_error "Failed to store text data in database for: $filename" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store text chunk in database
store_text_chunk() {
    local db_name="$1"
    local text_path="$2"
    local chunk_file="$3"
    local analysis_file="$4"
    
    # Validate inputs
    validate_inputs "store_text_chunk" "db_name" "text_path" "chunk_file"
    
    # Verify files exist
    require_file "$text_path" "Text file not found: $text_path"
    require_file "$chunk_file" "Chunk file not found: $chunk_file"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing text chunk in database: $db_path"
    
    # Extract metadata
    local filename
    filename=$(basename "$text_path")
    local chunk_number
    chunk_number=$(basename "$chunk_file" | grep -o '[0-9]*' || echo "0")
    
    # Get chunk content and analysis
    local chunk_content analysis_json
    
    # Read chunk content with error handling
    if [[ -s "$chunk_file" ]]; then
        chunk_content=$(cat "$chunk_file" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to read chunk file: $chunk_file, using empty content"
            chunk_content=""
        fi
    else
        log_warning "Chunk file is empty: $chunk_file"
        chunk_content=""
    fi
    
    # Read analysis file with error handling
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes for SQL safety
    chunk_content="${chunk_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert chunk
    local query
    query="INSERT INTO text_chunks (text_path, filename, chunk_number, content, analysis, imported_at)
           VALUES ('$text_path', '$filename', $chunk_number, '$chunk_content', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Text chunk stored successfully: $filename (chunk $chunk_number)"
        return 0
    else
        raise_error "Failed to store text chunk in database: $filename (chunk $chunk_number)" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store code data in database
store_code_data() {
    local db_name="$1"
    local code_path="$2"
    local language="$3"
    local analysis_file="$4"
    
    # Validate inputs
    validate_inputs "store_code_data" "db_name" "code_path"
    
    # Verify files exist
    require_file "$code_path" "Code file not found: $code_path"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing code data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$code_path")
    local file_size
    if ! file_size=$(stat -f%z "$code_path" 2>/dev/null); then
        raise_error "Failed to get file size for: $code_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    # Get code content and analysis
    local code_content analysis_json
    
    # Read code content with error handling
    if [[ -s "$code_path" ]]; then
        code_content=$(cat "$code_path" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to read code file: $code_path, using empty content"
            code_content=""
        fi
    else
        log_warning "Code file is empty: $code_path"
        code_content=""
    fi
    
    # Read analysis file with error handling
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes for SQL safety
    code_content="${code_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # Use a default language if none provided
    if [[ -z "$language" ]]; then
        language="unknown"
    fi
    
    # SQLite query to insert data
    local query
    query="INSERT INTO code (file_path, filename, file_size, language, content, analysis, imported_at)
           VALUES ('$code_path', '$filename', $file_size, '$language', '$code_content', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Code data stored successfully: $filename"
        return 0
    else
        raise_error "Failed to store code data in database for: $filename" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Store generic data in database
store_generic_data() {
    local db_name="$1"
    local file_path="$2"
    local content_type="$3"
    local metadata_file="$4"
    local analysis_file="$5"
    
    # Validate inputs
    validate_inputs "store_generic_data" "db_name" "file_path"
    
    # Verify files exist
    require_file "$file_path" "File not found: $file_path"
    require_file "$metadata_file" "Metadata file not found: $metadata_file"
    require_file "$analysis_file" "Analysis file not found: $analysis_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing generic data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$file_path")
    local file_size
    if ! file_size=$(stat -f%z "$file_path" 2>/dev/null); then
        raise_error "Failed to get file size for: $file_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    # Default content type if not provided
    if [[ -z "$content_type" ]]; then
        content_type="application/octet-stream"
    fi
    
    # Get metadata and analysis with error handling
    local metadata_json analysis_json
    metadata_json=$(cat "$metadata_file" 2>/dev/null || echo "{}")
    analysis_json=$(cat "$analysis_file" 2>/dev/null || echo "{}")
    
    # Escape single quotes for SQL safety
    metadata_json="${metadata_json//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO generic_content (file_path, filename, file_size, content_type, metadata, analysis, imported_at)
           VALUES ('$file_path', '$filename', $file_size, '$content_type', '$metadata_json', '$analysis_json', datetime('now'));"
    
    # Execute query with retry and error handling
    if safe_db_query "$db_path" "$query" > /dev/null; then
        log_info "Generic data stored successfully: $filename"
        return 0
    else
        raise_error "Failed to store generic data in database for: $filename" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Get database schema info
get_database_schema() {
    local db_name="$1"
    local db_path
    
    # Validate inputs
    validate_inputs "get_database_schema" "db_name"
    
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists
    require_file "$db_path" "Database file not found: $db_path"
    
    # Get schema info
    log_debug "Getting schema for database: $db_path"
    
    local query="SELECT sql FROM sqlite_master WHERE type='table' ORDER BY name;"
    local schema
    
    schema=$(safe_db_query "$db_path" "$query")
    
    if [[ $? -ne 0 ]]; then
        raise_error "Failed to get database schema" $ERR_DATABASE
        return $ERR_DATABASE
    fi
    
    echo "$schema"
    return 0
}

# Run a custom query on a database
run_custom_query() {
    local db_name="$1"
    local query="$2"
    
    # Validate inputs
    validate_inputs "run_custom_query" "db_name" "query"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists
    require_file "$db_path" "Database file not found: $db_path"
    
    log_debug "Running custom query on database: $db_path"
    
    # Run query with error handling
    local result
    result=$(safe_db_query "$db_path" "$query")
    
    if [[ $? -ne 0 ]]; then
        raise_error "Failed to run custom query on database" $ERR_DATABASE
        return $ERR_DATABASE
    fi
    
    echo "$result"
    return 0
}

# Create a database backup
backup_database() {
    local db_name="$1"
    local backup_dir="${2:-${DB_DIR}/backups}"
    
    # Validate inputs
    validate_inputs "backup_database" "db_name"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists
    require_file "$db_path" "Database file not found: $db_path"
    
    # Create backup directory if it doesn't exist
    require_directory "$backup_dir" "Backup directory not found: $backup_dir" true
    
    # Create backup filename with timestamp
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/${db_name}_backup_${timestamp}.sqlite"
    
    log_info "Creating database backup: $backup_file"
    
    # Use sqlite3 to create a backup
    if safe_db_query "$db_path" ".backup '$backup_file'" > /dev/null; then
        log_info "Database backup created successfully: $backup_file"
        return 0
    else
        raise_error "Failed to create database backup" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Restore a database from backup
restore_database() {
    local backup_file="$1"
    local db_name="$2"
    
    # Validate inputs
    validate_inputs "restore_database" "backup_file" "db_name"
    
    # Check if backup file exists
    require_file "$backup_file" "Backup file not found: $backup_file"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Create a backup of the current database if it exists
    if [[ -f "$db_path" ]]; then
        log_info "Creating backup of current database before restoration"
        backup_database "$db_name" || log_warning "Failed to backup current database before restoration"
    fi
    
    # Create database directory if it doesn't exist
    local db_dir
    db_dir=$(dirname "$db_path")
    require_directory "$db_dir" "Database directory not found: $db_dir" true
    
    log_info "Restoring database from backup: $backup_file to $db_path"
    
    # Use sqlite3 to restore from backup
    if sqlite3 "$backup_file" ".backup '$db_path'" > /dev/null 2>&1; then
        log_info "Database restored successfully from backup"
        return 0
    else
        raise_error "Failed to restore database from backup" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Vacuum a database to optimize it
vacuum_database() {
    local db_name="$1"
    
    # Validate inputs
    validate_inputs "vacuum_database" "db_name"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists
    require_file "$db_path" "Database file not found: $db_path"
    
    log_info "Vacuuming database to optimize space: $db_path"
    
    # Run VACUUM command
    if safe_db_query "$db_path" "VACUUM;" > /dev/null; then
        log_info "Database vacuum completed successfully"
        return 0
    else
        raise_error "Failed to vacuum database" $ERR_DATABASE
        return $ERR_DATABASE
    fi
}

# Get database statistics
get_database_stats() {
    local db_name="$1"
    
    # Validate inputs
    validate_inputs "get_database_stats" "db_name"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists
    require_file "$db_path" "Database file not found: $db_path"
    
    log_debug "Getting statistics for database: $db_path"
    
    # Query to get table statistics
    local query="
    SELECT 'Database Size' as 'Stat', (SELECT page_count * page_size / 1024.0 / 1024.0 || ' MB' FROM pragma_page_count(), pragma_page_size()) as 'Value'
    UNION ALL
    SELECT 'Total Tables', (SELECT COUNT(*) FROM sqlite_master WHERE type='table') 
    UNION ALL
    SELECT name || ' Count', (SELECT COUNT(*) FROM " || name || ") 
    FROM sqlite_master 
    WHERE type='table' AND name NOT LIKE 'sqlite_%';"
    
    # Use run_custom_query to execute with error handling
    run_custom_query "$db_name" "$query"
}