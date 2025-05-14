/**
 * Processing Controller
 * 
 * Handles content processing, entity extraction, and batch processing operations
 */
import { Request, Response, NextFunction } from 'express';
import { v4 as uuid } from 'uuid';
import { Logger } from '../../core/logging';
import { ContentProcessor } from '../../core/content/ContentProcessor';
import { BatchProcessor } from '../../core/content/BatchProcessor';
import { EntityExtractor } from '../../core/entity/EntityExtractor';
import { EventType } from '../websocket';
import { getWebSocketManager } from '../index';

// Create logger
const logger = new Logger('processing-controller');

// Active processing jobs
const activeJobs = new Map<string, { 
  jobId: string;
  type: 'analyze' | 'extract' | 'batch';
  status: 'pending' | 'processing' | 'completed' | 'failed' | 'canceled';
  progress: number;
  startTime: Date;
  endTime?: Date;
  error?: string;
  result?: any;
}>();

/**
 * Process and analyze content
 */
const analyzeContent = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { content, contentType, options } = req.body;
    
    // Create job ID and tracking object
    const jobId = uuid();
    const job = {
      jobId,
      type: 'analyze' as const,
      status: 'pending' as const,
      progress: 0,
      startTime: new Date()
    };
    
    // Add to active jobs
    activeJobs.set(jobId, job);
    
    // Send initial response with job ID
    res.status(202).json({
      success: true,
      data: {
        jobId,
        status: job.status,
        message: 'Content analysis started'
      }
    });
    
    // Process content asynchronously
    processContentAsync(jobId, content, contentType, options);
    
  } catch (error) {
    next(error);
  }
};

/**
 * Extract entities from content
 */
const extractEntities = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { content, contentType, options } = req.body;
    
    // Create job ID and tracking object
    const jobId = uuid();
    const job = {
      jobId,
      type: 'extract' as const,
      status: 'pending' as const,
      progress: 0,
      startTime: new Date()
    };
    
    // Add to active jobs
    activeJobs.set(jobId, job);
    
    // Send initial response with job ID
    res.status(202).json({
      success: true,
      data: {
        jobId,
        status: job.status,
        message: 'Entity extraction started'
      }
    });
    
    // Extract entities asynchronously
    extractEntitiesAsync(jobId, content, contentType, options);
    
  } catch (error) {
    next(error);
  }
};

/**
 * Create a batch processing job
 */
const createBatchProcess = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { items, options } = req.body;
    
    // Create job ID and tracking object
    const jobId = uuid();
    const job = {
      jobId,
      type: 'batch' as const,
      status: 'pending' as const,
      progress: 0,
      startTime: new Date()
    };
    
    // Add to active jobs
    activeJobs.set(jobId, job);
    
    // Send initial response with job ID
    res.status(202).json({
      success: true,
      data: {
        jobId,
        status: job.status,
        message: 'Batch processing started',
        totalItems: items.length
      }
    });
    
    // Process batch asynchronously
    processBatchAsync(jobId, items, options);
    
  } catch (error) {
    next(error);
  }
};

/**
 * Get processing job status
 */
const getProcessingStatus = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { jobId } = req.params;
    
    // Check if job exists
    if (!activeJobs.has(jobId)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'JOB_NOT_FOUND',
          message: `Processing job ${jobId} not found`
        }
      });
    }
    
    // Get job status
    const job = activeJobs.get(jobId);
    
    // Return status
    res.json({
      success: true,
      data: {
        jobId: job.jobId,
        type: job.type,
        status: job.status,
        progress: job.progress,
        startTime: job.startTime,
        ...(job.endTime && { endTime: job.endTime }),
        ...(job.error && { error: job.error }),
        ...(job.status === 'completed' && { result: job.result })
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Cancel a processing job
 */
const cancelProcessing = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { jobId } = req.params;
    
    // Check if job exists
    if (!activeJobs.has(jobId)) {
      return res.status(404).json({
        success: false,
        error: {
          code: 'JOB_NOT_FOUND',
          message: `Processing job ${jobId} not found`
        }
      });
    }
    
    // Get job
    const job = activeJobs.get(jobId);
    
    // Can only cancel pending or processing jobs
    if (job.status !== 'pending' && job.status !== 'processing') {
      return res.status(400).json({
        success: false,
        error: {
          code: 'INVALID_JOB_STATE',
          message: `Cannot cancel job with status: ${job.status}`
        }
      });
    }
    
    // Update job status
    job.status = 'canceled';
    job.endTime = new Date();
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    const wsManager = getWebSocketManager();
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_CANCELED, {
        jobId: job.jobId,
        type: job.type,
        status: job.status
      });
    }
    
    // Return success
    res.json({
      success: true,
      data: {
        jobId: job.jobId,
        status: job.status,
        message: 'Processing job canceled'
      }
    });
    
  } catch (error) {
    next(error);
  }
};

/**
 * Process content asynchronously
 */
async function processContentAsync(jobId: string, content: string, contentType: string, options: any) {
  // Get job
  const job = activeJobs.get(jobId);
  
  // Update status to processing
  job.status = 'processing';
  activeJobs.set(jobId, job);
  
  // Notify via WebSocket
  const wsManager = getWebSocketManager();
  if (wsManager) {
    wsManager.broadcast(EventType.JOB_STARTED, {
      jobId,
      type: job.type,
      status: job.status
    });
  }
  
  try {
    // Create content processor
    const processor = new ContentProcessor();
    
    // Process content
    const result = await processor.process(content, contentType, options);
    
    // Update job with success result
    job.status = 'completed';
    job.progress = 100;
    job.endTime = new Date();
    job.result = result;
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_COMPLETED, {
        jobId,
        type: job.type,
        status: job.status,
        result: result
      });
    }
    
    logger.info(`Processing job ${jobId} completed successfully`);
    
  } catch (error) {
    // Update job with error result
    job.status = 'failed';
    job.endTime = new Date();
    job.error = error instanceof Error ? error.message : 'Unknown error';
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_FAILED, {
        jobId,
        type: job.type,
        status: job.status,
        error: job.error
      });
    }
    
    logger.error(`Processing job ${jobId} failed: ${job.error}`);
  }
}

/**
 * Extract entities asynchronously
 */
async function extractEntitiesAsync(jobId: string, content: string, contentType: string, options: any) {
  // Get job
  const job = activeJobs.get(jobId);
  
  // Update status to processing
  job.status = 'processing';
  activeJobs.set(jobId, job);
  
  // Notify via WebSocket
  const wsManager = getWebSocketManager();
  if (wsManager) {
    wsManager.broadcast(EventType.JOB_STARTED, {
      jobId,
      type: job.type,
      status: job.status
    });
  }
  
  try {
    // Create entity extractor
    const extractor = new EntityExtractor();
    
    // Extract entities
    const entities = await extractor.extract(content, contentType, options);
    
    // Update job with success result
    job.status = 'completed';
    job.progress = 100;
    job.endTime = new Date();
    job.result = { entities };
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_COMPLETED, {
        jobId,
        type: job.type,
        status: job.status,
        result: { entities }
      });
    }
    
    logger.info(`Entity extraction job ${jobId} completed successfully`);
    
  } catch (error) {
    // Update job with error result
    job.status = 'failed';
    job.endTime = new Date();
    job.error = error instanceof Error ? error.message : 'Unknown error';
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_FAILED, {
        jobId,
        type: job.type,
        status: job.status,
        error: job.error
      });
    }
    
    logger.error(`Entity extraction job ${jobId} failed: ${job.error}`);
  }
}

/**
 * Process batch asynchronously
 */
async function processBatchAsync(jobId: string, items: any[], options: any) {
  // Get job
  const job = activeJobs.get(jobId);
  
  // Update status to processing
  job.status = 'processing';
  activeJobs.set(jobId, job);
  
  // Notify via WebSocket
  const wsManager = getWebSocketManager();
  if (wsManager) {
    wsManager.broadcast(EventType.JOB_STARTED, {
      jobId,
      type: job.type,
      status: job.status
    });
  }
  
  try {
    // Create batch processor
    const processor = new BatchProcessor();
    
    // Subscribe to progress events
    processor.on('progress', (progress) => {
      // Update job progress
      job.progress = progress;
      activeJobs.set(jobId, job);
      
      // Notify via WebSocket
      if (wsManager) {
        wsManager.broadcast(EventType.JOB_PROGRESS, {
          jobId,
          type: job.type,
          status: job.status,
          progress
        });
      }
    });
    
    // Process batch
    const result = await processor.processBatch(items, options);
    
    // Update job with success result
    job.status = 'completed';
    job.progress = 100;
    job.endTime = new Date();
    job.result = result;
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_COMPLETED, {
        jobId,
        type: job.type,
        status: job.status,
        result
      });
    }
    
    logger.info(`Batch processing job ${jobId} completed successfully`);
    
  } catch (error) {
    // Update job with error result
    job.status = 'failed';
    job.endTime = new Date();
    job.error = error instanceof Error ? error.message : 'Unknown error';
    activeJobs.set(jobId, job);
    
    // Notify via WebSocket
    if (wsManager) {
      wsManager.broadcast(EventType.JOB_FAILED, {
        jobId,
        type: job.type,
        status: job.status,
        error: job.error
      });
    }
    
    logger.error(`Batch processing job ${jobId} failed: ${job.error}`);
  }
}

// Export controller
export const processingController = {
  analyzeContent,
  extractEntities,
  createBatchProcess,
  getProcessingStatus,
  cancelProcessing
};