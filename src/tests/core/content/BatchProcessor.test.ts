/**
 * Unit tests for BatchProcessor
 */

import { BatchProcessor } from '../../../core/content/BatchProcessor';
import { ContentProcessor } from '../../../core/content/ContentProcessor';
import { Logger } from '../../../core/logging';
import { FileSystem } from '../../../core/utils';

// Mock dependencies
jest.mock('../../../core/logging');
jest.mock('../../../core/utils/FileSystem');
jest.mock('../../../core/content/ContentProcessor');

describe('BatchProcessor', () => {
  let batchProcessor: BatchProcessor;
  let mockLogger: jest.Mocked<Logger>;
  let mockFs: jest.Mocked<FileSystem>;
  let mockContentProcessor: jest.Mocked<ContentProcessor>;
  
  beforeEach(() => {
    // Create mocks
    mockLogger = new Logger() as jest.Mocked<Logger>;
    mockFs = new FileSystem(mockLogger) as jest.Mocked<FileSystem>;
    mockContentProcessor = new ContentProcessor(mockLogger, mockFs) as jest.Mocked<ContentProcessor>;
    
    // Initialize BatchProcessor with mocks
    batchProcessor = new BatchProcessor(mockLogger, mockFs, mockContentProcessor);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('processBatch', () => {
    it('should process a batch of files with default options', async () => {
      // Setup mock file system responses
      mockFs.isFile.mockResolvedValue(true);
      mockFs.stat.mockResolvedValue({ size: 1024, isFile: () => true, isDirectory: () => false } as any);
      
      // Setup mock content processor response
      mockContentProcessor.processContent.mockResolvedValue({
        contentId: 123,
        contentType: 'text/plain',
        chunks: 1,
        success: true,
        metadata: { size: 1024 }
      });
      
      // Process a batch of test files
      const result = await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt',
        '/path/to/file3.txt'
      ]);
      
      // Verify results
      expect(result.totalFiles).toBe(3);
      expect(result.successfulFiles).toBe(3);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
      expect(result.results.size).toBe(3);
      expect(result.errors.size).toBe(0);
      
      // Verify content processor was called for each file
      expect(mockContentProcessor.processContent).toHaveBeenCalledTimes(3);
    });
    
    it('should filter files based on options', async () => {
      // Setup mock file system responses
      mockFs.isFile.mockImplementation(async (path) => {
        return !path.includes('invalid');
      });
      
      mockFs.stat.mockImplementation(async (path) => {
        const size = path.includes('large') ? 200 * 1024 * 1024 : 1024;
        return { 
          size, 
          isFile: () => true, 
          isDirectory: () => false 
        } as any;
      });
      
      // Setup custom file filter
      const fileFilter = (file: string) => !file.includes('filtered');
      
      // Setup mock content processor response
      mockContentProcessor.processContent.mockResolvedValue({
        contentId: 123,
        contentType: 'text/plain',
        chunks: 1,
        success: true,
        metadata: { size: 1024 }
      });
      
      // Process a batch of test files
      const result = await batchProcessor.processBatch([
        '/path/to/file1.txt',           // Valid
        '/path/to/invalid-file.txt',    // Not a file
        '/path/to/large-file.txt',      // Too large
        '/path/to/filtered-file.txt'    // Filtered out
      ], {
        fileFilter,
        maxFileSize: 100 * 1024 * 1024  // 100MB
      });
      
      // Verify results
      expect(result.totalFiles).toBe(1); // Only one file should be processed
      expect(result.successfulFiles).toBe(1);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
      
      // Verify content processor was called only for valid file
      expect(mockContentProcessor.processContent).toHaveBeenCalledTimes(1);
      expect(mockContentProcessor.processContent).toHaveBeenCalledWith(
        '/path/to/file1.txt',
        expect.any(String),
        expect.any(Object)
      );
    });
    
    it('should handle processing errors based on continueOnError option', async () => {
      // Setup mock file system responses
      mockFs.isFile.mockResolvedValue(true);
      mockFs.stat.mockResolvedValue({ size: 1024, isFile: () => true, isDirectory: () => false } as any);
      
      // Setup mock content processor to succeed for file1 and fail for file2
      mockContentProcessor.processContent.mockImplementation(async (filePath) => {
        if (filePath.includes('file1')) {
          return {
            contentId: 123,
            contentType: 'text/plain',
            chunks: 1,
            success: true,
            metadata: { size: 1024 }
          };
        } else {
          return {
            contentId: -1,
            contentType: 'text/plain',
            chunks: 0,
            success: false,
            error: 'Processing failed'
          };
        }
      });
      
      // Process with continueOnError = true (default)
      const resultContinue = await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt'
      ]);
      
      // Verify results
      expect(resultContinue.totalFiles).toBe(2);
      expect(resultContinue.successfulFiles).toBe(1);
      expect(resultContinue.failedFiles).toBe(1);
      expect(resultContinue.success).toBe(false); // At least one file failed
      expect(resultContinue.errors.size).toBe(1);
      
      // Reset mocks
      jest.clearAllMocks();
      
      // Setup mock to throw error for file2
      mockContentProcessor.processContent.mockImplementation(async (filePath) => {
        if (filePath.includes('file1')) {
          return {
            contentId: 123,
            contentType: 'text/plain',
            chunks: 1,
            success: true,
            metadata: { size: 1024 }
          };
        } else {
          throw new Error('Processing failed');
        }
      });
      
      // Process with continueOnError = false
      let errorThrown = false;
      try {
        await batchProcessor.processBatch([
          '/path/to/file1.txt',
          '/path/to/file2.txt'
        ], {
          continueOnError: false
        });
      } catch (error) {
        errorThrown = true;
      }
      
      // Verify error was thrown
      expect(errorThrown).toBe(true);
    });
  });

  describe('processDirectory', () => {
    it('should process all files in a directory', async () => {
      // Setup mock directory contents
      mockFs.readDir.mockResolvedValue(['file1.txt', 'file2.txt', 'subdirectory']);
      mockFs.stat.mockImplementation(async (path) => ({
        size: 1024,
        isFile: () => !path.includes('subdirectory'),
        isDirectory: () => path.includes('subdirectory')
      } as any));
      
      // For subdirectory, return more files
      mockFs.readDir.mockImplementation(async (dirPath) => {
        if (dirPath.includes('subdirectory')) {
          return ['file3.txt', 'file4.txt'];
        }
        return ['file1.txt', 'file2.txt', 'subdirectory'];
      });
      
      // Setup mock file system functions
      mockFs.isFile.mockResolvedValue(true);
      
      // Setup mock content processor
      mockContentProcessor.processContent.mockResolvedValue({
        contentId: 123,
        contentType: 'text/plain',
        chunks: 1,
        success: true,
        metadata: { size: 1024 }
      });
      
      // Process directory recursively
      const result = await batchProcessor.processDirectory('/path/to/directory', {}, true);
      
      // Verify results
      expect(result.totalFiles).toBe(4); // 2 files in main dir + 2 files in subdirectory
      expect(result.successfulFiles).toBe(4);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
      
      // Process directory non-recursively
      jest.clearAllMocks();
      
      // Reset mocks
      mockFs.readDir.mockResolvedValue(['file1.txt', 'file2.txt', 'subdirectory']);
      mockFs.stat.mockImplementation(async (path) => ({
        size: 1024,
        isFile: () => !path.includes('subdirectory'),
        isDirectory: () => path.includes('subdirectory')
      } as any));
      
      const nonRecursiveResult = await batchProcessor.processDirectory('/path/to/directory', {}, false);
      
      // Verify results
      expect(nonRecursiveResult.totalFiles).toBe(2); // Only 2 files in main dir
      expect(nonRecursiveResult.successfulFiles).toBe(2);
      expect(nonRecursiveResult.failedFiles).toBe(0);
      expect(nonRecursiveResult.success).toBe(true);
    });
  });

  describe('events', () => {
    it('should emit progress events during processing', async () => {
      // Setup mock file system
      mockFs.isFile.mockResolvedValue(true);
      mockFs.stat.mockResolvedValue({ size: 1024, isFile: () => true, isDirectory: () => false } as any);
      
      // Setup mock content processor
      mockContentProcessor.processContent.mockResolvedValue({
        contentId: 123,
        contentType: 'text/plain',
        chunks: 1,
        success: true,
        metadata: { size: 1024 }
      });
      
      // Progress event listener
      const progressEvents: any[] = [];
      batchProcessor.on('progress', (progress) => {
        progressEvents.push({ ...progress });
      });
      
      // Process batch
      await batchProcessor.processBatch([
        '/path/to/file1.txt',
        '/path/to/file2.txt',
        '/path/to/file3.txt'
      ]);
      
      // Verify progress events
      expect(progressEvents.length).toBe(3); // One event per file
      
      // First event (33% complete)
      expect(progressEvents[0].processedFiles).toBe(1);
      expect(progressEvents[0].totalFiles).toBe(3);
      expect(progressEvents[0].percentComplete).toBeCloseTo(33.33, 1);
      
      // Last event (100% complete)
      expect(progressEvents[2].processedFiles).toBe(3);
      expect(progressEvents[2].totalFiles).toBe(3);
      expect(progressEvents[2].percentComplete).toBe(100);
    });
  });
});