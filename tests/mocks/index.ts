import { Logger } from '../../src/core/logging/Logger';
import { EntityType, Entity, EntityMention, EntityExtractionResult } from '../../src/core/entity/types/EntityTypes';
import { ClaudeService } from '../../src/core/services/ClaudeService';
import { FileSystem } from '../../src/core/utils/FileSystem';

// Mock logger that doesn't output anything but records calls
export class MockLogger extends Logger {
  public logs: { level: string; message: string; data?: any }[] = [];
  
  constructor() {
    super('test');
    
    // Override all log methods to capture calls without output
    this.debug = jest.fn((message: string, data?: any) => {
      this.logs.push({ level: 'debug', message, data });
    });
    
    this.info = jest.fn((message: string, data?: any) => {
      this.logs.push({ level: 'info', message, data });
    });
    
    this.warn = jest.fn((message: string, data?: any) => {
      this.logs.push({ level: 'warn', message, data });
    });
    
    this.error = jest.fn((message: string, data?: any) => {
      this.logs.push({ level: 'error', message, data });
    });
  }
  
  clearLogs() {
    this.logs = [];
  }
}

// Mock Claude service for testing
export class MockClaudeService extends ClaudeService {
  public calls: { method: string; args: any[] }[] = [];
  
  constructor() {
    super(new MockLogger());
    
    // Mock the extractEntities method
    this.extractEntities = jest.fn(async (content: string, contentType: string) => {
      this.calls.push({
        method: 'extractEntities',
        args: [content, contentType]
      });
      
      // Return mock entities based on content
      return this.getMockEntities(content);
    });
  }
  
  private getMockEntities(content: string): EntityExtractionResult {
    // Generate mock entities based on input content
    const entities: Entity[] = [];
    
    // Add a person entity if content contains "John"
    if (content.includes('John')) {
      entities.push({
        name: 'John Doe',
        type: EntityType.PERSON,
        mentions: [
          {
            text: 'John',
            offset: content.indexOf('John'),
            length: 4,
            confidence: 0.95
          }
        ]
      });
    }
    
    // Add an organization entity if content contains "Acme"
    if (content.includes('Acme')) {
      entities.push({
        name: 'Acme Corporation',
        type: EntityType.ORGANIZATION,
        mentions: [
          {
            text: 'Acme',
            offset: content.indexOf('Acme'),
            length: 4,
            confidence: 0.92
          }
        ]
      });
    }
    
    // Add a location entity if content contains "New York"
    if (content.includes('New York')) {
      entities.push({
        name: 'New York City',
        type: EntityType.LOCATION,
        mentions: [
          {
            text: 'New York',
            offset: content.indexOf('New York'),
            length: 8,
            confidence: 0.97
          }
        ]
      });
    }
    
    return {
      entities,
      processingTime: 42, // Mock processing time
      confidence: 0.9,
      contentLength: content.length
    };
  }
  
  clearCalls() {
    this.calls = [];
  }
}

// Mock filesystem for testing
export class MockFileSystem extends FileSystem {
  public calls: { method: string; args: any[] }[] = [];
  public mockFiles: Map<string, string> = new Map();
  
  constructor() {
    super(new MockLogger());
    
    // Mock file operations
    this.readFile = jest.fn(async (filePath: string) => {
      this.calls.push({
        method: 'readFile',
        args: [filePath]
      });
      
      if (this.mockFiles.has(filePath)) {
        return this.mockFiles.get(filePath) as string;
      }
      
      throw new Error(`Mock file not found: ${filePath}`);
    });
    
    this.writeFile = jest.fn(async (filePath: string, content: string) => {
      this.calls.push({
        method: 'writeFile',
        args: [filePath, content]
      });
      
      this.mockFiles.set(filePath, content);
    });
    
    this.fileExists = jest.fn(async (filePath: string) => {
      this.calls.push({
        method: 'fileExists',
        args: [filePath]
      });
      
      return this.mockFiles.has(filePath);
    });
  }
  
  // Add a mock file
  addMockFile(filePath: string, content: string) {
    this.mockFiles.set(filePath, content);
  }
  
  // Clear tracking
  clearCalls() {
    this.calls = [];
  }
}

// Create test fixtures
export const createTestEntity = (
  name: string = 'Test Entity',
  type: EntityType = EntityType.ORGANIZATION,
  mentions: EntityMention[] = []
): Entity => {
  return {
    name,
    type,
    mentions: mentions.length > 0 ? mentions : [
      {
        text: name,
        offset: 0,
        length: name.length,
        confidence: 0.9
      }
    ]
  };
};

export const createTestMention = (
  text: string = 'mention',
  offset: number = 0,
  confidence: number = 0.9
): EntityMention => {
  return {
    text,
    offset,
    length: text.length,
    confidence
  };
};