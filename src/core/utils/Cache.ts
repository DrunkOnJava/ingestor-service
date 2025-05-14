import { Logger } from '../logging/Logger';

/**
 * Cache configuration options.
 */
export interface CacheOptions {
  /**
   * Maximum number of items to store in the cache.
   * When this limit is reached, least recently used items will be removed.
   */
  maxSize?: number;
  
  /**
   * Time-to-live in milliseconds for cache entries.
   * If specified, entries older than this will be considered stale.
   * Set to 0 for no expiration.
   */
  ttl?: number;
  
  /**
   * Whether to automatically prune stale entries on get operations.
   */
  autoPrune?: boolean;
}

/**
 * Cache entry with metadata.
 */
interface CacheEntry<T> {
  /**
   * The actual cached value.
   */
  value: T;
  
  /**
   * When the entry was last accessed.
   */
  lastAccessed: number;
  
  /**
   * When the entry was created or updated.
   */
  created: number;
}

/**
 * Generic LRU cache implementation with TTL support.
 */
export class Cache<K, V> {
  private cache: Map<K, CacheEntry<V>> = new Map();
  private logger: Logger;
  private options: Required<CacheOptions>;
  
  /**
   * Creates a new cache instance.
   * 
   * @param logger - Logger instance for cache events
   * @param options - Cache configuration options
   */
  constructor(logger: Logger, options: CacheOptions = {}) {
    this.logger = logger;
    
    // Set default options
    this.options = {
      maxSize: options.maxSize || 1000,
      ttl: options.ttl || 0, // 0 means no expiration
      autoPrune: options.autoPrune !== undefined ? options.autoPrune : true
    };
    
    this.logger.debug('Cache initialized', {
      maxSize: this.options.maxSize,
      ttl: this.options.ttl,
      autoPrune: this.options.autoPrune
    });
  }
  
  /**
   * Gets a value from the cache.
   * 
   * @param key - The cache key
   * @returns The cached value, or undefined if not found or expired
   */
  public get(key: K): V | undefined {
    const entry = this.cache.get(key);
    
    if (!entry) {
      this.logger.debug(`Cache miss for key: ${String(key)}`);
      return undefined;
    }
    
    // Check if the entry is expired
    if (
      this.options.ttl > 0 && 
      entry.created + this.options.ttl < Date.now()
    ) {
      this.logger.debug(`Cache entry expired for key: ${String(key)}`);
      this.cache.delete(key);
      return undefined;
    }
    
    // Update last accessed time
    entry.lastAccessed = Date.now();
    
    this.logger.debug(`Cache hit for key: ${String(key)}`);
    return entry.value;
  }
  
  /**
   * Sets a value in the cache.
   * 
   * @param key - The cache key
   * @param value - The value to cache
   */
  public set(key: K, value: V): void {
    // Prune if we've reached the max size
    if (this.cache.size >= this.options.maxSize) {
      this.prune(1); // Remove at least one entry
    }
    
    const now = Date.now();
    
    this.cache.set(key, {
      value,
      lastAccessed: now,
      created: now
    });
    
    this.logger.debug(`Cache set for key: ${String(key)}`);
  }
  
  /**
   * Checks if a key exists in the cache and is not expired.
   * 
   * @param key - The cache key
   * @returns True if the key exists and is not expired
   */
  public has(key: K): boolean {
    const entry = this.cache.get(key);
    
    if (!entry) {
      return false;
    }
    
    // Check if the entry is expired
    if (
      this.options.ttl > 0 && 
      entry.created + this.options.ttl < Date.now()
    ) {
      if (this.options.autoPrune) {
        this.cache.delete(key);
      }
      return false;
    }
    
    return true;
  }
  
  /**
   * Deletes a key from the cache.
   * 
   * @param key - The cache key
   * @returns True if the key was found and deleted
   */
  public delete(key: K): boolean {
    this.logger.debug(`Cache delete for key: ${String(key)}`);
    return this.cache.delete(key);
  }
  
  /**
   * Clears all entries from the cache.
   */
  public clear(): void {
    this.logger.debug('Cache cleared');
    this.cache.clear();
  }
  
  /**
   * Gets the number of entries in the cache.
   */
  public get size(): number {
    return this.cache.size;
  }
  
  /**
   * Prunes expired and least recently used entries from the cache.
   * 
   * @param minEntriesToRemove - Minimum number of entries to remove
   * @returns Number of entries removed
   */
  public prune(minEntriesToRemove = 0): number {
    const now = Date.now();
    let removed = 0;
    
    // First, remove expired entries
    if (this.options.ttl > 0) {
      for (const [key, entry] of this.cache.entries()) {
        if (entry.created + this.options.ttl < now) {
          this.cache.delete(key);
          removed++;
        }
      }
    }
    
    // If we still need to remove more entries, remove by LRU
    if (removed < minEntriesToRemove) {
      // Convert to array, sort by lastAccessed (oldest first)
      const entries = Array.from(this.cache.entries())
        .sort((a, b) => a[1].lastAccessed - b[1].lastAccessed);
      
      // Remove the oldest entries
      const toRemove = Math.min(
        minEntriesToRemove - removed,
        entries.length
      );
      
      for (let i = 0; i < toRemove; i++) {
        this.cache.delete(entries[i][0]);
        removed++;
      }
    }
    
    if (removed > 0) {
      this.logger.debug(`Pruned ${removed} entries from cache`);
    }
    
    return removed;
  }
  
  /**
   * Gets cache statistics.
   * 
   * @returns Object with cache statistics
   */
  public stats(): {
    size: number;
    maxSize: number;
    ttl: number;
    autoPrune: boolean;
  } {
    return {
      size: this.cache.size,
      maxSize: this.options.maxSize,
      ttl: this.options.ttl,
      autoPrune: this.options.autoPrune
    };
  }
}