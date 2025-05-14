/**
 * Entity Controller
 * 
 * Handles entity management operations including creating, updating,
 * retrieving, and deleting entities and their relationships.
 */

import { Request, Response, NextFunction } from 'express';
import { v4 as uuid } from 'uuid';
import { ApiError } from '../middleware/error-handler';
import { Logger } from '../../core/logging/Logger';
import { EntityRepository } from '../../core/entity/EntityRepository';
import { RelationshipRepository } from '../../core/entity/RelationshipRepository';
import { ContentRepository } from '../../core/content/ContentRepository';
import { getWebSocketManager, EventType } from '../websocket';
import config from '../config';

// Initialize logger
const logger = new Logger('api:controller:entity');

// Helper function for pagination
const getPaginationParams = (req: Request) => {
  const limit = Math.min(
    parseInt(req.query.limit as string || '50', 10),
    config.api.maxPageSize
  );
  const offset = parseInt(req.query.offset as string || '0', 10);
  const sort = (req.query.sort as string) || 'createdAt';
  const order = (req.query.order as string) || 'desc';
  
  return { limit, offset, sort, order };
};

/**
 * Entity controller methods
 */
export const entityController = {
  /**
   * List entities with filtering and pagination
   */
  async listEntities(req: Request, res: Response, next: NextFunction) {
    try {
      const { limit, offset, sort, order } = getPaginationParams(req);
      
      // Get filtering options
      const type = req.query.type as string;
      const query = req.query.q as string;
      const minConfidence = parseFloat(req.query.minConfidence as string || '0.5');
      
      // Get entities from repository
      const entityRepo = new EntityRepository();
      const result = await entityRepo.findAll({
        type,
        query,
        minConfidence,
        limit,
        offset,
        sort,
        order,
      });
      
      // Prepare response
      res.json({
        success: true,
        data: result.entities,
        meta: {
          pagination: {
            limit,
            offset,
            total: result.total,
            next: result.hasMore ? `/api/v1/entities?limit=${limit}&offset=${offset + limit}` : null,
            previous: offset > 0 ? `/api/v1/entities?limit=${limit}&offset=${Math.max(0, offset - limit)}` : null,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get entity types with counts
   */
  async getEntityTypes(req: Request, res: Response, next: NextFunction) {
    try {
      const entityRepo = new EntityRepository();
      const types = await entityRepo.getEntityTypes();
      
      res.json({
        success: true,
        data: types,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get entity by ID
   */
  async getEntity(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      const entityRepo = new EntityRepository();
      const entity = await entityRepo.findById(id);
      
      if (!entity) {
        throw new ApiError(`Entity not found with ID: ${id}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      res.json({
        success: true,
        data: entity,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Create new entity
   */
  async createEntity(req: Request, res: Response, next: NextFunction) {
    try {
      const entityData = req.body;
      const contentIds = entityData.contentIds || [];
      
      // Set entity ID and source
      const entityId = uuid();
      const entity = {
        ...entityData,
        id: entityId,
        source: 'manual',
        confidence: 1.0, // Manual entities always have perfect confidence
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };
      
      // Create entity
      const entityRepo = new EntityRepository();
      await entityRepo.create(entity);
      
      // Associate with content if provided
      if (contentIds.length > 0) {
        const contentRepo = new ContentRepository();
        
        for (const contentId of contentIds) {
          try {
            await contentRepo.associateEntity(contentId, entityId);
          } catch (err) {
            logger.warn(`Failed to associate entity with content: ${contentId}`, {
              entityId,
              contentId,
              error: (err as Error).message,
            });
          }
        }
      }
      
      // Notify via WebSocket
      const wsManager = getWebSocketManager();
      if (wsManager) {
        wsManager.broadcast(EventType.ENTITY_CREATED, {
          id: entityId,
          type: entity.type,
          name: entity.name,
        });
      }
      
      // Return success response
      res.status(201).json({
        success: true,
        data: entity,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Update entity
   */
  async updateEntity(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const updates = req.body;
      
      // Get existing entity
      const entityRepo = new EntityRepository();
      const existingEntity = await entityRepo.findById(id);
      
      if (!existingEntity) {
        throw new ApiError(`Entity not found with ID: ${id}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      // Prepare update data
      const updatedEntity = {
        ...existingEntity,
        ...updates,
        updatedAt: new Date().toISOString(),
      };
      
      // Update entity
      await entityRepo.update(id, updatedEntity);
      
      // Return updated entity
      res.json({
        success: true,
        data: updatedEntity,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Delete entity
   */
  async deleteEntity(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Delete entity
      const entityRepo = new EntityRepository();
      const relationshipRepo = new RelationshipRepository();
      
      // First check if entity exists
      const entity = await entityRepo.findById(id);
      
      if (!entity) {
        throw new ApiError(`Entity not found with ID: ${id}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      // Delete all relationships involving this entity
      await relationshipRepo.deleteByEntityId(id);
      
      // Delete the entity
      await entityRepo.delete(id);
      
      // Return success response
      res.json({
        success: true,
        data: {
          message: `Entity with ID ${id} deleted successfully`,
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get related entities
   */
  async getRelatedEntities(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const type = req.query.type as string;
      const limit = Math.min(
        parseInt(req.query.limit as string || '20', 10),
        100
      );
      
      // Check if entity exists
      const entityRepo = new EntityRepository();
      const entity = await entityRepo.findById(id);
      
      if (!entity) {
        throw new ApiError(`Entity not found with ID: ${id}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      // Get relationships
      const relationshipRepo = new RelationshipRepository();
      const relationships = await relationshipRepo.findByEntityId(id, { type, limit });
      
      // Get related entities
      const relatedEntities = [];
      
      for (const relationship of relationships) {
        const relatedEntityId = relationship.sourceId === id
          ? relationship.targetId
          : relationship.sourceId;
          
        const direction = relationship.sourceId === id
          ? 'outgoing'
          : 'incoming';
          
        const relatedEntity = await entityRepo.findById(relatedEntityId);
        
        if (relatedEntity) {
          relatedEntities.push({
            entity: relatedEntity,
            relationship: relationship.type,
            direction,
          });
        }
      }
      
      // Return related entities
      res.json({
        success: true,
        data: relatedEntities,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get content associated with entity
   */
  async getEntityContent(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { limit, offset } = getPaginationParams(req);
      
      // Check if entity exists
      const entityRepo = new EntityRepository();
      const entity = await entityRepo.findById(id);
      
      if (!entity) {
        throw new ApiError(`Entity not found with ID: ${id}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      // Get associated content
      const contentRepo = new ContentRepository();
      const result = await contentRepo.findByEntityId(id, { limit, offset });
      
      // Return paginated content
      res.json({
        success: true,
        data: result.content,
        meta: {
          pagination: {
            limit,
            offset,
            total: result.total,
            next: result.hasMore ? `/api/v1/entities/${id}/content?limit=${limit}&offset=${offset + limit}` : null,
            previous: offset > 0 ? `/api/v1/entities/${id}/content?limit=${limit}&offset=${Math.max(0, offset - limit)}` : null,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Create relationship between entities
   */
  async createRelationship(req: Request, res: Response, next: NextFunction) {
    try {
      const { sourceId, targetId, type, properties } = req.body;
      
      // Check if entities exist
      const entityRepo = new EntityRepository();
      const sourceEntity = await entityRepo.findById(sourceId);
      const targetEntity = await entityRepo.findById(targetId);
      
      if (!sourceEntity) {
        throw new ApiError(`Source entity not found with ID: ${sourceId}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      if (!targetEntity) {
        throw new ApiError(`Target entity not found with ID: ${targetId}`, 404, 'ENTITY_NOT_FOUND');
      }
      
      // Check if relationship already exists
      const relationshipRepo = new RelationshipRepository();
      const existingRelationship = await relationshipRepo.findByEntities(sourceId, targetId, type);
      
      if (existingRelationship) {
        throw new ApiError(
          `Relationship already exists between entities ${sourceId} and ${targetId} with type "${type}"`,
          409,
          'RELATIONSHIP_ALREADY_EXISTS'
        );
      }
      
      // Create relationship
      const relationshipId = uuid();
      const relationship = {
        id: relationshipId,
        sourceId,
        targetId,
        type,
        properties: properties || {},
        createdAt: new Date().toISOString(),
      };
      
      await relationshipRepo.create(relationship);
      
      // Return success response
      res.status(201).json({
        success: true,
        data: relationship,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Delete relationship
   */
  async deleteRelationship(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Delete relationship
      const relationshipRepo = new RelationshipRepository();
      
      // Check if relationship exists
      const relationship = await relationshipRepo.findById(id);
      
      if (!relationship) {
        throw new ApiError(`Relationship not found with ID: ${id}`, 404, 'RELATIONSHIP_NOT_FOUND');
      }
      
      // Delete the relationship
      await relationshipRepo.delete(id);
      
      // Return success response
      res.json({
        success: true,
        data: {
          message: `Relationship with ID ${id} deleted successfully`,
        },
      });
    } catch (error) {
      next(error);
    }
  },
};