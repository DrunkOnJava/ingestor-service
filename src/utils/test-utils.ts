/**
 * Utility functions for testing the ingestor system
 */

/**
 * Simple function to check if a value is an object
 * @param value - The value to check
 * @returns True if the value is an object (and not null)
 */
export function isObject(value: unknown): boolean {
  return typeof value === 'object' && value !== null;
}

/**
 * Creates a deep copy of an object
 * @param obj - The object to clone
 * @returns A deep copy of the input object
 */
export function deepClone<T>(obj: T): T {
  if (!isObject(obj)) {
    return obj;
  }
  
  if (Array.isArray(obj)) {
    return obj.map(item => deepClone(item)) as unknown as T;
  }
  
  const clone = {} as Record<string, unknown>;
  
  Object.keys(obj as Record<string, unknown>).forEach(key => {
    const value = (obj as Record<string, unknown>)[key];
    clone[key] = deepClone(value);
  });
  
  return clone as T;
}

/**
 * Creates a mock object with specified property values
 * @param props - Object containing properties to mock
 * @returns A mock object with the specified properties
 */
export function createMock<T>(props: Partial<T>): T {
  return props as T;
}