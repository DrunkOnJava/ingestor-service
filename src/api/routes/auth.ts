/**
 * Authentication Routes
 * 
 * Endpoints for user authentication and API key management.
 */

import { Router } from 'express';
import { expressjwt } from 'express-jwt';
import rateLimit from 'express-rate-limit';
import { authController } from '../controllers/auth';
import { validateLogin, validateRegister, validateChangePassword } from '../validators/auth';
import config from '../config';

// Create router
const router = Router();

// Configure rate limiting for authentication endpoints
const authLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: config.rateLimit.auth, // Limit login attempts
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMIT_EXCEEDED',
      message: 'Too many login attempts, please try again later.'
    }
  }
});

// JWT middleware
const jwtAuth = expressjwt({
  secret: config.jwt.secret,
  algorithms: ['HS256']
});

/**
 * Login user
 * POST /api/v1/auth/login
 */
router.post('/login', authLimiter, validateLogin, authController.login);

/**
 * Register new user
 * POST /api/v1/auth/register
 */
router.post('/register', validateRegister, authController.register);

/**
 * Get current user info
 * GET /api/v1/auth/me
 */
router.get('/me', jwtAuth, authController.getCurrentUser);

/**
 * Change password
 * POST /api/v1/auth/change-password
 */
router.post('/change-password', jwtAuth, validateChangePassword, authController.changePassword);

/**
 * Generate API key
 * POST /api/v1/auth/api-keys
 */
router.post('/api-keys', jwtAuth, authController.generateApiKey);

/**
 * List API keys
 * GET /api/v1/auth/api-keys
 */
router.get('/api-keys', jwtAuth, authController.listApiKeys);

/**
 * Delete API key
 * DELETE /api/v1/auth/api-keys/:id
 */
router.delete('/api-keys/:id', jwtAuth, authController.deleteApiKey);

export default router;