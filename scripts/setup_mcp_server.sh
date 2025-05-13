#!/bin/bash
set -eo pipefail

# Setup script for Ingestor MCP Server
# This script installs the required Node.js dependencies and sets up the MCP server

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

# Display header
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Ingestor System - MCP Server Setup               ${RESET}"
echo -e "${GREEN}====================================================${RESET}"

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_DIR="$PROJECT_ROOT/src/mcp"

# Change to the project directory
cd "$PROJECT_ROOT"

# Check for Node.js
echo -e "${YELLOW}Checking for Node.js...${RESET}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js not found. Please install Node.js before continuing.${RESET}"
    echo -e "${YELLOW}Visit https://nodejs.org/ to download and install.${RESET}"
    exit 1
fi

node_version=$(node -v)
echo -e "${GREEN}Node.js found: $node_version${RESET}"

# Check for npm
echo -e "${YELLOW}Checking for npm...${RESET}"
if ! command -v npm &> /dev/null; then
    echo -e "${RED}npm not found. Please install npm before continuing.${RESET}"
    exit 1
fi

npm_version=$(npm -v)
echo -e "${GREEN}npm found: $npm_version${RESET}"

# Create package.json if it doesn't exist
if [[ ! -f "$PROJECT_ROOT/package.json" ]]; then
    echo -e "${YELLOW}Creating package.json...${RESET}"
    cat > "$PROJECT_ROOT/package.json" << EOF
{
  "name": "ingestor-system",
  "version": "0.1.0",
  "description": "Content ingestion system for SQLite databases with Claude AI integration",
  "main": "src/mcp/ingestor_mcp_server.js",
  "scripts": {
    "start": "node src/mcp/ingestor_mcp_server.js",
    "start:http": "node src/mcp/ingestor_mcp_server.js --transport http",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "",
  "license": "MIT",
  "dependencies": {
    "sqlite3": "^5.1.6"
  }
}
EOF
    echo -e "${GREEN}Created package.json${RESET}"
fi

# Install dependencies
echo -e "${YELLOW}Installing Node.js dependencies...${RESET}"
npm install

# Create MCP configuration for Claude
echo -e "${YELLOW}Creating MCP server configuration...${RESET}"

# Ensure MCP configuration directory exists
mkdir -p ~/.claude/mcp/servers

# Create MCP server configuration
cat > ~/.claude/mcp/servers/ingestor.json << EOF
{
  "name": "ingestor",
  "transport": "stdio",
  "command": "node",
  "args": ["$MCP_DIR/ingestor_mcp_server.js"],
  "env": {
    "NODE_ENV": "production"
  },
  "autoApprove": ["*"],
  "cwd": "$PROJECT_ROOT"
}
EOF

echo -e "${GREEN}Created MCP server configuration at ~/.claude/mcp/servers/ingestor.json${RESET}"

# Create HTTP server version configuration
cat > ~/.claude/mcp/servers/ingestor-http.json << EOF
{
  "name": "ingestor-http",
  "transport": "http",
  "url": "http://localhost:11434",
  "autoApprove": ["*"]
}
EOF

echo -e "${GREEN}Created HTTP MCP server configuration at ~/.claude/mcp/servers/ingestor-http.json${RESET}"

# Create startup script
echo -e "${YELLOW}Creating MCP server startup script...${RESET}"

cat > "$PROJECT_ROOT/scripts/start_mcp_server.sh" << EOF
#!/bin/bash
set -eo pipefail

# Start script for Ingestor MCP Server
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="\$(cd "\$SCRIPT_DIR/.." && pwd)"
MCP_DIR="\$PROJECT_ROOT/src/mcp"

echo "Starting Ingestor MCP Server..."

# Default to stdio transport
TRANSPORT="stdio"

# Parse arguments
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --http)
            TRANSPORT="http"
            shift
            ;;
        --port)
            PORT="\$2"
            shift 2
            ;;
        *)
            echo "Unknown option: \$1"
            echo "Usage: \$0 [--http] [--port PORT]"
            exit 1
            ;;
    esac
done

# Start server with appropriate transport
if [[ "\$TRANSPORT" == "http" ]]; then
    PORT_ARG=""
    if [[ -n "\$PORT" ]]; then
        PORT_ARG="--port \$PORT"
    fi
    
    node "\$MCP_DIR/ingestor_mcp_server.js" --transport http \$PORT_ARG
else
    # Start with stdio transport
    node "\$MCP_DIR/ingestor_mcp_server.js"
fi
EOF

chmod +x "$PROJECT_ROOT/scripts/start_mcp_server.sh"
echo -e "${GREEN}Created startup script at $PROJECT_ROOT/scripts/start_mcp_server.sh${RESET}"

# Create a guide for using the MCP server
echo -e "${YELLOW}Creating usage guide...${RESET}"

cat > "$PROJECT_ROOT/docs/mcp_server_guide.md" << EOF
# Ingestor MCP Server Guide

This guide explains how to use the Ingestor MCP Server with Claude.

## Setup

The setup script has already:
1. Installed required Node.js dependencies
2. Created MCP server configurations for Claude
3. Created startup scripts

## Starting the MCP Server

You can start the MCP server in two ways:

### Standard stdio transport (recommended for Claude CLI)

```bash
# From the project root
./scripts/start_mcp_server.sh

# Or via npm
npm start
```

### HTTP transport (for other integrations)

```bash
# From the project root
./scripts/start_mcp_server.sh --http [--port PORT]

# Or via npm
npm run start:http
```

## Using with Claude

### Claude CLI

1. Start Claude CLI with the Ingestor MCP server:

```bash
claude --mcp ingestor
```

2. Now you can use the Ingestor tools in your conversation with Claude.

### Claude via web interface

If using the HTTP transport:

1. Start the MCP server with HTTP transport:

```bash
./scripts/start_mcp_server.sh --http
```

2. Add the server URL in Claude's settings.

## Available Tools

The Ingestor MCP server provides the following tools:

1. \`list_databases\` - List all available databases
2. \`get_database_schema\` - Get schema information for a database
3. \`query_database\` - Execute SELECT queries on a database
4. \`get_database_stats\` - Get statistics about a database
5. \`search_content\` - Search across databases for specific content
6. \`get_content_details\` - Get detailed information about a content item
7. \`run_ingestor\` - Execute ingestor commands directly
8. \`process_content\` - Process content through the ingestor

## Example Usage

Here are some example queries you can ask Claude:

- "List all databases in the ingestor system"
- "What is the schema of the general database?"
- "Search for 'climate change' across all databases"
- "Process this text and store it in the research database: [your text here]"
- "Get statistics about the media database"

## Troubleshooting

If you encounter issues:

1. Check the logs in \`~/.ingestor/logs/\`
2. Ensure the MCP server is running
3. Verify that Claude is configured to use the MCP server
4. Check that the required dependencies are installed
EOF

echo -e "${GREEN}Created usage guide at $PROJECT_ROOT/docs/mcp_server_guide.md${RESET}"

# Final output
echo -e "${GREEN}====================================================${RESET}"
echo -e "${GREEN}   Ingestor MCP Server setup complete!              ${RESET}"
echo -e "${GREEN}====================================================${RESET}"
echo
echo -e "${YELLOW}To start the MCP server:${RESET}"
echo -e "  ${GREEN}./scripts/start_mcp_server.sh${RESET}"
echo
echo -e "${YELLOW}To use with Claude CLI:${RESET}"
echo -e "  ${GREEN}claude --mcp ingestor${RESET}"
echo
echo -e "${YELLOW}For more information, see:${RESET}"
echo -e "  ${GREEN}$PROJECT_ROOT/docs/mcp_server_guide.md${RESET}"
echo