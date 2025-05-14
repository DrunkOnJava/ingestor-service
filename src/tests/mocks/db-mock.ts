/**
 * Mock implementation of database for testing
 */

import { Database } from 'better-sqlite3';

// In-memory map to store data for mocked DB
type MockData = {
  [tableName: string]: {
    [id: string]: Record<string, unknown>;
  };
};

/**
 * Creates a mock database interface for testing
 */
export function createMockDatabase(): {
  db: Partial<Database>;
  mockData: MockData;
  reset: () => void;
} {
  // Mock data storage
  let mockData: MockData = {};
  
  // Function to reset the mock data
  const reset = () => {
    mockData = {};
  };
  
  // Mock database implementation
  const db: Partial<Database> = {
    prepare: jest.fn((query: string) => {
      const insertMatch = query.match(/INSERT INTO (\w+)/i);
      const selectMatch = query.match(/SELECT .+ FROM (\w+)/i);
      const updateMatch = query.match(/UPDATE (\w+) SET/i);
      const deleteMatch = query.match(/DELETE FROM (\w+)/i);
      
      if (insertMatch) {
        const tableName = insertMatch[1];
        
        return {
          run: jest.fn((params: Record<string, unknown>) => {
            const id = (params.id || Math.random().toString(36).substring(2, 9)) as string;
            
            if (!mockData[tableName]) {
              mockData[tableName] = {};
            }
            
            mockData[tableName][id] = { ...params };
            
            return { lastInsertRowid: id };
          }),
          all: jest.fn(),
          get: jest.fn()
        };
      }
      
      if (selectMatch) {
        const tableName = selectMatch[1];
        
        return {
          all: jest.fn((params?: Record<string, unknown>) => {
            if (!mockData[tableName]) {
              return [];
            }
            
            return Object.values(mockData[tableName]);
          }),
          get: jest.fn((params?: Record<string, unknown>) => {
            if (!mockData[tableName]) {
              return null;
            }
            
            const id = params?.id;
            if (id && mockData[tableName][id as string]) {
              return mockData[tableName][id as string];
            }
            
            return Object.values(mockData[tableName])[0] || null;
          }),
          run: jest.fn()
        };
      }
      
      if (updateMatch) {
        const tableName = updateMatch[1];
        
        return {
          run: jest.fn((params: Record<string, unknown>) => {
            const id = params.id as string;
            
            if (!mockData[tableName] || !mockData[tableName][id]) {
              return { changes: 0 };
            }
            
            mockData[tableName][id] = { ...mockData[tableName][id], ...params };
            return { changes: 1 };
          }),
          all: jest.fn(),
          get: jest.fn()
        };
      }
      
      if (deleteMatch) {
        const tableName = deleteMatch[1];
        
        return {
          run: jest.fn((params: Record<string, unknown>) => {
            const id = params.id as string;
            
            if (!mockData[tableName] || !mockData[tableName][id]) {
              return { changes: 0 };
            }
            
            delete mockData[tableName][id];
            return { changes: 1 };
          }),
          all: jest.fn(),
          get: jest.fn()
        };
      }
      
      // Default mock
      return {
        run: jest.fn(() => ({ changes: 0 })),
        all: jest.fn(() => []),
        get: jest.fn(() => null)
      };
    }),
    
    exec: jest.fn((query: string) => {
      // Handle create table queries
      const createMatch = query.match(/CREATE TABLE IF NOT EXISTS (\w+)/i);
      if (createMatch) {
        const tableName = createMatch[1];
        if (!mockData[tableName]) {
          mockData[tableName] = {};
        }
      }
      
      return db;
    }),
    
    close: jest.fn()
  };
  
  return {
    db,
    mockData,
    reset
  };
}