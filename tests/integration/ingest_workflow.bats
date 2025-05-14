#!/usr/bin/env bats
# Integration tests for the complete ingestor workflow

# Load the test helper
load '../test_helper'

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Set up test-specific paths
    export TEST_PROJECT_DIR="${TEST_TEMP_DIR}/project"
    export CONFIG_DIR="${TEST_TEMP_DIR}/.ingestor/config"
    export DATABASE_DIR="${TEST_TEMP_DIR}/.ingestor/databases"
    export LOGS_DIR="${TEST_TEMP_DIR}/.ingestor/logs"
    export TEMP_DIR="${TEST_TEMP_DIR}/.ingestor/temp"
    export INGESTOR_HOME="${TEST_TEMP_DIR}/.ingestor"
    
    # Create necessary directories
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${DATABASE_DIR}"
    mkdir -p "${LOGS_DIR}"
    mkdir -p "${TEMP_DIR}"
    mkdir -p "${TEST_PROJECT_DIR}/test_data"
    
    # Create a simple test file
    echo "This is a test text file for the ingestor system." > "${TEST_PROJECT_DIR}/test_data/simple.txt"
    echo "It contains simple content that can be processed." >> "${TEST_PROJECT_DIR}/test_data/simple.txt"
    echo "The ingestor should be able to handle this basic text file." >> "${TEST_PROJECT_DIR}/test_data/simple.txt"
    
    # Create a configuration file
    cat > "${CONFIG_DIR}/settings.yml" << 'EOF'
# Test Ingestor Configuration

# Claude API Key (test mode)
claude_api_key: test_api_key_123

# Default database to use if none specified
default_database: test_db

# Log level (debug, info, warning, error)
log_level: debug

# Content processing settings
content:
  # Maximum file size in bytes for direct processing
  max_file_size: 1048576 # 1MB
  
  # Chunk size for large files
  chunk_size: 102400 # 100KB
  
  # Temporary file handling
  keep_temp_files: true

# Database settings
database:
  # Directory for database files relative to ~/.ingestor
  directory: databases
  
  # Whether to compress databases automatically
  auto_vacuum: true
  
  # Journal mode for databases
  journal_mode: WAL

# Claude integration settings
claude:
  # Model to use
  model: claude-test-model
  
  # Maximum tokens per request
  max_tokens: 1000
  
  # Temperature for generation
  temperature: 0.0
  
  # Request timeout in seconds
  timeout: 5
  
  # Maximum retries on failure
  max_retries: 1
EOF
    
    # Create a test database schema
    cat > "${TEST_PROJECT_DIR}/test_data/schema.sql" << 'EOF'
-- Test database schema

-- Main content table
CREATE TABLE IF NOT EXISTS content (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    content_type TEXT NOT NULL,
    title TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    content_text TEXT,
    metadata TEXT
);

-- Chunks table for large content
CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_id INTEGER NOT NULL,
    chunk_index INTEGER NOT NULL,
    chunk_text TEXT NOT NULL,
    FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE
);

-- Tags table
CREATE TABLE IF NOT EXISTS tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL
);

-- Content-Tags relationship
CREATE TABLE IF NOT EXISTS content_tags (
    content_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (content_id, tag_id),
    FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- Entities table (people, organizations, locations, etc.)
CREATE TABLE IF NOT EXISTS entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    type TEXT NOT NULL, -- person, organization, location, etc.
    metadata TEXT
);

-- Content-Entities relationship
CREATE TABLE IF NOT EXISTS content_entities (
    content_id INTEGER NOT NULL,
    entity_id INTEGER NOT NULL,
    PRIMARY KEY (content_id, entity_id),
    FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE,
    FOREIGN KEY (entity_id) REFERENCES entities(id) ON DELETE CASCADE
);

-- FTS virtual table for full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
    content_text,
    title,
    metadata,
    content='content',
    content_rowid='id'
);

-- Triggers to keep FTS table in sync
CREATE TRIGGER IF NOT EXISTS content_ai AFTER INSERT ON content BEGIN
    INSERT INTO content_fts(rowid, content_text, title, metadata)
    VALUES (new.id, new.content_text, new.title, new.metadata);
END;

CREATE TRIGGER IF NOT EXISTS content_ad AFTER DELETE ON content BEGIN
    INSERT INTO content_fts(content_fts, rowid, content_text, title, metadata)
    VALUES('delete', old.id, old.content_text, old.title, old.metadata);
END;

CREATE TRIGGER IF NOT EXISTS content_au AFTER UPDATE ON content BEGIN
    INSERT INTO content_fts(content_fts, rowid, content_text, title, metadata)
    VALUES('delete', old.id, old.content_text, old.title, old.metadata);
    INSERT INTO content_fts(rowid, content_text, title, metadata)
    VALUES (new.id, new.content_text, new.title, new.metadata);
END;
EOF

    # Create sqlite database for testing
    sqlite3 "${DATABASE_DIR}/test_db.sqlite" < "${TEST_PROJECT_DIR}/test_data/schema.sql"
    
    # Create mock ingestor script
    cat > "${TEST_PROJECT_DIR}/ingestor" << 'EOF'
#!/bin/bash
# Mock ingestor script for testing

# Configuration
INGESTOR_HOME="${INGESTOR_HOME:-$HOME/.ingestor}"
CONFIG_DIR="${INGESTOR_HOME}/config"
CONFIG_FILE="${CONFIG_DIR}/settings.yml"
DATABASE_DIR="${INGESTOR_HOME}/databases"
DEFAULT_DB="test_db"

# Parse command line arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --file)
            FILE_PATH="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --init-db)
            INIT_DB="$2"
            shift 2
            ;;
        --list-dbs)
            LIST_DBS=true
            shift
            ;;
        --help)
            echo "Usage: ingestor [options]"
            echo
            echo "Options:"
            echo "  --file PATH        Process the file at PATH"
            echo "  --database NAME    Use the database with NAME"
            echo "  --init-db NAME     Initialize a new database with NAME"
            echo "  --list-dbs         List available databases"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

# Handle list databases command
if [[ "$LIST_DBS" == true ]]; then
    echo "Available databases:"
    for db in "${DATABASE_DIR}"/*.sqlite; do
        echo "  - $(basename "$db" .sqlite)"
    done
    exit 0
fi

# Handle database initialization
if [[ -n "$INIT_DB" ]]; then
    DB_PATH="${DATABASE_DIR}/${INIT_DB}.sqlite"
    
    # Check if database already exists
    if [[ -f "$DB_PATH" ]]; then
        echo "Database '$INIT_DB' already exists."
        exit 1
    fi
    
    # Initialize the database with schema
    echo "Initializing database '$INIT_DB'..."
    sqlite3 "$DB_PATH" < "${TEST_PROJECT_DIR}/test_data/schema.sql"
    
    echo "Database '$INIT_DB' has been initialized."
    exit 0
fi

# Set the database to use
DATABASE="${DATABASE:-$DEFAULT_DB}"
DB_PATH="${DATABASE_DIR}/${DATABASE}.sqlite"

# Check if database exists
if [[ ! -f "$DB_PATH" ]]; then
    echo "Error: Database '$DATABASE' not found. Use --init-db to create it."
    exit 1
fi

# Process a file if specified
if [[ -n "$FILE_PATH" ]]; then
    # Check if file exists
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: File not found: $FILE_PATH"
        exit 1
    fi
    
    # Get file type
    CONTENT_TYPE=$(file --mime-type -b "$FILE_PATH")
    
    # Read file content
    CONTENT=$(cat "$FILE_PATH")
    
    # Insert into database
    TITLE=$(basename "$FILE_PATH")
    echo "Processing file: $FILE_PATH ($CONTENT_TYPE)"
    
    # In a real implementation, this would call the Claude API
    # For testing, we'll just insert the content directly
    sqlite3 "$DB_PATH" << EOSQL
INSERT INTO content (file_path, content_type, title, content_text, metadata)
VALUES ('$FILE_PATH', '$CONTENT_TYPE', '$TITLE', '$CONTENT', '{"source": "test"}');
EOSQL
    
    echo "File successfully processed and added to the '$DATABASE' database."
    exit 0
fi

# If no specific command was given, show usage
echo "No command specified. Use --help to see available options."
exit 1
EOF
    
    # Make the mock ingestor executable
    chmod +x "${TEST_PROJECT_DIR}/ingestor"
}

# Teardown - runs after each test
teardown() {
    teardown_test_environment
}

# Test listing databases
@test "ingestor --list-dbs lists available databases" {
    run "${TEST_PROJECT_DIR}/ingestor" --list-dbs
    
    assert_success
    assert_output --partial "Available databases:"
    assert_output --partial "test_db"
}

# Test database initialization
@test "ingestor --init-db creates a new database" {
    run "${TEST_PROJECT_DIR}/ingestor" --init-db "new_test_db"
    
    assert_success
    assert_output --partial "Initializing database 'new_test_db'"
    assert_output --partial "Database 'new_test_db' has been initialized"
    
    # Verify the database was created
    [ -f "${DATABASE_DIR}/new_test_db.sqlite" ]
}

# Test attempting to initialize an existing database
@test "ingestor --init-db fails if database already exists" {
    # First create the database
    run "${TEST_PROJECT_DIR}/ingestor" --init-db "existing_db"
    assert_success
    
    # Now try to create it again
    run "${TEST_PROJECT_DIR}/ingestor" --init-db "existing_db"
    
    assert_failure
    assert_output --partial "Database 'existing_db' already exists"
}

# Test processing a text file
@test "ingestor --file processes a text file" {
    run "${TEST_PROJECT_DIR}/ingestor" --file "${TEST_PROJECT_DIR}/test_data/simple.txt" --database "test_db"
    
    assert_success
    assert_output --partial "Processing file:"
    assert_output --partial "File successfully processed"
    
    # Verify the file was added to the database
    run sqlite3 "${DATABASE_DIR}/test_db.sqlite" "SELECT COUNT(*) FROM content WHERE title='simple.txt';"
    assert_output "1"
}

# Test processing with a non-existent database
@test "ingestor --file fails with non-existent database" {
    run "${TEST_PROJECT_DIR}/ingestor" --file "${TEST_PROJECT_DIR}/test_data/simple.txt" --database "nonexistent_db"
    
    assert_failure
    assert_output --partial "Error: Database 'nonexistent_db' not found"
}

# Test processing a non-existent file
@test "ingestor --file fails with non-existent file" {
    run "${TEST_PROJECT_DIR}/ingestor" --file "${TEST_PROJECT_DIR}/test_data/nonexistent.txt" --database "test_db"
    
    assert_failure
    assert_output --partial "Error: File not found"
}

# Test complete workflow (init db, process file, verify content)
@test "complete workflow: init db, process file, verify content" {
    # Create a new database
    run "${TEST_PROJECT_DIR}/ingestor" --init-db "workflow_test"
    assert_success
    
    # Process a file
    run "${TEST_PROJECT_DIR}/ingestor" --file "${TEST_PROJECT_DIR}/test_data/simple.txt" --database "workflow_test"
    assert_success
    
    # Verify file was added correctly
    run sqlite3 "${DATABASE_DIR}/workflow_test.sqlite" "SELECT content_text FROM content WHERE title='simple.txt';"
    assert_success
    assert_output --partial "This is a test text file for the ingestor system."
    
    # Check content type is correct
    run sqlite3 "${DATABASE_DIR}/workflow_test.sqlite" "SELECT content_type FROM content WHERE title='simple.txt';"
    assert_success
    assert_output --partial "text/"
}

# Test fulltext search functionality 
@test "fulltext search finds content correctly" {
    # Create a database with content
    run "${TEST_PROJECT_DIR}/ingestor" --init-db "search_test"
    assert_success
    
    run "${TEST_PROJECT_DIR}/ingestor" --file "${TEST_PROJECT_DIR}/test_data/simple.txt" --database "search_test"
    assert_success
    
    # Test fulltext search
    run sqlite3 "${DATABASE_DIR}/search_test.sqlite" "SELECT title FROM content WHERE id IN (SELECT rowid FROM content_fts WHERE content_fts MATCH 'ingestor');"
    assert_success
    assert_output "simple.txt"
}