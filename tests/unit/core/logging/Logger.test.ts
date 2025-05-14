import { Logger, LogLevel, LoggerConfig } from '../../../../src/core/logging/Logger';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

describe('Logger', () => {
  let tempDir: string;
  let logFilePath: string;
  
  // Spy on console methods
  const consoleInfoSpy = jest.spyOn(console, 'info').mockImplementation(() => {});
  const consoleDebugSpy = jest.spyOn(console, 'debug').mockImplementation(() => {});
  const consoleWarnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
  const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
  
  beforeAll(() => {
    // Create a temporary directory for testing log files
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ingestor-test-logs-'));
    logFilePath = path.join(tempDir, 'test-log.log');
  });
  
  afterAll(() => {
    // Clean up the temporary directory
    try {
      fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (error) {
      console.error(`Error cleaning up temporary directory: ${error}`);
    }
    
    // Restore console methods
    consoleInfoSpy.mockRestore();
    consoleDebugSpy.mockRestore();
    consoleWarnSpy.mockRestore();
    consoleErrorSpy.mockRestore();
  });
  
  beforeEach(() => {
    // Clear mocks between tests
    consoleInfoSpy.mockClear();
    consoleDebugSpy.mockClear();
    consoleWarnSpy.mockClear();
    consoleErrorSpy.mockClear();
    
    // Remove any existing log file
    if (fs.existsSync(logFilePath)) {
      fs.unlinkSync(logFilePath);
    }
  });
  
  describe('initialization', () => {
    it('should initialize with default settings', () => {
      const logger = new Logger('test');
      
      expect(logger).toBeDefined();
      expect((logger as any).modulePrefix).toBe('test');
      expect((logger as any).config.level).toBe(LogLevel.INFO);
      expect((logger as any).config.console).toBe(true);
    });
    
    it('should initialize with custom settings', () => {
      const config: LoggerConfig = {
        level: LogLevel.DEBUG,
        console: false,
        file: logFilePath,
        timestamps: true,
        structured: true
      };
      
      const logger = new Logger('custom', config);
      
      expect(logger).toBeDefined();
      expect((logger as any).config.level).toBe(LogLevel.DEBUG);
      expect((logger as any).config.console).toBe(false);
      expect((logger as any).config.file).toBe(logFilePath);
    });
  });
  
  describe('log methods', () => {
    it('should log info messages', () => {
      const logger = new Logger('test');
      
      logger.info('Info message');
      
      // Should use console.info
      expect(consoleInfoSpy).toHaveBeenCalled();
      expect(consoleInfoSpy.mock.calls[0][0]).toContain('[test]');
      expect(consoleInfoSpy.mock.calls[0][0]).toContain('Info message');
    });
    
    it('should log debug messages', () => {
      const logger = new Logger('test', { level: LogLevel.DEBUG });
      
      logger.debug('Debug message');
      
      // Should use console.debug
      expect(consoleDebugSpy).toHaveBeenCalled();
      expect(consoleDebugSpy.mock.calls[0][0]).toContain('[test]');
      expect(consoleDebugSpy.mock.calls[0][0]).toContain('Debug message');
    });
    
    it('should log warning messages', () => {
      const logger = new Logger('test');
      
      logger.warn('Warning message');
      
      // Should use console.warn
      expect(consoleWarnSpy).toHaveBeenCalled();
      expect(consoleWarnSpy.mock.calls[0][0]).toContain('[test]');
      expect(consoleWarnSpy.mock.calls[0][0]).toContain('Warning message');
    });
    
    it('should log error messages', () => {
      const logger = new Logger('test');
      
      logger.error('Error message');
      
      // Should use console.error
      expect(consoleErrorSpy).toHaveBeenCalled();
      expect(consoleErrorSpy.mock.calls[0][0]).toContain('[test]');
      expect(consoleErrorSpy.mock.calls[0][0]).toContain('Error message');
    });
    
    it('should include timestamps when configured', () => {
      const logger = new Logger('test', { timestamps: true });
      
      logger.info('Message with timestamp');
      
      // Check for timestamp format (e.g., [2023-05-13T12:34:56.789Z])
      expect(consoleInfoSpy.mock.calls[0][0]).toMatch(/\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z\]/);
    });
    
    it('should log additional data objects', () => {
      const logger = new Logger('test');
      const data = { user: 'test', id: 123 };
      
      logger.info('Message with data', data);
      
      // Should include data object
      expect(consoleInfoSpy).toHaveBeenCalledWith(
        expect.any(String),
        data
      );
    });
  });
  
  describe('log filtering', () => {
    it('should filter debug messages if level is INFO', () => {
      const logger = new Logger('test', { level: LogLevel.INFO });
      
      logger.debug('Debug message that should be filtered');
      
      // Should not log debug message
      expect(consoleDebugSpy).not.toHaveBeenCalled();
    });
    
    it('should filter info messages if level is WARN', () => {
      const logger = new Logger('test', { level: LogLevel.WARN });
      
      logger.info('Info message that should be filtered');
      logger.warn('Warning message that should be logged');
      
      // Should not log info message
      expect(consoleInfoSpy).not.toHaveBeenCalled();
      
      // But should log warning message
      expect(consoleWarnSpy).toHaveBeenCalled();
    });
    
    it('should filter all but error messages if level is ERROR', () => {
      const logger = new Logger('test', { level: LogLevel.ERROR });
      
      logger.debug('Debug message that should be filtered');
      logger.info('Info message that should be filtered');
      logger.warn('Warning message that should be filtered');
      logger.error('Error message that should be logged');
      
      // Should not log debug, info, or warn messages
      expect(consoleDebugSpy).not.toHaveBeenCalled();
      expect(consoleInfoSpy).not.toHaveBeenCalled();
      expect(consoleWarnSpy).not.toHaveBeenCalled();
      
      // But should log error message
      expect(consoleErrorSpy).toHaveBeenCalled();
    });
  });
  
  describe('file logging', () => {
    it('should log to a file when configured', () => {
      const logger = new Logger('test', { file: logFilePath });
      
      logger.info('File log test');
      
      // File should exist
      expect(fs.existsSync(logFilePath)).toBe(true);
      
      // File should contain the log message
      const logContent = fs.readFileSync(logFilePath, 'utf8');
      expect(logContent).toContain('[test]');
      expect(logContent).toContain('File log test');
    });
    
    it('should append to existing log file', () => {
      const logger = new Logger('test', { file: logFilePath });
      
      // Write first log message
      logger.info('First message');
      
      // Write second log message
      logger.info('Second message');
      
      // File should contain both messages
      const logContent = fs.readFileSync(logFilePath, 'utf8');
      expect(logContent).toContain('First message');
      expect(logContent).toContain('Second message');
    });
    
    it('should write structured logs in JSON format when configured', () => {
      const logger = new Logger('test', { 
        file: logFilePath,
        structured: true
      });
      
      const data = { user: 'test', id: 123 };
      logger.info('Structured log test', data);
      
      // File should exist
      expect(fs.existsSync(logFilePath)).toBe(true);
      
      // File should contain valid JSON
      const logContent = fs.readFileSync(logFilePath, 'utf8');
      const logLines = logContent.trim().split('\n');
      
      // Should have one line
      expect(logLines.length).toBe(1);
      
      // Should be valid JSON
      const parsedLog = JSON.parse(logLines[0]);
      expect(parsedLog).toHaveProperty('module', 'test');
      expect(parsedLog).toHaveProperty('level', 'info');
      expect(parsedLog).toHaveProperty('message', 'Structured log test');
      expect(parsedLog).toHaveProperty('data');
      expect(parsedLog.data).toEqual(data);
    });
  });
});