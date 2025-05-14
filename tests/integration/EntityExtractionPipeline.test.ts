import { EntityManager } from '../../src/core/entity/EntityManager';
import { TextEntityExtractor } from '../../src/core/entity/extractors/TextEntityExtractor';
import { ContentProcessor } from '../../src/core/content/ContentProcessor';
import { DatabaseService } from '../../src/core/services/DatabaseService';
import { ClaudeService } from '../../src/core/services/ClaudeService';
import { FileSystem } from '../../src/core/utils/FileSystem';
import { Logger } from '../../src/core/logging/Logger';
import { EntityType } from '../../src/core/entity/types/EntityTypes';
import { ContentTypeDetector } from '../../src/core/content/ContentTypeDetector';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

describe('Entity Extraction Pipeline Integration Tests', () => {
  let logger: Logger;
  let fileSystem: FileSystem;
  let dbService: DatabaseService;
  let claudeService: ClaudeService;
  let entityManager: EntityManager;
  let contentProcessor: ContentProcessor;
  let contentTypeDetector: ContentTypeDetector;
  let tempDir: string;
  let dbPath: string;
  
  beforeAll(async () => {
    // Create a temporary directory for testing
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ingestor-test-integration-'));
    dbPath = path.join(tempDir, 'integration-test.db');
    
    // Set up test files
    const textFilePath = path.join(tempDir, 'sample.txt');
    fs.writeFileSync(textFilePath, 
      'This is a sample document about John Doe who works at Acme Corporation in New York. ' +
      'He is the CEO and has been with the company since 2015. ' +
      'The company produces widgets and has an annual revenue of $10 million.'
    );
    
    const htmlFilePath = path.join(tempDir, 'sample.html');
    fs.writeFileSync(htmlFilePath,
      '<html><head><title>About Jane Smith</title></head><body>' +
      '<h1>Jane Smith</h1><p>Jane is the CTO of TechCorp based in San Francisco.' +
      'She previously worked at Google and has a degree from Stanford University.</p>' +
      '<p>Contact her at jane@example.com</p></body></html>'
    );
    
    const codeFilePath = path.join(tempDir, 'sample.js');
    fs.writeFileSync(codeFilePath,
      '/**\n' +
      ' * Product management module for ACME Corporation\n' +
      ' * @author John Doe\n' +
      ' */\n' +
      'class Product {\n' +
      '  constructor(name, price, category) {\n' +
      '    this.name = name;\n' +
      '    this.price = price;\n' +
      '    this.category = category;\n' +
      '  }\n' +
      '}\n\n' +
      'const COMPANY_NAME = "ACME Corp";\n' +
      'const LOCATION = "New York";\n'
    );
  });
  
  afterAll(() => {
    // Clean up the temporary directory
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (error) {
      console.error(`Error cleaning up temporary directory: ${error}`);
    }
  });
  
  beforeEach(async () => {
    // Initialize with real components (but with test configuration)
    logger = new Logger('integration-test', { console: true });
    fileSystem = new FileSystem(logger);
    dbService = new DatabaseService(logger, dbPath);
    
    // Initialize the database
    await dbService.initialize();
    
    // Create the entity extraction pipeline
    claudeService = new ClaudeService(logger);
    
    // Mock the Claude API call to avoid actual API requests
    jest.spyOn(claudeService, 'extractEntities').mockImplementation(async (content) => {
      // Return mock entities based on content
      const entities = [];
      
      if (content.includes('John Doe')) {
        entities.push({
          name: 'John Doe',
          type: EntityType.PERSON,
          mentions: [
            {
              text: 'John Doe',
              offset: content.indexOf('John Doe'),
              length: 8,
              confidence: 0.95
            }
          ]
        });
      }
      
      if (content.includes('Jane Smith')) {
        entities.push({
          name: 'Jane Smith',
          type: EntityType.PERSON,
          mentions: [
            {
              text: 'Jane Smith',
              offset: content.indexOf('Jane Smith'),
              length: 10,
              confidence: 0.96
            }
          ]
        });
      }
      
      if (content.includes('Acme')) {
        entities.push({
          name: 'Acme Corporation',
          type: EntityType.ORGANIZATION,
          mentions: [
            {
              text: 'Acme',
              offset: content.indexOf('Acme'),
              length: 4,
              confidence: 0.93
            }
          ]
        });
      }
      
      if (content.includes('TechCorp')) {
        entities.push({
          name: 'TechCorp',
          type: EntityType.ORGANIZATION,
          mentions: [
            {
              text: 'TechCorp',
              offset: content.indexOf('TechCorp'),
              length: 8,
              confidence: 0.92
            }
          ]
        });
      }
      
      if (content.includes('New York')) {
        entities.push({
          name: 'New York',
          type: EntityType.LOCATION,
          mentions: [
            {
              text: 'New York',
              offset: content.indexOf('New York'),
              length: 8,
              confidence: 0.97
            }
          ]
        });
      }
      
      if (content.includes('San Francisco')) {
        entities.push({
          name: 'San Francisco',
          type: EntityType.LOCATION,
          mentions: [
            {
              text: 'San Francisco',
              offset: content.indexOf('San Francisco'),
              length: 13,
              confidence: 0.96
            }
          ]
        });
      }
      
      return {
        entities,
        processingTime: 42,
        confidence: 0.94,
        contentLength: content.length
      };
    });
    
    entityManager = new EntityManager(logger, dbService, claudeService);
    contentTypeDetector = new ContentTypeDetector(logger, fileSystem);
    
    contentProcessor = new ContentProcessor(
      logger,
      fileSystem,
      claudeService,
      entityManager,
      contentTypeDetector
    );
  });
  
  afterEach(async () => {
    // Clean up database after each test
    await dbService.close();
    
    // Reset mocked functions
    jest.restoreAllMocks();
    
    // Remove the test database file if it exists
    if (fs.existsSync(dbPath)) {
      fs.unlinkSync(dbPath);
    }
  });
  
  describe('End-to-end entity extraction', () => {
    it('should process text content and extract entities', async () => {
      // Process raw text content
      const content = 'John Doe is the CEO of Acme Corporation based in New York.';
      const result = await contentProcessor.processContent(content, 'text/plain');
      
      // Verify the extraction was successful
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
      expect(locationEntity?.name).toBe('New York');
      
      // Verify entities were stored in the database
      const entities = await dbService.getEntities();
      expect(entities.length).toBeGreaterThan(0);
      
      // Verify we can query the database for entities
      const persons = await dbService.getEntitiesByType(EntityType.PERSON);
      expect(persons.length).toBeGreaterThan(0);
      expect(persons.some(p => p.name === 'John Doe')).toBe(true);
    });
    
    it('should process files with appropriate content type detection', async () => {
      // Process a text file
      const textFilePath = path.join(tempDir, 'sample.txt');
      const textResult = await contentProcessor.processFile(textFilePath);
      
      // Verify text file extraction
      expect(textResult).toBeDefined();
      expect(textResult.entities).toBeDefined();
      expect(textResult.entities.some(e => e.name === 'John Doe')).toBe(true);
      expect(textResult.entities.some(e => e.name === 'Acme Corporation')).toBe(true);
      
      // Process an HTML file
      const htmlFilePath = path.join(tempDir, 'sample.html');
      const htmlResult = await contentProcessor.processFile(htmlFilePath);
      
      // Verify HTML file extraction
      expect(htmlResult).toBeDefined();
      expect(htmlResult.entities).toBeDefined();
      expect(htmlResult.entities.some(e => e.name === 'Jane Smith')).toBe(true);
      expect(htmlResult.entities.some(e => e.name === 'TechCorp')).toBe(true);
      
      // Process a code file
      const codeFilePath = path.join(tempDir, 'sample.js');
      const codeResult = await contentProcessor.processFile(codeFilePath);
      
      // Verify code file extraction
      expect(codeResult).toBeDefined();
      expect(codeResult.entities).toBeDefined();
      expect(codeResult.entities.some(e => e.name === 'John Doe')).toBe(true);
      expect(codeResult.entities.some(e => e.name === 'Acme Corporation')).toBe(true);
      
      // Verify all entities are in the database
      const persons = await dbService.getEntitiesByType(EntityType.PERSON);
      expect(persons.length).toBeGreaterThan(1); // Should have John and Jane
      expect(persons.some(p => p.name === 'John Doe')).toBe(true);
      expect(persons.some(p => p.name === 'Jane Smith')).toBe(true);
      
      const orgs = await dbService.getEntitiesByType(EntityType.ORGANIZATION);
      expect(orgs.length).toBeGreaterThan(1); // Should have Acme and TechCorp
      expect(orgs.some(o => o.name === 'Acme Corporation')).toBe(true);
      expect(orgs.some(o => o.name === 'TechCorp')).toBe(true);
    });
    
    it('should handle batched entity processing across multiple files', async () => {
      // Process multiple files in batch
      const files = [
        path.join(tempDir, 'sample.txt'),
        path.join(tempDir, 'sample.html'),
        path.join(tempDir, 'sample.js')
      ];
      
      // Process each file
      const results = await Promise.all(files.map(file => contentProcessor.processFile(file)));
      
      // Verify all processing succeeded
      expect(results.length).toBe(files.length);
      expect(results.every(r => r.entities && r.entities.length > 0)).toBe(true);
      
      // Verify all entities are in the database
      const allEntities = await dbService.getEntities();
      
      // Count unique entity types
      const personCount = allEntities.filter(e => e.type === EntityType.PERSON).length;
      const orgCount = allEntities.filter(e => e.type === EntityType.ORGANIZATION).length;
      const locationCount = allEntities.filter(e => e.type === EntityType.LOCATION).length;
      
      // Should have at least 2 persons, 2 orgs, and 2 locations
      expect(personCount).toBeGreaterThanOrEqual(2);
      expect(orgCount).toBeGreaterThanOrEqual(2);
      expect(locationCount).toBeGreaterThanOrEqual(2);
      
      // Verify search functionality on the stored entities
      const searchResults = await dbService.searchEntities('New York');
      expect(searchResults.length).toBeGreaterThan(0);
      expect(searchResults.some(e => e.name === 'New York')).toBe(true);
    });
  });
});