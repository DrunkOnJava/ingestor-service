// This file is used to set up the test environment
// It runs before each test file is executed

// Set environment variables for testing
process.env.NODE_ENV = 'test';
process.env.INGESTOR_HOME = '/tmp/ingestor-test';
process.env.DATABASE_DIR = '/tmp/ingestor-test/databases';
process.env.LOG_LEVEL = 'error'; // Reduce logging noise during tests
process.env.API_PORT = '4000'; // Use a different port for testing
process.env.TEST_MODE = 'true';

// Setup test database name with timestamp to avoid conflicts
process.env.TEST_DB = `test_db_${Date.now()}`;

// Configure test timeouts
jest.setTimeout(15000); // 15 seconds for each test

// Mock global objects
global.fetch = jest.fn();

// Mock WebSocket for API tests
jest.mock('ws', () => {
  const WebSocket = jest.fn();
  WebSocket.prototype.on = jest.fn();
  WebSocket.prototype.send = jest.fn();
  WebSocket.prototype.close = jest.fn();
  WebSocket.prototype.terminate = jest.fn();
  WebSocket.Server = jest.fn().mockImplementation(() => ({
    on: jest.fn(),
    close: jest.fn(),
    clients: new Set(),
    handleUpgrade: jest.fn()
  }));
  return { WebSocket };
});

// Mock UUID to return predictable IDs in tests when needed
jest.mock('uuid', () => ({
  v4: jest.fn().mockReturnValue('00000000-0000-0000-0000-000000000000')
}));

// Suppress console output during tests (optional)
// Comment these out if you want to see console output during tests
// Or set LOG_LEVEL to 'debug' to see all logs
global.console.log = jest.fn();
global.console.info = jest.fn();
global.console.warn = jest.fn();
global.console.error = jest.fn();