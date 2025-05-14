/**
 * Content Controller
 * 
 * Handles requests for content operations.
 */

import { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs/promises';
import path from 'path';
import { ContentProcessor } from '../../core/content/ContentProcessor';
import { DatabaseService } from '../../core/services/DatabaseService';
import { EntityManager } from '../../core/entity/EntityManager';
import { Logger } from '../../core/logging/Logger';
import { ApiError } from '../middleware/error-handler';
import config from '../config';
import { getWebSocketManager, EventType } from '../websocket';

const logger = new Logger('api:content-controller');

/**
 * Content Controller implementation
 */
export const contentController = {
  /**
   * List content items with pagination and filtering
   */
  async listContent(req: Request, res: Response, next: NextFunction) {
    try {
      // Extract query parameters
      const limit = parseInt(req.query.limit as string || '20', 10);
      const offset = parseInt(req.query.offset as string || '0', 10);
      const contentType = req.query.type as string;
      const sort = req.query.sort as string || 'createdAt';
      const order = req.query.order as 'asc' | 'desc' || 'desc';
      const query = req.query.q as string;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Build SQL query
      let sql = 'SELECT * FROM content';
      const params: any[] = [];
      
      // Add WHERE conditions
      const conditions: string[] = [];
      
      if (contentType) {
        conditions.push('type = ?');
        params.push(contentType);
      }
      
      if (query) {
        conditions.push('(title LIKE ? OR content LIKE ?)');
        params.push(`%${query}%`, `%${query}%`);
      }
      
      if (conditions.length > 0) {
        sql += ' WHERE ' + conditions.join(' AND ');
      }
      
      // Add ORDER BY
      sql += ` ORDER BY ${sort} ${order === 'asc' ? 'ASC' : 'DESC'}`;
      
      // Add LIMIT and OFFSET
      sql += ' LIMIT ? OFFSET ?';
      params.push(limit, offset);
      
      // Get count for pagination
      const countSql = 'SELECT COUNT(*) as total FROM content' +
        (conditions.length > 0 ? ' WHERE ' + conditions.join(' AND ') : '');
      
      // Execute queries
      const results = await dbService.query(sql, params);
      const countResult = await dbService.query(countSql, params.slice(0, params.length - 2));
      const total = countResult[0]?.total || 0;
      
      // Send response
      res.json({
        success: true,
        data: results,
        meta: {
          pagination: {
            limit,
            offset,
            total,
            next: offset + limit < total ? 
              `/api/v1/content?limit=${limit}&offset=${offset + limit}` : null,
            previous: offset > 0 ? 
              `/api/v1/content?limit=${limit}&offset=${Math.max(0, offset - limit)}` : null,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get a specific content item by ID
   */
  async getContent(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Get content item
      const content = await dbService.query(
        'SELECT * FROM content WHERE id = ?',
        [id]
      );
      
      // Check if content exists
      if (!content || content.length === 0) {
        throw new ApiError(`Content with ID ${id} not found`, 404, 'CONTENT_NOT_FOUND');
      }
      
      // Send response
      res.json({
        success: true,
        data: content[0],
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Create a new content item
   */
  async createContent(req: Request, res: Response, next: NextFunction) {
    try {
      const { content, type, filename, metadata, processingOptions } = req.body;
      
      // Generate ID
      const id = uuidv4();
      
      // Processing ID for tracking
      const processingId = uuidv4();
      
      // Create metadata
      const contentMetadata = {
        ...(metadata || {}),
        contentLength: content.length,
        mimeType: type === 'text' ? 'text/plain' : `${type}/unknown`,
      };
      
      // Save content to database first
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Insert into database
      await dbService.query(
        'INSERT INTO content (id, type, filename, status, metadata, processing_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, type, filename, 'processing', JSON.stringify(contentMetadata), processingId, new Date().toISOString()]
      );
      
      // Initialize content processor
      const processor = new ContentProcessor();
      
      // Get WebSocket manager for real-time updates
      const wsManager = getWebSocketManager();
      
      // Process content asynchronously
      // In a real implementation, this would be handled by a queue
      setTimeout(async () => {
        try {
          // Notify processing started
          if (wsManager) {
            wsManager.broadcast(EventType.PROCESSING_STARTED, {
              id: processingId,
              contentId: id,
              contentType: type,
              filename: filename,
            });
            // Also send to content-specific room
            wsManager.broadcast(EventType.PROCESSING_STARTED, {
              id: processingId,
              contentId: id,
              contentType: type,
              filename: filename,
            }, `content:${id}`);
          }
          
          // Save content to file
          const contentPath = path.join(config.processing.uploadDir, `${id}.${type}`);
          await fs.writeFile(contentPath, content);
          
          // Process content
          const result = await processor.processContent(contentPath, {
            contentType: type,
            extractEntities: processingOptions?.extractEntities !== false,
            enableChunking: processingOptions?.enableChunking !== false,
            chunkSize: processingOptions?.chunkSize || config.processing.defaultChunkSize,
            chunkOverlap: processingOptions?.chunkOverlap || config.processing.defaultChunkOverlap,
          });
          
          // Update database with results
          await dbService.query(
            'UPDATE content SET status = ?, processed_at = ? WHERE id = ?',
            ['completed', new Date().toISOString(), id]
          );
          
          // Store processing results
          await dbService.query(
            'INSERT INTO processing_results (id, content_id, status, results, started_at, completed_at) VALUES (?, ?, ?, ?, ?, ?)',
            [processingId, id, 'completed', JSON.stringify(result), new Date().toISOString(), new Date().toISOString()]
          );
          
          logger.info('Content processing completed', { contentId: id, processingId });
          
          // Notify processing completed via WebSocket
          if (wsManager) {
            wsManager.broadcast(EventType.PROCESSING_COMPLETED, {
              id: processingId,
              contentId: id,
              status: 'completed',
              results: result,
            });
            // Also send to content-specific room
            wsManager.broadcast(EventType.PROCESSING_COMPLETED, {
              id: processingId,
              contentId: id,
              status: 'completed',
              results: result,
            }, `content:${id}`);
            
            // If entities were extracted, notify entity creation
            if (result.entities && result.entities.length > 0) {
              result.entities.forEach((entity: any) => {
                wsManager.broadcast(EventType.ENTITY_CREATED, {
                  id: entity.id,
                  contentId: id,
                  type: entity.type,
                  name: entity.name,
                });
              });
            }
          }
        } catch (error) {
          logger.error('Content processing failed', {
            contentId: id,
            processingId,
            error: (error as Error).message,
          });
          
          // Update database with error
          await dbService.query(
            'UPDATE content SET status = ? WHERE id = ?',
            ['failed', id]
          );
          
          // Store processing error
          const errorData = { message: (error as Error).message };
          
          await dbService.query(
            'INSERT INTO processing_results (id, content_id, status, error, started_at, completed_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              processingId,
              id,
              'failed',
              JSON.stringify(errorData),
              new Date().toISOString(),
              new Date().toISOString(),
            ]
          );
          
          // Notify processing failed via WebSocket
          if (wsManager) {
            wsManager.broadcast(EventType.PROCESSING_FAILED, {
              id: processingId,
              contentId: id,
              status: 'failed',
              error: errorData,
            });
            // Also send to content-specific room
            wsManager.broadcast(EventType.PROCESSING_FAILED, {
              id: processingId,
              contentId: id,
              status: 'failed',
              error: errorData,
            }, `content:${id}`);
          }
        }
      }, 0);
      
      // Send response immediately
      res.status(202).json({
        success: true,
        data: {
          id,
          type,
          filename,
          status: 'processing',
          metadata: contentMetadata,
          processingId,
          createdAt: new Date().toISOString(),
          links: {
            self: `/api/v1/content/${id}`,
            processing: `/api/v1/processing/${processingId}`,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Upload a file as content
   */
  async uploadContent(req: Request, res: Response, next: NextFunction) {
    try {
      // Check if file was uploaded
      if (!req.file) {
        throw new ApiError('No file uploaded', 400, 'NO_FILE_UPLOADED');
      }
      
      const file = req.file;
      
      // Generate ID
      const id = uuidv4();
      
      // Processing ID for tracking
      const processingId = uuidv4();
      
      // Determine content type from mimetype
      const mimeTypeParts = file.mimetype.split('/');
      const type = mimeTypeParts[0];
      
      // Create metadata
      const metadata = {
        filename: file.originalname,
        contentLength: file.size,
        mimeType: file.mimetype,
      };
      
      // Save content to database
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Insert into database
      await dbService.query(
        'INSERT INTO content (id, type, filename, status, metadata, processing_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, type, file.originalname, 'processing', JSON.stringify(metadata), processingId, new Date().toISOString()]
      );
      
      // Initialize content processor
      const processor = new ContentProcessor();
      
      // Process content asynchronously
      // In a real implementation, this would be handled by a queue
      setTimeout(async () => {
        try {
          // Process content
          const result = await processor.processContent(file.path, {
            contentType: type,
            extractEntities: true,
          });
          
          // Update database with results
          await dbService.query(
            'UPDATE content SET status = ?, processed_at = ? WHERE id = ?',
            ['completed', new Date().toISOString(), id]
          );
          
          // Store processing results
          await dbService.query(
            'INSERT INTO processing_results (id, content_id, status, results, started_at, completed_at) VALUES (?, ?, ?, ?, ?, ?)',
            [processingId, id, 'completed', JSON.stringify(result), new Date().toISOString(), new Date().toISOString()]
          );
          
          logger.info('Content processing completed', { contentId: id, processingId });
        } catch (error) {
          logger.error('Content processing failed', {
            contentId: id,
            processingId,
            error: (error as Error).message,
          });
          
          // Update database with error
          await dbService.query(
            'UPDATE content SET status = ? WHERE id = ?',
            ['failed', id]
          );
          
          // Store processing error
          await dbService.query(
            'INSERT INTO processing_results (id, content_id, status, error, started_at, completed_at) VALUES (?, ?, ?, ?, ?, ?)',
            [
              processingId,
              id,
              'failed',
              JSON.stringify({ message: (error as Error).message }),
              new Date().toISOString(),
              new Date().toISOString(),
            ]
          );
        }
      }, 0);
      
      // Send response immediately
      res.status(202).json({
        success: true,
        data: {
          id,
          type,
          filename: file.originalname,
          status: 'processing',
          metadata,
          processingId,
          createdAt: new Date().toISOString(),
          links: {
            self: `/api/v1/content/${id}`,
            processing: `/api/v1/processing/${processingId}`,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Update content item
   */
  async updateContent(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      const { metadata } = req.body;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if content exists
      const content = await dbService.query(
        'SELECT * FROM content WHERE id = ?',
        [id]
      );
      
      if (!content || content.length === 0) {
        throw new ApiError(`Content with ID ${id} not found`, 404, 'CONTENT_NOT_FOUND');
      }
      
      // Update metadata
      const currentMetadata = JSON.parse(content[0].metadata || '{}');
      const updatedMetadata = {
        ...currentMetadata,
        ...metadata,
      };
      
      // Update in database
      await dbService.query(
        'UPDATE content SET metadata = ?, updated_at = ? WHERE id = ?',
        [JSON.stringify(updatedMetadata), new Date().toISOString(), id]
      );
      
      // Get updated content
      const updatedContent = await dbService.query(
        'SELECT * FROM content WHERE id = ?',
        [id]
      );
      
      // Send response
      res.json({
        success: true,
        data: updatedContent[0],
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Delete content item
   */
  async deleteContent(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if content exists
      const content = await dbService.query(
        'SELECT * FROM content WHERE id = ?',
        [id]
      );
      
      if (!content || content.length === 0) {
        throw new ApiError(`Content with ID ${id} not found`, 404, 'CONTENT_NOT_FOUND');
      }
      
      // Delete from database
      await dbService.query('DELETE FROM content WHERE id = ?', [id]);
      
      // Delete related processing results
      await dbService.query('DELETE FROM processing_results WHERE content_id = ?', [id]);
      
      // Delete related entities
      await dbService.query('DELETE FROM content_entities WHERE content_id = ?', [id]);
      
      // Send response
      res.json({
        success: true,
        data: {
          message: `Content with ID ${id} deleted successfully`,
        },
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get entities for a content item
   */
  async getContentEntities(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if content exists
      const content = await dbService.query(
        'SELECT * FROM content WHERE id = ?',
        [id]
      );
      
      if (!content || content.length === 0) {
        throw new ApiError(`Content with ID ${id} not found`, 404, 'CONTENT_NOT_FOUND');
      }
      
      // Get entities
      const entities = await dbService.query(
        `SELECT e.*
         FROM entities e
         JOIN content_entities ce ON e.id = ce.entity_id
         WHERE ce.content_id = ?`,
        [id]
      );
      
      // Send response
      res.json({
        success: true,
        data: entities,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get related content
   */
  async getRelatedContent(req: Request, res: Response, next: NextFunction) {
    try {
      const { id } = req.params;
      
      // Get database service
      const dbService = new DatabaseService(
        path.join(config.database.dir, config.database.defaultDb)
      );
      
      // Check if content exists
      const content = await dbService.query(
        'SELECT * FROM content WHERE id = ?',
        [id]
      );
      
      if (!content || content.length === 0) {
        throw new ApiError(`Content with ID ${id} not found`, 404, 'CONTENT_NOT_FOUND');
      }
      
      // Get entities for this content
      const contentEntities = await dbService.query(
        'SELECT entity_id FROM content_entities WHERE content_id = ?',
        [id]
      );
      
      if (!contentEntities || contentEntities.length === 0) {
        return res.json({
          success: true,
          data: [],
        });
      }
      
      // Extract entity IDs
      const entityIds = contentEntities.map(item => item.entity_id);
      
      // Find other content with the same entities
      const relatedContent = await dbService.query(
        `SELECT c.*, COUNT(ce.entity_id) as matching_entities
         FROM content c
         JOIN content_entities ce ON c.id = ce.content_id
         WHERE ce.entity_id IN (${entityIds.map(() => '?').join(',')})
         AND c.id != ?
         GROUP BY c.id
         ORDER BY matching_entities DESC
         LIMIT 10`,
        [...entityIds, id]
      );
      
      // Send response
      res.json({
        success: true,
        data: relatedContent,
      });
    } catch (error) {
      next(error);
    }
  },
};

export default contentController;