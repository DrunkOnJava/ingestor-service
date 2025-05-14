/**
 * System API Routes
 * 
 * Endpoints for system monitoring, configuration, and statistics
 */

import { Router } from 'express';
import { systemController } from '../controllers/system';

// Create router
const router = Router();

/**
 * Get system status
 * GET /api/v1/system/status
 */
router.get('/status', systemController.getSystemStatus);

/**
 * Get system information
 * GET /api/v1/system/info
 */
router.get('/info', systemController.getSystemInfo);

/**
 * Get system configuration
 * GET /api/v1/system/config
 */
router.get('/config', systemController.getSystemConfig);

/**
 * Get system statistics
 * GET /api/v1/system/statistics
 */
router.get('/statistics', systemController.getSystemStatistics);

export default router;