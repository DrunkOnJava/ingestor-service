/**
 * Unit tests for the EntityExtractor base class
 */

import { EntityExtractor } from '../../../core/entity/EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityType } from '../../../core/entity/types';
import { Logger } from '../../../core/logging';

// Mock implementation of the abstract EntityExtractor
class MockEntityExtractor extends EntityExtractor {
  public async extract(
    content: string,
    contentType: string,
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    // Return empty result for testing
    return {
      entities: [],
      success: true
    };
  }

  // Expose protected methods for testing
  public testNormalizeEntityName(name: string, type: EntityType): string {
    return this.normalizeEntityName(name, type);
  }

  public testIsValidEntityType(type: string): boolean {
    return this.isValidEntityType(type);
  }

  public testMergeEntities(entityLists: Entity[][]): Entity[] {
    return this.mergeEntities(entityLists);
  }

  public testFilterEntities(
    entities: Entity[],
    options?: EntityExtractionOptions
  ): Entity[] {
    return this.filterEntities(entities, options);
  }
}

// Mock logger
const mockLogger = {
  debug: jest.fn(),
  info: jest.fn(),
  warning: jest.fn(),
  error: jest.fn()
} as unknown as Logger;

describe('EntityExtractor', () => {
  let extractor: MockEntityExtractor;

  beforeEach(() => {
    jest.clearAllMocks();
    extractor = new MockEntityExtractor(mockLogger);
  });

  describe('constructor', () => {
    it('should initialize with default options', () => {
      expect(extractor).toBeDefined();
    });

    it('should initialize with custom options', () => {
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.75,
        maxEntities: 100,
        entityTypes: [EntityType.PERSON, EntityType.ORGANIZATION]
      };
      
      const customExtractor = new MockEntityExtractor(mockLogger, options);
      
      // Test the custom filter with these options
      const entities: Entity[] = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          mentions: [{ context: 'John Doe is a person', position: 1, relevance: 0.8 }]
        },
        {
          name: 'ABC Corp',
          type: EntityType.ORGANIZATION,
          mentions: [{ context: 'ABC Corp is a company', position: 2, relevance: 0.7 }]
        },
        {
          name: 'New York',
          type: EntityType.LOCATION,
          mentions: [{ context: 'New York is a city', position: 3, relevance: 0.9 }]
        }
      ];
      
      const filtered = customExtractor.testFilterEntities(entities);
      
      expect(filtered).toHaveLength(2);
      expect(filtered.map(e => e.type)).toEqual([EntityType.PERSON, EntityType.ORGANIZATION]);
    });
  });

  describe('normalizeEntityName', () => {
    it('should normalize person names correctly', () => {
      const result = extractor.testNormalizeEntityName('john doe', EntityType.PERSON);
      expect(result).toBe('John Doe');
      
      const result2 = extractor.testNormalizeEntityName('JANE SMITH', EntityType.PERSON);
      expect(result2).toBe('Jane Smith');
      
      const result3 = extractor.testNormalizeEntityName('   Robert  Jones   ', EntityType.PERSON);
      expect(result3).toBe('Robert Jones');
    });

    it('should normalize organization names correctly', () => {
      const result = extractor.testNormalizeEntityName('acme corporation', EntityType.ORGANIZATION);
      expect(result).toBe('acme corporation');
      
      const result2 = extractor.testNormalizeEntityName('  ABC  Inc.  ', EntityType.ORGANIZATION);
      expect(result2).toBe('ABC Inc.');
    });

    it('should normalize location names correctly', () => {
      const result = extractor.testNormalizeEntityName('new york city', EntityType.LOCATION);
      expect(result).toBe('New York City');
      
      const result2 = extractor.testNormalizeEntityName('LONDON', EntityType.LOCATION);
      expect(result2).toBe('London');
    });

    it('should normalize date formats correctly', () => {
      const result = extractor.testNormalizeEntityName('01/02/2023', EntityType.DATE);
      expect(result).toBe('2023-01-02');
      
      const result2 = extractor.testNormalizeEntityName('12/25/22', EntityType.DATE);
      expect(result2).toBe('22-12-25');
    });

    it('should use basic normalization for other entity types', () => {
      const result = extractor.testNormalizeEntityName('  My Product  ', EntityType.PRODUCT);
      expect(result).toBe('My Product');
      
      const result2 = extractor.testNormalizeEntityName('"Some Technology"', EntityType.TECHNOLOGY);
      expect(result2).toBe('Some Technology');
    });
  });

  describe('isValidEntityType', () => {
    it('should return true for valid entity types', () => {
      expect(extractor.testIsValidEntityType(EntityType.PERSON)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.ORGANIZATION)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.LOCATION)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.DATE)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.PRODUCT)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.TECHNOLOGY)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.EVENT)).toBe(true);
      expect(extractor.testIsValidEntityType(EntityType.OTHER)).toBe(true);
    });

    it('should return false for invalid entity types', () => {
      expect(extractor.testIsValidEntityType('invalid_type')).toBe(false);
      expect(extractor.testIsValidEntityType('')).toBe(false);
    });
  });

  describe('mergeEntities', () => {
    it('should merge entities from multiple lists', () => {
      const entityList1: Entity[] = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          mentions: [{ context: 'John Doe is here', position: 1, relevance: 0.8 }]
        }
      ];

      const entityList2: Entity[] = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          description: 'A person',
          mentions: [{ context: 'John Doe works here', position: 5, relevance: 0.9 }]
        },
        {
          name: 'Acme Corp',
          type: EntityType.ORGANIZATION,
          mentions: [{ context: 'Works at Acme Corp', position: 10, relevance: 0.7 }]
        }
      ];

      const merged = extractor.testMergeEntities([entityList1, entityList2]);
      
      expect(merged).toHaveLength(2);
      
      const johnDoe = merged.find(e => e.name === 'John Doe');
      expect(johnDoe).toBeDefined();
      expect(johnDoe?.mentions).toHaveLength(2);
      expect(johnDoe?.description).toBe('A person');
      
      const acmeCorp = merged.find(e => e.name === 'Acme Corp');
      expect(acmeCorp).toBeDefined();
    });

    it('should handle empty entity lists', () => {
      const merged = extractor.testMergeEntities([[], []]);
      expect(merged).toHaveLength(0);
    });

    it('should use longer description when merging', () => {
      const entityList1: Entity[] = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          description: 'A short desc',
          mentions: [{ context: 'John Doe is here', position: 1, relevance: 0.8 }]
        }
      ];

      const entityList2: Entity[] = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          description: 'A much longer description that should be preferred',
          mentions: [{ context: 'John Doe works here', position: 5, relevance: 0.9 }]
        }
      ];

      const merged = extractor.testMergeEntities([entityList1, entityList2]);
      
      expect(merged).toHaveLength(1);
      expect(merged[0].description).toBe('A much longer description that should be preferred');
    });
  });

  describe('filterEntities', () => {
    let entities: Entity[];

    beforeEach(() => {
      entities = [
        {
          name: 'John Doe',
          type: EntityType.PERSON,
          mentions: [{ context: 'John Doe context', position: 1, relevance: 0.8 }]
        },
        {
          name: 'Jane Smith',
          type: EntityType.PERSON,
          mentions: [{ context: 'Jane Smith context', position: 2, relevance: 0.4 }]
        },
        {
          name: 'Acme Corp',
          type: EntityType.ORGANIZATION,
          mentions: [{ context: 'Acme Corp context', position: 3, relevance: 0.7 }]
        },
        {
          name: 'New York',
          type: EntityType.LOCATION,
          mentions: [{ context: 'New York context', position: 4, relevance: 0.6 }]
        },
        {
          name: '2023-01-01',
          type: EntityType.DATE,
          mentions: [{ context: '2023-01-01 context', position: 5, relevance: 0.9 }]
        }
      ];
    });

    it('should filter by confidence threshold', () => {
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.6
      };
      
      const filtered = extractor.testFilterEntities(entities, options);
      
      expect(filtered).toHaveLength(3);
      expect(filtered.map(e => e.name)).toContain('John Doe');
      expect(filtered.map(e => e.name)).toContain('Acme Corp');
      expect(filtered.map(e => e.name)).toContain('2023-01-01');
      expect(filtered.map(e => e.name)).not.toContain('Jane Smith');
    });

    it('should filter by entity types', () => {
      const options: EntityExtractionOptions = {
        entityTypes: [EntityType.PERSON, EntityType.DATE]
      };
      
      const filtered = extractor.testFilterEntities(entities, options);
      
      expect(filtered).toHaveLength(3);
      expect(filtered.map(e => e.type)).toEqual([EntityType.PERSON, EntityType.PERSON, EntityType.DATE]);
    });

    it('should limit number of entities', () => {
      const options: EntityExtractionOptions = {
        maxEntities: 2
      };
      
      const filtered = extractor.testFilterEntities(entities, options);
      
      expect(filtered).toHaveLength(2);
    });

    it('should apply multiple filters combined', () => {
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.6,
        entityTypes: [EntityType.PERSON, EntityType.ORGANIZATION],
        maxEntities: 1
      };
      
      const filtered = extractor.testFilterEntities(entities, options);
      
      expect(filtered).toHaveLength(1);
      expect(filtered[0].name).toBe('John Doe');
    });
  });
});