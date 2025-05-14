/**
 * ParallelBatchProcessor class
 * 
 * Enhanced batch processor that uses worker threads for optimized parallel processing
 */

import { Worker } from 'worker_threads';
import * as os from 'os';
import * as path from 'path';
import { EventEmitter } from 'events';
import { v4 as uuid } from 'uuid';
import { BatchProcessingOptions } from './BatchProcessor';
import { ContentProcessingResult } from './ContentProcessor';
import { Logger, LogLevel } from '../logging';

/**
 * Batch processing item
 */
export interface BatchItem {
  /** Unique ID for the item */
  id?: string;
  /** Content to process */
  content: string | Buffer;
  /** Content type */
  contentType?: string;
  /** Priority of the item (higher number = higher priority) */
  priority?: number;
  /** Custom options for this specific item */
  options?: Record<string, any>;
}

/**
 * Result of a batch processing operation
 */
export interface BatchProcessingResult {
  /** Total number of items processed */
  processed: number;
  /** Number of successfully processed items */
  successful: number;
  /** Number of failed items */
  failed: number;
  /** Detailed results for each item */
  items: {
    /** Item ID */
    id: string;
    /** Processing status */
    status: 'success' | 'error';
    /** Processing result (if successful) */
    result?: ContentProcessingResult;
    /** Error message (if failed) */
    error?: string;
    /** Processing time in milliseconds */
    processingTime?: number;
  }[];
  /** Overall processing time in milliseconds */
  totalTime: number;
  /** Batch ID */
  batchId: string;
}

/**
 * System resource usage information
 */
interface SystemResources {
  /** CPU usage percentage (0-100) */
  cpuUsage: number;
  /** Available memory in MB */
  availableMemory: number;
  /** Total memory in MB */
  totalMemory: number;
  /** Memory usage percentage (0-100) */
  memoryUsage: number;
}

/**
 * Worker thread status
 */
interface WorkerStatus {
  /** Worker ID */
  id: string;
  /** Worker thread */
  worker: Worker;
  /** Item being processed */
  item?: BatchItem;
  /** Start time */
  startTime?: number;
  /** Whether the worker is active */
  active: boolean;
  /** Memory usage in MB */
  memoryUsage?: number;
}

/**
 * Enhanced batch processor with worker thread-based parallelism
 */
export class ParallelBatchProcessor extends EventEmitter {
  private logger: Logger;
  private workers: Map<string, WorkerStatus> = new Map();
  private queue: BatchItem[] = [];
  private results: Map<string, any> = new Map();
  private workerPath: string;
  private isProcessing: boolean = false;
  private totalItems: number = 0;
  private processedItems: number = 0;
  private resourceCheckInterval: NodeJS.Timeout | null = null;
  
  /**
   * Constructor
   */
  constructor() {
    super();
    
    this.logger = new Logger('parallel-batch-processor', {
      level: (process.env.LOG_LEVEL as LogLevel) || LogLevel.INFO
    });
    
    // Path to the worker script
    this.workerPath = path.join(__dirname, 'BatchWorker.js');
  }
  
  /**
   * Process a batch of items in parallel
   * 
   * @param items Array of items to process
   * @param options Batch processing options
   * @returns Processing results
   */
  async processBatch(
    items: BatchItem[],
    options: BatchProcessingOptions = {}
  ): Promise<BatchProcessingResult> {
    const startTime = Date.now();
    const batchId = uuid();
    
    this.logger.info(`Starting batch processing (ID: ${batchId}) with ${items.length} items`);
    
    // Set default options
    const mergedOptions = {
      maxConcurrency: options.maxConcurrency || Math.max(1, os.cpus().length - 1),
      continueOnError: options.continueOnError ?? true,
      prioritizeItems: options.prioritizeItems ?? true,
      useWorkerThreads: options.useWorkerThreads ?? true,
      dynamicConcurrency: options.dynamicConcurrency ?? true,
      workerMemoryLimit: options.workerMemoryLimit || 512,
      ...options
    };
    
    this.logger.debug(`Batch options: ${JSON.stringify(mergedOptions, null, 2)}`);
    
    // Prepare items and initialize results
    this.queue = items.map((item) => ({
      ...item,
      id: item.id || uuid(),
      priority: item.priority || 0
    }));
    
    this.totalItems = this.queue.length;
    this.processedItems = 0;
    this.results.clear();
    this.isProcessing = true;
    
    // Set up resource monitoring if dynamic concurrency is enabled
    if (mergedOptions.dynamicConcurrency) {
      this.startResourceMonitoring();
    }
    
    try {
      // Sort queue by priority if enabled
      if (mergedOptions.prioritizeItems) {
        this.queue.sort((a, b) => (b.priority || 0) - (a.priority || 0));
      }
      
      // Process items using worker threads if enabled and available
      if (mergedOptions.useWorkerThreads && typeof Worker !== 'undefined') {
        await this.processWithWorkers(mergedOptions);
      } else {
        // Fall back to legacy processing (implemented elsewhere)
        throw new Error("Legacy batch processing not implemented in ParallelBatchProcessor");
      }
      
      // Compile results
      const endTime = Date.now();
      const successful = Array.from(this.results.values())
        .filter(r => r.status === 'success').length;
      const failed = Array.from(this.results.values())
        .filter(r => r.status === 'error').length;
      
      const result: BatchProcessingResult = {
        batchId,
        processed: this.processedItems,
        successful,
        failed,
        items: Array.from(this.results.values()),
        totalTime: endTime - startTime
      };
      
      this.logger.info(
        `Batch processing completed: ${successful} successful, ${failed} failed, ` +
        `total time: ${result.totalTime}ms`
      );
      
      return result;
    } finally {
      // Clean up
      this.isProcessing = false;
      this.terminateAllWorkers();
      
      if (this.resourceCheckInterval) {
        clearInterval(this.resourceCheckInterval);
        this.resourceCheckInterval = null;
      }
    }
  }
  
  /**
   * Start monitoring system resources
   */
  private startResourceMonitoring() {
    this.resourceCheckInterval = setInterval(() => {
      const resources = this.getSystemResources();
      this.logger.debug(`System resources: ${JSON.stringify(resources)}`);
      
      // Emit resource metrics
      this.emit('resources', resources);
    }, 5000);
  }
  
  /**
   * Get current system resource usage
   */
  private getSystemResources(): SystemResources {
    const totalMemory = os.totalmem() / (1024 * 1024); // MB
    const freeMemory = os.freemem() / (1024 * 1024); // MB
    const availableMemory = freeMemory;
    const memoryUsage = ((totalMemory - freeMemory) / totalMemory) * 100;
    
    // Calculate CPU usage (average across cores)
    const cpuUsage = os.loadavg()[0] * 100 / os.cpus().length;
    
    return {
      cpuUsage,
      availableMemory,
      totalMemory,
      memoryUsage
    };
  }
  
  /**
   * Process items using worker threads
   * 
   * @param options Batch processing options
   */
  private async processWithWorkers(options: BatchProcessingOptions): Promise<void> {
    // Calculate initial concurrency
    let concurrency = options.maxConcurrency || Math.max(1, os.cpus().length - 1);
    
    // Create initial worker pool
    for (let i = 0; i < concurrency; i++) {
      this.createIdleWorker();
    }
    
    // Process items in the queue
    while (this.queue.length > 0 || this.hasActiveWorkers()) {
      // Adjust concurrency if dynamic concurrency is enabled
      if (options.dynamicConcurrency) {
        concurrency = this.adjustConcurrency(options);
      }
      
      // Get idle workers
      const idleWorkers = this.getIdleWorkers();
      
      // Only create new workers if needed
      while (idleWorkers.length < concurrency && this.workers.size < concurrency) {
        idleWorkers.push(this.createIdleWorker());
      }
      
      // Assign work to idle workers
      for (const worker of idleWorkers) {
        // Check if queue is empty
        if (this.queue.length === 0) {
          break;
        }
        
        // Get next item from queue
        const item = this.queue.shift();
        if (!item) continue;
        
        // Assign work to worker
        this.assignWorkToWorker(worker, item, options);
      }
      
      // Wait a bit before checking again
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  /**
   * Adjust concurrency based on system load
   * 
   * @param options Batch processing options
   * @returns Adjusted concurrency level
   */
  private adjustConcurrency(options: BatchProcessingOptions): number {
    const resources = this.getSystemResources();
    const maxConcurrency = options.maxConcurrency || Math.max(1, os.cpus().length - 1);
    
    // Adjust based on CPU usage
    let adjustedConcurrency = maxConcurrency;
    
    if (resources.cpuUsage > 90) {
      // High CPU usage, reduce concurrency
      adjustedConcurrency = Math.max(1, Math.floor(maxConcurrency * 0.5));
    } else if (resources.cpuUsage > 70) {
      // Moderate CPU usage, slightly reduce concurrency
      adjustedConcurrency = Math.max(1, Math.floor(maxConcurrency * 0.75));
    } else if (resources.cpuUsage < 30) {
      // Low CPU usage, can increase concurrency if memory allows
      adjustedConcurrency = Math.min(maxConcurrency + 2, os.cpus().length * 2);
    }
    
    // Further adjust based on memory constraints
    const workerMemoryLimit = options.workerMemoryLimit || 512; // MB
    const maxWorkersByMemory = Math.floor(resources.availableMemory / workerMemoryLimit);
    
    // Take the minimum value to ensure we don't exceed resources
    adjustedConcurrency = Math.max(1, Math.min(adjustedConcurrency, maxWorkersByMemory));
    
    return adjustedConcurrency;
  }
  
  /**
   * Create a new idle worker
   * 
   * @returns Worker status object
   */
  private createIdleWorker(): WorkerStatus {
    const workerId = uuid();
    
    try {
      const worker = new Worker(this.workerPath);
      
      const workerStatus: WorkerStatus = {
        id: workerId,
        worker,
        active: false
      };
      
      // Set up event handlers for the worker
      worker.on('message', (message) => {
        this.handleWorkerMessage(workerId, message);
      });
      
      worker.on('error', (error) => {
        this.logger.error(`Worker ${workerId} error: ${error.message}`);
        
        // Handle item failure
        const workerStatus = this.workers.get(workerId);
        if (workerStatus && workerStatus.item) {
          this.results.set(workerStatus.item.id, {
            id: workerStatus.item.id,
            status: 'error',
            error: error.message,
            processingTime: workerStatus.startTime ? Date.now() - workerStatus.startTime : 0
          });
          
          this.processedItems++;
          this.emit('progress', (this.processedItems / this.totalItems) * 100);
        }
        
        // Remove the worker
        this.workers.delete(workerId);
        
        // Create a replacement worker
        this.createIdleWorker();
      });
      
      worker.on('exit', (code) => {
        this.logger.debug(`Worker ${workerId} exited with code ${code}`);
        this.workers.delete(workerId);
      });
      
      // Add to worker pool
      this.workers.set(workerId, workerStatus);
      
      return workerStatus;
    } catch (error) {
      this.logger.error(`Failed to create worker: ${error.message}`);
      throw error;
    }
  }
  
  /**
   * Assign work to a worker
   * 
   * @param workerStatus Worker status object
   * @param item Item to process
   * @param options Batch processing options
   */
  private assignWorkToWorker(
    workerStatus: WorkerStatus,
    item: BatchItem,
    options: BatchProcessingOptions
  ): void {
    try {
      const { id: workerId, worker } = workerStatus;
      
      this.logger.debug(`Assigning item ${item.id} to worker ${workerId}`);
      
      // Update worker status
      workerStatus.item = item;
      workerStatus.startTime = Date.now();
      workerStatus.active = true;
      
      // Send work to worker
      worker.postMessage({
        itemId: item.id,
        content: item.content,
        contentType: item.contentType,
        options: {
          ...options,
          ...item.options
        }
      });
    } catch (error) {
      this.logger.error(`Failed to assign work to worker: ${error.message}`);
      
      // Handle item failure
      this.results.set(item.id, {
        id: item.id,
        status: 'error',
        error: error.message,
        processingTime: 0
      });
      
      this.processedItems++;
      this.emit('progress', (this.processedItems / this.totalItems) * 100);
      
      // Reset worker status
      workerStatus.item = undefined;
      workerStatus.startTime = undefined;
      workerStatus.active = false;
    }
  }
  
  /**
   * Handle a message from a worker
   * 
   * @param workerId Worker ID
   * @param message Message from worker
   */
  private handleWorkerMessage(workerId: string, message: any): void {
    const workerStatus = this.workers.get(workerId);
    if (!workerStatus) {
      this.logger.warn(`Received message from unknown worker ${workerId}`);
      return;
    }
    
    // Calculate processing time
    const processingTime = workerStatus.startTime ? Date.now() - workerStatus.startTime : 0;
    
    if (message.status === 'success') {
      // Handle successful processing
      this.logger.debug(`Worker ${workerId} successfully processed item ${message.itemId}`);
      
      this.results.set(message.itemId, {
        id: message.itemId,
        status: 'success',
        result: message.result,
        processingTime
      });
    } else if (message.status === 'error') {
      // Handle processing error
      this.logger.warn(`Worker ${workerId} failed to process item ${message.itemId}: ${message.error.message}`);
      
      this.results.set(message.itemId, {
        id: message.itemId,
        status: 'error',
        error: message.error.message,
        processingTime
      });
    }
    
    // Update progress
    this.processedItems++;
    const progressPercentage = (this.processedItems / this.totalItems) * 100;
    this.emit('progress', progressPercentage);
    
    // Reset worker status
    workerStatus.item = undefined;
    workerStatus.startTime = undefined;
    workerStatus.active = false;
  }
  
  /**
   * Check if there are any active workers
   * 
   * @returns True if any workers are active
   */
  private hasActiveWorkers(): boolean {
    for (const workerStatus of this.workers.values()) {
      if (workerStatus.active) {
        return true;
      }
    }
    return false;
  }
  
  /**
   * Get a list of idle workers
   * 
   * @returns Array of idle worker status objects
   */
  private getIdleWorkers(): WorkerStatus[] {
    const idleWorkers: WorkerStatus[] = [];
    
    for (const workerStatus of this.workers.values()) {
      if (!workerStatus.active) {
        idleWorkers.push(workerStatus);
      }
    }
    
    return idleWorkers;
  }
  
  /**
   * Terminate all workers
   */
  private terminateAllWorkers(): void {
    for (const workerStatus of this.workers.values()) {
      try {
        workerStatus.worker.terminate();
      } catch (error) {
        this.logger.warn(`Failed to terminate worker ${workerStatus.id}: ${error.message}`);
      }
    }
    
    this.workers.clear();
  }
  
  /**
   * Cancel processing
   */
  cancel(): void {
    this.logger.info('Cancelling batch processing');
    
    // Clear the queue
    this.queue = [];
    
    // Terminate all workers
    this.terminateAllWorkers();
    
    // Reset processing state
    this.isProcessing = false;
    
    // Stop resource monitoring
    if (this.resourceCheckInterval) {
      clearInterval(this.resourceCheckInterval);
      this.resourceCheckInterval = null;
    }
  }
}