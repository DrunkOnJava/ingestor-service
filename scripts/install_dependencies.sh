#!/bin/bash
set -eo pipefail

# Install dependencies script for Ingestor System
# This script installs all required dependencies for the ingestor system

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Ingestor System - Dependencies Installation      ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Check for Homebrew (macOS)
install_with_brew() {
    echo -e "${YELLOW}Checking for Homebrew...${RESET}"
    if command -v brew &> /dev/null; then
        echo -e "${GREEN}Homebrew found.${RESET}"
        
        echo -e "${YELLOW}Installing dependencies via Homebrew...${RESET}"
        brew update
        
        # Core dependencies
        brew install sqlite
        brew install jq
        brew install coreutils
        
        # Content type detection
        brew install file
        
        # Image processing
        brew install exiftool
        
        # PDF processing
        brew install poppler # For pdftotext
        
        # Video processing
        brew install ffmpeg
        
        echo -e "${GREEN}Homebrew dependencies installed successfully.${RESET}"
        return 0
    else
        echo -e "${RED}Homebrew not found. Please install Homebrew first: https://brew.sh${RESET}"
        return 1
    fi
}

# Check for apt-get (Ubuntu/Debian)
install_with_apt() {
    echo -e "${YELLOW}Checking for apt-get...${RESET}"
    if command -v apt-get &> /dev/null; then
        echo -e "${GREEN}apt-get found.${RESET}"
        
        echo -e "${YELLOW}Installing dependencies via apt-get...${RESET}"
        sudo apt-get update
        
        # Core dependencies
        sudo apt-get install -y sqlite3 libsqlite3-dev
        sudo apt-get install -y jq
        
        # Content type detection
        sudo apt-get install -y file
        
        # Image processing
        sudo apt-get install -y libimage-exiftool-perl
        
        # PDF processing
        sudo apt-get install -y poppler-utils
        
        # Video processing
        sudo apt-get install -y ffmpeg
        
        echo -e "${GREEN}apt-get dependencies installed successfully.${RESET}"
        return 0
    else
        return 1
    fi
}

# Check for Node.js
check_node() {
    echo -e "${YELLOW}Checking for Node.js...${RESET}"
    if command -v node &> /dev/null; then
        node_version=$(node -v)
        echo -e "${GREEN}Node.js found: $node_version${RESET}"
        return 0
    else
        echo -e "${RED}Node.js not found. Some features may not work.${RESET}"
        echo -e "${YELLOW}Please install Node.js from https://nodejs.org/${RESET}"
        return 1
    fi
}

# Check for Python 3
check_python() {
    echo -e "${YELLOW}Checking for Python 3...${RESET}"
    if command -v python3 &> /dev/null; then
        python_version=$(python3 --version)
        echo -e "${GREEN}Python 3 found: $python_version${RESET}"
        return 0
    else
        echo -e "${RED}Python 3 not found. Some features may not work.${RESET}"
        echo -e "${YELLOW}Please install Python 3 from https://www.python.org/${RESET}"
        return 1
    fi
}

# Set up ingestor environment
setup_environment() {
    echo -e "${YELLOW}Setting up ingestor environment...${RESET}"
    
    # Create .ingestor directory structure
    mkdir -p ~/.ingestor/{config,databases,logs,tmp}
    
    # Create initial configuration if it doesn't exist
    if [[ ! -f ~/.ingestor/config/settings.yml ]]; then
        echo -e "${YELLOW}Creating initial configuration...${RESET}"
        
        mkdir -p ~/.ingestor/config/databases
        
        # Copy default configuration files
        cp -r "$(dirname "$0")/../config/"* ~/.ingestor/config/
        
        echo -e "${GREEN}Initial configuration created.${RESET}"
    fi
    
    echo -e "${GREEN}Environment setup complete.${RESET}"
}

# Create symlink to make ingestor command available
create_symlink() {
    echo -e "${YELLOW}Creating ingestor command symlink...${RESET}"
    
    # Get script directory (resolving symlinks)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    # Create symlink in /usr/local/bin if possible, otherwise in ~/bin
    if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
        echo -e "${YELLOW}Creating symlink in /usr/local/bin...${RESET}"
        sudo ln -sf "$PROJECT_ROOT/src/ingestor" /usr/local/bin/ingestor
        echo -e "${GREEN}Symlink created in /usr/local/bin/ingestor${RESET}"
    else
        echo -e "${YELLOW}Creating symlink in ~/bin...${RESET}"
        mkdir -p ~/bin
        ln -sf "$PROJECT_ROOT/src/ingestor" ~/bin/ingestor
        
        # Add ~/bin to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
            echo -e "${YELLOW}Adding ~/bin to PATH...${RESET}"
            if [[ -f ~/.bashrc ]]; then
                echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
                echo -e "${GREEN}Added ~/bin to PATH in ~/.bashrc${RESET}"
            elif [[ -f ~/.zshrc ]]; then
                echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
                echo -e "${GREEN}Added ~/bin to PATH in ~/.zshrc${RESET}"
            else
                echo 'export PATH="$HOME/bin:$PATH"' >> ~/.profile
                echo -e "${GREEN}Added ~/bin to PATH in ~/.profile${RESET}"
            fi
            
            echo -e "${YELLOW}Please restart your shell or run 'source ~/.bashrc' (or your shell's config file) to update your PATH.${RESET}"
        fi
        
        echo -e "${GREEN}Symlink created in ~/bin/ingestor${RESET}"
    fi
}

# Main installation process
main() {
    echo -e "${YELLOW}Starting installation...${RESET}"
    
    # Detect and install system dependencies
    if install_with_brew; then
        echo -e "${GREEN}Homebrew dependencies installed.${RESET}"
    elif install_with_apt; then
        echo -e "${GREEN}apt-get dependencies installed.${RESET}"
    else
        echo -e "${RED}No supported package manager found. Please install dependencies manually.${RESET}"
        echo -e "${YELLOW}Required dependencies: sqlite3, jq, file, exiftool, poppler-utils, ffmpeg${RESET}"
    fi
    
    # Check for Node.js and Python
    check_node
    check_python
    
    # Set up environment
    setup_environment
    
    # Create command symlink
    create_symlink
    
    echo -e "${GREEN}====================================================${RESET}"
    echo -e "${GREEN}   Ingestor System dependencies installed!          ${RESET}"
    echo -e "${GREEN}====================================================${RESET}"
    echo -e "${YELLOW}You can now use the 'ingestor' command.${RESET}"
    echo -e "${YELLOW}To initialize a database run: ingestor --init-db <name>${RESET}"
}

# Run the main function
main