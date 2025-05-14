/**
 * Base EntityExtractor class
 * Provides the core interface and functionality for entity extraction
 */

import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityType } from './types';
import { Logger } from '../logging';

/**
 * Abstract base class for entity extractors
 * Defines the common interface and shared functionality for all entity extractors
 */
export abstract class EntityExtractor {
  protected logger: Logger;
  protected options: EntityExtractionOptions;
  
  /**
   * Creates a new EntityExtractor
   * @param logger Logger instance for extraction logging
   * @param options Default options for entity extraction
   */
  constructor(logger: Logger, options: EntityExtractionOptions = {}) {
    this.logger = logger;
    this.options = {
      confidenceThreshold: 0.5,
      maxEntities: 50,
      ...options
    };
  }
  
  /**
   * Extract entities from content
   * @param content The content to extract entities from (can be text or file path)
   * @param contentType MIME type of the content (e.g., "text/plain", "image/jpeg")
   * @param options Options to customize extraction behavior
   */
  public abstract extract(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult>;
  
  /**
   * Normalize entity name based on its type
   * @param name Raw entity name
   * @param type Entity type
   * @returns Normalized entity name
   */
  protected normalizeEntityName(name: string, type: EntityType): string {
    // Basic normalization - remove quotes and extra spaces
    let normalized = name.replace(/"/g, '').replace(/\s+/g, ' ').trim();
    
    // Type-specific normalization
    switch (type) {
      case EntityType.PERSON:
        // Capitalize first letter of each word for person names
        normalized = normalized.split(' ')
          .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
          .join(' ');
        break;
        
      case EntityType.ORGANIZATION:
        // Organizations often have specific capitalization, preserve most of it
        normalized = normalized.trim();
        break;
        
      case EntityType.LOCATION:
        // Capitalize first letter of each word for locations
        normalized = normalized.split(' ')
          .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
          .join(' ');
        break;
        
      case EntityType.DATE:
        // Standardize date formats
        if (/^\d{1,2}\/\d{1,2}\/\d{2,4}$/.test(normalized)) {
          // Convert MM/DD/YYYY to YYYY-MM-DD (very basic)
          const parts = normalized.split('/');
          normalized = `${parts[2]}-${parts[0]}-${parts[1]}`;
        }
        break;
        
      default:
        // Default normalization just trims whitespace
        normalized = normalized.trim();
        break;
    }
    
    return normalized;
  }
  
  /**
   * Validate if an entity type is supported
   * @param type Entity type to validate
   * @returns True if the type is valid, false otherwise
   */
  protected isValidEntityType(type: string): boolean {
    return Object.values(EntityType).includes(type as EntityType);
  }
  
  /**
   * Merge entities from multiple extractors or sources
   * @param entityLists Arrays of entities to merge
   * @returns Merged unique entities
   */
  protected mergeEntities(entityLists: Entity[][]): Entity[] {
    const entityMap = new Map<string, Entity>();
    
    // Process each list of entities
    for (const entityList of entityLists) {
      for (const entity of entityList) {
        const key = `${entity.type}:${entity.name}`;
        
        if (entityMap.has(key)) {
          // If we've seen this entity before, merge its mentions
          const existingEntity = entityMap.get(key)!;
          existingEntity.mentions = [
            ...existingEntity.mentions,
            ...entity.mentions
          ];
          
          // Use the longer description if available
          if (entity.description && (!existingEntity.description || 
              entity.description.length > existingEntity.description.length)) {
            existingEntity.description = entity.description;
          }
        } else {
          // If we haven't seen this entity before, add it to our map
          entityMap.set(key, { ...entity });
        }
      }
    }
    
    // Convert map back to array
    return Array.from(entityMap.values());
  }
  
  /**
   * Filter entities based on extraction options
   * @param entities Raw extracted entities
   * @param options Entity extraction options
   * @returns Filtered entities
   */
  protected filterEntities(
    entities: Entity[], 
    options: EntityExtractionOptions = {}
  ): Entity[] {
    const mergedOptions = { ...this.options, ...options };
    let filtered = [...entities];
    
    // Filter by confidence threshold
    if (mergedOptions.confidenceThreshold !== undefined) {
      filtered = filtered.filter(entity => 
        entity.mentions.some(mention => mention.relevance >= (mergedOptions.confidenceThreshold || 0))
      );
    }
    
    // Filter by entity type
    if (mergedOptions.entityTypes !== undefined && mergedOptions.entityTypes.length > 0) {
      filtered = filtered.filter(entity => 
        mergedOptions.entityTypes?.includes(entity.type as EntityType)
      );
    }
    
    // Limit number of entities
    if (mergedOptions.maxEntities !== undefined) {
      filtered = filtered.slice(0, mergedOptions.maxEntities);
    }
    
    return filtered;
  }
}