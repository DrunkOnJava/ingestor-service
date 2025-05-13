#!/bin/bash
set -eo pipefail

# Start script for Ingestor MCP Server
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_DIR="$PROJECT_ROOT/src/mcp"

echo "Starting Ingestor MCP Server..."

# Default to stdio transport
TRANSPORT="stdio"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --http)
            TRANSPORT="http"
            shift
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--http] [--port PORT]"
            exit 1
            ;;
    esac
done

# Start server with appropriate transport
if [[ "$TRANSPORT" == "http" ]]; then
    PORT_ARG=""
    if [[ -n "$PORT" ]]; then
        PORT_ARG="--port $PORT"
    fi
    
    node "$MCP_DIR/ingestor_mcp_server.js" --transport http $PORT_ARG
else
    # Start with stdio transport
    node "$MCP_DIR/ingestor_mcp_server.js"
fi
