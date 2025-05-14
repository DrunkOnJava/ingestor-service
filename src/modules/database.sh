#!/bin/bash
# Database management module for ingestor-system
# Enhanced with robust error handling

# Source enhanced error handler if not already loaded
if ! type init_enhanced_error_handler &>/dev/null; then
    # Locate the enhanced_error_handler.sh module
    if [[ -f "${BASH_SOURCE%/*}/enhanced_error_handler.sh" ]]; then
        source "${BASH_SOURCE%/*}/enhanced_error_handler.sh"
        init_enhanced_error_handler
    else
        # Fall back to standard error handler
        if [[ -f "${BASH_SOURCE%/*}/error_handler.sh" ]]; then
            source "${BASH_SOURCE%/*}/error_handler.sh"
            init_error_handler
            echo "Warning: Using standard error handler instead of enhanced version" >&2
        else
            echo "Error: No error handler module found" >&2
            exit 1
        fi
    fi
fi

# Import error codes if not already imported
if [[ -z "${ERR_UNKNOWN+x}" && -f "${BASH_SOURCE%/*}/error_codes.sh" ]]; then
    source "${BASH_SOURCE%/*}/error_codes.sh"
fi

# Check for required dependencies
if type require_dependency &>/dev/null; then
    require_dependency "sqlite3" "SQLite3 command-line tool is required for database operations"
else
    # Fallback if require_dependency is not available
    if ! command -v sqlite3 &>/dev/null; then
        log_error "SQLite3 command-line tool is required for database operations"
        exit $ERR_DEPENDENCY
    fi
fi

# Initialize database module
init_database_module() {
    # Set optional configuration parameters
    DB_RETRY_COUNT=${DB_RETRY_COUNT:-5}            # Higher retry count for database operations
    DB_RETRY_DELAY=${DB_RETRY_DELAY:-1}           # Start with shorter delay but use exponential backoff
    DB_OPERATION_TIMEOUT=${DB_OPERATION_TIMEOUT:-30}  # Default timeout for database operations
    DB_TRANSACTION_ISOLATION=${DB_TRANSACTION_ISOLATION:-"IMMEDIATE"}  # Default transaction isolation level
    DB_AUTO_BACKUP=${DB_AUTO_BACKUP:-true}       # Whether to auto-backup before risky operations
    DB_MAX_FAILURES=${DB_MAX_FAILURES:-3}        # Maximum allowed failures before halting operations
    
    log_debug "Database module initialized with retry count: $DB_RETRY_COUNT, retry delay: $DB_RETRY_DELAY"
    
    # Track database failures for adaptive error handling
    DB_FAILURE_COUNT=0
}

# Initialize database with schema
init_database() {
    local db_path="$1"
    local schema_file="$2"
    local force_recreate="${3:-false}"
    local apply_optimizations="${4:-true}"
    
    # Validate required inputs
    if [[ -z "$db_path" || -z "$schema_file" ]]; then
        log_error "Database path and schema file are required for initialization"
        document_error $ERR_INVALID_ARG "init_database" "Missing required parameters"
        return $ERR_INVALID_ARG
    fi
    
    log_info "Initializing database at: $db_path with schema: $schema_file"
    
    # Ensure the database directory exists
    local db_dir
    db_dir=$(dirname "$db_path")
    
    # Create directory with enhanced error checking
    if [[ ! -d "$db_dir" ]]; then
        log_info "Creating database directory: $db_dir"
        if ! mkdir -p "$db_dir" 2>/dev/null; then
            log_error "Failed to create database directory: $db_dir"
            document_error $ERR_DIR_UNWRITABLE "init_database" "Cannot create database directory: $db_dir"
            return $ERR_DIR_UNWRITABLE
        fi
    elif [[ ! -w "$db_dir" ]]; then
        log_error "Database directory is not writable: $db_dir"
        document_error $ERR_DIR_UNWRITABLE "init_database" "Cannot write to database directory: $db_dir"
        return $ERR_DIR_UNWRITABLE
    fi
    
    # Verify schema file exists with enhanced checking
    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema file not found: $schema_file"
        document_error $ERR_FILE_NOT_FOUND "init_database" "Schema file not found: $schema_file"
        return $ERR_FILE_NOT_FOUND
    elif [[ ! -r "$schema_file" ]]; then
        log_error "Schema file is not readable: $schema_file"
        document_error $ERR_FILE_UNREADABLE "init_database" "Cannot read schema file: $schema_file"
        return $ERR_FILE_UNREADABLE
    fi
    
    # Check if database already exists and force_recreate is false
    if [[ -f "$db_path" && "$force_recreate" != "true" ]]; then
        # Check database integrity
        if sqlite3 "$db_path" "PRAGMA integrity_check;" &>/dev/null; then
            log_info "Database already exists and passed integrity check: $db_path"
            
            # Apply entity index optimizations if enabled
            if [[ "$apply_optimizations" == "true" ]]; then
                # Check if we have entities table
                local has_entities
                has_entities=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='entities';" 2>/dev/null || echo "0")
                
                if [[ "$has_entities" -gt "0" ]]; then
                    log_debug "Database has entities table, applying optimizations"
                    # Get the database name from path
                    local db_name
                    db_name=$(basename "$db_path" .sqlite)
                    # Apply entity optimizations
                    optimize_entity_indexes "$db_name" >/dev/null || log_warning "Failed to apply entity optimizations to existing database"
                fi
            fi
            
            return 0
        else
            log_warning "Database exists but failed integrity check: $db_path"
            # Continue to recreate the database
        fi
    fi
    
    # Backup existing database if it exists and we're recreating it
    if [[ -f "$db_path" && "$force_recreate" == "true" ]]; then
        local backup_path="${db_path}.backup_$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing database to: $backup_path"
        if ! cp "$db_path" "$backup_path" 2>/dev/null; then
            log_warning "Failed to backup existing database"
        fi
    fi
    
    # Initialize database with schema using enhanced error handling and retry
    log_info "Applying schema from $schema_file to database at $db_path"
    
    # Track if initialization was successful
    local init_success=false
    
    # We'll use try-catch for better error handling if available
    if type try &>/dev/null; then
        try safe_sql_query "$db_path" ".read $schema_file"
        
        catch handle_db_init_error "$db_path" "$schema_file"
        
        if [[ ${_ENHANCED_ERROR_HANDLER_CODE:-0} -eq 0 ]]; then
            log_info "Database initialized successfully"
            init_success=true
        else
            return ${_ENHANCED_ERROR_HANDLER_CODE}
        fi
    else
        # Fallback to traditional error handling with retry
        if type retry_function &>/dev/null; then
            if retry_function safe_sql_query "$db_path" ".read $schema_file" "$DB_RETRY_COUNT" "$DB_RETRY_DELAY"; then
                log_info "Database initialized successfully"
                init_success=true
            else
                local exit_code=$?
                log_error "Failed to initialize database with schema after $DB_RETRY_COUNT attempts: $schema_file"
                document_error $exit_code "init_database" "Failed to apply schema after multiple attempts"
                return $exit_code
            fi
        else
            # Basic fallback if enhanced functions aren't available
            if sqlite3 "$db_path" ".read $schema_file" 2>/dev/null; then
                log_info "Database initialized successfully"
                init_success=true
            else
                log_error "Failed to initialize database with schema: $schema_file"
                return $ERR_DATABASE
            fi
        fi
    fi
    
    # If initialization was successful and optimizations are enabled, apply entity indexing
    if [[ "$init_success" == "true" && "$apply_optimizations" == "true" ]]; then
        # Check if entities table was created
        local has_entities
        has_entities=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='entities';" 2>/dev/null || echo "0")
        
        if [[ "$has_entities" -gt "0" ]]; then
            log_debug "Database has entities table, applying optimizations"
            # Get the database name from path
            local db_name
            db_name=$(basename "$db_path" .sqlite)
            # Apply entity optimizations
            optimize_entity_indexes "$db_name" >/dev/null || log_warning "Failed to apply entity optimizations to new database"
        fi
    fi
    
    # Creation of maintenance log table
    create_maintenance_log_if_needed "$db_path"
    
    return 0
}

# Error handler for database initialization
handle_db_init_error() {
    local db_path="$1"
    local schema_file="$2"
    local error_code="$3"
    local line="$4"
    local func="$5"
    local file="$6"
    
    log_error "Database initialization failed with error $error_code at $file:$line ($func)"
    
    # Check for specific errors and provide targeted recovery advice
    case $error_code in
        $ERR_DB_LOCKED)
            log_error "Database is locked. Please ensure no other processes are using it and try again."
            ;;
        $ERR_DB_CORRUPT)
            log_error "Database appears to be corrupt. If you have a backup, restore it or recreate the database."
            ;;
        $ERR_DB_SCHEMA)
            log_error "Schema error. The schema file may contain syntax errors: $schema_file"
            ;;
        *)
            log_error "A database error occurred. Check permissions and disk space."
            ;;
    esac
    
    document_error $error_code "init_database" "Failed to initialize database: $db_path with schema: $schema_file"
    return $error_code
}

# Check if database exists and is properly initialized
database_exists() {
    local db_name="$1"
    local run_integrity_check="${2:-true}"
    
    # Validate required inputs with enhanced validation
    if [[ -z "$db_name" ]]; then
        log_error "Database name is required for database_exists"
        return $ERR_INVALID_ARG
    fi
    
    # Check if DB_DIR is set
    if [[ -z "${DB_DIR+x}" ]]; then
        log_error "DB_DIR environment variable is not set"
        document_error $ERR_ENVIRONMENT "database_exists" "DB_DIR environment variable is not set"
        return $ERR_ENVIRONMENT
    fi
    
    local db_path="${DB_DIR}/${db_name}.sqlite"
    
    # Check if file exists with enhanced error details
    if [[ ! -f "$db_path" ]]; then
        log_debug "Database file does not exist: $db_path"
        return 1
    fi
    
    # Skip integrity check if not requested (for performance)
    if [[ "$run_integrity_check" != "true" ]]; then
        log_debug "Database file exists (integrity check skipped): $db_path"
        return 0
    fi
    
    # Run integrity check with enhanced timeout and retry
    if type run_with_timeout &>/dev/null; then
        if run_with_timeout "sqlite3 '$db_path' 'PRAGMA integrity_check;'" 10 "Database integrity check timed out"; then
            log_debug "Database integrity check passed: $db_path"
            return 0
        else
            local exit_code=$?
            if [[ $exit_code -eq $ERR_TIMEOUT ]]; then
                log_warning "Database integrity check timed out: $db_path"
            else
                log_warning "Database exists but failed integrity check: $db_path"
            fi
            return 1
        fi
    else
        # Fallback to simpler check without timeout
        if sqlite3 "$db_path" "PRAGMA integrity_check;" &>/dev/null; then
            log_debug "Database integrity check passed: $db_path"
            return 0
        else
            log_warning "Database exists but failed integrity check: $db_path"
            return 1
        fi
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

# Create a database backup with enhanced resilience
backup_database() {
    local db_name="$1"
    local backup_dir="${2:-${DB_DIR}/backups}"
    local verify_backup="${3:-true}"
    
    # Validate inputs with enhanced error details
    if [[ -z "$db_name" ]]; then
        log_error "Database name is required for backup operation"
        document_error $ERR_INVALID_ARG "backup_database" "Missing required database name parameter"
        return $ERR_INVALID_ARG
    fi
    
    # Get database path
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists with enhanced error details
    if [[ ! -f "$db_path" ]]; then
        log_error "Database file not found: $db_path"
        document_error $ERR_FILE_NOT_FOUND "backup_database" "Database file not found: $db_path"
        return $ERR_FILE_NOT_FOUND
    fi
    
    # Check database readability
    if [[ ! -r "$db_path" ]]; then
        log_error "Database file not readable: $db_path"
        document_error $ERR_FILE_UNREADABLE "backup_database" "Database file not readable: $db_path"
        return $ERR_FILE_UNREADABLE
    fi
    
    # Perform system resource check before backup
    if type check_system_resources &>/dev/null; then
        # Check for at least twice the database size in free space
        local db_size
        db_size=$(stat -f%z "$db_path" 2>/dev/null || echo "0")
        local required_space=$((db_size / 1024 / 1024 * 2 + 50)) # DB size * 2 + 50MB buffer, converted to MB
        
        if ! check_system_resources "$required_space" "100"; then
            log_error "Insufficient disk space for database backup"
            document_error $ERR_DISK_SPACE "backup_database" "Insufficient disk space for database backup (need ${required_space}MB)"
            return $ERR_DISK_SPACE
        fi
    fi
    
    # Create backup directory with enhanced error handling
    if [[ ! -d "$backup_dir" ]]; then
        log_info "Creating backup directory: $backup_dir"
        if ! mkdir -p "$backup_dir" 2>/dev/null; then
            log_error "Failed to create backup directory: $backup_dir"
            document_error $ERR_DIR_UNWRITABLE "backup_database" "Cannot create backup directory: $backup_dir"
            return $ERR_DIR_UNWRITABLE
        fi
    elif [[ ! -w "$backup_dir" ]]; then
        log_error "Backup directory is not writable: $backup_dir"
        document_error $ERR_DIR_UNWRITABLE "backup_database" "Backup directory is not writable: $backup_dir"
        return $ERR_DIR_UNWRITABLE
    fi
    
    # Create backup filename with timestamp and random suffix for uniqueness
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local random_suffix=$(hexdump -n 2 -e '/2 "%04x"' /dev/urandom 2>/dev/null || echo "0000")
    local backup_file="${backup_dir}/${db_name}_backup_${timestamp}_${random_suffix}.sqlite"
    
    log_info "Creating database backup: $backup_file"
    
    # Acquire a lock to prevent concurrent backups if possible
    local lock_acquired=0
    if type acquire_lock &>/dev/null; then
        if acquire_lock "/tmp/db_backup_${db_name}.lock" 30; then
            lock_acquired=1
        else
            log_warning "Could not acquire backup lock, proceeding anyway but backup may conflict with other operations"
        fi
    fi
    
    # Use enhanced retry mechanism for backup
    local result=0
    if type retry_with_backoff &>/dev/null; then
        retry_with_backoff "sqlite3 '$db_path' '.backup $backup_file'" 3 2 10 60 > /dev/null
        result=$?
    else
        # Fallback to basic backup command
        sqlite3 "$db_path" ".backup '$backup_file'" > /dev/null 2>&1
        result=$?
    fi
    
    # Release the lock if acquired
    if [[ $lock_acquired -eq 1 ]] && type release_lock &>/dev/null; then
        release_lock "/tmp/db_backup_${db_name}.lock"
    fi
    
    # Check backup result
    if [[ $result -eq 0 ]]; then
        # Verify backup integrity if requested
        if [[ "$verify_backup" == "true" ]]; then
            log_debug "Verifying backup integrity"
            if sqlite3 "$backup_file" "PRAGMA integrity_check;" &>/dev/null; then
                log_info "Database backup created and verified successfully: $backup_file"
            else
                log_error "Backup verification failed for: $backup_file"
                document_error $ERR_DB_CORRUPT "backup_database" "Backup verification failed for: $backup_file"
                rm -f "$backup_file" # Remove corrupt backup
                return $ERR_DB_CORRUPT
            fi
        } else {
            log_info "Database backup created successfully: $backup_file"
        }
        
        # Maintain backup rotation - keep only the last 5 backups per database
        if [[ -d "$backup_dir" ]]; then
            local backup_count
            backup_count=$(find "$backup_dir" -name "${db_name}_backup_*.sqlite" | wc -l)
            
            if [[ "$backup_count" -gt 5 ]]; then
                log_debug "Removing old backups to maintain rotation limit"
                find "$backup_dir" -name "${db_name}_backup_*.sqlite" | sort | head -n -5 | xargs rm -f 2>/dev/null || true
            fi
        fi
        
        # Return the backup file path for reference
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create database backup (error: $result)"
        document_error $ERR_DATABASE "backup_database" "Failed to create database backup: $db_path"
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

# Apply entity indexing optimizations to a database
optimize_entity_indexes() {
    local db_name="$1"
    local script_path="$2"
    
    # Validate inputs
    validate_inputs "optimize_entity_indexes" "db_name"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    # Check if database exists
    require_file "$db_path" "Database file not found: $db_path"
    
    # Check if entities table exists
    local entities_exist
    entities_exist=$(safe_db_query "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='entities';")
    
    if [[ "$entities_exist" -eq "0" ]]; then
        log_warning "Database does not have entities table, skipping indexing: $db_path"
        return 0
    fi
    
    log_info "Optimizing entity indexes for database: $db_path"
    
    # If script path not provided, use default location
    if [[ -z "$script_path" ]]; then
        # First try to locate the script relative to this module
        local module_dir="$(dirname "${BASH_SOURCE[0]}")/../.."
        script_path="$module_dir/config/schemas/entity_indexes.sql"
        
        # If not found, try using a hardcoded path based on typical installation
        if [[ ! -f "$script_path" ]]; then
            script_path="/path/to/ingestor-system/config/schemas/entity_indexes.sql"
        fi
    fi
    
    # Check if the index script exists
    if [[ ! -f "$script_path" ]]; then
        log_error "Entity index script not found: $script_path"
        raise_error "Entity index script not found: $script_path" $ERR_FILE_NOT_FOUND
        return $ERR_FILE_NOT_FOUND
    fi
    
    # Apply the indexes using our safe SQL function
    log_debug "Applying entity indexes from $script_path"
    
    # Create a backup before modifying the database
    if [[ "$DB_AUTO_BACKUP" == "true" ]]; then
        log_debug "Creating backup before applying entity indexes"
        backup_database "$db_name" >/dev/null || log_warning "Failed to backup database before optimization"
    fi
    
    # Apply optimizations with retry and error handling
    if type retry_function &>/dev/null; then
        if retry_function safe_sql_query "$db_path" ".read $script_path" "$DB_RETRY_COUNT" "$DB_RETRY_DELAY"; then
            log_info "Successfully optimized entity indexes in database: $db_name"
            
            # Get the number of indexes applied
            local index_count
            index_count=$(safe_db_query "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%entities%';")
            
            log_info "Applied/verified $index_count entity-related indexes"
            
            # Record the optimization in the database's maintenance log
            create_maintenance_log_if_needed "$db_path"
            safe_db_query "$db_path" "INSERT INTO maintenance_log (operation, details) VALUES ('entity_indexes_optimization', 'Added entity indexes for improved performance');" >/dev/null
            
            return 0
        else
            local exit_code=$?
            log_error "Failed to apply entity indexes to database"
            document_error $exit_code "optimize_entity_indexes" "Failed to apply entity indexes to $db_path"
            return $exit_code
        fi
    else
        # Fallback to basic approach without retry
        if sqlite3 "$db_path" ".read $script_path" 2>/dev/null; then
            log_info "Successfully optimized entity indexes in database: $db_name"
            return 0
        else
            log_error "Failed to apply entity indexes to database"
            raise_error "Failed to apply entity indexes to database: $db_path" $ERR_DATABASE
            return $ERR_DATABASE
        fi
    fi
}

# Create maintenance log table if it doesn't exist
create_maintenance_log_if_needed() {
    local db_path="$1"
    
    # Create maintenance log table if it doesn't exist
    local query="CREATE TABLE IF NOT EXISTS maintenance_log (
        id INTEGER PRIMARY KEY,
        operation TEXT NOT NULL,
        details TEXT,
        executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );"
    
    sqlite3 "$db_path" "$query" 2>/dev/null
}