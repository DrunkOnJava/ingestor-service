/**
 * PDF entity extractor implementation
 * Specialized for extracting entities from PDF document content
 */

import { EntityExtractor } from '../EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityType } from '../types/EntityTypes';
import { ClaudeService } from '../../services/ClaudeService';
import { Logger } from '../../logging';
import { FileSystem } from '../../utils/FileSystem';
import * as fs from 'fs/promises';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

/**
 * Entity extractor specialized for PDF content
 * Note: This implementation requires the pdfjs-dist package
 * npm install pdfjs-dist
 */
export class PdfEntityExtractor extends EntityExtractor {
  private claudeService?: ClaudeService;
  private fs: FileSystem;
  
  /**
   * Creates a new PdfEntityExtractor
   * @param logger Logger instance for extraction logging
   * @param options Default options for entity extraction
   * @param claudeService Optional Claude service for AI-powered extraction
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
   * Extract entities from PDF content
   * @param content The PDF file path or PDF content as base64
   * @param contentType MIME type (application/pdf)
   * @param options Options to customize extraction behavior
   */
  public async extract(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    const startTime = Date.now();
    this.logger.debug(`Extracting entities from PDF content (${contentType})`);
    
    // Validate content type
    if (!contentType.includes('pdf') && !contentType.includes('application/octet-stream')) {
      return {
        entities: [],
        success: false,
        error: `Invalid content type for PDF extraction: ${contentType}`
      };
    }
    
    try {
      // Determine if content is a file path or content data
      let textContent: string;
      if (await this.fs.isFile(content)) {
        textContent = await this.extractFromFile(content);
      } else if (content.startsWith('data:application/pdf;base64,')) {
        // Extract base64 data
        const base64Data = content.split(',')[1];
        textContent = await this.extractFromBuffer(Buffer.from(base64Data, 'base64'));
      } else {
        return {
          entities: [],
          success: false,
          error: 'Invalid PDF content format'
        };
      }
      
      // If text is empty, return empty result
      if (!textContent || textContent.trim().length === 0) {
        return {
          entities: [],
          success: false,
          error: 'Empty or unreadable PDF content'
        };
      }
      
      let entities: Entity[] = [];
      
      // Try to use Claude service if available
      if (this.claudeService) {
        try {
          this.logger.debug('Using Claude for PDF entity extraction');
          entities = await this.extractWithClaude(textContent, options);
        } catch (error) {
          this.logger.warning(`Claude PDF extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
          this.logger.debug('Falling back to rule-based extraction');
        }
      }
      
      // If Claude service failed or is unavailable, use rule-based extraction
      if (entities.length === 0) {
        this.logger.debug('Using rule-based entity extraction for PDF');
        entities = await this.extractWithRules(textContent);
      }
      
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
      
      this.logger.debug(`Extracted ${result.stats?.entityCount} entities from PDF in ${result.stats?.processingTimeMs}ms`);
      return result;
    } catch (error) {
      this.logger.error(`PDF entity extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {
        entities: [],
        success: false,
        error: `PDF extraction error: ${error instanceof Error ? error.message : 'Unknown error'}`
      };
    }
  }
  
  /**
   * Extract text content from a PDF file
   * @param filePath Path to the PDF file
   * @returns Extracted text content
   * @private
   */
  private async extractFromFile(filePath: string): Promise<string> {
    try {
      this.logger.debug(`Extracting text from PDF file: ${filePath}`);
      
      // Check if pdftotext from poppler-utils is available
      try {
        await execPromise('which pdftotext');
        // Use pdftotext (from poppler-utils) if available
        const { stdout } = await execPromise(`pdftotext -layout -enc UTF-8 "${filePath}" -`);
        return stdout;
      } catch (error) {
        this.logger.warning('pdftotext not available, falling back to PDF.js extraction');
        
        // Fallback to using PDF.js (this would actually be imported at the top)
        // For demonstration purposes, this is pseudocode
        /*
        const pdfData = await fs.readFile(filePath);
        return this.extractFromBuffer(pdfData);
        */
        
        // Since we don't have PDF.js implementation here, throw error for now
        throw new Error('PDF text extraction requires pdftotext utility or PDF.js library');
      }
    } catch (error) {
      this.logger.error(`Failed to extract text from PDF file: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Extract text content from a PDF buffer
   * @param buffer PDF content as buffer
   * @returns Extracted text content
   * @private
   */
  private async extractFromBuffer(buffer: Buffer): Promise<string> {
    try {
      this.logger.debug('Extracting text from PDF buffer');
      
      // Write buffer to a temporary file
      const tempDir = '/tmp/ingestor-temp';
      await fs.mkdir(tempDir, { recursive: true });
      const tempFile = path.join(tempDir, `pdf-${Date.now()}.pdf`);
      await fs.writeFile(tempFile, buffer);
      
      // Extract text from the temporary file
      const text = await this.extractFromFile(tempFile);
      
      // Clean up
      await fs.unlink(tempFile).catch(err => 
        this.logger.warning(`Failed to remove temp PDF file: ${err.message}`)
      );
      
      return text;
    } catch (error) {
      this.logger.error(`Failed to extract text from PDF buffer: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Extract entities using Claude AI
   * @param text Extracted PDF text content
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithClaude(
    text: string, 
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    if (!this.claudeService) {
      return [];
    }
    
    try {
      // Use the PDF-specific prompt template
      const claudeResponse = await this.claudeService.analyze(text, 'pdf', {
        contentType: 'application/pdf',
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
      this.logger.error(`Error extracting entities from PDF with Claude: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Extract entities using rule-based approach
   * @param text Extracted PDF text content
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithRules(text: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep/sed
    const tempFile = await this.fs.createTempFile(text);
    
    try {
      // Extract person entities
      try {
        // Match potential full names
        const personMatches = await this.fs.grep(tempFile, '\\b[A-Z][a-z]+ ([A-Z]\\.? )?[A-Z][a-z]+\\b');
        // Match titles (Mr., Dr., etc.) followed by names
        const titledPersonMatches = await this.fs.grep(tempFile, '\\b(Mr\\.|Mrs\\.|Ms\\.|Dr\\.|Prof\\.) [A-Z][a-z]+ ([A-Z][a-z]+)?\\b');
        
        // Combine and deduplicate
        const persons = Array.from(new Set([...personMatches, ...titledPersonMatches]));
        
        for (const person of persons) {
          if (person.trim()) {
            // Get context (text surrounding the entity)
            const context = await this.fs.grepContext(tempFile, person, 50);
            // Get position (line number)
            const position = await this.fs.grepLineNumber(tempFile, person);
            
            entities.push({
              name: this.normalizeEntityName(person, EntityType.PERSON),
              type: EntityType.PERSON,
              mentions: [{
                context: context || person,
                position: position,
                relevance: 0.75
              }]
            });
          }
        }
      } catch (error) {
        this.logger.warning(`Error extracting person entities from PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
      
      // Extract organization entities
      try {
        // Match common organization patterns in PDFs
        const orgMatches = await this.fs.grep(tempFile, '\\b[A-Z][A-Za-z0-9]* (Inc\\.|Corp\\.|Ltd\\.|LLC|Company|Association|Foundation|University|Technologies|Group|Institute|Agency|Department)\\b');
        // Match capitalized multi-word names that could be organizations
        const capitalizedOrgMatches = await this.fs.grep(tempFile, '\\b([A-Z][a-z]+ ){1,3}(Inc\\.|Corp\\.|Ltd\\.|LLC|Company|Association|Foundation|University|Technologies|Group|Institute|Agency|Department)\\b');
        // Match common abbreviations (all caps) that could be organizations
        const abbrOrgMatches = await this.fs.grep(tempFile, '\\b[A-Z]{2,}\\b');
        
        // Combine and deduplicate
        const organizations = Array.from(new Set([...orgMatches, ...capitalizedOrgMatches, ...abbrOrgMatches]));
        
        for (const org of organizations) {
          if (org.trim() && org.length > 1) {
            // Get context
            const context = await this.fs.grepContext(tempFile, org, 50);
            // Get position
            const position = await this.fs.grepLineNumber(tempFile, org);
            
            entities.push({
              name: this.normalizeEntityName(org, EntityType.ORGANIZATION),
              type: EntityType.ORGANIZATION,
              mentions: [{
                context: context || org,
                position: position,
                relevance: 0.7
              }]
            });
          }
        }
      } catch (error) {
        this.logger.warning(`Error extracting organization entities from PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
      
      // Extract date entities - PDFs often contain dates in headers, footers, metadata
      try {
        // Match various date formats common in PDFs
        const datePattern = '\\b[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}\\b|\\b[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\\b|\\b(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2},? [0-9]{4}\\b|\\b[0-9]{1,2} (January|February|March|April|May|June|July|August|September|October|November|December),? [0-9]{4}\\b';
        const dateMatches = await this.fs.grep(tempFile, datePattern);
        
        for (const date of dateMatches) {
          if (date.trim()) {
            // Get context
            const context = await this.fs.grepContext(tempFile, date, 50);
            // Get position
            const position = await this.fs.grepLineNumber(tempFile, date);
            
            entities.push({
              name: this.normalizeEntityName(date, EntityType.DATE),
              type: EntityType.DATE,
              mentions: [{
                context: context || date,
                position: position,
                relevance: 0.8
              }]
            });
          }
        }
      } catch (error) {
        this.logger.warning(`Error extracting date entities from PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
      
      // Extract location entities
      try {
        // Match locations in PDFs
        const majorLocations = 'United States|Canada|UK|Australia|China|Japan|Russia|Germany|France|Italy|Spain|Brazil|India|Mexico|New York|London|Paris|Tokyo|Berlin|Rome|Moscow|Beijing|Los Angeles|Chicago|Toronto|Sydney|Amsterdam|Dubai';
        const majorLocationMatches = await this.fs.grep(tempFile, `\\b(${majorLocations})\\b`);
        
        // Match common address patterns in PDFs
        const addressPatterns = await this.fs.grep(tempFile, '\\b[0-9]+ [A-Z][a-z]+ (St\\.|Street|Ave\\.|Avenue|Rd\\.|Road|Blvd\\.|Boulevard|Dr\\.|Drive)\\b');
        
        // Combine and deduplicate
        const allLocations = Array.from(new Set([...majorLocationMatches, ...addressPatterns]));
        
        for (const location of allLocations) {
          if (location.trim()) {
            // Get context
            const context = await this.fs.grepContext(tempFile, location, 50);
            // Get position
            const position = await this.fs.grepLineNumber(tempFile, location);
            
            entities.push({
              name: this.normalizeEntityName(location, EntityType.LOCATION),
              type: EntityType.LOCATION,
              mentions: [{
                context: context || location,
                position: position,
                relevance: 0.65
              }]
            });
          }
        }
      } catch (error) {
        this.logger.warning(`Error extracting location entities from PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
      
      // Extract product entities - often found in PDFs
      try {
        // Match product names (often marked with ™, ®, etc.)
        const productMatches = await this.fs.grep(tempFile, '\\b[A-Z][a-zA-Z0-9]+(™|®|©)?\\b');
        
        for (const product of productMatches) {
          if (product.trim() && product.length > 1 && /[a-zA-Z0-9]+[™®©]?$/.test(product)) {
            // Get context
            const context = await this.fs.grepContext(tempFile, product, 50);
            // Get position
            const position = await this.fs.grepLineNumber(tempFile, product);
            
            entities.push({
              name: this.normalizeEntityName(product, EntityType.PRODUCT),
              type: EntityType.PRODUCT,
              mentions: [{
                context: context || product,
                position: position,
                relevance: 0.6
              }]
            });
          }
        }
      } catch (error) {
        this.logger.warning(`Error extracting product entities from PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
      
    } finally {
      // Clean up temporary file
      await this.fs.removeFile(tempFile);
    }
    
    return entities;
  }
}