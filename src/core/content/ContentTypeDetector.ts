/**
 * Content type detector
 * Detects MIME types of content based on file extensions or content analysis
 */

import { Logger } from '../logging';
import { FileSystem } from '../utils';
import * as path from 'path';

/**
 * Map of file extensions to MIME types
 */
const EXTENSION_TO_MIME: Record<string, string> = {
  // Text formats
  'txt': 'text/plain',
  'md': 'text/markdown',
  'markdown': 'text/markdown',
  'html': 'text/html',
  'htm': 'text/html',
  'css': 'text/css',
  'csv': 'text/csv',
  
  // Programming languages
  'js': 'text/javascript',
  'ts': 'text/typescript',
  'tsx': 'text/typescript',
  'jsx': 'text/javascript',
  'py': 'text/x-python',
  'java': 'text/x-java',
  'c': 'text/x-c',
  'cpp': 'text/x-c++',
  'h': 'text/x-c',
  'hpp': 'text/x-c++',
  'sh': 'application/x-sh',
  'rb': 'text/x-ruby',
  'go': 'text/x-go',
  'php': 'text/x-php',
  'rs': 'text/x-rust',
  'swift': 'text/x-swift',
  
  // Document formats
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  
  // Data formats
  'json': 'application/json',
  'xml': 'application/xml',
  'yaml': 'application/yaml',
  'yml': 'application/yaml',
  'toml': 'application/toml',
  
  // Image formats
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'svg': 'image/svg+xml',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'tiff': 'image/tiff',
  'tif': 'image/tiff',
  
  // Audio formats
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
  'aac': 'audio/aac',
  
  // Video formats
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'avi': 'video/x-msvideo',
  'mov': 'video/quicktime',
  'wmv': 'video/x-ms-wmv',
  'mkv': 'video/x-matroska',
  
  // Archive formats
  'zip': 'application/zip',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  
  // Other formats
  'exe': 'application/x-msdownload',
  'dll': 'application/x-msdownload',
  'bin': 'application/octet-stream',
  'iso': 'application/x-iso9660-image'
};

/**
 * Content type detector for the ingestor system
 */
export class ContentTypeDetector {
  private logger: Logger;
  private fs: FileSystem;
  
  /**
   * Creates a new ContentTypeDetector instance
   * @param logger Logger instance
   * @param fs File system utility
   */
  constructor(logger: Logger, fs: FileSystem) {
    this.logger = logger;
    this.fs = fs;
  }
  
  /**
   * Detect the MIME type of content
   * @param content Content to detect (can be text or file path)
   * @returns Detected MIME type
   */
  public async detectContentType(content: string): Promise<string> {
    // Check if content is a file
    if (await this.fs.isFile(content)) {
      return this.detectFileType(content);
    }
    
    // If content is raw text, try to detect type from content
    return this.detectTextType(content);
  }
  
  /**
   * Detect MIME type of a file
   * @param filePath Path to the file
   * @returns Detected MIME type
   * @private
   */
  private async detectFileType(filePath: string): Promise<string> {
    this.logger.debug(`Detecting content type for file: ${filePath}`);
    
    // First, try to get type based on file extension
    const extension = path.extname(filePath).toLowerCase().substring(1);
    if (extension && EXTENSION_TO_MIME[extension]) {
      this.logger.debug(`Detected type from extension: ${EXTENSION_TO_MIME[extension]}`);
      return EXTENSION_TO_MIME[extension];
    }
    
    // If extension doesn't match, use file command
    try {
      const mimeType = await this.fs.getMimeType(filePath);
      this.logger.debug(`Detected type using file command: ${mimeType}`);
      return mimeType;
    } catch (error) {
      this.logger.warning(`Failed to detect MIME type using file command: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // If all else fails, read file beginning and try to detect
    try {
      // Read first 4KB to detect type
      const fileContent = await this.fs.readFile(filePath);
      const filePreview = fileContent.substring(0, 4096);
      
      return this.detectTextType(filePreview);
    } catch (error) {
      this.logger.warning(`Failed to read file for type detection: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
    
    // Default to binary if we can't detect
    return 'application/octet-stream';
  }
  
  /**
   * Detect MIME type of text content
   * @param text Text content to analyze
   * @returns Detected MIME type
   * @private
   */
  private detectTextType(text: string): string {
    // HTML detection
    if (text.trim().startsWith('<!DOCTYPE html>') || text.trim().startsWith('<html')) {
      return 'text/html';
    }
    
    // XML detection
    if (text.trim().startsWith('<?xml')) {
      return 'application/xml';
    }
    
    // JSON detection
    if (text.trim().startsWith('{') || text.trim().startsWith('[')) {
      try {
        JSON.parse(text);
        return 'application/json';
      } catch {
        // Not valid JSON
      }
    }
    
    // Markdown detection
    if (text.includes('# ') || text.includes('## ') || text.includes('```') || text.includes('**')) {
      return 'text/markdown';
    }
    
    // Python detection
    if (text.includes('def ') || text.includes('import ') || text.includes('class ')) {
      return 'text/x-python';
    }
    
    // JavaScript detection
    if (text.includes('function ') || text.includes('const ') || text.includes('let ') || text.includes('var ')) {
      return 'text/javascript';
    }
    
    // Shell script detection
    if (text.includes('#!/bin/') || text.includes('export ') || text.startsWith('#!')) {
      return 'application/x-sh';
    }
    
    // CSV detection
    if (text.includes(',') && text.split('\n').every(line => line.split(',').length > 1)) {
      return 'text/csv';
    }
    
    // Default to plain text
    return 'text/plain';
  }
}