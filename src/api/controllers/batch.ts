/**
 * Batch Controller
 * 
 * Handles batch processing operations such as folder imports, bulk content processing,
 * and entity extraction across multiple content items.
 */

import { Request, Response, NextFunction } from 'express';
import { v4 as uuid } from 'uuid';
import { ApiError } from '../middleware/error-handler';
import { Logger } from '../../core/logging/Logger';
import { BatchRepository } from '../../core/services/BatchRepository';
import { BatchProcessorFactory } from '../../core/services/BatchProcessorFactory';
import { getWebSocketManager, EventType } from '../websocket';
import config from '../config';

// Initialize logger
const logger = new Logger('api:controller:batch');

// Helper function for pagination
const getPaginationParams = (req: Request) => {
  const limit = Math.min(
    parseInt(req.query.limit as string || '20', 10),
    config.batch.maxPageSize
  );
  const offset = parseInt(req.query.offset as string || '0', 10);
  const sort = (req.query.sort as string) || 'createdAt';
  const order = (req.query.order as string) || 'desc';
  
  return { limit, offset, sort, order };
};

/**
 * Batch controller methods
 */
export const batchController = {
  /**
   * List batch processes with filtering and pagination
   */
  async listBatchProcesses(req: Request, res: Response, next: NextFunction) {
    try {
      const { limit, offset, sort, order } = getPaginationParams(req);
      
      // Get filtering options
      const status = req.query.status as string;
      
      // Get batch processes from repository
      const batchRepo = new BatchRepository();
      const result = await batchRepo.findAll({
        status,
        limit,
        offset,
        sort,
        order,
      });
      
      // Prepare pagination metadata
      const meta = {
        pagination: {
          limit,
          offset,
          total: result.total,
          next: result.hasMore ? `/api/v1/batch?limit=${limit}&offset=${offset + limit}` : null,
          previous: offset > 0 ? `/api/v1/batch?limit=${limit}&offset=${Math.max(0, offset - limit)}` : null,
        },
      };
      
      // Return paginated batch processes
      res.json({
        success: true,
        data: result.batches,
        meta,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Create a new batch process
   */
  async createBatchProcess(req: Request, res: Response, next: NextFunction) {
    try {
      const batchData = req.body;
      const userId = (req as any).user?.id;
      
      // Set batch ID and initial properties
      const batchId = uuid();
      const batch = {
        id: batchId,
        status: 'pending',
        progress: {
          total: 0,
          completed: 0,
          failed: 0,
          processing: 0,
          pending: 0,
          skipped: 0,
          percentage: 0,
        },
        ...batchData,
        createdAt: new Date().toISOString(),
        createdBy: userId,
      };
      
      // Create batch record
      const batchRepo = new BatchRepository();
      await batchRepo.create(batch);
      
      // Start batch processing (async)
      const processorFactory = new BatchProcessorFactory();
      const processor = processorFactory.createProcessor(batch.type);
      
      if (!processor) {
        throw new ApiError(`Unsupported batch type: ${batch.type}`, 400, 'UNSUPPORTED_BATCH_TYPE');
      }
      
      // Start processing in the background
      processor.process(batchId, batch.options)
        .then(() => {
          logger.info(`Batch process completed: ${batchId}`, {
            batchId,
            type: batch.type,
          });
        })
        .catch((error) => {
          logger.error(`Batch process failed: ${batchId}`, {
            batchId,
            type: batch.type,
            error: (error as Error).message,
          });
        });
      
      // Notify via WebSocket
      const wsManager = getWebSocketManager();
      if (wsManager) {
        wsManager.broadcast(EventType.BATCH_STARTED, {
          id: batchId,
          type: batch.type,
          name: batch.name,
        });
        
        // Add to batch-specific room for targeted updates
        wsManager.broadcast(EventType.BATCH_STARTED, {
          id: batchId,
          type: batch.type,
          name: batch.name,
        }, `batch:${batchId}`);
      }
      
      // Return accepted response with batch info
      res.status(202).json({
        success: true,
        data: batch,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get batch process by ID
   */
  async getBatchProcess(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Get batch from repository
      const batchRepo = new BatchRepository();
      const batch = await batchRepo.findById(id);
      
      if (!batch) {
        throw new ApiError(`Batch process not found with ID: ${id}`, 404, 'BATCH_NOT_FOUND');
      }
      
      // Return batch process details
      res.json({
        success: true,
        data: batch,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Cancel a batch process
   */
  async cancelBatchProcess(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Get batch from repository
      const batchRepo = new BatchRepository();
      const batch = await batchRepo.findById(id);
      
      if (!batch) {
        throw new ApiError(`Batch process not found with ID: ${id}`, 404, 'BATCH_NOT_FOUND');
      }
      
      // Check if batch can be cancelled
      if (batch.status !== 'pending' && batch.status !== 'processing') {
        throw new ApiError(
          `Cannot cancel batch process with status: ${batch.status}`,
          400,
          'BATCH_CANNOT_BE_CANCELLED'
        );
      }
      
      // Cancel the batch
      await batchRepo.updateStatus(id, 'cancelled');
      
      // Notify via WebSocket
      const wsManager = getWebSocketManager();
      if (wsManager) {
        const message = {
          id,
          status: 'cancelled',
          message: 'Batch process cancelled by user',
        };
        
        wsManager.broadcast(EventType.BATCH_FAILED, message);
        wsManager.broadcast(EventType.BATCH_FAILED, message, `batch:${id}`);
      }
      
      // Return success response
      res.json({
        success: true,
        data: {
          message: 'Batch process cancelled successfully',
          id,
          status: 'cancelled',
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * List batch process items
   */
  async listBatchProcessItems(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { limit, offset } = getPaginationParams(req);
      const status = req.query.status as string;
      
      // Get batch from repository to verify existence
      const batchRepo = new BatchRepository();
      const batch = await batchRepo.findById(id);
      
      if (!batch) {
        throw new ApiError(`Batch process not found with ID: ${id}`, 404, 'BATCH_NOT_FOUND');
      }
      
      // Get batch items
      const result = await batchRepo.findItemsByBatchId(id, {
        status,
        limit,
        offset,
      });
      
      // Get status counts
      const statusCounts = await batchRepo.getItemStatusCounts(id);
      
      // Prepare pagination and status metadata
      const meta = {
        pagination: {
          limit,
          offset,
          total: result.total,
          next: result.hasMore ? `/api/v1/batch/${id}/items?limit=${limit}&offset=${offset + limit}` : null,
          previous: offset > 0 ? `/api/v1/batch/${id}/items?limit=${limit}&offset=${Math.max(0, offset - limit)}` : null,
        },
        status: statusCounts,
      };
      
      // Return paginated batch items with metadata
      res.json({
        success: true,
        data: result.items,
        meta,
      });
    } catch (error) {
      next(error);
    }
  },
};