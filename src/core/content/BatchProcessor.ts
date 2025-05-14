/**
 * BatchProcessor class
 * Handles batch processing of multiple content files
 */

import { ContentProcessor, ChunkOptions, ContentProcessingResult } from './ContentProcessor';
import { Logger } from '../logging';
import { FileSystem } from '../utils';
import * as path from 'path';
import { EventEmitter } from 'events';
import { ParallelBatchProcessor, BatchItem } from './ParallelBatchProcessor';

/**
 * Options for batch processing
 */
export interface BatchProcessingOptions {
  /** Maximum number of concurrent file processes (default: 5) */
  maxConcurrency?: number;
  /** Whether to continue processing on file errors (default: true) */
  continueOnError?: boolean;
  /** Process priority items first (default: true) */
  prioritizeItems?: boolean;
  /** Enable enhanced parallel processing with worker threads (default: true) */
  useWorkerThreads?: boolean;
  /** Dynamic concurrency based on system load (default: true) */
  dynamicConcurrency?: boolean;
  /** Memory limit per worker in MB (default: 512) */
  workerMemoryLimit?: number;
  /** Options for chunking content */
  chunkOptions?: ChunkOptions;
  /** Filter function to determine which files to process */
  fileFilter?: (file: string) => boolean;
  /** Auto-detect content types from file extensions */
  autoDetectContentType?: boolean;
  /** Max file size to process (in bytes) */
  maxFileSize?: number;
}

/**
 * Result of a batch processing operation
 */
export interface BatchProcessingResult {
  /** Total number of files processed */
  totalFiles: number;
  /** Number of files successfully processed */
  successfulFiles: number;
  /** Number of files that failed processing */
  failedFiles: number;
  /** Processing results for each file */
  results: Map<string, ContentProcessingResult>;
  /** Any errors that occurred during processing */
  errors: Map<string, string>;
  /** Total processing time in milliseconds */
  processingTimeMs: number;
  /** Batch success status */
  success: boolean;
}

/**
 * Progress information for batch processing
 */
export interface BatchProcessingProgress {
  /** Current file being processed */
  currentFile: string;
  /** Number of files processed so far */
  processedFiles: number;
  /** Total number of files to process */
  totalFiles: number;
  /** Percentage complete (0-100) */
  percentComplete: number;
  /** Estimated time remaining in milliseconds */
  estimatedTimeRemainingMs?: number;
}

/**
 * Batch processor for handling multiple content files
 */
export class BatchProcessor extends EventEmitter {
  private logger: Logger;
  private fs: FileSystem;
  private contentProcessor: ContentProcessor;
  private defaultOptions: Required<BatchProcessingOptions>;
  /** ParallelBatchProcessor instance for enhanced parallel processing */
  private parallelProcessor: ParallelBatchProcessor | null = null;

  /**
   * Creates a new BatchProcessor
   * @param logger Logger instance
   * @param fs FileSystem utility
   * @param contentProcessor ContentProcessor instance
   */
  constructor(
    logger: Logger,
    fs: FileSystem,
    contentProcessor: ContentProcessor
  ) {
    super();
    this.logger = logger;
    this.fs = fs;
    this.contentProcessor = contentProcessor;

    // Set default options
    this.defaultOptions = {
      maxConcurrency: 5,
      continueOnError: true,
      prioritizeItems: true,
      useWorkerThreads: true,
      dynamicConcurrency: true,
      workerMemoryLimit: 512, // 512MB per worker
      chunkOptions: {
        maxChunkSize: 4 * 1024 * 1024, // 4MB
        chunkOverlap: 200, // 200 bytes
        chunkStrategy: 'paragraph'
      },
      fileFilter: () => true, // Accept all files by default
      autoDetectContentType: true,
      maxFileSize: 100 * 1024 * 1024 // 100MB
    };
  }
  
  /**
   * Update default batch processing options
   * @param options New default options to set
   */
  public setDefaultOptions(options: Partial<BatchProcessingOptions>): void {
    this.defaultOptions = {
      ...this.defaultOptions,
      ...options
    };
    
    this.logger.debug(`Updated default batch processing options: ${JSON.stringify(options)}`);
  }

  /**
   * Process a batch of files
   * @param filePaths Array of file paths to process
   * @param options Batch processing options
   * @returns Batch processing result
   */
  public async processBatch(
    filePaths: string[],
    options: BatchProcessingOptions = {}
  ): Promise<BatchProcessingResult> {
    // Merge with default options
    const opts: Required<BatchProcessingOptions> = {
      ...this.defaultOptions,
      ...options
    };

    this.logger.info(`Starting batch processing of ${filePaths.length} files with concurrency ${opts.maxConcurrency}`);
    
    // Filter files based on options
    const filteredPaths = await this.filterFiles(filePaths, opts);
    
    this.logger.info(`Processing ${filteredPaths.length} files after filtering`);
    
    // Initialize result
    const result: BatchProcessingResult = {
      totalFiles: filteredPaths.length,
      successfulFiles: 0,
      failedFiles: 0,
      results: new Map(),
      errors: new Map(),
      processingTimeMs: 0,
      success: true
    };
    
    if (filteredPaths.length === 0) {
      this.logger.info('No files to process after filtering');
      return result;
    }
    
    const startTime = Date.now();
    
    // Use ParallelBatchProcessor if worker threads are enabled and available
    if (opts.useWorkerThreads && typeof Worker !== 'undefined') {
      try {
        this.logger.info(`Using parallel batch processing with worker threads`);
        await this.processFilesWithParallelProcessor(filteredPaths, opts, result);
      } catch (error) {
        this.logger.error(`Parallel processing failed, falling back to standard processing: ${error instanceof Error ? error.message : 'Unknown error'}`);
        // Reset result for fallback processing
        result.successfulFiles = 0;
        result.failedFiles = 0;
        result.results = new Map();
        result.errors = new Map();
        
        // Fall back to standard processing
        await this.processFilesWithConcurrency(filteredPaths, opts, result);
      }
    } else {
      // Use standard processing
      if (opts.useWorkerThreads) {
        this.logger.info(`Worker threads requested but not available, using standard processing`);
      } else {
        this.logger.info(`Using standard batch processing`);
      }
      
      await this.processFilesWithConcurrency(filteredPaths, opts, result);
    }
    
    // Calculate total processing time
    result.processingTimeMs = Date.now() - startTime;
    
    // Determine overall success
    result.success = result.failedFiles === 0;
    
    this.logger.info(`Batch processing completed in ${result.processingTimeMs}ms: ` +
      `${result.successfulFiles} successful, ${result.failedFiles} failed`);
    
    return result;
  }

  /**
   * Process a directory recursively
   * @param dirPath Directory path to process
   * @param options Batch processing options
   * @param recursive Whether to process subdirectories
   * @returns Batch processing result
   */
  public async processDirectory(
    dirPath: string,
    options: BatchProcessingOptions = {},
    recursive: boolean = true
  ): Promise<BatchProcessingResult> {
    this.logger.info(`Processing directory: ${dirPath} (recursive: ${recursive})`);
    
    // Get all files in the directory
    const allFiles = await this.getFilesFromDirectory(dirPath, recursive);
    
    this.logger.debug(`Found ${allFiles.length} files in directory`);
    
    // Process the batch
    return this.processBatch(allFiles, options);
  }

  /**
   * Filter files based on batch options
   * @param filePaths Array of file paths
   * @param options Batch processing options
   * @returns Filtered file paths
   * @private
   */
  private async filterFiles(
    filePaths: string[],
    options: Required<BatchProcessingOptions>
  ): Promise<string[]> {
    const filtered: string[] = [];
    
    for (const filePath of filePaths) {
      try {
        // Check if file exists and is a file (not a directory)
        if (!(await this.fs.isFile(filePath))) {
          this.logger.debug(`Skipping non-file: ${filePath}`);
          continue;
        }
        
        // Check file size
        const stats = await this.fs.stat(filePath);
        if (stats.size > options.maxFileSize) {
          this.logger.debug(`Skipping file exceeding max size: ${filePath} (${stats.size} bytes)`);
          continue;
        }
        
        // Apply custom filter function
        if (!options.fileFilter(filePath)) {
          this.logger.debug(`Skipping file based on filter: ${filePath}`);
          continue;
        }
        
        filtered.push(filePath);
      } catch (error) {
        this.logger.error(`Error filtering file ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
    }
    
    return filtered;
  }

  /**
   * Get all files from a directory, optionally recursively
   * @param dirPath Directory path
   * @param recursive Whether to include subdirectories
   * @returns Array of file paths
   * @private
   */
  private async getFilesFromDirectory(dirPath: string, recursive: boolean): Promise<string[]> {
    const result: string[] = [];
    const entries = await this.fs.readDir(dirPath);
    
    for (const entry of entries) {
      const fullPath = path.join(dirPath, entry);
      const stats = await this.fs.stat(fullPath);
      
      if (stats.isFile()) {
        result.push(fullPath);
      } else if (recursive && stats.isDirectory()) {
        const subDirFiles = await this.getFilesFromDirectory(fullPath, recursive);
        result.push(...subDirFiles);
      }
    }
    
    return result;
  }

  /**
   * Process files with concurrency control
   * @param filePaths Files to process
   * @param options Batch processing options
   * @param result Batch processing result to update
   * @private
   */
  private async processFilesWithConcurrency(
    filePaths: string[],
    options: Required<BatchProcessingOptions>,
    result: BatchProcessingResult
  ): Promise<void> {
    const queue = [...filePaths];
    const inProgress = new Set<Promise<void>>();
    const startTimes = new Map<string, number>();
    let completedFiles = 0;
    
    // Process until queue is empty and all in-progress tasks complete
    while (queue.length > 0 || inProgress.size > 0) {
      // Fill up to max concurrency
      while (queue.length > 0 && inProgress.size < options.maxConcurrency) {
        const filePath = queue.shift()!;
        
        // Create a promise for this file's processing
        const processPromise = this.processFile(filePath, options)
          .then(fileResult => {
            // Update batch results
            result.results.set(filePath, fileResult);
            
            if (fileResult.success) {
              result.successfulFiles++;
            } else {
              result.failedFiles++;
              result.errors.set(filePath, fileResult.error || 'Unknown error');
            }
            
            // Calculate and emit progress
            completedFiles++;
            
            const avgTimePerFile = completedFiles > 0 
              ? [...startTimes.entries()]
                  .filter(([file]) => result.results.has(file))
                  .reduce((sum, [file, startTime]) => sum + (Date.now() - startTime), 0) / completedFiles
              : 0;
            
            const filesRemaining = queue.length + inProgress.size - 1; // -1 for current file
            const estimatedTimeRemainingMs = avgTimePerFile * filesRemaining;
            
            const progress: BatchProcessingProgress = {
              currentFile: filePath,
              processedFiles: completedFiles,
              totalFiles: result.totalFiles,
              percentComplete: (completedFiles / result.totalFiles) * 100,
              estimatedTimeRemainingMs: estimatedTimeRemainingMs > 0 ? estimatedTimeRemainingMs : undefined
            };
            
            this.emit('progress', progress);
          })
          .catch(error => {
            this.logger.error(`Unexpected error processing file ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
            result.failedFiles++;
            result.errors.set(filePath, error instanceof Error ? error.message : 'Unknown error');
          })
          .finally(() => {
            // Remove from in-progress set
            inProgress.delete(processPromise);
          });
        
        // Add to in-progress set
        inProgress.add(processPromise);
        startTimes.set(filePath, Date.now());
      }
      
      // Wait for at least one task to complete if we're at max concurrency or queue is empty
      if (inProgress.size > 0) {
        await Promise.race(inProgress);
      }
    }
  }

  /**
   * Process a single file
   * @param filePath File path
   * @param options Batch processing options
   * @returns Content processing result
   * @private
   */
  private async processFile(
    filePath: string,
    options: Required<BatchProcessingOptions>
  ): Promise<ContentProcessingResult> {
    this.logger.debug(`Processing file: ${filePath}`);
    
    try {
      // Determine content type
      let contentType = 'application/octet-stream';
      
      if (options.autoDetectContentType) {
        contentType = await this.fs.getMimeType(filePath);
        this.logger.debug(`Detected content type: ${contentType}`);
      }
      
      // Process the file
      return await this.contentProcessor.processContent(
        filePath,
        contentType,
        options.chunkOptions
      );
    } catch (error) {
      this.logger.error(`Error processing file ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      
      // If we should continue on error, return a failure result
      if (options.continueOnError) {
        return {
          contentId: -1,
          contentType: 'unknown',
          chunks: 0,
          success: false,
          error: error instanceof Error ? error.message : 'Unknown error'
        };
      }
      
      // Otherwise, rethrow the error
      throw error;
    }
  }
  
  /**
   * Convert a file path to a batch item for parallel processing
   * @param filePath Path to the file
   * @param options Processing options
   * @returns BatchItem containing file content and metadata
   * @private
   */
  private async filePathToBatchItem(
    filePath: string, 
    options: Required<BatchProcessingOptions>
  ): Promise<BatchItem> {
    this.logger.debug(`Converting file to batch item: ${filePath}`);
    
    // Read file content
    const content = await this.fs.readFile(filePath);
    
    // Determine content type
    let contentType = 'application/octet-stream';
    if (options.autoDetectContentType) {
      contentType = await this.fs.getMimeType(filePath);
    }
    
    // Create batch item
    return {
      id: filePath, // Use file path as unique ID
      content,
      contentType,
      priority: 0, // Default priority
      options: {
        filePath, // Include original file path for reference
        chunkOptions: options.chunkOptions
      }
    };
  }
  
  /**
   * Convert multiple file paths to batch items for parallel processing
   * @param filePaths Array of file paths
   * @param options Processing options
   * @returns Array of batch items
   * @private
   */
  private async filePathsToBatchItems(
    filePaths: string[],
    options: Required<BatchProcessingOptions>
  ): Promise<BatchItem[]> {
    this.logger.debug(`Converting ${filePaths.length} files to batch items`);
    
    const batchItems: BatchItem[] = [];
    
    for (const filePath of filePaths) {
      try {
        const item = await this.filePathToBatchItem(filePath, options);
        batchItems.push(item);
      } catch (error) {
        this.logger.error(`Error converting file ${filePath} to batch item: ${error instanceof Error ? error.message : 'Unknown error'}`);
        
        if (!options.continueOnError) {
          throw error;
        }
      }
    }
    
    return batchItems;
  }
  
  /**
   * Map a parallel batch processing result back to the legacy result format
   * @param parallelResult Result from ParallelBatchProcessor
   * @param filePathMap Map from file paths to batch item IDs
   * @returns BatchProcessingResult in the legacy format
   * @private
   */
  /**
   * Process files using the ParallelBatchProcessor for enhanced performance
   * @param filePaths Array of file paths to process
   * @param options Batch processing options
   * @param result Result object to update
   * @private
   */
  private async processFilesWithParallelProcessor(
    filePaths: string[],
    options: Required<BatchProcessingOptions>,
    result: BatchProcessingResult
  ): Promise<void> {
    this.logger.debug(`Processing ${filePaths.length} files with ParallelBatchProcessor`);
    
    // Initialize ParallelBatchProcessor if needed
    if (!this.parallelProcessor) {
      this.parallelProcessor = new ParallelBatchProcessor();
      
      // Forward progress events
      this.parallelProcessor.on('progress', (progressPercentage: number) => {
        // Calculate number of processed files from percentage
        const processedFiles = Math.floor((progressPercentage / 100) * filePaths.length);
        
        // Create progress event compatible with legacy format
        const progress: BatchProcessingProgress = {
          currentFile: 'unknown', // Individual file name not tracked in parallel processing
          processedFiles,
          totalFiles: filePaths.length,
          percentComplete: progressPercentage,
          // No estimated time remaining in parallel processing
        };
        
        this.emit('progress', progress);
      });
      
      // Forward resource events
      this.parallelProcessor.on('resources', (resources) => {
        this.emit('resources', resources);
      });
    }
    
    // Convert file paths to batch items
    const batchItems = await this.filePathsToBatchItems(filePaths, options);
    
    if (batchItems.length === 0) {
      this.logger.warn('No valid batch items to process');
      return;
    }
    
    // Process batch items
    const parallelResult = await this.parallelProcessor.processBatch(batchItems, options);
    
    // Update result with parallel processing results
    const updatedResult = this.mapParallelResultToLegacyResult(parallelResult, new Map());
    
    result.successfulFiles = updatedResult.successfulFiles;
    result.failedFiles = updatedResult.failedFiles;
    result.results = updatedResult.results;
    result.errors = updatedResult.errors;
    result.processingTimeMs = updatedResult.processingTimeMs;
    result.success = updatedResult.success;
  }
  
  private mapParallelResultToLegacyResult(
    parallelResult: import('./ParallelBatchProcessor').BatchProcessingResult,
    filePathMap: Map<string, string>
  ): BatchProcessingResult {
    const result: BatchProcessingResult = {
      totalFiles: parallelResult.processed,
      successfulFiles: parallelResult.successful,
      failedFiles: parallelResult.failed,
      results: new Map(),
      errors: new Map(),
      processingTimeMs: parallelResult.totalTime,
      success: parallelResult.failed === 0
    };
    
    // Convert item results to the legacy format
    for (const item of parallelResult.items) {
      const filePath = item.id;
      
      if (item.status === 'success' && item.result) {
        result.results.set(filePath, item.result);
      } else if (item.status === 'error') {
        result.errors.set(filePath, item.error || 'Unknown error');
      }
    }
    
    return result;
  }
  
  /**
   * Clean up resources used by the batch processor
   * Should be called when the processor is no longer needed
   */
  public shutdown(): void {
    this.logger.info('Shutting down BatchProcessor');
    
    // Clean up parallel processor if it exists
    if (this.parallelProcessor) {
      this.logger.debug('Terminating parallel processor');
      this.parallelProcessor.cancel();
      this.parallelProcessor = null;
    }
    
    // Remove all listeners
    this.removeAllListeners();
  }
}