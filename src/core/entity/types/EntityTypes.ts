/**
 * Core entity types for the ingestor system
 * These types define the structure of entities extracted from content
 */

/**
 * Enum defining the supported entity types
 */
export enum EntityType {
  PERSON = 'person',
  ORGANIZATION = 'organization',
  LOCATION = 'location',
  DATE = 'date',
  PRODUCT = 'product',
  TECHNOLOGY = 'technology',
  EVENT = 'event',
  OTHER = 'other'
}

/**
 * Interface for an entity mention
 * Represents a specific occurrence of an entity in content
 */
export interface EntityMention {
  /** Context text surrounding the entity (useful for disambiguation) */
  context: string;
  /** Position in the content where entity was found (line number, offset, etc.) */
  position: number;
  /** Confidence score or relevance of this entity mention (0.0-1.0) */
  relevance: number;
}

/**
 * Interface for a detected entity
 */
export interface Entity {
  /** Name of the entity */
  name: string;
  /** Type of entity from EntityType enum */
  type: EntityType;
  /** Optional description of the entity */
  description?: string;
  /** List of occurrences of this entity in the content */
  mentions: EntityMention[];
}

/**
 * Interface for entity extraction options
 */
export interface EntityExtractionOptions {
  /** Minimum confidence threshold for including entities (0.0-1.0) */
  confidenceThreshold?: number;
  /** Maximum number of entities to extract */
  maxEntities?: number;
  /** Specific entity types to include (if absent, all types are included) */
  entityTypes?: EntityType[];
  /** Custom context to help with extraction */
  context?: string;
  /** Specific language for code entity extraction */
  language?: string;
}

/**
 * Interface for entity extraction results
 */
export interface EntityExtractionResult {
  /** Array of extracted entities */
  entities: Entity[];
  /** Success status of the extraction */
  success: boolean;
  /** Error message if extraction failed */
  error?: string;
  /** Stats about the extraction process */
  stats?: {
    /** Time taken to extract entities (ms) */
    processingTimeMs: number;
    /** Number of entities extracted */
    entityCount: number;
  };
}