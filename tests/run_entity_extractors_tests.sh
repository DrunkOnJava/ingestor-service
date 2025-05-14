#!/bin/bash
# Run entity extractors tests

set -e

# Get the project root directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run the entity extractors tests
cd "$ROOT_DIR"
./scripts/run_tests.sh entity_extractors