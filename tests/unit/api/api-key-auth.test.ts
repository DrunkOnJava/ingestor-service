/**
 * API Key Authentication Middleware Tests
 * 
 * Tests the API key authentication middleware
 */
import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { Request, Response } from 'express';
import { apiKeyAuth } from '../../../src/api/middleware/api-key-auth';

// Mock dependencies
jest.mock('../../../src/core/services/DatabaseService', () => {
  return {
    DatabaseService: jest.fn().mockImplementation(() => ({
      query: jest.fn().mockImplementation((query, params) => {
        // Mock different responses based on the API key
        if (params && params[0] === 'valid-api-key') {
          return Promise.resolve([{
            id: 'api-key-id',
            key: 'valid-api-key',
            user_id: 'user123',
            name: 'Test API Key',
            expires_at: new Date(Date.now() + 86400000).toISOString() // expires tomorrow
          }]);
        } else if (params && params[0] === 'expired-api-key') {
          return Promise.resolve([{
            id: 'api-key-id',
            key: 'expired-api-key',
            user_id: 'user123',
            name: 'Expired API Key',
            expires_at: new Date(Date.now() - 86400000).toISOString() // expired yesterday
          }]);
        } else {
          return Promise.resolve([]);
        }
      })
    }))
  };
});

describe('API Key Authentication Middleware', () => {
  // Setup mock request, response, and next function
  let req: Partial<Request>;
  let res: Partial<Response>;
  let next: jest.Mock;
  
  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();
    
    // Setup request, response, and next function mocks
    req = {
      headers: {},
      get: jest.fn().mockImplementation((header) => {
        return req.headers?.[header.toLowerCase()];
      })
    };
    
    res = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis()
    };
    
    next = jest.fn();
  });
  
  afterEach(() => {
    jest.resetAllMocks();
  });
  
  it('should authenticate request with valid API key in header', async () => {
    // Setup request with valid API key
    req.headers = {
      'x-api-key': 'valid-api-key'
    };
    
    // Call the middleware
    await apiKeyAuth(req as Request, res as Response, next);
    
    // Verify that next was called (authentication successful)
    expect(next).toHaveBeenCalled();
    
    // Verify that user was added to request
    expect(req.user).toBeDefined();
    expect(req.user?.id).toBe('user123');
    expect(req.user?.apiKeyId).toBe('api-key-id');
  });
  
  it('should reject request with expired API key', async () => {
    // Setup request with expired API key
    req.headers = {
      'x-api-key': 'expired-api-key'
    };
    
    // Call the middleware
    await apiKeyAuth(req as Request, res as Response, next);
    
    // Verify that error response was sent
    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'API_KEY_EXPIRED',
        message: 'API key has expired'
      }
    });
    
    // Verify that next was called with error
    expect(next).toHaveBeenCalled();
    expect(next.mock.calls[0][0]).toBeDefined();
  });
  
  it('should reject request with invalid API key', async () => {
    // Setup request with invalid API key
    req.headers = {
      'x-api-key': 'invalid-api-key'
    };
    
    // Call the middleware
    await apiKeyAuth(req as Request, res as Response, next);
    
    // Verify that error response was sent
    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'INVALID_API_KEY',
        message: 'Invalid API key'
      }
    });
    
    // Verify that next was called with error
    expect(next).toHaveBeenCalled();
    expect(next.mock.calls[0][0]).toBeDefined();
  });
  
  it('should pass control to next middleware when no API key is provided', async () => {
    // Setup request with no API key
    req.headers = {};
    
    // Call the middleware
    await apiKeyAuth(req as Request, res as Response, next);
    
    // Verify that next was called without args (authentication skipped)
    expect(next).toHaveBeenCalled();
    expect(next.mock.calls[0][0]).toBeUndefined();
    
    // Verify that no user was added to request
    expect(req.user).toBeUndefined();
  });
  
  it('should handle database errors gracefully', async () => {
    // Setup request with API key
    req.headers = {
      'x-api-key': 'valid-api-key'
    };
    
    // Force database query to throw error
    const DatabaseService = require('../../../src/core/services/DatabaseService').DatabaseService;
    DatabaseService.mockImplementationOnce(() => ({
      query: jest.fn().mockRejectedValue(new Error('Database error'))
    }));
    
    // Call the middleware
    await apiKeyAuth(req as Request, res as Response, next);
    
    // Verify that error was passed to next
    expect(next).toHaveBeenCalled();
    expect(next.mock.calls[0][0]).toBeInstanceOf(Error);
    expect(next.mock.calls[0][0].message).toBe('Database error');
  });
});