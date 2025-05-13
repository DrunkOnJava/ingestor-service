#!/bin/bash
# Database management module for ingestor

# Initialize database with schema
init_database() {
    local db_path="$1"
    local schema_file="$2"
    
    log_info "Initializing database at: $db_path with schema: $schema_file"
    
    # Create directory if needed
    mkdir -p "$(dirname "$db_path")"
    
    # Check if schema file exists
    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema file not found: $schema_file"
        return 1
    fi
    
    # Initialize database with schema
    if sqlite3 "$db_path" < "$schema_file"; then
        log_info "Database initialized successfully"
        return 0
    else
        log_error "Failed to initialize database"
        return 1
    fi
}

# Check if database exists
database_exists() {
    local db_name="$1"
    local db_path="${DB_DIR}/${db_name}.sqlite"
    
    if [[ -f "$db_path" ]]; then
        return 0
    else
        return 1
    fi
}

# Get database path
get_database_path() {
    local db_name="$1"
    echo "${DB_DIR}/${db_name}.sqlite"
}

# Store image data in database
store_image_data() {
    local db_name="$1"
    local image_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing image data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$image_path")
    local file_size
    file_size=$(stat -f%z "$image_path")
    local mime_type
    mime_type=$(file --mime-type -b "$image_path")
    
    # Extract specific metadata fields
    local width
    width=$(extract_image_metadata "$image_path" "ImageWidth" || echo "0")
    local height
    height=$(extract_image_metadata "$image_path" "ImageHeight" || echo "0")
    local creation_date
    creation_date=$(extract_image_metadata "$image_path" "CreateDate" || date -r "$image_path" +"%Y:%m:%d %H:%M:%S")
    
    # Get metadata and analysis as JSON strings
    local metadata_json
    metadata_json=$(cat "$metadata_file")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes in JSON
    metadata_json="${metadata_json//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO images (file_path, filename, file_size, mime_type, width, height, creation_date, metadata, analysis, imported_at)
           VALUES ('$image_path', '$filename', $file_size, '$mime_type', $width, $height, '$creation_date', '$metadata_json', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Image data stored successfully: $filename"
        return 0
    else
        log_error "Failed to store image data for: $filename"
        return 1
    fi
}

# Store video data in database
store_video_data() {
    local db_name="$1"
    local video_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing video data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$video_path")
    local file_size
    file_size=$(stat -f%z "$video_path")
    local mime_type
    mime_type=$(file --mime-type -b "$video_path")
    
    # Get metadata and analysis as JSON strings
    local metadata_json
    metadata_json=$(cat "$metadata_file")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes in JSON
    metadata_json="${metadata_json//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # Extract duration and dimensions from metadata if available
    local duration
    duration=$(jq -r '.format.duration // "0"' "$metadata_file" 2>/dev/null || echo "0")
    local width
    width=$(jq -r '.streams[0].width // "0"' "$metadata_file" 2>/dev/null || echo "0")
    local height
    height=$(jq -r '.streams[0].height // "0"' "$metadata_file" 2>/dev/null || echo "0")
    
    # SQLite query to insert data
    local query
    query="INSERT INTO videos (file_path, filename, file_size, mime_type, duration, width, height, metadata, analysis, imported_at)
           VALUES ('$video_path', '$filename', $file_size, '$mime_type', $duration, $width, $height, '$metadata_json', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Video data stored successfully: $filename"
        return 0
    else
        log_error "Failed to store video data for: $filename"
        return 1
    fi
}

# Store document data in database
store_document_data() {
    local db_name="$1"
    local document_path="$2"
    local text_file="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing document data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$document_path")
    local file_size
    file_size=$(stat -f%z "$document_path")
    local mime_type
    mime_type=$(file --mime-type -b "$document_path")
    
    # Get text content and analysis as strings
    local text_content
    text_content=$(cat "$text_file")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes
    text_content="${text_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO documents (file_path, filename, file_size, mime_type, content, analysis, imported_at)
           VALUES ('$document_path', '$filename', $file_size, '$mime_type', '$text_content', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Document data stored successfully: $filename"
        return 0
    else
        log_error "Failed to store document data for: $filename"
        return 1
    fi
}

# Store document chunk data in database
store_document_chunk() {
    local db_name="$1"
    local document_path="$2"
    local chunk_file="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing document chunk in database: $db_path"
    
    # Extract metadata
    local filename
    filename=$(basename "$document_path")
    local chunk_number
    chunk_number=$(basename "$chunk_file" | grep -o '[0-9]*' || echo "0")
    
    # Get chunk content and analysis
    local chunk_content
    chunk_content=$(cat "$chunk_file")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes
    chunk_content="${chunk_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert chunk
    local query
    query="INSERT INTO document_chunks (document_path, filename, chunk_number, content, analysis, imported_at)
           VALUES ('$document_path', '$filename', $chunk_number, '$chunk_content', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Document chunk stored successfully: $filename (chunk $chunk_number)"
        return 0
    else
        log_error "Failed to store document chunk for: $filename (chunk $chunk_number)"
        return 1
    fi
}

# Store text data in database
store_text_data() {
    local db_name="$1"
    local text_path="$2"
    local analysis_file="$3"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing text data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$text_path")
    local file_size
    file_size=$(stat -f%z "$text_path")
    
    # Get text content and analysis
    local text_content
    text_content=$(cat "$text_path")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes
    text_content="${text_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO texts (file_path, filename, file_size, content, analysis, imported_at)
           VALUES ('$text_path', '$filename', $file_size, '$text_content', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Text data stored successfully: $filename"
        return 0
    else
        log_error "Failed to store text data for: $filename"
        return 1
    fi
}

# Store text chunk in database
store_text_chunk() {
    local db_name="$1"
    local text_path="$2"
    local chunk_file="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing text chunk in database: $db_path"
    
    # Extract metadata
    local filename
    filename=$(basename "$text_path")
    local chunk_number
    chunk_number=$(basename "$chunk_file" | grep -o '[0-9]*' || echo "0")
    
    # Get chunk content and analysis
    local chunk_content
    chunk_content=$(cat "$chunk_file")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes
    chunk_content="${chunk_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert chunk
    local query
    query="INSERT INTO text_chunks (text_path, filename, chunk_number, content, analysis, imported_at)
           VALUES ('$text_path', '$filename', $chunk_number, '$chunk_content', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Text chunk stored successfully: $filename (chunk $chunk_number)"
        return 0
    else
        log_error "Failed to store text chunk for: $filename (chunk $chunk_number)"
        return 1
    fi
}

# Store code data in database
store_code_data() {
    local db_name="$1"
    local code_path="$2"
    local language="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing code data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$code_path")
    local file_size
    file_size=$(stat -f%z "$code_path")
    
    # Get code content and analysis
    local code_content
    code_content=$(cat "$code_path")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes
    code_content="${code_content//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO code (file_path, filename, file_size, language, content, analysis, imported_at)
           VALUES ('$code_path', '$filename', $file_size, '$language', '$code_content', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Code data stored successfully: $filename"
        return 0
    else
        log_error "Failed to store code data for: $filename"
        return 1
    fi
}

# Store generic data in database
store_generic_data() {
    local db_name="$1"
    local file_path="$2"
    local content_type="$3"
    local metadata_file="$4"
    local analysis_file="$5"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Storing generic data in database: $db_path"
    
    # Extract metadata from file
    local filename
    filename=$(basename "$file_path")
    local file_size
    file_size=$(stat -f%z "$file_path")
    
    # Get metadata and analysis
    local metadata_json
    metadata_json=$(cat "$metadata_file")
    local analysis_json
    analysis_json=$(cat "$analysis_file")
    
    # Escape single quotes
    metadata_json="${metadata_json//\'/\'\'}"
    analysis_json="${analysis_json//\'/\'\'}"
    
    # SQLite query to insert data
    local query
    query="INSERT INTO generic_content (file_path, filename, file_size, content_type, metadata, analysis, imported_at)
           VALUES ('$file_path', '$filename', $file_size, '$content_type', '$metadata_json', '$analysis_json', datetime('now'));"
    
    # Execute query
    if sqlite3 "$db_path" "$query"; then
        log_info "Generic data stored successfully: $filename"
        return 0
    else
        log_error "Failed to store generic data for: $filename"
        return 1
    fi
}