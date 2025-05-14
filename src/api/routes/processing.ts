/**
 * Processing API Routes
 * 
 * Endpoints for content processing operations
 */
import { Router } from 'express';
import { validateProcessingRequest } from '../validators/processing';
import { processingController } from '../controllers/processing';

// Create router
const router = Router();

// Routes for content processing
router.post('/analyze', validateProcessingRequest, processingController.analyzeContent);
router.post('/extract-entities', validateProcessingRequest, processingController.extractEntities);
router.post('/batch', validateProcessingRequest, processingController.createBatchProcess);
router.get('/status/:jobId', processingController.getProcessingStatus);
router.delete('/cancel/:jobId', processingController.cancelProcessing);

export default router;