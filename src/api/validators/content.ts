/**
 * Content Validators
 * 
 * Validation middleware for content-related requests.
 */

import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';
import { ApiError } from '../middleware/error-handler';
import config from '../config';

/**
 * Schema for content creation validation
 */
const createContentSchema = Joi.object({
  content: Joi.string().required(),
  
  type: Joi.string()
    .valid(...config.processing.allowedTypes)
    .required()
    .messages({
      'any.required': 'Content type is required',
      'any.only': `Content type must be one of: ${config.processing.allowedTypes.join(', ')}`,
    }),
  
  filename: Joi.string().optional(),
  
  metadata: Joi.object({
    title: Joi.string().optional(),
    description: Joi.string().optional(),
    tags: Joi.array().items(Joi.string()).optional(),
  }).optional(),
  
  processingOptions: Joi.object({
    extractEntities: Joi.boolean().default(true),
    enableChunking: Joi.boolean().default(true),
    chunkSize: Joi.number().integer().min(1000).max(1000000).default(config.processing.defaultChunkSize),
    chunkOverlap: Joi.number().integer().min(0).max(50000).default(config.processing.defaultChunkOverlap),
    chunkStrategy: Joi.string().valid('size', 'paragraph', 'sentence').default('size'),
  }).optional(),
});

/**
 * Schema for content update validation
 */
const updateContentSchema = Joi.object({
  metadata: Joi.object({
    title: Joi.string().optional(),
    description: Joi.string().optional(),
    tags: Joi.array().items(Joi.string()).optional(),
  }).required(),
});

/**
 * Validate content creation request
 */
export const validateContentCreate = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = createContentSchema.validate(req.body, {
    abortEarly: false,
    stripUnknown: true,
  });
  
  if (error) {
    const details = error.details.map(detail => ({
      path: detail.path.join('.'),
      message: detail.message,
    }));
    
    return next(new ApiError('Validation error', 400, 'VALIDATION_ERROR', details));
  }
  
  // Update request body with validated and sanitized data
  req.body = value;
  next();
};

/**
 * Validate content update request
 */
export const validateContentUpdate = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = updateContentSchema.validate(req.body, {
    abortEarly: false,
    stripUnknown: true,
  });
  
  if (error) {
    const details = error.details.map(detail => ({
      path: detail.path.join('.'),
      message: detail.message,
    }));
    
    return next(new ApiError('Validation error', 400, 'VALIDATION_ERROR', details));
  }
  
  // Update request body with validated and sanitized data
  req.body = value;
  next();
};