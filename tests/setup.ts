// This file is used to set up the test environment
// It runs before each test file is executed

// Set environment variables for testing
process.env.NODE_ENV = 'test';
process.env.INGESTOR_HOME = '/tmp/ingestor-test';

// Configure test timeouts
jest.setTimeout(10000); // 10 seconds for each test

// Mock global objects if needed
// For example, if we're using fetch in our code:
global.fetch = jest.fn();

// Suppress console output during tests (optional)
// Comment these out if you want to see console output during tests
global.console.log = jest.fn();
global.console.info = jest.fn();
global.console.warn = jest.fn();
global.console.error = jest.fn();