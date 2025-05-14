/**
 * FileSystem utility class
 * Provides file system operations for the ingestor system
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import { Logger } from '../logging';

const execPromise = promisify(exec);

/**
 * File system utility for working with content files
 */
export class FileSystem {
  private logger: Logger;
  private tempDir: string;
  
  /**
   * Creates a new FileSystem instance
   * @param logger Logger instance
   * @param tempDir Directory for temporary files (defaults to /tmp/ingestor-temp)
   */
  constructor(
    logger: Logger,
    tempDir: string = '/tmp/ingestor-temp'
  ) {
    this.logger = logger;
    this.tempDir = tempDir;
    this.initTempDir();
  }
  
  /**
   * Initialize the temporary directory
   * @private
   */
  private async initTempDir(): Promise<void> {
    try {
      await fs.mkdir(this.tempDir, { recursive: true });
      this.logger.debug(`Temporary directory initialized: ${this.tempDir}`);
    } catch (error) {
      this.logger.error(`Failed to create temp directory: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
  }
  
  /**
   * Check if a path is a file
   * @param filePath Path to check
   */
  public async isFile(filePath: string): Promise<boolean> {
    try {
      const stats = await fs.stat(filePath);
      return stats.isFile();
    } catch (error) {
      return false;
    }
  }
  
  /**
   * Read file content as string
   * @param filePath Path to the file
   */
  public async readFile(filePath: string): Promise<string> {
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      return content;
    } catch (error) {
      this.logger.error(`Failed to read file ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return '';
    }
  }
  
  /**
   * Write content to a file
   * @param filePath Path to the file
   * @param content Content to write
   */
  public async writeFile(filePath: string, content: string): Promise<boolean> {
    try {
      await fs.writeFile(filePath, content, 'utf-8');
      return true;
    } catch (error) {
      this.logger.error(`Failed to write file ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
  
  /**
   * Create a temporary file with content
   * @param content Content to write to the file
   * @param prefix Optional prefix for the file name
   */
  public async createTempFile(content: string, prefix = 'ingestor-'): Promise<string> {
    try {
      const timestamp = Date.now();
      const tempFile = path.join(this.tempDir, `${prefix}${timestamp}.txt`);
      await this.writeFile(tempFile, content);
      return tempFile;
    } catch (error) {
      this.logger.error(`Failed to create temp file: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Remove a file
   * @param filePath Path to the file
   */
  public async removeFile(filePath: string): Promise<boolean> {
    try {
      await fs.unlink(filePath);
      return true;
    } catch (error) {
      this.logger.warning(`Failed to remove file ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
  
  /**
   * Check if a directory exists
   * @param dirPath Path to the directory
   */
  public async dirExists(dirPath: string): Promise<boolean> {
    try {
      const stats = await fs.stat(dirPath);
      return stats.isDirectory();
    } catch (error) {
      return false;
    }
  }
  
  /**
   * Create a directory
   * @param dirPath Path to create
   */
  public async createDir(dirPath: string): Promise<boolean> {
    try {
      await fs.mkdir(dirPath, { recursive: true });
      return true;
    } catch (error) {
      this.logger.error(`Failed to create directory ${dirPath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
  
  /**
   * Find text matches in a file using grep
   * @param filePath Path to the file
   * @param pattern Pattern to search for
   */
  public async grep(filePath: string, pattern: string): Promise<string[]> {
    try {
      // Use ripgrep (rg) instead of grep for better performance and features
      const cmd = `rg -o '${pattern}' ${filePath} | sort | uniq`;
      const { stdout } = await execPromise(cmd);
      
      // Split result by lines and filter out empty lines
      return stdout.split('\n').filter(line => line.trim() !== '');
    } catch (error) {
      if ((error as any).code === 1) {
        // ripgrep returns code 1 when no matches are found, which is not an error
        return [];
      }
      
      this.logger.warning(`Grep failed for ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Get context around a pattern match in a file
   * @param filePath Path to the file
   * @param pattern Pattern to search for
   * @param contextSize Number of characters of context to include
   */
  public async grepContext(filePath: string, pattern: string, contextSize = 30): Promise<string> {
    try {
      // Escape pattern for grep command
      const escapedPattern = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      
      // Use ripgrep with context
      const cmd = `rg -o '.{0,${contextSize}}${escapedPattern}.{0,${contextSize}}' ${filePath} | head -1`;
      const { stdout } = await execPromise(cmd);
      
      return stdout.trim();
    } catch (error) {
      this.logger.warning(`Failed to get context for ${pattern} in ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return '';
    }
  }
  
  /**
   * Get line number of a pattern match in a file
   * @param filePath Path to the file
   * @param pattern Pattern to search for
   */
  public async grepLineNumber(filePath: string, pattern: string): Promise<number> {
    try {
      // Escape pattern for grep command
      const escapedPattern = pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      
      // Use ripgrep to get line number
      const cmd = `rg -n '${escapedPattern}' ${filePath} | head -1 | cut -d: -f1`;
      const { stdout } = await execPromise(cmd);
      
      const lineNumber = parseInt(stdout.trim(), 10);
      return isNaN(lineNumber) ? 0 : lineNumber;
    } catch (error) {
      this.logger.warning(`Failed to get line number for ${pattern} in ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return 0;
    }
  }
  
  /**
   * Get the MIME type of a file
   * @param filePath Path to the file
   */
  public async getMimeType(filePath: string): Promise<string> {
    try {
      // Use file command to determine MIME type
      const cmd = `file --mime-type -b "${filePath}"`;
      const { stdout } = await execPromise(cmd);
      
      return stdout.trim();
    } catch (error) {
      this.logger.warning(`Failed to get MIME type for ${filePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return 'application/octet-stream'; // Default binary MIME type
    }
  }
}