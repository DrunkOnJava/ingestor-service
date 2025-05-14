/**
 * Processing Validators
 * 
 * Validation schemas and middleware for processing operations
 */
import { Request, Response, NextFunction } from 'express';
import Joi from 'joi';

// Schema for content processing request
export const processingRequestSchema = Joi.object({
  content: Joi.alternatives()
    .try(
      Joi.string().min(1).max(1000000),
      Joi.object({
        type: Joi.string().required(),
        data: Joi.string().required(),
        name: Joi.string(),
        size: Joi.number(),
        metadata: Joi.object()
      })
    )
    .required()
    .description('Content to process (string or content object)'),
  
  contentType: Joi.string()
    .valid('text', 'image', 'video', 'document', 'code', 'auto')
    .default('auto')
    .description('Type of content'),
  
  options: Joi.object({
    extractEntities: Joi.boolean().default(true),
    extractSentiment: Joi.boolean().default(false),
    extractKeywords: Joi.boolean().default(true),
    extractSummary: Joi.boolean().default(false),
    storeContent: Joi.boolean().default(true),
    database: Joi.string().min(1).max(100),
    customPrompt: Joi.string().max(5000),
    language: Joi.string(),
    contextLimit: Joi.number().min(1000).max(100000),
    confidenceThreshold: Joi.number().min(0).max(1).default(0.7),
    format: Joi.string().valid('json', 'text', 'markdown').default('json')
  })
  .default({})
  .description('Processing options')
});

// Schema for batch processing request
export const batchProcessingRequestSchema = Joi.object({
  items: Joi.array()
    .items(
      Joi.object({
        id: Joi.string().uuid(),
        content: Joi.alternatives()
          .try(
            Joi.string().min(1).max(1000000),
            Joi.object({
              type: Joi.string().required(),
              data: Joi.string().required(),
              name: Joi.string(),
              size: Joi.number(),
              metadata: Joi.object()
            })
          )
          .required(),
        contentType: Joi.string()
          .valid('text', 'image', 'video', 'document', 'code', 'auto')
          .default('auto'),
        options: Joi.object()
      })
    )
    .min(1)
    .max(100)
    .required()
    .description('Array of items to process'),
  
  options: Joi.object({
    parallelism: Joi.number().min(1).max(10).default(5),
    continueOnError: Joi.boolean().default(true),
    database: Joi.string().min(1).max(100),
    extractEntities: Joi.boolean().default(true),
    extractSentiment: Joi.boolean().default(false),
    extractKeywords: Joi.boolean().default(true),
    extractSummary: Joi.boolean().default(false),
    storeContent: Joi.boolean().default(true),
    confidenceThreshold: Joi.number().min(0).max(1).default(0.7)
  })
  .default({})
  .description('Batch processing options')
});

/**
 * Validate processing request middleware
 */
export const validateProcessingRequest = (req: Request, res: Response, next: NextFunction) => {
  // Determine which schema to use based on the route
  const schema = req.path.includes('/batch')
    ? batchProcessingRequestSchema
    : processingRequestSchema;
  
  // Validate request body
  const { error, value } = schema.validate(req.body, {
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
        message: 'Invalid request data',
        details: errorDetails
      }
    });
  }
  
  // Replace request body with validated value
  req.body = value;
  next();
};