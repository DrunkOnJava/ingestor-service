/**
 * Entity storage utilities
 * Provides helper functions for storing and retrieving entities
 */

import { Entity, EntityType } from '../types';
import { Logger } from '../../logging';
import { DatabaseService } from '../../services/DatabaseService';

/**
 * Class for handling entity storage operations
 */
export class EntityStorage {
  private logger: Logger;
  private db: DatabaseService;
  
  /**
   * Creates a new EntityStorage instance
   * @param logger Logger instance
   * @param db Database service
   */
  constructor(logger: Logger, db: DatabaseService) {
    this.logger = logger;
    this.db = db;
  }
  
  /**
   * Store an entity in the database
   * @param name Entity name
   * @param type Entity type
   * @param description Optional entity description
   * @returns Entity ID or null if storage failed
   */
  public async storeEntity(
    name: string, 
    type: EntityType, 
    description: string = ''
  ): Promise<number | null> {
    try {
      this.logger.debug(`Storing entity: ${name} (${type})`);
      
      // Check if entity already exists
      const existingId = await this.db.query(
        'SELECT id FROM entities WHERE name = ? AND entity_type = ? LIMIT 1',
        [name, type]
      );
      
      if (existingId && existingId.length > 0) {
        this.logger.debug(`Entity already exists with ID ${existingId[0].id}`);
        return existingId[0].id;
      }
      
      // If entity doesn't exist, create it
      const result = await this.db.query(
        'INSERT INTO entities (name, entity_type, description) VALUES (?, ?, ?) RETURNING id',
        [name, type, description]
      );
      
      if (result && result.length > 0) {
        const entityId = result[0].id;
        this.logger.debug(`Entity stored with ID ${entityId}`);
        return entityId;
      }
      
      return null;
    } catch (error) {
      this.logger.error(`Failed to store entity: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return null;
    }
  }
  
  /**
   * Link an entity to content
   * @param entityId Entity ID
   * @param contentId Content ID
   * @param contentType Content type
   * @param relevance Relevance score (0.0-1.0)
   * @param context Context text where entity was found
   * @returns True if successful, false otherwise
   */
  public async linkEntityToContent(
    entityId: number,
    contentId: number,
    contentType: string,
    relevance: number = 0.5,
    context: string = ''
  ): Promise<boolean> {
    try {
      this.logger.debug(`Linking entity ${entityId} to content ${contentId} (${contentType})`);
      
      // Check if link already exists
      const existingLink = await this.db.query(
        'SELECT COUNT(*) as count FROM content_entities WHERE content_id = ? AND content_type = ? AND entity_id = ?',
        [contentId, contentType, entityId]
      );
      
      if (existingLink && existingLink.length > 0 && existingLink[0].count > 0) {
        // Update existing link with new relevance and context
        await this.db.query(
          'UPDATE content_entities SET relevance = ?, context = ? WHERE content_id = ? AND content_type = ? AND entity_id = ?',
          [relevance, context, contentId, contentType, entityId]
        );
      } else {
        // Create new link
        await this.db.query(
          'INSERT INTO content_entities (content_id, content_type, entity_id, relevance, context) VALUES (?, ?, ?, ?, ?)',
          [contentId, contentType, entityId, relevance, context]
        );
      }
      
      return true;
    } catch (error) {
      this.logger.error(`Failed to link entity to content: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
  
  /**
   * Get entities for a specific content
   * @param contentId Content ID
   * @param contentType Content type
   * @returns Array of entities
   */
  public async getEntitiesForContent(
    contentId: number,
    contentType: string
  ): Promise<Entity[]> {
    try {
      this.logger.debug(`Getting entities for content ${contentId} (${contentType})`);
      
      const rows = await this.db.query(`
        SELECT e.id, e.name, e.entity_type, e.description,
               ce.relevance, ce.context
        FROM entities e
        JOIN content_entities ce ON e.id = ce.entity_id
        WHERE ce.content_id = ? AND ce.content_type = ?
        ORDER BY ce.relevance DESC
      `, [contentId, contentType]);
      
      if (!rows || rows.length === 0) {
        return [];
      }
      
      // Group by entity to handle multiple mentions
      const entityMap = new Map<number, Entity>();
      
      for (const row of rows) {
        const entityId = row.id;
        
        if (!entityMap.has(entityId)) {
          entityMap.set(entityId, {
            name: row.name,
            type: row.entity_type as EntityType,
            description: row.description,
            mentions: []
          });
        }
        
        // Add mention
        const entity = entityMap.get(entityId)!;
        entity.mentions.push({
          context: row.context,
          position: 0, // Not stored in DB
          relevance: row.relevance
        });
      }
      
      return Array.from(entityMap.values());
    } catch (error) {
      this.logger.error(`Failed to get entities for content: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Search for entities
   * @param query Search query
   * @param types Optional array of entity types to filter by
   * @param limit Maximum number of results to return
   * @returns Array of matching entities
   */
  public async searchEntities(
    query: string, 
    types?: EntityType[],
    limit: number = 50
  ): Promise<Entity[]> {
    try {
      this.logger.debug(`Searching for entities matching "${query}"`);
      
      let sql = `
        SELECT e.id, e.name, e.entity_type, e.description,
               ce.relevance, ce.context
        FROM entities e
        LEFT JOIN content_entities ce ON e.id = ce.entity_id
        WHERE e.name LIKE ?
      `;
      
      const params = [`%${query}%`];
      
      // Add type filter if provided
      if (types && types.length > 0) {
        sql += ' AND e.entity_type IN (?)';
        params.push(types.join(','));
      }
      
      // Add limit and order
      sql += ' ORDER BY e.name LIMIT ?';
      params.push(limit);
      
      const rows = await this.db.query(sql, params);
      
      if (!rows || rows.length === 0) {
        return [];
      }
      
      // Group by entity
      const entityMap = new Map<number, Entity>();
      
      for (const row of rows) {
        const entityId = row.id;
        
        if (!entityMap.has(entityId)) {
          entityMap.set(entityId, {
            name: row.name,
            type: row.entity_type as EntityType,
            description: row.description,
            mentions: []
          });
        }
        
        // Add mention if available
        if (row.context) {
          const entity = entityMap.get(entityId)!;
          entity.mentions.push({
            context: row.context,
            position: 0,
            relevance: row.relevance || 0.5
          });
        }
      }
      
      return Array.from(entityMap.values());
    } catch (error) {
      this.logger.error(`Failed to search entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
}