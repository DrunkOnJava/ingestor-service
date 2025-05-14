/**
 * Ingestor System API
 * 
 * Main entry point for the RESTful API that provides access to the
 * content processing, entity extraction, and database capabilities.
 * 
 * @module api/server
 */

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import { json, urlencoded } from 'body-parser';
import { expressjwt } from 'express-jwt';
import rateLimit from 'express-rate-limit';
import swaggerUi from 'swagger-ui-express';
import YAML from 'yamljs';
import path from 'path';

// Import routes
import authRoutes from './routes/auth';
import contentRoutes from './routes/content';
import entityRoutes from './routes/entity';
import batchRoutes from './routes/batch';
import processingRoutes from './routes/processing';
import systemRoutes from './routes/system';
import databaseRoutes from './routes/database';

// Import middleware
import { errorHandler } from './middleware/error-handler';
import { requestLogger } from './middleware/request-logger';
import { apiKeyAuth } from './middleware/api-key-auth';

// Import configuration
import config from './config';

// Create Express app
const app = express();

// Load OpenAPI documentation
const openApiDocument = YAML.load(path.join(__dirname, '../../docs/api/openapi.yaml'));

// Apply middleware
app.use(helmet()); // Security headers
app.use(compression()); // Response compression
app.use(cors(config.cors)); // CORS configuration
app.use(json({ limit: '10mb' })); // Parse JSON bodies
app.use(urlencoded({ extended: true, limit: '10mb' })); // Parse URL-encoded bodies
app.use(requestLogger); // Log requests

// Configure rate limiting
const apiLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: config.rateLimit.standard, // Limit each IP per windowMs
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMIT_EXCEEDED',
      message: 'Too many requests, please try again later.'
    }
  }
});

// Apply rate limiting to all API routes
app.use('/api', apiLimiter);

// Authentication middleware
app.use('/api/v1', (req, res, next) => {
  // Skip auth for OpenAPI docs and auth routes
  if (req.path.startsWith('/docs') || req.path === '/auth/login') {
    return next();
  }

  // Try API key authentication first
  apiKeyAuth(req, res, (err) => {
    if (!err) return next(); // API key authentication successful

    // Fall back to JWT authentication
    expressjwt({
      secret: config.jwt.secret,
      algorithms: ['HS256']
    })(req, res, next);
  });
});

// API routes
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/content', contentRoutes);
app.use('/api/v1/entities', entityRoutes);
app.use('/api/v1/batches', batchRoutes);
app.use('/api/v1/processing', processingRoutes);
app.use('/api/v1/system', systemRoutes);
app.use('/api/v1/database', databaseRoutes);

// OpenAPI documentation
app.use('/api/docs', swaggerUi.serve);
app.get('/api/docs', swaggerUi.setup(openApiDocument));

// Catch-all route for non-existent endpoints
app.use('/api/*', (req, res) => {
  res.status(404).json({
    success: false,
    error: {
      code: 'ENDPOINT_NOT_FOUND',
      message: `Endpoint ${req.method} ${req.path} not found`
    }
  });
});

// Error handling middleware (must be last)
app.use(errorHandler);

// Create HTTP server
import http from 'http';
import { initWebSocketServer } from './websocket';

const server = http.createServer(app);

// Initialize WebSocket server
const wsManager = initWebSocketServer(server);

// Export both Express app and HTTP server
export { app, server, wsManager };

// Start the server if this file is run directly
if (require.main === module) {
  const PORT = process.env.PORT || config.server.port;
  
  server.listen(PORT, () => {
    console.log(`API server running on port ${PORT}`);
    console.log(`WebSocket server available at ws://localhost:${PORT}${config.websocket.path}`);
    console.log(`Documentation available at http://localhost:${PORT}/api/docs`);
  });
}