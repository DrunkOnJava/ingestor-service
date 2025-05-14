#!/bin/bash
# Script to create a new versioned release

set -euo pipefail

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Determine the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Ingestor System - Release Management             ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Parse arguments
VERSION=""
TYPE="patch"
MESSAGE=""

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -v, --version VERSION   Specify version (e.g., 1.0.0)"
    echo "  -t, --type TYPE         Specify version type (patch, minor, major)"
    echo "  -m, --message MESSAGE   Release message"
    echo "  -h, --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --version 1.0.0 --message \"First stable release\""
    echo "  $0 --type minor --message \"New feature release\""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                VERSION="$2"
                shift 2
            else
                echo -e "${RED}Error: --version requires a version number${RESET}"
                exit 1
            fi
            ;;
        -t|--type)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                TYPE="$2"
                shift 2
            else
                echo -e "${RED}Error: --type requires an argument (patch, minor, major)${RESET}"
                exit 1
            fi
            ;;
        -m|--message)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                MESSAGE="$2"
                shift 2
            else
                echo -e "${RED}Error: --message requires a message${RESET}"
                exit 1
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${RESET}"
            show_help
            exit 1
            ;;
    esac
done

# Check if jq is installed for package.json manipulation
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required for this script.${RESET}"
    echo -e "${YELLOW}Please install jq:${RESET}"
    echo -e "  - On macOS: brew install jq"
    echo -e "  - On Ubuntu: apt-get install jq"
    exit 1
fi

# Get current version from package.json
CURRENT_VERSION=$(jq -r '.version' package.json)
echo -e "${YELLOW}Current version: ${CURRENT_VERSION}${RESET}"

# Determine new version
if [[ -z "$VERSION" ]]; then
    # Split the version string into components
    IFS='.' read -r -a version_parts <<< "$CURRENT_VERSION"
    MAJOR="${version_parts[0]}"
    MINOR="${version_parts[1]}"
    PATCH="${version_parts[2]}"

    case "$TYPE" in
        patch)
            PATCH=$((PATCH + 1))
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        *)
            echo -e "${RED}Error: Invalid version type. Use patch, minor, or major.${RESET}"
            exit 1
            ;;
    esac

    VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

echo -e "${YELLOW}New version will be: ${VERSION}${RESET}"

# If no message is provided, prompt for one
if [[ -z "$MESSAGE" ]]; then
    echo -e "${YELLOW}Enter release message:${RESET}"
    read -r MESSAGE
    
    if [[ -z "$MESSAGE" ]]; then
        echo -e "${RED}Error: Release message cannot be empty.${RESET}"
        exit 1
    fi
fi

# Confirm the release
echo -e "${YELLOW}Ready to create release v${VERSION} with message: \"${MESSAGE}\"${RESET}"
echo -e "${YELLOW}Continue? [y/N]${RESET}"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Release cancelled.${RESET}"
    exit 0
fi

echo -e "${YELLOW}Creating release...${RESET}"

# Update version in package.json
echo -e "${YELLOW}Updating version in package.json...${RESET}"
jq ".version = \"$VERSION\"" package.json > package.json.tmp && mv package.json.tmp package.json

# Make sure tests pass
echo -e "${YELLOW}Running tests...${RESET}"
./scripts/run_tests.sh || {
    echo -e "${RED}Tests failed. Aborting release.${RESET}"
    exit 1
}

# Commit the change
echo -e "${YELLOW}Committing version bump...${RESET}"
git add package.json
git commit -m "Bump version to v${VERSION}"

# Create a tag
echo -e "${YELLOW}Creating tag v${VERSION}...${RESET}"
git tag -a "v${VERSION}" -m "${MESSAGE}"

# Instructions for pushing
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Release v${VERSION} prepared!                     ${RESET}"
echo -e "${GREEN}====================================================${RESET}"
echo -e "${YELLOW}To finalize the release, run:${RESET}"
echo -e "  git push origin main"
echo -e "  git push origin v${VERSION}"
echo -e "${YELLOW}This will trigger the CI/CD pipeline to create a GitHub release.${RESET}"