#!/usr/bin/env node

/**
 * Ingestor System - Model Context Protocol (MCP) Server
 * 
 * This script creates an MCP server that allows Claude to interact with
 * the Ingestor System's SQLite databases. It provides tools for database
 * operations including querying, inserting, and managing content.
 * 
 * The server follows the Model Context Protocol specification to enable
 * Claude to use the ingestor as a tool.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const sqlite3 = require('sqlite3').verbose();
const { Database } = require('sqlite3');
const { createServer } = require('http');
const { EventEmitter } = require('events');
const readline = require('readline');
const { execSync } = require('child_process');
const crypto = require('crypto');

// Configuration
const DEFAULT_PORT = 11434;
const DEFAULT_HOST = 'localhost';
const HOME_DIR = os.homedir();
const INGESTOR_HOME = path.join(HOME_DIR, '.ingestor');
const DB_DIR = path.join(INGESTOR_HOME, 'databases');
const CONFIG_DIR = path.join(INGESTOR_HOME, 'config');
const LOGS_DIR = path.join(INGESTOR_HOME, 'logs');
const LOG_FILE = path.join(LOGS_DIR, `mcp_server_${new Date().toISOString().split('T')[0]}.log`);

// Ensure directories exist
[INGESTOR_HOME, DB_DIR, CONFIG_DIR, LOGS_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Import structured logger
const { logger } = require('./logger');

// Configure logger based on environment variables
logger.configure({
  level: process.env.LOG_LEVEL || 'info',
  format: process.env.LOG_FORMAT || 'human',
  destination: process.env.LOG_DESTINATION || 'both',
  filename: `mcp_server_${new Date().toISOString().split('T')[0]}.log`
});

// Set up logging (using the structured logger but maintaining backward compatibility)
const log = {
  info: (message) => logger.info(message),
  error: (message, error) => logger.error(message, error),
  debug: (message) => logger.debug(message)
};

// MCP server class
class MCPServer {
  constructor(options = {}) {
    this.port = options.port || DEFAULT_PORT;
    this.host = options.host || DEFAULT_HOST;
    this.transport = options.transport || 'stdio';
    this.dbConnections = new Map();
    this.emitter = new EventEmitter();
    this.setupEventHandlers();
  }

  // Set up event handlers for the MCP protocol
  setupEventHandlers() {
    this.emitter.on('tool_call', async (message) => {
      try {
        const { tool_name, tool_input, tool_call_id } = message;
        log.debug(`Tool call received: ${tool_name}`);
        
        // Find the appropriate tool handler
        const toolHandler = this.tools[tool_name];
        if (!toolHandler) {
          throw new Error(`Unknown tool: ${tool_name}`);
        }

        // Call the tool handler
        const result = await toolHandler.call(this, tool_input);
        
        // Send the tool result
        this.sendToolResult({ tool_call_id, result });
      } catch (error) {
        log.error('Error handling tool call', error);
        this.sendToolError(message.tool_call_id, error.message);
      }
    });
  }

  // Get a database connection, creating if needed
  getDbConnection(dbName) {
    if (!dbName) {
      throw new Error('Database name is required');
    }

    // Validate dbName to prevent path traversal
    if (dbName.includes('/') || dbName.includes('\\')) {
      throw new Error('Invalid database name');
    }

    const dbPath = path.join(DB_DIR, `${dbName}.sqlite`);
    
    // Check if db exists
    if (!fs.existsSync(dbPath)) {
      throw new Error(`Database ${dbName} does not exist`);
    }
    
    // Return cached connection or create new one
    if (this.dbConnections.has(dbName)) {
      return this.dbConnections.get(dbName);
    }

    log.info(`Opening database: ${dbPath}`);
    const db = new sqlite3.Database(dbPath, (err) => {
      if (err) {
        log.error(`Error opening database: ${dbPath}`, err);
        throw err;
      }
    });

    // Enable foreign keys
    db.exec('PRAGMA foreign_keys = ON;');
    
    // Store in connection cache
    this.dbConnections.set(dbName, db);
    return db;
  }

  // Close all database connections
  closeAllConnections() {
    this.dbConnections.forEach((db, name) => {
      log.info(`Closing database connection: ${name}`);
      db.close();
    });
    this.dbConnections.clear();
  }

  // Parse and handle incoming MCP messages
  handleMessage(message) {
    try {
      const parsed = JSON.parse(message);
      log.debug(`Received message type: ${parsed.type}`);
      
      switch (parsed.type) {
        case 'tool_call':
          this.emitter.emit('tool_call', parsed);
          break;
        case 'permission_request':
          // Auto-approve all permission requests
          this.sendPermissionGrant(parsed.permission_request_id);
          break;
        case 'ping':
          this.sendPong(parsed.ping_id);
          break;
        default:
          log.error(`Unknown message type: ${parsed.type}`);
      }
    } catch (error) {
      log.error('Error parsing message', error);
    }
  }

  // Send a tool result message
  sendToolResult({ tool_call_id, result }) {
    const message = {
      type: 'tool_result',
      tool_call_id,
      result
    };
    this.sendMessage(message);
  }

  // Send a tool error message
  sendToolError(tool_call_id, error) {
    const message = {
      type: 'tool_error',
      tool_call_id,
      error
    };
    this.sendMessage(message);
  }

  // Send a permission grant message
  sendPermissionGrant(permission_request_id) {
    const message = {
      type: 'permission_grant',
      permission_request_id
    };
    this.sendMessage(message);
  }

  // Send a pong response
  sendPong(ping_id) {
    const message = {
      type: 'pong',
      ping_id
    };
    this.sendMessage(message);
  }

  // Start the server with the specified transport
  start() {
    log.info(`Starting MCP server with ${this.transport} transport`);
    
    if (this.transport === 'http') {
      this.startHttpServer();
    } else if (this.transport === 'stdio') {
      this.startStdioTransport();
    } else {
      throw new Error(`Unsupported transport: ${this.transport}`);
    }
    
    // Send server ready message
    this.sendServerReady();
  }

  // Start HTTP transport
  startHttpServer() {
    const server = createServer((req, res) => {
      if (req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk.toString(); });
        req.on('end', () => {
          this.handleMessage(body);
          res.end('OK');
        });
      } else {
        res.statusCode = 404;
        res.end('Not found');
      }
    });
    
    server.listen(this.port, this.host, () => {
      log.info(`HTTP server listening on ${this.host}:${this.port}`);
    });
    
    this.httpServer = server;
  }

  // Start stdio transport
  startStdioTransport() {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: false
    });
    
    rl.on('line', (line) => {
      if (line.trim()) {
        this.handleMessage(line);
      }
    });
    
    rl.on('close', () => {
      log.info('stdin closed, shutting down');
      this.closeAllConnections();
      process.exit(0);
    });
    
    this.rl = rl;
  }

  // Send an MCP message based on the transport
  sendMessage(message) {
    const json = JSON.stringify(message);
    
    if (this.transport === 'stdio') {
      console.log(json);
    } else if (this.transport === 'http' && this.currentResponse) {
      this.currentResponse.write(json);
      this.currentResponse.end();
    }
  }

  // Send the server_ready message with tools specification
  sendServerReady() {
    const toolSpecs = {};
    
    // Define tool specifications based on this.tools
    Object.entries(this.tools).forEach(([name, handler]) => {
      toolSpecs[name] = {
        description: handler.description,
        input_schema: handler.inputSchema
      };
    });
    
    const message = {
      type: 'server_ready',
      tools: toolSpecs
    };
    
    this.sendMessage(message);
  }

  // Tool definitions
  tools = {
    // List available databases
    list_databases: {
      description: 'List all available databases in the ingestor system',
      inputSchema: {
        type: 'object',
        properties: {},
        required: []
      },
      async call() {
        log.info('Listing databases');
        
        try {
          const files = fs.readdirSync(DB_DIR);
          const databases = files
            .filter(file => file.endsWith('.sqlite'))
            .map(file => file.replace('.sqlite', ''));
          
          return { databases };
        } catch (error) {
          log.error('Error listing databases', error);
          throw new Error(`Failed to list databases: ${error.message}`);
        }
      }
    },
    
    // Get database schema
    get_database_schema: {
      description: 'Get the schema of a specific database',
      inputSchema: {
        type: 'object',
        properties: {
          database: { type: 'string', description: 'Database name' }
        },
        required: ['database']
      },
      async call({ database }) {
        log.info(`Getting schema for database: ${database}`);
        
        try {
          const db = this.getDbConnection(database);
          
          // Query for tables
          const tables = await new Promise((resolve, reject) => {
            db.all(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
              (err, rows) => {
                if (err) reject(err);
                else resolve(rows.map(row => row.name));
              }
            );
          });
          
          // Get schema for each table
          const schema = {};
          for (const table of tables) {
            const tableInfo = await new Promise((resolve, reject) => {
              db.all(`PRAGMA table_info(${table})`, (err, rows) => {
                if (err) reject(err);
                else resolve(rows);
              });
            });
            
            schema[table] = tableInfo.map(col => ({
              name: col.name,
              type: col.type,
              notNull: Boolean(col.notnull),
              defaultValue: col.dflt_value,
              primaryKey: Boolean(col.pk)
            }));
          }
          
          return { schema };
        } catch (error) {
          log.error(`Error getting schema for ${database}`, error);
          throw new Error(`Failed to get schema: ${error.message}`);
        }
      }
    },
    
    // Execute a select query
    query_database: {
      description: 'Execute a SELECT query on a database',
      inputSchema: {
        type: 'object',
        properties: {
          database: { type: 'string', description: 'Database name' },
          query: { type: 'string', description: 'SQL SELECT query' },
          params: { 
            type: 'array', 
            items: { type: 'any' },
            description: 'Query parameters for prepared statement'
          }
        },
        required: ['database', 'query']
      },
      async call({ database, query, params = [] }) {
        log.info(`Executing query on database ${database}: ${query}`);
        
        // Security check - only allow SELECT statements
        if (!query.trim().toLowerCase().startsWith('select')) {
          throw new Error('Only SELECT queries are allowed');
        }
        
        try {
          const db = this.getDbConnection(database);
          
          const results = await new Promise((resolve, reject) => {
            db.all(query, params, (err, rows) => {
              if (err) reject(err);
              else resolve(rows);
            });
          });
          
          return { results };
        } catch (error) {
          log.error(`Error executing query on ${database}`, error);
          throw new Error(`Query failed: ${error.message}`);
        }
      }
    },
    
    // Get database statistics
    get_database_stats: {
      description: 'Get statistics about a database',
      inputSchema: {
        type: 'object',
        properties: {
          database: { type: 'string', description: 'Database name' }
        },
        required: ['database']
      },
      async call({ database }) {
        log.info(`Getting stats for database: ${database}`);
        
        try {
          const db = this.getDbConnection(database);
          
          // Get tables
          const tables = await new Promise((resolve, reject) => {
            db.all(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
              (err, rows) => {
                if (err) reject(err);
                else resolve(rows.map(row => row.name));
              }
            );
          });
          
          // Get count for each table
          const tableCounts = {};
          for (const table of tables) {
            const count = await new Promise((resolve, reject) => {
              db.get(`SELECT COUNT(*) as count FROM ${table}`, (err, row) => {
                if (err) reject(err);
                else resolve(row.count);
              });
            });
            
            tableCounts[table] = count;
          }
          
          // Get database file size
          const dbPath = path.join(DB_DIR, `${database}.sqlite`);
          const stats = fs.statSync(dbPath);
          const sizeInMB = (stats.size / (1024 * 1024)).toFixed(2);
          
          return {
            database_name: database,
            file_size_mb: sizeInMB,
            tables: tables.length,
            table_counts: tableCounts,
            last_modified: stats.mtime
          };
        } catch (error) {
          log.error(`Error getting stats for ${database}`, error);
          throw new Error(`Failed to get stats: ${error.message}`);
        }
      }
    },
    
    // Search across databases
    search_content: {
      description: 'Search for content across databases',
      inputSchema: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search query' },
          databases: { 
            type: 'array', 
            items: { type: 'string' },
            description: 'List of databases to search (empty for all)'
          },
          content_types: {
            type: 'array',
            items: { type: 'string' },
            description: 'Content types to search (text, image, video, etc.)'
          },
          limit: { type: 'number', description: 'Maximum results to return' }
        },
        required: ['query']
      },
      async call({ query, databases = [], content_types = [], limit = 50 }) {
        log.info(`Searching for "${query}" across ${databases.length ? databases.join(', ') : 'all databases'}`);
        
        try {
          // Get all databases if none specified
          if (databases.length === 0) {
            const files = fs.readdirSync(DB_DIR);
            databases = files
              .filter(file => file.endsWith('.sqlite'))
              .map(file => file.replace('.sqlite', ''));
          }
          
          const results = [];
          
          for (const dbName of databases) {
            try {
              const db = this.getDbConnection(dbName);
              
              // Check if FTS tables exist
              const ftsTablesQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts'";
              const ftsTables = await new Promise((resolve, reject) => {
                db.all(ftsTablesQuery, (err, rows) => {
                  if (err) reject(err);
                  else resolve(rows.map(row => row.name));
                });
              });
              
              // Search in FTS tables if they exist
              for (const ftsTable of ftsTables) {
                // Get base table name
                const baseTable = ftsTable.replace('_fts', '');
                
                // Skip if content_types filter is provided and doesn't include this type
                if (content_types.length > 0 && !content_types.includes(baseTable)) {
                  continue;
                }
                
                const searchQuery = `
                  SELECT 
                    '${dbName}' as database,
                    '${baseTable}' as content_type,
                    id,
                    file_path,
                    filename,
                    snippet(${ftsTable}, 2, '<mark>', '</mark>', '...', 15) as snippet
                  FROM ${ftsTable}
                  WHERE ${ftsTable} MATCH ?
                  LIMIT ?
                `;
                
                const tableResults = await new Promise((resolve, reject) => {
                  db.all(searchQuery, [`${query}*`, limit], (err, rows) => {
                    if (err) {
                      // FTS error is not fatal, just log and continue
                      log.error(`FTS search error in ${dbName}.${ftsTable}`, err);
                      resolve([]);
                    } else {
                      resolve(rows);
                    }
                  });
                });
                
                results.push(...tableResults);
              }
              
              // Also search in regular tables if no FTS tables or if FTS doesn't cover all tables
              const regularTablesQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE '%_fts' AND name NOT LIKE 'sqlite_%'";
              const regularTables = await new Promise((resolve, reject) => {
                db.all(regularTablesQuery, (err, rows) => {
                  if (err) reject(err);
                  else resolve(rows.map(row => row.name));
                });
              });
              
              for (const table of regularTables) {
                // Skip if content_types filter is provided and doesn't include this type
                if (content_types.length > 0 && !content_types.includes(table)) {
                  continue;
                }
                
                // Get columns for this table
                const columnsQuery = `PRAGMA table_info(${table})`;
                const columns = await new Promise((resolve, reject) => {
                  db.all(columnsQuery, (err, rows) => {
                    if (err) reject(err);
                    else resolve(rows.map(row => row.name));
                  });
                });
                
                // Search in text columns
                const textColumns = columns.filter(col => 
                  col === 'content' || col === 'analysis' || col === 'metadata' || 
                  col === 'filename' || col === 'file_path'
                );
                
                if (textColumns.length > 0) {
                  const whereConditions = textColumns.map(col => `${col} LIKE ?`).join(' OR ');
                  const searchParams = textColumns.map(() => `%${query}%`);
                  
                  const searchQuery = `
                    SELECT 
                      '${dbName}' as database,
                      '${table}' as content_type,
                      id,
                      ${columns.includes('file_path') ? 'file_path' : 'NULL as file_path'},
                      ${columns.includes('filename') ? 'filename' : 'NULL as filename'}
                    FROM ${table}
                    WHERE ${whereConditions}
                    LIMIT ?
                  `;
                  
                  const tableResults = await new Promise((resolve, reject) => {
                    db.all(searchQuery, [...searchParams, limit], (err, rows) => {
                      if (err) {
                        // Regular search error is not fatal, just log and continue
                        log.error(`Regular search error in ${dbName}.${table}`, err);
                        resolve([]);
                      } else {
                        resolve(rows);
                      }
                    });
                  });
                  
                  // Add a simple snippet for regular search results
                  for (const row of tableResults) {
                    if (!row.snippet) {
                      // Find which column had the match
                      for (const col of textColumns) {
                        const colValue = await new Promise((resolve) => {
                          db.get(`SELECT ${col} FROM ${table} WHERE id = ?`, [row.id], (err, result) => {
                            if (err || !result) resolve(null);
                            else resolve(result[col]);
                          });
                        });
                        
                        if (colValue && typeof colValue === 'string' && colValue.toLowerCase().includes(query.toLowerCase())) {
                          // Create a simple snippet
                          const start = Math.max(0, colValue.toLowerCase().indexOf(query.toLowerCase()) - 30);
                          const end = Math.min(colValue.length, start + query.length + 60);
                          let snippet = colValue.substring(start, end);
                          
                          if (start > 0) snippet = '...' + snippet;
                          if (end < colValue.length) snippet = snippet + '...';
                          
                          // Highlight the match
                          const regex = new RegExp(query, 'gi');
                          row.snippet = snippet.replace(regex, '<mark>$&</mark>');
                          break;
                        }
                      }
                      
                      // If no snippet was created, add a placeholder
                      if (!row.snippet) {
                        row.snippet = `Match found in ${table}`;
                      }
                    }
                  }
                  
                  results.push(...tableResults);
                }
              }
            } catch (error) {
              // Log error but continue with other databases
              log.error(`Error searching database ${dbName}`, error);
            }
          }
          
          // Sort results by relevance (currently just limiting to max results)
          const limitedResults = results.slice(0, limit);
          
          return { 
            query,
            total_results: results.length,
            results: limitedResults
          };
        } catch (error) {
          log.error(`Error searching content`, error);
          throw new Error(`Search failed: ${error.message}`);
        }
      }
    },
    
    // Get content details
    get_content_details: {
      description: 'Get detailed information about a specific content item',
      inputSchema: {
        type: 'object',
        properties: {
          database: { type: 'string', description: 'Database name' },
          content_type: { type: 'string', description: 'Content type (table name)' },
          id: { type: 'number', description: 'Content ID' }
        },
        required: ['database', 'content_type', 'id']
      },
      async call({ database, content_type, id }) {
        log.info(`Getting content details for ${database}.${content_type} ID: ${id}`);
        
        try {
          const db = this.getDbConnection(database);
          
          // Validate content type exists
          const tableCheck = await new Promise((resolve, reject) => {
            db.get(
              "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
              [content_type],
              (err, row) => {
                if (err) reject(err);
                else resolve(row);
              }
            );
          });
          
          if (!tableCheck) {
            throw new Error(`Content type '${content_type}' does not exist in database '${database}'`);
          }
          
          // Get content details
          const content = await new Promise((resolve, reject) => {
            db.get(`SELECT * FROM ${content_type} WHERE id = ?`, [id], (err, row) => {
              if (err) reject(err);
              else resolve(row);
            });
          });
          
          if (!content) {
            throw new Error(`Content with ID ${id} not found in ${content_type}`);
          }
          
          // Check if content has analysis JSON
          if (content.analysis) {
            try {
              content.analysis = JSON.parse(content.analysis);
            } catch (e) {
              // If not valid JSON, leave as is
              log.debug(`Analysis is not valid JSON for ${content_type} ID: ${id}`);
            }
          }
          
          // Check if content has metadata JSON
          if (content.metadata) {
            try {
              content.metadata = JSON.parse(content.metadata);
            } catch (e) {
              // If not valid JSON, leave as is
              log.debug(`Metadata is not valid JSON for ${content_type} ID: ${id}`);
            }
          }
          
          return { content };
        } catch (error) {
          log.error(`Error getting content details`, error);
          throw new Error(`Failed to get content details: ${error.message}`);
        }
      }
    },
    
    // Execute ingestor command
    run_ingestor: {
      description: 'Execute ingestor command with given arguments',
      inputSchema: {
        type: 'object',
        properties: {
          args: { 
            type: 'array', 
            items: { type: 'string' },
            description: 'Ingestor command arguments'
          }
        },
        required: ['args']
      },
      async call({ args }) {
        log.info(`Running ingestor command with args: ${args.join(' ')}`);
        
        try {
          // Get path to ingestor script
          const ingestorPath = path.join(__dirname, '..', 'ingestor');
          
          // Check if script exists
          if (!fs.existsSync(ingestorPath)) {
            throw new Error(`Ingestor script not found at: ${ingestorPath}`);
          }
          
          // Execute ingestor command
          const result = execSync(`${ingestorPath} ${args.join(' ')}`, { 
            encoding: 'utf-8',
            maxBuffer: 10 * 1024 * 1024 // 10MB buffer
          });
          
          return { output: result };
        } catch (error) {
          log.error(`Error running ingestor command`, error);
          
          return { 
            error: true, 
            message: error.message,
            output: error.stdout || '',
            stderr: error.stderr || ''
          };
        }
      }
    },
    
    // Process content with ingestor
    process_content: {
      description: 'Process content using the ingestor system',
      inputSchema: {
        type: 'object',
        properties: {
          content: { type: 'string', description: 'Content to process' },
          content_type: { type: 'string', description: 'Content type hint' },
          database: { type: 'string', description: 'Target database name' }
        },
        required: ['content', 'database']
      },
      async call({ content, content_type, database }) {
        log.info(`Processing content for database: ${database}`);
        
        try {
          // Generate a temporary file name
          const tempDir = path.join(INGESTOR_HOME, 'tmp');
          if (!fs.existsSync(tempDir)) {
            fs.mkdirSync(tempDir, { recursive: true });
          }
          
          // Create a unique filename with appropriate extension
          const hash = crypto.createHash('md5').update(content).digest('hex');
          let extension = '.txt';
          
          if (content_type) {
            switch (content_type.toLowerCase()) {
              case 'json':
                extension = '.json';
                break;
              case 'xml':
                extension = '.xml';
                break;
              case 'html':
                extension = '.html';
                break;
              case 'python':
                extension = '.py';
                break;
              case 'javascript':
                extension = '.js';
                break;
              // Add more extensions as needed
            }
          }
          
          const tempFilePath = path.join(tempDir, `claude_content_${hash}${extension}`);
          
          // Write content to temp file
          fs.writeFileSync(tempFilePath, content, 'utf-8');
          
          // Process the file with ingestor
          const ingestorPath = path.join(__dirname, '..', 'ingestor');
          const result = execSync(`${ingestorPath} --file "${tempFilePath}" --database ${database}`, { 
            encoding: 'utf-8' 
          });
          
          // Clean up temp file
          fs.unlinkSync(tempFilePath);
          
          return { 
            success: true, 
            output: result,
            database
          };
        } catch (error) {
          log.error(`Error processing content`, error);
          
          return { 
            success: false, 
            error: error.message,
            output: error.stdout || '',
            stderr: error.stderr || ''
          };
        }
      }
    }
  };
}

// Get command line arguments
const args = process.argv.slice(2);
const options = {
  port: DEFAULT_PORT,
  host: DEFAULT_HOST,
  transport: 'stdio'
};

// Parse command line arguments
for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  
  if (arg === '--port' && i + 1 < args.length) {
    options.port = parseInt(args[i + 1], 10);
    i++;
  } else if (arg === '--host' && i + 1 < args.length) {
    options.host = args[i + 1];
    i++;
  } else if (arg === '--transport' && i + 1 < args.length) {
    options.transport = args[i + 1];
    i++;
  } else if (arg === '--help') {
    console.log(`
Ingestor MCP Server

Usage:
  node ingestor_mcp_server.js [options]

Options:
  --port PORT          Port for HTTP transport (default: ${DEFAULT_PORT})
  --host HOST          Host for HTTP transport (default: ${DEFAULT_HOST})
  --transport TYPE     Transport type: stdio or http (default: stdio)
  --help               Show this help message
    `);
    process.exit(0);
  }
}

// Check for required npm packages
try {
  require.resolve('sqlite3');
} catch (error) {
  console.error('Error: Required package "sqlite3" is not installed.');
  console.error('Please install it by running: npm install sqlite3');
  process.exit(1);
}

// Show startup message
log.info('Starting Ingestor MCP Server');
log.info(`Transport: ${options.transport}`);
if (options.transport === 'http') {
  log.info(`Host: ${options.host}`);
  log.info(`Port: ${options.port}`);
}

// Create and start the server
const server = new MCPServer(options);
server.start();

// Handle process termination
process.on('SIGINT', () => {
  log.info('Received SIGINT, shutting down');
  server.closeAllConnections();
  process.exit(0);
});

process.on('SIGTERM', () => {
  log.info('Received SIGTERM, shutting down');
  server.closeAllConnections();
  process.exit(0);
});

// Expose server for testing
module.exports = server;