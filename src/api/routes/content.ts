/**
 * Content API Routes
 * 
 * Endpoints for managing content items (texts, images, videos, etc.)
 */

import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import { ApiError } from '../middleware/error-handler';
import { contentController } from '../controllers/content';
import { validateContentCreate, validateContentUpdate } from '../validators/content';
import config from '../config';

// Create router
const router = Router();

// Configure file upload middleware
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, config.processing.uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname);
    cb(null, file.fieldname + '-' + uniqueSuffix + ext);
  },
});

const upload = multer({
  storage,
  limits: {
    fileSize: config.processing.maxFileSize,
  },
  fileFilter: (req, file, cb) => {
    // Check if the file type is allowed based on mimetype
    const mimeType = file.mimetype.split('/')[0];
    if (config.processing.allowedTypes.includes(mimeType)) {
      cb(null, true);
    } else {
      cb(new ApiError(`File type not allowed: ${file.mimetype}`, 400, 'INVALID_FILE_TYPE'));
    }
  },
});

/**
 * List content items
 * GET /api/v1/content
 */
router.get('/', contentController.listContent);

/**
 * Get content item by ID
 * GET /api/v1/content/:id
 */
router.get('/:id', contentController.getContent);

/**
 * Create new content item by raw content
 * POST /api/v1/content
 */
router.post('/', validateContentCreate, contentController.createContent);

/**
 * Upload a file as content
 * POST /api/v1/content/upload
 */
router.post('/upload', upload.single('file'), contentController.uploadContent);

/**
 * Update content item
 * PUT /api/v1/content/:id
 */
router.put('/:id', validateContentUpdate, contentController.updateContent);

/**
 * Delete content item
 * DELETE /api/v1/content/:id
 */
router.delete('/:id', contentController.deleteContent);

/**
 * Get entities for a content item
 * GET /api/v1/content/:id/entities
 */
router.get('/:id/entities', contentController.getContentEntities);

/**
 * Get related content
 * GET /api/v1/content/:id/related
 */
router.get('/:id/related', contentController.getRelatedContent);

export default router;