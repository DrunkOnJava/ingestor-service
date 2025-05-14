/**
 * Content processor for handling different content types
 */

import { Logger } from '../logging';
import { FileSystem } from '../utils';
import { ClaudeService } from '../services';
import { EntityManager } from '../entity';

/**
 * Chunk options for processing large content
 */
export interface ChunkOptions {
  /** Maximum size in bytes of each chunk */
  maxChunkSize?: number;
  /** Overlap between chunks in bytes */
  chunkOverlap?: number;
  /** Strategy for chunking (line, character, token, etc.) */
  chunkStrategy?: 'line' | 'character' | 'token' | 'paragraph';
}

/**
 * Result of content processing
 */
export interface ContentProcessingResult {
  /** ID of the processed content */
  contentId: number;
  /** Type of the content (MIME type) */
  contentType: string;
  /** Number of chunks the content was split into (1 if not chunked) */
  chunks: number;
  /** Whether processing was successful */
  success: boolean;
  /** Any error message if processing failed */
  error?: string;
  /** Extracted metadata */
  metadata?: Record<string, any>;
  /** Entity IDs extracted from content */
  entityIds?: number[];
}

/**
 * Content processor for the ingestor system
 */
export class ContentProcessor {
  private logger: Logger;
  private fs: FileSystem;
  private claudeService?: ClaudeService;
  private entityManager?: EntityManager;
  
  /**
   * Creates a new ContentProcessor instance
   * @param logger Logger instance
   * @param fs File system utility
   * @param claudeService Optional Claude service for content analysis
   * @param entityManager Optional Entity manager for entity extraction
   */
  constructor(
    logger: Logger,
    fs: FileSystem,
    claudeService?: ClaudeService,
    entityManager?: EntityManager
  ) {
    this.logger = logger;
    this.fs = fs;
    this.claudeService = claudeService;
    this.entityManager = entityManager;
  }
  
  /**
   * Process content
   * @param content Content to process (can be text or file path)
   * @param contentType MIME type of the content
   * @param chunkOptions Options for chunking large content
   * @returns Processing result
   */
  public async processContent(
    content: string,
    contentType: string,
    chunkOptions?: ChunkOptions
  ): Promise<ContentProcessingResult> {
    this.logger.info(`Processing content of type: ${contentType}`);
    
    try {
      // Determine if content is a file or raw text
      let contentText = content;
      let isFile = false;
      
      if (await this.fs.isFile(content)) {
        isFile = true;
        this.logger.debug(`Content is a file: ${content}`);
        
        // For text-based content types, read the file
        if (this.isTextContentType(contentType)) {
          contentText = await this.fs.readFile(content);
        }
        
        // If content type is not specified or is octet-stream, try to detect it
        if (contentType === 'application/octet-stream' || !contentType) {
          contentType = await this.fs.getMimeType(content);
          this.logger.debug(`Detected content type: ${contentType}`);
        }
      }
      
      // Check if content needs to be chunked
      let contentChunks: string[] = [];
      if (this.isTextContentType(contentType) && this.shouldChunk(contentText, chunkOptions)) {
        this.logger.debug('Content needs to be chunked');
        contentChunks = this.chunkContent(contentText, chunkOptions);
      } else {
        // Single chunk
        contentChunks = [contentText];
      }
      
      this.logger.debug(`Content split into ${contentChunks.length} chunks`);
      
      // Process each chunk and extract entities if entity manager is available
      const entityIds: number[] = [];
      
      if (this.entityManager) {
        for (let i = 0; i < contentChunks.length; i++) {
          const chunk = contentChunks[i];
          this.logger.debug(`Processing chunk ${i + 1}/${contentChunks.length}`);
          
          // Extract entities from this chunk
          const result = await this.entityManager.extractEntities(chunk, contentType);
          
          if (result.success && result.entities && result.entities.length > 0) {
            // In a real implementation, we would store these entities in the database
            // For demonstration, we'll just return a placeholder ID
            entityIds.push(...result.entities.map((_: any, index: number) => 1000 + index));
          }
        }
      }
      
      // In a real implementation, we would store the content in the database
      // For demonstration, we'll just return a simulated result
      return {
        contentId: Math.floor(Math.random() * 1000), // Simulated content ID
        contentType,
        chunks: contentChunks.length,
        success: true,
        entityIds,
        metadata: {
          isFile,
          fileName: isFile ? content : undefined,
          size: contentText.length,
          processedAt: new Date().toISOString()
        }
      };
    } catch (error) {
      this.logger.error(`Content processing failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {
        contentId: -1,
        contentType,
        chunks: 0,
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      };
    }
  }
  
  /**
   * Check if content is of a text-based MIME type
   * @param contentType MIME type to check
   * @returns True if content type is text-based
   * @private
   */
  private isTextContentType(contentType: string): boolean {
    return contentType.startsWith('text/') ||
           contentType === 'application/json' ||
           contentType === 'application/xml' ||
           contentType === 'application/javascript';
  }
  
  /**
   * Check if content should be chunked
   * @param content Content to check
   * @param options Chunk options
   * @returns True if content should be chunked
   * @private
   */
  private shouldChunk(content: string, options?: ChunkOptions): boolean {
    // Default max chunk size is 4MB (roughly 1 million tokens)
    const maxChunkSize = options?.maxChunkSize || 4 * 1024 * 1024;
    
    // If content is larger than max chunk size, it should be chunked
    return content.length > maxChunkSize;
  }
  
  /**
   * Split content into chunks
   * @param content Content to chunk
   * @param options Chunk options
   * @returns Array of content chunks
   * @private
   */
  private chunkContent(content: string, options?: ChunkOptions): string[] {
    // Default max chunk size is 4MB
    const maxChunkSize = options?.maxChunkSize || 4 * 1024 * 1024;
    // Default overlap is 10% of max chunk size
    const chunkOverlap = options?.chunkOverlap || Math.floor(maxChunkSize * 0.1);
    // Default strategy is paragraph
    const strategy = options?.chunkStrategy || 'paragraph';
    
    this.logger.debug(`Chunking content with strategy: ${strategy}, maxSize: ${maxChunkSize}, overlap: ${chunkOverlap}`);
    
    // Split content according to strategy
    switch (strategy) {
      case 'paragraph':
        return this.chunkByParagraph(content, maxChunkSize, chunkOverlap);
      case 'line':
        return this.chunkByLine(content, maxChunkSize, chunkOverlap);
      case 'token':
        return this.chunkByToken(content, maxChunkSize, chunkOverlap);
      case 'character':
      default:
        return this.chunkByCharacter(content, maxChunkSize, chunkOverlap);
    }
  }
  
  /**
   * Chunk content by paragraph
   * @param content Content to chunk
   * @param maxChunkSize Maximum chunk size
   * @param chunkOverlap Overlap between chunks
   * @returns Array of chunks
   * @private
   */
  private chunkByParagraph(content: string, maxChunkSize: number, chunkOverlap: number): string[] {
    // Split by double newline (paragraph boundary)
    const paragraphs = content.split(/\n\s*\n/);
    return this.createChunksFromSegments(paragraphs, maxChunkSize, chunkOverlap);
  }
  
  /**
   * Chunk content by line
   * @param content Content to chunk
   * @param maxChunkSize Maximum chunk size
   * @param chunkOverlap Overlap between chunks
   * @returns Array of chunks
   * @private
   */
  private chunkByLine(content: string, maxChunkSize: number, chunkOverlap: number): string[] {
    // Split by newline
    const lines = content.split(/\n/);
    return this.createChunksFromSegments(lines, maxChunkSize, chunkOverlap);
  }
  
  /**
   * Chunk content by character
   * @param content Content to chunk
   * @param maxChunkSize Maximum chunk size
   * @param chunkOverlap Overlap between chunks
   * @returns Array of chunks
   * @private
   */
  private chunkByCharacter(content: string, maxChunkSize: number, chunkOverlap: number): string[] {
    const chunks: string[] = [];
    
    let position = 0;
    while (position < content.length) {
      const end = Math.min(position + maxChunkSize, content.length);
      chunks.push(content.substring(position, end));
      position = end - chunkOverlap;
      
      // Make sure we advance if overlap would prevent progress
      if (position <= 0 || position >= content.length - 1) {
        break;
      }
    }
    
    return chunks;
  }
  
  /**
   * Chunk content by approximate token count
   * @param content Content to chunk
   * @param maxChunkSize Maximum chunk size
   * @param chunkOverlap Overlap between chunks
   * @returns Array of chunks
   * @private
   */
  private chunkByToken(content: string, maxChunkSize: number, chunkOverlap: number): string[] {
    // This is a very approximate token counting method
    // In a real implementation, you would use a proper tokenizer
    // For now, we'll just split by whitespace and punctuation
    const tokens = content.split(/\s+|[.,;!?]/);
    return this.createChunksFromSegments(tokens, maxChunkSize, chunkOverlap);
  }
  
  /**
   * Create chunks from text segments
   * @param segments Text segments (paragraphs, lines, tokens, etc.)
   * @param maxChunkSize Maximum chunk size
   * @param chunkOverlap Overlap between chunks
   * @returns Array of chunks
   * @private
   */
  private createChunksFromSegments(segments: string[], maxChunkSize: number, chunkOverlap: number): string[] {
    const chunks: string[] = [];
    let currentChunk = '';
    let currentSize = 0;
    
    for (const segment of segments) {
      // If adding this segment would exceed the max size, start a new chunk
      if (currentSize + segment.length > maxChunkSize && currentChunk) {
        chunks.push(currentChunk);
        
        // Start new chunk with overlap
        const overlapSize = Math.min(chunkOverlap, currentSize);
        if (overlapSize > 0) {
          currentChunk = currentChunk.substring(currentChunk.length - overlapSize);
          currentSize = overlapSize;
        } else {
          currentChunk = '';
          currentSize = 0;
        }
      }
      
      // Add segment to current chunk
      if (currentChunk) {
        // Add a separator based on the segment type (space for tokens, newline for paragraphs)
        currentChunk += segments === segments.filter(s => s.includes(' ')) ? '\n\n' : ' ';
        currentSize += 1;
      }
      
      currentChunk += segment;
      currentSize += segment.length;
    }
    
    // Add the last chunk if it's not empty
    if (currentChunk) {
      chunks.push(currentChunk);
    }
    
    return chunks;
  }
}