/**
 * Main entry point for the ingestor system
 */

import { Logger, LogLevel } from './core/logging';
import { IngestorMcpServer } from './api/mcp';

// Create main logger
const logger = new Logger('ingestor', {
  level: (process.env.LOG_LEVEL as LogLevel) || LogLevel.INFO,
  console: true,
  timestamps: true
});

/**
 * Main function to start the ingestor system
 */
async function main() {
  try {
    logger.info('Starting ingestor system');
    
    // Parse command line arguments
    const args = parseCommandLineArgs();
    
    // Create and start MCP server
    if (args.startMcp) {
      const transport = args.httpMcp ? 'http' : 'stdio';
      const port = args.port ? parseInt(args.port, 10) : 3000;
      
      logger.info(`Starting MCP server with ${transport} transport${transport === 'http' ? ` on port ${port}` : ''}`);
      
      const mcpServer = new IngestorMcpServer({
        transport,
        port,
        logLevel: (args.debug ? LogLevel.DEBUG : undefined)
      });
      
      mcpServer.start();
      
      // Handle process signals
      process.on('SIGINT', async () => {
        logger.info('Received SIGINT, shutting down');
        await mcpServer.stop();
        process.exit(0);
      });
      
      process.on('SIGTERM', async () => {
        logger.info('Received SIGTERM, shutting down');
        await mcpServer.stop();
        process.exit(0);
      });
    } 
    // Run ingestor CLI mode
    else {
      logger.info('Running in CLI mode');
      // Implement CLI functionality here
    }
  } catch (error) {
    logger.error(`Error in main: ${error instanceof Error ? error.message : 'Unknown error'}`);
    process.exit(1);
  }
}

/**
 * Parse command line arguments
 * @returns Parsed arguments
 */
function parseCommandLineArgs() {
  const args: Record<string, string | boolean> = {
    startMcp: false,
    httpMcp: false,
    debug: false
  };
  
  // Process command line arguments
  for (let i = 2; i < process.argv.length; i++) {
    const arg = process.argv[i];
    
    if (arg === '--mcp') {
      args.startMcp = true;
    } else if (arg === '--http') {
      args.httpMcp = true;
      args.startMcp = true;
    } else if (arg === '--debug') {
      args.debug = true;
    } else if (arg === '--port' && i + 1 < process.argv.length) {
      args.port = process.argv[++i];
    } else if (arg.startsWith('--')) {
      const key = arg.substring(2);
      const value = i + 1 < process.argv.length && !process.argv[i + 1].startsWith('--') 
        ? process.argv[++i] 
        : true;
      args[key] = value;
    }
  }
  
  return args;
}

// Run main function if this file is executed directly
if (require.main === module) {
  main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}