/**
 * Database service for the ingestor system
 * Provides SQLite database operations
 */

import { Database, open } from 'sqlite';
import sqlite3 from 'sqlite3';
import * as fs from 'fs/promises';
import * as path from 'path';
import { Logger } from '../logging';

/**
 * Service for interacting with SQLite databases
 */
export class DatabaseService {
  private logger: Logger;
  private db?: Database<sqlite3.Database>;
  private dbPath?: string;
  private connected: boolean = false;
  
  /**
   * Creates a new DatabaseService instance
   * @param logger Logger instance
   * @param dbPath Optional database path to connect immediately
   */
  constructor(logger: Logger, dbPath?: string) {
    this.logger = logger;
    this.dbPath = dbPath;
    
    if (dbPath) {
      this.connect(dbPath).catch(err => {
        this.logger.error(`Failed to connect to database: ${err.message}`);
      });
    }
  }
  
  /**
   * Connect to a SQLite database
   * @param dbPath Path to the database file
   */
  public async connect(dbPath: string): Promise<void> {
    if (this.connected) {
      await this.disconnect();
    }
    
    try {
      // Ensure the directory exists
      const dbDir = path.dirname(dbPath);
      await fs.mkdir(dbDir, { recursive: true });
      
      this.logger.info(`Connecting to database: ${dbPath}`);
      this.db = await open({
        filename: dbPath,
        driver: sqlite3.Database
      });
      
      // Enable foreign keys
      await this.db.exec('PRAGMA foreign_keys = ON');
      
      this.dbPath = dbPath;
      this.connected = true;
      
      this.logger.info('Database connection established');
    } catch (error) {
      this.logger.error(`Failed to connect to database: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Disconnect from the database
   */
  public async disconnect(): Promise<void> {
    if (this.db && this.connected) {
      try {
        await this.db.close();
        this.connected = false;
        this.logger.info('Database connection closed');
      } catch (error) {
        this.logger.error(`Failed to close database connection: ${error instanceof Error ? error.message : 'Unknown error'}`);
        throw error;
      }
    }
  }
  
  /**
   * Execute a SQL query
   * @param sql SQL query
   * @param params Query parameters
   * @returns Query result
   */
  public async query(sql: string, params: any[] = []): Promise<any> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      this.logger.debug(`Executing SQL query: ${sql.substring(0, 100)}${sql.length > 100 ? '...' : ''}`);
      
      // Determine query type (SELECT or other)
      const queryType = sql.trim().toUpperCase().startsWith('SELECT') ? 'all' : 'run';
      
      if (queryType === 'all') {
        return await this.db.all(sql, params);
      } else {
        return await this.db.run(sql, params);
      }
    } catch (error) {
      this.logger.error(`SQL query failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Execute a query and return a single row
   * @param sql SQL query
   * @param params Query parameters
   * @returns Single row or undefined
   */
  public async queryOne(sql: string, params: any[] = []): Promise<any> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      this.logger.debug(`Executing SQL query (single row): ${sql.substring(0, 100)}${sql.length > 100 ? '...' : ''}`);
      return await this.db.get(sql, params);
    } catch (error) {
      this.logger.error(`SQL query failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Execute a batch of SQL statements
   * @param statements SQL statements to execute
   */
  public async executeBatch(statements: string[]): Promise<void> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      // Begin transaction
      await this.db.exec('BEGIN TRANSACTION');
      
      // Execute each statement
      for (const sql of statements) {
        await this.db.exec(sql);
      }
      
      // Commit transaction
      await this.db.exec('COMMIT');
      
      this.logger.debug(`Executed batch of ${statements.length} SQL statements`);
    } catch (error) {
      // Rollback on error
      if (this.db && this.connected) {
        await this.db.exec('ROLLBACK');
      }
      
      this.logger.error(`Batch execution failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Initialize database schema
   * @param schemaPath Path to the schema SQL file
   */
  public async initSchema(schemaPath: string): Promise<void> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      this.logger.info(`Initializing database schema from ${schemaPath}`);
      
      // Read schema file
      const schemaSql = await fs.readFile(schemaPath, 'utf-8');
      
      // Execute schema SQL
      await this.db.exec(schemaSql);
      
      this.logger.info('Database schema initialized');
    } catch (error) {
      this.logger.error(`Failed to initialize schema: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Check if a table exists
   * @param tableName Name of the table to check
   */
  public async tableExists(tableName: string): Promise<boolean> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      const result = await this.db.get(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName]
      );
      
      return !!result;
    } catch (error) {
      this.logger.error(`Failed to check table existence: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Get the current database path
   */
  public getDbPath(): string | undefined {
    return this.dbPath;
  }
  
  /**
   * Check if database is connected
   */
  public isConnected(): boolean {
    return this.connected;
  }
  
  /**
   * Store an entity in the database
   * @param name Entity name
   * @param type Entity type
   * @param description Entity description
   * @returns Entity ID or null if storage failed
   */
  public async storeEntity(name: string, type: string, description: string = ''): Promise<number | null> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      this.logger.debug(`Storing entity: ${name} (${type})`);
      
      // Check if entity already exists
      const existing = await this.queryOne(
        'SELECT id FROM entities WHERE name = ? AND entity_type = ? LIMIT 1',
        [name, type]
      );
      
      if (existing) {
        this.logger.debug(`Entity already exists with ID ${existing.id}`);
        return existing.id;
      }
      
      // Insert new entity
      const result = await this.query(
        'INSERT INTO entities (name, entity_type, description, created_at) VALUES (?, ?, ?, datetime(\'now\')) RETURNING id',
        [name, type, description]
      );
      
      if (result && result.length > 0) {
        const entityId = result[0].id;
        this.logger.debug(`Entity stored with ID ${entityId}`);
        return entityId;
      }
      
      return null;
    } catch (error) {
      this.logger.error(`Failed to store entity: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return null;
    }
  }
  
  /**
   * Link an entity to content
   * @param entityId Entity ID
   * @param contentId Content ID
   * @param contentType Content type
   * @param relevance Relevance score
   * @param context Context text
   * @returns True if successful, false otherwise
   */
  public async linkEntityToContent(
    entityId: number,
    contentId: number,
    contentType: string,
    relevance: number = 0.5,
    context: string = ''
  ): Promise<boolean> {
    if (!this.db || !this.connected) {
      throw new Error('Database not connected');
    }
    
    try {
      this.logger.debug(`Linking entity ${entityId} to content ${contentId} (${contentType})`);
      
      // Check if link already exists
      const existing = await this.queryOne(
        'SELECT id FROM content_entities WHERE content_id = ? AND content_type = ? AND entity_id = ?',
        [contentId, contentType, entityId]
      );
      
      if (existing) {
        // Update existing link
        await this.query(
          'UPDATE content_entities SET relevance = ?, context = ?, updated_at = datetime(\'now\') WHERE id = ?',
          [relevance, context, existing.id]
        );
      } else {
        // Create new link
        await this.query(
          'INSERT INTO content_entities (content_id, content_type, entity_id, relevance, context, created_at) VALUES (?, ?, ?, ?, ?, datetime(\'now\'))',
          [contentId, contentType, entityId, relevance, context]
        );
      }
      
      return true;
    } catch (error) {
      this.logger.error(`Failed to link entity to content: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
}