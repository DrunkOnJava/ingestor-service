#!/bin/bash
set -eo pipefail

# Script to create a GitHub repository and push the local repo to it
# This script uses the GitHub CLI (gh) to create a repository

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Create GitHub Repository for Ingestor System      ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Parse command line arguments
REPO_NAME=""
REPO_DESC=""
PRIVATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            REPO_NAME="$2"
            shift 2
            ;;
        --desc|--description)
            REPO_DESC="$2"
            shift 2
            ;;
        --private)
            PRIVATE="--private"
            shift
            ;;
        --public)
            PRIVATE="--public"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--name REPO_NAME] [--desc DESCRIPTION] [--private|--public]"
            exit 1
            ;;
    esac
done

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}GitHub CLI (gh) not found. Please install it before running this script.${RESET}"
    echo -e "${YELLOW}Visit https://cli.github.com/ to install.${RESET}"
    exit 1
fi

# Check if logged in
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}You need to authenticate with GitHub CLI first.${RESET}"
    echo -e "${YELLOW}Running 'gh auth login'...${RESET}"
    gh auth login
fi

# If not provided via arguments, prompt for inputs
if [[ -z "$REPO_NAME" ]]; then
    echo -e "${YELLOW}This script will create a new GitHub repository for your Ingestor System project.${RESET}"
    read -p "Repository name [ingestor-servicey]: " REPO_NAME
    REPO_NAME=${REPO_NAME:-ingestor-servicey}
fi

if [[ -z "$REPO_DESC" ]]; then
    read -p "Repository description [Content ingestion service with Claude AI integration]: " REPO_DESC
    REPO_DESC=${REPO_DESC:-"Content ingestion service with Claude AI integration"}
fi

if [[ -z "$PRIVATE" ]]; then
    read -p "Make repository private? (y/N): " PRIVATE_CHOICE
    if [[ $PRIVATE_CHOICE =~ ^[Yy]$ ]]; then
        PRIVATE="--private"
    else
        PRIVATE="--public"
    fi
fi

# Create repository
echo -e "${YELLOW}Creating GitHub repository: $REPO_NAME${RESET}"
gh repo create "$REPO_NAME" --description "$REPO_DESC" $PRIVATE --confirm

# Add remote and push
echo -e "${YELLOW}Adding remote and pushing code...${RESET}"
git remote add origin "https://github.com/$(gh api user | jq -r .login)/$REPO_NAME.git"
git branch -M main
git push -u origin main

echo -e "${GREEN}Repository created and code pushed successfully!${RESET}"
echo -e "${GREEN}Repository URL: https://github.com/$(gh api user | jq -r .login)/$REPO_NAME${RESET}"