/**
 * Batch Processing API Routes
 * 
 * Endpoints for managing batch operations (folder imports, bulk processing, etc.)
 */

import { Router } from 'express';
import { batchController } from '../controllers/batch';
import { validateBatchCreate } from '../validators/batch';

// Create router
const router = Router();

/**
 * List batch processes with pagination and filtering
 * GET /api/v1/batch
 */
router.get('/', batchController.listBatchProcesses);

/**
 * Create new batch process
 * POST /api/v1/batch
 */
router.post('/', validateBatchCreate, batchController.createBatchProcess);

/**
 * Get batch process by ID
 * GET /api/v1/batch/:id
 */
router.get('/:id', batchController.getBatchProcess);

/**
 * Cancel a batch process
 * POST /api/v1/batch/:id/cancel
 */
router.post('/:id/cancel', batchController.cancelBatchProcess);

/**
 * Get batch process items
 * GET /api/v1/batch/:id/items
 */
router.get('/:id/items', batchController.listBatchProcessItems);

export default router;