/**
 * Tests for the database mock
 */

import { createMockDatabase } from './db-mock';

describe('Database Mock', () => {
  let mockDb: ReturnType<typeof createMockDatabase>;
  
  beforeEach(() => {
    mockDb = createMockDatabase();
  });
  
  afterEach(() => {
    mockDb.reset();
  });
  
  it('should mock CREATE TABLE statements', () => {
    mockDb.db.exec?.('CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)');
    
    expect(mockDb.mockData).toHaveProperty('users');
    expect(mockDb.mockData.users).toEqual({});
  });
  
  it('should mock INSERT statements', () => {
    mockDb.db.exec?.('CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)');
    
    const stmt = mockDb.db.prepare?.('INSERT INTO users VALUES (?, ?, ?)');
    const user = { id: 'user1', name: 'Test User', email: 'test@example.com' };
    
    stmt?.run(user);
    
    expect(mockDb.mockData.users).toHaveProperty('user1');
    expect(mockDb.mockData.users.user1).toEqual(user);
  });
  
  it('should mock SELECT statements', () => {
    // Create table and insert data
    mockDb.db.exec?.('CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)');
    const insertStmt = mockDb.db.prepare?.('INSERT INTO users VALUES (?, ?, ?)');
    const user1 = { id: 'user1', name: 'Test User 1', email: 'test1@example.com' };
    const user2 = { id: 'user2', name: 'Test User 2', email: 'test2@example.com' };
    
    insertStmt?.run(user1);
    insertStmt?.run(user2);
    
    // Test SELECT all
    const selectAllStmt = mockDb.db.prepare?.('SELECT * FROM users');
    const allUsers = selectAllStmt?.all();
    
    expect(allUsers).toHaveLength(2);
    expect(allUsers).toContainEqual(user1);
    expect(allUsers).toContainEqual(user2);
    
    // Test SELECT with id
    const selectByIdStmt = mockDb.db.prepare?.('SELECT * FROM users WHERE id = ?');
    const user = selectByIdStmt?.get({ id: 'user1' });
    
    expect(user).toEqual(user1);
  });
  
  it('should mock UPDATE statements', () => {
    // Create table and insert data
    mockDb.db.exec?.('CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)');
    const insertStmt = mockDb.db.prepare?.('INSERT INTO users VALUES (?, ?, ?)');
    const user = { id: 'user1', name: 'Original Name', email: 'original@example.com' };
    
    insertStmt?.run(user);
    
    // Test UPDATE
    const updateStmt = mockDb.db.prepare?.('UPDATE users SET name = ?, email = ? WHERE id = ?');
    const updatedData = { id: 'user1', name: 'Updated Name', email: 'updated@example.com' };
    const result = updateStmt?.run(updatedData);
    
    expect(result).toHaveProperty('changes', 1);
    expect(mockDb.mockData.users.user1).toEqual(updatedData);
  });
  
  it('should mock DELETE statements', () => {
    // Create table and insert data
    mockDb.db.exec?.('CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)');
    const insertStmt = mockDb.db.prepare?.('INSERT INTO users VALUES (?, ?, ?)');
    const user1 = { id: 'user1', name: 'Test User 1', email: 'test1@example.com' };
    const user2 = { id: 'user2', name: 'Test User 2', email: 'test2@example.com' };
    
    insertStmt?.run(user1);
    insertStmt?.run(user2);
    
    // Test DELETE
    const deleteStmt = mockDb.db.prepare?.('DELETE FROM users WHERE id = ?');
    const result = deleteStmt?.run({ id: 'user1' });
    
    expect(result).toHaveProperty('changes', 1);
    expect(mockDb.mockData.users).not.toHaveProperty('user1');
    expect(mockDb.mockData.users).toHaveProperty('user2');
  });
  
  it('should handle reset', () => {
    // Create table and insert data
    mockDb.db.exec?.('CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)');
    const insertStmt = mockDb.db.prepare?.('INSERT INTO users VALUES (?, ?, ?)');
    insertStmt?.run({ id: 'user1', name: 'Test User', email: 'test@example.com' });
    
    // Verify data exists
    expect(mockDb.mockData.users).toHaveProperty('user1');
    
    // Reset mock database
    mockDb.reset();
    
    // Verify data is cleared
    expect(mockDb.mockData).toEqual({});
  });
});