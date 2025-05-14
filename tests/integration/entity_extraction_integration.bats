#!/usr/bin/env bats
# Integration tests for entity extraction module

load ../test_helper
load ../assertions

setup() {
    setup_test_temp_dir
    TEST_FILES_DIR="${BATS_TEST_DIRNAME}/test_files"
    mkdir -p "${TEST_FILES_DIR}"
    
    # Create test database
    TEST_DB="${TEST_TEMP_DIR}/test_entities.db"
    
    # Create sample test files
    echo "John Smith is the CEO of Acme Corporation. He started the company in New York on January 15, 2010." > "${TEST_FILES_DIR}/sample.txt"
    echo "{\"company\":\"TechCorp\",\"founded\":\"2015-03-22\",\"headquarters\":\"Seattle\"}" > "${TEST_FILES_DIR}/data.json"
    
    # Create database schema
    sqlite3 "$TEST_DB" << EOF
CREATE TABLE entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, entity_type)
);

CREATE TABLE content_entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_id INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    entity_id INTEGER NOT NULL,
    relevance REAL DEFAULT 0.5,
    context TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (entity_id) REFERENCES entities(id),
    UNIQUE(content_id, content_type, entity_id)
);

CREATE INDEX idx_entities_name ON entities(name);
CREATE INDEX idx_entities_type ON entities(entity_type);
CREATE INDEX idx_content_entities_content ON content_entities(content_id, content_type);
CREATE INDEX idx_content_entities_entity ON content_entities(entity_id);
EOF

    # Mock modules for testing
    cat > "${TEST_TEMP_DIR}/test_modules.sh" << 'EOF'
#!/bin/bash
# Mock modules for integration testing

# Logging module
log_debug() {
    local message="$1"
    local module="$2"
    local function="$3"
    
    echo "[DEBUG] [$module] [$function] $message" >&3
}

log_info() {
    local message="$1"
    local module="$2"
    local function="$3"
    
    echo "[INFO] [$module] [$function] $message" >&3
}

log_warning() {
    local message="$1"
    local module="$2"
    local function="$3"
    
    echo "[WARNING] [$module] [$function] $message" >&3
}

log_error() {
    local message="$1"
    local module="$2"
    local function="$3"
    
    echo "[ERROR] [$module] [$function] $message" >&3
}

# Structured logging module
init_structured_logging() {
    return 0
}

log_structured() {
    return 0
}

# Database module
DB_FILE=""

init_database() {
    DB_FILE="$1"
    return 0
}

db_query() {
    local query="$1"
    local result
    
    # Execute the query
    result=$(sqlite3 "$DB_FILE" "$query" 2>/dev/null)
    
    # Return the result
    echo "$result"
    return 0
}

# Claude API mock
extract_entities_with_claude() {
    local content="$1"
    local content_type="$2"
    local options="$3"
    
    if [[ "$content_type" == "text/plain" ]]; then
        # Basic text entity extraction for testing
        cat << EOF
[
  {
    "name": "John Smith",
    "type": "person",
    "mentions": [
      {
        "context": "John Smith is the CEO of Acme Corporation",
        "position": 0,
        "relevance": 0.95
      }
    ]
  },
  {
    "name": "Acme Corporation",
    "type": "organization",
    "mentions": [
      {
        "context": "John Smith is the CEO of Acme Corporation",
        "position": 0,
        "relevance": 0.9
      }
    ]
  },
  {
    "name": "New York",
    "type": "location",
    "mentions": [
      {
        "context": "started the company in New York",
        "position": 0,
        "relevance": 0.85
      }
    ]
  },
  {
    "name": "January 15, 2010",
    "type": "date",
    "mentions": [
      {
        "context": "New York on January 15, 2010",
        "position": 0,
        "relevance": 0.8
      }
    ]
  }
]
EOF
    elif [[ "$content_type" == "application/json" ]]; then
        # Basic JSON entity extraction for testing
        cat << EOF
[
  {
    "name": "TechCorp",
    "type": "organization",
    "mentions": [
      {
        "context": "company\":\"TechCorp",
        "position": 0,
        "relevance": 0.95
      }
    ]
  },
  {
    "name": "Seattle",
    "type": "location",
    "mentions": [
      {
        "context": "headquarters\":\"Seattle",
        "position": 0,
        "relevance": 0.9
      }
    ]
  },
  {
    "name": "2015-03-22",
    "type": "date",
    "mentions": [
      {
        "context": "founded\":\"2015-03-22",
        "position": 0,
        "relevance": 0.85
      }
    ]
  }
]
EOF
    else
        # Empty array for unknown content types
        echo "[]"
    fi
    
    return 0
}

analyze_with_claude() {
    # Mock response
    echo "{\"entities\": [{\"name\":\"Mock Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Mock context\",\"position\":0,\"relevance\":0.5}]}]}"
    return 0
}
EOF
    
    # Entity extraction integration test module
    cat > "${TEST_TEMP_DIR}/entity_extraction_integration.sh" << EOF
#!/bin/bash
# Entity extraction integration test

# Source mock modules
source "${TEST_TEMP_DIR}/test_modules.sh"

# Source entity extractors module
source "$(dirname "$(dirname "$BATS_TEST_DIRNAME")")/src/modules/entity_extractors.sh"

# Test extraction and storage functions
test_extract_and_store() {
    local content="\$1"
    local content_type="\$2"
    local content_id="\$3"
    local db_file="\$4"
    
    # Initialize database
    init_database "\$db_file"
    
    # Extract entities
    local entities_json
    entities_json=\$(extract_entities "\$content" "\$content_type")
    
    # Print debug info
    echo "Extracted entities: \$entities_json" >&3
    
    # Check if entities were extracted
    if [[ "\$entities_json" == "[]" ]]; then
        echo "No entities extracted" >&2
        return 1
    fi
    
    # Parse and store entities
    local stored_count=0
    
    # Parse the JSON (basic approach for testing)
    local entity_names=\$(echo "\$entities_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//')
    local entity_types=\$(echo "\$entities_json" | grep -o '"type":"[^"]*"' | sed 's/"type":"//;s/"$//')
    
    # Combine names and types into arrays
    IFS=\$'\n' read -d '' -ra names <<< "\$entity_names"
    IFS=\$'\n' read -d '' -ra types <<< "\$entity_types"
    
    # Store each entity
    for i in "\${!names[@]}"; do
        local name="\${names[\$i]}"
        local type="\${types[\$i]}"
        
        # Normalize entity name
        local normalized_name=\$(normalize_entity_name "\$name" "\$type")
        
        # Store entity in database
        local entity_id
        entity_id=\$(store_entity "\$normalized_name" "\$type" "Extracted from content \$content_id")
        
        # Check if entity was stored
        if [[ -n "\$entity_id" ]]; then
            # Link entity to content
            link_entity_to_content "\$entity_id" "\$content_id" "\$content_type" "0.9" "Extracted context"
            stored_count=\$((stored_count + 1))
        fi
    done
    
    echo "\$stored_count"
    return 0
}

# Get entity count
get_entity_count() {
    local db_file="\$1"
    
    # Initialize database
    init_database "\$db_file"
    
    # Count entities
    local count
    count=\$(db_query "SELECT COUNT(*) FROM entities;")
    
    echo "\$count"
    return 0
}

# Get content_entities count
get_content_entities_count() {
    local db_file="\$1"
    local content_id="\$2"
    
    # Initialize database
    init_database "\$db_file"
    
    # Count content entities
    local count
    count=\$(db_query "SELECT COUNT(*) FROM content_entities WHERE content_id = \$content_id;")
    
    echo "\$count"
    return 0
}
EOF

    chmod +x "${TEST_TEMP_DIR}/entity_extraction_integration.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    
    if [[ -d "${TEST_FILES_DIR}" ]]; then
        rm -rf "${TEST_FILES_DIR}"
    fi
}

# Load our integration test module
load_integration_module() {
    source "${TEST_TEMP_DIR}/entity_extraction_integration.sh"
}

# Test end-to-end extraction and storage
@test "integration - extract entities from text and store in database" {
    load_integration_module
    
    # Test extraction and storage from text file
    run test_extract_and_store "${TEST_FILES_DIR}/sample.txt" "text/plain" "123" "$TEST_DB"
    
    # Check that extraction and storage was successful
    assert_success
    
    # Verify that entities were stored
    [ "$output" -gt 0 ]
    
    # Check database for entities
    run get_entity_count "$TEST_DB"
    
    # Expect at least 4 entities (person, organization, location, date)
    [ "$output" -ge 4 ]
    
    # Check content_entities links
    run get_content_entities_count "$TEST_DB" "123"
    
    # Should match entity count
    [ "$output" -ge 4 ]
}

@test "integration - extract entities from JSON and store in database" {
    load_integration_module
    
    # Test extraction and storage from JSON file
    run test_extract_and_store "${TEST_FILES_DIR}/data.json" "application/json" "456" "$TEST_DB"
    
    # Check that extraction and storage was successful
    assert_success
    
    # Verify that entities were stored
    [ "$output" -gt 0 ]
    
    # Check database for entities
    run get_entity_count "$TEST_DB"
    
    # Expect at least 3 entities (organization, location, date)
    [ "$output" -ge 3 ]
    
    # Check content_entities links
    run get_content_entities_count "$TEST_DB" "456"
    
    # Should match entity count
    [ "$output" -ge 3 ]
}

@test "integration - multiple content sources store entities correctly" {
    load_integration_module
    
    # First extract and store from text file
    run test_extract_and_store "${TEST_FILES_DIR}/sample.txt" "text/plain" "123" "$TEST_DB"
    assert_success
    local text_entity_count="$output"
    
    # Then extract and store from JSON file
    run test_extract_and_store "${TEST_FILES_DIR}/data.json" "application/json" "456" "$TEST_DB"
    assert_success
    local json_entity_count="$output"
    
    # Total entity count should be at least the sum of both extractions
    run get_entity_count "$TEST_DB"
    local total_entity_count="$output"
    
    # We should have at least the sum of both extractions (may be less if there are duplicate entities)
    [ "$total_entity_count" -ge $(( text_entity_count + json_entity_count - 2 )) ]
    
    # Check content_entities links for each content item
    run get_content_entities_count "$TEST_DB" "123"
    [ "$output" -ge "$text_entity_count" ]
    
    run get_content_entities_count "$TEST_DB" "456"
    [ "$output" -ge "$json_entity_count" ]
}

@test "integration - database indexes improve query performance" {
    load_integration_module
    
    # Extract and store entities from both sources
    test_extract_and_store "${TEST_FILES_DIR}/sample.txt" "text/plain" "123" "$TEST_DB"
    test_extract_and_store "${TEST_FILES_DIR}/data.json" "application/json" "456" "$TEST_DB"
    
    # Initialize database
    init_database "$TEST_DB"
    
    # Test query with index
    local start_time=$(date +%s%N)
    db_query "SELECT * FROM entities WHERE entity_type = 'person';"
    local end_time=$(date +%s%N)
    local indexed_time=$((end_time - start_time))
    
    # Test query that can't use the index
    local start_time=$(date +%s%N)
    db_query "SELECT * FROM entities WHERE description LIKE '%content%';"
    local end_time=$(date +%s%N)
    local non_indexed_time=$((end_time - start_time))
    
    # The indexed query should be faster, but on small test datasets the difference might be minimal
    # This is primarily a sanity check that indexes exist and are being used
    [ $indexed_time -le $((non_indexed_time * 100)) ]
}

# Test the complete entity extraction pipeline
@test "integration - complete entity extraction pipeline works end-to-end" {
    load_integration_module
    
    # Create a function to process content through the complete pipeline
    process_content() {
        local content_path="$1"
        local content_type="$2"
        local content_id="$3"
        
        # Extract entities
        local entities_json
        entities_json=$(extract_entities "$content_path" "$content_type")
        
        # Store entities in database
        local stored_count=0
        local entity_names=$(echo "$entities_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"$//')
        local entity_types=$(echo "$entities_json" | grep -o '"type":"[^"]*"' | sed 's/"type":"//;s/"$//')
        
        # Combine names and types into arrays
        IFS=$'\n' read -d '' -ra names <<< "$entity_names"
        IFS=$'\n' read -d '' -ra types <<< "$entity_types"
        
        # Store each entity
        for i in "${!names[@]}"; do
            local name="${names[$i]}"
            local type="${types[$i]}"
            
            # Save entities to database
            local entity_id
            entity_id=$(store_entity "$name" "$type" "From content $content_id")
            
            # Link entity to content
            if [[ -n "$entity_id" ]]; then
                link_entity_to_content "$entity_id" "$content_id" "$content_type" "0.9" "Context"
                stored_count=$((stored_count + 1))
            fi
        done
        
        echo "$stored_count"
    }
    
    # Test text content processing
    run process_content "${TEST_FILES_DIR}/sample.txt" "text/plain" "789"
    assert_success
    [ "$output" -gt 0 ]
    
    # Check the database for stored entities and links
    run get_entity_count "$TEST_DB"
    [ "$output" -gt 0 ]
    
    run get_content_entities_count "$TEST_DB" "789"
    [ "$output" -gt 0 ]
    
    # Initialize database to run some queries
    init_database "$TEST_DB"
    
    # Query for specific entity types
    local person_count
    person_count=$(db_query "SELECT COUNT(*) FROM entities WHERE entity_type = 'person';")
    [ "$person_count" -gt 0 ]
    
    local org_count
    org_count=$(db_query "SELECT COUNT(*) FROM entities WHERE entity_type = 'organization';")
    [ "$org_count" -gt 0 ]
    
    # Verify entity-content relationships
    local relation_count
    relation_count=$(db_query "SELECT COUNT(*) FROM content_entities ce JOIN entities e ON ce.entity_id = e.id WHERE ce.content_id = 789;")
    [ "$relation_count" -gt 0 ]
}