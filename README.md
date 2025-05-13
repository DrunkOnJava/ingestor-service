# Ingestor System

A flexible content ingestion system for SQLite databases that processes various content types using Claude AI to extract meaningful data.

## Overview

The Ingestor System is designed to accept various content types (text, images, videos, code files) and intelligently process them to extract relevant data and metadata for storage in specialized SQLite databases. It uses Claude's AI capabilities for content analysis and supports both interactive terminal input and file-based processing.

## Features

- Simple command-line interface with "ingestor" command
- Support for multiple content types (text, images, videos, documents, code)
- Intelligent processing and extraction using Claude AI
- Chunked processing for handling large inputs
- Configurable database profiles for specialized data interests
- Interactive terminal mode and file-based processing

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/ingestor-system.git
cd ingestor-system

# Install dependencies
./scripts/install_dependencies.sh

# Set up environment
cp .env.example .env
# Edit .env with your Claude API key and other configuration
```

## Usage

```bash
# Interactive mode
ingestor --database my_database

# Process a file
ingestor --file path/to/file.txt --database my_database

# Batch processing
ingestor --batch --directory path/to/files --database my_database
```

## Project Structure

```
ingestor-system/
├── config/               # Configuration files
├── docs/                 # Documentation
├── lib/                  # Shared libraries
├── scripts/              # Utility scripts
├── src/                  # Source code
│   ├── modules/          # Core modules
│   ├── processors/       # Content type processors
│   ├── database/         # Database management
│   ├── claude/           # Claude integration
│   └── ingestor          # Main executable
└── tests/                # Test suite
```

## Configuration

The system uses a hierarchical configuration structure:

- Global settings in `config/settings.yml`
- Database profiles in `config/databases/`
- Content type processors in `config/processors/`

## Development

```bash
# Run tests
./scripts/run_tests.sh

# Check code style
./scripts/lint.sh

# Build documentation
./scripts/build_docs.sh
```

## License

MIT