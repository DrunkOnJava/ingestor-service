/**
 * Code entity extractor implementation
 * Specialized for extracting entities from code files (TypeScript, JavaScript, Python, etc.)
 */

import { EntityExtractor } from '../EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityMention, EntityType } from '../types';
import { ClaudeService } from '../../services/ClaudeService';
import { Logger } from '../../logging';
import { FileSystem } from '../../utils/FileSystem';
import * as path from 'path';

/**
 * Entity extractor specialized for code files
 */
export class CodeEntityExtractor extends EntityExtractor {
  private claudeService?: ClaudeService;
  private fs: FileSystem;
  
  /**
   * Creates a new CodeEntityExtractor
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
   * Extract entities from code content
   * @param content The code content or file path
   * @param contentType MIME type of the code file
   * @param options Options to customize extraction behavior
   */
  public async extract(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    const startTime = Date.now();
    this.logger.debug(`Extracting entities from code content (${contentType})`);
    
    // Determine if content is a file path or raw code
    let codeContent = content;
    let language = options?.language;
    let filePath: string | undefined;
    
    if (await this.fs.isFile(content)) {
      filePath = content;
      codeContent = await this.fs.readFile(content);
      
      if (!language) {
        // Try to determine language from file extension if not provided
        language = this.detectLanguageFromPath(content);
      }
    }
    
    // If code is empty, return empty result
    if (!codeContent || codeContent.trim().length === 0) {
      return {
        entities: [],
        success: false,
        error: 'Empty code content'
      };
    }
    
    // If language is still unknown, try to detect from content
    if (!language) {
      language = this.detectLanguageFromContent(codeContent);
    }
    
    // Set the language in options for passing to extraction methods
    const enrichedOptions: EntityExtractionOptions = {
      ...options,
      language
    };
    
    let entities: Entity[] = [];
    
    // Try to use Claude service if available
    if (this.claudeService) {
      try {
        this.logger.debug(`Using Claude for code entity extraction (language: ${language || 'unknown'})`);
        entities = await this.extractWithClaude(codeContent, contentType, enrichedOptions);
      } catch (error) {
        this.logger.warning(`Claude extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
        this.logger.debug('Falling back to rule-based extraction');
      }
    }
    
    // If Claude service failed or is unavailable, use rule-based extraction
    if (entities.length === 0) {
      this.logger.debug(`Using rule-based code entity extraction (language: ${language || 'unknown'})`);
      entities = await this.extractWithRules(codeContent, language);
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
    
    this.logger.debug(`Extracted ${result.stats?.entityCount} entities from code in ${result.stats?.processingTimeMs}ms`);
    return result;
  }
  
  /**
   * Extract entities from code file using specific extractor for the language
   * @param content The code content
   * @param language Programming language of the code
   * @returns Array of extracted entities
   */
  private async extractFromFile(content: string, language?: string): Promise<Entity[]> {
    // First, extract common code entities regardless of language
    const commonEntities = await this.extractCommonCodeEntities(content);
    
    // Then extract language-specific entities based on detected language
    let languageSpecificEntities: Entity[] = [];
    
    switch (language?.toLowerCase()) {
      case 'javascript':
      case 'typescript':
      case 'js':
      case 'ts':
        languageSpecificEntities = await this.extractJavaScriptEntities(content);
        break;
      
      case 'python':
      case 'py':
        languageSpecificEntities = await this.extractPythonEntities(content);
        break;
      
      case 'java':
        languageSpecificEntities = await this.extractJavaEntities(content);
        break;
      
      case 'c':
      case 'cpp':
      case 'c++':
        languageSpecificEntities = await this.extractCEntities(content);
        break;
      
      case 'go':
        languageSpecificEntities = await this.extractGoEntities(content);
        break;
      
      case 'ruby':
      case 'rb':
        languageSpecificEntities = await this.extractRubyEntities(content);
        break;
      
      case 'php':
        languageSpecificEntities = await this.extractPhpEntities(content);
        break;
      
      case 'rust':
      case 'rs':
        languageSpecificEntities = await this.extractRustEntities(content);
        break;
      
      default:
        // For unknown languages, just use common entities
        this.logger.debug(`No specific extractor for language: ${language || 'unknown'}`);
        break;
    }
    
    // Merge and return all entities
    return this.mergeEntities([commonEntities, languageSpecificEntities]);
  }
  
  /**
   * Extract entities using Claude AI
   * @param code Code content
   * @param contentType MIME type of the content
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithClaude(
    code: string, 
    contentType: string, 
    options: EntityExtractionOptions
  ): Promise<Entity[]> {
    if (!this.claudeService) {
      return [];
    }
    
    try {
      // Use the code-specific prompt template
      const claudeResponse = await this.claudeService.analyze(code, 'code', {
        contentType,
        language: options.language,
        entityTypes: options.entityTypes?.join(','),
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
   * @param code Code content to analyze
   * @param language Detected programming language
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithRules(code: string, language?: string): Promise<Entity[]> {
    return this.extractFromFile(code, language);
  }
  
  /**
   * Detect programming language from file path/extension
   * @param filePath Path to the file
   * @returns Detected language or undefined
   * @private
   */
  private detectLanguageFromPath(filePath: string): string | undefined {
    const extension = path.extname(filePath).toLowerCase();
    
    switch (extension) {
      case '.js':
        return 'javascript';
      case '.ts':
      case '.tsx':
        return 'typescript';
      case '.py':
        return 'python';
      case '.java':
        return 'java';
      case '.c':
        return 'c';
      case '.cpp':
      case '.cc':
      case '.cxx':
      case '.h':
      case '.hpp':
        return 'cpp';
      case '.go':
        return 'go';
      case '.rb':
        return 'ruby';
      case '.php':
        return 'php';
      case '.rs':
        return 'rust';
      case '.swift':
        return 'swift';
      case '.cs':
        return 'csharp';
      case '.kt':
      case '.kts':
        return 'kotlin';
      case '.scala':
        return 'scala';
      case '.r':
        return 'r';
      case '.sh':
      case '.bash':
        return 'bash';
      case '.pl':
        return 'perl';
      case '.lua':
        return 'lua';
      case '.html':
        return 'html';
      case '.css':
        return 'css';
      case '.sql':
        return 'sql';
      default:
        return undefined;
    }
  }
  
  /**
   * Attempt to detect programming language from content
   * @param content Code content
   * @returns Detected language or 'unknown'
   * @private
   */
  private detectLanguageFromContent(content: string): string {
    // Simple heuristics to detect language from content
    
    // Check for Python patterns
    if (content.includes('def ') && content.includes(':') && (content.includes('import ') || content.includes('from '))) {
      return 'python';
    }
    
    // Check for JavaScript/TypeScript patterns
    if ((content.includes('function ') || content.includes('=>')) && 
        (content.includes('const ') || content.includes('let ') || content.includes('var '))) {
      // Check if it's TypeScript
      if (content.includes('interface ') || content.includes(': string') || 
          content.includes(': number') || content.includes(': boolean') || 
          content.includes('<T>')) {
        return 'typescript';
      }
      return 'javascript';
    }
    
    // Check for Java patterns
    if (content.includes('public class ') || content.includes('private class ') || 
        (content.includes('import java.') && content.includes('}'))) {
      return 'java';
    }
    
    // Check for C/C++ patterns
    if (content.includes('#include <') || (content.includes('int main(') && content.includes('}'))) {
      if (content.includes('std::') || content.includes('namespace ') || 
          content.includes('class ') || content.includes('template<')) {
        return 'cpp';
      }
      return 'c';
    }
    
    // Check for Go patterns
    if (content.includes('package ') && content.includes('func ') && content.includes('import (')) {
      return 'go';
    }
    
    // Check for Ruby patterns
    if (content.includes('def ') && content.includes('end') && (content.includes('require ') || content.includes('class '))) {
      return 'ruby';
    }
    
    // Check for PHP patterns
    if (content.includes('<?php') || (content.includes('function ') && content.includes('$'))) {
      return 'php';
    }
    
    // Check for Rust patterns
    if (content.includes('fn ') && content.includes('-> ') && content.includes('let mut ')) {
      return 'rust';
    }
    
    return 'unknown';
  }
  
  /**
   * Extract common code entities that appear across most programming languages
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractCommonCodeEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract imports and dependencies
      const importPatterns = [
        'import\\s+[\\w\\s,.{}]*\\s+from\\s+[\'"][^\'"]+[\'"]', // JS/TS imports
        'import\\s+[\'"][^\'"]+[\'"]',                          // JS/TS bare imports
        'import\\s+[\\w.]+', // Java/Python imports
        '#include\\s+[<"][^>"]+[>"]', // C/C++ includes
        'require\\s*\\([\'"][^\'"]+[\'"]\\)', // Node.js require
        'require\\s+[\'"][^\'"]+[\'"]', // Ruby require
        'use\\s+[\\w:]+', // Rust use statements
        'from\\s+[\\w.]+\\s+import' // Python specific imports
      ];
      
      for (const pattern of importPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract the dependency name
          let dependencyName = match;
          // Try to extract just the package/module name
          const fromMatch = match.match(/from\s+['"]([^'"]+)['"]/);
          const importMatch = match.match(/import\s+['"]([^'"]+)['"]/);
          const requireMatch = match.match(/require\s*\(['"]([^'"]+)['"]\)/);
          const includeMatch = match.match(/#include\s+[<"]([^>"]+)[>"]/);
          
          if (fromMatch) {
            dependencyName = fromMatch[1];
          } else if (importMatch) {
            dependencyName = importMatch[1];
          } else if (requireMatch) {
            dependencyName = requireMatch[1];
          } else if (includeMatch) {
            dependencyName = includeMatch[1];
          }
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 50);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: dependencyName,
            type: EntityType.TECHNOLOGY,
            description: `Imported dependency: ${dependencyName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract function definitions
      const functionPatterns = [
        'function\\s+[\\w]+\\s*\\([^)]*\\)', // JavaScript functions
        '[\\w]+\\s*:\\s*function\\s*\\(', // JavaScript object functions
        'const\\s+[\\w]+\\s*=\\s*\\([^)]*\\)\\s*=>',  // JavaScript arrow functions
        'def\\s+[\\w_]+\\s*\\([^)]*\\)', // Python functions
        '\\bfunc\\s+[\\w]+\\s*\\([^)]*\\)', // Go functions
        '\\b(public|private|protected)?(\\s+static)?\\s+[\\w<>\\[\\]]+\\s+[\\w]+\\s*\\([^)]*\\)', // Java methods
        '[\\w_]+\\s*=\\s*function\\s*\\(',  // JavaScript assigned functions
        'fn\\s+[\\w_]+\\s*\\([^)]*\\)' // Rust functions
      ];
      
      for (const pattern of functionPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract just the function name
          let functionName = match;
          
          // Match function name based on pattern
          const jsMatch = match.match(/function\s+([\w]+)/);
          const objFuncMatch = match.match(/([\w]+)\s*:\s*function/);
          const arrowMatch = match.match(/const\s+([\w]+)\s*=/);
          const pythonMatch = match.match(/def\s+([\w_]+)/);
          const goMatch = match.match(/func\s+([\w]+)/);
          const javaMatch = match.match(/\s+([\w]+)\s*\(/);
          const assignedFuncMatch = match.match(/([\w_]+)\s*=\s*function/);
          const rustMatch = match.match(/fn\s+([\w_]+)/);
          
          if (jsMatch) functionName = jsMatch[1];
          else if (objFuncMatch) functionName = objFuncMatch[1];
          else if (arrowMatch) functionName = arrowMatch[1];
          else if (pythonMatch) functionName = pythonMatch[1];
          else if (goMatch) functionName = goMatch[1];
          else if (javaMatch && javaMatch[1] !== 'return') functionName = javaMatch[1]; // avoid return statement matches
          else if (assignedFuncMatch) functionName = assignedFuncMatch[1];
          else if (rustMatch) functionName = rustMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          // Skip if function name is too generic
          const genericNames = ['if', 'for', 'while', 'switch', 'catch', 'then', 'else', 'return'];
          if (genericNames.includes(functionName)) continue;
          
          entities.push({
            name: functionName,
            type: EntityType.TECHNOLOGY,
            description: `Function: ${functionName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.8
            }]
          });
        }
      }
      
      // Extract class definitions
      const classPatterns = [
        'class\\s+[\\w]+', // General class pattern
        'interface\\s+[\\w]+', // TypeScript/Java interfaces
        'struct\\s+[\\w]+', // C/C++/Rust structs
        'enum\\s+[\\w]+', // Enums
        'type\\s+[\\w]+\\s*struct', // Go struct types
        'trait\\s+[\\w]+'  // Rust traits
      ];
      
      for (const pattern of classPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract just the class/interface/struct name
          let className = match;
          
          const classMatch = match.match(/class\s+([\w]+)/);
          const interfaceMatch = match.match(/interface\s+([\w]+)/);
          const structMatch = match.match(/struct\s+([\w]+)/);
          const enumMatch = match.match(/enum\s+([\w]+)/);
          const goStructMatch = match.match(/type\s+([\w]+)\s*struct/);
          const traitMatch = match.match(/trait\s+([\w]+)/);
          
          if (classMatch) className = classMatch[1];
          else if (interfaceMatch) className = interfaceMatch[1];
          else if (structMatch) className = structMatch[1];
          else if (enumMatch) className = enumMatch[1];
          else if (goStructMatch) className = goStructMatch[1];
          else if (traitMatch) className = traitMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: className,
            type: EntityType.TECHNOLOGY,
            description: `Class/Interface/Type: ${className}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.9
            }]
          });
        }
      }
      
      // Extract constants and significant variables
      const constPatterns = [
        'const\\s+[A-Z_\\d]+\\s*=', // ALL_CAPS constants
        'final\\s+[\\w]+\\s+[A-Z_\\d]+\\s*=', // Java final constants
        'static\\s+final\\s+[\\w]+\\s+[A-Z_\\d]+\\s*=', // Java static final constants
        '#define\\s+[A-Z_\\d]+', // C/C++ macros
        'var\\s+[A-Z_\\d]+\\s*=', // JavaScript ALL_CAPS variables
        'let\\s+[A-Z_\\d]+\\s*=' // JavaScript ALL_CAPS let variables
      ];
      
      for (const pattern of constPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract just the constant name
          let constName = match;
          
          const jsConstMatch = match.match(/const\s+([A-Z_\d]+)/);
          const javaConstMatch = match.match(/final\s+[\w]+\s+([A-Z_\d]+)/);
          const javaStaticConstMatch = match.match(/static\s+final\s+[\w]+\s+([A-Z_\d]+)/);
          const defineMatch = match.match(/#define\s+([A-Z_\d]+)/);
          const varMatch = match.match(/var\s+([A-Z_\d]+)/);
          const letMatch = match.match(/let\s+([A-Z_\d]+)/);
          
          if (jsConstMatch) constName = jsConstMatch[1];
          else if (javaConstMatch) constName = javaConstMatch[1];
          else if (javaStaticConstMatch) constName = javaStaticConstMatch[1];
          else if (defineMatch) constName = defineMatch[1];
          else if (varMatch) constName = varMatch[1];
          else if (letMatch) constName = letMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: constName,
            type: EntityType.TECHNOLOGY,
            description: `Constant: ${constName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.7
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting common code entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract JavaScript/TypeScript specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractJavaScriptEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract React components
      const reactPatterns = [
        'function\\s+[A-Z][\\w]*\\s*\\([^)]*\\)\\s*{', // Functional components
        'const\\s+[A-Z][\\w]*\\s*=\\s*\\([^)]*\\)\\s*=>',  // Arrow function components
        'class\\s+[A-Z][\\w]*\\s+extends\\s+React\\.Component', // Class components
        'class\\s+[A-Z][\\w]*\\s+extends\\s+Component' // Class components without React namespace
      ];
      
      for (const pattern of reactPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract component name
          let componentName = match;
          
          const funcCompMatch = match.match(/function\s+([A-Z][\w]*)/);
          const arrowCompMatch = match.match(/const\s+([A-Z][\w]*)\s*=/);
          const classCompMatch = match.match(/class\s+([A-Z][\w]*)\s+extends/);
          
          if (funcCompMatch) componentName = funcCompMatch[1];
          else if (arrowCompMatch) componentName = arrowCompMatch[1];
          else if (classCompMatch) componentName = classCompMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: componentName,
            type: EntityType.TECHNOLOGY,
            description: `React Component: ${componentName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract TypeScript interfaces and types
      const typePatterns = [
        'interface\\s+[\\w]+\\s*{', // TypeScript interfaces
        'type\\s+[\\w]+\\s*=\\s*{', // TypeScript type aliases with object
        'type\\s+[\\w]+\\s*=\\s*[\\w]+', // TypeScript type aliases
        'enum\\s+[\\w]+\\s*{' // TypeScript enums
      ];
      
      for (const pattern of typePatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract type name
          let typeName = match;
          
          const interfaceMatch = match.match(/interface\s+([\w]+)/);
          const typeObjectMatch = match.match(/type\s+([\w]+)\s*=/);
          const typeAliasMatch = match.match(/type\s+([\w]+)\s*=/);
          const enumMatch = match.match(/enum\s+([\w]+)/);
          
          if (interfaceMatch) typeName = interfaceMatch[1];
          else if (typeObjectMatch) typeName = typeObjectMatch[1];
          else if (typeAliasMatch) typeName = typeAliasMatch[1];
          else if (enumMatch) typeName = enumMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: typeName,
            type: EntityType.TECHNOLOGY,
            description: `TypeScript Type: ${typeName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract hooks usage
      const hooksPatterns = [
        'use[A-Z][\\w]*\\(', // React hooks (useState, useEffect, etc.)
        'const\\s+\\[[\\w]+,\\s*set[A-Z][\\w]*\\]\\s*=\\s*useState' // useState pattern
      ];
      
      for (const pattern of hooksPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Extract hook name
          let hookName = match;
          
          const hookMatch = match.match(/use([A-Z][\w]*)\(/);
          const useStateMatch = match.match(/set([A-Z][\w]*)\]/);
          
          if (hookMatch) hookName = `use${hookMatch[1]}`;
          else if (useStateMatch) hookName = `useState (${useStateMatch[1]})`;
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: hookName,
            type: EntityType.TECHNOLOGY,
            description: `React Hook: ${hookName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.75
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting JavaScript/TypeScript entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract Python specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractPythonEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract decorators
      const decoratorPattern = '@[\\w_.]+';
      const decoratorMatches = await this.fs.grep(tempFile, decoratorPattern);
      
      for (const match of decoratorMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Python Decorator: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.75
          }]
        });
      }
      
      // Extract class methods
      const methodPattern = '\\s+def\\s+[\\w_]+\\s*\\(self';
      const methodMatches = await this.fs.grep(tempFile, methodPattern);
      
      for (const match of methodMatches) {
        // Extract method name
        const methodMatch = match.match(/def\s+([\w_]+)/);
        if (methodMatch) {
          const methodName = methodMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: methodName,
            type: EntityType.TECHNOLOGY,
            description: `Class Method: ${methodName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.8
            }]
          });
        }
      }
      
      // Extract data science/ML libraries
      const dsLibsPattern = 'import\\s+(numpy|pandas|matplotlib|scipy|sklearn|keras|tensorflow|torch|seaborn)';
      const dsLibsMatches = await this.fs.grep(tempFile, dsLibsPattern);
      
      for (const match of dsLibsMatches) {
        // Extract library name
        const libMatch = match.match(/import\s+([\w.]+)/);
        if (libMatch) {
          const libName = libMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: libName,
            type: EntityType.TECHNOLOGY,
            description: `Data Science Library: ${libName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.9
            }]
          });
        }
      }
      
      // Extract type hints
      const typeHintPattern = '\\)\\s*->\\s*[\\w\\[\\],\\s.]+:';
      const typeHintMatches = await this.fs.grep(tempFile, typeHintPattern);
      
      for (const match of typeHintMatches) {
        // Extract return type
        const typeMatch = match.match(/\)\s*->\s*([\w\[\],\s.]+):/);
        if (typeMatch) {
          const typeName = typeMatch[1].trim();
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: typeName,
            type: EntityType.TECHNOLOGY,
            description: `Return Type: ${typeName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.7
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting Python entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract Java specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractJavaEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract annotations
      const annotationPattern = '@[A-Z][\\w]+';
      const annotationMatches = await this.fs.grep(tempFile, annotationPattern);
      
      for (const match of annotationMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Java Annotation: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.8
          }]
        });
      }
      
      // Extract packages
      const packagePattern = 'package\\s+[\\w.]+;';
      const packageMatches = await this.fs.grep(tempFile, packagePattern);
      
      for (const match of packageMatches) {
        // Extract package name
        const packageMatch = match.match(/package\s+([\w.]+);/);
        if (packageMatch) {
          const packageName = packageMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: packageName,
            type: EntityType.TECHNOLOGY,
            description: `Java Package: ${packageName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract interfaces
      const interfacePattern = '(public|private|protected)?\\s+interface\\s+[\\w]+';
      const interfaceMatches = await this.fs.grep(tempFile, interfacePattern);
      
      for (const match of interfaceMatches) {
        // Extract interface name
        const interfaceMatch = match.match(/interface\s+([\w]+)/);
        if (interfaceMatch) {
          const interfaceName = interfaceMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: interfaceName,
            type: EntityType.TECHNOLOGY,
            description: `Java Interface: ${interfaceName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract generic type parameters
      const genericPattern = '<[A-Z]((,\\s*[A-Z])*(\\s+extends\\s+[\\w.]+)?)>';
      const genericMatches = await this.fs.grep(tempFile, genericPattern);
      
      for (const match of genericMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Generic Type Parameter: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.7
          }]
        });
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting Java entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract C/C++ specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractCEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract preprocessor directives
      const preprocessorPattern = '#(include|define|ifdef|ifndef|endif|pragma)';
      const preprocessorMatches = await this.fs.grep(tempFile, preprocessorPattern);
      
      for (const match of preprocessorMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Preprocessor Directive: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.75
          }]
        });
      }
      
      // Extract structs
      const structPattern = 'struct\\s+[\\w]+\\s*{';
      const structMatches = await this.fs.grep(tempFile, structPattern);
      
      for (const match of structMatches) {
        // Extract struct name
        const structMatch = match.match(/struct\s+([\w]+)/);
        if (structMatch) {
          const structName = structMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: structName,
            type: EntityType.TECHNOLOGY,
            description: `Struct: ${structName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract C++ namespaces
      const namespacePattern = 'namespace\\s+[\\w]+\\s*{';
      const namespaceMatches = await this.fs.grep(tempFile, namespacePattern);
      
      for (const match of namespaceMatches) {
        // Extract namespace name
        const namespaceMatch = match.match(/namespace\s+([\w]+)/);
        if (namespaceMatch) {
          const namespaceName = namespaceMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: namespaceName,
            type: EntityType.TECHNOLOGY,
            description: `Namespace: ${namespaceName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract C++ templates
      const templatePattern = 'template\\s*<[^>]+>';
      const templateMatches = await this.fs.grep(tempFile, templatePattern);
      
      for (const match of templateMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Template: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.8
          }]
        });
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting C/C++ entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract Go specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractGoEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract package declarations
      const packagePattern = 'package\\s+[\\w]+';
      const packageMatches = await this.fs.grep(tempFile, packagePattern);
      
      for (const match of packageMatches) {
        // Extract package name
        const packageMatch = match.match(/package\s+([\w]+)/);
        if (packageMatch) {
          const packageName = packageMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: packageName,
            type: EntityType.TECHNOLOGY,
            description: `Go Package: ${packageName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.9
            }]
          });
        }
      }
      
      // Extract struct types
      const structPattern = 'type\\s+[\\w]+\\s+struct\\s*{';
      const structMatches = await this.fs.grep(tempFile, structPattern);
      
      for (const match of structMatches) {
        // Extract struct name
        const structMatch = match.match(/type\s+([\w]+)\s+struct/);
        if (structMatch) {
          const structName = structMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: structName,
            type: EntityType.TECHNOLOGY,
            description: `Go Struct: ${structName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract interfaces
      const interfacePattern = 'type\\s+[\\w]+\\s+interface\\s*{';
      const interfaceMatches = await this.fs.grep(tempFile, interfacePattern);
      
      for (const match of interfaceMatches) {
        // Extract interface name
        const interfaceMatch = match.match(/type\s+([\w]+)\s+interface/);
        if (interfaceMatch) {
          const interfaceName = interfaceMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: interfaceName,
            type: EntityType.TECHNOLOGY,
            description: `Go Interface: ${interfaceName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract methods
      const methodPattern = 'func\\s*\\([\\w\\s\\*]+\\s+[\\w]+\\)\\s+[\\w]+';
      const methodMatches = await this.fs.grep(tempFile, methodPattern);
      
      for (const match of methodMatches) {
        // Extract method name and receiver
        const methodMatch = match.match(/func\s*\([\w\s\*]+\s+([\w]+)\)\s+([\w]+)/);
        if (methodMatch) {
          const receiverType = methodMatch[1];
          const methodName = methodMatch[2];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: `${receiverType}.${methodName}`,
            type: EntityType.TECHNOLOGY,
            description: `Method: ${methodName} on ${receiverType}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.8
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting Go entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract Ruby specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractRubyEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract Ruby modules
      const modulePattern = 'module\\s+[A-Z][\\w:]*';
      const moduleMatches = await this.fs.grep(tempFile, modulePattern);
      
      for (const match of moduleMatches) {
        // Extract module name
        const moduleMatch = match.match(/module\s+([A-Z][\w:]*)/);
        if (moduleMatch) {
          const moduleName = moduleMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: moduleName,
            type: EntityType.TECHNOLOGY,
            description: `Ruby Module: ${moduleName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.9
            }]
          });
        }
      }
      
      // Extract symbols
      const symbolPattern = ':[\\w_]+';
      const symbolMatches = await this.fs.grep(tempFile, symbolPattern);
      
      for (const match of symbolMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Ruby Symbol: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.7
          }]
        });
      }
      
      // Extract Rails-specific patterns
      const railsPatterns = [
        'has_many\\s+:[\\w_]+',
        'belongs_to\\s+:[\\w_]+',
        'validates\\s+:[\\w_]+',
        'before_action\\s+:[\\w_]+',
        'scope\\s+:[\\w_]+'
      ];
      
      for (const pattern of railsPatterns) {
        const matches = await this.fs.grep(tempFile, pattern);
        
        for (const match of matches) {
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: match,
            type: EntityType.TECHNOLOGY,
            description: `Rails Pattern: ${match}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting Ruby entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract PHP specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractPhpEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract namespaces
      const namespacePattern = 'namespace\\s+[\\w\\\\]+;';
      const namespaceMatches = await this.fs.grep(tempFile, namespacePattern);
      
      for (const match of namespaceMatches) {
        // Extract namespace name
        const namespaceMatch = match.match(/namespace\s+([\w\\]+);/);
        if (namespaceMatch) {
          const namespaceName = namespaceMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: namespaceName,
            type: EntityType.TECHNOLOGY,
            description: `PHP Namespace: ${namespaceName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.9
            }]
          });
        }
      }
      
      // Extract PHP class methods
      const methodPattern = '(public|private|protected)\\s+function\\s+[\\w_]+\\s*\\(';
      const methodMatches = await this.fs.grep(tempFile, methodPattern);
      
      for (const match of methodMatches) {
        // Extract method name and visibility
        const methodMatch = match.match(/(public|private|protected)\s+function\s+([\w_]+)/);
        if (methodMatch) {
          const visibility = methodMatch[1];
          const methodName = methodMatch[2];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: methodName,
            type: EntityType.TECHNOLOGY,
            description: `${visibility} Method: ${methodName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.8
            }]
          });
        }
      }
      
      // Extract trait definitions
      const traitPattern = 'trait\\s+[\\w_]+';
      const traitMatches = await this.fs.grep(tempFile, traitPattern);
      
      for (const match of traitMatches) {
        // Extract trait name
        const traitMatch = match.match(/trait\s+([\w_]+)/);
        if (traitMatch) {
          const traitName = traitMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: traitName,
            type: EntityType.TECHNOLOGY,
            description: `PHP Trait: ${traitName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting PHP entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
  
  /**
   * Extract Rust specific entities
   * @param code Code content
   * @returns Array of extracted entities
   * @private
   */
  private async extractRustEntities(code: string): Promise<Entity[]> {
    const entities: Entity[] = [];
    
    // Create a temporary file for processing with grep
    const tempFile = await this.fs.createTempFile(code);
    
    try {
      // Extract Rust structs
      const structPattern = 'struct\\s+[\\w_]+';
      const structMatches = await this.fs.grep(tempFile, structPattern);
      
      for (const match of structMatches) {
        // Extract struct name
        const structMatch = match.match(/struct\s+([\w_]+)/);
        if (structMatch) {
          const structName = structMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: structName,
            type: EntityType.TECHNOLOGY,
            description: `Rust Struct: ${structName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract Rust enums
      const enumPattern = 'enum\\s+[\\w_]+';
      const enumMatches = await this.fs.grep(tempFile, enumPattern);
      
      for (const match of enumMatches) {
        // Extract enum name
        const enumMatch = match.match(/enum\s+([\w_]+)/);
        if (enumMatch) {
          const enumName = enumMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: enumName,
            type: EntityType.TECHNOLOGY,
            description: `Rust Enum: ${enumName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.85
            }]
          });
        }
      }
      
      // Extract Rust traits
      const traitPattern = 'trait\\s+[\\w_]+';
      const traitMatches = await this.fs.grep(tempFile, traitPattern);
      
      for (const match of traitMatches) {
        // Extract trait name
        const traitMatch = match.match(/trait\s+([\w_]+)/);
        if (traitMatch) {
          const traitName = traitMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: traitName,
            type: EntityType.TECHNOLOGY,
            description: `Rust Trait: ${traitName}`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.9
            }]
          });
        }
      }
      
      // Extract Rust impl blocks
      const implPattern = 'impl(\\s+[\\w<>,\\s]+)?\\s+for\\s+[\\w<>,\\s]+';
      const implMatches = await this.fs.grep(tempFile, implPattern);
      
      for (const match of implMatches) {
        // Get context and position
        const context = await this.fs.grepContext(tempFile, match, 100);
        const position = await this.fs.grepLineNumber(tempFile, match);
        
        entities.push({
          name: match,
          type: EntityType.TECHNOLOGY,
          description: `Rust Implementation: ${match}`,
          mentions: [{
            context: context || match,
            position: position,
            relevance: 0.8
          }]
        });
      }
      
      // Extract macros
      const macroPattern = '\\w+!\\(';
      const macroMatches = await this.fs.grep(tempFile, macroPattern);
      
      for (const match of macroMatches) {
        // Extract macro name
        const macroMatch = match.match(/([\w]+)!/);
        if (macroMatch) {
          const macroName = macroMatch[1];
          
          // Get context and position
          const context = await this.fs.grepContext(tempFile, match, 100);
          const position = await this.fs.grepLineNumber(tempFile, match);
          
          entities.push({
            name: `${macroName}!`,
            type: EntityType.TECHNOLOGY,
            description: `Rust Macro: ${macroName}!`,
            mentions: [{
              context: context || match,
              position: position,
              relevance: 0.75
            }]
          });
        }
      }
      
    } catch (error) {
      this.logger.warning(`Error extracting Rust entities: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Clean up temporary file
    await this.fs.removeFile(tempFile);
    
    return entities;
  }
}