/**
 * Error Handler Middleware Tests
 * 
 * Tests the error handling middleware for the API
 */
import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { Request, Response } from 'express';
import { errorHandler } from '../../../src/api/middleware/error-handler';
import { Logger } from '../../../src/core/logging';

// Mock dependencies
jest.mock('../../../src/core/logging', () => ({
  Logger: jest.fn().mockImplementation(() => ({
    error: jest.fn(),
    warn: jest.fn(),
    info: jest.fn(),
    debug: jest.fn()
  }))
}));

describe('Error Handler Middleware', () => {
  // Setup mock request, response, and next function
  let req: Partial<Request>;
  let res: Partial<Response>;
  let next: jest.Mock;
  
  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();
    
    // Setup request, response, and next function mocks
    req = {};
    
    res = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis()
    };
    
    next = jest.fn();
  });
  
  it('should handle simple Error objects', () => {
    // Create error
    const error = new Error('Test error');
    
    // Call error handler
    errorHandler(error, req as Request, res as Response, next);
    
    // Verify response
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Test error'
      }
    });
    
    // Verify logging
    const logger = (Logger as jest.Mock).mock.instances[0];
    expect(logger.error).toHaveBeenCalled();
  });
  
  it('should handle errors with status code', () => {
    // Create error with status code
    const error = new Error('Not found error');
    (error as any).statusCode = 404;
    
    // Call error handler
    errorHandler(error, req as Request, res as Response, next);
    
    // Verify response
    expect(res.status).toHaveBeenCalledWith(404);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'NOT_FOUND',
        message: 'Not found error'
      }
    });
  });
  
  it('should handle errors with error code', () => {
    // Create error with custom code
    const error = new Error('Validation error');
    (error as any).statusCode = 400;
    (error as any).code = 'VALIDATION_ERROR';
    
    // Call error handler
    errorHandler(error, req as Request, res as Response, next);
    
    // Verify response
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Validation error'
      }
    });
  });
  
  it('should handle errors with details', () => {
    // Create error with details
    const error = new Error('Validation error');
    (error as any).statusCode = 400;
    (error as any).code = 'VALIDATION_ERROR';
    (error as any).details = [
      { field: 'name', message: 'Name is required' },
      { field: 'email', message: 'Email is invalid' }
    ];
    
    // Call error handler
    errorHandler(error, req as Request, res as Response, next);
    
    // Verify response
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Validation error',
        details: [
          { field: 'name', message: 'Name is required' },
          { field: 'email', message: 'Email is invalid' }
        ]
      }
    });
  });
  
  it('should map HTTP status codes to error codes', () => {
    // Test cases for different status codes
    const testCases = [
      { statusCode: 400, expectedCode: 'BAD_REQUEST' },
      { statusCode: 401, expectedCode: 'UNAUTHORIZED' },
      { statusCode: 403, expectedCode: 'FORBIDDEN' },
      { statusCode: 404, expectedCode: 'NOT_FOUND' },
      { statusCode: 409, expectedCode: 'CONFLICT' },
      { statusCode: 422, expectedCode: 'UNPROCESSABLE_ENTITY' },
      { statusCode: 429, expectedCode: 'TOO_MANY_REQUESTS' },
      { statusCode: 500, expectedCode: 'INTERNAL_SERVER_ERROR' },
      { statusCode: 503, expectedCode: 'SERVICE_UNAVAILABLE' }
    ];
    
    for (const testCase of testCases) {
      // Reset mocks
      jest.clearAllMocks();
      
      // Create error with status code
      const error = new Error(`Error with status ${testCase.statusCode}`);
      (error as any).statusCode = testCase.statusCode;
      
      // Call error handler
      errorHandler(error, req as Request, res as Response, next);
      
      // Verify response
      expect(res.status).toHaveBeenCalledWith(testCase.statusCode);
      expect(res.json).toHaveBeenCalledWith({
        success: false,
        error: {
          code: testCase.expectedCode,
          message: `Error with status ${testCase.statusCode}`
        }
      });
    }
  });
  
  it('should sanitize error messages in production', () => {
    // Store original NODE_ENV
    const originalNodeEnv = process.env.NODE_ENV;
    
    try {
      // Set NODE_ENV to production
      process.env.NODE_ENV = 'production';
      
      // Create error with sensitive information
      const error = new Error('Database error: password=secret123');
      
      // Call error handler
      errorHandler(error, req as Request, res as Response, next);
      
      // Verify response has sanitized message
      expect(res.json).toHaveBeenCalledWith({
        success: false,
        error: {
          code: 'INTERNAL_SERVER_ERROR',
          message: 'An internal server error occurred'
        }
      });
      
      // Verify original error was still logged
      const logger = (Logger as jest.Mock).mock.instances[0];
      expect(logger.error).toHaveBeenCalledWith(
        expect.stringContaining('Database error: password=secret123')
      );
    } finally {
      // Restore original NODE_ENV
      process.env.NODE_ENV = originalNodeEnv;
    }
  });
  
  it('should handle non-Error objects', () => {
    // Create a non-Error object
    const nonError = { message: 'Not an Error object' };
    
    // Call error handler
    errorHandler(nonError as any, req as Request, res as Response, next);
    
    // Verify response
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Not an Error object'
      }
    });
  });
});