/**
 * Unit tests for ParallelBatchProcessor
 */

import { ParallelBatchProcessor, BatchItem } from '../../../../src/core/content/ParallelBatchProcessor';
import { Worker } from 'worker_threads';
import * as os from 'os';
import { EventEmitter } from 'events';

// Mock Worker implementation
jest.mock('worker_threads', () => ({
  Worker: jest.fn().mockImplementation(() => {
    const eventEmitter = new EventEmitter();
    return {
      on: eventEmitter.on.bind(eventEmitter),
      once: eventEmitter.once.bind(eventEmitter),
      postMessage: jest.fn().mockImplementation((message) => {
        // Simulate successful processing
        setTimeout(() => {
          eventEmitter.emit('message', {
            status: 'success',
            itemId: message.itemId,
            result: {
              contentId: 123,
              contentType: message.contentType || 'text/plain',
              chunks: 1,
              success: true,
              metadata: { size: message.content.length }
            }
          });
        }, 10);
      }),
      terminate: jest.fn()
    };
  }),
  parentPort: {
    on: jest.fn(),
    postMessage: jest.fn()
  },
  workerData: {}
}));

// Mock os module
jest.mock('os', () => ({
  cpus: jest.fn().mockReturnValue([{}, {}, {}, {}]), // Mock 4 CPUs
  totalmem: jest.fn().mockReturnValue(8 * 1024 * 1024 * 1024), // 8GB total memory
  freemem: jest.fn().mockReturnValue(4 * 1024 * 1024 * 1024), // 4GB free memory
  loadavg: jest.fn().mockReturnValue([1.0, 1.5, 2.0]) // CPU load averages
}));

describe('ParallelBatchProcessor', () => {
  let processor: ParallelBatchProcessor;
  let mockWorker: any;
  
  beforeEach(() => {
    // Clear all mocks
    jest.clearAllMocks();
    
    // Create a new processor instance
    processor = new ParallelBatchProcessor();
    
    // Get reference to the mocked Worker
    mockWorker = (Worker as jest.Mock).mock.results[0]?.value;
  });
  
  afterEach(() => {
    // Clean up
    processor.cancel();
  });
  
  describe('constructor', () => {
    it('should initialize with default configuration', () => {
      expect(processor).toBeInstanceOf(ParallelBatchProcessor);
      expect(processor).toBeInstanceOf(EventEmitter);
    });
  });
  
  describe('processBatch', () => {
    it('should process a batch of items successfully', async () => {
      // Create test batch items
      const batchItems: BatchItem[] = [
        {
          id: 'item1',
          content: 'Test content 1',
          contentType: 'text/plain'
        },
        {
          id: 'item2',
          content: 'Test content 2',
          contentType: 'text/plain'
        },
        {
          id: 'item3',
          content: 'Test content 3',
          contentType: 'text/plain'
        }
      ];
      
      // Process batch
      const result = await processor.processBatch(batchItems);
      
      // Verify result
      expect(result.processed).toBe(3);
      expect(result.successful).toBe(3);
      expect(result.failed).toBe(0);
      expect(result.items.length).toBe(3);
      expect(result.items[0].status).toBe('success');
      expect(result.items[1].status).toBe('success');
      expect(result.items[2].status).toBe('success');
      
      // Verify Worker was created
      expect(Worker).toHaveBeenCalled();
      
      // Verify worker postMessage was called for each item
      expect(mockWorker.postMessage).toHaveBeenCalledTimes(3);
    });
    
    it('should handle processing errors', async () => {
      // Override the worker mock for this test
      (Worker as jest.Mock).mockImplementationOnce(() => {
        const eventEmitter = new EventEmitter();
        return {
          on: eventEmitter.on.bind(eventEmitter),
          once: eventEmitter.once.bind(eventEmitter),
          postMessage: jest.fn().mockImplementation((message) => {
            // Simulate an error for the first item
            if (message.itemId === 'item1') {
              setTimeout(() => {
                eventEmitter.emit('message', {
                  status: 'error',
                  itemId: message.itemId,
                  error: { message: 'Processing failed', stack: 'Error stack' }
                });
              }, 10);
            } else {
              // Successful processing for other items
              setTimeout(() => {
                eventEmitter.emit('message', {
                  status: 'success',
                  itemId: message.itemId,
                  result: {
                    contentId: 123,
                    contentType: message.contentType || 'text/plain',
                    chunks: 1,
                    success: true,
                    metadata: { size: message.content.length }
                  }
                });
              }, 10);
            }
          }),
          terminate: jest.fn()
        };
      });
      
      // Create test batch items
      const batchItems: BatchItem[] = [
        {
          id: 'item1',
          content: 'Test content 1',
          contentType: 'text/plain'
        },
        {
          id: 'item2',
          content: 'Test content 2',
          contentType: 'text/plain'
        }
      ];
      
      // Process batch
      const result = await processor.processBatch(batchItems);
      
      // Verify result
      expect(result.processed).toBe(2);
      expect(result.successful).toBe(1);
      expect(result.failed).toBe(1);
      expect(result.items.length).toBe(2);
      expect(result.items[0].status).toBe('error');
      expect(result.items[0].error).toBe('Processing failed');
      expect(result.items[1].status).toBe('success');
    });
    
    it('should handle worker thread errors', async () => {
      // Override the worker mock for this test
      (Worker as jest.Mock).mockImplementationOnce(() => {
        const eventEmitter = new EventEmitter();
        return {
          on: eventEmitter.on.bind(eventEmitter),
          once: eventEmitter.once.bind(eventEmitter),
          postMessage: jest.fn().mockImplementation((message) => {
            if (message.itemId === 'item1') {
              // Simulate a worker thread error
              setTimeout(() => {
                eventEmitter.emit('error', new Error('Worker thread crashed'));
              }, 10);
            } else {
              setTimeout(() => {
                eventEmitter.emit('message', {
                  status: 'success',
                  itemId: message.itemId,
                  result: {
                    contentId: 123,
                    contentType: message.contentType || 'text/plain',
                    chunks: 1,
                    success: true
                  }
                });
              }, 10);
            }
          }),
          terminate: jest.fn()
        };
      });
      
      // Create test batch items
      const batchItems: BatchItem[] = [
        {
          id: 'item1',
          content: 'Test content 1',
          contentType: 'text/plain'
        },
        {
          id: 'item2',
          content: 'Test content 2',
          contentType: 'text/plain'
        }
      ];
      
      // Process batch
      const result = await processor.processBatch(batchItems);
      
      // Verify result
      expect(result.processed).toBe(2); // Both items should be counted
      expect(result.successful).toBe(1);
      expect(result.failed).toBe(1);
      expect(result.items.length).toBe(2);
      
      // Verify worker thread error is captured
      const errorItem = result.items.find(item => item.id === 'item1');
      expect(errorItem).toBeDefined();
      expect(errorItem?.status).toBe('error');
      expect(errorItem?.error).toContain('Worker thread crashed');
    });
    
    it('should respect maxConcurrency parameter', async () => {
      // Create test batch items (10 items)
      const batchItems: BatchItem[] = Array.from({ length: 10 }, (_, i) => ({
        id: `item${i + 1}`,
        content: `Test content ${i + 1}`,
        contentType: 'text/plain'
      }));
      
      // Process batch with maxConcurrency = 2
      const result = await processor.processBatch(batchItems, {
        maxConcurrency: 2
      });
      
      // Verify result
      expect(result.processed).toBe(10);
      expect(result.successful).toBe(10);
      
      // Should have created exactly 2 workers (limited by maxConcurrency)
      expect(Worker).toHaveBeenCalledTimes(2);
    });
    
    it('should prioritize items when prioritizeItems is true', async () => {
      // Create test batch items with priorities
      const batchItems: BatchItem[] = [
        {
          id: 'low-priority',
          content: 'Low priority content',
          contentType: 'text/plain',
          priority: 1
        },
        {
          id: 'high-priority',
          content: 'High priority content',
          contentType: 'text/plain',
          priority: 10
        },
        {
          id: 'medium-priority',
          content: 'Medium priority content',
          contentType: 'text/plain',
          priority: 5
        }
      ];
      
      // Mock the worker to record the order of processing
      let processingOrder: string[] = [];
      (Worker as jest.Mock).mockImplementationOnce(() => {
        const eventEmitter = new EventEmitter();
        return {
          on: eventEmitter.on.bind(eventEmitter),
          once: eventEmitter.once.bind(eventEmitter),
          postMessage: jest.fn().mockImplementation((message) => {
            // Record processing order
            processingOrder.push(message.itemId);
            
            // Simulate processing
            setTimeout(() => {
              eventEmitter.emit('message', {
                status: 'success',
                itemId: message.itemId,
                result: {
                  contentId: 123,
                  contentType: message.contentType || 'text/plain',
                  chunks: 1,
                  success: true
                }
              });
            }, 10);
          }),
          terminate: jest.fn()
        };
      });
      
      // Process batch with prioritizeItems = true
      await processor.processBatch(batchItems, {
        maxConcurrency: 1, // Force sequential processing to check order
        prioritizeItems: true
      });
      
      // Verify processing order (highest priority first)
      expect(processingOrder[0]).toBe('high-priority');
      expect(processingOrder[1]).toBe('medium-priority');
      expect(processingOrder[2]).toBe('low-priority');
    });
    
    it('should emit progress events', async () => {
      // Create test batch items
      const batchItems: BatchItem[] = [
        {
          id: 'item1',
          content: 'Test content 1',
          contentType: 'text/plain'
        },
        {
          id: 'item2',
          content: 'Test content 2',
          contentType: 'text/plain'
        }
      ];
      
      // Track progress events
      const progressEvents: number[] = [];
      processor.on('progress', (progress) => {
        progressEvents.push(progress);
      });
      
      // Process batch
      await processor.processBatch(batchItems);
      
      // Verify progress events
      expect(progressEvents.length).toBe(2);
      expect(progressEvents[0]).toBeCloseTo(50, 0);
      expect(progressEvents[1]).toBeCloseTo(100, 0);
    });
    
    it('should emit resource events when dynamicConcurrency is enabled', async () => {
      // Create test batch items
      const batchItems: BatchItem[] = [
        {
          id: 'item1',
          content: 'Test content 1',
          contentType: 'text/plain'
        }
      ];
      
      // Track resource events
      const resourceEvents: any[] = [];
      processor.on('resources', (resources) => {
        resourceEvents.push({ ...resources });
      });
      
      // Process batch with dynamicConcurrency enabled
      await processor.processBatch(batchItems, {
        dynamicConcurrency: true
      });
      
      // Verify at least one resource event was emitted
      expect(resourceEvents.length).toBeGreaterThan(0);
      
      // Check resource event properties
      const resourceEvent = resourceEvents[0];
      expect(resourceEvent).toHaveProperty('cpuUsage');
      expect(resourceEvent).toHaveProperty('availableMemory');
      expect(resourceEvent).toHaveProperty('totalMemory');
      expect(resourceEvent).toHaveProperty('memoryUsage');
    });
  });
  
  describe('cancel', () => {
    it('should terminate all workers when cancelled', async () => {
      // Create test batch items
      const batchItems: BatchItem[] = [
        {
          id: 'item1',
          content: 'Test content 1',
          contentType: 'text/plain'
        },
        {
          id: 'item2',
          content: 'Test content 2',
          contentType: 'text/plain'
        }
      ];
      
      // Start processing in background
      const processingPromise = processor.processBatch(batchItems);
      
      // Cancel processing
      processor.cancel();
      
      // Wait for processing to complete
      await processingPromise;
      
      // Verify workers were terminated
      expect(mockWorker.terminate).toHaveBeenCalled();
    });
  });
  
  describe('dynamicConcurrency', () => {
    it('should adjust concurrency based on system resources', async () => {
      // Mock high CPU usage
      (os.loadavg as jest.Mock).mockReturnValueOnce([3.5, 3.5, 3.5]);
      
      // Create test batch items
      const batchItems: BatchItem[] = Array.from({ length: 10 }, (_, i) => ({
        id: `item${i + 1}`,
        content: `Test content ${i + 1}`,
        contentType: 'text/plain'
      }));
      
      // Process with dynamic concurrency
      await processor.processBatch(batchItems, {
        maxConcurrency: 4,
        dynamicConcurrency: true
      });
      
      // With high CPU usage, it should use fewer workers than maxConcurrency
      expect(Worker).toHaveBeenCalledTimes(2);
      
      // Reset mocks
      jest.clearAllMocks();
      
      // Mock low CPU usage
      (os.loadavg as jest.Mock).mockReturnValueOnce([0.5, 0.5, 0.5]);
      
      // Create a new processor
      const processor2 = new ParallelBatchProcessor();
      
      // Process again with dynamic concurrency
      await processor2.processBatch(batchItems, {
        maxConcurrency: 4,
        dynamicConcurrency: true
      });
      
      // With low CPU usage, it should use max concurrency or higher
      expect(Worker).toHaveBeenCalledTimes(4);
    });
  });
});