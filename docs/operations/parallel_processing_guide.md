# Operational Guide: Parallel Processing

## Overview

This guide provides operational information for effectively using, configuring, and troubleshooting the parallel processing capabilities of the ingestor system. The parallel processing feature significantly improves performance for batch operations by leveraging worker threads for true parallel execution.

## When to Use Parallel Processing

Parallel processing provides the most benefit in these scenarios:

- **Large Batch Processing**: When processing multiple files at once (10+ files)
- **CPU-Intensive Operations**: For operations like entity extraction and content analysis
- **Multi-Core Systems**: On systems with 4+ CPU cores
- **Memory-Sufficient Environments**: When at least 4GB of RAM is available

Parallel processing may not be beneficial for:
- Single file processing
- I/O-bound operations (where disk or network is the bottleneck)
- Memory-constrained environments
- Systems with only 1-2 CPU cores

## Configuration Options

Parallel processing can be configured through the BatchProcessingOptions:

```typescript
const options = {
  // Enable or disable worker threads
  useWorkerThreads: true,
  
  // Maximum number of concurrent operations
  // Default: number of CPU cores - 1
  maxConcurrency: 8,
  
  // Adjust concurrency based on system load
  dynamicConcurrency: true,
  
  // Memory limit per worker in MB
  // Default: 512MB
  workerMemoryLimit: 512,
  
  // Process high-priority items first
  prioritizeItems: true
};

// Apply configuration
const result = await batchProcessor.processBatch(filePaths, options);
```

### Default Configuration

The default configuration is optimized for most systems and will:
- Enable worker threads if available
- Use (CPU cores - 1) for concurrency
- Enable dynamic adjustment of concurrency based on system load
- Set worker memory limit to 512MB
- Prioritize items by priority value

### Setting Global Defaults

To change default options for all batch operations:

```typescript
// Update default options
batchProcessor.setDefaultOptions({
  useWorkerThreads: true,
  maxConcurrency: 8,
  workerMemoryLimit: 1024 // 1GB per worker
});
```

## Performance Tuning

### Optimizing Concurrency

The `maxConcurrency` setting is crucial for performance:

- **Too Low**: Underutilizes system resources
- **Too High**: Causes resource contention and decreases performance

Recommendations:
- For CPU-intensive workloads: `number of CPU cores - 1`
- For balanced workloads: `number of CPU cores`
- For I/O-bound workloads: `number of CPU cores * 1.5`

### Memory Management

Each worker thread consumes memory. To prevent out-of-memory errors:

1. Adjust `workerMemoryLimit` based on your system's available memory:
   ```
   Safe workerMemoryLimit = (Available RAM - 1GB) / maxConcurrency
   ```

2. For very large files, consider reducing `maxConcurrency` or increasing the memory limit.

3. Enable `dynamicConcurrency` to automatically adjust based on system resources.

### Resource Monitoring

You can monitor system resources during processing:

```typescript
// Listen for resource events
batchProcessor.on('resources', (resources) => {
  console.log(`CPU Usage: ${resources.cpuUsage.toFixed(2)}%`);
  console.log(`Memory Usage: ${resources.memoryUsage.toFixed(2)}%`);
  console.log(`Available Memory: ${Math.round(resources.availableMemory)}MB`);
});
```

## Common Issues and Troubleshooting

### Worker Thread Creation Failures

**Symptoms**: 
- Error: "Cannot create worker thread"
- Fallback to standard processing

**Causes**:
- Node.js version doesn't support worker threads (< 12.x)
- Insufficient system resources
- OS limitations on thread creation

**Solutions**:
1. Upgrade Node.js to 12.x or later
2. Reduce `maxConcurrency`
3. Increase system resources
4. Check OS thread limits (`ulimit -u` on Linux)

### Out of Memory Errors

**Symptoms**:
- Process crashes with "JavaScript heap out of memory"
- Worker threads terminate unexpectedly

**Causes**:
- `workerMemoryLimit` set too high
- Too many concurrent workers
- Processing extremely large files

**Solutions**:
1. Reduce `workerMemoryLimit`
2. Decrease `maxConcurrency`
3. Enable `dynamicConcurrency`
4. Increase Node.js memory limit: `NODE_OPTIONS=--max-old-space-size=8192`

### Performance Degradation

**Symptoms**:
- Parallel processing is slower than expected
- CPU usage is low despite high concurrency

**Causes**:
- I/O bottlenecks
- Resource contention
- Inefficient file loading

**Solutions**:
1. Check disk I/O with tools like `iotop`
2. Verify network performance if files are remote
3. Try different `maxConcurrency` values to find optimal setting
4. Disable dynamic concurrency if it's reducing concurrency too aggressively

### Thread Communication Errors

**Symptoms**:
- "Cannot post message to worker" errors
- Tasks hang indefinitely

**Causes**:
- Worker thread crashed
- Communication channel issues
- Large data transfers between threads

**Solutions**:
1. Check for errors in worker thread
2. Reduce size of data being passed to worker threads
3. Restart the batch processor with `batchProcessor.shutdown()` and create a new instance

## Observability and Monitoring

### Logging

Parallel processing logs key events with these log levels:

- `INFO`: Batch start/end, worker thread creation
- `DEBUG`: Individual task assignments, worker status
- `TRACE`: Detailed worker communication, resource monitoring

To enable verbose logging:

```typescript
// Enable debug logging for parallel batch processor
logger.setLogLevel('parallel-batch-processor', LogLevel.DEBUG);
```

### Metrics

Key metrics to monitor:

1. **Processing Rate**: Files/items processed per second
2. **Success Rate**: Percentage of successfully processed items
3. **Worker Utilization**: Percentage of active workers
4. **Processing Time**: Average and max processing time per item
5. **Memory Usage**: Per worker and total system
6. **CPU Usage**: System-wide and per worker

### Health Checks

To verify parallel processing is functioning correctly:

```typescript
// Check if worker threads are available
const workerThreadsAvailable = typeof Worker !== 'undefined';

// Test parallel processing with a small batch
const testResult = await batchProcessor.processBatch(
  [testFile1, testFile2],
  { useWorkerThreads: true }
);

// Verify parallelism was used
console.log(`Parallel processing active: ${testResult.metadata?.usedParallelProcessing}`);
```

## Backup and Recovery

### Handling Interrupted Processing

If batch processing is interrupted:

1. The batch processor will automatically clean up worker threads on shutdown
2. Any partially processed items will be marked as failed
3. To resume processing:
   
   ```typescript
   // Get failed items from previous batch
   const failedItems = previousResult.errors.keys();
   
   // Process only failed items
   await batchProcessor.processBatch([...failedItems]);
   ```

### Cleaning Up Resources

Always call `shutdown()` when done with batch processing:

```typescript
// Clean up resources
batchProcessor.shutdown();
```

This ensures all worker threads are properly terminated and resources are released.

## Compatibility Considerations

### Backward Compatibility

The parallel processing implementation maintains backward compatibility:
- Same method signatures and return types
- Automatic fallback to standard processing if worker threads fail
- Compatible event emission patterns

### Platform Support

- **Node.js**: Full support in Node.js 12.x and later
- **Browsers**: Not supported (will automatically use standard processing)
- **Windows/Linux/macOS**: Fully supported on all major operating systems

## Best Practices

1. **Set Appropriate Concurrency**:
   - For most cases, `os.cpus().length - 1` is optimal
   - For memory-intensive operations, reduce concurrency

2. **Enable Dynamic Concurrency**:
   - Let the system adjust for optimal performance
   - Prevents resource exhaustion

3. **Careful Memory Management**:
   - Set `workerMemoryLimit` based on available system memory
   - Consider chunking very large files

4. **Clean Up Resources**:
   - Always call `shutdown()` when finished
   - Use try/finally blocks to ensure cleanup

5. **Monitor Performance**:
   - Listen for resource events
   - Track processing times and memory usage

6. **Error Handling**:
   - Set `continueOnError: true` for production workloads
   - Implement proper error logging and monitoring