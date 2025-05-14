/**
 * EntityManager class
 * Manages entity extraction, normalization, validation, and storage
 */

import { EntityExtractor } from './EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityType } from './types';
import { Logger } from '../logging';
import { DatabaseService } from '../services/DatabaseService';
import { TextEntityExtractor } from './extractors';
import { ClaudeService } from '../services/ClaudeService';

/**
 * Manager for entity extraction and storage
 * Coordinates between different entity extractors and the database
 */
export class EntityManager {
  private logger: Logger;
  private db?: DatabaseService;
  private extractors: Map<string, EntityExtractor>;
  private claudeService?: ClaudeService;
  
  /**
   * Creates a new EntityManager
   * @param logger Logger instance
   * @param db Optional database service for entity storage
   * @param claudeService Optional Claude service for AI-powered extraction
   */
  constructor(
    logger: Logger, 
    db?: DatabaseService,
    claudeService?: ClaudeService
  ) {
    this.logger = logger;
    this.db = db;
    this.claudeService = claudeService;
    this.extractors = new Map();
    
    // Initialize with default extractors
    this.initializeExtractors();
  }
  
  /**
   * Initialize default entity extractors
   * @private
   */
  private initializeExtractors(): void {
    // Register text entity extractor
    const textExtractor = new TextEntityExtractor(
      this.logger,
      { confidenceThreshold: 0.5, maxEntities: 50 },
      this.claudeService
    );
    
    // Register extractors by content type
    this.registerExtractor('text/plain', textExtractor);
    this.registerExtractor('text/markdown', textExtractor);
    this.registerExtractor('text/html', textExtractor);
    this.registerExtractor('text/*', textExtractor); // Fallback for all text types
    
    // Add more specialized extractors in the future
    // this.registerExtractor('application/json', jsonExtractor);
    // this.registerExtractor('application/xml', xmlExtractor);
    // this.registerExtractor('application/pdf', pdfExtractor);
    // this.registerExtractor('image/*', imageExtractor);
    // this.registerExtractor('video/*', videoExtractor);
    // this.registerExtractor('text/x-*', codeExtractor);
  }
  
  /**
   * Register an entity extractor for a specific content type
   * @param contentType MIME type or pattern (e.g., "text/plain", "image/*")
   * @param extractor EntityExtractor instance
   */
  public registerExtractor(contentType: string, extractor: EntityExtractor): void {
    this.extractors.set(contentType, extractor);
    this.logger.debug(`Registered entity extractor for ${contentType}`);
  }
  
  /**
   * Extract entities from content
   * @param content Content to analyze (text or file path)
   * @param contentType MIME type of the content
   * @param options Extraction options
   */
  public async extractEntities(
    content: string,
    contentType: string,
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    this.logger.info(`Extracting entities from content: ${contentType}`);
    
    // Find the right extractor for this content type
    const extractor = this.getExtractorForContentType(contentType);
    
    if (!extractor) {
      this.logger.error(`No entity extractor found for content type: ${contentType}`);
      return {
        entities: [],
        success: false,
        error: `Unsupported content type: ${contentType}`
      };
    }
    
    try {
      // Extract entities using the appropriate extractor
      return await extractor.extract(content, contentType, options);
    } catch (error) {
      this.logger.error(`Entity extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {
        entities: [],
        success: false,
        error: `Extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`
      };
    }
  }
  
  /**
   * Store entities in the database
   * @param contentId ID of the content these entities belong to
   * @param contentType MIME type of the content
   * @param entities Array of entities to store
   * @returns Array of entity IDs
   */
  public async storeEntities(
    contentId: number,
    contentType: string,
    entities: Entity[]
  ): Promise<number[]> {
    if (!this.db) {
      this.logger.warning('No database service provided, skipping entity storage');
      return [];
    }
    
    if (!entities || entities.length === 0) {
      this.logger.debug('No entities to store');
      return [];
    }
    
    this.logger.info(`Storing ${entities.length} entities for content ID ${contentId}`);
    const entityIds: number[] = [];
    
    for (const entity of entities) {
      try {
        // Normalize entity name
        const normalizedName = this.normalizeEntityName(entity.name, entity.type);
        
        // Validate entity type
        const entityType = this.validateEntityType(entity.type);
        
        // Store entity in database and get its ID
        const entityId = await this.db.storeEntity(
          normalizedName, 
          entityType, 
          entity.description || ''
        );
        
        if (entityId) {
          // Link entity to content
          for (const mention of entity.mentions) {
            await this.db.linkEntityToContent(
              entityId,
              contentId,
              contentType,
              mention.relevance,
              mention.context
            );
          }
          
          entityIds.push(entityId);
        }
      } catch (error) {
        this.logger.error(`Failed to store entity ${entity.name}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
    }
    
    this.logger.debug(`Successfully stored ${entityIds.length} entities`);
    return entityIds;
  }
  
  /**
   * Get the appropriate extractor for a content type
   * @param contentType MIME type to find extractor for
   * @returns EntityExtractor instance or undefined if none found
   * @private
   */
  private getExtractorForContentType(contentType: string): EntityExtractor | undefined {
    // First try exact match
    if (this.extractors.has(contentType)) {
      return this.extractors.get(contentType);
    }
    
    // Try category match (e.g., "text/*" for "text/plain")
    const category = `${contentType.split('/')[0]}/*`;
    if (this.extractors.has(category)) {
      return this.extractors.get(category);
    }
    
    // Try fallback extractors
    for (const [pattern, extractor] of this.extractors.entries()) {
      if (pattern.endsWith('*') && contentType.startsWith(pattern.replace('*', ''))) {
        return extractor;
      }
    }
    
    // No extractor found
    return undefined;
  }
  
  /**
   * Normalize entity name
   * @param name Raw entity name
   * @param type Entity type
   * @returns Normalized entity name
   * @private
   */
  private normalizeEntityName(name: string, type: EntityType | string): string {
    // Basic normalization
    let normalized = name.trim().replace(/"/g, '').replace(/\s+/g, ' ');
    
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
        // Try to standardize date formats (basic approach)
        if (/^\d{1,2}\/\d{1,2}\/\d{2,4}$/.test(normalized)) {
          // Convert MM/DD/YYYY to YYYY-MM-DD
          const parts = normalized.split('/');
          normalized = `${parts[2]}-${parts[0]}-${parts[1]}`;
        }
        break;
    }
    
    return normalized;
  }
  
  /**
   * Validate and normalize entity type
   * @param type Raw entity type
   * @returns Validated entity type
   * @private
   */
  private validateEntityType(type: EntityType | string): EntityType {
    // Check if the type is a valid EntityType
    if (Object.values(EntityType).includes(type as EntityType)) {
      return type as EntityType;
    }
    
    // Convert string type to enum if possible
    const normalizedType = type.toLowerCase();
    for (const [key, value] of Object.entries(EntityType)) {
      if (value === normalizedType) {
        return value;
      }
    }
    
    // Default to OTHER if type is invalid
    this.logger.warning(`Invalid entity type: ${type}, defaulting to ${EntityType.OTHER}`);
    return EntityType.OTHER;
  }
}