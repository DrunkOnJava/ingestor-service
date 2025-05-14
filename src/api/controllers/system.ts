/**
 * System Controller
 * 
 * Handles system-level operations such as status monitoring,
 * configuration management, and statistics reporting.
 */

import { Request, Response, NextFunction } from 'express';
import os from 'os';
import { Logger } from '../../core/logging/Logger';
import { SystemMonitor } from '../../core/services/SystemMonitor';
import { DatabaseService } from '../../core/database/DatabaseService';
import { ContentRepository } from '../../core/content/ContentRepository';
import { EntityRepository } from '../../core/entity/EntityRepository';
import { getWebSocketManager } from '../websocket';
import { version, claudeVersion } from '../../constants';
import config from '../config';

// Initialize logger
const logger = new Logger('api:controller:system');

// Helper function to calculate date range for statistics
const getTimeframeForPeriod = (period: string) => {
  const now = new Date();
  const end = new Date(now);
  let start: Date;
  
  switch (period) {
    case 'day':
      start = new Date(now);
      start.setDate(start.getDate() - 1);
      break;
    case 'month':
      start = new Date(now);
      start.setMonth(start.getMonth() - 1);
      break;
    case 'year':
      start = new Date(now);
      start.setFullYear(start.getFullYear() - 1);
      break;
    case 'week':
    default:
      start = new Date(now);
      start.setDate(start.getDate() - 7);
      break;
  }
  
  return { start, end, period };
};

/**
 * System controller methods
 */
export const systemController = {
  /**
   * Get system status information
   */
  async getSystemStatus(req: Request, res: Response, next: NextFunction) {
    try {
      // Get system monitor instance
      const systemMonitor = new SystemMonitor();
      
      // Get system resources
      const cpuUsage = await systemMonitor.getCpuUsage();
      const memoryUsage = await systemMonitor.getMemoryUsage();
      const storageUsage = await systemMonitor.getStorageUsage();
      const servicesStatus = await systemMonitor.getServicesStatus();
      
      // Format response
      const statusResponse = {
        status: 'healthy', // Default to healthy, will be overridden if issues found
        uptime: process.uptime(),
        version,
        resources: {
          cpu: {
            usage: cpuUsage.percentage,
            cores: os.cpus().length,
          },
          memory: {
            total: memoryUsage.totalBytes,
            used: memoryUsage.usedBytes,
            percentage: memoryUsage.percentage,
          },
          storage: {
            total: storageUsage.totalBytes,
            used: storageUsage.usedBytes,
            percentage: storageUsage.percentage,
          },
        },
        services: servicesStatus,
      };
      
      // Determine overall status based on services and resources
      const degradedServices = servicesStatus.filter(s => s.status === 'degraded').length;
      const downServices = servicesStatus.filter(s => s.status === 'down').length;
      
      if (downServices > 0) {
        statusResponse.status = 'degraded';
      }
      
      if (downServices > 1 || (downServices === 1 && degradedServices > 0)) {
        statusResponse.status = 'maintenance';
      }
      
      // Return status response
      res.json({
        success: true,
        data: statusResponse,
      });
      
      // Log system check
      logger.info('System status check', {
        status: statusResponse.status,
        cpuUsage: cpuUsage.percentage.toFixed(1) + '%',
        memoryUsage: memoryUsage.percentage.toFixed(1) + '%',
        storageUsage: storageUsage.percentage.toFixed(1) + '%',
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get system information
   */
  async getSystemInfo(req: Request, res: Response, next: NextFunction) {
    try {
      // Get database information
      const db = new DatabaseService();
      
      // Get content repository for supported types
      const contentRepo = new ContentRepository();
      const supportedFormats = await contentRepo.getSupportedFormats();
      
      // Prepare system information
      const systemInfo = {
        name: 'Ingestor System',
        version,
        description: 'Document processing system with entity extraction capabilities',
        buildDate: config.buildDate || new Date().toISOString(),
        claudeVersion,
        features: [
          'text-extraction',
          'image-analysis',
          'code-analysis',
          'pdf-processing',
          'document-chunking',
          'entity-extraction',
          'batch-processing',
        ],
        maxUploadSize: config.content.maxSize,
        supportedFormats,
      };
      
      // Return system information
      res.json({
        success: true,
        data: systemInfo,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get system configuration
   */
  async getSystemConfig(req: Request, res: Response, next: NextFunction) {
    try {
      // Prepare safe configuration (excluding secrets)
      const safeConfig = {
        processing: {
          defaultChunkSize: config.content.chunkSize,
          defaultChunkOverlap: config.content.chunkOverlap,
          defaultChunkStrategy: 'size',
          maxConcurrentProcesses: config.batch.maxConcurrentProcesses,
          processingTimeout: config.batch.processingTimeout,
        },
        extraction: {
          defaultMinConfidence: 0.5,
          entityTypes: [
            'person',
            'organization',
            'location',
            'date',
            'concept',
            'technology',
            'event',
          ],
          relationshipTypes: [
            'worksFor',
            'createdBy',
            'locatedIn',
            'partOf',
            'references',
            'uses',
          ],
        },
        batch: {
          maxBatchSize: config.batch.maxBatchSize,
          maxConcurrentItems: config.batch.maxConcurrentProcesses,
          batchTimeout: config.batch.processingTimeout,
        },
        api: {
          rateLimits: {
            defaultPerMinute: config.rateLimits.defaultPerMinute,
            uploadPerMinute: config.rateLimits.uploadPerMinute,
            batchPerHour: 5,
          },
        },
        storage: {
          contentRetentionDays: config.content.retentionDays,
          maxContentSize: config.content.maxSize,
        },
      };
      
      // Return safe configuration
      res.json({
        success: true,
        data: safeConfig,
      });
    } catch (error) {
      next(error);
    }
  },
  
  /**
   * Get system statistics
   */
  async getSystemStatistics(req: Request, res: Response, next: NextFunction) {
    try {
      // Get period from query (default to week)
      const period = (req.query.period as string) || 'week';
      const timeframe = getTimeframeForPeriod(period);
      
      // Get repositories
      const contentRepo = new ContentRepository();
      const entityRepo = new EntityRepository();
      
      // Get content statistics
      const contentStats = await contentRepo.getStatistics(timeframe.start, timeframe.end);
      
      // Get entity statistics
      const entityStats = await entityRepo.getStatistics(timeframe.start, timeframe.end);
      
      // Get processing statistics
      const processingStats = await contentRepo.getProcessingStatistics(timeframe.start, timeframe.end);
      
      // Format response
      const statistics = {
        timeframe: {
          start: timeframe.start.toISOString(),
          end: timeframe.end.toISOString(),
          period: timeframe.period,
        },
        content: contentStats,
        entities: entityStats,
        processing: processingStats,
      };
      
      // Return statistics
      res.json({
        success: true,
        data: statistics,
      });
    } catch (error) {
      next(error);
    }
  },
};