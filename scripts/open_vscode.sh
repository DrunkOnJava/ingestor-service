#!/bin/bash
set -eo pipefail

# Get the absolute path to the project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Open VS Code in a new window
echo "Opening VS Code workspace at: $PROJECT_ROOT"
code -n "$PROJECT_ROOT"

# Exit with success
exit 0