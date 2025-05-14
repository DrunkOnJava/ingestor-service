# Ingestor System - Modular File Structure

This document outlines the proposed modular file organization structure for the ingestor-system project, designed to optimize maintainability and scalability.

## Root Directory Structure

```
ingestor-system/
├── src/               # Application source code
├── tests/             # Test files organized to mirror src/
├── config/            # Configuration files
├── docs/              # Documentation
├── scripts/           # Build and utility scripts
├── .env.example       # Example environment variables
├── .gitignore         # Git ignore file
├── package.json       # Project metadata and dependencies
├── tsconfig.json      # TypeScript configuration
├── README.md          # Project overview
└── CONTRIBUTING.md    # Contribution guidelines
```

## Detailed Directory Structure

### src/ Directory

```
src/
├── core/              # Core business logic
│   ├── entity/        # Entity extraction logic
│   ├── content/       # Content processing logic
│   └── analysis/      # Content analysis logic
├── utils/             # Reusable helper functions
│   ├── logging/       # Logging utilities
│   ├── error/         # Error handling utilities
│   └── validation/    # Input validation utilities
├── api/               # API endpoints and route handlers
│   ├── routes/        # Route definitions
│   ├── controllers/   # Request handlers
│   ├── middleware/    # API-specific middleware
│   └── validators/    # Request validation
├── db/                # Database operations
│   ├── models/        # Data models
│   ├── repositories/  # Data access logic
│   ├── migrations/    # Database migration scripts
│   └── schemas/       # Database schema definitions
├── types/             # TypeScript type definitions
│   ├── entity.ts      # Entity-related types
│   ├── content.ts     # Content-related types
│   ├── config.ts      # Configuration types
│   └── api.ts         # API-related types
├── services/          # External service integrations
│   ├── claude/        # Claude AI integration
│   ├── storage/       # Storage service integration
│   └── analytics/     # Analytics service integration
├── constants/         # Application constants
│   ├── errorCodes.ts  # Error code definitions
│   ├── contentTypes.ts # Content type definitions
│   └── config.ts      # Configuration constants
└── index.ts           # Application entry point
```

### Example File Content and Organization

#### 1. Core Module Example - Entity Extraction

```typescript
// src/core/entity/entityExtractor.ts
/**
 * EntityExtractor
 * Responsible for extracting named entities from various content types.
 */
import { Entity, EntityType, EntitySource } from '../../types/entity';
import { ContentType, Content } from '../../types/content';
import { logger } from '../../utils/logging';
import { ClaudeService } from '../../services/claude/claudeService';

export class EntityExtractor {
  private claudeService: ClaudeService;
  
  constructor(claudeService: ClaudeService) {
    this.claudeService = claudeService;
  }
  
  /**
   * Extract entities from content based on content type
   */
  async extractEntities(content: Content): Promise<Entity[]> {
    logger.debug(`Extracting entities from content: ${content.id}`, {
      contentType: content.type,
      contentSize: content.size
    });
    
    try {
      // Select appropriate extractor based on content type
      switch (content.type) {
        case ContentType.TEXT:
          return this.extractEntitiesFromText(content);
        case ContentType.PDF:
          return this.extractEntitiesFromPdf(content);
        case ContentType.IMAGE:
          return this.extractEntitiesFromImage(content);
        default:
          return this.extractEntitiesGeneric(content);
      }
    } catch (error) {
      logger.error(`Entity extraction failed for content ${content.id}`, { error });
      throw error;
    }
  }
  
  private async extractEntitiesFromText(content: Content): Promise<Entity[]> {
    // Implementation details
  }
  
  // Other extraction methods...
}

// src/core/entity/index.ts
export * from './entityExtractor';
export * from './entityNormalizer';
export * from './entityMerger';
```

#### 2. Database Module Example - Entity Repository

```typescript
// src/db/repositories/entityRepository.ts
/**
 * EntityRepository
 * Handles database operations for entities.
 */
import { Entity, EntityRelation } from '../../types/entity';
import { DatabaseClient } from '../client';
import { logger } from '../../utils/logging';
import { EntityModel } from '../models/entityModel';

export class EntityRepository {
  private dbClient: DatabaseClient;
  
  constructor(dbClient: DatabaseClient) {
    this.dbClient = dbClient;
  }
  
  /**
   * Store a new entity in the database
   */
  async saveEntity(entity: Entity): Promise<string> {
    logger.debug(`Storing entity in database: ${entity.name} (${entity.type})`);
    
    try {
      const entityModel = new EntityModel({
        name: entity.name,
        type: entity.type,
        description: entity.description,
        confidence: entity.confidence,
        source: entity.source
      });
      
      const id = await this.dbClient.insert('entities', entityModel);
      return id;
    } catch (error) {
      logger.error(`Failed to store entity: ${entity.name}`, { error });
      throw error;
    }
  }
  
  /**
   * Link entity to content
   */
  async linkEntityToContent(entityId: string, contentId: string, relation: EntityRelation): Promise<void> {
    // Implementation details
  }
  
  // Other repository methods...
}

// src/db/repositories/index.ts
export * from './entityRepository';
export * from './contentRepository';
```

#### 3. Service Module Example - Claude AI Integration

```typescript
// src/services/claude/claudeService.ts
/**
 * ClaudeService
 * Handles integration with Claude AI for content analysis and entity extraction.
 */
import { ClaudeClientConfig, AnalysisOptions } from '../../types/service';
import { logger } from '../../utils/logging';
import { ApiError } from '../../utils/error';
import { ErrorCodes } from '../../constants/errorCodes';

export class ClaudeService {
  private apiKey: string;
  private baseUrl: string;
  private timeout: number;
  
  constructor(config: ClaudeClientConfig) {
    this.apiKey = config.apiKey;
    this.baseUrl = config.baseUrl || 'https://api.anthropic.com/v1';
    this.timeout = config.timeout || 60000;
  }
  
  /**
   * Analyze content with Claude AI
   */
  async analyzeContent(content: string, contentType: string, options?: AnalysisOptions): Promise<any> {
    logger.debug('Analyzing content with Claude AI', { contentType, options });
    
    try {
      const response = await this.makeApiRequest('/analyze', {
        content,
        contentType,
        options
      });
      
      return response.data;
    } catch (error) {
      logger.error('Claude API request failed', { error });
      throw new ApiError(
        'Failed to analyze content with Claude AI',
        ErrorCodes.CLAUDE_API_ERROR,
        error
      );
    }
  }
  
  /**
   * Extract entities from content
   */
  async extractEntities(content: string, contentType: string): Promise<any> {
    // Implementation details
  }
  
  private async makeApiRequest(endpoint: string, data: any): Promise<any> {
    // Implementation details
  }
}

// src/services/claude/index.ts
export * from './claudeService';
```

#### 4. API Module Example - Entity Controller

```typescript
// src/api/controllers/entityController.ts
/**
 * EntityController
 * Handles API requests related to entities.
 */
import { Request, Response, NextFunction } from 'express';
import { EntityService } from '../../core/entity/entityService';
import { logger } from '../../utils/logging';
import { HttpStatus } from '../../constants/httpStatus';

export class EntityController {
  private entityService: EntityService;
  
  constructor(entityService: EntityService) {
    this.entityService = entityService;
  }
  
  /**
   * Extract entities from content
   */
  async extractEntities(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const { contentId } = req.params;
      const { filters } = req.query;
      
      logger.info(`Extracting entities for content: ${contentId}`, { filters });
      
      const entities = await this.entityService.extractEntitiesFromContent(contentId, filters);
      
      res.status(HttpStatus.OK).json({
        success: true,
        data: entities
      });
    } catch (error) {
      next(error);
    }
  }
  
  /**
   * Get entities by content ID
   */
  async getEntitiesByContent(req: Request, res: Response, next: NextFunction): Promise<void> {
    // Implementation details
  }
  
  // Other controller methods...
}

// src/api/controllers/index.ts
export * from './entityController';
export * from './contentController';
```

#### 5. Utils Module Example - Error Handling

```typescript
// src/utils/error/appError.ts
/**
 * AppError
 * Base error class for application errors.
 */
export class AppError extends Error {
  public readonly code: string;
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly details?: Record<string, any>;

  constructor(
    message: string,
    code: string,
    statusCode: number = 500,
    isOperational: boolean = true,
    details?: Record<string, any>
  ) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    this.details = details;
    
    Error.captureStackTrace(this, this.constructor);
  }
}

// src/utils/error/errorHandler.ts
/**
 * Error handling utilities
 */
import { Request, Response, NextFunction } from 'express';
import { AppError } from './appError';
import { logger } from '../logging';
import { ErrorCodes } from '../../constants/errorCodes';

/**
 * Global error handler middleware
 */
export const globalErrorHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
): void => {
  // Implementation details
};

// src/utils/error/index.ts
export * from './appError';
export * from './errorHandler';
export * from './apiError';
```

## Testing Structure

```
tests/
├── unit/              # Unit tests
│   ├── core/          # Tests for core modules
│   ├── utils/         # Tests for utility functions
│   └── services/      # Tests for services
├── integration/       # Integration tests
│   ├── api/           # API endpoint tests
│   ├── db/            # Database operation tests
│   └── services/      # External service tests
├── e2e/               # End-to-end tests
│   └── workflows/     # Complete workflow tests
├── fixtures/          # Test fixtures and mock data
│   ├── entities/      # Entity test data
│   ├── content/       # Content test files
│   └── responses/     # Mock API responses
└── helpers/           # Test helper functions
```

## Example Test File

```typescript
// tests/unit/core/entity/entityExtractor.test.ts
/**
 * EntityExtractor unit tests
 */
import { describe, it, expect, beforeEach, jest } from '@jest/globals';
import { EntityExtractor } from '../../../../src/core/entity/entityExtractor';
import { ClaudeService } from '../../../../src/services/claude/claudeService';
import { ContentType } from '../../../../src/types/content';
import { mockTextContent, mockEntities } from '../../../fixtures/entities/mockData';

describe('EntityExtractor', () => {
  let entityExtractor: EntityExtractor;
  let mockClaudeService: jest.Mocked<ClaudeService>;
  
  beforeEach(() => {
    mockClaudeService = {
      analyzeContent: jest.fn(),
      extractEntities: jest.fn()
    } as any;
    
    entityExtractor = new EntityExtractor(mockClaudeService);
  });
  
  describe('extractEntities', () => {
    it('should extract entities from text content', async () => {
      // Arrange
      mockClaudeService.extractEntities.mockResolvedValue(mockEntities);
      
      // Act
      const result = await entityExtractor.extractEntities(mockTextContent);
      
      // Assert
      expect(mockClaudeService.extractEntities).toHaveBeenCalledWith(
        mockTextContent.content,
        ContentType.TEXT
      );
      expect(result).toEqual(mockEntities);
    });
    
    // More tests...
  });
});
```

## Configuration Structure

```
config/
├── default.js         # Default configuration values
├── development.js     # Development environment config
├── production.js      # Production environment config
├── test.js            # Test environment config
├── schema.js          # Configuration schema validation
├── index.js           # Configuration loader
└── schemas/           # Database schema files
    ├── entities.sql   # Entity table schema
    ├── content.sql    # Content table schema
    └── relations.sql  # Relationship table schema
```

## Documentation Structure

```
docs/
├── api/               # API documentation
│   ├── endpoints.md   # API endpoint reference
│   └── examples.md    # API usage examples
├── architecture/      # Architecture documentation
│   ├── overview.md    # System architecture overview
│   ├── modules.md     # Module descriptions
│   └── diagrams/      # Architecture diagrams
├── guides/            # User guides
│   ├── setup.md       # Setup instructions
│   ├── usage.md       # Usage guide
│   └── examples.md    # Usage examples
└── development/       # Developer documentation
    ├── contributing.md # Contribution guidelines
    ├── testing.md     # Testing guidelines
    └── style-guide.md # Code style guide
```

## Scripts Structure

```
scripts/
├── build/             # Build scripts
│   ├── build.js       # Main build script
│   └── bundle.js      # Bundling script
├── db/                # Database scripts
│   ├── migrate.js     # Database migration script
│   ├── seed.js        # Database seeding script
│   └── backup.js      # Database backup script
├── ci/                # CI/CD scripts
│   ├── test.js        # Test runner script
│   └── deploy.js      # Deployment script
└── utils/             # Utility scripts
    ├── generate-docs.js  # Documentation generator
    └── lint.js        # Linting script
```

## Key Principles Applied in This Structure

1. **Single Responsibility**: Each module has a clearly defined responsibility.
2. **Separation of Concerns**: Business logic, data access, and API layers are separated.
3. **Modularity**: Related functionality is grouped together.
4. **Dependency Injection**: Services and repositories are injected rather than imported directly.
5. **Clean API Design**: Clear interfaces between modules.
6. **Testability**: Structure designed with testing in mind.
7. **Scalability**: Easy to add new features without modifying existing code.
8. **Maintainability**: Consistent patterns and organization.

This architecture provides a solid foundation for the ingestor system and can be easily extended as the application grows.