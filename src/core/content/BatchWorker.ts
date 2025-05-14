/**
 * BatchWorker Module
 * 
 * Provides worker thread implementation for parallel content processing
 */

import { parentPort, workerData } from 'worker_threads';
import { ContentProcessor } from './ContentProcessor';

// Worker thread implementation
if (parentPort) {
  // Get worker data
  const { itemId, content, contentType, options } = workerData;
  
  // Create content processor
  const processor = new ContentProcessor();
  
  // Process content
  processor.process(content, contentType, options)
    .then(result => {
      // Send success result back to main thread
      parentPort.postMessage({
        status: 'success',
        itemId,
        result
      });
    })
    .catch(error => {
      // Send error result back to main thread
      parentPort.postMessage({
        status: 'error',
        itemId,
        error: {
          message: error.message,
          stack: error.stack
        }
      });
    });
  
  // Listen for messages from parent thread
  parentPort.on('message', message => {
    if (message === 'cancel') {
      // Clean up and exit
      process.exit(0);
    }
  });
}