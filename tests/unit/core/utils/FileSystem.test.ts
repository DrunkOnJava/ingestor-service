import { FileSystem } from '../../../../src/core/utils/FileSystem';
import { Logger } from '../../../../src/core/logging/Logger';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

describe('FileSystem', () => {
  let logger: Logger;
  let fileSystem: FileSystem;
  let tempDir: string;
  
  beforeAll(() => {
    // Create a temporary directory for testing
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ingestor-test-fs-'));
  });
  
  afterAll(() => {
    // Clean up the temporary directory
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (error) {
      console.error(`Error cleaning up temporary directory: ${error}`);
    }
  });
  
  beforeEach(() => {
    logger = new Logger('test');
    fileSystem = new FileSystem(logger, path.join(tempDir, 'temp'));
  });
  
  describe('initialization', () => {
    it('should create the temporary directory if it does not exist', () => {
      // The constructor should have created the temp directory
      const tempDirPath = path.join(tempDir, 'temp');
      expect(fs.existsSync(tempDirPath)).toBe(true);
      expect(fs.statSync(tempDirPath).isDirectory()).toBe(true);
    });
    
    it('should use an existing temporary directory if it exists', () => {
      // Create a directory and some file
      const existingTempDir = path.join(tempDir, 'existing-temp');
      fs.mkdirSync(existingTempDir, { recursive: true });
      
      const markerFile = path.join(existingTempDir, 'marker.txt');
      fs.writeFileSync(markerFile, 'This is a marker file');
      
      // Create a file system with the existing temp dir
      const existingFs = new FileSystem(logger, existingTempDir);
      
      // Should not delete the existing content
      expect(fs.existsSync(markerFile)).toBe(true);
    });
  });
  
  describe('file operations', () => {
    it('should read file contents', async () => {
      // Create a test file
      const filePath = path.join(tempDir, 'test-read.txt');
      const content = 'Test file content for reading';
      fs.writeFileSync(filePath, content);
      
      // Read the file
      const readContent = await fileSystem.readFile(filePath);
      
      // Should match the written content
      expect(readContent).toBe(content);
    });
    
    it('should write file contents', async () => {
      const filePath = path.join(tempDir, 'test-write.txt');
      const content = 'Test file content for writing';
      
      // Write to the file
      await fileSystem.writeFile(filePath, content);
      
      // Read back using Node.js fs
      const readContent = fs.readFileSync(filePath, 'utf8');
      
      // Should match the written content
      expect(readContent).toBe(content);
    });
    
    it('should check if a file exists', async () => {
      // Create a test file
      const filePath = path.join(tempDir, 'test-exists.txt');
      fs.writeFileSync(filePath, 'File exists');
      
      // Non-existent file
      const nonExistentPath = path.join(tempDir, 'non-existent.txt');
      
      // Check existence
      const exists = await fileSystem.fileExists(filePath);
      const notExists = await fileSystem.fileExists(nonExistentPath);
      
      // Should return correct results
      expect(exists).toBe(true);
      expect(notExists).toBe(false);
    });
    
    it('should delete files', async () => {
      // Create a test file
      const filePath = path.join(tempDir, 'test-delete.txt');
      fs.writeFileSync(filePath, 'File to delete');
      
      // Verify file exists
      expect(fs.existsSync(filePath)).toBe(true);
      
      // Delete the file
      await fileSystem.deleteFile(filePath);
      
      // File should no longer exist
      expect(fs.existsSync(filePath)).toBe(false);
    });
    
    it('should handle errors for non-existent files when reading', async () => {
      const nonExistentPath = path.join(tempDir, 'non-existent.txt');
      
      // Should reject when trying to read non-existent file
      await expect(fileSystem.readFile(nonExistentPath))
        .rejects.toThrow();
    });
  });
  
  describe('directory operations', () => {
    it('should create directories', async () => {
      const dirPath = path.join(tempDir, 'test-dir');
      
      // Create directory
      await fileSystem.createDirectory(dirPath);
      
      // Directory should exist
      expect(fs.existsSync(dirPath)).toBe(true);
      expect(fs.statSync(dirPath).isDirectory()).toBe(true);
    });
    
    it('should create nested directories', async () => {
      const nestedDirPath = path.join(tempDir, 'nested', 'test', 'dir');
      
      // Create nested directories
      await fileSystem.createDirectory(nestedDirPath);
      
      // Directory should exist
      expect(fs.existsSync(nestedDirPath)).toBe(true);
      expect(fs.statSync(nestedDirPath).isDirectory()).toBe(true);
    });
    
    it('should list directory contents', async () => {
      // Create a directory with files and subdirectories
      const dirPath = path.join(tempDir, 'list-dir');
      fs.mkdirSync(dirPath, { recursive: true });
      
      // Create some files
      fs.writeFileSync(path.join(dirPath, 'file1.txt'), 'File 1');
      fs.writeFileSync(path.join(dirPath, 'file2.txt'), 'File 2');
      
      // Create a subdirectory
      fs.mkdirSync(path.join(dirPath, 'subdir'), { recursive: true });
      
      // List the directory
      const contents = await fileSystem.listDirectory(dirPath);
      
      // Should contain both files and the subdirectory
      expect(contents).toHaveLength(3);
      expect(contents).toContain('file1.txt');
      expect(contents).toContain('file2.txt');
      expect(contents).toContain('subdir');
    });
  });
  
  describe('path operations', () => {
    it('should resolve relative paths to absolute paths', () => {
      const relativePath = 'some/relative/path';
      
      // Should convert to absolute path
      const absolutePath = fileSystem.resolvePath(relativePath);
      
      // Should be an absolute path
      expect(path.isAbsolute(absolutePath)).toBe(true);
      expect(absolutePath).toContain(relativePath);
    });
    
    it('should leave absolute paths unchanged', () => {
      const absolutePath = path.join(tempDir, 'absolute/path');
      
      // Should not modify absolute path
      const resolvedPath = fileSystem.resolvePath(absolutePath);
      
      // Should be the same path
      expect(resolvedPath).toBe(absolutePath);
    });
    
    it('should expand home directory tildes', () => {
      const homeRelativePath = '~/some/path';
      
      // Should replace ~ with home directory
      const expandedPath = fileSystem.resolvePath(homeRelativePath);
      
      // Should be an absolute path without ~
      expect(path.isAbsolute(expandedPath)).toBe(true);
      expect(expandedPath).not.toContain('~');
      expect(expandedPath).toContain('some/path');
    });
  });
  
  describe('temporary file operations', () => {
    it('should create temporary files', async () => {
      // Create a temporary file
      const { path: tempFilePath, cleanup } = await fileSystem.createTempFile('test-', '.txt');
      
      // File should exist
      expect(fs.existsSync(tempFilePath)).toBe(true);
      
      // Path should include prefix and suffix
      expect(path.basename(tempFilePath)).toMatch(/^test-.*\.txt$/);
      
      // Clean up the file
      await cleanup();
      
      // File should no longer exist
      expect(fs.existsSync(tempFilePath)).toBe(false);
    });
    
    it('should write content to temporary files', async () => {
      const content = 'Temporary file content';
      
      // Create a temporary file with content
      const { path: tempFilePath, cleanup } = await fileSystem.createTempFile(
        'content-', '.txt', content
      );
      
      // File should exist with the content
      expect(fs.existsSync(tempFilePath)).toBe(true);
      expect(fs.readFileSync(tempFilePath, 'utf8')).toBe(content);
      
      // Clean up the file
      await cleanup();
    });
    
    it('should create temporary directories', async () => {
      // Create a temporary directory
      const { path: tempDirPath, cleanup } = await fileSystem.createTempDirectory('test-dir-');
      
      // Directory should exist
      expect(fs.existsSync(tempDirPath)).toBe(true);
      expect(fs.statSync(tempDirPath).isDirectory()).toBe(true);
      
      // Path should include prefix
      expect(path.basename(tempDirPath)).toMatch(/^test-dir-/);
      
      // Clean up the directory
      await cleanup();
      
      // Directory should no longer exist
      expect(fs.existsSync(tempDirPath)).toBe(false);
    });
  });
  
  describe('pattern matching', () => {
    beforeEach(() => {
      // Create a directory structure for pattern matching tests
      const testDir = path.join(tempDir, 'pattern-test');
      fs.mkdirSync(testDir, { recursive: true });
      
      // Create nested directories and files
      fs.mkdirSync(path.join(testDir, 'src'), { recursive: true });
      fs.mkdirSync(path.join(testDir, 'src', 'components'), { recursive: true });
      fs.mkdirSync(path.join(testDir, 'src', 'utils'), { recursive: true });
      
      // Create some files
      fs.writeFileSync(path.join(testDir, 'src', 'index.ts'), '// Index file');
      fs.writeFileSync(path.join(testDir, 'src', 'components', 'Button.tsx'), '// Button component');
      fs.writeFileSync(path.join(testDir, 'src', 'components', 'Card.tsx'), '// Card component');
      fs.writeFileSync(path.join(testDir, 'src', 'utils', 'format.ts'), '// Format utility');
      fs.writeFileSync(path.join(testDir, 'src', 'utils', 'logger.ts'), '// Logger utility');
      fs.writeFileSync(path.join(testDir, 'package.json'), '{ "name": "test" }');
      fs.writeFileSync(path.join(testDir, 'README.md'), '# Test Project');
    });
    
    it('should find files matching a glob pattern', async () => {
      const testDir = path.join(tempDir, 'pattern-test');
      
      // Find all TypeScript files
      const tsFiles = await fileSystem.findFiles(testDir, '**/*.ts');
      
      // Should find 3 .ts files
      expect(tsFiles).toHaveLength(3);
      expect(tsFiles.some(file => file.endsWith('index.ts'))).toBe(true);
      expect(tsFiles.some(file => file.endsWith('format.ts'))).toBe(true);
      expect(tsFiles.some(file => file.endsWith('logger.ts'))).toBe(true);
      
      // Find all TSX files
      const tsxFiles = await fileSystem.findFiles(testDir, '**/*.tsx');
      
      // Should find 2 .tsx files
      expect(tsxFiles).toHaveLength(2);
      expect(tsxFiles.some(file => file.endsWith('Button.tsx'))).toBe(true);
      expect(tsxFiles.some(file => file.endsWith('Card.tsx'))).toBe(true);
    });
    
    it('should find files in specific directories', async () => {
      const testDir = path.join(tempDir, 'pattern-test');
      
      // Find files in the utils directory
      const utilsFiles = await fileSystem.findFiles(testDir, 'src/utils/**/*');
      
      // Should find 2 files in utils
      expect(utilsFiles).toHaveLength(2);
      expect(utilsFiles.some(file => file.endsWith('format.ts'))).toBe(true);
      expect(utilsFiles.some(file => file.endsWith('logger.ts'))).toBe(true);
    });
    
    it('should search file contents with grep', async () => {
      const testDir = path.join(tempDir, 'pattern-test');
      
      // Create files with specific content for grepping
      fs.writeFileSync(
        path.join(testDir, 'src', 'utils', 'helpers.ts'),
        'export function formatDate(date: Date) { return date.toISOString(); }'
      );
      
      fs.writeFileSync(
        path.join(testDir, 'src', 'components', 'DatePicker.tsx'),
        'import { formatDate } from "../utils/helpers";\nexport function DatePicker() { /* ... */ }'
      );
      
      // Search for files containing 'formatDate'
      const matches = await fileSystem.grepFiles(testDir, 'formatDate');
      
      // Should find 2 files with 'formatDate'
      expect(matches).toHaveLength(2);
      expect(matches.some(file => file.endsWith('helpers.ts'))).toBe(true);
      expect(matches.some(file => file.endsWith('DatePicker.tsx'))).toBe(true);
    });
  });
  
  describe('error handling', () => {
    it('should handle file operation errors gracefully', async () => {
      // Create a file with no read permissions
      const restrictedFile = path.join(tempDir, 'restricted.txt');
      fs.writeFileSync(restrictedFile, 'Restricted content');
      
      // Make it read-only for owner (not writable)
      fs.chmodSync(restrictedFile, 0o444);
      
      // Should handle write permission error
      await expect(fileSystem.writeFile(restrictedFile, 'New content'))
        .rejects.toThrow();
      
      // Should log the error
      // This is hard to test directly with the logger, but we can check the file wasn't modified
      expect(fs.readFileSync(restrictedFile, 'utf8')).toBe('Restricted content');
      
      // Reset permissions for clean up
      fs.chmodSync(restrictedFile, 0o644);
    });
    
    it('should handle directory operation errors', async () => {
      if (process.platform !== 'win32') { // Skip on Windows
        // Create a directory with no write permissions
        const restrictedDir = path.join(tempDir, 'restricted-dir');
        fs.mkdirSync(restrictedDir, { recursive: true });
        
        // Make it read-only
        fs.chmodSync(restrictedDir, 0o555);
        
        // Should handle permission error when creating file inside
        const filePath = path.join(restrictedDir, 'new-file.txt');
        await expect(fileSystem.writeFile(filePath, 'Content'))
          .rejects.toThrow();
        
        // Reset permissions for clean up
        fs.chmodSync(restrictedDir, 0o755);
      }
    });
  });
});