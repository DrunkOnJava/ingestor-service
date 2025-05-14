#!/bin/bash
# Run the complete test suite for the ingestor-system

set -eo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Print header
echo "====================================================="
echo "Running Ingestor System Test Suite"
echo "====================================================="
echo

# Check for local BATS installation
BATS_EXEC="$SCRIPT_DIR/tests/libs/bats/bin/bats"
if [ ! -x "$BATS_EXEC" ]; then
    echo "ERROR: Local BATS installation not found or not executable."
    echo "Expected at: $BATS_EXEC"
    exit 1
fi

# Set up environment
export TEST_MODE=true
export PROJECT_ROOT="$SCRIPT_DIR"

# Run BATS unit tests
echo "Running BATS unit tests..."
"$BATS_EXEC" "$SCRIPT_DIR/tests/unit/"
BATS_UNIT_RESULT=$?
echo

# Run BATS integration tests
echo "Running BATS integration tests..."
"$BATS_EXEC" "$SCRIPT_DIR/tests/integration/"
BATS_INTEGRATION_RESULT=$?
echo

# Run Jest TypeScript tests
echo "Running TypeScript tests..."
npx jest
JEST_RESULT=$?
echo

# Print summary
echo "====================================================="
echo "Test Summary"
echo "====================================================="
echo "BATS unit tests: $([ $BATS_UNIT_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo "BATS integration tests: $([ $BATS_INTEGRATION_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo "TypeScript tests: $([ $JEST_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo

# Exit with error if any tests failed
if [ $BATS_UNIT_RESULT -ne 0 ] || [ $BATS_INTEGRATION_RESULT -ne 0 ] || [ $JEST_RESULT -ne 0 ]; then
    echo "Some tests failed."
    exit 1
fi

echo "All tests passed successfully."