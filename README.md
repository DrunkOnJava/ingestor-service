# Ingestor System

A flexible content ingestion system for SQLite databases that processes various content types using Claude AI to extract meaningful data.

## Overview

The Ingestor System is designed to accept various content types (text, images, videos, code files) and intelligently process them to extract relevant data and metadata for storage in specialized SQLite databases. It uses Claude's AI capabilities for content analysis and supports both interactive terminal input and file-based processing.

The system is designed to be modular, with separate components for content detection, processing, database management, and Claude AI integration. It provides a seamless way to analyze and store content of different types with minimal configuration.

## Features

- Simple command-line interface with "ingestor" command
- Support for multiple content types (text, images, videos, documents, code)
- Intelligent processing and extraction using Claude AI
- Chunked processing for handling large inputs
- Configurable database profiles for specialized data interests
- Interactive terminal mode and file-based processing

## Installation

### Prerequisites

- Bash 4.0+ or compatible shell
- SQLite 3.35.0+ for database operations
- cURL or wget for network operations
- jq for JSON processing
- A Claude API key for content analysis

### Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/ingestor-system.git
cd ingestor-system

# Install dependencies (including BATS for testing)
./scripts/install_dependencies.sh

# Set up environment and configuration
./scripts/setup.sh

# Configure your Claude API key (uses macOS Keychain or manual entry)
./scripts/configure_api_key.sh
```

The installation script will:
1. Check and install required dependencies
2. Set up the directory structure in `~/.ingestor/`
3. Create default configuration files
4. Set up database schemas
5. Configure the MCP server (for Claude Code integration)

## Usage

### Basic Operations

```bash
# Interactive mode
ingestor --database my_database

# Process a file
ingestor --file path/to/file.txt --database my_database

# Batch processing
ingestor --batch --directory path/to/files --database my_database

# List available databases
ingestor --list-dbs

# Initialize a new database
ingestor --init-db new_database
```

### Advanced Options

```bash
# Specify chunking strategy (size, paragraph, or sentence)
ingestor --file large_document.txt --chunk-strategy paragraph

# Set maximum chunk size (in bytes for size strategy)
ingestor --file large_document.txt --max-chunk-size 8192

# Process with specific Claude model
ingestor --file code.py --model claude-3-opus-20240229

# Extract specific entities
ingestor --file article.txt --extract people,organizations,dates

# Control verbosity
ingestor --file document.txt --verbose
ingestor --file document.txt --quiet

# Export processed content
ingestor --database my_database --export json --output exported_data.json
```

### Using as MCP Server with Claude Code

```bash
# Start MCP server (stdio transport)
./scripts/start_mcp_server.sh

# Start MCP server (HTTP transport on port 8080)
./scripts/start_mcp_server.sh --http --port 8080

# Use with Claude CLI
claude --mcp ingestor
```

## Project Structure

```
ingestor-system/
├── config/               # Configuration files
│   ├── schemas/          # Database schemas
│   └── defaults/         # Default configuration templates
├── docs/                 # Documentation
│   ├── api/              # API documentation
│   ├── examples/         # Example usage scenarios
│   └── images/           # Documentation images
├── lib/                  # Shared libraries
├── scripts/              # Utility scripts
│   ├── install_dependencies.sh  # Install required dependencies
│   ├── setup.sh          # Set up the environment
│   ├── configure_api_key.sh     # Configure Claude API key
│   ├── run_tests.sh      # Run the test suite
│   ├── lint.sh           # Check code style
│   ├── start_mcp_server.sh      # Start MCP server
│   └── setup_mcp_server.sh      # Configure MCP server
├── src/                  # Source code
│   ├── modules/          # Core modules
│   │   ├── config.sh     # Configuration management
│   │   ├── content.sh    # Content detection and processing
│   │   ├── database.sh   # Database operations
│   │   ├── keychain.sh   # API key management
│   │   └── logging.sh    # Logging functionality
│   ├── processors/       # Content type processors
│   │   ├── text.sh       # Text processor
│   │   ├── image.sh      # Image processor
│   │   ├── video.sh      # Video processor
│   │   ├── document.sh   # Document processor
│   │   └── code.sh       # Code processor
│   ├── mcp/              # Model Context Protocol integration
│   │   └── ingestor_mcp_server.js  # MCP server implementation
│   ├── claude/           # Claude integration
│   │   ├── api.sh        # Claude API client
│   │   └── prompts/      # System prompts for content types
│   └── ingestor          # Main executable
└── tests/                # Test suite
    ├── unit/             # Unit tests
    │   ├── config.bats   # Tests for config module
    │   ├── content.bats  # Tests for content module
    │   ├── database.bats # Tests for database module
    │   └── keychain.bats # Tests for keychain module
    ├── integration/      # Integration tests
    │   └── ingestor_basic.bats  # Basic end-to-end tests
    ├── fixtures/         # Test fixtures (sample files)
    ├── test_helper.bash  # Test helpers and utilities
    └── assertions.bash   # Custom assertion functions
```

## Configuration

The system uses a hierarchical configuration structure:

### System Configuration

The global configuration is stored in `~/.ingestor/config/settings.yml` and includes:

```yaml
# Claude API Key (or use KEYCHAIN to retrieve from system keychain)
claude_api_key: KEYCHAIN

# Default database to use if none specified
default_database: general

# Log level (debug, info, warning, error)
log_level: info

# Content processing settings
content:
  # Maximum file size in bytes for direct processing
  max_file_size: 10485760 # 10MB
  
  # Chunk size for large files
  chunk_size: 524288 # 512KB
  
  # Temporary file handling
  keep_temp_files: false

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
  model: claude-3-opus-20240229
  
  # Maximum tokens per request
  max_tokens: 4096
  
  # Temperature for generation
  temperature: 0.7
  
  # Request timeout in seconds
  timeout: 60
  
  # Maximum retries on failure
  max_retries: 3
```

### Database Profiles

Database profiles (stored in `~/.ingestor/config/databases/`) define how content is processed for specific databases:

```yaml
# Example database profile: research.yml
name: Research Database
description: Specialized database for research papers and academic content

# Content types to process
content_types:
  - text/plain
  - application/pdf
  - application/msword
  
# Extraction focus
extraction:
  # General topics of interest
  topics:
    - research methodology
    - scientific findings
    - academic citations
  
  # Entities to extract
  entities:
    - authors
    - institutions
    - dates
    - citations
  
  # Metadata to extract
  metadata:
    - title
    - abstract
    - publication_date
    - keywords
```

### MCP Server Configuration

For Claude Code integration, configure the MCP server using the setup script:

```bash
./scripts/setup_mcp_server.sh
```

This creates a configuration for the Claude CLI:

```json
{
  "name": "ingestor",
  "command": "/path/to/ingestor-system/scripts/start_mcp_server.sh",
  "env": {
    "INGESTOR_MCP_MODE": "true",
    "INGESTOR_CONFIG_DIR": "~/.ingestor/config"
  },
  "transport": "stdio",
  "description": "Content ingestion system for Claude integration"
}
```

## Development

### Running Tests

The project uses BATS (Bash Automated Testing System) for testing:

```bash
# Run all tests
./scripts/run_tests.sh

# Run only unit tests
./scripts/run_tests.sh --unit

# Run only integration tests
./scripts/run_tests.sh --int

# Run specific module tests
./scripts/run_tests.sh keychain
./scripts/run_tests.sh content

# Run tests with verbose output
./scripts/run_tests.sh --verbose
```

### Code Style

The project follows shell script best practices:

```bash
# Check code style
./scripts/lint.sh

# Auto-fix linting issues where possible
./scripts/lint.sh --fix
```

### Building Documentation

Documentation is generated using Markdown and converted to HTML/PDF:

```bash
# Build all documentation
./scripts/build_docs.sh

# Build specific sections
./scripts/build_docs.sh --section api
./scripts/build_docs.sh --section examples
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and linting (`./scripts/run_tests.sh && ./scripts/lint.sh`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## System Architecture

### Core Components

1. **Config Module**
   - Manages configuration loading/saving
   - Handles default configuration creation
   - Provides profile management for databases

2. **Content Module**
   - Detects content types
   - Manages content chunking strategies
   - Routes content to appropriate processors

3. **Database Module**
   - Handles SQLite database operations
   - Creates and upgrades database schemas
   - Provides query utilities for content retrieval

4. **Keychain Module**
   - Securely manages API keys
   - Integrates with system keychain (macOS/Linux)
   - Provides fallback for environments without keychain

5. **Claude Integration**
   - Handles API communication with Claude
   - Manages prompts for different content types
   - Processes and formats Claude responses

6. **MCP Server**
   - Implements Model Context Protocol
   - Provides tools for Claude Code integration
   - Supports both stdio and HTTP transport

## License

MIT