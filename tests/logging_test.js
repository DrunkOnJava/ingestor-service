/**
 * Test script for the structured logger (Node.js version)
 */

const { logger, StructuredLogger } = require('../src/mcp/logger');
const fs = require('fs');
const path = require('path');

// Create a custom test directory
const TEST_LOG_DIR = path.join(__dirname, 'logs');
if (!fs.existsSync(TEST_LOG_DIR)) {
  fs.mkdirSync(TEST_LOG_DIR, { recursive: true });
}

// Test the logger
function testLogger() {
  console.log('Testing default logging (human-readable format):');
  
  // Basic logging
  logger.debug('This is a debug message');
  logger.info('This is an info message');
  logger.warn('This is a warning message');
  logger.error('This is an error message');
  
  console.log('\nTesting JSON logging:');
  
  // Configure for JSON format
  logger.configure({
    level: 'debug',
    format: 'json',
    directory: TEST_LOG_DIR,
    filename: 'test_structured.log'
  });
  
  // Log messages in JSON format
  logger.debug('This is a debug message in JSON format');
  logger.info('This is an info message in JSON format');
  
  // Log with additional fields
  logger.info('User action performed', {
    user: 'test_user',
    action: 'login',
    status: 'success'
  });
  
  // Log a metric
  logger.metric('request_time', 150, 'ms');
  
  // Log an event
  logger.event('user_login', 'info', {
    user: 'test_user',
    method: 'password'
  });
  
  // Test error with stack trace
  try {
    throw new Error('Test error');
  } catch (error) {
    logger.error('Something went wrong', error);
  }
  
  // Test child logger
  const dbLogger = logger.child({ module: 'database', component: 'query-executor' });
  dbLogger.info('Executing query', { query: 'SELECT * FROM users' });
  
  // Return to human-readable format for final message
  logger.configure({ format: 'human' });
  logger.info('Logging test complete');
  
  return path.join(TEST_LOG_DIR, 'test_structured.log');
}

// Run the test
const logFilePath = testLogger();

// Print log file path
console.log(`\nLog file written to: ${logFilePath}`);
console.log(`You can examine it with: cat ${logFilePath}`);

// Print a sample of the log file
console.log('\nSample JSON logs from file:');
try {
  if (fs.existsSync(logFilePath)) {
    const fileContent = fs.readFileSync(logFilePath, 'utf8');
    const lines = fileContent.split('\n').filter(line => line.includes('json format'));
    console.log(lines.slice(0, 2).join('\n'));
  }
} catch (error) {
  console.error('Error reading log file:', error);
}