import { EntityManager } from '../../../src/core/entity/EntityManager';
import { TextEntityExtractor } from '../../../src/core/entity/extractors/TextEntityExtractor';
import { PdfEntityExtractor } from '../../../src/core/entity/extractors/PdfEntityExtractor';
import { CodeEntityExtractor } from '../../../src/core/entity/extractors/CodeEntityExtractor';
import { ImageEntityExtractor } from '../../../src/core/entity/extractors/ImageEntityExtractor';
import { VideoEntityExtractor } from '../../../src/core/entity/extractors/VideoEntityExtractor';
import { EntityType } from '../../../src/core/entity/types/EntityTypes';
import { MockLogger, MockClaudeService, MockFileSystem, createTestEntity } from '../../mocks';

// Mock database service
const mockDbService = {
  storeEntity: jest.fn().mockResolvedValue(1),
  getEntity: jest.fn().mockResolvedValue(createTestEntity()),
  getEntities: jest.fn().mockResolvedValue([createTestEntity()]),
  deleteEntity: jest.fn().mockResolvedValue(true),
  query: jest.fn().mockResolvedValue([]),
  exec: jest.fn().mockResolvedValue({}),
  connect: jest.fn().mockResolvedValue(true),
  close: jest.fn().mockResolvedValue(true),
};

describe('EntityManager', () => {
  let mockLogger: MockLogger;
  let mockClaudeService: MockClaudeService;
  let mockFileSystem: MockFileSystem;
  let entityManager: EntityManager;
  
  beforeEach(() => {
    // Reset mocks
    mockLogger = new MockLogger();
    mockClaudeService = new MockClaudeService();
    mockFileSystem = new MockFileSystem();
    
    // Mock the database service
    mockDbService.storeEntity.mockClear();
    mockDbService.getEntity.mockClear();
    mockDbService.getEntities.mockClear();
    mockDbService.deleteEntity.mockClear();
    
    // Create the entity manager
    entityManager = new EntityManager(
      mockLogger,
      mockDbService as any,
      mockClaudeService
    );
  });
  
  describe('initialization', () => {
    it('should initialize with default extractors', () => {
      expect(entityManager).toBeDefined();
      // Use private property access for testing
      const extractors = (entityManager as any).extractors;
      expect(extractors.size).toBeGreaterThan(0);
      
      // Verify the default extractors are registered
      expect(extractors.get('text/plain')).toBeInstanceOf(TextEntityExtractor);
      expect(extractors.get('text/html')).toBeInstanceOf(TextEntityExtractor);
      expect(extractors.get('application/pdf')).toBeInstanceOf(PdfEntityExtractor);
      expect(extractors.get('text/javascript')).toBeInstanceOf(CodeEntityExtractor);
      expect(extractors.get('text/typescript')).toBeInstanceOf(CodeEntityExtractor);
      expect(extractors.get('image/jpeg')).toBeInstanceOf(ImageEntityExtractor);
      expect(extractors.get('image/png')).toBeInstanceOf(ImageEntityExtractor);
      expect(extractors.get('video/mp4')).toBeInstanceOf(VideoEntityExtractor);
    });
    
    it('should initialize without database', () => {
      const managerWithoutDb = new EntityManager(
        mockLogger,
        undefined,
        mockClaudeService
      );
      expect(managerWithoutDb).toBeDefined();
    });
  });
  
  describe('registerExtractor', () => {
    it('should register a custom extractor', () => {
      const customExtractor = new TextEntityExtractor(mockLogger);
      entityManager.registerExtractor('custom/type', customExtractor);
      
      // Verify the extractor was registered
      const extractors = (entityManager as any).extractors;
      expect(extractors.get('custom/type')).toBe(customExtractor);
    });
  });
  
  describe('extract', () => {
    it('should extract entities from content using the appropriate extractor', async () => {
      const content = 'John works at Acme in New York.';
      const contentType = 'text/plain';
      
      const result = await entityManager.extract(content, contentType);
      
      // Verify results
      expect(result).toBeDefined();
      expect(result.entities).toBeDefined();
      expect(result.entities.length).toBeGreaterThan(0);
      
      // Verify specific entities were extracted
      const hasPerson = result.entities.some(e => e.type === EntityType.PERSON);
      const hasOrg = result.entities.some(e => e.type === EntityType.ORGANIZATION);
      const hasLocation = result.entities.some(e => e.type === EntityType.LOCATION);
      
      expect(hasPerson).toBe(true);
      expect(hasOrg).toBe(true);
      expect(hasLocation).toBe(true);
    });
    
    it('should throw an error for unsupported content types', async () => {
      await expect(entityManager.extract('content', 'unsupported/type'))
        .rejects.toThrow();
    });
  });
  
  describe('extractFromFile', () => {
    beforeEach(() => {
      // Set up mock files
      mockFileSystem.addMockFile('/test/document.txt', 'Sample text with John and Acme.');
      mockFileSystem.addMockFile('/test/code.js', 'function test() { console.log("Hello"); }');
      
      // Make the entity manager use our mock file system
      (entityManager as any).fs = mockFileSystem;
    });
    
    it('should extract entities from a file using the correct extractor based on file type', async () => {
      // Text file
      const textResult = await entityManager.extractFromFile('/test/document.txt');
      expect(textResult).toBeDefined();
      expect(textResult.entities.length).toBeGreaterThan(0);
      
      // JS file (should use CodeEntityExtractor)
      const jsResult = await entityManager.extractFromFile('/test/code.js');
      expect(jsResult).toBeDefined();
    });
    
    it('should handle files with unknown content types', async () => {
      mockFileSystem.addMockFile('/test/unknown.xyz', 'Some content');
      
      // Should fall back to text extraction
      const result = await entityManager.extractFromFile('/test/unknown.xyz');
      expect(result).toBeDefined();
    });
  });
  
  describe('database operations', () => {
    const testEntity = createTestEntity('Test Entity', EntityType.ORGANIZATION);
    
    beforeEach(() => {
      // Mock database responses
      mockDbService.storeEntity.mockResolvedValue(42);
      mockDbService.getEntity.mockResolvedValue(testEntity);
      mockDbService.getEntities.mockResolvedValue([testEntity]);
    });
    
    it('should store entities in the database', async () => {
      const id = await entityManager.storeEntity(testEntity);
      
      expect(id).toBe(42);
      expect(mockDbService.storeEntity).toHaveBeenCalledWith(testEntity);
    });
    
    it('should retrieve entities from the database', async () => {
      const entity = await entityManager.getEntity(42);
      
      expect(entity).toEqual(testEntity);
      expect(mockDbService.getEntity).toHaveBeenCalledWith(42);
    });
    
    it('should retrieve entities by type from the database', async () => {
      const entities = await entityManager.getEntitiesByType(EntityType.ORGANIZATION);
      
      expect(entities).toEqual([testEntity]);
      expect(mockDbService.getEntities).toHaveBeenCalled();
    });
    
    it('should search entities in the database', async () => {
      const entities = await entityManager.searchEntities('Test');
      
      expect(entities).toEqual([testEntity]);
      expect(mockDbService.query).toHaveBeenCalled();
    });
    
    it('should gracefully handle database operations when no database is provided', async () => {
      const managerWithoutDb = new EntityManager(
        mockLogger,
        undefined,
        mockClaudeService
      );
      
      // These should resolve to undefined/empty array without throwing errors
      await expect(managerWithoutDb.storeEntity(testEntity)).resolves.toBeUndefined();
      await expect(managerWithoutDb.getEntity(42)).resolves.toBeUndefined();
      await expect(managerWithoutDb.getEntitiesByType(EntityType.ORGANIZATION)).resolves.toEqual([]);
      await expect(managerWithoutDb.searchEntities('Test')).resolves.toEqual([]);
    });
  });
});