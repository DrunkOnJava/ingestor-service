#!/bin/bash
set -eo pipefail

# Script to install testing dependencies for ingestor-system
# Main dependency: Bash Automated Testing System (BATS)

# Current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$PROJECT_ROOT/tests"
BATS_DIR="$TESTS_DIR/libs/bats"

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Installing Testing Dependencies                  ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create directories
mkdir -p "$TESTS_DIR/libs"

# Check if BATS is already installed
if [ -d "$BATS_DIR" ]; then
    echo -e "${YELLOW}BATS is already installed at $BATS_DIR${RESET}"
    echo -e "${YELLOW}Updating BATS...${RESET}"
    
    # Pull latest changes
    cd "$BATS_DIR"
    if command_exists git; then
        git pull
    else
        echo -e "${YELLOW}Git not found. Skipping BATS update.${RESET}"
    fi
else
    echo -e "${YELLOW}Installing BATS...${RESET}"
    
    # Check if git is installed
    if ! command_exists git; then
        echo -e "${RED}Error: Git is required to install BATS.${RESET}"
        echo -e "${YELLOW}Please install git and run this script again.${RESET}"
        exit 1
    fi
    
    # Clone the BATS repository
    git clone https://github.com/bats-core/bats-core.git "$BATS_DIR"
    
    if [ ! -d "$BATS_DIR" ]; then
        echo -e "${RED}Error: Failed to clone BATS repository.${RESET}"
        exit 1
    fi
fi

# Install BATS helper libraries
BATS_SUPPORT_DIR="$TESTS_DIR/libs/bats-support"
BATS_ASSERT_DIR="$TESTS_DIR/libs/bats-assert"
BATS_FILE_DIR="$TESTS_DIR/libs/bats-file"

# Install bats-support
if [ ! -d "$BATS_SUPPORT_DIR" ]; then
    echo -e "${YELLOW}Installing bats-support...${RESET}"
    git clone https://github.com/bats-core/bats-support.git "$BATS_SUPPORT_DIR"
else
    echo -e "${YELLOW}bats-support is already installed${RESET}"
fi

# Install bats-assert
if [ ! -d "$BATS_ASSERT_DIR" ]; then
    echo -e "${YELLOW}Installing bats-assert...${RESET}"
    git clone https://github.com/bats-core/bats-assert.git "$BATS_ASSERT_DIR"
else
    echo -e "${YELLOW}bats-assert is already installed${RESET}"
fi

# Install bats-file
if [ ! -d "$BATS_FILE_DIR" ]; then
    echo -e "${YELLOW}Installing bats-file...${RESET}"
    git clone https://github.com/bats-core/bats-file.git "$BATS_FILE_DIR"
else
    echo -e "${YELLOW}bats-file is already installed${RESET}"
fi

# Create test fixtures directory
mkdir -p "$TESTS_DIR/fixtures"

# Create test helper module
HELPER_FILE="$TESTS_DIR/test_helper.bash"
if [ ! -f "$HELPER_FILE" ]; then
    echo -e "${YELLOW}Creating test helper module...${RESET}"
    
    cat > "$HELPER_FILE" << 'EOF'
#!/usr/bin/env bash
# Test helper functions for ingestor-system tests

# Determine project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load BATS libraries
load "libs/bats-support/load"
load "libs/bats-assert/load"
load "libs/bats-file/load"

# Create test environment
setup_test_environment() {
    # Create temporary directory for the test
    TEST_TEMP_DIR="$(mktemp -d)"
    
    # Set up test-specific environment variables
    export INGESTOR_TEST_MODE="true"
    export INGESTOR_HOME="${TEST_TEMP_DIR}/.ingestor"
    export INGESTOR_TEST_FIXTURES="${PROJECT_ROOT}/tests/fixtures"
    
    # Create necessary directories
    mkdir -p "${INGESTOR_HOME}/config"
    mkdir -p "${INGESTOR_HOME}/databases"
    mkdir -p "${INGESTOR_HOME}/logs"
    mkdir -p "${INGESTOR_HOME}/tmp"
}

# Clean up test environment
teardown_test_environment() {
    # Clean up temporary directory
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    
    # Unset test-specific environment variables
    unset INGESTOR_TEST_MODE
    unset INGESTOR_HOME
    unset INGESTOR_TEST_FIXTURES
}

# Setup to run before each test
setup() {
    setup_test_environment
}

# Teardown to run after each test
teardown() {
    teardown_test_environment
}

# Mocking helper functions
mock_function() {
    local function_name="$1"
    local output="$2"
    local exit_code="${3:-0}"
    
    eval "${function_name}() { echo \"$output\"; return $exit_code; }"
    export -f "$function_name"
}

# Create a test configuration file
create_test_config() {
    cat > "${INGESTOR_HOME}/config/settings.yml" << EOF
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
}

# Create test database
create_test_database() {
    local db_name="${1:-test_db}"
    local schema_file="${2:-${PROJECT_ROOT}/config/schemas/general.sql}"
    
    # Check if schema file exists
    if [ ! -f "$schema_file" ]; then
        echo "Schema file not found: $schema_file" >&2
        return 1
    fi
    
    # Create database path
    local db_path="${INGESTOR_HOME}/databases/${db_name}.sqlite"
    
    # Create database with schema
    sqlite3 "$db_path" < "$schema_file"
    
    # Check if database was created
    if [ ! -f "$db_path" ]; then
        echo "Failed to create database: $db_path" >&2
        return 1
    fi
    
    echo "$db_path"
}

# Helper to source a module for testing (with optional mocks)
source_module() {
    local module_path="$1"
    
    # Set TEST_MODE environment variable
    export TEST_MODE="true"
    
    # Source the module
    source "$module_path"
}
EOF
    
    echo -e "${GREEN}Created test helper module at $HELPER_FILE${RESET}"
else
    echo -e "${YELLOW}Test helper module already exists at $HELPER_FILE${RESET}"
fi

# Create run_tests.sh script
RUN_TESTS_SCRIPT="$PROJECT_ROOT/scripts/run_tests.sh"
if [ ! -f "$RUN_TESTS_SCRIPT" ]; then
    echo -e "${YELLOW}Creating run_tests.sh script...${RESET}"
    
    cat > "$RUN_TESTS_SCRIPT" << 'EOF'
#!/bin/bash
set -eo pipefail

# Script to run tests for ingestor-system

# Current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$PROJECT_ROOT/tests"
BATS_BIN="$TESTS_DIR/libs/bats/bin/bats"

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Running Tests for Ingestor System                ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Check if BATS is installed
if [ ! -f "$BATS_BIN" ]; then
    echo -e "${YELLOW}BATS not found. Installing dependencies...${RESET}"
    "$SCRIPT_DIR/install_test_deps.sh"
fi

# Parse command line arguments
TEST_PATH="$TESTS_DIR"
TEST_PATTERN="*.bats"
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit)
            TEST_PATH="$TESTS_DIR/unit"
            shift
            ;;
        --integration)
            TEST_PATH="$TESTS_DIR/integration"
            shift
            ;;
        --module)
            if [[ -n "$2" && "$2" != --* ]]; then
                TEST_PATTERN="*${2}*.bats"
                shift 2
            else
                echo -e "${RED}Error: --module requires a module name${RESET}"
                exit 1
            fi
            ;;
        --verbose|-v)
            VERBOSE="--verbose"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --unit              Run only unit tests"
            echo "  --integration       Run only integration tests"
            echo "  --module NAME       Run tests for a specific module"
            echo "  --verbose, -v       Run tests in verbose mode"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${RESET}"
            exit 1
            ;;
    esac
done

# Run the tests
echo -e "${YELLOW}Running tests in $TEST_PATH with pattern $TEST_PATTERN${RESET}"
"$BATS_BIN" $VERBOSE "$TEST_PATH/$TEST_PATTERN"

echo -e "${GREEN}All tests completed successfully!${RESET}"
EOF
    
    # Make the script executable
    chmod +x "$RUN_TESTS_SCRIPT"
    
    echo -e "${GREEN}Created run_tests.sh script at $RUN_TESTS_SCRIPT${RESET}"
else
    echo -e "${YELLOW}run_tests.sh script already exists at $RUN_TESTS_SCRIPT${RESET}"
fi

# Create lint.sh script
LINT_SCRIPT="$PROJECT_ROOT/scripts/lint.sh"
if [ ! -f "$LINT_SCRIPT" ]; then
    echo -e "${YELLOW}Creating lint.sh script...${RESET}"
    
    cat > "$LINT_SCRIPT" << 'EOF'
#!/bin/bash
set -eo pipefail

# Script to lint shell scripts in ingestor-system

# Current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Linting Scripts for Ingestor System              ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}Error: shellcheck is not installed.${RESET}"
    echo -e "${YELLOW}Please install shellcheck and run this script again.${RESET}"
    echo -e "${YELLOW}On macOS, you can install it with: brew install shellcheck${RESET}"
    echo -e "${YELLOW}On Ubuntu, you can install it with: sudo apt-get install shellcheck${RESET}"
    exit 1
fi

# Parse command line arguments
LINT_PATH="$PROJECT_ROOT"
LINT_PATTERN="*.sh"
LINT_RECURSIVE=true
LINT_FIX=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)
            if [[ -n "$2" && "$2" != --* ]]; then
                LINT_PATH="$2"
                shift 2
            else
                echo -e "${RED}Error: --path requires a directory path${RESET}"
                exit 1
            fi
            ;;
        --pattern)
            if [[ -n "$2" && "$2" != --* ]]; then
                LINT_PATTERN="$2"
                shift 2
            else
                echo -e "${RED}Error: --pattern requires a glob pattern${RESET}"
                exit 1
            fi
            ;;
        --no-recursive)
            LINT_RECURSIVE=false
            shift
            ;;
        --fix)
            LINT_FIX=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --path PATH         Specify the directory to lint (default: project root)"
            echo "  --pattern PATTERN   Specify the file pattern to lint (default: *.sh)"
            echo "  --no-recursive      Do not search directories recursively"
            echo "  --fix               Attempt to automatically fix some issues"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${RESET}"
            exit 1
            ;;
    esac
done

# Find shell scripts to lint
if [ "$LINT_RECURSIVE" = true ]; then
    FIND_COMMAND="find \"$LINT_PATH\" -type f -name \"$LINT_PATTERN\""
else
    FIND_COMMAND="find \"$LINT_PATH\" -maxdepth 1 -type f -name \"$LINT_PATTERN\""
fi

# Execute find command and get the list of files
FILES_TO_LINT=$(eval "$FIND_COMMAND")

# Check if any files were found
if [ -z "$FILES_TO_LINT" ]; then
    echo -e "${YELLOW}No files matching pattern $LINT_PATTERN found in $LINT_PATH${RESET}"
    exit 0
fi

# Count files to lint
FILE_COUNT=$(echo "$FILES_TO_LINT" | wc -l)
echo -e "${YELLOW}Linting $FILE_COUNT shell scripts...${RESET}"

# Initialize counters
ERROR_COUNT=0
FIXED_COUNT=0

# Lint each file
for FILE in $FILES_TO_LINT; do
    echo -e "Linting ${FILE}..."
    
    # Use shellcheck to check the file
    if [ "$LINT_FIX" = true ]; then
        # Use a temporary file for fixes
        TMPFILE=$(mktemp)
        
        # Try to fix the file
        shellcheck "$FILE" --format=diff > "$TMPFILE" 2>/dev/null
        
        # Apply fixes if any were generated
        if [ -s "$TMPFILE" ]; then
            patch "$FILE" "$TMPFILE"
            FIXED_COUNT=$((FIXED_COUNT + 1))
            echo -e "${GREEN}Fixed issues in $FILE${RESET}"
        fi
        
        # Clean up temporary file
        rm -f "$TMPFILE"
    fi
    
    # Check the file (even if fixed)
    if ! shellcheck "$FILE"; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
        echo -e "${RED}Issues found in $FILE${RESET}"
    fi
done

# Display summary
echo
if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}All $FILE_COUNT shell scripts passed linting!${RESET}"
    if [ "$LINT_FIX" = true ] && [ $FIXED_COUNT -gt 0 ]; then
        echo -e "${GREEN}Fixed issues in $FIXED_COUNT files.${RESET}"
    fi
else
    echo -e "${RED}Issues found in $ERROR_COUNT of $FILE_COUNT shell scripts.${RESET}"
    if [ "$LINT_FIX" = true ]; then
        echo -e "${YELLOW}Fixed some issues in $FIXED_COUNT files.${RESET}"
        echo -e "${YELLOW}Run again with --fix to attempt to fix remaining issues.${RESET}"
    else
        echo -e "${YELLOW}Run with --fix to attempt to fix some issues automatically.${RESET}"
    fi
    exit 1
fi
EOF
    
    # Make the script executable
    chmod +x "$LINT_SCRIPT"
    
    echo -e "${GREEN}Created lint.sh script at $LINT_SCRIPT${RESET}"
else
    echo -e "${YELLOW}lint.sh script already exists at $LINT_SCRIPT${RESET}"
fi

echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   All testing dependencies installed!               ${RESET}"
echo -e "${GREEN}====================================================${RESET}"
echo
echo -e "${YELLOW}To run tests:${RESET}"
echo -e "  ${GREEN}$PROJECT_ROOT/scripts/run_tests.sh${RESET}"
echo
echo -e "${YELLOW}To lint shell scripts:${RESET}"
echo -e "  ${GREEN}$PROJECT_ROOT/scripts/lint.sh${RESET}"
echo