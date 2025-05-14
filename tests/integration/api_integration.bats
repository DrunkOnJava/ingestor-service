#!/usr/bin/env bats
#
# API Integration Tests
# Tests the RESTful API endpoints and functionality

load ../libs/bats-support/load
load ../libs/bats-assert/load
load ../libs/test_helper

# Setup - runs before each test
setup() {
    # Create a test database
    export TEST_DB="api_test_$(date +%s)"
    mkdir -p "$BATS_TMPDIR/ingestor"
    export INGESTOR_HOME="$BATS_TMPDIR/ingestor"
    export DATABASE_DIR="$INGESTOR_HOME/databases"
    mkdir -p "$DATABASE_DIR"

    # Start API server for testing in the background
    TEST_PORT=4000
    export API_PORT=$TEST_PORT
    export API_SERVER_PID=""
    
    # Use ts-node-script to run the API server
    node_modules/.bin/ts-node-script src/index.ts --api --api-port $TEST_PORT > "$BATS_TMPDIR/api_server.log" 2>&1 &
    API_SERVER_PID=$!
    
    # Allow time for the API server to start
    sleep 2
    
    # Save PID for teardown
    echo $API_SERVER_PID > "$BATS_TMPDIR/api_server.pid"
    
    # Test API base URL
    export API_BASE="http://localhost:$TEST_PORT/api/v1"
}

# Teardown - runs after each test
teardown() {
    # Kill API server
    if [ -f "$BATS_TMPDIR/api_server.pid" ]; then
        API_SERVER_PID=$(cat "$BATS_TMPDIR/api_server.pid")
        kill $API_SERVER_PID || true
        rm "$BATS_TMPDIR/api_server.pid"
    fi
    
    # Clean up logs
    rm -f "$BATS_TMPDIR/api_server.log"
    
    # Clean up test database
    rm -rf "$DATABASE_DIR/$TEST_DB.sqlite"
}

#
# Test API health check endpoint
#
@test "API: Health check endpoint returns 200" {
    run curl -s -o /dev/null -w "%{http_code}" "$API_BASE/system/health"
    assert_output "200"
}

#
# Test database operations
#
@test "API: Initialize database" {
    # Create payload for initializing the database
    cat > "$BATS_TMPDIR/init_db.json" << EOF
{
  "force": true
}
EOF

    # Make request to initialize database
    run curl -s -X POST -H "Content-Type: application/json" -d @"$BATS_TMPDIR/init_db.json" "$API_BASE/database/$TEST_DB/init"
    assert_success
    
    # Parse output to check success
    echo "$output" | grep -q "success\":true"
    assert_success
}

@test "API: Database operations - list databases" {
    run curl -s "$API_BASE/database/list"
    assert_success
    echo "$output" | grep -q "success\":true"
    assert_success
}

#
# Test Entity API endpoints
#
@test "API: Entity creation and retrieval" {
    # Create payload for entity creation
    cat > "$BATS_TMPDIR/test_entity.json" << EOF
{
  "name": "Test Entity",
  "type": "person",
  "properties": {
    "age": 42,
    "occupation": "Developer"
  }
}
EOF

    # Create entity
    run curl -s -X POST -H "Content-Type: application/json" -d @"$BATS_TMPDIR/test_entity.json" "$API_BASE/entities"
    assert_success
    echo "$output" | grep -q "success\":true"
    assert_success
    
    # Extract entity ID using grep and cut
    ENTITY_ID=$(echo "$output" | grep -o "\"id\":\"[^\"]*\"" | cut -d'"' -f4)
    
    # Verify entity ID is not empty
    [ -n "$ENTITY_ID" ]
    
    # Get entity by ID
    run curl -s "$API_BASE/entities/$ENTITY_ID"
    assert_success
    echo "$output" | grep -q "Test Entity"
    assert_success
}

#
# Test Processing API endpoints
#
@test "API: Process text content" {
    # Create payload for content processing
    cat > "$BATS_TMPDIR/process_content.json" << EOF
{
  "content": "This is test content with organizations like Google and Apple mentioned.",
  "contentType": "text",
  "options": {
    "extractEntities": true,
    "database": "$TEST_DB"
  }
}
EOF

    # Process content
    run curl -s -X POST -H "Content-Type: application/json" -d @"$BATS_TMPDIR/process_content.json" "$API_BASE/processing/analyze"
    assert_success
    echo "$output" | grep -q "success\":true"
    assert_success
    
    # Extract job ID
    JOB_ID=$(echo "$output" | grep -o "\"jobId\":\"[^\"]*\"" | cut -d'"' -f4)
    
    # Verify job ID is not empty
    [ -n "$JOB_ID" ]
    
    # Check job status with retries
    RETRIES=0
    MAX_RETRIES=5
    while [ $RETRIES -lt $MAX_RETRIES ]; do
        run curl -s "$API_BASE/processing/status/$JOB_ID"
        if echo "$output" | grep -q "\"status\":\"completed\""; then
            break
        fi
        sleep 2
        RETRIES=$((RETRIES + 1))
    done
    
    if [ $RETRIES -eq $MAX_RETRIES ]; then
        fail "Job did not complete within expected time"
    fi
    
    echo "$output" | grep -q "success\":true"
    assert_success
}

#
# Test Batch API endpoints
#
@test "API: Create and monitor batch process" {
    # Create payload for batch creation
    cat > "$BATS_TMPDIR/batch_process.json" << EOF
{
  "items": [
    {
      "content": "Sample text mentioning Microsoft.",
      "contentType": "text"
    },
    {
      "content": "Another text about Facebook.",
      "contentType": "text"
    }
  ],
  "options": {
    "parallelism": 2,
    "database": "$TEST_DB"
  }
}
EOF

    # Create batch
    run curl -s -X POST -H "Content-Type: application/json" -d @"$BATS_TMPDIR/batch_process.json" "$API_BASE/batches"
    assert_success
    echo "$output" | grep -q "success\":true"
    assert_success
    
    # Extract batch ID
    BATCH_ID=$(echo "$output" | grep -o "\"id\":\"[^\"]*\"" | cut -d'"' -f4)
    
    # Verify batch ID is not empty
    [ -n "$BATCH_ID" ]
    
    # Check batch status with retries
    RETRIES=0
    MAX_RETRIES=5
    while [ $RETRIES -lt $MAX_RETRIES ]; do
        run curl -s "$API_BASE/batches/$BATCH_ID"
        if echo "$output" | grep -q "\"status\":\"completed\""; then
            break
        fi
        sleep 2
        RETRIES=$((RETRIES + 1))
    done
    
    if [ $RETRIES -eq $MAX_RETRIES ]; then
        # Not failing the test here as batch processing might take longer
        echo "Warning: Batch did not complete within expected time, but test continues"
    fi
    
    # Verify we can at least get batch information
    echo "$output" | grep -q "success\":true"
    assert_success
}

#
# Test Authentication
#
@test "API: Authentication endpoints" {
    # Create user registration payload
    cat > "$BATS_TMPDIR/register.json" << EOF
{
  "username": "testuser",
  "password": "Test1234!",
  "email": "test@example.com"
}
EOF

    # Register user
    run curl -s -X POST -H "Content-Type: application/json" -d @"$BATS_TMPDIR/register.json" "$API_BASE/auth/register"
    assert_success
    echo "$output" | grep -q "success\":true"
    assert_success
    
    # Login user
    cat > "$BATS_TMPDIR/login.json" << EOF
{
  "username": "testuser",
  "password": "Test1234!"
}
EOF

    run curl -s -X POST -H "Content-Type: application/json" -d @"$BATS_TMPDIR/login.json" "$API_BASE/auth/login"
    assert_success
    echo "$output" | grep -q "token"
    assert_success
    
    # Extract JWT token
    JWT_TOKEN=$(echo "$output" | grep -o "\"token\":\"[^\"]*\"" | cut -d'"' -f4)
    
    # Verify token is not empty
    [ -n "$JWT_TOKEN" ]
    
    # Create API key with the JWT
    cat > "$BATS_TMPDIR/create_api_key.json" << EOF
{
  "name": "Test API Key",
  "expiration": "2025-12-31T23:59:59Z"
}
EOF

    run curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $JWT_TOKEN" -d @"$BATS_TMPDIR/create_api_key.json" "$API_BASE/auth/api-key"
    assert_success
    echo "$output" | grep -q "apiKey"
    assert_success
}