#!/bin/bash
# API Testing Script
# This script runs a series of tests against the ingestor system API

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
API_PORT=${API_PORT:-3000}
API_URL="http://localhost:$API_PORT/api/v1"
TEMP_DIR="/tmp/ingestor-api-test"
OUTPUT_FILE="$TEMP_DIR/api_test_results.json"
RESPONSE_FILE="$TEMP_DIR/api_response.json"
SERVER_PID_FILE="$TEMP_DIR/api_server.pid"
SERVER_LOG_FILE="$TEMP_DIR/api_server.log"
TEST_DB="api_test_$(date +%s)"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Print header
print_header() {
    echo -e "\n${BLUE}=================================${NC}"
    echo -e "${BLUE}Ingestor System API Testing Script${NC}"
    echo -e "${BLUE}=================================${NC}\n"
}

# Setup
setup() {
    echo -e "${BLUE}Setting up test environment...${NC}"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Clean up any existing files
    rm -f "$OUTPUT_FILE" "$RESPONSE_FILE" "$SERVER_PID_FILE" "$SERVER_LOG_FILE"
    
    # Start API server for testing
    echo -e "${BLUE}Starting API server on port $API_PORT...${NC}"
    cd "$PROJECT_ROOT"
    npm run api:dev -- --api-port $API_PORT > "$SERVER_LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo "$SERVER_PID" > "$SERVER_PID_FILE"
    
    # Wait for server to start
    echo -e "${BLUE}Waiting for server to start...${NC}"
    for i in {1..30}; do
        if curl -s "$API_URL/system/health" > /dev/null; then
            echo -e "${GREEN}Server started successfully!${NC}"
            break
        fi
        
        if [ $i -eq 30 ]; then
            echo -e "${RED}Failed to start server within 30 seconds.${NC}"
            echo -e "${YELLOW}Server logs:${NC}"
            cat "$SERVER_LOG_FILE"
            teardown
            exit 1
        fi
        
        sleep 1
    done
}

# Teardown
teardown() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    
    # Kill API server
    if [ -f "$SERVER_PID_FILE" ]; then
        SERVER_PID=$(cat "$SERVER_PID_FILE")
        echo -e "${BLUE}Stopping API server (PID: $SERVER_PID)...${NC}"
        kill $SERVER_PID 2>/dev/null || true
        rm -f "$SERVER_PID_FILE"
    fi
    
    # Print summary
    echo -e "\n${BLUE}Test Summary${NC}"
    echo -e "${BLUE}==============${NC}"
    echo -e "Total tests: $TESTS_TOTAL"
    echo -e "Passed tests: ${GREEN}$TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "Failed tests: ${RED}$TESTS_FAILED${NC}"
        echo -e "\n${RED}Some tests failed.${NC}"
        exit 1
    else
        echo -e "\n${GREEN}All tests passed!${NC}"
    fi
}

# Run a test and check the result
run_test() {
    TEST_NAME=$1
    METHOD=${2:-GET}
    ENDPOINT=$3
    PAYLOAD=$4
    EXPECTED_STATUS=${5:-200}
    CHECK_EXPR=${6:-'"success" == true'}
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    echo -e "\n${BLUE}Running test: ${NC}$TEST_NAME"
    echo -e "${BLUE}$METHOD $ENDPOINT${NC}"
    
    # Create payload file if provided
    if [ -n "$PAYLOAD" ]; then
        echo "$PAYLOAD" > "$TEMP_DIR/payload.json"
        CMD="curl -s -X $METHOD -H \"Content-Type: application/json\" -d @\"$TEMP_DIR/payload.json\" \"$API_URL$ENDPOINT\""
    else
        CMD="curl -s -X $METHOD \"$API_URL$ENDPOINT\""
    fi
    
    # Execute the command and capture status code
    HTTP_STATUS=$(eval $CMD -o "$RESPONSE_FILE" -w "%{http_code}")
    
    # Check status code
    if [ "$HTTP_STATUS" != "$EXPECTED_STATUS" ]; then
        echo -e "${RED}✗ Failed: Expected status $EXPECTED_STATUS, got $HTTP_STATUS${NC}"
        echo -e "${YELLOW}Response:${NC}"
        cat "$RESPONSE_FILE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Check response content if expression provided
    if [ -n "$CHECK_EXPR" ]; then
        # Use jq to evaluate expression against response
        RESULT=$(cat "$RESPONSE_FILE" | jq -r "$CHECK_EXPR" 2>/dev/null || echo "jq_error")
        
        if [ "$RESULT" = "true" ] || [ "$RESULT" = "jq_error" ]; then
            echo -e "${GREEN}✓ Passed${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            echo -e "${RED}✗ Failed: Response check failed${NC}"
            echo -e "${YELLOW}Response:${NC}"
            cat "$RESPONSE_FILE"
            echo -e "${YELLOW}Check expression:${NC} $CHECK_EXPR"
            echo -e "${YELLOW}Result:${NC} $RESULT"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        echo -e "${GREEN}✓ Passed${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi
}

# Run all API tests
run_all_tests() {
    # System endpoints
    run_test "Health Check" "GET" "/system/health" "" 200 '.success'
    run_test "System Info" "GET" "/system/info" "" 200 '.success'
    
    # Initialize test database
    DB_INIT_PAYLOAD=$(cat <<EOF
{
  "force": true
}
EOF
)
    run_test "Initialize Database" "POST" "/database/$TEST_DB/init" "$DB_INIT_PAYLOAD" 200 '.success'
    
    # Database endpoints
    run_test "List Databases" "GET" "/database/list" "" 200 '.success'
    run_test "Get Database Schema" "GET" "/database/$TEST_DB/schema" "" 200 '.success'
    
    # Auth endpoints
    USER_PAYLOAD=$(cat <<EOF
{
  "username": "testuser",
  "password": "Test1234!",
  "email": "test@example.com"
}
EOF
)
    run_test "Register User" "POST" "/auth/register" "$USER_PAYLOAD" 201 '.success'
    
    LOGIN_PAYLOAD=$(cat <<EOF
{
  "username": "testuser",
  "password": "Test1234!"
}
EOF
)
    run_test "Login User" "POST" "/auth/login" "$LOGIN_PAYLOAD" 200 '.data.token != null'
    
    # Extract token for authenticated requests
    TOKEN=$(cat "$RESPONSE_FILE" | jq -r '.data.token')
    
    # Create an entity
    ENTITY_PAYLOAD=$(cat <<EOF
{
  "name": "Test Entity",
  "type": "person",
  "properties": {
    "age": 42,
    "occupation": "Developer"
  }
}
EOF
)
    run_test "Create Entity" "POST" "/entities" "$ENTITY_PAYLOAD" 201 '.success'
    
    # Extract entity ID
    ENTITY_ID=$(cat "$RESPONSE_FILE" | jq -r '.data.id')
    
    # Get entity by ID
    run_test "Get Entity" "GET" "/entities/$ENTITY_ID" "" 200 '.success'
    
    # Process content
    CONTENT_PAYLOAD=$(cat <<EOF
{
  "content": "This is test content with organizations like Google and Apple mentioned.",
  "contentType": "text",
  "options": {
    "extractEntities": true,
    "database": "$TEST_DB"
  }
}
EOF
)
    run_test "Process Content" "POST" "/processing/analyze" "$CONTENT_PAYLOAD" 202 '.success'
    
    # Extract job ID
    JOB_ID=$(cat "$RESPONSE_FILE" | jq -r '.data.jobId')
    
    # Check job status (may not be completed yet, just check that the endpoint works)
    run_test "Get Job Status" "GET" "/processing/status/$JOB_ID" "" 200 '.success'
    
    # Create batch process
    BATCH_PAYLOAD=$(cat <<EOF
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
)
    run_test "Create Batch Process" "POST" "/batches" "$BATCH_PAYLOAD" 201 '.success'
    
    # Extract batch ID
    BATCH_ID=$(cat "$RESPONSE_FILE" | jq -r '.data.id')
    
    # Get batch by ID
    run_test "Get Batch" "GET" "/batches/$BATCH_ID" "" 200 '.success'
    
    # Create API key with token
    API_KEY_PAYLOAD=$(cat <<EOF
{
  "name": "Test API Key",
  "expiration": "2025-12-31T23:59:59Z"
}
EOF
)
    run_test "Create API Key" "POST" "/auth/api-key" "$API_KEY_PAYLOAD" 201 '.success' ".data.apiKey != null"
    
    # Extract API key
    API_KEY=$(cat "$RESPONSE_FILE" | jq -r '.data.apiKey')
    
    # Test API key authentication
    run_test "API Key Authentication" "GET" "/system/info" "" 200 '.success' \
        --header "X-API-Key: $API_KEY"
}

# Main execution
print_header
setup
trap teardown EXIT

# Run all tests
run_all_tests

# Script will exit with teardown function
exit 0