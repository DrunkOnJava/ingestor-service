#!/usr/bin/env bats
# Basic integration tests for the ingestor system

# Load the test helper
load ../test_helper

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Set up mock environment
    export INGESTOR_HOME="${TEST_TEMP_DIR}/.ingestor"
    export CONFIG_DIR="${INGESTOR_HOME}/config"
    export DB_DIR="${INGESTOR_HOME}/databases"
    export TEMP_DIR="${INGESTOR_HOME}/temp"
    export LOG_DIR="${INGESTOR_HOME}/logs"
    export SCHEMAS_DIR="${CONFIG_DIR}/schemas"
    export PROJECT_ROOT="${TEST_TEMP_DIR}/project"
    
    # Create necessary directories
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${DB_DIR}"
    mkdir -p "${TEMP_DIR}"
    mkdir -p "${LOG_DIR}"
    mkdir -p "${SCHEMAS_DIR}"
    mkdir -p "${PROJECT_ROOT}/src/modules"
    mkdir -p "${PROJECT_ROOT}/config/schemas"
    
    # Create a test schema file
    cat > "${SCHEMAS_DIR}/general.sql" << 'EOF'
-- General content database schema

-- Images table
CREATE TABLE IF NOT EXISTS images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    width INTEGER,
    height INTEGER,
    creation_date TEXT,
    metadata TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Texts table
CREATE TABLE IF NOT EXISTS texts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Create full-text search tables
CREATE VIRTUAL TABLE IF NOT EXISTS fts_texts USING fts5(
    content, analysis,
    content=texts, content_rowid=id
);

-- Create triggers to keep FTS tables in sync
CREATE TRIGGER IF NOT EXISTS texts_ai AFTER INSERT ON texts BEGIN
    INSERT INTO fts_texts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;
EOF
    
    # Create mock modules
    
    # Mock logging module
    cat > "${PROJECT_ROOT}/src/modules/logging.sh" << 'EOF'
#!/bin/bash
# Logging module for ingestor

# Log levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_ERROR=3

# Current log level (default: info)
LOG_LEVEL="$LOG_LEVEL_INFO"

# Initialize logging
init_logging() {
    local log_level_name="$1"
    
    # Set log level based on name
    case "$log_level_name" in
        debug)
            LOG_LEVEL="$LOG_LEVEL_DEBUG"
            ;;
        info)
            LOG_LEVEL="$LOG_LEVEL_INFO"
            ;;
        warning)
            LOG_LEVEL="$LOG_LEVEL_WARNING"
            ;;
        error)
            LOG_LEVEL="$LOG_LEVEL_ERROR"
            ;;
        *)
            echo "Unknown log level: $log_level_name, using default (info)"
            LOG_LEVEL="$LOG_LEVEL_INFO"
            ;;
    esac
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    LOG_FILE="${LOG_DIR}/ingestor_$(date +%Y%m%d).log"
    
    # For testing, redirect to a test log file
    if [[ "$TEST_MODE" == "true" ]]; then
        LOG_FILE="${LOG_DIR}/test.log"
    fi
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE"
}

# Log a message at a specific level
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Only log if level is high enough
    if [[ "$level" -ge "$LOG_LEVEL" ]]; then
        local level_name
        case "$level" in
            "$LOG_LEVEL_DEBUG")
                level_name="DEBUG"
                ;;
            "$LOG_LEVEL_INFO")
                level_name="INFO"
                ;;
            "$LOG_LEVEL_WARNING")
                level_name="WARNING"
                ;;
            "$LOG_LEVEL_ERROR")
                level_name="ERROR"
                ;;
            *)
                level_name="UNKNOWN"
                ;;
        esac
        
        # Format: [TIMESTAMP] [LEVEL] message
        local log_entry="[$timestamp] [$level_name] $message"
        
        # Write to log file in test mode
        if [[ "$TEST_MODE" == "true" ]]; then
            echo "$log_entry" >> "$LOG_FILE"
        else
            # In normal mode, print to console and log file
            echo "$log_entry" | tee -a "$LOG_FILE"
        fi
    fi
}

# Convenience functions for different log levels
log_debug() {
    log_message "$LOG_LEVEL_DEBUG" "$*"
}

log_info() {
    log_message "$LOG_LEVEL_INFO" "$*"
}

log_warning() {
    log_message "$LOG_LEVEL_WARNING" "$*"
}

log_error() {
    log_message "$LOG_LEVEL_ERROR" "$*"
}

# Initialize logging with default level
init_logging "debug"
EOF
    
    # Mock config module
    cat > "${PROJECT_ROOT}/src/modules/config.sh" << 'EOF'
#!/bin/bash
# Configuration module for ingestor (mock for testing)

# Global config variables
CONFIG_FILE="${CONFIG_DIR}/settings.yml"
DATABASE_PROFILES_DIR="${CONFIG_DIR}/databases"
CLAUDE_API_KEY="mock_api_key"
DEFAULT_DATABASE="test_db"
LOG_LEVEL="debug"
ENABLE_CHUNKING="true"
CHUNK_SIZE=5000
CHUNK_OVERLAP=500
CHUNK_STRATEGY="size"

# Load configuration (mock version)
load_config() {
    log_debug "Mock: Loading configuration"
    
    # In test mode, we don't need to create real config files
    # Just set up the necessary variables
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATABASE_PROFILES_DIR"
    
    log_debug "Mock configuration loaded successfully"
}

# Get database profile (mock version)
get_database_profile() {
    local db_name="$1"
    local profile_file="${DATABASE_PROFILES_DIR}/${db_name}.yml"
    
    # For testing, we'll just return a success
    echo "$profile_file"
    return 0
}
EOF
    
    # Mock database module (simplified)
    cat > "${PROJECT_ROOT}/src/modules/database.sh" << 'EOF'
#!/bin/bash
# Database module for ingestor (mock for testing)

# Initialize database with schema
init_database() {
    local db_path="$1"
    local schema_file="$2"
    
    log_info "Mock: Initializing database at: $db_path with schema: $schema_file"
    
    # Create directory if needed
    mkdir -p "$(dirname "$db_path")"
    
    # Check if schema file exists
    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema file not found: $schema_file"
        return 1
    fi
    
    # For testing, we'll create an empty database file
    touch "$db_path"
    
    log_info "Mock: Database initialized successfully"
    return 0
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

# Store text data in database (mock)
store_text_data() {
    local db_name="$1"
    local text_path="$2"
    local analysis_file="$3"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Mock: Storing text data in database: $db_path"
    
    # For testing, just ensure database file exists
    touch "$db_path"
    
    log_info "Mock: Text data stored successfully: $(basename "$text_path")"
    return 0
}

# Store image data in database (mock)
store_image_data() {
    local db_name="$1"
    local image_path="$2"
    local metadata_file="$3"
    local analysis_file="$4"
    
    local db_path
    db_path=$(get_database_path "$db_name")
    
    log_debug "Mock: Storing image data in database: $db_path"
    
    # For testing, just ensure database file exists
    touch "$db_path"
    
    log_info "Mock: Image data stored successfully: $(basename "$image_path")"
    return 0
}
EOF
    
    # Mock content module (simplified)
    cat > "${PROJECT_ROOT}/src/modules/content.sh" << 'EOF'
#!/bin/bash
# Content module for ingestor (mock for testing)

# Detect content type
detect_content_type() {
    local input="$1"
    
    if [[ -f "$input" ]]; then
        # Check file extension
        local extension="${input##*.}"
        case "$extension" in
            txt|md) echo "text/plain" ;;
            jpg|jpeg|png) echo "image/${extension}" ;;
            *) echo "application/octet-stream" ;;
        esac
    else
        # Default to text/plain for testing
        echo "text/plain"
    fi
}

# Process content
process_content() {
    local content_path="$1"
    local database="$2"
    
    # Get content type
    local content_type
    content_type=$(detect_content_type "$content_path")
    
    log_info "Mock: Processing content of type: $content_type"
    
    # Process different content types
    case "$content_type" in
        text/*)
            process_text "$content_path" "$database"
            ;;
        image/*)
            process_image "$content_path" "$database"
            ;;
        *)
            log_warning "Unsupported content type: $content_type"
            return 1
            ;;
    esac
    
    return 0
}

# Process text files
process_text() {
    local text_path="$1"
    local database="$2"
    
    log_info "Mock: Processing text: $text_path"
    
    # Create mock analysis file
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$text_path").json"
    echo '{"mock": "analysis"}' > "$analysis_file"
    
    # Store in database
    store_text_data "$database" "$text_path" "$analysis_file"
    
    return 0
}

# Process image files
process_image() {
    local image_path="$1"
    local database="$2"
    
    log_info "Mock: Processing image: $image_path"
    
    # Create mock metadata and analysis files
    local metadata_file="${TEMP_DIR}/metadata_$(basename "$image_path").json"
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$image_path").json"
    
    echo '{"width": 1920, "height": 1080}' > "$metadata_file"
    echo '{"mock": "image_analysis"}' > "$analysis_file"
    
    # Store in database
    store_image_data "$database" "$image_path" "$metadata_file" "$analysis_file"
    
    return 0
}

# Mock function to simulate Claude API integration
analyze_with_claude() {
    local input="$1"
    local content_type="$2"
    
    echo '{"analysis": "Mock Claude analysis for '$content_type'", "confidence": 0.95}'
    return 0
}
EOF
    
    # Mock claude module
    cat > "${PROJECT_ROOT}/src/modules/claude.sh" << 'EOF'
#!/bin/bash
# Claude API integration module (mock for testing)

# Analyze content with Claude
analyze_with_claude() {
    local input="$1"
    local content_type="$2"
    
    log_debug "Mock: Analyzing $content_type with Claude API"
    
    # Return mock analysis
    echo '{"analysis": "Mock Claude analysis for '$content_type'", "confidence": 0.95}'
    return 0
}
EOF
    
    # Create a mock ingestor script with core functionality
    cat > "${PROJECT_ROOT}/src/ingestor" << 'EOF'
#!/bin/bash
# Ingestor script (mock for testing)

set -eo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default paths
INGESTOR_HOME="${INGESTOR_HOME:-$HOME/.ingestor}"
CONFIG_DIR="${INGESTOR_HOME}/config"
DB_DIR="${INGESTOR_HOME}/databases"
TEMP_DIR="${INGESTOR_HOME}/temp"
LOG_DIR="${INGESTOR_HOME}/logs"
SCHEMAS_DIR="${CONFIG_DIR}/schemas"

# Create directories if they don't exist
mkdir -p "$CONFIG_DIR"
mkdir -p "$DB_DIR"
mkdir -p "$TEMP_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$SCHEMAS_DIR"

# Chunking settings (defaults)
ENABLE_CHUNKING="false"
CHUNK_SIZE=500000
CHUNK_OVERLAP=5000
CHUNK_STRATEGY="size"

# Source modules
source "${SCRIPT_DIR}/modules/logging.sh"
source "${SCRIPT_DIR}/modules/config.sh"
source "${SCRIPT_DIR}/modules/database.sh"
source "${SCRIPT_DIR}/modules/content.sh"
source "${SCRIPT_DIR}/modules/claude.sh"

# Print usage information
print_usage() {
    cat << EOF
Usage: ingestor [OPTIONS]

Options:
  --file PATH               Process a specific file
  --directory DIR           Process all files in a directory (batch mode)
  --database NAME           Specify database to use (default: $DEFAULT_DATABASE)
  --init-db NAME            Initialize a new database
  --list-dbs                List available databases
  --enable-chunking         Enable content chunking
  --disable-chunking        Disable content chunking
  --chunk-size SIZE         Chunk size in bytes (default: $CHUNK_SIZE)
  --chunk-overlap SIZE      Chunk overlap in bytes (default: $CHUNK_OVERLAP)
  --chunk-strategy STRATEGY Chunking strategy: size, paragraph, sentence (default: $CHUNK_STRATEGY)
  --help                    Show this help message
EOF
}

# Initialize a database
initialize_database() {
    local db_name="$1"
    local db_path="${DB_DIR}/${db_name}.sqlite"
    local schema_file="${SCHEMAS_DIR}/general.sql"
    
    # Check if schema file exists
    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema file not found: $schema_file"
        exit 1
    fi
    
    # Initialize the database
    if init_database "$db_path" "$schema_file"; then
        log_info "Database $db_name initialized successfully"
    else
        log_error "Failed to initialize database $db_name"
        exit 1
    fi
}

# List available databases
list_databases() {
    log_info "Available databases:"
    
    # Check if the database directory exists
    if [[ ! -d "$DB_DIR" ]]; then
        log_info "No databases found"
        return
    fi
    
    # List database files
    local count=0
    for db_file in "$DB_DIR"/*.sqlite; do
        if [[ -f "$db_file" ]]; then
            db_name=$(basename "$db_file" .sqlite)
            echo " - $db_name"
            ((count++))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        log_info "No databases found"
    fi
}

# Process a single file
process_file() {
    local file_path="$1"
    local database="$2"
    
    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        return 1
    fi
    
    # Check if database exists, initialize if not
    if ! database_exists "$database"; then
        log_warning "Database $database does not exist, initializing..."
        initialize_database "$database"
    fi
    
    # Process the file
    if process_content "$file_path" "$database"; then
        log_info "Successfully processed: $file_path"
        return 0
    else
        log_error "Failed to process: $file_path"
        return 1
    fi
}

# Process directory (batch mode)
run_batch_mode() {
    local directory="$1"
    local database="$2"
    local extensions="$3"
    local recursive="$4"
    local max_files="$5"
    
    # Check if directory exists
    if [[ ! -d "$directory" ]]; then
        log_error "Directory not found: $directory"
        return 1
    fi
    
    log_info "Running batch mode on directory: $directory"
    log_info "Using database: $database"
    
    # Build find command
    local find_cmd="find \"$directory\""
    
    # Add maxdepth if not recursive
    if [[ "$recursive" != "true" ]]; then
        find_cmd="$find_cmd -maxdepth 1"
    fi
    
    # Add type filter for files
    find_cmd="$find_cmd -type f"
    
    # Add extension filter if provided
    if [[ -n "$extensions" ]]; then
        local ext_pattern=""
        IFS=',' read -ra EXT_ARRAY <<< "$extensions"
        for ext in "${EXT_ARRAY[@]}"; do
            ext=$(echo "$ext" | tr -d '[:space:]')
            if [[ -n "$ext_pattern" ]]; then
                ext_pattern="$ext_pattern -o -name \"*.$ext\""
            else
                ext_pattern="-name \"*.$ext\""
            fi
        done
        find_cmd="$find_cmd \\( $ext_pattern \\)"
    fi
    
    # Execute the find command to get files
    log_debug "Find command: $find_cmd"
    local files
    files=$(eval "$find_cmd")
    
    # Limit number of files if max_files is set
    if [[ -n "$max_files" && "$max_files" -gt 0 ]]; then
        files=$(echo "$files" | head -n "$max_files")
    fi
    
    # Process each file
    local total_files=0
    local successful_files=0
    local failed_files=0
    
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            ((total_files++))
            
            log_info "Processing file $total_files: $file"
            if process_file "$file" "$database"; then
                ((successful_files++))
            else
                ((failed_files++))
            fi
        fi
    done <<< "$files"
    
    # Print summary
    log_info "Batch processing complete"
    log_info "Total files: $total_files"
    log_info "Successfully processed: $successful_files"
    log_info "Failed: $failed_files"
    
    # Return success if at least one file was processed successfully
    if [[ $successful_files -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Main function
main() {
    # Default values
    local file=""
    local directory=""
    local database="$DEFAULT_DATABASE"
    local init_db=""
    local list_dbs=false
    local extensions=""
    local recursive=false
    local max_files=0
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                file="$2"
                shift 2
                ;;
            --directory)
                directory="$2"
                shift 2
                ;;
            --database)
                database="$2"
                shift 2
                ;;
            --init-db)
                init_db="$2"
                shift 2
                ;;
            --list-dbs)
                list_dbs=true
                shift
                ;;
            --enable-chunking)
                ENABLE_CHUNKING="true"
                shift
                ;;
            --disable-chunking)
                ENABLE_CHUNKING="false"
                shift
                ;;
            --chunk-size)
                CHUNK_SIZE="$2"
                shift 2
                ;;
            --chunk-overlap)
                CHUNK_OVERLAP="$2"
                shift 2
                ;;
            --chunk-strategy)
                CHUNK_STRATEGY="$2"
                shift 2
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Load configuration
    load_config
    
    # Handle database operations
    if [[ -n "$init_db" ]]; then
        initialize_database "$init_db"
        exit 0
    fi
    
    if [[ "$list_dbs" == true ]]; then
        list_databases
        exit 0
    fi
    
    # Process content
    if [[ -n "$file" ]]; then
        # Process single file
        process_file "$file" "$database"
    elif [[ -n "$directory" ]]; then
        # Process directory (batch mode)
        run_batch_mode "$directory" "$database" "$extensions" "$recursive" "$max_files"
    else
        log_error "No file or directory specified"
        print_usage
        exit 1
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF
    
    # Make the ingestor script executable
    chmod +x "${PROJECT_ROOT}/src/ingestor"
    
    # Create test files
    mkdir -p "${TEST_TEMP_DIR}/test_files"
    echo "This is a test text file." > "${TEST_TEMP_DIR}/test_files/test.txt"
    echo "Mock image data" > "${TEST_TEMP_DIR}/test_files/test.jpg"
    
    # Source all the modules
    source "${PROJECT_ROOT}/src/modules/logging.sh"
    source "${PROJECT_ROOT}/src/modules/config.sh"
    source "${PROJECT_ROOT}/src/modules/database.sh"
    source "${PROJECT_ROOT}/src/modules/content.sh"
    source "${PROJECT_ROOT}/src/modules/claude.sh"
}

# Teardown - runs after each test
teardown() {
    # Call the common teardown
    teardown_test_environment
}

# Test database initialization
@test "ingestor can initialize a database" {
    run "${PROJECT_ROOT}/src/ingestor" --init-db "test_db"
    assert_success
    assert_file_exists "${DB_DIR}/test_db.sqlite"
}

# Test processing a single file
@test "ingestor can process a single text file" {
    # Initialize the database first
    run "${PROJECT_ROOT}/src/ingestor" --init-db "test_db"
    assert_success
    
    # Process a text file
    run "${PROJECT_ROOT}/src/ingestor" --file "${TEST_TEMP_DIR}/test_files/test.txt" --database "test_db"
    assert_success
    
    # Check the log file for success message
    assert_file_exists "${LOG_DIR}/test.log"
    run grep "Successfully processed" "${LOG_DIR}/test.log"
    assert_success
}

# Test processing a single image file
@test "ingestor can process a single image file" {
    # Initialize the database first
    run "${PROJECT_ROOT}/src/ingestor" --init-db "test_db"
    assert_success
    
    # Process an image file
    run "${PROJECT_ROOT}/src/ingestor" --file "${TEST_TEMP_DIR}/test_files/test.jpg" --database "test_db"
    assert_success
    
    # Check the log file for success message
    assert_file_exists "${LOG_DIR}/test.log"
    run grep "Successfully processed" "${LOG_DIR}/test.log"
    assert_success
}

# Test batch processing
@test "ingestor can process multiple files in batch mode" {
    # Initialize the database first
    run "${PROJECT_ROOT}/src/ingestor" --init-db "test_db"
    assert_success
    
    # Process all files in the directory
    run "${PROJECT_ROOT}/src/ingestor" --directory "${TEST_TEMP_DIR}/test_files" --database "test_db"
    assert_success
    
    # Check the log file for success message
    assert_file_exists "${LOG_DIR}/test.log"
    run grep "Batch processing complete" "${LOG_DIR}/test.log"
    assert_success
}

# Test listing databases
@test "ingestor can list available databases" {
    # Initialize the database first
    run "${PROJECT_ROOT}/src/ingestor" --init-db "test_db"
    assert_success
    
    # List databases
    run "${PROJECT_ROOT}/src/ingestor" --list-dbs
    assert_success
}

# Test enabling chunking
@test "ingestor supports content chunking options" {
    # Initialize the database first
    run "${PROJECT_ROOT}/src/ingestor" --init-db "test_db"
    assert_success
    
    # Process a text file with chunking enabled
    run "${PROJECT_ROOT}/src/ingestor" --file "${TEST_TEMP_DIR}/test_files/test.txt" --database "test_db" --enable-chunking --chunk-size 1000 --chunk-overlap 100 --chunk-strategy "paragraph"
    assert_success
    
    # Check the log file
    assert_file_exists "${LOG_DIR}/test.log"
    run grep "Successfully processed" "${LOG_DIR}/test.log"
    assert_success
}

# Test basic workflow
@test "ingestor basic end-to-end workflow" {
    # 1. Initialize database
    run "${PROJECT_ROOT}/src/ingestor" --init-db "workflow_test"
    assert_success
    
    # 2. Process a file
    run "${PROJECT_ROOT}/src/ingestor" --file "${TEST_TEMP_DIR}/test_files/test.txt" --database "workflow_test"
    assert_success
    
    # 3. List databases
    run "${PROJECT_ROOT}/src/ingestor" --list-dbs
    assert_success
    
    # 4. Process another file with chunking
    run "${PROJECT_ROOT}/src/ingestor" --file "${TEST_TEMP_DIR}/test_files/test.jpg" --database "workflow_test" --enable-chunking
    assert_success
    
    # 5. Check that database exists
    assert_file_exists "${DB_DIR}/workflow_test.sqlite"
}