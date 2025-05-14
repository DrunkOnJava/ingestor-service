/**
 * Text entity extractor implementation
 * Specialized for extracting entities from text content
 */

import { EntityExtractor } from '../EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityMention, EntityType } from '../types';
import { ClaudeService } from '../../services/ClaudeService';
import { Logger } from '../../logging';
import { FileSystem } from '../../utils/FileSystem';

/**
 * Entity extractor specialized for text content
 */
export class TextEntityExtractor extends EntityExtractor {
  private claudeService?: ClaudeService;
  private fs: FileSystem;
  
  /**
   * Creates a new TextEntityExtractor
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
   * Extract entities from text content
   * @param content The text content or file path
   * @param contentType MIME type (text/plain, text/markdown, etc.)
   * @param options Options to customize extraction behavior
   */
  public async extract(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    const startTime = Date.now();
    this.logger.debug(`Extracting entities from text content (${contentType})`);
    
    // Determine if content is a file path or raw text
    let textContent = content;
    if (await this.fs.isFile(content)) {
      textContent = await this.fs.readFile(content);
    }
    
    // If text is empty, return empty result
    if (!textContent || textContent.trim().length === 0) {
      return {
        entities: [],
        success: false,
        error: 'Empty text content'
      };
    }
    
    let entities: Entity[] = [];
    
    // Try to use Claude service if available
    if (this.claudeService) {
      try {
        this.logger.debug('Using Claude for entity extraction');
        entities = await this.extractWithClaude(textContent, contentType, options);
      } catch (error) {
        this.logger.warning(`Claude extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
        this.logger.debug('Falling back to rule-based extraction');
      }
    }
    
    // If Claude service failed or is unavailable, use rule-based extraction
    if (entities.length === 0) {
      this.logger.debug('Using rule-based entity extraction');
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
    
    this.logger.debug(`Extracted ${result.stats?.entityCount} entities in ${result.stats?.processingTimeMs}ms`);
    return result;
  }
  
  /**
   * Extract entities using Claude AI
   * @param text Text content
   * @param contentType MIME type of the content
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithClaude(
    text: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    if (!this.claudeService) {
      return [];
    }
    
    try {
      // Determine prompt template based on content type
      let promptTemplate = 'text_entities';
      if (options?.entityTypes && options.entityTypes.length > 0) {
        promptTemplate = 'text_entities_custom';
      }
      
      // Call Claude with appropriate prompt
      const claudeResponse = await this.claudeService.analyze(text, promptTemplate, {
        contentType,
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
      this.logger.error(`Error extracting entities with Claude: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Extract entities using rule-based approach
   * @param text Text content to analyze
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithRules(text: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep/sed
    const tempFile = await this.fs.createTempFile(text);
    
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
          const context = await this.fs.grepContext(tempFile, person, 30);
          // Get position (line number)
          const position = await this.fs.grepLineNumber(tempFile, person);
          
          entities.push({
            name: person,
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
      this.logger.warning(`Error extracting person entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Extract organization entities
    try {
      // Match common organization patterns
      const orgMatches = await this.fs.grep(tempFile, '\\b[A-Z][A-Za-z0-9]* (Inc\\.|Corp\\.|Ltd\\.|LLC|Company|Association|Foundation|University|Technologies|Group|Institute|Agency|Department)\\b');
      // Match capitalized multi-word names that could be organizations
      const capitalizedOrgMatches = await this.fs.grep(tempFile, '\\b([A-Z][a-z]+ ){1,3}(Inc\\.|Corp\\.|Ltd\\.|LLC|Company|Association|Foundation|University|Technologies|Group|Institute|Agency|Department)\\b');
      
      // Combine and deduplicate
      const organizations = Array.from(new Set([...orgMatches, ...capitalizedOrgMatches]));
      
      for (const org of organizations) {
        if (org.trim()) {
          // Get context
          const context = await this.fs.grepContext(tempFile, org, 30);
          // Get position
          const position = await this.fs.grepLineNumber(tempFile, org);
          
          entities.push({
            name: org,
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
      this.logger.warning(`Error extracting organization entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Extract location entities
    try {
      // Match common location patterns
      const locationMatches = await this.fs.grep(tempFile, '\\b(in|at|from|to) ([A-Z][a-z]+ )+([A-Z][a-z]+)?\\b');
      // Extract locations by removing the prepositions
      const locations = locationMatches.map(loc => 
        loc.replace(/^in /, '').replace(/^at /, '').replace(/^from /, '').replace(/^to /, '')
      );
      
      // Match countries and major cities
      const majorLocations = 'United States|Canada|UK|Australia|China|Japan|Russia|Germany|France|Italy|Spain|Brazil|India|Mexico|New York|London|Paris|Tokyo|Berlin|Rome|Moscow|Beijing|Los Angeles|Chicago|Toronto|Sydney|Amsterdam|Dubai';
      const majorLocationMatches = await this.fs.grep(tempFile, `\\b(${majorLocations})\\b`);
      
      // Combine and deduplicate
      const allLocations = Array.from(new Set([...locations, ...majorLocationMatches]));
      
      for (const location of allLocations) {
        if (location.trim()) {
          // Get context
          const context = await this.fs.grepContext(tempFile, location, 30);
          // Get position
          const position = await this.fs.grepLineNumber(tempFile, location);
          
          entities.push({
            name: location,
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
      this.logger.warning(`Error extracting location entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Extract date entities
    try {
      // Match various date formats
      const datePattern = '\\b[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}\\b|\\b[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\\b|\\b(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2},? [0-9]{4}\\b|\\b[0-9]{1,2} (January|February|March|April|May|June|July|August|September|October|November|December),? [0-9]{4}\\b';
      const dateMatches = await this.fs.grep(tempFile, datePattern);
      
      for (const date of dateMatches) {
        if (date.trim()) {
          // Get context
          const context = await this.fs.grepContext(tempFile, date, 30);
          // Get position
          const position = await this.fs.grepLineNumber(tempFile, date);
          
          entities.push({
            name: date,
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
      this.logger.warning(`Error extracting date entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
}