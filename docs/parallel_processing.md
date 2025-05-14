# Parallel Processing

## Overview

The ingestor system includes enhanced parallel processing capabilities to optimize content ingestion performance. This document explains how to use these features and how they work.

## Using Parallel Processing

### Basic Usage

By default, the BatchProcessor will automatically use parallel processing when:
1. Worker threads are available (Node.js environment)
2. The `useWorkerThreads` option is enabled (true by default)

```typescript
import { BatchProcessor } from '../core/content/BatchProcessor';

// Create a batch processor
const batchProcessor = new BatchProcessor(logger, fs, contentProcessor);

// Process files (will use parallel processing by default)
const result = await batchProcessor.processBatch(filePaths);
```

### Configuration Options

You can customize the parallel processing behavior using the following options:

```typescript
// Configure batch processing
const result = await batchProcessor.processBatch(filePaths, {
  // Enable or disable worker threads
  useWorkerThreads: true,
  
  // Enable dynamic concurrency based on system load
  dynamicConcurrency: true,
  
  // Set maximum concurrency
  maxConcurrency: 8,
  
  // Set memory limit per worker (in MB)
  workerMemoryLimit: 512,
  
  // Process high-priority items first
  prioritizeItems: true
});
```

### Setting Default Options

You can set default options for all batch processing operations:

```typescript
// Update default options
batchProcessor.setDefaultOptions({
  useWorkerThreads: true,
  maxConcurrency: 8,
  workerMemoryLimit: 1024 // 1GB per worker
});
```

### Cleanup

When you're done with the batch processor, make sure to shut it down to clean up resources:

```typescript
// Clean up resources
batchProcessor.shutdown();
```

## How It Works

### Architecture

The parallel processing system consists of:

1. **BatchProcessor**: Main interface for batch processing with backward compatibility
2. **ParallelBatchProcessor**: Enhanced implementation using worker threads
3. **BatchWorker**: Worker thread implementation for content processing

```
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────┐
│ BatchProcessor  │────▶│ParallelBatchProcessor│────▶│ BatchWorker │
└─────────────────┘     └─────────────────────┘     └─────────────┘
                                  │                        │
                                  │                        │
                                  ▼                        ▼
                        ┌─────────────────────┐  ┌─────────────────┐
                        │ SystemResourceMonitor│  │ ContentProcessor│
                        └─────────────────────┘  └─────────────────┘
```

### Worker Threads

Parallel processing uses Node.js worker threads to process content in separate threads, allowing true parallel execution. Each worker thread:

1. Receives content to process
2. Creates a ContentProcessor instance 
3. Processes the content
4. Returns the result to the main thread

### Dynamic Concurrency

The system can dynamically adjust concurrency based on system resources:

- Monitors CPU usage and available memory
- Reduces concurrency when resources are low
- Increases concurrency when resources are available
- Ensures optimal performance without overloading the system

### Resource Monitoring

Resource monitoring provides insights into system performance:

```typescript
// Listen for resource events
batchProcessor.on('resources', (resources) => {
  console.log(`CPU Usage: ${resources.cpuUsage.toFixed(2)}%`);
  console.log(`Memory Usage: ${resources.memoryUsage.toFixed(2)}%`);
  console.log(`Available Memory: ${Math.round(resources.availableMemory)}MB`);
});
```

## Performance Considerations

- **CPU-Bound Operations**: Parallel processing provides the most benefit for CPU-bound operations
- **Memory Usage**: Adjust `workerMemoryLimit` based on your system's available memory
- **Disk I/O**: If operations are I/O-bound, increasing concurrency may not improve performance
- **Large Files**: For very large files, chunk processing is more important than parallel processing

## Backward Compatibility

The enhanced BatchProcessor maintains backward compatibility with existing code:

- Same interface and return types
- Automatic fallback to standard processing if parallel processing fails
- Consistent event emission for progress tracking

## Error Handling

Errors in worker threads are properly captured and reported:

- Worker errors are caught and included in the batch result
- Processing continues for other items (unless `continueOnError` is false)
- Detailed error information is available in the batch result

## Limitations

- Worker threads are not available in all JavaScript environments
- Each worker thread has memory overhead
- Some operations may not benefit from parallelization