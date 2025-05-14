/**
 * Entity Validators
 * 
 * Validation middleware for entity-related requests
 */

import Joi from 'joi';
import { Request, Response, NextFunction } from 'express';
import { ApiError } from '../middleware/error-handler';

/**
 * Validation schema for entity creation
 */
export const entityCreateSchema = Joi.object({
  name: Joi.string().required().min(1).max(100)
    .description('Name of the entity'),
  
  type: Joi.string().required().min(1).max(50)
    .description('Type of the entity (e.g., person, organization, etc.)'),
  
  properties: Joi.object().default({})
    .description('Additional properties for the entity'),
  
  contentIds: Joi.array().items(Joi.string().uuid())
    .description('IDs of content items to associate with this entity'),
});

/**
 * Validation schema for entity update
 */
export const entityUpdateSchema = Joi.object({
  name: Joi.string().min(1).max(100)
    .description('Name of the entity'),
  
  type: Joi.string().min(1).max(50)
    .description('Type of the entity (e.g., person, organization, etc.)'),
  
  properties: Joi.object()
    .description('Additional properties for the entity'),
});

/**
 * Validation schema for relationship creation
 */
export const relationshipCreateSchema = Joi.object({
  sourceId: Joi.string().uuid().required()
    .description('ID of the source entity'),
  
  targetId: Joi.string().uuid().required()
    .description('ID of the target entity'),
  
  type: Joi.string().required().min(1).max(50)
    .description('Type of the relationship'),
  
  properties: Joi.object().default({})
    .description('Additional properties for the relationship'),
});

/**
 * Validator middleware for entity creation
 */
export const validateEntityCreate = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = entityCreateSchema.validate(req.body, {
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
  
  // Update request body with validated and sanitized values
  req.body = value;
  
  next();
};

/**
 * Validator middleware for entity update
 */
export const validateEntityUpdate = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = entityUpdateSchema.validate(req.body, {
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
  
  // Update request body with validated and sanitized values
  req.body = value;
  
  next();
};

/**
 * Validator middleware for relationship creation
 */
export const validateRelationshipCreate = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = relationshipCreateSchema.validate(req.body, {
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
  
  // Update request body with validated and sanitized values
  req.body = value;
  
  next();
};