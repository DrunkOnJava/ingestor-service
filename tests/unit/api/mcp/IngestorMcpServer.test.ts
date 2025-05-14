import { IngestorMcpServer } from '../../../../src/api/mcp/IngestorMcpServer';
import { MockLogger } from '../../../mocks';
import * as http from 'http';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';

// Mock http server
jest.mock('http', () => {
  const mockServer = {
    listen: jest.fn().mockImplementation((port, callback) => {
      if (callback) callback();
      return mockServer;
    }),
    close: jest.fn().mockImplementation(callback => {
      if (callback) callback(null);
      return mockServer;
    })
  };
  
  return {
    ...jest.requireActual('http'),
    createServer: jest.fn().mockReturnValue(mockServer),
    Server: jest.fn().mockImplementation(() => mockServer)
  };
});

// Mock process.stdout and process.stdin
const mockStdout = {
  write: jest.fn()
};

const mockStdin = {
  on: jest.fn().mockImplementation((event, callback) => {
    if (event === 'data') {
      // Store the callback for later triggering
      mockStdin.dataCallback = callback;
    }
    return mockStdin;
  }),
  dataCallback: null,
  // Helper to simulate data received on stdin
  simulateData: (data: string) => {
    if (mockStdin.dataCallback) {
      mockStdin.dataCallback(Buffer.from(data, 'utf-8'));
    }
  }
};

// Save original process.stdout and process.stdin
const originalStdout = process.stdout;
const originalStdin = process.stdin;

describe('IngestorMcpServer', () => {
  let mockLogger: MockLogger;
  let tempDir: string;
  
  beforeAll(() => {
    // Replace process.stdout and process.stdin with mocks
    Object.defineProperty(process, 'stdout', {
      value: mockStdout,
      writable: true
    });
    
    Object.defineProperty(process, 'stdin', {
      value: mockStdin,
      writable: true
    });
    
    // Create a temporary directory for testing
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ingestor-test-'));
  });
  
  afterAll(() => {
    // Restore original process.stdout and process.stdin
    Object.defineProperty(process, 'stdout', {
      value: originalStdout,
      writable: true
    });
    
    Object.defineProperty(process, 'stdin', {
      value: originalStdin,
      writable: true
    });
    
    // Clean up the temporary directory
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (error) {
      console.error(`Error cleaning up temporary directory: ${error}`);
    }
  });
  
  beforeEach(() => {
    mockLogger = new MockLogger();
    
    // Clear mock data
    mockStdout.write.mockClear();
    mockStdin.on.mockClear();
    http.createServer.mockClear();
  });
  
  describe('initialization', () => {
    it('should initialize with stdio transport by default', () => {
      const server = new IngestorMcpServer({
        ingestorHome: tempDir
      });
      
      expect(server).toBeDefined();
      // Private property access for testing
      expect((server as any).config.transport).toBe('stdio');
    });
    
    it('should initialize with http transport when specified', () => {
      const server = new IngestorMcpServer({
        transport: 'http',
        port: 8080,
        ingestorHome: tempDir
      });
      
      expect(server).toBeDefined();
      expect((server as any).config.transport).toBe('http');
      expect((server as any).config.port).toBe(8080);
    });
  });
  
  describe('start', () => {
    it('should start stdio transport and set up event handlers', async () => {
      const server = new IngestorMcpServer({
        ingestorHome: tempDir,
        transport: 'stdio'
      });
      
      // Replace the logger with our mock
      (server as any).logger = mockLogger;
      
      await server.start();
      
      // Should have set up stdin handlers
      expect(mockStdin.on).toHaveBeenCalledWith('data', expect.any(Function));
      
      // Should log startup
      expect(mockLogger.logs.some(log => 
        log.level === 'info' && log.message.includes('started')
      )).toBe(true);
    });
    
    it('should start http transport and create server', async () => {
      const server = new IngestorMcpServer({
        ingestorHome: tempDir,
        transport: 'http',
        port: 8080
      });
      
      // Replace the logger with our mock
      (server as any).logger = mockLogger;
      
      await server.start();
      
      // Should have created http server
      expect(http.createServer).toHaveBeenCalled();
      
      // Should log startup with port
      expect(mockLogger.logs.some(log => 
        log.level === 'info' && 
        log.message.includes('started') && 
        log.message.includes('8080')
      )).toBe(true);
    });
  });
  
  describe('stop', () => {
    it('should stop stdio transport gracefully', async () => {
      const server = new IngestorMcpServer({
        ingestorHome: tempDir,
        transport: 'stdio'
      });
      
      // Replace the logger with our mock
      (server as any).logger = mockLogger;
      
      await server.start();
      await server.stop();
      
      // Should log shutdown
      expect(mockLogger.logs.some(log => 
        log.level === 'info' && log.message.includes('stopped')
      )).toBe(true);
    });
    
    it('should stop http transport and close server', async () => {
      const server = new IngestorMcpServer({
        ingestorHome: tempDir,
        transport: 'http',
        port: 8080
      });
      
      // Replace the logger with our mock
      (server as any).logger = mockLogger;
      
      await server.start();
      
      // Get reference to mock http server
      const mockHttpServer = (server as any).httpServer;
      
      await server.stop();
      
      // Should have closed http server
      expect(mockHttpServer.close).toHaveBeenCalled();
      
      // Should log shutdown
      expect(mockLogger.logs.some(log => 
        log.level === 'info' && log.message.includes('stopped')
      )).toBe(true);
    });
  });
  
  describe('MCP message handling', () => {
    let server: IngestorMcpServer;
    
    beforeEach(async () => {
      server = new IngestorMcpServer({
        ingestorHome: tempDir,
        transport: 'stdio'
      });
      
      // Replace the logger with our mock
      (server as any).logger = mockLogger;
      
      // Create a spy for the handleMessage method
      jest.spyOn(server as any, 'handleMessage');
      
      await server.start();
    });
    
    afterEach(async () => {
      await server.stop();
      jest.restoreAllMocks();
    });
    
    it('should handle valid MCP messages', () => {
      // Simulate receiving a valid MCP message
      const message = JSON.stringify({
        type: 'tool_call',
        toolCall: {
          id: 'test-call-1',
          name: 'extract_entities',
          parameters: {
            content: 'John Doe works at Acme Corp in New York.',
            contentType: 'text/plain'
          }
        }
      });
      
      mockStdin.simulateData(message + '\\n');
      
      // Should have called handleMessage
      expect((server as any).handleMessage).toHaveBeenCalledWith(expect.any(Object));
      
      // Should have written a response
      expect(mockStdout.write).toHaveBeenCalled();
    });
    
    it('should handle invalid JSON gracefully', () => {
      // Simulate receiving invalid JSON
      mockStdin.simulateData('invalid json\\n');
      
      // Should log an error
      expect(mockLogger.logs.some(log => 
        log.level === 'error' && log.message.includes('parse')
      )).toBe(true);
    });
    
    it('should handle unknown message types gracefully', () => {
      // Simulate receiving an unknown message type
      const message = JSON.stringify({
        type: 'unknown_type',
        data: {}
      });
      
      mockStdin.simulateData(message + '\\n');
      
      // Should log a warning
      expect(mockLogger.logs.some(log => 
        log.level === 'warn' && log.message.includes('Unknown message type')
      )).toBe(true);
    });
  });
  
  describe('MCP tools', () => {
    let server: IngestorMcpServer;
    
    beforeEach(async () => {
      server = new IngestorMcpServer({
        ingestorHome: tempDir,
        transport: 'stdio'
      });
      
      // Replace the logger with our mock
      (server as any).logger = mockLogger;
      
      // Spy on response method
      jest.spyOn(server as any, 'sendResponse');
      
      await server.start();
    });
    
    afterEach(async () => {
      await server.stop();
      jest.restoreAllMocks();
    });
    
    it('should handle extract_entities tool call', () => {
      // Create tool call for extracting entities
      const toolCall = {
        id: 'test-call-1',
        name: 'extract_entities',
        parameters: {
          content: 'John Doe works at Acme Corp in New York.',
          contentType: 'text/plain'
        }
      };
      
      // Call the handler directly
      (server as any).handleToolCall(toolCall);
      
      // Should have sent a response
      expect((server as any).sendResponse).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'tool_response',
          toolResponse: expect.objectContaining({
            id: 'test-call-1'
          })
        })
      );
    });
    
    it('should handle extract_entities_from_file tool call', () => {
      // Create a test file
      const testFilePath = path.join(tempDir, 'test-file.txt');
      fs.writeFileSync(testFilePath, 'John Doe works at Acme Corp in New York.');
      
      // Create tool call for extracting entities from file
      const toolCall = {
        id: 'test-call-2',
        name: 'extract_entities_from_file',
        parameters: {
          filePath: testFilePath
        }
      };
      
      // Call the handler directly
      (server as any).handleToolCall(toolCall);
      
      // Should have sent a response
      expect((server as any).sendResponse).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'tool_response',
          toolResponse: expect.objectContaining({
            id: 'test-call-2'
          })
        })
      );
    });
    
    it('should handle store_entity tool call', () => {
      // Create tool call for storing an entity
      const toolCall = {
        id: 'test-call-3',
        name: 'store_entity',
        parameters: {
          name: 'Acme Corporation',
          type: 'organization',
          description: 'A fictional company'
        }
      };
      
      // Call the handler directly
      (server as any).handleToolCall(toolCall);
      
      // Should have sent a response
      expect((server as any).sendResponse).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'tool_response',
          toolResponse: expect.objectContaining({
            id: 'test-call-3'
          })
        })
      );
    });
    
    it('should handle unknown tool calls gracefully', () => {
      // Create an unknown tool call
      const toolCall = {
        id: 'test-call-unknown',
        name: 'unknown_tool',
        parameters: {}
      };
      
      // Call the handler directly
      (server as any).handleToolCall(toolCall);
      
      // Should have sent an error response
      expect((server as any).sendResponse).toHaveBeenCalledWith(
        expect.objectContaining({
          type: 'tool_response',
          toolResponse: expect.objectContaining({
            id: 'test-call-unknown',
            status: 'error'
          })
        })
      );
      
      // Should log an error
      expect(mockLogger.logs.some(log => 
        log.level === 'error' && log.message.includes('Unknown tool')
      )).toBe(true);
    });
  });
});