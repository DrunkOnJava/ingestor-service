/**
 * BatchProcessor class
 * Handles batch processing of multiple content files
 */

import { ContentProcessor, ChunkOptions, ContentProcessingResult } from './ContentProcessor';
import { Logger } from '../logging';
import { FileSystem } from '../utils';
import * as path from 'path';
import { EventEmitter } from 'events';

/**
 * Options for batch processing
 */
export interface BatchProcessingOptions {
  /** Maximum number of concurrent file processes */
  maxConcurrency?: number;
  /** Whether to continue processing on file errors */
  continueOnError?: boolean;
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
    
    // Process files with concurrency limits
    await this.processFilesWithConcurrency(filteredPaths, opts, result);
    
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
}