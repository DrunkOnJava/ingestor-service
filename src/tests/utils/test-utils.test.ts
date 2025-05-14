/**
 * Tests for utility functions in test-utils.ts
 */

import { isObject, deepClone, createMock } from '../../utils/test-utils';

describe('Test Utilities', () => {
  describe('isObject', () => {
    it('should return true for objects', () => {
      expect(isObject({})).toBe(true);
      expect(isObject({ key: 'value' })).toBe(true);
      expect(isObject([])).toBe(true);
      expect(isObject(new Date())).toBe(true);
    });

    it('should return false for non-objects', () => {
      expect(isObject(null)).toBe(false);
      expect(isObject(undefined)).toBe(false);
      expect(isObject(42)).toBe(false);
      expect(isObject('string')).toBe(false);
      expect(isObject(true)).toBe(false);
      expect(isObject(Symbol('sym'))).toBe(false);
    });
  });

  describe('deepClone', () => {
    it('should return primitives as is', () => {
      expect(deepClone(42)).toBe(42);
      expect(deepClone('test')).toBe('test');
      expect(deepClone(true)).toBe(true);
      expect(deepClone(null)).toBe(null);
      expect(deepClone(undefined)).toBe(undefined);
    });

    it('should create a deep copy of objects', () => {
      const original = {
        name: 'test',
        nested: { value: 123 },
        arr: [1, 2, { x: 'y' }]
      };

      const cloned = deepClone(original);
      
      // Should be equal in value
      expect(cloned).toEqual(original);
      
      // But not the same reference
      expect(cloned).not.toBe(original);
      expect(cloned.nested).not.toBe(original.nested);
      expect(cloned.arr).not.toBe(original.arr);
      expect(cloned.arr[2]).not.toBe(original.arr[2]);
      
      // Modifying the clone should not affect the original
      cloned.name = 'modified';
      cloned.nested.value = 456;
      cloned.arr[2].x = 'z';
      
      expect(original.name).toBe('test');
      expect(original.nested.value).toBe(123);
      expect(original.arr[2].x).toBe('y');
    });

    it('should handle arrays correctly', () => {
      const original = [1, [2, 3], { a: 'b' }];
      const cloned = deepClone(original);
      
      expect(cloned).toEqual(original);
      expect(cloned).not.toBe(original);
      expect(cloned[1]).not.toBe(original[1]);
      expect(cloned[2]).not.toBe(original[2]);
    });
  });

  describe('createMock', () => {
    it('should create a mock object with specified properties', () => {
      interface User {
        id: number;
        name: string;
        email: string;
        isActive: boolean;
      }
      
      const mockUser = createMock<User>({
        id: 1,
        name: 'Test User'
      });
      
      expect(mockUser.id).toBe(1);
      expect(mockUser.name).toBe('Test User');
      expect(mockUser.email).toBeUndefined();
      expect(mockUser.isActive).toBeUndefined();
    });
  });
});