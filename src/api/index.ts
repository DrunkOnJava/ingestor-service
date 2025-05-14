/**
 * Index file for API module
 * Re-exports API components
 */

// Re-export MCP server
export * from './mcp';

// Export server components
import { app, server, wsManager } from './server';
export { app, server };

// WebSocket manager singleton
let _wsManager = wsManager;

/**
 * Get the WebSocket manager instance
 * @returns WebSocket manager or undefined if not initialized
 */
export function getWebSocketManager() {
  return _wsManager;
}

/**
 * Initialize and start the API server
 * @param options Server configuration options
 * @returns The server instance
 */
export function startApiServer(options = {}) {
  const port = options.port || process.env.API_PORT || 3000;
  
  return new Promise<void>((resolve) => {
    server.listen(port, () => {
      console.log(`API server running on port ${port}`);
      console.log(`API documentation available at http://localhost:${port}/api/docs`);
      resolve();
    });
  });
}

/**
 * Stop the API server
 */
export function stopApiServer() {
  return new Promise<void>((resolve, reject) => {
    server.close((err) => {
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
}