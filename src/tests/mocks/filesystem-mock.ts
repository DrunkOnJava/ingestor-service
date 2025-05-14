/**
 * Mock implementation of FileSystem utilities for testing
 */

import { Logger } from '../../core/logging';

/**
 * Creates a mock FileSystem service for testing
 */
export function createFileSystemMock(logger?: Logger) {
  // Mock implementation of FileSystem utilities
  return {
    isFile: jest.fn().mockResolvedValue(false),
    
    readFile: jest.fn().mockResolvedValue(''),
    
    writeFile: jest.fn().mockResolvedValue(true),
    
    createTempFile: jest.fn().mockResolvedValue('/tmp/temp_file.txt'),
    
    removeFile: jest.fn().mockResolvedValue(true),
    
    grep: jest.fn().mockResolvedValue([]),
    
    grepContext: jest.fn().mockResolvedValue('Sample context'),
    
    grepLineNumber: jest.fn().mockResolvedValue(1),
    
    // Configure to return specific patterns based on inputs
    configurePatternMatches: (patterns: Record<string, string[]>) => {
      const mockFs = createFileSystemMock(logger);
      
      mockFs.grep.mockImplementation(async (filePath: string, pattern: string) => {
        // Check if we have mock results for this pattern
        if (patterns[pattern]) {
          return patterns[pattern];
        }
        
        // Default response
        return [];
      });
      
      return mockFs;
    }
  };
}