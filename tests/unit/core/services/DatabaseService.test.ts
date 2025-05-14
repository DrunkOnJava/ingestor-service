import { DatabaseService } from '../../../../src/core/services/DatabaseService';
import { Entity, EntityType } from '../../../../src/core/entity/types/EntityTypes';
import { MockLogger, createTestEntity } from '../../../mocks';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

describe('DatabaseService', () => {
  let mockLogger: MockLogger;
  let dbService: DatabaseService;
  let tempDir: string;
  let dbPath: string;
  
  beforeAll(() => {
    // Create a temporary directory for testing
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ingestor-test-db-'));
    dbPath = path.join(tempDir, 'test.db');
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
    mockLogger = new MockLogger();
    dbService = new DatabaseService(mockLogger, dbPath);
    
    // Initialize the database
    await dbService.initialize();
  });
  
  afterEach(async () => {
    // Close the database connection
    await dbService.close();
    
    // Remove the test database file if it exists
    if (fs.existsSync(dbPath)) {
      fs.unlinkSync(dbPath);
    }
  });
  
  describe('connection', () => {
    it('should connect to the database successfully', async () => {
      // Check if connection was established
      expect((dbService as any).connected).toBe(true);
      
      // Should have logged successful connection
      expect(mockLogger.logs.some(log => 
        log.level === 'info' && log.message.includes('connected')
      )).toBe(true);
    });
    
    it('should initialize the database schema', async () => {
      // Ensure tables were created
      const tables = await dbService.query('SELECT name FROM sqlite_master WHERE type="table"');
      
      // Should have the entity tables
      expect(tables.some((table: any) => table.name === 'entities')).toBe(true);
      expect(tables.some((table: any) => table.name === 'entity_mentions')).toBe(true);
      expect(tables.some((table: any) => table.name === 'entity_relations')).toBe(true);
      
      // Should have logged schema initialization
      expect(mockLogger.logs.some(log => 
        log.level === 'info' && log.message.includes('schema')
      )).toBe(true);
    });
    
    it('should handle connection errors gracefully', async () => {
      // Create a service with an invalid path
      const invalidDbService = new DatabaseService(mockLogger, '/invalid/path/to/db.sqlite');
      
      // Connect should throw an error
      await expect(invalidDbService.connect('/invalid/path/to/db.sqlite'))
        .rejects.toThrow();
      
      // Should have logged an error
      expect(mockLogger.logs.some(log => 
        log.level === 'error' && log.message.includes('connect')
      )).toBe(true);
    });
  });
  
  describe('entity operations', () => {
    const testEntity: Entity = {
      name: 'Acme Corporation',
      type: EntityType.ORGANIZATION,
      description: 'A fictional company',
      mentions: [
        {
          text: 'Acme',
          offset: 10,
          length: 4,
          confidence: 0.95
        },
        {
          text: 'Acme Corporation',
          offset: 100,
          length: 16,
          confidence: 0.98
        }
      ]
    };
    
    it('should store and retrieve entities', async () => {
      // Store the test entity
      const entityId = await dbService.storeEntity(testEntity);
      
      // Should have returned an ID
      expect(entityId).toBeDefined();
      expect(typeof entityId).toBe('number');
      
      // Retrieve the entity
      const retrievedEntity = await dbService.getEntity(entityId);
      
      // Verify the entity was retrieved correctly
      expect(retrievedEntity).toBeDefined();
      expect(retrievedEntity?.name).toBe(testEntity.name);
      expect(retrievedEntity?.type).toBe(testEntity.type);
      expect(retrievedEntity?.description).toBe(testEntity.description);
      
      // Verify mentions were stored
      expect(retrievedEntity?.mentions).toBeDefined();
      expect(retrievedEntity?.mentions.length).toBe(testEntity.mentions.length);
    });
    
    it('should update existing entities', async () => {
      // Store the test entity
      const entityId = await dbService.storeEntity(testEntity);
      
      // Update the entity
      const updatedEntity: Entity = {
        ...testEntity,
        name: 'Updated Acme Corp',
        description: 'An updated fictional company'
      };
      
      // Store with the same ID
      await dbService.storeEntity(updatedEntity, entityId);
      
      // Retrieve the updated entity
      const retrievedEntity = await dbService.getEntity(entityId);
      
      // Verify the entity was updated
      expect(retrievedEntity?.name).toBe(updatedEntity.name);
      expect(retrievedEntity?.description).toBe(updatedEntity.description);
    });
    
    it('should search entities by name', async () => {
      // Store multiple entities
      await dbService.storeEntity(testEntity);
      await dbService.storeEntity({
        name: 'John Doe',
        type: EntityType.PERSON,
        mentions: [
          {
            text: 'John',
            offset: 0,
            length: 4,
            confidence: 0.9
          }
        ]
      });
      
      // Search for entities
      const results = await dbService.searchEntities('Acme');
      
      // Should find our test entity
      expect(results.length).toBeGreaterThan(0);
      expect(results.some(e => e.name === testEntity.name)).toBe(true);
      
      // Should not find other entities
      expect(results.some(e => e.name === 'John Doe')).toBe(false);
    });
    
    it('should retrieve entities by type', async () => {
      // Store multiple entities of different types
      await dbService.storeEntity(testEntity); // ORGANIZATION
      await dbService.storeEntity({
        name: 'John Doe',
        type: EntityType.PERSON,
        mentions: []
      });
      await dbService.storeEntity({
        name: 'New York',
        type: EntityType.LOCATION,
        mentions: []
      });
      
      // Get entities by type
      const orgs = await dbService.getEntitiesByType(EntityType.ORGANIZATION);
      const people = await dbService.getEntitiesByType(EntityType.PERSON);
      const locations = await dbService.getEntitiesByType(EntityType.LOCATION);
      
      // Verify correct entities were returned
      expect(orgs.length).toBeGreaterThan(0);
      expect(orgs.some(e => e.name === testEntity.name)).toBe(true);
      
      expect(people.length).toBeGreaterThan(0);
      expect(people.some(e => e.name === 'John Doe')).toBe(true);
      
      expect(locations.length).toBeGreaterThan(0);
      expect(locations.some(e => e.name === 'New York')).toBe(true);
    });
    
    it('should delete entities', async () => {
      // Store an entity
      const entityId = await dbService.storeEntity(testEntity);
      
      // Delete the entity
      await dbService.deleteEntity(entityId);
      
      // Try to retrieve the deleted entity
      const retrievedEntity = await dbService.getEntity(entityId);
      
      // Should be undefined
      expect(retrievedEntity).toBeUndefined();
    });
  });
  
  describe('entity relations', () => {
    let entityId1: number;
    let entityId2: number;
    
    beforeEach(async () => {
      // Create two test entities
      entityId1 = await dbService.storeEntity(createTestEntity(
        'Acme Corporation',
        EntityType.ORGANIZATION
      ));
      
      entityId2 = await dbService.storeEntity(createTestEntity(
        'John Doe',
        EntityType.PERSON
      ));
    });
    
    it('should create and retrieve relations between entities', async () => {
      // Create a relation
      await dbService.createRelation(entityId1, entityId2, 'employs');
      
      // Get related entities
      const relatedEntities = await dbService.getRelatedEntities(entityId1, 'employs');
      
      // Should return the related entity
      expect(relatedEntities.length).toBe(1);
      expect(relatedEntities[0].name).toBe('John Doe');
      
      // Get inverse relations
      const inverseRelations = await dbService.getRelatedEntities(entityId2, 'employed_by');
      
      // Should return the original entity
      expect(inverseRelations.length).toBe(1);
      expect(inverseRelations[0].name).toBe('Acme Corporation');
    });
    
    it('should delete relations', async () => {
      // Create a relation
      await dbService.createRelation(entityId1, entityId2, 'employs');
      
      // Delete the relation
      await dbService.deleteRelation(entityId1, entityId2, 'employs');
      
      // Get related entities
      const relatedEntities = await dbService.getRelatedEntities(entityId1, 'employs');
      
      // Should be empty
      expect(relatedEntities.length).toBe(0);
    });
  });
  
  describe('transaction handling', () => {
    it('should commit successful transactions', async () => {
      // Start a transaction
      await dbService.beginTransaction();
      
      // Store an entity in the transaction
      const entityId = await dbService.storeEntity(createTestEntity());
      
      // Commit the transaction
      await dbService.commitTransaction();
      
      // Entity should exist
      const entity = await dbService.getEntity(entityId);
      expect(entity).toBeDefined();
    });
    
    it('should rollback failed transactions', async () => {
      // Store an initial entity outside the transaction
      const initialId = await dbService.storeEntity(createTestEntity('Initial Entity', EntityType.ORGANIZATION));
      
      // Start a transaction
      await dbService.beginTransaction();
      
      // Store an entity in the transaction
      const entityId = await dbService.storeEntity(createTestEntity('Transaction Entity', EntityType.ORGANIZATION));
      
      // Rollback the transaction
      await dbService.rollbackTransaction();
      
      // Entity from transaction should not exist
      const entity = await dbService.getEntity(entityId);
      expect(entity).toBeUndefined();
      
      // Initial entity should still exist
      const initialEntity = await dbService.getEntity(initialId);
      expect(initialEntity).toBeDefined();
      expect(initialEntity?.name).toBe('Initial Entity');
    });
  });
});