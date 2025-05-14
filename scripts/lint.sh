#!/bin/bash
# Lint shell scripts using shellcheck

set -euo pipefail

# Determine the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

# Check if shellcheck is installed
check_shellcheck() {
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck not found. Please install it first:"
        echo "  On macOS: brew install shellcheck"
        echo "  On Ubuntu: apt-get install shellcheck"
        echo "  On other systems: https://github.com/koalaman/shellcheck#installing"
        exit 1
    fi
}

# Find all shell scripts in the project
find_shell_scripts() {
    local search_path="${1:-$PROJECT_ROOT}"
    
    # Find all shell scripts
    find "$search_path" -type f \( -name "*.sh" -o -name "*.bash" -o -path "*/src/ingestor" \) | \
        grep -v "node_modules" | \
        grep -v "vendor" | \
        sort
}

# Lint a specific file
lint_file() {
    local file="$1"
    local severity="${2:-style}"
    
    echo "Linting: $file"
    shellcheck --severity="$severity" "$file" || return 1
}

# Lint all shell scripts
lint_all() {
    local severity="${1:-style}"
    local exit_code=0
    local files
    
    files=$(find_shell_scripts)
    
    echo "Linting all shell scripts with severity: $severity"
    echo
    
    # Loop through each file and lint it
    while IFS= read -r file; do
        if ! lint_file "$file" "$severity"; then
            exit_code=1
        fi
    done <<< "$files"
    
    if [[ $exit_code -eq 0 ]]; then
        echo "All files passed shellcheck!"
    else
        echo "Some files failed shellcheck. Please fix the issues."
    fi
    
    return $exit_code
}

# Fix shell scripts automatically where possible
fix_scripts() {
    local files
    files=$(find_shell_scripts)
    
    echo "Attempting to automatically fix shell scripts..."
    echo
    
    while IFS= read -r file; do
        echo "Fixing: $file"
        shellcheck -f diff "$file" | patch -p1 "$file" || true
    done <<< "$files"
    
    echo "Automatic fixing completed. Some issues may still require manual fixes."
}

# Display help
show_help() {
    echo "Usage: $0 [options] [file]"
    echo
    echo "Options:"
    echo "  -h, --help               Show this help message"
    echo "  -a, --all                Lint all shell scripts (default)"
    echo "  -f, --fix                Attempt to fix issues automatically"
    echo "  -s, --severity SEVERITY  Set severity level (style, info, warning, error)"
    echo
    echo "Examples:"
    echo "  $0                        # Lint all shell scripts with default severity"
    echo "  $0 src/modules/keychain.sh # Lint a specific file"
    echo "  $0 --severity error        # Only report errors"
    echo "  $0 --fix                   # Try to fix issues automatically"
}

# Parse command line arguments
parse_args() {
    local mode="all"
    local severity="style"
    local file=""
    local fix=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                mode="all"
                shift
                ;;
            -s|--severity)
                if [[ -n "${2:-}" ]]; then
                    severity="$2"
                    shift 2
                else
                    echo "Error: --severity requires an argument"
                    exit 1
                fi
                ;;
            -f|--fix)
                fix=1
                shift
                ;;
            *)
                # If it's not an option, it's a file
                file="$1"
                mode="file"
                shift
                ;;
        esac
    done
    
    # Check if fix mode is enabled
    if [[ $fix -eq 1 ]]; then
        fix_scripts
        exit 0
    fi
    
    # Run the appropriate lint mode
    case "$mode" in
        all)
            lint_all "$severity"
            ;;
        file)
            if [[ -f "$file" ]]; then
                lint_file "$file" "$severity"
            else
                echo "Error: File not found: $file"
                exit 1
            fi
            ;;
    esac
}

# Main function
main() {
    # Check if shellcheck is installed
    check_shellcheck
    
    # Parse command line arguments
    parse_args "$@"
}

# Run the main function
main "$@"