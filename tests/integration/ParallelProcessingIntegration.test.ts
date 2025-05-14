/**
 * Integration test for parallel batch processing
 * 
 * Tests the full integration between BatchProcessor and ParallelBatchProcessor
 * with real file operations.
 */

import { BatchProcessor } from '../../src/core/content/BatchProcessor';
import { ContentProcessor } from '../../src/core/content/ContentProcessor';
import { Logger, LogLevel } from '../../src/core/logging';
import { FileSystem } from '../../src/core/utils';
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';

// Skip tests if worker_threads are not available in current Node.js version
const workerThreadsAvailable = (() => {
  try {
    require('worker_threads');
    return true;
  } catch (e) {
    return false;
  }
})();

describe('Parallel Processing Integration', () => {
  // Setup test directory and files
  const testDir = path.join(os.tmpdir(), 'ingestor-parallel-test-' + Date.now());
  const testFiles: string[] = [];
  const numTestFiles = 10;
  
  let batchProcessor: BatchProcessor;
  let logger: Logger;
  let fs: FileSystem;
  let contentProcessor: ContentProcessor;
  
  beforeAll(async () => {
    // Create test directory
    await fs.promises.mkdir(testDir, { recursive: true });
    
    // Create test files
    for (let i = 0; i < numTestFiles; i++) {
      const filePath = path.join(testDir, `test-file-${i}.txt`);
      const content = `Test file ${i} content.\n`.repeat(100); // ~1600 bytes per file
      await fs.promises.writeFile(filePath, content);
      testFiles.push(filePath);
    }
    
    // Initialize components
    logger = new Logger('test', { level: LogLevel.DEBUG });
    fs = new FileSystem(logger);
    contentProcessor = new ContentProcessor(logger, fs);
    batchProcessor = new BatchProcessor(logger, fs, contentProcessor);
  });
  
  afterAll(async () => {
    // Clean up test files
    for (const file of testFiles) {
      try {
        await fs.promises.unlink(file);
      } catch (e) {
        // Ignore errors
      }
    }
    
    // Clean up test directory
    try {
      await fs.promises.rmdir(testDir);
    } catch (e) {
      // Ignore errors
    }
    
    // Clean up batch processor
    (batchProcessor as any).shutdown();
  });
  
  // Only run these tests if worker_threads are available
  (workerThreadsAvailable ? describe : describe.skip)('with worker threads', () => {
    it('should process files faster with parallel processing', async () => {
      // Add an artificial delay to content processing to simulate CPU-intensive work
      jest.spyOn(contentProcessor as any, 'processContent').mockImplementation(async (filePath: string) => {
        // Read the file
        const content = await fs.promises.readFile(filePath, 'utf-8');
        
        // Simulate CPU-intensive processing with a delay
        await new Promise(resolve => setTimeout(resolve, 100));
        
        // Return a successful result
        return {
          contentId: 123,
          contentType: 'text/plain',
          chunks: 1,
          success: true,
          metadata: { 
            size: content.length,
            filename: path.basename(filePath)
          }
        };
      });
      
      // Measure time for sequential processing
      const sequentialStart = Date.now();
      const sequentialResult = await batchProcessor.processBatch(testFiles, {
        useWorkerThreads: false
      });
      const sequentialTime = Date.now() - sequentialStart;
      
      // Reset the spy
      jest.clearAllMocks();
      
      // Measure time for parallel processing
      const parallelStart = Date.now();
      const parallelResult = await batchProcessor.processBatch(testFiles, {
        useWorkerThreads: true,
        maxConcurrency: Math.min(4, os.cpus().length)
      });
      const parallelTime = Date.now() - parallelStart;
      
      // Check results
      expect(sequentialResult.totalFiles).toBe(numTestFiles);
      expect(sequentialResult.successfulFiles).toBe(numTestFiles);
      expect(parallelResult.totalFiles).toBe(numTestFiles);
      expect(parallelResult.successfulFiles).toBe(numTestFiles);
      
      // Parallel processing should be at least 1.5x faster with multiple cores
      // but we'll use a more conservative 1.2x to avoid test flakiness
      const expectedSpeedup = 1.2;
      console.log(`Sequential time: ${sequentialTime}ms, Parallel time: ${parallelTime}ms`);
      expect(sequentialTime / parallelTime).toBeGreaterThanOrEqual(expectedSpeedup);
    }, 30000); // Increase timeout to 30 seconds
    
    it('should handle progress events correctly with parallel processing', async () => {
      // Create a spy for the mock implementation to ensure it's used
      const processSpy = jest.spyOn(contentProcessor as any, 'processContent').mockImplementation(async (filePath: string) => {
        // Read the file
        const content = await fs.promises.readFile(filePath, 'utf-8');
        
        // Simulate CPU-intensive processing with a delay
        await new Promise(resolve => setTimeout(resolve, 50));
        
        // Return a successful result
        return {
          contentId: 123,
          contentType: 'text/plain',
          chunks: 1,
          success: true,
          metadata: { 
            size: content.length,
            filename: path.basename(filePath)
          }
        };
      });
      
      // Track progress events
      const progressEvents: any[] = [];
      batchProcessor.on('progress', (progress) => {
        progressEvents.push({ ...progress });
      });
      
      // Process files with parallel processing
      await batchProcessor.processBatch(testFiles, {
        useWorkerThreads: true,
        maxConcurrency: Math.min(4, os.cpus().length)
      });
      
      // Clear mock to prevent interfering with other tests
      processSpy.mockRestore();
      
      // Verify progress events
      expect(progressEvents.length).toBeGreaterThan(0);
      
      // First event should have percentComplete > 0
      expect(progressEvents[0].percentComplete).toBeGreaterThan(0);
      
      // Last event should be 100% complete
      expect(progressEvents[progressEvents.length - 1].percentComplete).toBeCloseTo(100, 0);
      
      // Verify progress increases monotonically
      for (let i = 1; i < progressEvents.length; i++) {
        expect(progressEvents[i].percentComplete).toBeGreaterThanOrEqual(
          progressEvents[i - 1].percentComplete
        );
      }
    });
    
    it('should process a directory efficiently with parallel processing', async () => {
      // Create a spy for the mock implementation to ensure it's used
      const processSpy = jest.spyOn(contentProcessor as any, 'processContent').mockImplementation(async (filePath: string) => {
        // Read the file
        const content = await fs.promises.readFile(filePath, 'utf-8');
        
        // Simulate CPU-intensive processing with a delay
        await new Promise(resolve => setTimeout(resolve, 50));
        
        // Return a successful result
        return {
          contentId: 123,
          contentType: 'text/plain',
          chunks: 1,
          success: true,
          metadata: { 
            size: content.length,
            filename: path.basename(filePath)
          }
        };
      });
      
      // Process directory with parallel processing
      const result = await batchProcessor.processDirectory(testDir, {
        useWorkerThreads: true,
        maxConcurrency: Math.min(4, os.cpus().length)
      });
      
      // Clear mock to prevent interfering with other tests
      processSpy.mockRestore();
      
      // Verify results
      expect(result.totalFiles).toBe(numTestFiles);
      expect(result.successfulFiles).toBe(numTestFiles);
      expect(result.failedFiles).toBe(0);
      expect(result.success).toBe(true);
    });
    
    it('should handle processing errors correctly with parallel processing', async () => {
      // Create a spy for the mock implementation to fail on every other file
      const processSpy = jest.spyOn(contentProcessor as any, 'processContent').mockImplementation(async (filePath: string) => {
        // Read the file
        const content = await fs.promises.readFile(filePath, 'utf-8');
        
        // Get file index from filename
        const fileIndex = parseInt(path.basename(filePath).match(/test-file-(\d+)/)?.[1] || '0');
        
        // Simulate CPU-intensive processing with a delay
        await new Promise(resolve => setTimeout(resolve, 50));
        
        // Fail on even file indices
        if (fileIndex % 2 === 0) {
          throw new Error(`Simulated error processing file ${fileIndex}`);
        }
        
        // Return a successful result for odd file indices
        return {
          contentId: 123,
          contentType: 'text/plain',
          chunks: 1,
          success: true,
          metadata: { 
            size: content.length,
            filename: path.basename(filePath)
          }
        };
      });
      
      // Process with parallel processing and continueOnError = true
      const result = await batchProcessor.processBatch(testFiles, {
        useWorkerThreads: true,
        maxConcurrency: Math.min(4, os.cpus().length),
        continueOnError: true
      });
      
      // Clear mock to prevent interfering with other tests
      processSpy.mockRestore();
      
      // Verify results
      expect(result.totalFiles).toBe(numTestFiles);
      expect(result.successfulFiles).toBe(Math.floor(numTestFiles / 2)); // Only odd indices succeed
      expect(result.failedFiles).toBe(Math.ceil(numTestFiles / 2)); // Even indices fail
      expect(result.success).toBe(false); // At least one file failed
      
      // Verify errors were captured
      expect(result.errors.size).toBe(Math.ceil(numTestFiles / 2));
      
      // Check with continueOnError = false
      processSpy.mockImplementation(async (filePath: string) => {
        // Read the file
        const content = await fs.promises.readFile(filePath, 'utf-8');
        
        // Get file index from filename
        const fileIndex = parseInt(path.basename(filePath).match(/test-file-(\d+)/)?.[1] || '0');
        
        // Simulate CPU-intensive processing with a delay
        await new Promise(resolve => setTimeout(resolve, 50));
        
        // Fail on first file
        if (fileIndex === 0) {
          throw new Error('Simulated error processing first file');
        }
        
        // Return a successful result for other files
        return {
          contentId: 123,
          contentType: 'text/plain',
          chunks: 1,
          success: true,
          metadata: { 
            size: content.length,
            filename: path.basename(filePath)
          }
        };
      });
      
      // Process with continueOnError = false
      let errorThrown = false;
      try {
        await batchProcessor.processBatch(testFiles, {
          useWorkerThreads: true,
          maxConcurrency: Math.min(4, os.cpus().length),
          continueOnError: false
        });
      } catch (error) {
        errorThrown = true;
      }
      
      // Clear mock to prevent interfering with other tests
      processSpy.mockRestore();
      
      // When continueOnError = false, an error should be thrown
      expect(errorThrown).toBe(true);
    });
  });
});