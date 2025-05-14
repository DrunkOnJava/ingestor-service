# Ingestor System

A modular TypeScript system for content ingestion, entity extraction, and database storage with Claude AI integration.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

The Ingestor System processes various content types (text, PDFs, code, images, etc.), extracts named entities, and stores them in SQLite databases for later retrieval and analysis. It includes a Model Context Protocol (MCP) server for seamless integration with Claude.

The system is designed to be modular, with separate components for content detection, processing, database management, and Claude AI integration. It provides a seamless way to analyze and store content of different types with minimal configuration.

## Features

- **Content Processing**: Analyze text, code, PDFs, images, and more
- **Entity Extraction**: Extract people, organizations, dates, and other entities
- **Content Chunking**: Efficiently process large files
- **SQLite Storage**: Store content and entities with optimized indexes
- **Full-Text Search**: Search across all content and entities
- **Claude AI Integration**: Use Claude for enhanced entity recognition
- **MCP Server**: Claude Model Context Protocol implementation
- **TypeScript Architecture**: Modular design with strong typing

## Installation

### Prerequisites

- Node.js 16+ for TypeScript execution
- SQLite 3.35.0+ for database operations
- Optional: Claude API key for enhanced entity extraction

### Steps

```bash
# Clone the repository
git clone https://github.com/yourusername/ingestor-system.git
cd ingestor-system

# Install dependencies
npm install

# Build the project
npm run build

# Set up environment
cp .env.example .env
# Edit .env to add your Claude API key
```

The built system will:
1. Create the necessary directory structure in `~/.ingestor/`
2. Set up database schemas automatically
3. Configure logging and temporary directories

## Usage

### MCP Server

Start the MCP server for Claude integration:

```bash
# Start with stdio transport (for Claude CLI)
npm run mcp

# Start with HTTP transport (for other clients)
npm run mcp:http --port 3000
```

### TypeScript API

```typescript
import { EntityManager, ContentProcessor, DatabaseService } from './core';

// Create components
const logger = new Logger('myapp');
const dbService = new DatabaseService(logger);
const entityManager = new EntityManager(logger, dbService);
const contentProcessor = new ContentProcessor(logger, fs, claudeService, entityManager);

// Process content
const result = await contentProcessor.processContent(
  'path/to/content.txt',
  'text/plain'
);

// Extract entities
const entityResult = await entityManager.extractEntities(
  'This is a text containing Apple Inc. and Tim Cook.',
  'text/plain'
);
```

### Content Processing

The system supports various content types:

- Text (plain text, markdown, HTML)
- Documents (PDF, Word)
- Code (multiple programming languages)
- Images (with text extraction)
- Videos (metadata extraction)

Content can be chunked for efficient processing of large files using different strategies:
- Character-based chunking
- Line-based chunking
- Paragraph-based chunking
- Token-based chunking

## Architecture

The system follows a modular architecture with clear separation of concerns:

```
ingestor-system/
├── config/               # Configuration files
│   └── schemas/          # Database schema SQL files
├── src/                  # Source code
│   ├── core/             # Core functionality
│   │   ├── entity/       # Entity extraction
│   │   │   ├── types/    # Entity type definitions
│   │   │   ├── extractors/ # Content-specific extractors
│   │   │   └── utils/    # Entity utilities
│   │   ├── content/      # Content processing
│   │   ├── database/     # Database management
│   │   ├── logging/      # Logging functionality
│   │   ├── services/     # Service interfaces
│   │   └── utils/        # Utility functions
│   ├── api/              # External interfaces
│   │   └── mcp/          # MCP server implementation
│   └── index.ts          # Main entry point
├── tests/                # Test suite
│   ├── unit/             # Unit tests
│   ├── integration/      # Integration tests
│   └── fixtures/         # Test fixtures
├── dist/                 # Compiled output
├── scripts/              # Utility scripts
├── package.json          # NPM package definition
└── tsconfig.json         # TypeScript configuration
```

## Database Schema

The system uses SQLite with a modular schema:

### Entity Tables

```sql
-- Entities table
CREATE TABLE IF NOT EXISTS entities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  description TEXT,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Content-entity relationships
CREATE TABLE IF NOT EXISTS content_entities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  relevance REAL DEFAULT 0.5,
  context TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (entity_id) REFERENCES entities(id) ON DELETE CASCADE
);
```

### Content Tables

```sql
-- Content metadata
CREATE TABLE IF NOT EXISTS content (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_type TEXT NOT NULL,
  title TEXT,
  description TEXT,
  source TEXT,
  file_path TEXT,
  hash TEXT,
  size INTEGER,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Content chunks for large content
CREATE TABLE IF NOT EXISTS content_chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id INTEGER NOT NULL,
  chunk_index INTEGER NOT NULL,
  chunk_text TEXT,
  chunk_metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE
);
```

### Full-Text Search

```sql
-- Full-text search for content
CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
  title, 
  description, 
  content,
  content='content_chunks',
  content_rowid='id'
);

-- Entity full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS entity_fts USING fts5(
  name,
  type,
  description,
  content='entities',
  content_rowid='id'
);

## Development

### Development Workflow

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Start MCP server in development mode
npm run mcp

# Run linting
npm run lint

# Run tests
npm run test
```

### Testing

The project uses Jest for testing TypeScript code:

```bash
# Run all tests
npm test

# Run with coverage
npm test -- --coverage

# Run specific tests
npm test -- --testPathPattern=entity
```

### Extending the System

#### Adding a New Entity Extractor

1. Create a new class in `src/core/entity/extractors` that extends `EntityExtractor`
2. Implement the `extract` method for your specific content type
3. Register your extractor in `EntityManager.initializeExtractors()`

```typescript
// Example: Create a new PDF entity extractor
import { EntityExtractor } from '../EntityExtractor';

export class PdfEntityExtractor extends EntityExtractor {
  public async extract(content: string, contentType: string, options?: EntityExtractionOptions): Promise<EntityExtractionResult> {
    // PDF-specific extraction logic here
    // ...
    return {
      entities: extractedEntities,
      success: true
    };
  }
}
```

#### Adding a New MCP Tool

1. Define your tool in `src/api/mcp/IngestorMcpServer.ts`
2. Implement the handler method
3. Add the tool to the routing logic in `handleToolRequest()`

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and linting (`npm test && npm run lint`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

MIT