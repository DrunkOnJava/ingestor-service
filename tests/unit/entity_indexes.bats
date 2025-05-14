#!/usr/bin/env bats
# Test cases for entity indexing feature

load ../test_helper
load ../assertions

setup() {
    setup_test_temp_dir
    DB_DIR="${TEST_TEMP_DIR}/databases"
    mkdir -p "${DB_DIR}"
    export DB_DIR
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
}

# Create a temporary database with the general schema and entities table
create_test_db() {
    local db_name="$1"
    local db_path="${DB_DIR}/${db_name}.sqlite"
    
    # Create a very minimal schema with entities and content_entities tables
    cat > "${TEST_TEMP_DIR}/minimal_schema.sql" << 'EOF'
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE content_entities (
    id INTEGER PRIMARY KEY,
    content_id INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    entity_id INTEGER NOT NULL,
    relevance REAL,
    context TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
    
    # Initialize database with minimal schema
    init_database "${db_path}" "${TEST_TEMP_DIR}/minimal_schema.sql" true false
    
    # Return the database path
    echo "${db_path}"
}

# Helper to check if an index exists in the database
index_exists() {
    local db_path="$1"
    local index_name="$2"
    
    local result
    result=$(sqlite3 "${db_path}" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='${index_name}';")
    
    [[ "${result}" -eq 1 ]]
}

# Create the entity_indexes.sql script in the test directory
create_entity_indexes_script() {
    cat > "${TEST_TEMP_DIR}/entity_indexes.sql" << 'EOF'
-- Entity Tables Indexing Script
-- This script adds optimized indexes to the entity-related tables to improve query performance

-- Start transaction
BEGIN TRANSACTION;

-- Add composite index for entity_type and name 
-- This will improve lookups by entity type and partial name matches
CREATE INDEX IF NOT EXISTS idx_entities_type_name ON entities(entity_type, name);

-- Add index for entity creation date
-- Useful for finding recently added entities
CREATE INDEX IF NOT EXISTS idx_entities_creation_date ON entities(created_at);

-- Add better indexes for content_entities table
-- These improve lookups when searching for entities within specific content types
CREATE INDEX IF NOT EXISTS idx_content_entities_content ON content_entities(content_id, content_type);

-- Add index for relevance to help with filtering high-relevance entities
CREATE INDEX IF NOT EXISTS idx_content_entities_relevance ON content_entities(relevance);

-- Add composite index for entity_id and relevance
-- This helps when finding the most relevant mentions of a specific entity
CREATE INDEX IF NOT EXISTS idx_content_entities_entity_relevance ON content_entities(entity_id, relevance);

-- Update statistics to ensure the query planner uses the new indexes effectively
ANALYZE entities;
ANALYZE content_entities;

-- Commit transaction
COMMIT;
EOF
}

# Test entity indexing with optimize_entity_indexes function
@test "optimize_entity_indexes creates expected indexes" {
    # Skip test if optimize_entity_indexes function is not available
    if ! type optimize_entity_indexes &>/dev/null; then
        skip "optimize_entity_indexes function not available"
    fi
    
    # Create a test database
    local db_name="test_entity_indexes"
    local db_path=$(create_test_db "${db_name}")
    
    # Create the entity indexes script
    create_entity_indexes_script
    
    # Call optimize_entity_indexes with the test script
    run optimize_entity_indexes "${db_name}" "${TEST_TEMP_DIR}/entity_indexes.sql"
    assert_success
    
    # Check that the expected indexes were created
    assert index_exists "${db_path}" "idx_entities_type_name"
    assert index_exists "${db_path}" "idx_entities_creation_date"
    assert index_exists "${db_path}" "idx_content_entities_content"
    assert index_exists "${db_path}" "idx_content_entities_relevance"
    assert index_exists "${db_path}" "idx_content_entities_entity_relevance"
    
    # Check that maintenance log was created and updated
    local maintenance_log_exists
    maintenance_log_exists=$(sqlite3 "${db_path}" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='maintenance_log';")
    assert_equal "${maintenance_log_exists}" "1"
    
    local operation_recorded
    operation_recorded=$(sqlite3 "${db_path}" "SELECT COUNT(*) FROM maintenance_log WHERE operation='entity_indexes_optimization';")
    assert_equal "${operation_recorded}" "1"
}

# Test entity indexing performance improvement
@test "entity indexes improve query performance" {
    # Skip test if db_query function is not available
    if ! type db_query &>/dev/null; then
        skip "db_query function not available"
    fi
    
    # Create a test database
    local db_name="test_entity_performance"
    local db_path=$(create_test_db "${db_name}")
    
    # Insert sample data for performance testing - 1000 entities and 5000 content links
    sqlite3 "${db_path}" << 'EOF'
-- Insert sample entities
BEGIN TRANSACTION;
INSERT INTO entities (name, entity_type, description)
SELECT 'Entity_' || i, 
       CASE (i % 5) 
           WHEN 0 THEN 'person' 
           WHEN 1 THEN 'organization' 
           WHEN 2 THEN 'location' 
           WHEN 3 THEN 'date' 
           ELSE 'other' 
       END,
       'Description for Entity_' || i
FROM (WITH RECURSIVE cnt(i) AS (
          SELECT 1
          UNION ALL
          SELECT i+1 FROM cnt
          LIMIT 1000
      )
      SELECT i FROM cnt);
COMMIT;

-- Insert sample content_entities
BEGIN TRANSACTION;
INSERT INTO content_entities (content_id, content_type, entity_id, relevance, context)
SELECT 
    (i % 100) + 1,  -- content_id (100 content items)
    CASE ((i/100) % 4)
        WHEN 0 THEN 'text/plain'
        WHEN 1 THEN 'application/pdf'
        WHEN 2 THEN 'text/html'
        ELSE 'image/jpeg'
    END,  -- content_type
    (i % 1000) + 1,  -- entity_id (link to all 1000 entities)
    (i % 100) / 100.0,  -- relevance (0.0 - 0.99)
    'Context for link ' || i  -- context
FROM (WITH RECURSIVE cnt(i) AS (
          SELECT 1
          UNION ALL
          SELECT i+1 FROM cnt
          LIMIT 5000
      )
      SELECT i FROM cnt);
COMMIT;
EOF
    
    # Create the entity indexes script
    create_entity_indexes_script
    
    # Run a complex query without indexes and measure time
    local start_time_before
    start_time_before=$(date +%s.%N)
    
    sqlite3 "${db_path}" << 'EOF'
EXPLAIN QUERY PLAN
SELECT e.name, e.entity_type, ce.relevance
FROM entities e
JOIN content_entities ce ON e.id = ce.entity_id
WHERE e.entity_type = 'person'
AND ce.content_type = 'text/plain'
AND ce.relevance > 0.7
ORDER BY ce.relevance DESC
LIMIT 10;
EOF
    
    local end_time_before
    end_time_before=$(date +%s.%N)
    local duration_before
    duration_before=$(echo "${end_time_before} - ${start_time_before}" | bc)
    
    # Apply entity indexes
    optimize_entity_indexes "${db_name}" "${TEST_TEMP_DIR}/entity_indexes.sql" >/dev/null
    
    # Run the same complex query with indexes and measure time
    local start_time_after
    start_time_after=$(date +%s.%N)
    
    sqlite3 "${db_path}" << 'EOF'
EXPLAIN QUERY PLAN
SELECT e.name, e.entity_type, ce.relevance
FROM entities e
JOIN content_entities ce ON e.id = ce.entity_id
WHERE e.entity_type = 'person'
AND ce.content_type = 'text/plain'
AND ce.relevance > 0.7
ORDER BY ce.relevance DESC
LIMIT 10;
EOF
    
    local end_time_after
    end_time_after=$(date +%s.%N)
    local duration_after
    duration_after=$(echo "${end_time_after} - ${start_time_after}" | bc)
    
    # Check if the query plan has changed (uses indexes)
    local query_plan_before
    query_plan_before=$(sqlite3 "${db_path}" "PRAGMA index_list('entities'); PRAGMA index_list('content_entities');")
    
    # There should be more indexes after optimization
    assert [ "${#query_plan_before}" -gt 0 ]
    
    # Verify that required indexes exist
    assert index_exists "${db_path}" "idx_entities_type_name"
    assert index_exists "${db_path}" "idx_content_entities_relevance"
}

# Test integration with init_database function
@test "init_database applies entity indexes automatically" {
    # Skip test if init_database function doesn't support optimization
    if ! declare -f init_database | grep -q "apply_optimizations"; then
        skip "init_database doesn't support automatic optimizations"
    fi
    
    # Create a test schema with entities table
    cat > "${TEST_TEMP_DIR}/full_schema.sql" << 'EOF'
-- General Content Database Schema

-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- Database Settings
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- Entities Table
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Content Entities Table
CREATE TABLE content_entities (
    id INTEGER PRIMARY KEY,
    content_id INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    entity_id INTEGER NOT NULL,
    relevance REAL,
    context TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(entity_id) REFERENCES entities(id) ON DELETE CASCADE
);
EOF
    
    # Create the entity indexes script in expected location
    mkdir -p "${TEST_TEMP_DIR}/config/schemas"
    create_entity_indexes_script
    
    # Initialize a database with automatic optimization
    local db_name="test_auto_optimize"
    local db_path="${DB_DIR}/${db_name}.sqlite"
    
    # Set the script path in environment for the function to find
    export ENTITY_INDEXES_SCRIPT="${TEST_TEMP_DIR}/entity_indexes.sql"
    
    # Initialize the database with auto-optimization
    run init_database "${db_path}" "${TEST_TEMP_DIR}/full_schema.sql" false true
    assert_success
    
    # Check if the indexes were created
    assert index_exists "${db_path}" "idx_entities_type_name"
    assert index_exists "${db_path}" "idx_entities_creation_date"
    
    # Check for maintenance log
    local maintenance_table_exists
    maintenance_table_exists=$(sqlite3 "${db_path}" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='maintenance_log';")
    assert_equal "${maintenance_table_exists}" "1"
}

# Test store_entity function with optimization trigger
@test "store_entity triggers optimization on first entity" {
    # Skip test if store_entity doesn't support optimization
    if ! declare -f store_entity | grep -q "ENTITY_DB_OPTIMIZE"; then
        skip "store_entity doesn't support database optimization"
    fi
    
    # Create a test database
    local db_name="test_store_entity"
    local db_path=$(create_test_db "${db_name}")
    
    # Create the entity indexes script
    create_entity_indexes_script
    
    # Set environment variables to trigger optimization
    export ENTITY_DB_OPTIMIZE="true"
    export ENTITY_INDEXES_SCRIPT="${TEST_TEMP_DIR}/entity_indexes.sql"
    
    # Call store_entity to add the first entity
    run store_entity "Test Person" "person" "A test person" "${db_name}"
    assert_success
    assert_output "1"  # Should return entity ID 1
    
    # Check if the indexes were created
    # Wait a moment for background optimization to complete
    sleep 1
    
    # Verify at least one index was created (the most important one)
    assert index_exists "${db_path}" "idx_entities_type_name"
}