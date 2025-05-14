#!/bin/bash
# Test runner script for ingestor-system

set -euo pipefail

# Determine the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

# Check if BATS is installed
check_bats() {
    # First check if bats is installed in tests/libs/bats/bin
    if [[ -x "${PROJECT_ROOT}/tests/libs/bats/bin/bats" ]]; then
        export PATH="${PROJECT_ROOT}/tests/libs/bats/bin:$PATH"
        return 0
    fi
    
    # Then check if it's available on the system path
    if ! command -v bats &> /dev/null; then
        echo "BATS testing framework not found."
        echo "Please run ./scripts/install_test_deps.sh to install it."
        exit 1
    fi
}

# Run all tests or specific tests
run_tests() {
    local test_path="${1:-$PROJECT_ROOT/tests}"
    
    echo "Running tests in $test_path..."
    
    # Run BATS tests
    bats "$test_path"
}

# Run a specific test module
run_module_tests() {
    local module_name="$1"
    local test_path="$PROJECT_ROOT/tests/unit/${module_name}.bats"
    
    if [[ -f "$test_path" ]]; then
        echo "Running tests for $module_name module..."
        bats "$test_path"
    else
        echo "Test file not found: $test_path"
        echo "Available test modules:"
        find "$PROJECT_ROOT/tests/unit" -name "*.bats" -exec basename {} .bats \; | sort
        exit 1
    fi
}

# Display help
show_help() {
    echo "Usage: $0 [options] [module]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -a, --all      Run all tests (default)"
    echo "  -u, --unit     Run only unit tests"
    echo "  -i, --int      Run only integration tests"
    echo "  -v, --verbose  Increase verbosity"
    echo
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 keychain           # Run only keychain module tests"
    echo "  $0 --unit             # Run all unit tests"
    echo "  $0 --int              # Run all integration tests"
    echo "  $0 --verbose keychain # Run keychain tests with verbose output"
}

# Parse command line arguments
parse_args() {
    local test_type="all"
    local verbose=0
    local module_name=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                test_type="all"
                shift
                ;;
            -u|--unit)
                test_type="unit"
                shift
                ;;
            -i|--int)
                test_type="integration"
                shift
                ;;
            -v|--verbose)
                verbose=1
                shift
                ;;
            *)
                # If it's not an option, it's a module name
                module_name="$1"
                shift
                ;;
        esac
    done
    
    # Set verbosity
    if [[ $verbose -eq 1 ]]; then
        export TEST_VERBOSE=1
    fi
    
    # Determine what to run
    if [[ -n "$module_name" ]]; then
        run_module_tests "$module_name"
    else
        case "$test_type" in
            all)
                run_tests "$PROJECT_ROOT/tests"
                ;;
            unit)
                run_tests "$PROJECT_ROOT/tests/unit"
                ;;
            integration)
                if [[ -d "$PROJECT_ROOT/tests/integration" ]]; then
                    run_tests "$PROJECT_ROOT/tests/integration"
                else
                    echo "No integration tests found."
                    exit 1
                fi
                ;;
        esac
    fi
}

# Main function
main() {
    # Check if BATS is installed
    check_bats
    
    # Parse command line arguments
    parse_args "$@"
}

# Run the main function
main "$@"