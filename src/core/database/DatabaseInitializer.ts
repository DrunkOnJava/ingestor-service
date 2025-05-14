/**
 * Database initializer
 * Handles database creation and schema setup
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { Logger } from '../logging';
import { DatabaseService } from '../services';

/**
 * Class for initializing and setting up databases
 */
export class DatabaseInitializer {
  private logger: Logger;
  private dbService: DatabaseService;
  private schemasDir: string;
  
  /**
   * Creates a new DatabaseInitializer instance
   * @param logger Logger instance
   * @param dbService Database service
   * @param schemasDir Directory containing schema files
   */
  constructor(
    logger: Logger,
    dbService: DatabaseService,
    schemasDir: string = path.join(process.cwd(), 'config', 'schemas')
  ) {
    this.logger = logger;
    this.dbService = dbService;
    this.schemasDir = schemasDir;
  }
  
  /**
   * Initialize a database with the necessary schemas
   * @param dbPath Path to the database file
   */
  public async initializeDatabase(dbPath: string): Promise<void> {
    try {
      this.logger.info(`Initializing database at ${dbPath}`);
      
      // Connect to database
      await this.dbService.connect(dbPath);
      
      // Apply base schema
      await this.applyBaseSchema();
      
      // Apply entity schema
      await this.applyEntitySchema();
      
      // Apply content schema
      await this.applyContentSchema();
      
      // Apply search schema
      await this.applySearchSchema();
      
      this.logger.info('Database initialization complete');
    } catch (error) {
      this.logger.error(`Database initialization failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Apply the base database schema
   * @private
   */
  private async applyBaseSchema(): Promise<void> {
    try {
      this.logger.debug('Applying base database schema');
      
      const schemaPath = path.join(this.schemasDir, 'base_schema.sql');
      if (await this.fileExists(schemaPath)) {
        await this.dbService.initSchema(schemaPath);
      } else {
        this.logger.warning(`Base schema file not found: ${schemaPath}`);
        
        // Apply default base schema
        const baseSchema = `
          -- Create base tables and settings
          PRAGMA foreign_keys = ON;
          
          -- Database metadata
          CREATE TABLE IF NOT EXISTS db_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
          
          -- Insert metadata
          INSERT OR REPLACE INTO db_metadata (key, value) VALUES 
            ('schema_version', '1.0'),
            ('created_at', datetime('now')),
            ('ingestor_version', '1.0.0');
        `;
        
        await this.dbService.query(baseSchema);
      }
    } catch (error) {
      this.logger.error(`Failed to apply base schema: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Apply the entity schema
   * @private
   */
  private async applyEntitySchema(): Promise<void> {
    try {
      this.logger.debug('Applying entity schema');
      
      const schemaPath = path.join(this.schemasDir, 'entity_schema.sql');
      if (await this.fileExists(schemaPath)) {
        await this.dbService.initSchema(schemaPath);
      } else {
        this.logger.warning(`Entity schema file not found: ${schemaPath}`);
        
        // Apply default entity schema
        const entitySchema = `
          -- Entity tables
          
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
          
          -- Create indexes for entity lookups
          CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name);
          CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type);
          CREATE INDEX IF NOT EXISTS idx_entities_type_name ON entities(entity_type, name);
          
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
          
          -- Create indexes for content-entity lookups
          CREATE INDEX IF NOT EXISTS idx_content_entities_content ON content_entities(content_id, content_type);
          CREATE INDEX IF NOT EXISTS idx_content_entities_entity ON content_entities(entity_id);
        `;
        
        await this.dbService.query(entitySchema);
      }
      
      // Apply entity indexes
      await this.applyEntityIndexes();
    } catch (error) {
      this.logger.error(`Failed to apply entity schema: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Apply the content schema
   * @private
   */
  private async applyContentSchema(): Promise<void> {
    try {
      this.logger.debug('Applying content schema');
      
      const schemaPath = path.join(this.schemasDir, 'content_schema.sql');
      if (await this.fileExists(schemaPath)) {
        await this.dbService.initSchema(schemaPath);
      } else {
        this.logger.warning(`Content schema file not found: ${schemaPath}`);
        
        // Apply default content schema
        const contentSchema = `
          -- Content tables
          
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
          
          -- Create indexes for content lookups
          CREATE INDEX IF NOT EXISTS idx_content_type ON content(content_type);
          CREATE INDEX IF NOT EXISTS idx_content_source ON content(source);
          CREATE INDEX IF NOT EXISTS idx_content_hash ON content(hash);
          
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
          
          -- Create indexes for chunk lookups
          CREATE INDEX IF NOT EXISTS idx_chunks_content_id ON content_chunks(content_id);
          CREATE INDEX IF NOT EXISTS idx_chunks_content_index ON content_chunks(content_id, chunk_index);
          
          -- Content tags
          CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
          
          -- Content-tag relationships
          CREATE TABLE IF NOT EXISTS content_tags (
            content_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            PRIMARY KEY (content_id, tag_id),
            FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE,
            FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
          );
          
          -- Create indexes for tag lookups
          CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
          CREATE INDEX IF NOT EXISTS idx_content_tags_tag ON content_tags(tag_id);
        `;
        
        await this.dbService.query(contentSchema);
      }
    } catch (error) {
      this.logger.error(`Failed to apply content schema: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Apply the search schema
   * @private
   */
  private async applySearchSchema(): Promise<void> {
    try {
      this.logger.debug('Applying search schema');
      
      const schemaPath = path.join(this.schemasDir, 'search_schema.sql');
      if (await this.fileExists(schemaPath)) {
        await this.dbService.initSchema(schemaPath);
      } else {
        this.logger.warning(`Search schema file not found: ${schemaPath}`);
        
        // Apply default search schema
        const searchSchema = `
          -- Full-text search tables
          
          -- Content search
          CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
            title, 
            description, 
            content,
            content='content_chunks',
            content_rowid='id'
          );
          
          -- Create triggers to keep FTS in sync
          
          -- Insert trigger
          CREATE TRIGGER IF NOT EXISTS content_fts_insert
          AFTER INSERT ON content_chunks
          BEGIN
            INSERT INTO content_fts(rowid, title, description, content)
            SELECT 
              new.id,
              (SELECT title FROM content WHERE id = new.content_id),
              (SELECT description FROM content WHERE id = new.content_id),
              new.chunk_text
            ;
          END;
          
          -- Delete trigger
          CREATE TRIGGER IF NOT EXISTS content_fts_delete
          AFTER DELETE ON content_chunks
          BEGIN
            DELETE FROM content_fts WHERE rowid = old.id;
          END;
          
          -- Update trigger
          CREATE TRIGGER IF NOT EXISTS content_fts_update
          AFTER UPDATE ON content_chunks
          BEGIN
            DELETE FROM content_fts WHERE rowid = old.id;
            INSERT INTO content_fts(rowid, title, description, content)
            SELECT 
              new.id,
              (SELECT title FROM content WHERE id = new.content_id),
              (SELECT description FROM content WHERE id = new.content_id),
              new.chunk_text
            ;
          END;
          
          -- Content title/description update trigger
          CREATE TRIGGER IF NOT EXISTS content_meta_update
          AFTER UPDATE OF title, description ON content
          BEGIN
            -- Update all FTS entries for this content
            UPDATE content_fts
            SET 
              title = new.title,
              description = new.description
            WHERE rowid IN (SELECT id FROM content_chunks WHERE content_id = new.id);
          END;
          
          -- Search terms table to track search history
          CREATE TABLE IF NOT EXISTS search_terms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term TEXT NOT NULL,
            search_count INTEGER DEFAULT 1,
            last_searched_at TEXT NOT NULL DEFAULT (datetime('now')),
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
          
          -- Create indexes for search terms
          CREATE INDEX IF NOT EXISTS idx_search_terms ON search_terms(term);
        `;
        
        await this.dbService.query(searchSchema);
      }
    } catch (error) {
      this.logger.error(`Failed to apply search schema: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Apply entity indexes
   * @private
   */
  private async applyEntityIndexes(): Promise<void> {
    try {
      this.logger.debug('Applying entity indexes');
      
      const indexPath = path.join(this.schemasDir, 'entity_indexes.sql');
      if (await this.fileExists(indexPath)) {
        await this.dbService.initSchema(indexPath);
      } else {
        this.logger.warning(`Entity indexes file not found: ${indexPath}`);
        
        // Apply default entity indexes
        const entityIndexes = `
          -- Additional entity indexes for optimization
          
          -- Add index for entity creation date
          CREATE INDEX IF NOT EXISTS idx_entities_creation_date ON entities(created_at);
          
          -- Add index for content-entity relevance
          CREATE INDEX IF NOT EXISTS idx_content_entities_relevance ON content_entities(relevance);
          
          -- Add compound index for content lookup
          CREATE INDEX IF NOT EXISTS idx_content_entities_lookup ON content_entities(content_id, content_type, entity_id);
        `;
        
        await this.dbService.query(entityIndexes);
      }
    } catch (error) {
      this.logger.error(`Failed to apply entity indexes: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Check if a file exists
   * @param filePath Path to check
   * @private
   */
  private async fileExists(filePath: string): Promise<boolean> {
    try {
      await fs.access(filePath);
      return true;
    } catch {
      return false;
    }
  }
}