/**
 * Batch Validators
 * 
 * Validation middleware for batch processing requests
 */

import Joi from 'joi';
import { Request, Response, NextFunction } from 'express';
import { ApiError } from '../middleware/error-handler';

/**
 * Validation schema for batch process creation
 */
export const batchCreateSchema = Joi.object({
  type: Joi.string().required().valid(
    'folder-import',
    'url-crawl',
    'entity-extraction',
    'reprocess',
    'content-analysis'
  ).description('Type of batch process'),
  
  name: Joi.string().min(1).max(100).default(() => {
    const type = Joi.ref('type');
    return `${type} - ${new Date().toISOString()}`;
  }).description('Name of the batch process'),
  
  description: Joi.string().max(500)
    .description('Description of the batch process'),
  
  options: Joi.object().when('type', [
    {
      is: 'folder-import',
      then: Joi.object({
        path: Joi.string().required()
          .description('Path to the folder to import'),
        recursive: Joi.boolean().default(true)
          .description('Whether to recursively import subfolders'),
        fileTypes: Joi.array().items(Joi.string())
          .description('File types to import (e.g., .pdf, .docx)'),
        extractEntities: Joi.boolean().default(true)
          .description('Whether to extract entities from imported content'),
      }),
    },
    {
      is: 'url-crawl',
      then: Joi.object({
        urls: Joi.array().items(Joi.string().uri()).required()
          .description('URLs to crawl'),
        crawlDepth: Joi.number().integer().min(1).max(5).default(2)
          .description('Maximum crawl depth'),
        extractEntities: Joi.boolean().default(true)
          .description('Whether to extract entities from crawled content'),
      }),
    },
    {
      is: 'entity-extraction',
      then: Joi.object({
        contentIds: Joi.array().items(Joi.string().uuid()).required()
          .description('IDs of content items to extract entities from'),
      }),
    },
    {
      is: 'reprocess',
      then: Joi.object({
        contentIds: Joi.array().items(Joi.string().uuid()).required()
          .description('IDs of content items to reprocess'),
      }),
    },
    {
      is: 'content-analysis',
      then: Joi.object({
        contentIds: Joi.array().items(Joi.string().uuid())
          .description('IDs of content items to analyze'),
        filters: Joi.object({
          contentType: Joi.array().items(Joi.string())
            .description('Content types to include'),
          createdAfter: Joi.date().iso()
            .description('Include content created after this date'),
          createdBefore: Joi.date().iso()
            .description('Include content created before this date'),
        }),
      }),
    },
  ]).required().description('Batch process options'),
  
  priority: Joi.string().valid('low', 'normal', 'high').default('normal')
    .description('Priority of the batch process'),
  
  callback: Joi.object({
    url: Joi.string().uri().required()
      .description('Webhook URL to notify on batch completion'),
    headers: Joi.object()
      .description('Headers to include in the webhook request'),
  }).description('Webhook callback configuration'),
});

/**
 * Validator middleware for batch process creation
 */
export const validateBatchCreate = (req: Request, res: Response, next: NextFunction) => {
  const { error, value } = batchCreateSchema.validate(req.body, {
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