/**
 * Database API Routes
 * 
 * Endpoints for database operations and management
 */
import { Router } from 'express';
import { validateDatabaseQuery, validateDatabaseOperation } from '../validators/database';
import { databaseController } from '../controllers/database';

// Create router
const router = Router();

// Routes for database operations
router.get('/list', databaseController.listDatabases);
router.get('/:database/schema', databaseController.getDatabaseSchema);
router.get('/:database/stats', databaseController.getDatabaseStats);
router.post('/:database/init', databaseController.initializeDatabase);
router.post('/:database/query', validateDatabaseQuery, databaseController.queryDatabase);
router.post('/:database/optimize', databaseController.optimizeDatabase);
router.post('/:database/backup', databaseController.backupDatabase);
router.post('/:database/operation', validateDatabaseOperation, databaseController.performDatabaseOperation);

export default router;