/**
 * Unit tests for the TextEntityExtractor
 */

import { TextEntityExtractor } from '../../../../core/entity/extractors/TextEntityExtractor';
import { Entity, EntityExtractionOptions, EntityType } from '../../../../core/entity/types';
import { ClaudeService } from '../../../../core/services/ClaudeService';
import { Logger } from '../../../../core/logging';
import { FileSystem } from '../../../../core/utils/FileSystem';

// Mock dependencies
jest.mock('../../../../core/services/ClaudeService');
jest.mock('../../../../core/logging/Logger');
jest.mock('../../../../core/utils/FileSystem');

describe('TextEntityExtractor', () => {
  let extractor: TextEntityExtractor;
  let mockLogger: jest.Mocked<Logger>;
  let mockClaudeService: jest.Mocked<ClaudeService>;
  let mockFileSystem: jest.Mocked<FileSystem>;

  beforeEach(() => {
    // Set up mocks
    mockLogger = {
      debug: jest.fn(),
      info: jest.fn(),
      warning: jest.fn(),
      error: jest.fn()
    } as unknown as jest.Mocked<Logger>;

    mockClaudeService = {
      analyze: jest.fn()
    } as unknown as jest.Mocked<ClaudeService>;

    mockFileSystem = {
      isFile: jest.fn(),
      readFile: jest.fn(),
      createTempFile: jest.fn(),
      removeFile: jest.fn(),
      grep: jest.fn(),
      grepContext: jest.fn(),
      grepLineNumber: jest.fn()
    } as unknown as jest.Mocked<FileSystem>;

    // Initialize extractor with mocks
    extractor = new TextEntityExtractor(
      mockLogger,
      {},
      mockClaudeService,
      mockFileSystem
    );
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('constructor', () => {
    it('should initialize with default options', () => {
      const basicExtractor = new TextEntityExtractor(mockLogger);
      expect(basicExtractor).toBeDefined();
    });

    it('should initialize with custom options', () => {
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.8,
        maxEntities: 20
      };
      
      const customExtractor = new TextEntityExtractor(mockLogger, options);
      expect(customExtractor).toBeDefined();
    });
  });

  describe('extract', () => {
    it('should handle empty content', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      
      const result = await extractor.extract('', 'text/plain');
      
      expect(result.success).toBe(false);
      expect(result.error).toBe('Empty text content');
      expect(result.entities).toHaveLength(0);
    });

    it('should read from file if content is a file path', async () => {
      const filePath = '/path/to/test.txt';
      const fileContent = 'This is test content with John Doe and Acme Corp.';
      
      mockFileSystem.isFile.mockResolvedValue(true);
      mockFileSystem.readFile.mockResolvedValue(fileContent);
      
      // Mock Claude service to return entities
      mockClaudeService.analyze.mockResolvedValue({
        entities: [
          {
            name: 'John Doe',
            type: EntityType.PERSON,
            mentions: [
              { context: 'test content with John Doe and', position: 1, relevance: 0.9 }
            ]
          },
          {
            name: 'Acme Corp',
            type: EntityType.ORGANIZATION,
            mentions: [
              { context: 'John Doe and Acme Corp.', position: 1, relevance: 0.8 }
            ]
          }
        ]
      });
      
      const result = await extractor.extract(filePath, 'text/plain');
      
      expect(mockFileSystem.isFile).toHaveBeenCalledWith(filePath);
      expect(mockFileSystem.readFile).toHaveBeenCalledWith(filePath);
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(2);
    });

    it('should use Claude for entity extraction when available', async () => {
      const content = 'This is test content with John Doe and Acme Corp.';
      const expectedEntities = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          mentions: [
            { context: 'test content with John Doe and', position: 1, relevance: 0.9 }
          ]
        },
        {
          name: 'Acme Corp',
          type: EntityType.ORGANIZATION,
          mentions: [
            { context: 'John Doe and Acme Corp.', position: 1, relevance: 0.8 }
          ]
        }
      ];
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({ entities: expectedEntities });
      
      const result = await extractor.extract(content, 'text/plain');
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        content,
        expect.any(String),
        expect.any(Object)
      );
      expect(result.success).toBe(true);
      expect(result.entities).toEqual(expectedEntities);
    });

    it('should fall back to rule-based extraction when Claude fails', async () => {
      const content = 'This is test content with John Doe and Acme Corp.';
      const tempFilePath = '/tmp/temp_file.txt';
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockRejectedValue(new Error('Claude API error'));
      
      // Mock rule-based extraction
      mockFileSystem.createTempFile.mockResolvedValue(tempFilePath);
      
      // Mock person extraction
      mockFileSystem.grep.mockResolvedValueOnce(['John Doe']); // Person matches
      mockFileSystem.grep.mockResolvedValueOnce([]); // Titled person matches
      mockFileSystem.grepContext.mockResolvedValue('test content with John Doe and Acme Corp');
      mockFileSystem.grepLineNumber.mockResolvedValue(1);
      
      // Mock organization extraction
      mockFileSystem.grep.mockResolvedValueOnce(['Acme Corp']); // Org matches
      mockFileSystem.grep.mockResolvedValueOnce([]); // Capitalized org matches
      
      // Mock location extraction
      mockFileSystem.grep.mockResolvedValueOnce([]); // Location matches
      mockFileSystem.grep.mockResolvedValueOnce([]); // Major location matches
      
      // Mock date extraction
      mockFileSystem.grep.mockResolvedValueOnce([]); // Date matches
      
      const result = await extractor.extract(content, 'text/plain');
      
      expect(mockLogger.warning).toHaveBeenCalledWith(expect.stringContaining('Claude extraction failed'));
      expect(mockFileSystem.createTempFile).toHaveBeenCalledWith(content);
      expect(mockFileSystem.removeFile).toHaveBeenCalledWith(tempFilePath);
      expect(result.success).toBe(true);
      expect(result.entities.length).toBeGreaterThan(0);
    });

    it('should filter entities based on options', async () => {
      const content = 'This is test content with John Doe and Acme Corp.';
      const options: EntityExtractionOptions = {
        entityTypes: [EntityType.PERSON],
        confidenceThreshold: 0.8
      };
      
      const claudeEntities = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          mentions: [
            { context: 'test content with John Doe and', position: 1, relevance: 0.9 }
          ]
        },
        {
          name: 'Acme Corp',
          type: EntityType.ORGANIZATION,
          mentions: [
            { context: 'John Doe and Acme Corp.', position: 1, relevance: 0.7 }
          ]
        }
      ];
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({ entities: claudeEntities });
      
      const result = await extractor.extract(content, 'text/plain', options);
      
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(1);
      expect(result.entities[0].name).toBe('John Doe');
    });

    it('should include stats in the result', async () => {
      const content = 'This is test content.';
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({ entities: [] });
      
      const result = await extractor.extract(content, 'text/plain');
      
      expect(result.success).toBe(true);
      expect(result.stats).toBeDefined();
      expect(result.stats?.processingTimeMs).toBeGreaterThanOrEqual(0);
      expect(result.stats?.entityCount).toBe(0);
    });
  });

  describe('extractWithRules', () => {
    it('should handle errors during rule-based extraction gracefully', async () => {
      const content = 'This is test content with John Doe.';
      const tempFilePath = '/tmp/temp_file.txt';
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockRejectedValue(new Error('Claude API error'));
      
      // Mock rule-based extraction with error
      mockFileSystem.createTempFile.mockResolvedValue(tempFilePath);
      mockFileSystem.grep.mockRejectedValue(new Error('Grep error'));
      
      const result = await extractor.extract(content, 'text/plain');
      
      expect(mockLogger.warning).toHaveBeenCalledWith(expect.stringContaining('Error extracting'));
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(0);
    });
  });

  describe('extractWithClaude', () => {
    it('should handle invalid Claude response format', async () => {
      const content = 'This is test content.';
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({ something: 'not entities' });
      
      const result = await extractor.extract(content, 'text/plain');
      
      expect(mockLogger.warning).toHaveBeenCalledWith(expect.stringContaining('Claude response did not contain valid entities array'));
      expect(result.entities).toHaveLength(0);
    });

    it('should use custom prompt template for specific entity types', async () => {
      const content = 'This is test content.';
      const options: EntityExtractionOptions = {
        entityTypes: [EntityType.PERSON, EntityType.ORGANIZATION]
      };
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({ entities: [] });
      
      await extractor.extract(content, 'text/plain', options);
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        content,
        'text_entities_custom',
        expect.objectContaining({
          entityTypes: 'person,organization'
        })
      );
    });
  });
});