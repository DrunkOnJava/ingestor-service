/**
 * Helper utilities for testing the ingestor system
 */

import { deepClone } from '../../utils/test-utils';

/**
 * Creates a mock for database repositories and similar objects
 * with methods that return promises
 * @param mockImplementation - Object containing mock implementations of methods
 * @returns A mock object with the specified implementations
 */
export function createRepositoryMock<T extends Record<string, unknown>>(
  mockImplementation: Partial<T> = {}
): jest.Mocked<T> {
  const mockObj = {} as jest.Mocked<T>;
  
  // Add default mock implementations for common repository methods
  const defaultMethods = [
    'findById',
    'findAll',
    'create',
    'update',
    'delete',
    'findByQuery',
    'count'
  ];
  
  // Create default implementation for each method (resolving to null)
  defaultMethods.forEach(method => {
    if (!(method in mockImplementation)) {
      mockObj[method as keyof T] = jest.fn().mockResolvedValue(null) as unknown as T[keyof T];
    }
  });
  
  // Add custom mock implementations
  Object.keys(mockImplementation).forEach(key => {
    mockObj[key as keyof T] = 
      typeof mockImplementation[key] === 'function'
        ? jest.fn().mockImplementation(mockImplementation[key] as (...args: unknown[]) => unknown)
        : mockImplementation[key] as T[keyof T];
  });
  
  return mockObj;
}

/**
 * Creates test fixtures from a template with optional overrides
 * @param template - The base template for the fixture
 * @param overrides - An array of partial overrides to apply
 * @returns An array of fixtures with applied overrides
 */
export function createFixtures<T>(template: T, overrides: Partial<T>[] = []): T[] {
  if (overrides.length === 0) {
    return [deepClone(template)];
  }
  
  return overrides.map(override => {
    const fixture = deepClone(template);
    return { ...fixture, ...override };
  });
}

/**
 * Creates a mock for service objects
 * @param mockImplementation - Object containing mock implementations of methods
 * @returns A mock service object with the specified implementations
 */
export function createServiceMock<T extends Record<string, unknown>>(
  mockImplementation: Partial<T> = {}
): jest.Mocked<T> {
  return createRepositoryMock<T>(mockImplementation);
}

/**
 * Helper to create assertion functions for testing asynchronous errors
 * @param errorClass - The expected error class
 * @param partialMessage - Optional substring to match in the error message
 * @returns An assertion function to test for the expected error
 */
export function expectToThrowAsync<T extends Error>(
  errorClass: new (...args: any[]) => T,
  partialMessage?: string
): (promise: Promise<any>) => Promise<void> {
  return async (promise: Promise<any>): Promise<void> => {
    try {
      await promise;
      fail(`Expected promise to throw ${errorClass.name} but it didn't throw any error`);
    } catch (error) {
      expect(error).toBeInstanceOf(errorClass);
      if (partialMessage) {
        expect((error as Error).message).toContain(partialMessage);
      }
    }
  };
}