/**
 * Unit tests for the enhanced BatchProcessor with parallel processing capabilities
 * Focus is on testing the integration with ParallelBatchProcessor
 */

import { BatchProcessor, BatchProcessingOptions } from '../../../../src/core/content/BatchProcessor';
import { ParallelBatchProcessor } from '../../../../src/core/content/ParallelBatchProcessor';
import { ContentProcessor } from '../../../../src/core/content/ContentProcessor';
import { Logger } from '../../../../src/core/logging';
import { FileSystem } from '../../../../src/core/utils';
import { EventEmitter } from 'events';

// Mock dependencies
jest.mock('../../../../src/core/logging');
jest.mock('../../../../src/core/utils/FileSystem');
jest.mock('../../../../src/core/content/ContentProcessor');
jest.mock('../../../../src/core/content/ParallelBatchProcessor');

// Mock Worker to simulate worker thread environment
global.Worker = jest.fn().mockImplementation(() => {
  return {};
});

describe('Enhanced BatchProcessor with parallel processing', () => {
  let batchProcessor: BatchProcessor;
  let mockLogger: jest.Mocked<Logger>;
  let mockFs: jest.Mocked<FileSystem>;
  let mockContentProcessor: jest.Mocked<ContentProcessor>;
  let mockParallelProcessor: jest.Mocked<ParallelBatchProcessor>;
  
  beforeEach(() => {
    // Create mocks
    mockLogger = new Logger() as jest.Mocked<Logger>;
    mockFs = new FileSystem(mockLogger) as jest.Mocked<FileSystem>;
    mockContentProcessor = new ContentProcessor(mockLogger, mockFs) as jest.Mocked<ContentProcessor>;
    
    // Initialize BatchProcessor with mocks
    batchProcessor = new BatchProcessor(mockLogger, mockFs, mockContentProcessor);
    
    // Mock FileSystem.readFile to return file content
    mockFs.readFile = jest.fn().mockResolvedValue(Buffer.from('test file content'));
    
    // Setup mock file system responses for common tests
    mockFs.isFile.mockResolvedValue(true);
    mockFs.stat.mockResolvedValue({ size: 1024, isFile: () => true, isDirectory: () => false } as any);
    mockFs.getMimeType.mockResolvedValue('text/plain');
    
    // Setup mock content processor
    mockContentProcessor.processContent.mockResolvedValue({
      contentId: 123,
      contentType: 'text/plain',
      chunks: 1,
      success: true,
      metadata: { size: 1024 }
    });
    
    // Mock ParallelBatchProcessor
    mockParallelProcessor = new ParallelBatchProcessor() as jest.Mocked<ParallelBatchProcessor>;
    (ParallelBatchProcessor as jest.Mock).mockImplementation(() => {
      const eventEmitter = new EventEmitter();
      return {
        processBatch: jest.fn().mockImplementation(async (items) => {
          return {
            batchId: 'test-batch',
            processed: items.length,
            successful: items.length,
            failed: 0,
            items: items.map(item => ({
              id: item.id,
              status: 'success',
              result: {
                contentId: 123,
                contentType: item.contentType || 'text/plain',
                chunks: 1,
                success: true,
                metadata: { size: 1024 }
              },
              processingTime: 10
            })),
            totalTime: 100
          };
        }),
        on: eventEmitter.on.bind(eventEmitter),
        emit: eventEmitter.emit.bind(eventEmitter),
        cancel: jest.fn()
      };
    });
  });
  
  afterEach(() => {
    jest.clearAllMocks();
  });
  
  describe('parallel processing integration', () => {
    it('should use ParallelBatchProcessor when worker threads are enabled', async () => {
      // Process a batch with worker threads enabled
      const result = await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ], {
        useWorkerThreads: true
      });
      
      // Verify results
      expect(result.totalFiles).toBe(2);
      expect(result.successfulFiles).toBe(2);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
      
      // Verify ParallelBatchProcessor was created
      expect(ParallelBatchProcessor).toHaveBeenCalled();
      
      // Verify the parallel processor was used
      const parallellInstance = (ParallelBatchProcessor as jest.Mock).mock.results[0].value;
      expect(parallellInstance.processBatch).toHaveBeenCalled();
      
      // Verify file content was loaded
      expect(mockFs.readFile).toHaveBeenCalledTimes(2);
    });
    
    it('should fall back to standard processing when worker threads are disabled', async () => {
      // Process a batch with worker threads disabled
      const result = await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ], {
        useWorkerThreads: false
      });
      
      // Verify results
      expect(result.totalFiles).toBe(2);
      expect(result.successfulFiles).toBe(2);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
      
      // Verify ParallelBatchProcessor was NOT used (since worker threads are disabled)
      expect(ParallelBatchProcessor).not.toHaveBeenCalled();
      
      // Verify the content processor was used directly
      expect(mockContentProcessor.processContent).toHaveBeenCalledTimes(2);
    });
    
    it('should fall back to standard processing if parallel processing fails', async () => {
      // Make parallel processing fail
      (ParallelBatchProcessor as jest.Mock).mockImplementationOnce(() => {
        return {
          processBatch: jest.fn().mockRejectedValue(new Error('Parallel processing failed')),
          on: jest.fn(),
          cancel: jest.fn()
        };
      });
      
      // Process a batch with worker threads enabled
      const result = await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ], {
        useWorkerThreads: true
      });
      
      // Verify results still successful (fallback worked)
      expect(result.totalFiles).toBe(2);
      expect(result.successfulFiles).toBe(2);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
      
      // Verify ParallelBatchProcessor was created but failed
      expect(ParallelBatchProcessor).toHaveBeenCalled();
      
      // Verify content processor was used as fallback
      expect(mockContentProcessor.processContent).toHaveBeenCalledTimes(2);
    });
    
    it('should forward progress events from ParallelBatchProcessor', async () => {
      // Create a parallel processor mock that emits progress events
      (ParallelBatchProcessor as jest.Mock).mockImplementationOnce(() => {
        const eventEmitter = new EventEmitter();
        setTimeout(() => {
          eventEmitter.emit('progress', 50); // 50% complete
        }, 10);
        setTimeout(() => {
          eventEmitter.emit('progress', 100); // 100% complete
        }, 20);
        
        return {
          processBatch: jest.fn().mockImplementation(async (items) => {
            return {
              batchId: 'test-batch',
              processed: items.length,
              successful: items.length,
              failed: 0,
              items: items.map(item => ({
                id: item.id,
                status: 'success',
                result: {
                  contentId: 123,
                  contentType: item.contentType || 'text/plain',
                  chunks: 1,
                  success: true
                },
                processingTime: 10
              })),
              totalTime: 100
            };
          }),
          on: eventEmitter.on.bind(eventEmitter),
          emit: eventEmitter.emit.bind(eventEmitter),
          cancel: jest.fn()
        };
      });
      
      // Collect progress events
      const progressEvents: any[] = [];
      batchProcessor.on('progress', (progress) => {
        progressEvents.push({ ...progress });
      });
      
      // Process a batch
      await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ], {
        useWorkerThreads: true
      });
      
      // Verify progress events were forwarded
      expect(progressEvents.length).toBe(2);
      
      // First event (50% complete)
      expect(progressEvents[0].processedFiles).toBe(1);
      expect(progressEvents[0].totalFiles).toBe(2);
      expect(progressEvents[0].percentComplete).toBe(50);
      
      // Last event (100% complete)
      expect(progressEvents[1].processedFiles).toBe(2);
      expect(progressEvents[1].totalFiles).toBe(2);
      expect(progressEvents[1].percentComplete).toBe(100);
    });
    
    it('should correctly convert file paths to batch items', async () => {
      // Create a spy on the private method using any
      const batchProcessorAny = batchProcessor as any;
      const spy = jest.spyOn(batchProcessorAny, 'filePathsToBatchItems');
      
      // Process a batch
      await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ], {
        useWorkerThreads: true
      });
      
      // Verify file paths were converted to batch items
      expect(spy).toHaveBeenCalled();
      
      // Verify file content was loaded
      expect(mockFs.readFile).toHaveBeenCalledTimes(2);
      
      // Call the method directly to verify conversion
      const batchItems = await batchProcessorAny.filePathsToBatchItems(['/path/to/test.txt'], {
        autoDetectContentType: true,
        chunkOptions: { maxChunkSize: 1024 },
        fileFilter: () => true
      });
      
      // Verify batch item structure
      expect(batchItems.length).toBe(1);
      expect(batchItems[0].id).toBe('/path/to/test.txt');
      expect(batchItems[0].contentType).toBe('text/plain');
      expect(batchItems[0].content).toEqual(Buffer.from('test file content'));
      expect(batchItems[0].options).toHaveProperty('filePath');
      expect(batchItems[0].options).toHaveProperty('chunkOptions');
    });
    
    it('should respect batch processing options', async () => {
      // Setup options
      const options: BatchProcessingOptions = {
        maxConcurrency: 3,
        continueOnError: true,
        prioritizeItems: true,
        useWorkerThreads: true,
        dynamicConcurrency: true,
        workerMemoryLimit: 1024,
        chunkOptions: {
          maxChunkSize: 2048,
          chunkOverlap: 100,
          chunkStrategy: 'sentence'
        }
      };
      
      // Process a batch with options
      await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ], options);
      
      // Verify ParallelBatchProcessor was created
      expect(ParallelBatchProcessor).toHaveBeenCalled();
      
      // Verify options were passed to the parallel processor
      const parallellInstance = (ParallelBatchProcessor as jest.Mock).mock.results[0].value;
      expect(parallellInstance.processBatch).toHaveBeenCalledWith(
        expect.any(Array),
        expect.objectContaining({
          maxConcurrency: 3,
          continueOnError: true,
          prioritizeItems: true,
          useWorkerThreads: true,
          dynamicConcurrency: true,
          workerMemoryLimit: 1024,
          chunkOptions: {
            maxChunkSize: 2048,
            chunkOverlap: 100,
            chunkStrategy: 'sentence'
          }
        })
      );
    });
    
    it('should update batch options for all processing', async () => {
      // Set default options
      (batchProcessor as any).setDefaultOptions({
        maxConcurrency: 8,
        useWorkerThreads: true,
        workerMemoryLimit: 2048
      });
      
      // Process a batch without specifying options
      await batchProcessor.processBatch([
        '/path/to/file1.txt'
      ]);
      
      // Verify ParallelBatchProcessor was created
      expect(ParallelBatchProcessor).toHaveBeenCalled();
      
      // Verify default options were used
      const parallellInstance = (ParallelBatchProcessor as jest.Mock).mock.results[0].value;
      expect(parallellInstance.processBatch).toHaveBeenCalledWith(
        expect.any(Array),
        expect.objectContaining({
          maxConcurrency: 8,
          useWorkerThreads: true,
          workerMemoryLimit: 2048
        })
      );
    });
    
    it('should clean up resources when shutdown is called', async () => {
      // Process a batch to create a parallel processor
      await batchProcessor.processBatch([
        '/path/to/file1.txt'
      ], {
        useWorkerThreads: true
      });
      
      // Get the parallel processor instance
      const parallellInstance = (ParallelBatchProcessor as jest.Mock).mock.results[0].value;
      
      // Call shutdown
      (batchProcessor as any).shutdown();
      
      // Verify parallel processor was cancelled
      expect(parallellInstance.cancel).toHaveBeenCalled();
    });
  });
});