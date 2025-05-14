/**
 * Processing Controller Tests
 * 
 * Tests the processing controller functionality
 */
import { describe, it, expect, beforeEach, afterEach, jest } from '@jest/globals';
import { Request, Response } from 'express';
import { v4 as uuid } from 'uuid';
import { processingController } from '../../../src/api/controllers/processing';
import { ContentProcessor } from '../../../src/core/content/ContentProcessor';
import { BatchProcessor } from '../../../src/core/content/BatchProcessor';
import { EntityExtractor } from '../../../src/core/entity/EntityExtractor';

// Mock dependencies
jest.mock('uuid');
jest.mock('../../../src/core/content/ContentProcessor');
jest.mock('../../../src/core/content/BatchProcessor');
jest.mock('../../../src/core/entity/EntityExtractor');
jest.mock('../../../src/api/index', () => ({
  getWebSocketManager: jest.fn().mockReturnValue({
    broadcast: jest.fn()
  })
}));

describe('Processing Controller', () => {
  // Setup mock request, response, and next function
  let req: Partial<Request>;
  let res: Partial<Response>;
  let next: jest.Mock;
  const mockJobId = '12345678-1234-1234-1234-123456789abc';
  
  beforeEach(() => {
    // Reset mocks
    jest.clearAllMocks();
    
    // Setup request, response, and next function mocks
    req = {
      params: {},
      body: {}
    };
    
    res = {
      json: jest.fn().mockReturnThis(),
      status: jest.fn().mockReturnThis()
    };
    
    next = jest.fn();
    
    // Mock uuid to return a consistent ID for testing
    (uuid as jest.Mock).mockReturnValue(mockJobId);
    
    // Setup ContentProcessor mock
    (ContentProcessor as unknown as jest.Mock).mockImplementation(() => ({
      process: jest.fn().mockResolvedValue({
        id: 'result123',
        content: 'Processed content',
        entities: []
      })
    }));
    
    // Setup BatchProcessor mock
    (BatchProcessor as unknown as jest.Mock).mockImplementation(() => ({
      processBatch: jest.fn().mockResolvedValue({
        processed: 2,
        successful: 2,
        failed: 0,
        items: []
      }),
      on: jest.fn().mockImplementation((event, callback) => {
        if (event === 'progress') {
          // Call the progress callback immediately for testing
          callback(50);
        }
        return {
          processBatch: jest.fn().mockResolvedValue({
            processed: 2,
            successful: 2,
            failed: 0,
            items: []
          })
        };
      })
    }));
    
    // Setup EntityExtractor mock
    (EntityExtractor as unknown as jest.Mock).mockImplementation(() => ({
      extract: jest.fn().mockResolvedValue([
        {
          id: 'entity1',
          type: 'person',
          name: 'John Doe',
          confidence: 0.95
        }
      ])
    }));
  });
  
  afterEach(() => {
    jest.resetAllMocks();
  });
  
  it('should analyze content asynchronously', async () => {
    // Setup request body
    req.body = {
      content: 'This is test content',
      contentType: 'text',
      options: {
        extractEntities: true
      }
    };
    
    // Call the analyzeContent function
    await processingController.analyzeContent(req as Request, res as Response, next);
    
    // Verify initial response
    expect(res.status).toHaveBeenCalledWith(202);
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: {
        jobId: mockJobId,
        status: 'pending',
        message: 'Content analysis started'
      }
    });
    
    // Let async operations complete
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verify ContentProcessor was instantiated and process was called
    expect(ContentProcessor).toHaveBeenCalled();
    const processorInstance = (ContentProcessor as unknown as jest.Mock).mock.instances[0];
    expect(processorInstance.process).toHaveBeenCalledWith(
      'This is test content',
      'text',
      { extractEntities: true }
    );
  });
  
  it('should extract entities asynchronously', async () => {
    // Setup request body
    req.body = {
      content: 'This is test content with entities',
      contentType: 'text',
      options: {}
    };
    
    // Call the extractEntities function
    await processingController.extractEntities(req as Request, res as Response, next);
    
    // Verify initial response
    expect(res.status).toHaveBeenCalledWith(202);
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: {
        jobId: mockJobId,
        status: 'pending',
        message: 'Entity extraction started'
      }
    });
    
    // Let async operations complete
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verify EntityExtractor was instantiated and extract was called
    expect(EntityExtractor).toHaveBeenCalled();
    const extractorInstance = (EntityExtractor as unknown as jest.Mock).mock.instances[0];
    expect(extractorInstance.extract).toHaveBeenCalledWith(
      'This is test content with entities',
      'text',
      {}
    );
  });
  
  it('should create batch process asynchronously', async () => {
    // Setup request body
    req.body = {
      items: [
        {
          content: 'Item 1',
          contentType: 'text'
        },
        {
          content: 'Item 2',
          contentType: 'text'
        }
      ],
      options: {
        parallelism: 2
      }
    };
    
    // Call the createBatchProcess function
    await processingController.createBatchProcess(req as Request, res as Response, next);
    
    // Verify initial response
    expect(res.status).toHaveBeenCalledWith(202);
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: {
        jobId: mockJobId,
        status: 'pending',
        message: 'Batch processing started',
        totalItems: 2
      }
    });
    
    // Let async operations complete
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verify BatchProcessor was instantiated and processBatch was called
    expect(BatchProcessor).toHaveBeenCalled();
    const batchProcessorInstance = (BatchProcessor as unknown as jest.Mock).mock.instances[0];
    expect(batchProcessorInstance.processBatch).toHaveBeenCalledWith(
      [
        {
          content: 'Item 1',
          contentType: 'text'
        },
        {
          content: 'Item 2',
          contentType: 'text'
        }
      ],
      {
        parallelism: 2
      }
    );
  });
  
  it('should get processing status', async () => {
    // Setup params with job ID
    req.params = { jobId: mockJobId };
    
    // Mock that job exists in active jobs map
    // We need to access the private map in the module
    // For testing purposes, we'll manually set a job in the map
    const controller = processingController as any;
    const activeJobs = new Map();
    activeJobs.set(mockJobId, {
      jobId: mockJobId,
      type: 'analyze',
      status: 'completed',
      progress: 100,
      startTime: new Date(),
      endTime: new Date(),
      result: { id: 'result123' }
    });
    controller.activeJobs = activeJobs;
    
    // Call the getProcessingStatus function
    await processingController.getProcessingStatus(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        jobId: mockJobId,
        type: 'analyze',
        status: 'completed',
        progress: 100,
        result: expect.objectContaining({
          id: 'result123'
        })
      })
    });
  });
  
  it('should handle job not found', async () => {
    // Setup params with non-existent job ID
    req.params = { jobId: 'nonexistent' };
    
    // Call the getProcessingStatus function
    await processingController.getProcessingStatus(req as Request, res as Response, next);
    
    // Verify error response
    expect(res.status).toHaveBeenCalledWith(404);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'JOB_NOT_FOUND',
        message: 'Processing job nonexistent not found'
      }
    });
  });
  
  it('should cancel processing job', async () => {
    // Setup params with job ID
    req.params = { jobId: mockJobId };
    
    // Mock that job exists in active jobs map with a processing status
    const controller = processingController as any;
    const activeJobs = new Map();
    activeJobs.set(mockJobId, {
      jobId: mockJobId,
      type: 'analyze',
      status: 'processing',
      progress: 50,
      startTime: new Date()
    });
    controller.activeJobs = activeJobs;
    
    // Call the cancelProcessing function
    await processingController.cancelProcessing(req as Request, res as Response, next);
    
    // Verify response
    expect(res.json).toHaveBeenCalledWith({
      success: true,
      data: expect.objectContaining({
        jobId: mockJobId,
        status: 'canceled',
        message: 'Processing job canceled'
      })
    });
    
    // Verify job status was updated
    const updatedJob = activeJobs.get(mockJobId);
    expect(updatedJob.status).toBe('canceled');
    expect(updatedJob.endTime).toBeDefined();
  });
  
  it('should handle cancellation of completed job', async () => {
    // Setup params with job ID
    req.params = { jobId: mockJobId };
    
    // Mock that job exists in active jobs map with a completed status
    const controller = processingController as any;
    const activeJobs = new Map();
    activeJobs.set(mockJobId, {
      jobId: mockJobId,
      type: 'analyze',
      status: 'completed',
      progress: 100,
      startTime: new Date(),
      endTime: new Date()
    });
    controller.activeJobs = activeJobs;
    
    // Call the cancelProcessing function
    await processingController.cancelProcessing(req as Request, res as Response, next);
    
    // Verify error response
    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith({
      success: false,
      error: {
        code: 'INVALID_JOB_STATE',
        message: 'Cannot cancel job with status: completed'
      }
    });
  });
});