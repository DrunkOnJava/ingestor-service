/**
 * Authentication Validators
 * 
 * Validation middleware for authentication-related requests.
 */

import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';
import { ApiError } from '../middleware/error-handler';

/**
 * Schema for login validation
 */
const loginSchema = Joi.object({
  username: Joi.string().required().messages({
    'any.required': 'Username is required',
  }),
  
  password: Joi.string().required().messages({
    'any.required': 'Password is required',
  }),
});

/**
 * Schema for user registration validation
 */
const registerSchema = Joi.object({
  username: Joi.string()
    .min(3)
    .max(30)
    .pattern(/^[a-zA-Z0-9_]+$/)
    .required()
    .messages({
      'any.required': 'Username is required',
      'string.min': 'Username must be at least 3 characters long',
      'string.max': 'Username cannot exceed 30 characters',
      'string.pattern.base': 'Username can only contain letters, numbers, and underscores',
    }),
  
  password: Joi.string()
    .min(8)
    .required()
    .messages({
      'any.required': 'Password is required',
      'string.min': 'Password must be at least 8 characters long',
    }),
  
  role: Joi.string()
    .valid('user', 'admin')
    .default('user')
    .messages({
      'any.only': 'Role must be either "user" or "admin"',
    }),
});

/**
 * Schema for password change validation
 */
const changePasswordSchema = Joi.object({
  currentPassword: Joi.string().required().messages({
    'any.required': 'Current password is required',
  }),
  
  newPassword: Joi.string()
    .min(8)
    .required()
    .disallow(Joi.ref('currentPassword'))
    .messages({
      'any.required': 'New password is required',
      'string.min': 'New password must be at least 8 characters long',
      'any.invalid': 'New password must be different from the current password',
    }),
});

/**
 * Validate login request
 */
export const validateLogin = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = loginSchema.validate(req.body, {
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
 * Validate registration request
 */
export const validateRegister = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = registerSchema.validate(req.body, {
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
 * Validate password change request
 */
export const validateChangePassword = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = changePasswordSchema.validate(req.body, {
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