import { ContentProcessor } from '../../../../src/core/content/ContentProcessor';
import { EntityType } from '../../../../src/core/entity/types/EntityTypes';
import { MockLogger, MockClaudeService, MockFileSystem, createTestEntity } from '../../../mocks';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

// Mock entity manager
const mockEntityManager = {
  extract: jest.fn().mockResolvedValue({
    entities: [
      createTestEntity('John Doe', EntityType.PERSON),
      createTestEntity('Acme Corp', EntityType.ORGANIZATION)
    ],
    processingTime: 42,
    confidence: 0.95,
    contentLength: 500
  }),
  extractFromFile: jest.fn().mockResolvedValue({
    entities: [
      createTestEntity('Jane Smith', EntityType.PERSON),
      createTestEntity('TechCorp', EntityType.ORGANIZATION)
    ],
    processingTime: 56,
    confidence: 0.92,
    contentLength: 1000
  }),
  storeEntity: jest.fn().mockResolvedValue(1)
};

// Mock content type detector
const mockContentTypeDetector = {
  detectContentType: jest.fn().mockImplementation((filePath: string) => {
    if (filePath.endsWith('.txt')) return 'text/plain';
    if (filePath.endsWith('.html')) return 'text/html';
    if (filePath.endsWith('.js')) return 'text/javascript';
    if (filePath.endsWith('.pdf')) return 'application/pdf';
    if (filePath.endsWith('.jpg') || filePath.endsWith('.jpeg')) return 'image/jpeg';
    if (filePath.endsWith('.png')) return 'image/png';
    if (filePath.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  })
};

describe('ContentProcessor', () => {
  let mockLogger: MockLogger;
  let mockClaudeService: MockClaudeService;
  let mockFileSystem: MockFileSystem;
  let contentProcessor: ContentProcessor;
  let tempDir: string;
  
  beforeAll(() => {
    // Create a temporary directory for testing
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ingestor-test-content-'));
  });
  
  afterAll(() => {
    // Clean up the temporary directory
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (error) {
      console.error(`Error cleaning up temporary directory: ${error}`);
    }
  });
  
  beforeEach(() => {
    // Reset mocks
    mockLogger = new MockLogger();
    mockClaudeService = new MockClaudeService();
    mockFileSystem = new MockFileSystem();
    
    // Create the content processor
    contentProcessor = new ContentProcessor(
      mockLogger,
      mockFileSystem,
      mockClaudeService,
      mockEntityManager as any
    );
    
    // Add the content type detector
    (contentProcessor as any).contentTypeDetector = mockContentTypeDetector;
    
    // Add some mock files for testing
    mockFileSystem.addMockFile(
      path.join(tempDir, 'sample.txt'),
      'This is a sample text file about John Doe who works at Acme Corp.'
    );
    
    mockFileSystem.addMockFile(
      path.join(tempDir, 'code.js'),
      'function process() {\n  console.log("Processing");\n}'
    );
    
    // Reset mock functions
    mockEntityManager.extract.mockClear();
    mockEntityManager.extractFromFile.mockClear();
    mockEntityManager.storeEntity.mockClear();
    mockContentTypeDetector.detectContentType.mockClear();
  });
  
  describe('processContent', () => {
    it('should process raw content with the correct content type', async () => {
      const content = 'This is raw content to process.';
      const contentType = 'text/plain';
      
      const result = await contentProcessor.processContent(content, contentType);
      
      // Should have called entity manager to extract entities
      expect(mockEntityManager.extract).toHaveBeenCalledWith(content, contentType);
      
      // Should return extraction results
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(2);
      expect(result.confidence).toBeGreaterThan(0);
      
      // Should have stored entities if storeResults is true
      expect(mockEntityManager.storeEntity).toHaveBeenCalledTimes(2);
    });
    
    it('should not store entities if storeResults is false', async () => {
      const content = 'This is raw content to process.';
      const contentType = 'text/plain';
      
      const result = await contentProcessor.processContent(content, contentType, {
        storeResults: false
      });
      
      // Should have called entity manager to extract entities
      expect(mockEntityManager.extract).toHaveBeenCalledWith(content, contentType);
      
      // Should return extraction results
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(2);
      
      // Should NOT have stored entities
      expect(mockEntityManager.storeEntity).not.toHaveBeenCalled();
    });
    
    it('should apply content filters when specified', async () => {
      const content = 'This is raw content with SENSITIVE_INFO that should be filtered.';
      const contentType = 'text/plain';
      
      // Define a filter function
      const filterFunc = (text: string) => text.replace('SENSITIVE_INFO', '[REDACTED]');
      
      const result = await contentProcessor.processContent(content, contentType, {
        filters: [filterFunc]
      });
      
      // Should have called entity manager with filtered content
      expect(mockEntityManager.extract).toHaveBeenCalledWith(
        expect.not.stringContaining('SENSITIVE_INFO'),
        contentType
      );
      
      // Make sure the extract call contains the redacted text
      const extractCall = mockEntityManager.extract.mock.calls[0][0];
      expect(extractCall).toContain('[REDACTED]');
    });
  });
  
  describe('processFile', () => {
    it('should process a file with the correct content type detection', async () => {
      const filePath = path.join(tempDir, 'sample.txt');
      
      const result = await contentProcessor.processFile(filePath);
      
      // Should have detected content type
      expect(mockContentTypeDetector.detectContentType).toHaveBeenCalledWith(filePath);
      
      // Should have called entity manager to extract entities from file
      expect(mockEntityManager.extractFromFile).toHaveBeenCalledWith(filePath);
      
      // Should return extraction results
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(2);
      expect(result.confidence).toBeGreaterThan(0);
      
      // Should have stored entities if storeResults is true
      expect(mockEntityManager.storeEntity).toHaveBeenCalledTimes(2);
    });
    
    it('should process a file with an explicitly provided content type', async () => {
      const filePath = path.join(tempDir, 'sample.txt');
      const explicitContentType = 'application/custom';
      
      const result = await contentProcessor.processFile(filePath, {
        contentType: explicitContentType
      });
      
      // Should NOT have detected content type
      expect(mockContentTypeDetector.detectContentType).not.toHaveBeenCalled();
      
      // Should have called entity manager to extract entities from file
      expect(mockEntityManager.extractFromFile).toHaveBeenCalledWith(filePath);
      
      // Should return extraction results
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(2);
    });
    
    it('should not store entities if storeResults is false', async () => {
      const filePath = path.join(tempDir, 'sample.txt');
      
      const result = await contentProcessor.processFile(filePath, {
        storeResults: false
      });
      
      // Should have called entity manager to extract entities
      expect(mockEntityManager.extractFromFile).toHaveBeenCalledWith(filePath);
      
      // Should return extraction results
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(2);
      
      // Should NOT have stored entities
      expect(mockEntityManager.storeEntity).not.toHaveBeenCalled();
    });
  });
  
  describe('chunking', () => {
    it('should process large content in chunks when chunk size is specified', async () => {
      // Create large content (larger than default chunk size)
      const largeContent = 'A'.repeat(20000);
      const contentType = 'text/plain';
      
      // Set up a spy on the internal _processChunk method
      const processChunkSpy = jest.spyOn(contentProcessor as any, '_processChunk');
      
      const result = await contentProcessor.processContent(largeContent, contentType, {
        chunkSize: 5000, // Smaller chunk size for testing
        chunkOverlap: 500
      });
      
      // Should have called _processChunk multiple times
      expect(processChunkSpy).toHaveBeenCalledTimes(4); // 20000 / 5000 = 4 chunks
      
      // Should have combined results from all chunks
      expect(result).toBeDefined();
      expect(result.chunks).toBeDefined();
      expect(result.chunks?.length).toBe(4);
      
      // Clean up spy
      processChunkSpy.mockRestore();
    });
    
    it('should handle file chunking properly', async () => {
      // Create a large file
      const largeFilePath = path.join(tempDir, 'large.txt');
      const largeContent = 'A'.repeat(20000);
      mockFileSystem.addMockFile(largeFilePath, largeContent);
      
      // Set up a spy on the internal _processFileInChunks method
      const processFileInChunksSpy = jest.spyOn(contentProcessor as any, '_processFileInChunks');
      
      const result = await contentProcessor.processFile(largeFilePath, {
        chunkSize: 5000, // Smaller chunk size for testing
        chunkOverlap: 500
      });
      
      // Should have called _processFileInChunks
      expect(processFileInChunksSpy).toHaveBeenCalled();
      
      // Should have read the file
      expect(mockFileSystem.calls.some(c => c.method === 'readFile')).toBe(true);
      
      // Should have combined results
      expect(result).toBeDefined();
      expect(result.chunks).toBeDefined();
      
      // Clean up spy
      processFileInChunksSpy.mockRestore();
    });
  });
  
  describe('content filtering', () => {
    it('should apply multiple content filters in sequence', async () => {
      const content = 'This is SECRET content with SENSITIVE data.';
      const contentType = 'text/plain';
      
      // Define multiple filter functions
      const filter1 = (text: string) => text.replace('SECRET', '[REDACTED]');
      const filter2 = (text: string) => text.replace('SENSITIVE', '[CONFIDENTIAL]');
      
      const result = await contentProcessor.processContent(content, contentType, {
        filters: [filter1, filter2]
      });
      
      // Should have called entity manager with doubly-filtered content
      expect(mockEntityManager.extract).toHaveBeenCalledWith(
        expect.stringContaining('[REDACTED]'),
        contentType
      );
      
      const extractCall = mockEntityManager.extract.mock.calls[0][0];
      expect(extractCall).toContain('[REDACTED]');
      expect(extractCall).toContain('[CONFIDENTIAL]');
    });
  });
  
  describe('error handling', () => {
    it('should handle extraction errors gracefully', async () => {
      // Make extract throw an error
      mockEntityManager.extract.mockRejectedValueOnce(new Error('Extraction failed'));
      
      const content = 'This content will cause an error.';
      const contentType = 'text/plain';
      
      // Should not throw but return error info
      const result = await contentProcessor.processContent(content, contentType);
      
      expect(result).toBeDefined();
      expect(result.error).toBeDefined();
      expect(result.error?.message).toBe('Extraction failed');
      
      // Should log error
      expect(mockLogger.logs.some(log => 
        log.level === 'error' && log.message.includes('extraction')
      )).toBe(true);
    });
    
    it('should handle file processing errors gracefully', async () => {
      // Make file read throw an error
      mockFileSystem.readFile.mockRejectedValueOnce(new Error('File read failed'));
      
      const nonExistentFile = path.join(tempDir, 'nonexistent.txt');
      
      // Should not throw but return error info
      const result = await contentProcessor.processFile(nonExistentFile);
      
      expect(result).toBeDefined();
      expect(result.error).toBeDefined();
      expect(result.error?.message).toBe('File read failed');
      
      // Should log error
      expect(mockLogger.logs.some(log => 
        log.level === 'error' && log.message.includes('file')
      )).toBe(true);
    });
  });
});