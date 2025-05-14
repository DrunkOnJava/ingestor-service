/**
 * Authentication Controller
 * 
 * Handles user authentication, token generation, and validation.
 */

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { v4 as uuidv4 } from 'uuid';
import { DatabaseService } from '../../core/services/DatabaseService';
import { Logger } from '../../core/logging/Logger';
import { ApiError } from '../middleware/error-handler';
import config from '../config';
import path from 'path';

const logger = new Logger('api:auth-controller');

/**
 * Authentication Controller implementation
 */
export const authController = {
  /**
   * Authenticate user and issue JWT token
   */
  async login(req: Request, res: Response, next: NextFunction) {
    try {
      const { username, password } = req.body;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if users table exists, if not create it
      const tableExists = await dbService.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='users'"
      );
      
      if (!tableExists || tableExists.length === 0) {
        // In a real application, this would be part of the initial database setup
        await dbService.query(`
          CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            role TEXT NOT NULL,
            created_at TEXT NOT NULL,
            last_login TEXT
          )
        `);
        
        // Create default admin user if no users exist
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash('admin', salt);
        
        await dbService.query(
          'INSERT INTO users (id, username, password, role, created_at) VALUES (?, ?, ?, ?, ?)',
          [uuidv4(), 'admin', hashedPassword, 'admin', new Date().toISOString()]
        );
        
        logger.info('Created default admin user');
      }
      
      // Find user
      const users = await dbService.query(
        'SELECT * FROM users WHERE username = ?',
        [username]
      );
      
      // Check if user exists
      if (!users || users.length === 0) {
        throw new ApiError('Invalid username or password', 401, 'INVALID_CREDENTIALS');
      }
      
      const user = users[0];
      
      // Verify password
      const isValid = await bcrypt.compare(password, user.password);
      
      if (!isValid) {
        throw new ApiError('Invalid username or password', 401, 'INVALID_CREDENTIALS');
      }
      
      // Update last login time
      await dbService.query(
        'UPDATE users SET last_login = ? WHERE id = ?',
        [new Date().toISOString(), user.id]
      );
      
      // Generate JWT token
      const token = jwt.sign(
        {
          id: user.id,
          username: user.username,
          role: user.role,
        },
        config.jwt.secret,
        {
          expiresIn: config.jwt.expiresIn,
          issuer: config.jwt.issuer,
        }
      );
      
      // Send response
      res.json({
        success: true,
        data: {
          token,
          user: {
            id: user.id,
            username: user.username,
            role: user.role,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Create a new user account
   */
  async register(req: Request, res: Response, next: NextFunction) {
    try {
      const { username, password, role = 'user' } = req.body;
      
      // Validate admin role
      const user = (req as any).user;
      
      if (role === 'admin' && (!user || user.role !== 'admin')) {
        throw new ApiError('Only admins can create admin accounts', 403, 'FORBIDDEN');
      }
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if username already exists
      const existingUser = await dbService.query(
        'SELECT * FROM users WHERE username = ?',
        [username]
      );
      
      if (existingUser && existingUser.length > 0) {
        throw new ApiError('Username already exists', 409, 'USERNAME_EXISTS');
      }
      
      // Hash password
      const salt = await bcrypt.genSalt(10);
      const hashedPassword = await bcrypt.hash(password, salt);
      
      // Generate user ID
      const id = uuidv4();
      
      // Insert new user
      await dbService.query(
        'INSERT INTO users (id, username, password, role, created_at) VALUES (?, ?, ?, ?, ?)',
        [id, username, hashedPassword, role, new Date().toISOString()]
      );
      
      logger.info('Created new user', { username, role });
      
      // Send response
      res.status(201).json({
        success: true,
        data: {
          id,
          username,
          role,
          createdAt: new Date().toISOString(),
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Change user password
   */
  async changePassword(req: Request, res: Response, next: NextFunction) {
    try {
      const { currentPassword, newPassword } = req.body;
      const userId = (req as any).user.id;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Get user
      const users = await dbService.query(
        'SELECT * FROM users WHERE id = ?',
        [userId]
      );
      
      if (!users || users.length === 0) {
        throw new ApiError('User not found', 404, 'USER_NOT_FOUND');
      }
      
      const user = users[0];
      
      // Verify current password
      const isValid = await bcrypt.compare(currentPassword, user.password);
      
      if (!isValid) {
        throw new ApiError('Current password is incorrect', 401, 'INVALID_CURRENT_PASSWORD');
      }
      
      // Hash new password
      const salt = await bcrypt.genSalt(10);
      const hashedPassword = await bcrypt.hash(newPassword, salt);
      
      // Update password
      await dbService.query(
        'UPDATE users SET password = ? WHERE id = ?',
        [hashedPassword, userId]
      );
      
      logger.info('Changed user password', { userId });
      
      // Send response
      res.json({
        success: true,
        data: {
          message: 'Password changed successfully',
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get current user info
   */
  async getCurrentUser(req: Request, res: Response, next: NextFunction) {
    try {
      const user = (req as any).user;
      
      // Send response
      res.json({
        success: true,
        data: {
          id: user.id,
          username: user.username,
          role: user.role,
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Generate API key for user
   */
  async generateApiKey(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = (req as any).user.id;
      
      // Generate API key
      const apiKey = Buffer.from(uuidv4() + uuidv4()).toString('base64');
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if API keys table exists, if not create it
      const tableExists = await dbService.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='api_keys'"
      );
      
      if (!tableExists || tableExists.length === 0) {
        await dbService.query(`
          CREATE TABLE IF NOT EXISTS api_keys (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            key TEXT NOT NULL,
            description TEXT,
            created_at TEXT NOT NULL,
            last_used TEXT,
            FOREIGN KEY (user_id) REFERENCES users (id)
          )
        `);
      }
      
      // Insert new API key
      const id = uuidv4();
      const description = req.body.description || 'API key';
      
      await dbService.query(
        'INSERT INTO api_keys (id, user_id, key, description, created_at) VALUES (?, ?, ?, ?, ?)',
        [id, userId, apiKey, description, new Date().toISOString()]
      );
      
      logger.info('Generated new API key', { userId, keyId: id });
      
      // Send response
      res.status(201).json({
        success: true,
        data: {
          id,
          apiKey,
          description,
          createdAt: new Date().toISOString(),
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * List API keys for user
   */
  async listApiKeys(req: Request, res: Response, next: NextFunction) {
    try {
      const userId = (req as any).user.id;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if API keys table exists
      const tableExists = await dbService.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='api_keys'"
      );
      
      if (!tableExists || tableExists.length === 0) {
        return res.json({
          success: true,
          data: [],
        });
      }
      
      // Get API keys
      const keys = await dbService.query(
        'SELECT id, description, created_at, last_used FROM api_keys WHERE user_id = ?',
        [userId]
      );
      
      // Send response
      res.json({
        success: true,
        data: keys,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Delete API key
   */
  async deleteApiKey(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const userId = (req as any).user.id;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if API key exists and belongs to user
      const keys = await dbService.query(
        'SELECT * FROM api_keys WHERE id = ? AND user_id = ?',
        [id, userId]
      );
      
      if (!keys || keys.length === 0) {
        throw new ApiError('API key not found', 404, 'API_KEY_NOT_FOUND');
      }
      
      // Delete API key
      await dbService.query(
        'DELETE FROM api_keys WHERE id = ?',
        [id]
      );
      
      logger.info('Deleted API key', { userId, keyId: id });
      
      // Send response
      res.json({
        success: true,
        data: {
          message: `API key ${id} deleted successfully`,
        },
      });
    } catch (error) {
      next(error);
    }
  },
};

export default authController;