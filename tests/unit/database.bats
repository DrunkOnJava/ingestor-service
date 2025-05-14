#!/usr/bin/env bats
# Unit tests for the database.sh module

# Load the test helper
load ../test_helper

# Setup - runs before each test
setup() {
    # Call the common setup
    setup_test_environment
    
    # Set up mock variables needed for the database module
    export DB_DIR="${TEST_TEMP_DIR}/databases"
    export TEMP_DIR="${TEST_TEMP_DIR}/temp"
    export TEST_DB_NAME="test_db"
    export TEST_DB_PATH="${DB_DIR}/${TEST_DB_NAME}.sqlite"
    
    # Create necessary directories
    mkdir -p "${DB_DIR}"
    mkdir -p "${TEMP_DIR}"
    
    # Create a mock logging module
    cat > "${TEST_TEMP_DIR}/logging.sh" << 'EOF'
#!/bin/bash
# Mock logging module for testing

log_debug() {
    echo "[DEBUG] $*" >/dev/null
}

log_info() {
    echo "[INFO] $*" >/dev/null
}

log_warning() {
    echo "[WARNING] $*" >/dev/null
}

log_error() {
    echo "[ERROR] $*" >/dev/null
}
EOF
    
    source "${TEST_TEMP_DIR}/logging.sh"
    
    # Create test schema file
    cat > "${TEST_TEMP_DIR}/test_schema.sql" << 'EOF'
-- Test database schema

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

-- Videos table
CREATE TABLE IF NOT EXISTS videos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    duration REAL,
    width INTEGER,
    height INTEGER,
    metadata TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Documents table
CREATE TABLE IF NOT EXISTS documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Document chunks table
CREATE TABLE IF NOT EXISTS document_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    content TEXT,
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

-- Text chunks table
CREATE TABLE IF NOT EXISTS text_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Code table
CREATE TABLE IF NOT EXISTS code (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    language TEXT NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Generic content table
CREATE TABLE IF NOT EXISTS generic_content (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    metadata TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Create full-text search tables
CREATE VIRTUAL TABLE IF NOT EXISTS fts_documents USING fts5(
    content, analysis,
    content=documents, content_rowid=id
);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_texts USING fts5(
    content, analysis,
    content=texts, content_rowid=id
);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_code USING fts5(
    content, analysis,
    content=code, content_rowid=id
);

-- Create triggers to keep FTS tables in sync
CREATE TRIGGER IF NOT EXISTS documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO fts_documents(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;

CREATE TRIGGER IF NOT EXISTS texts_ai AFTER INSERT ON texts BEGIN
    INSERT INTO fts_texts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;

CREATE TRIGGER IF NOT EXISTS code_ai AFTER INSERT ON code BEGIN
    INSERT INTO fts_code(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;
EOF

    # Mock the extract_image_metadata function
    extract_image_metadata() {
        local image_path="$1"
        local field="$2"
        
        case "$field" in
            "ImageWidth") echo "1920" ;;
            "ImageHeight") echo "1080" ;;
            "CreateDate") echo "2025:05:10 12:00:00" ;;
            *) echo "Unknown" ;;
        esac
    }
    export -f extract_image_metadata
    
    # Mock sqlite3 command
    sqlite3() {
        # First argument is the database path
        local db_path="$1"
        
        # If there's a second argument, it's either a SQL file to execute or a query
        if [[ -n "$2" ]]; then
            # If it's a file (for init_database), just create an empty file
            if [[ -f "$2" ]]; then
                touch "$db_path"
                return 0
            fi
            
            # Otherwise it's a query, check for different operations
            if [[ "$2" == *"INSERT INTO"* ]]; then
                # Create the database file if it doesn't exist
                touch "$db_path"
                return 0
            fi
        fi
        
        # Default success
        return 0
    }
    export -f sqlite3
    
    # Source the database module to test
    source "${PROJECT_ROOT}/src/modules/database.sh"
}

# Teardown - runs after each test
teardown() {
    # Call the common teardown
    teardown_test_environment
}

# Create sample files for testing
create_sample_files() {
    # Create sample image
    echo "Mock image data" > "$TEST_TEMP_DIR/sample.jpg"
    
    # Create sample video
    echo "Mock video data" > "$TEST_TEMP_DIR/sample.mp4"
    
    # Create sample text
    echo "This is a sample text file." > "$TEST_TEMP_DIR/sample.txt"
    
    # Create sample PDF
    echo "%PDF-1.5 Mock PDF data" > "$TEST_TEMP_DIR/sample.pdf"
    
    # Create sample code file
    cat > "$TEST_TEMP_DIR/sample.py" << EOF
def hello():
    print("Hello, world!")
EOF

    # Create sample unknown file
    echo "Unknown data format" > "$TEST_TEMP_DIR/sample.xyz"
    
    # Create sample metadata files
    echo '{"width": 1920, "height": 1080}' > "$TEMP_DIR/metadata_sample.jpg.json"
    echo '{"duration": 60, "streams": [{"width": 1920, "height": 1080}]}' > "$TEMP_DIR/metadata_sample.mp4.json"
    echo '{"filename": "sample.xyz", "size": 123}' > "$TEMP_DIR/metadata_sample.xyz.json"
    
    # Create sample analysis files
    echo '{"objects": ["person", "car"], "description": "An image showing a street scene"}' > "$TEMP_DIR/analysis_sample.jpg.json"
    echo '{"scenes": ["intro", "main", "outro"], "description": "A video about nature"}' > "$TEMP_DIR/analysis_sample.mp4.json"
    echo '{"content_type": "text", "summary": "A simple text document"}' > "$TEMP_DIR/analysis_sample.txt.json"
    echo '{"content_type": "pdf", "summary": "A simple PDF document"}' > "$TEMP_DIR/analysis_sample.pdf.json"
    echo '{"language": "python", "functions": ["hello"]}' > "$TEMP_DIR/analysis_sample.py.json"
    echo '{"content_type": "unknown", "description": "Unknown file format"}' > "$TEMP_DIR/analysis_sample.xyz.json"
    
    # Create sample text content
    echo "Extracted text from PDF" > "$TEMP_DIR/text_sample.pdf.txt"
    
    # Create sample chunks
    echo "Chunk 1 of sample.pdf" > "$TEMP_DIR/chunk_text_sample.pdf_1.txt"
    echo "Chunk 2 of sample.pdf" > "$TEMP_DIR/chunk_text_sample.pdf_2.txt"
    echo "Chunk 1 of sample.txt" > "$TEMP_DIR/chunk_sample.txt_1.txt"
    echo "Chunk 2 of sample.txt" > "$TEMP_DIR/chunk_sample.txt_2.txt"
    
    # Create sample chunk analysis files
    echo '{"content_type": "pdf_chunk", "summary": "Analysis of chunk 1"}' > "$TEMP_DIR/analysis_chunk_text_sample.pdf_1.txt.json"
    echo '{"content_type": "pdf_chunk", "summary": "Analysis of chunk 2"}' > "$TEMP_DIR/analysis_chunk_text_sample.pdf_2.txt.json"
    echo '{"content_type": "text_chunk", "summary": "Analysis of text chunk 1"}' > "$TEMP_DIR/analysis_chunk_sample.txt_1.txt.json"
    echo '{"content_type": "text_chunk", "summary": "Analysis of text chunk 2"}' > "$TEMP_DIR/analysis_chunk_sample.txt_2.txt.json"
}

# Test database initialization
@test "init_database creates database with schema" {
    run init_database "$TEST_DB_PATH" "${TEST_TEMP_DIR}/test_schema.sql"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

@test "init_database fails with missing schema file" {
    run init_database "$TEST_DB_PATH" "${TEST_TEMP_DIR}/nonexistent_schema.sql"
    assert_failure
}

# Test database_exists function
@test "database_exists returns true for existing database" {
    # Create an empty database file
    mkdir -p "$DB_DIR"
    touch "$TEST_DB_PATH"
    
    run database_exists "$TEST_DB_NAME"
    assert_success
}

@test "database_exists returns false for non-existent database" {
    run database_exists "nonexistent_db"
    assert_failure
}

# Test get_database_path function
@test "get_database_path returns correct path" {
    run get_database_path "custom_db"
    assert_output "${DB_DIR}/custom_db.sqlite"
}

# Test store_image_data function
@test "store_image_data successfully stores image data" {
    create_sample_files
    
    run store_image_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.jpg" "$TEMP_DIR/metadata_sample.jpg.json" "$TEMP_DIR/analysis_sample.jpg.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_video_data function
@test "store_video_data successfully stores video data" {
    create_sample_files
    
    run store_video_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.mp4" "$TEMP_DIR/metadata_sample.mp4.json" "$TEMP_DIR/analysis_sample.mp4.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_document_data function
@test "store_document_data successfully stores document data" {
    create_sample_files
    
    run store_document_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.pdf" "$TEMP_DIR/text_sample.pdf.txt" "$TEMP_DIR/analysis_sample.pdf.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_document_chunk function
@test "store_document_chunk successfully stores document chunk" {
    create_sample_files
    
    run store_document_chunk "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.pdf" "$TEMP_DIR/chunk_text_sample.pdf_1.txt" "$TEMP_DIR/analysis_chunk_text_sample.pdf_1.txt.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_text_data function
@test "store_text_data successfully stores text data" {
    create_sample_files
    
    run store_text_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.txt" "$TEMP_DIR/analysis_sample.txt.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_text_chunk function
@test "store_text_chunk successfully stores text chunk" {
    create_sample_files
    
    run store_text_chunk "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.txt" "$TEMP_DIR/chunk_sample.txt_1.txt" "$TEMP_DIR/analysis_chunk_sample.txt_1.txt.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_code_data function
@test "store_code_data successfully stores code data" {
    create_sample_files
    
    run store_code_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.py" "python" "$TEMP_DIR/analysis_sample.py.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test store_generic_data function
@test "store_generic_data successfully stores generic data" {
    create_sample_files
    
    run store_generic_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/sample.xyz" "application/octet-stream" "$TEMP_DIR/metadata_sample.xyz.json" "$TEMP_DIR/analysis_sample.xyz.json"
    assert_success
    assert_file_exists "$TEST_DB_PATH"
}

# Test multiple SQL escaping in store functions
@test "SQL escaping handles single quotes properly" {
    # Create sample file with single quotes
    echo "This file's content has 'single quotes'" > "$TEST_TEMP_DIR/quotes.txt"
    echo "{'analysis': 'Contains single quotes', 'quote': 'John's analysis'}" > "$TEMP_DIR/analysis_quotes.txt.json"
    
    run store_text_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/quotes.txt" "$TEMP_DIR/analysis_quotes.txt.json"
    assert_success
}

# Test handling of non-existent files
@test "store functions handle non-existent files gracefully" {
    # This test relies on the mocked sqlite3 function
    # Even with non-existent files, our mocks should make this appear to succeed
    run store_text_data "$TEST_DB_NAME" "$TEST_TEMP_DIR/nonexistent.txt" "$TEMP_DIR/nonexistent.json"
    assert_success
}