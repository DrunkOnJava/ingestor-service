/**
 * BatchProcessorTool for the MCP server
 * Provides batch processing capabilities for multiple files
 */

import { BatchProcessor, ContentProcessor, ChunkOptions } from '../../../core/content';
import { Logger } from '../../../core/logging';
import { FileSystem } from '../../../core/utils';
import { DatabaseService } from '../../../core/services';
import { EntityManager } from '../../../core/entity';
import { ClaudeService } from '../../../core/services';
import * as path from 'path';

/**
 * Tool configuration options
 */
interface BatchToolConfig {
  /** Database service */
  databaseService?: DatabaseService;
  /** Logger instance */
  logger: Logger;
  /** FileSystem utility */
  fs: FileSystem;
  /** Claude service for AI extraction */
  claudeService?: ClaudeService;
}

/**
 * Input parameters for the batch processing tool
 */
export interface BatchProcessInput {
  /** Directory to process */
  directory?: string;
  /** Array of specific files to process */
  files?: string[];
  /** Database to use for storage */
  database: string;
  /** File extensions to include (e.g., "*.txt,*.md") */
  extensions?: string;
  /** Whether to process recursively (for directories) */
  recursive?: boolean;
  /** Maximum number of files to process (0 = unlimited) */
  maxFiles?: number;
  /** Maximum concurrent processes */
  concurrency?: number;
  /** Whether to continue on errors */
  continueOnError?: boolean;
  /** Content chunking options */
  chunking?: {
    /** Whether to enable chunking */
    enabled?: boolean;
    /** Maximum chunk size in bytes */
    maxSize?: number;
    /** Chunk overlap in bytes */
    overlap?: number;
    /** Chunking strategy (line, character, token, paragraph) */
    strategy?: 'line' | 'character' | 'token' | 'paragraph';
  };
}

/**
 * Output from the batch processing tool
 */
export interface BatchProcessOutput {
  /** Number of files successfully processed */
  successfulFiles: number;
  /** Number of files that failed processing */
  failedFiles: number;
  /** Total number of files processed */
  totalFiles: number;
  /** Total processing time in milliseconds */
  processingTimeMs: number;
  /** Success status of the operation */
  success: boolean;
  /** List of processed files with their status */
  fileResults: {
    /** File path */
    path: string;
    /** Processing success status */
    success: boolean;
    /** Error message (if failed) */
    error?: string;
    /** Content ID (if successful) */
    contentId?: number;
  }[];
}

/**
 * Tool for batch processing multiple files through the MCP server
 */
export class BatchProcessorTool {
  private logger: Logger;
  private fs: FileSystem;
  private databaseService?: DatabaseService;
  private claudeService?: ClaudeService;
  private contentProcessor: ContentProcessor;
  private entityManager?: EntityManager;
  private batchProcessor: BatchProcessor;

  /**
   * Creates a new BatchProcessorTool
   * @param config Tool configuration
   */
  constructor(config: BatchToolConfig) {
    this.logger = config.logger;
    this.fs = config.fs;
    this.databaseService = config.databaseService;
    this.claudeService = config.claudeService;

    // Create entity manager if database and Claude service are available
    if (this.databaseService && this.claudeService) {
      this.entityManager = new EntityManager(this.logger, this.databaseService, this.claudeService);
    }

    // Create content processor
    this.contentProcessor = new ContentProcessor(
      this.logger,
      this.fs,
      this.claudeService,
      this.entityManager
    );

    // Create batch processor
    this.batchProcessor = new BatchProcessor(
      this.logger,
      this.fs,
      this.contentProcessor
    );
  }

  /**
   * Execute batch processing
   * @param params Tool parameters
   * @returns Processing results
   */
  public async execute(params: BatchProcessInput): Promise<BatchProcessOutput> {
    this.logger.info(`Executing batch processing with database: ${params.database}`);

    // First, connect to the database if not already connected
    if (this.databaseService && !this.databaseService.isConnected()) {
      const dbPath = path.join(process.env.INGESTOR_HOME || '~/.ingestor', 'databases', `${params.database}.sqlite`);
      await this.databaseService.connect(dbPath);
    }

    // Set up chunk options
    const chunkOptions: ChunkOptions = {
      maxChunkSize: params.chunking?.maxSize || 4 * 1024 * 1024, // Default 4MB
      chunkOverlap: params.chunking?.overlap || 5000, // Default 5KB
      chunkStrategy: params.chunking?.strategy || 'paragraph'
    };

    // Set up batch options
    const batchOptions = {
      maxConcurrency: params.concurrency || 5,
      continueOnError: params.continueOnError !== false,
      chunkOptions,
      fileFilter: (file: string) => {
        if (!params.extensions) return true;
        
        // Convert extensions string to array
        const extensions = params.extensions.split(',')
          .map(ext => ext.trim())
          .filter(Boolean);
        
        if (extensions.length === 0) return true;
        
        const fileName = path.basename(file);
        // Check if any extension pattern matches
        return extensions.some(ext => {
          // Handle glob patterns like *.txt
          if (ext.startsWith('*')) {
            const extPattern = ext.replace('*', '');
            return fileName.endsWith(extPattern);
          }
          return fileName.endsWith(ext);
        });
      },
      maxFileSize: 100 * 1024 * 1024 // 100MB max size
    };

    // Determine the file list to process
    let filesToProcess: string[] = [];

    if (params.files && params.files.length > 0) {
      // Use explicit file list if provided
      filesToProcess = params.files;
    } else if (params.directory) {
      // Process directory
      const isRecursive = params.recursive !== false;
      
      // Get all files in the directory
      filesToProcess = await this.getFilesFromDirectory(
        params.directory, 
        isRecursive,
        batchOptions.fileFilter
      );
      
      // Apply max files limit if specified
      if (params.maxFiles && params.maxFiles > 0 && filesToProcess.length > params.maxFiles) {
        filesToProcess = filesToProcess.slice(0, params.maxFiles);
      }
    } else {
      throw new Error('Either directory or files parameter must be provided');
    }

    this.logger.info(`Found ${filesToProcess.length} files to process`);

    // Process files
    const result = await this.batchProcessor.processBatch(filesToProcess, batchOptions);

    // Transform result for the MCP interface
    const fileResults = Array.from(result.results.entries()).map(([filePath, processingResult]) => ({
      path: filePath,
      success: processingResult.success,
      error: processingResult.error,
      contentId: processingResult.contentId >= 0 ? processingResult.contentId : undefined
    }));

    // Additional errors from the error map
    Array.from(result.errors.entries()).forEach(([filePath, error]) => {
      // Check if this file is already in fileResults
      const existing = fileResults.find(r => r.path === filePath);
      if (!existing) {
        fileResults.push({
          path: filePath,
          success: false,
          error
        });
      }
    });

    return {
      successfulFiles: result.successfulFiles,
      failedFiles: result.failedFiles,
      totalFiles: result.totalFiles,
      processingTimeMs: result.processingTimeMs,
      success: result.success,
      fileResults
    };
  }

  /**
   * Get all files from a directory, optionally recursively
   * @param dirPath Directory path
   * @param recursive Whether to include subdirectories
   * @param fileFilter Optional filter function for files
   * @returns Array of file paths
   * @private
   */
  private async getFilesFromDirectory(
    dirPath: string, 
    recursive: boolean,
    fileFilter?: (file: string) => boolean
  ): Promise<string[]> {
    const result: string[] = [];
    const entries = await this.fs.readDir(dirPath);
    
    for (const entry of entries) {
      const fullPath = path.join(dirPath, entry);
      const stats = await this.fs.stat(fullPath);
      
      if (stats.isFile()) {
        // Apply filter if provided
        if (!fileFilter || fileFilter(fullPath)) {
          result.push(fullPath);
        }
      } else if (recursive && stats.isDirectory()) {
        const subDirFiles = await this.getFilesFromDirectory(fullPath, recursive, fileFilter);
        result.push(...subDirFiles);
      }
    }
    
    return result;
  }
}