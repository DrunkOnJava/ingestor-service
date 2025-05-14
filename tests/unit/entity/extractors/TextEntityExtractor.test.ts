import { TextEntityExtractor } from '../../../../src/core/entity/extractors/TextEntityExtractor';
import { EntityType, EntityExtractionOptions } from '../../../../src/core/entity/types/EntityTypes';
import { MockLogger, MockClaudeService, MockFileSystem } from '../../../mocks';

describe('TextEntityExtractor', () => {
  let mockLogger: MockLogger;
  let mockClaudeService: MockClaudeService;
  let mockFileSystem: MockFileSystem;
  let extractor: TextEntityExtractor;
  
  beforeEach(() => {
    // Set up mocks and extractor for each test
    mockLogger = new MockLogger();
    mockClaudeService = new MockClaudeService();
    mockFileSystem = new MockFileSystem();
    
    // Create test instance with mocks
    extractor = new TextEntityExtractor(
      mockLogger,
      { confidenceThreshold: 0.5 },
      mockClaudeService,
      mockFileSystem
    );
    
    // Add some mock files for testing
    mockFileSystem.addMockFile(
      '/test/sample.txt',
      'This is a test document about John Doe who works at Acme Corporation in New York.'
    );
    
    mockFileSystem.addMockFile(
      '/test/empty.txt',
      ''
    );
  });
  
  afterEach(() => {
    // Clear mocks between tests
    mockLogger.clearLogs();
    mockClaudeService.clearCalls();
    mockFileSystem.clearCalls();
  });
  
  describe('initialization', () => {
    it('should properly initialize with default options', () => {
      const defaultExtractor = new TextEntityExtractor(mockLogger);
      expect(defaultExtractor).toBeDefined();
    });
    
    it('should properly initialize with custom options', () => {
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.7,
        maxEntities: 20,
        includeTypes: [EntityType.PERSON, EntityType.ORGANIZATION]
      };
      
      const customExtractor = new TextEntityExtractor(mockLogger, options);
      expect(customExtractor).toBeDefined();
    });
  });
  
  describe('extract', () => {
    it('should extract entities from text content', async () => {
      const content = 'John works at Acme in New York.';
      
      const result = await extractor.extract(content, 'text/plain');
      
      // Verify the result has entities
      expect(result).toBeDefined();
      expect(result.entities).toBeDefined();
      expect(result.entities.length).toBeGreaterThan(0);
      
      // Check for specific entity types
      const personEntity = result.entities.find(e => e.type === EntityType.PERSON);
      expect(personEntity).toBeDefined();
      expect(personEntity?.name).toBe('John Doe');
      
      const orgEntity = result.entities.find(e => e.type === EntityType.ORGANIZATION);
      expect(orgEntity).toBeDefined();
      expect(orgEntity?.name).toBe('Acme Corporation');
      
      const locationEntity = result.entities.find(e => e.type === EntityType.LOCATION);
      expect(locationEntity).toBeDefined();
      expect(locationEntity?.name).toBe('New York City');
    });
    
    it('should handle empty content', async () => {
      const result = await extractor.extract('', 'text/plain');
      
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(0);
      expect(result.confidence).toBeDefined();
      expect(result.processingTime).toBeDefined();
    });
    
    it('should respect confidence threshold options', async () => {
      const highConfidenceExtractor = new TextEntityExtractor(
        mockLogger,
        { confidenceThreshold: 0.99 }, // Very high threshold that no entity will meet
        mockClaudeService,
        mockFileSystem
      );
      
      const result = await highConfidenceExtractor.extract(
        'John works at Acme in New York.',
        'text/plain'
      );
      
      // All entities should be filtered out due to high confidence threshold
      expect(result.entities).toHaveLength(0);
    });
    
    it('should respect includeTypes options', async () => {
      const personOnlyExtractor = new TextEntityExtractor(
        mockLogger,
        { includeTypes: [EntityType.PERSON] },
        mockClaudeService,
        mockFileSystem
      );
      
      const result = await personOnlyExtractor.extract(
        'John works at Acme in New York.',
        'text/plain'
      );
      
      // Only person entities should be included
      expect(result.entities).toHaveLength(1);
      expect(result.entities[0].type).toBe(EntityType.PERSON);
    });
    
    it('should respect excludeTypes options', async () => {
      const noPersonExtractor = new TextEntityExtractor(
        mockLogger,
        { excludeTypes: [EntityType.PERSON] },
        mockClaudeService,
        mockFileSystem
      );
      
      const result = await noPersonExtractor.extract(
        'John works at Acme in New York.',
        'text/plain'
      );
      
      // Person entities should be excluded
      expect(result.entities.some(e => e.type === EntityType.PERSON)).toBe(false);
      expect(result.entities.length).toBeGreaterThan(0);
    });
  });
  
  describe('extractFromFile', () => {
    it('should extract entities from a text file', async () => {
      const result = await extractor.extractFromFile('/test/sample.txt');
      
      // Verify file was read
      expect(mockFileSystem.calls.some(c => 
        c.method === 'readFile' && c.args[0] === '/test/sample.txt'
      )).toBe(true);
      
      // Verify the result has entities
      expect(result).toBeDefined();
      expect(result.entities).toBeDefined();
      expect(result.entities.length).toBeGreaterThan(0);
      
      // Check for specific entity types
      const personEntity = result.entities.find(e => e.type === EntityType.PERSON);
      expect(personEntity).toBeDefined();
      
      const orgEntity = result.entities.find(e => e.type === EntityType.ORGANIZATION);
      expect(orgEntity).toBeDefined();
      
      const locationEntity = result.entities.find(e => e.type === EntityType.LOCATION);
      expect(locationEntity).toBeDefined();
    });
    
    it('should handle empty files', async () => {
      const result = await extractor.extractFromFile('/test/empty.txt');
      
      expect(result).toBeDefined();
      expect(result.entities).toHaveLength(0);
    });
    
    it('should throw an error for non-existent files', async () => {
      await expect(extractor.extractFromFile('/test/nonexistent.txt'))
        .rejects.toThrow();
    });
  });
  
  describe('fallback handling', () => {
    it('should fall back to rule-based extraction when Claude is not available', async () => {
      // Create extractor without Claude service
      const fallbackExtractor = new TextEntityExtractor(
        mockLogger,
        undefined,
        undefined, // No Claude service
        mockFileSystem
      );
      
      const result = await fallbackExtractor.extract(
        'John is the CEO of Acme Corp based in New York.',
        'text/plain'
      );
      
      // Should still extract some entities using rules
      expect(result.entities.length).toBeGreaterThan(0);
      
      // Make sure Claude was not called
      expect(mockClaudeService.calls.length).toBe(0);
    });
  });
});