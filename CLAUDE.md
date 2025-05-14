# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Test Commands

- Install dependencies: `./scripts/install_dependencies.sh`
- Set up MCP server: `./scripts/setup_mcp_server.sh`
- Start MCP server (stdio): `./scripts/start_mcp_server.sh`
- Start MCP server (HTTP): `./scripts/start_mcp_server.sh --http [--port PORT]`
- Use with Claude CLI: `claude --mcp ingestor`
- Run ingestor (interactive): `./src/ingestor --database DB_NAME`
- Run ingestor (file): `./src/ingestor --file PATH --database DB_NAME`
- List databases: `./src/ingestor --list-dbs`
- Initialize database: `./src/ingestor --init-db DB_NAME`
- Run tests: `./scripts/run_tests.sh` (when implemented)
- Lint code: `./scripts/lint.sh` (when implemented)

## System Architecture

### Core Components

1. **MCP Server (`src/mcp/ingestor_mcp_server.js`)**
   - NodeJS server implementing the Model Context Protocol
   - Allows Claude to interact with the ingestor system
   - Provides tools for database operations and content processing
   - Supports both stdio and HTTP transport

2. **Ingestor CLI (`src/ingestor`)**
   - Bash script providing command-line interface
   - Processes various content types (text, images, videos, code)
   - Supports interactive, file-based, and batch processing modes
   - Extracts data using Claude AI and stores in SQLite databases

3. **Core Modules (`src/modules/`)**
   - `claude.sh`: Claude API integration for content analysis
   - `config.sh`: Configuration management
   - `content.sh`: Content type detection and processing
   - `database.sh`: SQLite database operations
   - `logging.sh`: Logging functionality

4. **Database Layer**
   - Uses SQLite for storage
   - Schemas defined in `config/schemas/`
   - FTS (Full-Text Search) for efficient content querying
   - Content-specific tables (texts, images, videos, documents, code)

### Data Flow

1. **Content Ingestion**
   - User provides content via CLI or MCP interface
   - System detects content type
   - Content is chunked if necessary (for large files)

2. **Analysis with Claude**
   - Content sent to Claude API with appropriate system prompt
   - Claude analyzes content and returns structured JSON
   - Analysis includes topics, entities, sentiments, and other metadata

3. **Storage in SQLite**
   - Content and analysis stored in appropriate tables
   - FTS indexes created for efficient searching
   - Metadata extracted for relationships and tagging

4. **Query and Retrieval**
   - MCP server provides database query capabilities
   - Full-text search across content and analysis
   - Filtering by content type, tags, entities

## Configuration

1. **Environment Setup**
   - Ingestor home directory: `~/.ingestor/`
   - Databases stored in: `~/.ingestor/databases/`
   - Configuration in: `~/.ingestor/config/`
   - Logs in: `~/.ingestor/logs/`

2. **MCP Configuration**
   - Claude MCP server configuration: `~/.claude/mcp/servers/ingestor.json`
   - HTTP variant: `~/.claude/mcp/servers/ingestor-http.json`

3. **API Keys**
   - Claude API key required for content analysis
   - Set in environment or config file

## Database Schema

The system uses SQLite databases with the following key tables:

1. **Content Type Tables**
   - `texts`: Text documents and plain text
   - `images`: Image files with analysis
   - `videos`: Video files with metadata
   - `documents`: PDFs and other structured documents
   - `code`: Source code files

2. **Organizational Tables**
   - `tags`: Content categorization
   - `entities`: People, organizations, locations extracted
   - `content_entities`: Links between content and entities
   - `search_terms`: Tracks search history

3. **Full-Text Search**
   - FTS5 virtual tables for efficient text searching
   - Indexes on content and analysis fields
   - Trigger-based synchronization

## MCP Tools

The MCP server exposes these tools to Claude:

1. **Database Tools**
   - `list_databases`: Show available databases
   - `get_database_schema`: View database structure
   - `query_database`: Execute SELECT queries
   - `get_database_stats`: Database statistics

2. **Content Tools**
   - `search_content`: Search across databases
   - `get_content_details`: Retrieve specific content
   - `process_content`: Process and store new content
   - `run_ingestor`: Execute ingestor commands

## Development Workflow

1. **Setup Environment**
   - Clone repository
   - Run `./scripts/install_dependencies.sh`
   - Set up MCP server with `./scripts/setup_mcp_server.sh`

2. **Feature Development**
   - Core functionality in `src/modules/`
   - MCP server extensions in `src/mcp/`
   - Database schema changes in `config/schemas/`

3. **Testing**
   - Manual testing with CLI
   - MCP server testing with Claude
   - SQLite query validation

4. **Deployment**
   - Configure MCP server for Claude
   - Set required API keys
   - Initialize databases