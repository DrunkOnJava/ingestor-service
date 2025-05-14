/**
 * Database Controller Tests
 * 
 * Tests the database controller functionality
 */
import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { Request, Response } from 'express';
import fs from 'fs';
import path from 'path';
import { databaseController } from '../../../src/api/controllers/database';
import { DatabaseService } from '../../../src/core/services/DatabaseService';
import { DatabaseInitializer } from '../../../src/core/database/DatabaseInitializer';
import { DatabaseOptimizer } from '../../../src/core/database/DatabaseOptimizer';

// Mock dependencies
jest.mock('fs');
jest.mock('path');
jest.mock('../../../src/core/services/DatabaseService');
jest.mock('../../../src/core/database/DatabaseInitializer');
jest.mock('../../../src/core/database/DatabaseOptimizer');

describe('Database Controller', () => {
  // Setup mock request, response, and next function
  let req: Partial<Request>;
  let res: Partial<Response>;
  let next: jest.Mock;
  
  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();
    
    // Setup request, response, and next function mocks
    req = {
      params: {},
      body: {}
    };
    
    res = {
      json: jest.fn().mockReturnThis(),
      status: jest.fn().mockReturnThis()
    };
    
    next = jest.fn();
    
    // Setup fs mock
    (fs.existsSync as jest.Mock).mockReturnValue(true);
    (fs.readdirSync as jest.Mock).mockReturnValue(['test.sqlite', 'test2.db']);
    (fs.statSync as jest.Mock).mockReturnValue({
      size: 1024,
      mtime: new Date()
    });
    (fs.mkdirSync as jest.Mock).mockReturnValue(undefined);
    (fs.copyFileSync as jest.Mock).mockReturnValue(undefined);
    
    // Setup path mock
    (path.join as jest.Mock).mockImplementation((...args) => args.join('/'));
    (path.basename as jest.Mock).mockImplementation((file, ext) => {
      if (ext) {
        return file.replace(ext, '');
      }
      return file;
    });
    (path.extname as jest.Mock).mockImplementation((file) => {
      const parts = file.split('.');
      return parts.length > 1 ? `.${parts[parts.length - 1]}` : '';
    });
  });
  
  afterEach(() => {
    jest.resetAllMocks();
  });
  
  it('should list databases', async () => {
    // Call the listDatabases function
    await databaseController.listDatabases(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        databases: expect.arrayContaining([
          expect.objectContaining({
            name: expect.any(String),
            path: expect.any(String),
            size: expect.any(Number),
            modified: expect.any(Date)
          })
        ])
      })
    });
    
    // Verify fs functions were called correctly
    expect(fs.readdirSync).toHaveBeenCalled();
    expect(fs.statSync).toHaveBeenCalled();
  });
  
  it('should get database schema', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    const mockSchema = { tables: ['table1', 'table2'] };
    const mockDbService = {
      getSchema: jest.fn().mockResolvedValue(mockSchema)
    };
    (DatabaseService as jest.Mock).mockImplementation(() => mockDbService);
    
    // Call the getDatabaseSchema function
    await databaseController.getDatabaseSchema(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: {
        database: 'test',
        schema: mockSchema
      }
    });
    
    // Verify database service was called
    expect(mockDbService.getSchema).toHaveBeenCalled();
  });
  
  it('should initialize a database', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    req.body = { force: true };
    const mockInitializer = {
      initialize: jest.fn().mockResolvedValue(undefined)
    };
    (DatabaseInitializer as jest.Mock).mockImplementation(() => mockInitializer);
    
    // Call the initializeDatabase function
    await databaseController.initializeDatabase(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        database: 'test',
        message: expect.stringContaining('initialized')
      })
    });
    
    // Verify initializer was called with correct params
    expect(mockInitializer.initialize).toHaveBeenCalledWith('test', true);
  });
  
  it('should handle error when database not found', async () => {
    // Setup mocks
    req.params = { database: 'nonexistent' };
    (fs.existsSync as jest.Mock).mockReturnValue(false);
    
    // Call the getDatabaseSchema function
    await databaseController.getDatabaseSchema(req as Request, res as Response, next);
    
    // Verify error response
    expect(res.status).toHaveBeenCalledWith(404);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: expect.objectContaining({
        code: 'DATABASE_NOT_FOUND',
        message: expect.stringContaining('not found')
      })
    });
  });
  
  it('should optimize a database', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    const mockOptimizer = {
      optimize: jest.fn().mockResolvedValue({ 
        indexesCreated: 2, 
        tablesCleaned: 3 
      })
    };
    (DatabaseOptimizer as jest.Mock).mockImplementation(() => mockOptimizer);
    
    // Call the optimizeDatabase function
    await databaseController.optimizeDatabase(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        database: 'test',
        message: expect.stringContaining('optimized'),
        result: expect.objectContaining({
          indexesCreated: 2,
          tablesCleaned: 3
        })
      })
    });
    
    // Verify optimizer was called with correct params
    expect(mockOptimizer.optimize).toHaveBeenCalledWith('test');
  });
  
  it('should execute a valid database query', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    req.body = { 
      query: 'SELECT * FROM entities WHERE type = ?', 
      params: ['person'] 
    };
    const mockResults = [{ id: 1, name: 'Test Entity' }];
    const mockDbService = {
      query: jest.fn().mockResolvedValue(mockResults)
    };
    (DatabaseService as jest.Mock).mockImplementation(() => mockDbService);
    
    // Call the queryDatabase function
    await databaseController.queryDatabase(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: {
        database: 'test',
        result: mockResults
      }
    });
    
    // Verify db service was called with correct params
    expect(mockDbService.query).toHaveBeenCalledWith(
      'SELECT * FROM entities WHERE type = ?', 
      ['person']
    );
  });
  
  it('should reject non-SELECT queries', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    req.body = { 
      query: 'DELETE FROM entities', 
      params: [] 
    };
    
    // Call the queryDatabase function
    await databaseController.queryDatabase(req as Request, res as Response, next);
    
    // Verify error response
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: expect.objectContaining({
        code: 'INVALID_QUERY',
        message: expect.stringContaining('SELECT')
      })
    });
  });
  
  it('should handle backup database operation', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    
    // Call the backupDatabase function
    await databaseController.backupDatabase(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        database: 'test',
        backup: expect.any(String),
        message: expect.stringContaining('backed up')
      })
    });
    
    // Verify fs functions were called
    expect(fs.mkdirSync).toHaveBeenCalled();
    expect(fs.copyFileSync).toHaveBeenCalled();
  });
  
  it('should handle database operations', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    req.body = { operation: 'vacuum' };
    const mockDbService = {
      vacuum: jest.fn().mockResolvedValue({ bytesFreed: 1024 })
    };
    (DatabaseService as jest.Mock).mockImplementation(() => mockDbService);
    
    // Call the performDatabaseOperation function
    await databaseController.performDatabaseOperation(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        database: 'test',
        operation: 'vacuum',
        message: expect.stringContaining('executed'),
        result: expect.objectContaining({
          bytesFreed: 1024
        })
      })
    });
    
    // Verify db service was called
    expect(mockDbService.vacuum).toHaveBeenCalled();
  });
  
  it('should reject invalid operation types', async () => {
    // Setup mocks
    req.params = { database: 'test' };
    req.body = { operation: 'invalid_operation' };
    
    // Call the performDatabaseOperation function
    await databaseController.performDatabaseOperation(req as Request, res as Response, next);
    
    // Verify error response
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: expect.objectContaining({
        code: 'INVALID_OPERATION',
        message: expect.stringContaining('Unsupported operation')
      })
    });
  });
});