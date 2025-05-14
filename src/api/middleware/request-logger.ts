/**
 * Request Logger Middleware
 * 
 * Logs all incoming API requests.
 */

import { Request, Response, NextFunction } from 'express';
import { Logger } from '../../core/logging/Logger';

const logger = new Logger('api:request');

/**
 * Middleware to log API request details
 */
export const requestLogger = (req: Request, res: Response, next: NextFunction) => {
  // Don't log health check or static asset requests
  if (req.path === '/health' || req.path.startsWith('/api/docs')) {
    return next();
  }

  // Capture start time
  const start = Date.now();
  
  // Log request details
  const requestInfo = {
    method: req.method,
    path: req.path,
    query: Object.keys(req.query).length ? req.query : undefined,
    ip: req.ip,
    userAgent: req.get('user-agent'),
  };
  
  logger.info('API request', requestInfo);
  
  // Record response status and timing
  res.on('finish', () => {
    const duration = Date.now() - start;
    const responseInfo = {
      ...requestInfo,
      status: res.statusCode,
      duration: `${duration}ms`,
    };
    
    // Use appropriate log level based on status code
    if (res.statusCode >= 500) {
      logger.error('API response', responseInfo);
    } else if (res.statusCode >= 400) {
      logger.warn('API response', responseInfo);
    } else {
      logger.debug('API response', responseInfo);
    }
  });
  
  next();
};