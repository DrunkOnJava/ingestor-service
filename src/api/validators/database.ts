/**
 * Database Validators
 * 
 * Validation schemas and middleware for database operations
 */
import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';

// Schema for database query request
export const databaseQuerySchema = Joi.object({
  query: Joi.string()
    .min(1)
    .max(5000)
    .required()
    .description('SQL query to execute (SELECT only)'),
  
  params: Joi.object()
    .pattern(
      Joi.string(),
      Joi.alternatives().try(
        Joi.string(),
        Joi.number(),
        Joi.boolean(),
        Joi.date(),
        Joi.allow(null)
      )
    )
    .default({})
    .description('Query parameters')
});

// Schema for database operation request
export const databaseOperationSchema = Joi.object({
  operation: Joi.string()
    .valid('vacuum', 'analyze', 'reindex', 'compact')
    .required()
    .description('Database operation to perform'),
  
  options: Joi.object({
    table: Joi.string().min(1).max(100)
  })
  .default({})
  .description('Operation options')
});

/**
 * Validate database query middleware
 */
export const validateDatabaseQuery = (req: Request, res: Response, next: NextFunction) => {
  // Validate request body
  const { error, value } = databaseQuerySchema.validate(req.body, {
    abortEarly: false,
    stripUnknown: true,
    presence: 'required'
  });
  
  if (error) {
    // Format validation errors
    const errorDetails = error.details.map(detail => ({
      path: detail.path.join('.'),
      message: detail.message
    }));
    
    return res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid query request',
        details: errorDetails
      }
    });
  }
  
  // Check if query is SELECT only
  if (!value.query.trim().toLowerCase().startsWith('select')) {
    return res.status(400).json({
      success: false,
      error: {
        code: 'INVALID_QUERY',
        message: 'Only SELECT queries are allowed'
      }
    });
  }
  
  // Replace request body with validated value
  req.body = value;
  next();
};

/**
 * Validate database operation middleware
 */
export const validateDatabaseOperation = (req: Request, res: Response, next: NextFunction) => {
  // Validate request body
  const { error, value } = databaseOperationSchema.validate(req.body, {
    abortEarly: false,
    stripUnknown: true,
    presence: 'required'
  });
  
  if (error) {
    // Format validation errors
    const errorDetails = error.details.map(detail => ({
      path: detail.path.join('.'),
      message: detail.message
    }));
    
    return res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid operation request',
        details: errorDetails
      }
    });
  }
  
  // Replace request body with validated value
  req.body = value;
  next();
};