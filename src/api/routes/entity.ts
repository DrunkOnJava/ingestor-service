/**
 * Entity API Routes
 * 
 * Endpoints for managing entities and relationships
 */

import { Router } from 'express';
import { entityController } from '../controllers/entity';
import { validateEntityCreate, validateEntityUpdate, validateRelationshipCreate } from '../validators/entity';

// Create router
const router = Router();

/**
 * List all entities with optional filtering
 * GET /api/v1/entities
 */
router.get('/', entityController.listEntities);

/**
 * Get entity types with counts
 * GET /api/v1/entities/types
 */
router.get('/types', entityController.getEntityTypes);

/**
 * Create a new entity
 * POST /api/v1/entities
 */
router.post('/', validateEntityCreate, entityController.createEntity);

/**
 * Get entity by ID
 * GET /api/v1/entities/:id
 */
router.get('/:id', entityController.getEntity);

/**
 * Update entity
 * PUT /api/v1/entities/:id
 */
router.put('/:id', validateEntityUpdate, entityController.updateEntity);

/**
 * Delete entity
 * DELETE /api/v1/entities/:id
 */
router.delete('/:id', entityController.deleteEntity);

/**
 * Get related entities
 * GET /api/v1/entities/:id/related
 */
router.get('/:id/related', entityController.getRelatedEntities);

/**
 * Get content items associated with entity
 * GET /api/v1/entities/:id/content
 */
router.get('/:id/content', entityController.getEntityContent);

/**
 * Create relationship between entities
 * POST /api/v1/entities/relationships
 */
router.post('/relationships', validateRelationshipCreate, entityController.createRelationship);

/**
 * Delete relationship
 * DELETE /api/v1/entities/relationships/:id
 */
router.delete('/relationships/:id', entityController.deleteRelationship);

export default router;