/**
 * Database Controller
 * 
 * Handles database operations and management
 */
import { Request, Response, NextFunction } from 'express';
import path from 'path';
import fs from 'fs';
import { Logger } from '../../core/logging';
import { DatabaseService } from '../../core/services/DatabaseService';
import { DatabaseInitializer } from '../../core/database/DatabaseInitializer';
import { DatabaseOptimizer } from '../../core/database/DatabaseOptimizer';
import config from '../config';

// Create logger
const logger = new Logger('database-controller');

/**
 * List available databases
 */
const listDatabases = async (req: Request, res: Response, next: NextFunction) => {
  try {
    // Get database directory from config
    const dbDir = config.database.directory;
    
    // Create directory if it doesn't exist
    if (!fs.existsSync(dbDir)) {
      fs.mkdirSync(dbDir, { recursive: true });
    }
    
    // Get all SQLite database files
    const files = fs.readdirSync(dbDir)
      .filter(file => file.endsWith('.sqlite') || file.endsWith('.db'))
      .map(file => ({
        name: path.basename(file, path.extname(file)),
        path: path.join(dbDir, file),
        size: fs.statSync(path.join(dbDir, file)).size,
        modified: fs.statSync(path.join(dbDir, file)).mtime
      }));
    
    // Return database list
    res.json({
      success: true,
      data: {
        databases: files
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Get database schema
 */
const getDatabaseSchema = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    
    // Check if database exists
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'DATABASE_NOT_FOUND',
          message: `Database '${database}' not found`
        }
      });
    }
    
    // Create database service
    const dbService = new DatabaseService(database);
    
    // Get schema information
    const schema = await dbService.getSchema();
    
    // Return schema
    res.json({
      success: true,
      data: {
        database,
        schema
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Get database statistics
 */
const getDatabaseStats = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    
    // Check if database exists
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'DATABASE_NOT_FOUND',
          message: `Database '${database}' not found`
        }
      });
    }
    
    // Create database service
    const dbService = new DatabaseService(database);
    
    // Get statistics
    const stats = await dbService.getStatistics();
    
    // Return statistics
    res.json({
      success: true,
      data: {
        database,
        stats
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Initialize database
 */
const initializeDatabase = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    const { force } = req.body || {};
    
    // Get database path
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    
    // Check if database exists and not forcing
    if (fs.existsSync(dbPath) && !force) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'DATABASE_EXISTS',
          message: `Database '${database}' already exists. Use 'force: true' to reinitialize.`
        }
      });
    }
    
    // Create directory if it doesn't exist
    if (!fs.existsSync(config.database.directory)) {
      fs.mkdirSync(config.database.directory, { recursive: true });
    }
    
    // Initialize database
    const initializer = new DatabaseInitializer();
    await initializer.initialize(database, force);
    
    // Return success
    res.json({
      success: true,
      data: {
        database,
        message: `Database '${database}' successfully initialized`
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Query database
 */
const queryDatabase = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    const { query, params } = req.body;
    
    // Check if database exists
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'DATABASE_NOT_FOUND',
          message: `Database '${database}' not found`
        }
      });
    }
    
    // Validate query to ensure it's a SELECT
    if (!query.trim().toLowerCase().startsWith('select')) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'INVALID_QUERY',
          message: 'Only SELECT queries are allowed'
        }
      });
    }
    
    // Create database service
    const dbService = new DatabaseService(database);
    
    // Execute query
    const result = await dbService.query(query, params);
    
    // Return results
    res.json({
      success: true,
      data: {
        database,
        result
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Optimize database
 */
const optimizeDatabase = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    
    // Check if database exists
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'DATABASE_NOT_FOUND',
          message: `Database '${database}' not found`
        }
      });
    }
    
    // Optimize database
    const optimizer = new DatabaseOptimizer();
    const result = await optimizer.optimize(database);
    
    // Return success
    res.json({
      success: true,
      data: {
        database,
        message: `Database '${database}' successfully optimized`,
        result
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Backup database
 */
const backupDatabase = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    
    // Check if database exists
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'DATABASE_NOT_FOUND',
          message: `Database '${database}' not found`
        }
      });
    }
    
    // Create backup directory if it doesn't exist
    const backupDir = path.join(config.database.directory, 'backups');
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }
    
    // Create backup filename with timestamp
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupFile = path.join(backupDir, `${database}_${timestamp}.sqlite`);
    
    // Copy database file
    fs.copyFileSync(dbPath, backupFile);
    
    // Return success
    res.json({
      success: true,
      data: {
        database,
        backup: backupFile,
        message: `Database '${database}' successfully backed up to '${backupFile}'`
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Perform database operation
 */
const performDatabaseOperation = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { database } = req.params;
    const { operation, options } = req.body;
    
    // Check if database exists
    const dbPath = path.join(config.database.directory, `${database}.sqlite`);
    if (!fs.existsSync(dbPath)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'DATABASE_NOT_FOUND',
          message: `Database '${database}' not found`
        }
      });
    }
    
    // Create database service
    const dbService = new DatabaseService(database);
    
    // Switch on operation type
    let result;
    switch (operation) {
      case 'vacuum':
        result = await dbService.vacuum();
        break;
      case 'analyze':
        result = await dbService.analyze();
        break;
      case 'reindex':
        result = await dbService.reindex(options?.table);
        break;
      case 'compact':
        result = await dbService.compact();
        break;
      default:
        return res.status(400).json({
          success: false,
          error: {
            code: 'INVALID_OPERATION',
            message: `Unsupported operation: ${operation}`
          }
        });
    }
    
    // Return success
    res.json({
      success: true,
      data: {
        database,
        operation,
        message: `Operation '${operation}' successfully executed on database '${database}'`,
        result
      }
    });
    
  } catch (error) {
    next(error);
  }
};

// Export controller
export const databaseController = {
  listDatabases,
  getDatabaseSchema,
  getDatabaseStats,
  initializeDatabase,
  queryDatabase,
  optimizeDatabase,
  backupDatabase,
  performDatabaseOperation
};