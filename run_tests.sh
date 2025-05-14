#!/bin/bash
# Run the complete test suite for the ingestor-system

set -eo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Print header
echo "====================================================="
echo "Running Ingestor System Test Suite"
echo "====================================================="
echo

# Check for required tools
if ! command -v bats &> /dev/null; then
    echo "ERROR: bats test framework not found. Please install it to run tests."
    echo "  Installation: https://github.com/bats-core/bats-core#installation"
    exit 1
fi

# Set up environment
export TEST_MODE=true
export PROJECT_ROOT="$SCRIPT_DIR"

# Run unit tests
echo "Running unit tests..."
bats "$SCRIPT_DIR/tests/unit/"
UNIT_RESULT=$?
echo

# Run integration tests
echo "Running integration tests..."
bats "$SCRIPT_DIR/tests/integration/"
INTEGRATION_RESULT=$?
echo

# Print summary
echo "====================================================="
echo "Test Summary"
echo "====================================================="
echo "Unit tests: $([ $UNIT_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo "Integration tests: $([ $INTEGRATION_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo

# Exit with error if any tests failed
if [ $UNIT_RESULT -ne 0 ] || [ $INTEGRATION_RESULT -ne 0 ]; then
    echo "Some tests failed."
    exit 1
fi

echo "All tests passed successfully."