/**
 * API Key Authentication Middleware
 * 
 * Validates API keys for authentication.
 */

import { Request, Response, NextFunction } from 'express';
import config from '../config';
import { Logger } from '../../core/logging/Logger';

const logger = new Logger('api:auth');

/**
 * Middleware to authenticate requests using API keys
 */
export const apiKeyAuth = (req: Request, res: Response, next: NextFunction) => {
  // Get the API key from the request header
  const apiKey = req.header(config.apiKeys.headerName);
  
  // If no API key is provided, skip this authentication method
  if (!apiKey) {
    return next(new Error('No API key provided'));
  }
  
  // Check if the API key is valid
  // In a production environment, this would typically check against a database
  if (config.apiKeys.validKeys.includes(apiKey)) {
    // Add API key info to the request object
    (req as any).apiKey = {
      id: apiKey,
      // In a real implementation, you'd also add the key owner, permissions, etc.
    };
    
    logger.debug('API key authentication successful', {
      keyId: apiKey.substring(0, 8) + '...',
    });
    
    return next();
  }
  
  // Invalid API key
  logger.warn('Invalid API key', {
    keyId: apiKey.substring(0, 8) + '...',
    ip: req.ip,
  });
  
  // Return 401 Unauthorized
  return res.status(401).json({
    success: false,
    error: {
      code: 'INVALID_API_KEY',
      message: 'Invalid API key',
    },
  });
};