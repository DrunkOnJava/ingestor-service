/**
 * API Configuration
 * 
 * Central configuration for the RESTful API server.
 * This loads settings from environment variables with sensible defaults.
 */

import dotenv from 'dotenv';
import path from 'path';

// Load environment variables from .env file
dotenv.config();

/**
 * Default configuration values
 */
const config = {
  env: process.env.NODE_ENV || 'development',
  
  // Server settings
  server: {
    port: parseInt(process.env.API_PORT || '3000', 10),
    host: process.env.API_HOST || 'localhost',
    basePath: process.env.API_BASE_PATH || '/api',
  },
  
  // CORS configuration
  cors: {
    origin: process.env.CORS_ORIGIN || '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key'],
    exposedHeaders: ['X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-RateLimit-Reset'],
    credentials: true,
  },
  
  // Rate limiting
  rateLimit: {
    standard: parseInt(process.env.RATE_LIMIT_STANDARD || '1000', 10), // Default: 1000 requests per hour
    auth: parseInt(process.env.RATE_LIMIT_AUTH || '50', 10), // Default: 50 login attempts per hour
  },
  
  // JWT authentication
  jwt: {
    secret: process.env.JWT_SECRET || 'development-secret-change-in-production',
    expiresIn: process.env.JWT_EXPIRES_IN || '24h',
    issuer: process.env.JWT_ISSUER || 'ingestor-api',
  },
  
  // API Keys
  apiKeys: {
    headerName: process.env.API_KEY_HEADER || 'X-API-Key',
    // In production, API keys should be stored in a database, not hardcoded
    validKeys: (process.env.API_KEYS || '').split(',').filter(Boolean),
  },
  
  // WebSocket settings
  websocket: {
    path: '/api/v1/ws',
    pingInterval: parseInt(process.env.WS_PING_INTERVAL || '30000', 10), // 30 seconds
  },
  
  // Content processing
  processing: {
    uploadDir: process.env.UPLOAD_DIR || path.join(process.cwd(), 'uploads'),
    maxFileSize: parseInt(process.env.MAX_FILE_SIZE || '10485760', 10), // 10MB
    allowedTypes: (process.env.ALLOWED_TYPES || 'text,image,video,code,pdf,document').split(','),
    defaultChunkSize: parseInt(process.env.DEFAULT_CHUNK_SIZE || '500000', 10), // 500KB
    defaultChunkOverlap: parseInt(process.env.DEFAULT_CHUNK_OVERLAP || '5000', 10), // 5KB
  },
  
  // Batch processing
  batch: {
    maxConcurrent: parseInt(process.env.BATCH_MAX_CONCURRENT || '5', 10),
    timeout: parseInt(process.env.BATCH_TIMEOUT || '3600000', 10), // 1 hour
    pollInterval: parseInt(process.env.BATCH_POLL_INTERVAL || '5000', 10), // 5 seconds
  },
  
  // Database connection
  database: {
    dir: process.env.DB_DIR || path.join(process.cwd(), 'databases'),
    defaultDb: process.env.DEFAULT_DB || 'ingestor.sqlite',
  },
  
  // Logging
  logging: {
    level: process.env.LOG_LEVEL || 'info',
    file: process.env.LOG_FILE || path.join(process.cwd(), 'logs', 'api.log'),
  },
  
  // Claude AI integration
  claude: {
    apiKey: process.env.CLAUDE_API_KEY || '',
    model: process.env.CLAUDE_MODEL || 'claude-3-opus-20240229',
    timeout: parseInt(process.env.CLAUDE_TIMEOUT || '60000', 10), // 60 seconds
  },
};

/**
 * Environment-specific configuration overrides
 */
if (config.env === 'production') {
  // Validate that critical settings are provided in production
  if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET environment variable is required in production');
  }
  
  if (!process.env.CLAUDE_API_KEY) {
    throw new Error('CLAUDE_API_KEY environment variable is required in production');
  }
  
  // In production, restrict CORS to specific origins
  if (process.env.CORS_ORIGIN === '*') {
    console.warn('Warning: CORS is configured to allow all origins in production');
  }
}

export default config;