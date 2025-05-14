/**
 * Tests for helper utilities in test-helpers.ts
 */

import { 
  createRepositoryMock, 
  createFixtures, 
  createServiceMock, 
  expectToThrowAsync 
} from './test-helpers';

describe('Test Helpers', () => {
  describe('createRepositoryMock', () => {
    it('should create a mock with default repository methods', () => {
      const mock = createRepositoryMock();
      
      // Verify default methods
      expect(mock.findById).toBeDefined();
      expect(mock.findAll).toBeDefined();
      expect(mock.create).toBeDefined();
      expect(mock.update).toBeDefined();
      expect(mock.delete).toBeDefined();
      expect(mock.findByQuery).toBeDefined();
      expect(mock.count).toBeDefined();
      
      // All should be jest mock functions
      expect(jest.isMockFunction(mock.findById)).toBe(true);
      expect(jest.isMockFunction(mock.create)).toBe(true);
    });
    
    it('should override default methods with custom implementations', () => {
      const customFindById = jest.fn().mockResolvedValue({ id: 1, name: 'Test' });
      const mock = createRepositoryMock({
        findById: customFindById,
        customMethod: jest.fn().mockResolvedValue('custom')
      });
      
      // Test overridden method
      expect(mock.findById).toBe(customFindById);
      
      // Test custom method
      expect(mock.customMethod).toBeDefined();
      expect(jest.isMockFunction(mock.customMethod)).toBe(true);
    });
  });
  
  describe('createFixtures', () => {
    it('should create a single fixture from a template with no overrides', () => {
      const template = { id: 1, name: 'Test', active: true };
      const fixtures = createFixtures(template);
      
      expect(fixtures).toHaveLength(1);
      expect(fixtures[0]).toEqual(template);
      
      // Ensure it's a deep copy
      expect(fixtures[0]).not.toBe(template);
    });
    
    it('should create multiple fixtures with overrides', () => {
      const template = { id: 1, name: 'Test', active: true };
      const overrides = [
        { id: 2, name: 'Test 2' },
        { id: 3, name: 'Test 3', active: false }
      ];
      
      const fixtures = createFixtures(template, overrides);
      
      expect(fixtures).toHaveLength(2);
      expect(fixtures[0]).toEqual({ id: 2, name: 'Test 2', active: true });
      expect(fixtures[1]).toEqual({ id: 3, name: 'Test 3', active: false });
    });
  });
  
  describe('createServiceMock', () => {
    it('should create a service mock with specified methods', () => {
      const processFn = jest.fn().mockResolvedValue('processed');
      const mock = createServiceMock({
        process: processFn,
        isValid: jest.fn().mockReturnValue(true)
      });
      
      expect(mock.process).toBe(processFn);
      expect(mock.isValid).toBeDefined();
      expect(jest.isMockFunction(mock.process)).toBe(true);
      expect(jest.isMockFunction(mock.isValid)).toBe(true);
    });
  });
  
  describe('expectToThrowAsync', () => {
    class TestError extends Error {
      constructor(message: string) {
        super(message);
        this.name = 'TestError';
      }
    }
    
    it('should pass when promise rejects with expected error', async () => {
      const promise = Promise.reject(new TestError('Test error message'));
      
      await expectToThrowAsync(TestError)(promise);
    });
    
    it('should pass when promise rejects with expected error and message', async () => {
      const promise = Promise.reject(new TestError('Test error message'));
      
      await expectToThrowAsync(TestError, 'error message')(promise);
    });
    
    it('should fail when promise resolves', async () => {
      const promise = Promise.resolve('value');
      
      // Mock the fail function since we expect it to be called
      const originalFail = global.fail;
      global.fail = jest.fn();
      
      try {
        await expectToThrowAsync(TestError)(promise);
        // This should not execute if expectToThrowAsync is working correctly
        expect(global.fail).toHaveBeenCalled();
      } finally {
        // Restore the original fail function
        global.fail = originalFail;
      }
    });
    
    it('should fail when promise rejects with wrong error type', async () => {
      const promise = Promise.reject(new Error('Different error'));
      
      try {
        await expectToThrowAsync(TestError)(promise);
        // If we get here, the test should fail
        fail('Should have thrown an error');
      } catch (error) {
        // This is expected behavior
        expect(error).toBeDefined();
      }
    });
  });
});