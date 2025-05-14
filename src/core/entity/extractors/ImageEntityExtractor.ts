/**
 * Image entity extractor implementation
 * Specialized for extracting entities from image content using Claude's multimodal capabilities
 */

import { EntityExtractor } from '../EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityType } from '../types/EntityTypes';
import { ClaudeService } from '../../services/ClaudeService';
import { Logger } from '../../logging';
import { FileSystem } from '../../utils/FileSystem';
import * as fs from 'fs/promises';
import * as path from 'path';
import { promisify } from 'util';
import { exec } from 'child_process';

const execPromise = promisify(exec);

/**
 * Supported image file extensions
 */
const SUPPORTED_IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

/**
 * Entity extractor specialized for image content
 * Uses Claude's multimodal capabilities to analyze image content
 */
export class ImageEntityExtractor extends EntityExtractor {
  private claudeService?: ClaudeService;
  private fs: FileSystem;
  
  /**
   * Creates a new ImageEntityExtractor
   * @param logger Logger instance for extraction logging
   * @param options Default options for entity extraction
   * @param claudeService Claude service for AI-powered extraction (required for image analysis)
   * @param fs FileSystem service for file operations
   */
  constructor(
    logger: Logger, 
    options: EntityExtractionOptions = {},
    claudeService?: ClaudeService,
    fs: FileSystem = new FileSystem(logger)
  ) {
    super(logger, options);
    this.claudeService = claudeService;
    this.fs = fs;
  }
  
  /**
   * Extract entities from image content
   * @param content The image file path or image content as base64
   * @param contentType MIME type (image/jpeg, image/png, etc.)
   * @param options Options to customize extraction behavior
   */
  public async extract(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    const startTime = Date.now();
    this.logger.debug(`Extracting entities from image content (${contentType})`);
    
    // Validate content type
    if (!contentType.includes('image/') && !contentType.includes('application/octet-stream')) {
      return {
        entities: [],
        success: false,
        error: `Invalid content type for image extraction: ${contentType}`
      };
    }
    
    // Check if Claude service is available (required for image analysis)
    if (!this.claudeService) {
      return {
        entities: [],
        success: false,
        error: 'Claude service is required for image entity extraction but not provided'
      };
    }
    
    try {
      let imageBuffer: Buffer;
      
      // Determine if content is a file path or content data
      if (await this.fs.isFile(content)) {
        // Validate file extension
        const fileExt = path.extname(content).toLowerCase();
        if (!SUPPORTED_IMAGE_EXTENSIONS.includes(fileExt)) {
          return {
            entities: [],
            success: false,
            error: `Unsupported image file type: ${fileExt}`
          };
        }
        
        // Extract from file
        imageBuffer = await this.extractFromFile(content);
      } else if (content.startsWith('data:image/') && content.includes('base64,')) {
        // Extract base64 data
        const base64Data = content.split(',')[1];
        imageBuffer = Buffer.from(base64Data, 'base64');
      } else {
        return {
          entities: [],
          success: false,
          error: 'Invalid image content format'
        };
      }
      
      // Extract entities using Claude
      const entities = await this.extractWithClaude(imageBuffer, contentType, options);
      
      // Filter entities based on options
      const filteredEntities = this.filterEntities(entities, options);
      
      // Create result with stats
      const result: EntityExtractionResult = {
        entities: filteredEntities,
        success: true,
        stats: {
          processingTimeMs: Date.now() - startTime,
          entityCount: filteredEntities.length
        }
      };
      
      this.logger.debug(`Extracted ${result.stats?.entityCount} entities from image in ${result.stats?.processingTimeMs}ms`);
      return result;
    } catch (error) {
      this.logger.error(`Image entity extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {
        entities: [],
        success: false,
        error: `Image extraction error: ${error instanceof Error ? error.message : 'Unknown error'}`
      };
    }
  }
  
  /**
   * Extract image content from a file
   * @param filePath Path to the image file
   * @returns Image data as buffer
   * @private
   */
  private async extractFromFile(filePath: string): Promise<Buffer> {
    try {
      this.logger.debug(`Reading image file: ${filePath}`);
      return await fs.readFile(filePath);
    } catch (error) {
      this.logger.error(`Failed to read image file: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Extract image content from a buffer
   * @param buffer Image content as buffer
   * @returns Image data as buffer
   * @private
   */
  private async extractFromBuffer(buffer: Buffer): Promise<Buffer> {
    // Just return the buffer as is, we already have the image data
    return buffer;
  }
  
  /**
   * Extract entities from an image using Claude
   * @param imageBuffer Image data as buffer
   * @param contentType MIME type of the image
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithClaude(
    imageBuffer: Buffer,
    contentType: string,
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    if (!this.claudeService) {
      return [];
    }
    
    try {
      this.logger.debug('Using Claude for image entity extraction');
      
      // Convert image buffer to base64 for Claude API
      const base64Image = imageBuffer.toString('base64');
      const imageBase64Uri = `data:${contentType};base64,${base64Image}`;
      
      // Call Claude with appropriate prompt for image analysis
      const claudeResponse = await this.claudeService.analyze(imageBase64Uri, 'image', {
        contentType: contentType,
        entityTypes: options?.entityTypes?.join(','),
        ...options
      });
      
      // Extract entities from Claude's response
      if (claudeResponse && claudeResponse.entities && Array.isArray(claudeResponse.entities)) {
        return claudeResponse.entities as Entity[];
      }
      
      this.logger.warning('Claude response did not contain valid entities array');
      return [];
    } catch (error) {
      this.logger.error(`Error extracting entities from image with Claude: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Get image metadata (dimension, format, etc.)
   * @param filePath Path to the image file
   * @returns Object with image metadata
   */
  public async getImageMetadata(filePath: string): Promise<Record<string, any>> {
    try {
      // Use imagemagick's identify command to get image metadata
      let metadata: Record<string, any> = {};
      
      try {
        const { stdout } = await execPromise(`identify -format "%w×%h %m %z-bit %r" "${filePath}"`);
        const [dimensions, format, depth, colorspace] = stdout.trim().split(' ');
        const [width, height] = dimensions.split('×');
        
        metadata = {
          width: parseInt(width, 10),
          height: parseInt(height, 10),
          format,
          depth,
          colorspace
        };
      } catch (error) {
        this.logger.warning(`Failed to get image metadata using ImageMagick: ${error instanceof Error ? error.message : 'Unknown error'}`);
        // Basic metadata from file stats
        const stats = await fs.stat(filePath);
        metadata = {
          size: stats.size,
          format: path.extname(filePath).replace('.', '').toUpperCase()
        };
      }
      
      return metadata;
    } catch (error) {
      this.logger.error(`Failed to get image metadata: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {};
    }
  }
  
  /**
   * Check if a file is a supported image
   * @param filePath Path to the file
   * @returns True if the file is a supported image, false otherwise
   */
  public async isSupportedImage(filePath: string): Promise<boolean> {
    try {
      // Check file extension
      const fileExtension = path.extname(filePath).toLowerCase();
      if (!SUPPORTED_IMAGE_EXTENSIONS.includes(fileExtension)) {
        return false;
      }
      
      // Verify it's actually an image file using the file command
      const mimeType = await this.fs.getMimeType(filePath);
      return mimeType.startsWith('image/');
    } catch (error) {
      this.logger.error(`Failed to check if file is a supported image: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
}