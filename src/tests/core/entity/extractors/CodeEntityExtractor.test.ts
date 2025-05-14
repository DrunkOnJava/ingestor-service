/**
 * Unit tests for the CodeEntityExtractor
 */

import { CodeEntityExtractor } from '../../../../core/entity/extractors/CodeEntityExtractor';
import { Entity, EntityExtractionOptions, EntityType } from '../../../../core/entity/types';
import { ClaudeService } from '../../../../core/services/ClaudeService';
import { Logger } from '../../../../core/logging';
import { FileSystem } from '../../../../core/utils/FileSystem';
import { createClaudeMock } from '../../../mocks/claude-mock';
import { createFileSystemMock } from '../../../mocks/filesystem-mock';

// Mock dependencies
jest.mock('../../../../core/services/ClaudeService');
jest.mock('../../../../core/logging/Logger');
jest.mock('../../../../core/utils/FileSystem');

describe('CodeEntityExtractor', () => {
  let extractor: CodeEntityExtractor;
  let mockLogger: jest.Mocked<Logger>;
  let mockClaudeService: jest.Mocked<ClaudeService>;
  let mockFileSystem: jest.Mocked<FileSystem>;
  
  // Sample code for testing
  const jsCode = `
import React, { useState, useEffect } from 'react';
import axios from 'axios';

// Constants
const API_URL = 'https://api.example.com';
const MAX_RETRIES = 3;

/**
 * UserList component that displays a list of users
 */
function UserList({ initialUsers = [] }) {
  const [users, setUsers] = useState(initialUsers);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  
  useEffect(() => {
    const fetchUsers = async () => {
      setLoading(true);
      try {
        const response = await axios.get(\`\${API_URL}/users\`);
        setUsers(response.data);
        setError(null);
      } catch (err) {
        setError('Failed to fetch users');
        console.error(err);
      } finally {
        setLoading(false);
      }
    };
    
    fetchUsers();
  }, []);
  
  return (
    <div className="user-list">
      <h2>User List</h2>
      {loading && <p>Loading...</p>}
      {error && <p className="error">{error}</p>}
      <ul>
        {users.map(user => (
          <li key={user.id}>{user.name}</li>
        ))}
      </ul>
    </div>
  );
}

export default UserList;
  `;

  const pythonCode = `
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

# Constants
DATA_PATH = './data/processed/dataset.csv'
RANDOM_STATE = 42

class ModelTrainer:
    def __init__(self, data_path=DATA_PATH):
        self.data_path = data_path
        self.model = None
        self.X_train = None
        self.X_test = None
        self.y_train = None
        self.y_test = None
    
    def load_data(self):
        """Load the dataset and prepare it for training"""
        df = pd.read_csv(self.data_path)
        X = df.drop('target', axis=1)
        y = df['target']
        
        self.X_train, self.X_test, self.y_train, self.y_test = train_test_split(
            X, y, test_size=0.2, random_state=RANDOM_STATE
        )
        
        return self
    
    def train(self, n_estimators=100):
        """Train a Random Forest classifier"""
        self.model = RandomForestClassifier(n_estimators=n_estimators, random_state=RANDOM_STATE)
        self.model.fit(self.X_train, self.y_train)
        return self
    
    def evaluate(self):
        """Evaluate the model and return accuracy"""
        predictions = self.model.predict(self.X_test)
        accuracy = accuracy_score(self.y_test, predictions)
        return accuracy

if __name__ == "__main__":
    trainer = ModelTrainer()
    trainer.load_data().train()
    accuracy = trainer.evaluate()
    print(f"Model accuracy: {accuracy:.4f}")
  `;

  beforeEach(() => {
    // Set up mocks
    mockLogger = {
      debug: jest.fn(),
      info: jest.fn(),
      warning: jest.fn(),
      error: jest.fn()
    } as unknown as jest.Mocked<Logger>;

    // Use Claude mock
    const claudeMock = createClaudeMock();
    mockClaudeService = {
      analyze: jest.fn(claudeMock.extractEntities)
    } as unknown as jest.Mocked<ClaudeService>;

    // Use FileSystem mock
    mockFileSystem = createFileSystemMock() as unknown as jest.Mocked<FileSystem>;

    // Initialize extractor with mocks
    extractor = new CodeEntityExtractor(
      mockLogger,
      {},
      mockClaudeService,
      mockFileSystem
    );
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('constructor', () => {
    it('should initialize with default options', () => {
      const basicExtractor = new CodeEntityExtractor(mockLogger);
      expect(basicExtractor).toBeDefined();
    });

    it('should initialize with custom options', () => {
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.8,
        maxEntities: 20
      };
      
      const customExtractor = new CodeEntityExtractor(mockLogger, options);
      expect(customExtractor).toBeDefined();
    });
  });

  describe('extract', () => {
    it('should handle empty content', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      
      const result = await extractor.extract('', 'text/javascript');
      
      expect(result.success).toBe(false);
      expect(result.error).toBe('Empty code content');
      expect(result.entities).toHaveLength(0);
    });

    it('should read from file if content is a file path', async () => {
      const filePath = '/path/to/test.js';
      
      mockFileSystem.isFile.mockResolvedValue(true);
      mockFileSystem.readFile.mockResolvedValue(jsCode);
      
      const mockEntities = [
        {
          name: 'UserList',
          type: EntityType.TECHNOLOGY,
          mentions: [{ context: 'function UserList', position: 10, relevance: 0.9 }]
        },
        {
          name: 'React',
          type: EntityType.TECHNOLOGY,
          mentions: [{ context: 'import React', position: 1, relevance: 0.85 }]
        }
      ];
      
      mockClaudeService.analyze.mockResolvedValue({
        entities: mockEntities,
        success: true
      });
      
      const result = await extractor.extract(filePath, 'text/javascript');
      
      expect(mockFileSystem.isFile).toHaveBeenCalledWith(filePath);
      expect(mockFileSystem.readFile).toHaveBeenCalledWith(filePath);
      expect(result.success).toBe(true);
      expect(result.entities).toEqual(mockEntities);
    });

    it('should detect JavaScript language from file path', async () => {
      const filePath = '/path/to/test.js';
      
      mockFileSystem.isFile.mockResolvedValue(true);
      mockFileSystem.readFile.mockResolvedValue(jsCode);
      
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(filePath, 'text/javascript');
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          language: 'javascript'
        })
      );
    });

    it('should detect Python language from file path', async () => {
      const filePath = '/path/to/script.py';
      
      mockFileSystem.isFile.mockResolvedValue(true);
      mockFileSystem.readFile.mockResolvedValue(pythonCode);
      
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(filePath, 'text/x-python');
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          language: 'python'
        })
      );
    });

    it('should detect language from code content when extension is unknown', async () => {
      const noExtensionPath = '/path/to/script';
      
      mockFileSystem.isFile.mockResolvedValue(true);
      mockFileSystem.readFile.mockResolvedValue(pythonCode);
      
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(noExtensionPath, 'text/plain');
      
      // The content detection should identify this as Python code
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          language: expect.stringMatching(/python/i)
        })
      );
    });

    it('should fall back to rule-based extraction when Claude fails', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockRejectedValue(new Error('Claude API error'));
      
      // Configure the filesystem mock to return JavaScript patterns
      const patterns = {
        'import\\s+[\\w\\s,.{}]*\\s+from\\s+[\'"][^\'"]+[\'"]': ['import React, { useState, useEffect } from \'react\';', 'import axios from \'axios\';'],
        'function\\s+[\\w]+\\s*\\([^)]*\\)': ['function UserList({ initialUsers = [] })'],
        'const\\s+[A-Z_\\d]+\\s*=': ['const API_URL = \'https://api.example.com\';', 'const MAX_RETRIES = 3;']
      };
      
      mockFileSystem.grep.mockImplementation((file, pattern) => {
        return Promise.resolve(patterns[pattern] || []);
      });
      
      mockFileSystem.grepContext.mockResolvedValue('Sample context');
      mockFileSystem.grepLineNumber.mockResolvedValue(1);
      
      const result = await extractor.extract(jsCode, 'text/javascript');
      
      expect(mockLogger.warning).toHaveBeenCalledWith(expect.stringContaining('Claude extraction failed'));
      expect(mockFileSystem.createTempFile).toHaveBeenCalledWith(jsCode);
      expect(mockFileSystem.removeFile).toHaveBeenCalledWith('/tmp/temp_file.txt');
      expect(result.success).toBe(true);
      expect(result.entities.length).toBeGreaterThan(0);
      
      // Check that we found the React import
      const reactEntity = result.entities.find(e => e.name.includes('React'));
      expect(reactEntity).toBeDefined();
      
      // Check that we found the UserList function
      const userListEntity = result.entities.find(e => e.name === 'UserList');
      expect(userListEntity).toBeDefined();
      
      // Check that we found constants
      const apiUrlEntity = result.entities.find(e => e.name.includes('API_URL'));
      expect(apiUrlEntity).toBeDefined();
    });

    it('should extract React components from JavaScript code', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      
      // Configure the filesystem mock to return React component patterns
      const patterns = {
        'function\\s+[A-Z][\\w]*\\s*\\([^)]*\\)\\s*{': ['function UserList({ initialUsers = [] }) {'],
        'const\\s+[A-Z][\\w]*\\s*=\\s*\\([^)]*\\)\\s*=>': []
      };
      
      mockFileSystem.grep.mockImplementation((file, pattern) => {
        return Promise.resolve(patterns[pattern] || []);
      });
      
      mockFileSystem.grepContext.mockResolvedValue('function UserList({ initialUsers = [] }) {');
      mockFileSystem.grepLineNumber.mockResolvedValue(10);
      
      // Force rule-based extraction by making Claude fail
      mockClaudeService.analyze.mockRejectedValue(new Error('Claude API error'));
      
      const result = await extractor.extract(jsCode, 'text/javascript', { language: 'javascript' });
      
      expect(result.success).toBe(true);
      
      // Check that we found the React component
      const componentEntity = result.entities.find(e => 
        e.name === 'UserList' && 
        e.description?.includes('React Component')
      );
      expect(componentEntity).toBeDefined();
      expect(componentEntity?.mentions[0].position).toBe(10);
    });

    it('should extract Python classes and methods', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      
      // Configure the filesystem mock to return Python patterns
      const patterns = {
        'class\\s+[\\w]+': ['class ModelTrainer:'],
        '\\s+def\\s+[\\w_]+\\s*\\(self': ['    def __init__(self, data_path=DATA_PATH):', 
                                        '    def load_data(self):', 
                                        '    def train(self, n_estimators=100):', 
                                        '    def evaluate(self):']
      };
      
      mockFileSystem.grep.mockImplementation((file, pattern) => {
        return Promise.resolve(patterns[pattern] || []);
      });
      
      mockFileSystem.grepContext.mockImplementation((file, match) => {
        if (match.includes('ModelTrainer')) {
          return Promise.resolve('class ModelTrainer:');
        } else if (match.includes('load_data')) {
          return Promise.resolve('def load_data(self):');
        }
        return Promise.resolve(match);
      });
      
      mockFileSystem.grepLineNumber.mockResolvedValue(5);
      
      // Force rule-based extraction by making Claude fail
      mockClaudeService.analyze.mockRejectedValue(new Error('Claude API error'));
      
      const result = await extractor.extract(pythonCode, 'text/x-python', { language: 'python' });
      
      expect(result.success).toBe(true);
      
      // Check that we found the class
      const classEntity = result.entities.find(e => e.name === 'ModelTrainer');
      expect(classEntity).toBeDefined();
      
      // Check that we found the methods
      const methodEntity = result.entities.find(e => e.name === 'load_data');
      expect(methodEntity).toBeDefined();
    });

    it('should filter entities based on options', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      
      const mockEntities = [
        {
          name: 'UserList',
          type: EntityType.TECHNOLOGY,
          mentions: [{ context: 'function UserList', position: 10, relevance: 0.9 }]
        },
        {
          name: 'useState',
          type: EntityType.TECHNOLOGY,
          mentions: [{ context: 'import { useState }', position: 1, relevance: 0.7 }]
        }
      ];
      
      mockClaudeService.analyze.mockResolvedValue({
        entities: mockEntities,
        success: true
      });
      
      const options: EntityExtractionOptions = {
        confidenceThreshold: 0.8
      };
      
      const result = await extractor.extract(jsCode, 'text/javascript', options);
      
      expect(result.success).toBe(true);
      expect(result.entities).toHaveLength(1);
      expect(result.entities[0].name).toBe('UserList');
    });

    it('should include stats in the result', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      const result = await extractor.extract(jsCode, 'text/javascript');
      
      expect(result.success).toBe(true);
      expect(result.stats).toBeDefined();
      expect(result.stats?.processingTimeMs).toBeGreaterThanOrEqual(0);
      expect(result.stats?.entityCount).toBe(0);
    });
  });

  describe('language detection', () => {
    it('should detect JavaScript from content heuristics', async () => {
      const jsSnippet = `
        const hello = () => {
          console.log('Hello world');
        };
        let foo = 'bar';
        var baz = 42;
      `;
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(jsSnippet, 'text/plain');
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          language: 'javascript'
        })
      );
    });

    it('should detect TypeScript from content heuristics', async () => {
      const tsSnippet = `
        interface User {
          id: string;
          name: string;
          age: number;
        }
        
        const getUser = (id: string): User => {
          return { id, name: 'John', age: 30 };
        };
      `;
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(tsSnippet, 'text/plain');
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          language: 'typescript'
        })
      );
    });

    it('should detect Java from content heuristics', async () => {
      const javaSnippet = `
        import java.util.List;
        import java.util.ArrayList;
        
        public class MyClass {
          private String name;
          
          public MyClass(String name) {
            this.name = name;
          }
        }
      `;
      
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(javaSnippet, 'text/plain');
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          language: 'java'
        })
      );
    });
  });

  describe('extractWithClaude', () => {
    it('should handle invalid Claude response format', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({ something: 'not entities' });
      
      const result = await extractor.extract(jsCode, 'text/javascript');
      
      expect(mockLogger.warning).toHaveBeenCalledWith(expect.stringContaining('Claude response did not contain valid entities array'));
      expect(result.entities).toHaveLength(0);
    });

    it('should use code-specific prompt template', async () => {
      mockFileSystem.isFile.mockResolvedValue(false);
      mockClaudeService.analyze.mockResolvedValue({
        entities: [],
        success: true
      });
      
      await extractor.extract(jsCode, 'text/javascript', { language: 'javascript' });
      
      expect(mockClaudeService.analyze).toHaveBeenCalledWith(
        expect.any(String),
        'code',
        expect.objectContaining({
          contentType: 'text/javascript',
          language: 'javascript'
        })
      );
    });
  });
});