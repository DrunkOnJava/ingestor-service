/**
 * Error Handler Middleware
 * 
 * Centralized error handling for the API.
 * Converts various error types to a consistent API error response format.
 */

import { Request, Response, NextFunction } from 'express';
import { Logger } from '../../core/logging/Logger';

/**
 * Custom API error class with status code and error code
 */
export class ApiError extends Error {
  statusCode: number;
  code: string;
  details?: any;

  constructor(message: string, statusCode: number = 500, code: string = 'INTERNAL_SERVER_ERROR', details?: any) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

/**
 * Map of known error types to handler functions
 */
const errorHandlers: Record<string, (err: any) => Partial<ApiError>> = {
  // JWT errors
  'UnauthorizedError': (err) => ({
    statusCode: 401,
    code: 'UNAUTHORIZED',
    message: 'Invalid or missing authentication token',
  }),
  
  // Validation errors
  'ValidationError': (err) => ({
    statusCode: 400,
    code: 'VALIDATION_ERROR',
    message: 'Validation failed',
    details: err.details || err.errors,
  }),
  
  // Not found errors
  'NotFoundError': (err) => ({
    statusCode: 404,
    code: 'NOT_FOUND',
    message: err.message || 'Resource not found',
  }),
  
  // Database errors
  'DatabaseError': (err) => ({
    statusCode: 500,
    code: 'DATABASE_ERROR',
    message: 'Database operation failed',
  }),
  
  // File system errors
  'FileSystemError': (err) => ({
    statusCode: 500,
    code: 'FILESYSTEM_ERROR',
    message: 'File system operation failed',
  }),
  
  // Claude API errors
  'ClaudeApiError': (err) => ({
    statusCode: 502,
    code: 'CLAUDE_API_ERROR',
    message: 'Error communicating with Claude API',
    details: err.details,
  }),
};

/**
 * Global error handling middleware
 */
export const errorHandler = (err: any, req: Request, res: Response, next: NextFunction) => {
  const logger = new Logger('api:error-handler');
  
  // Log the error with a suitable level
  if (err.statusCode >= 500 || !err.statusCode) {
    logger.error('Server error', { 
      error: err.message, 
      stack: err.stack,
      path: req.path,
      method: req.method,
    });
  } else {
    logger.info('Client error', { 
      error: err.message, 
      code: err.code,
      path: req.path,
      method: req.method,
    });
  }
  
  // Handle ApiError directly
  if (err instanceof ApiError) {
    return res.status(err.statusCode).json({
      success: false,
      error: {
        code: err.code,
        message: err.message,
        details: err.details,
      },
    });
  }
  
  // Map known error types to ApiError
  const errorName = err.name || 'Error';
  const handler = errorHandlers[errorName];
  
  if (handler) {
    const errorInfo = handler(err);
    return res.status(errorInfo.statusCode || 500).json({
      success: false,
      error: {
        code: errorInfo.code || 'UNKNOWN_ERROR',
        message: errorInfo.message || 'An unexpected error occurred',
        details: errorInfo.details,
      },
    });
  }
  
  // Default fallback for unknown errors
  const statusCode = err.statusCode || 500;
  const errorCode = err.code || 'INTERNAL_SERVER_ERROR';
  const message = err.message || 'An unexpected error occurred';
  
  res.status(statusCode).json({
    success: false,
    error: {
      code: errorCode,
      message: statusCode === 500 ? 'An unexpected error occurred' : message,
      ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
    },
  });
};

/**
 * Not Found error handler
 */
export const notFoundHandler = (req: Request, res: Response) => {
  res.status(404).json({
    success: false,
    error: {
      code: 'NOT_FOUND',
      message: `Path not found: ${req.path}`,
    },
  });
};