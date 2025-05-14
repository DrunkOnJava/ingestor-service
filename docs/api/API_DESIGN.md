# Ingestor System API Design

## 1. API Overview

The Ingestor System API provides a RESTful interface for interacting with the content processing, entity extraction, and data management capabilities of the system. The API allows external applications to:

- Process content files (text, images, videos, code, etc.)
- Extract entities and insights using Claude AI
- Manage and query processed content in the database
- Monitor processing status and receive real-time updates

The API is designed to be secure, performant, and extensible, following RESTful principles and modern web API standards.

## 2. Base URL and Versioning

Base URL: `/api`

To support future changes and backward compatibility, all endpoints are versioned:

```
/api/v1/resources
```

API versioning follows semantic versioning principles, with major version changes in the URL path when backward incompatible changes are introduced.

## 3. Authentication and Security

### Authentication Methods

The API supports multiple authentication methods:

1. **API Key Authentication**
   - API keys provided in the `X-API-Key` header
   - Used for server-to-server communication

2. **JWT Authentication**
   - JSON Web Tokens issued after successful login
   - Used for user-based authentication
   - Provided in the `Authorization` header as `Bearer {token}`

3. **OAuth 2.0** (planned for future)
   - Support for OAuth 2.0 flows with third-party identity providers

### Security Measures

- All API traffic requires HTTPS
- Rate limiting based on client IP and/or API key
- Input validation for all endpoints
- Content validation before processing
- Permission-based access control
- CORS configuration for allowed origins
- Prevention of common web vulnerabilities (XSS, CSRF, injection attacks)

## 4. Resource Structure

The API is organized around the following main resources:

### Content
Represents the content items processed by the system.

### Entities
Entities (people, places, organizations, etc.) extracted from content items.

### Batches
Batch processing jobs for multiple content items.

### Processing
Statuses and results of content processing operations.

### Database
Information about available databases and schema.

### System
System information, status, and configuration.

## 5. Endpoints for Content Management

### Content Resource

#### List Content
```
GET /api/v1/content
```
Query parameters:
- `type`: Filter by content type (text, image, code, etc.)
- `limit`: Maximum number of items to return (default: 20)
- `offset`: Pagination offset (default: 0)
- `sort`: Field to sort by (created_at, title, type, etc.)
- `order`: Sort order (asc, desc)
- `q`: Search query across content text and metadata

#### Get Content Item
```
GET /api/v1/content/{id}
```
Returns details for a specific content item.

#### Create Content Item
```
POST /api/v1/content
```
Create a new content item by uploading content directly or providing a reference.

Request body:
```json
{
  "content": "string or base64 encoded content",
  "type": "text|image|video|code|pdf|document",
  "filename": "optional filename.ext",
  "metadata": {
    "title": "Optional title",
    "description": "Optional description",
    "tags": ["tag1", "tag2"],
    "customField": "value"
  },
  "processingOptions": {
    "extractEntities": true,
    "enableChunking": true,
    "chunkSize": 500000,
    "chunkOverlap": 5000
  }
}
```

#### Upload Content File
```
POST /api/v1/content/upload
```
Multipart form data upload for files.

#### Update Content Item
```
PUT /api/v1/content/{id}
```
Update metadata for a content item.

#### Delete Content Item
```
DELETE /api/v1/content/{id}
```
Delete a content item.

### Content Relationships

#### Get Content Entities
```
GET /api/v1/content/{id}/entities
```
Get entities associated with a content item.

#### Get Related Content
```
GET /api/v1/content/{id}/related
```
Get content items related to the specified content.

## 6. Endpoints for Entity Management

### Entity Resource

#### List Entities
```
GET /api/v1/entities
```
Query parameters:
- `type`: Filter by entity type (person, organization, etc.)
- `limit`: Maximum number of items to return
- `offset`: Pagination offset
- `q`: Search query across entity names and properties

#### Get Entity
```
GET /api/v1/entities/{id}
```
Get details for a specific entity.

#### Create Entity
```
POST /api/v1/entities
```
Manually create a new entity.

#### Update Entity
```
PUT /api/v1/entities/{id}
```
Update entity properties.

#### Delete Entity
```
DELETE /api/v1/entities/{id}
```
Delete an entity.

### Entity Relationships

#### Get Entity Content
```
GET /api/v1/entities/{id}/content
```
Get content items associated with an entity.

#### Get Entity Relationships
```
GET /api/v1/entities/{id}/relationships
```
Get relationships with other entities.

## 7. Endpoints for Batch Processing

### Batch Resource

#### List Batches
```
GET /api/v1/batches
```
List all batch processing jobs.

#### Get Batch
```
GET /api/v1/batches/{id}
```
Get details for a specific batch job.

#### Create Batch
```
POST /api/v1/batches
```
Create a new batch processing job.

Request body:
```json
{
  "name": "Batch job name",
  "description": "Optional description",
  "items": [
    { "path": "/path/to/file1.txt" },
    { "path": "/path/to/file2.jpg" }
  ],
  "directories": [
    {
      "path": "/path/to/directory",
      "pattern": "*.md",
      "recursive": true
    }
  ],
  "processingOptions": {
    "maxConcurrent": 5,
    "extractEntities": true,
    "enableChunking": true
  }
}
```

#### Cancel Batch
```
POST /api/v1/batches/{id}/cancel
```
Cancel a running batch job.

#### Get Batch Status
```
GET /api/v1/batches/{id}/status
```
Get the current status of a batch job.

#### Get Batch Items
```
GET /api/v1/batches/{id}/items
```
Get items in a batch and their processing status.

## 8. Request/Response Formats

### General Response Format

All API responses follow a consistent format:

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "pagination": {
      "limit": 20,
      "offset": 0,
      "total": 100
    }
  }
}
```

Error responses:

```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": { ... }
  }
}
```

### Content Types

- Request bodies: `application/json` for all endpoints except file uploads
- File uploads: `multipart/form-data`
- Response bodies: `application/json`

### DateTime Format

All date/time values use ISO 8601 format with UTC timezone (`YYYY-MM-DDTHH:MM:SSZ`).

## 9. Error Handling

### Error Codes

The API uses consistent error codes across all endpoints:

- `400` - Bad Request: Invalid input parameters
- `401` - Unauthorized: Missing or invalid authentication
- `403` - Forbidden: Insufficient permissions
- `404` - Not Found: Resource not found
- `409` - Conflict: Resource already exists or state conflict
- `422` - Unprocessable Entity: Request syntax valid but semantically incorrect
- `429` - Too Many Requests: Rate limit exceeded
- `500` - Internal Server Error: Unexpected server error
- `503` - Service Unavailable: System temporarily unavailable

### Error Responses

Error responses include:
- HTTP status code
- Error code string for programmatic handling
- Human-readable error message
- Detailed information when applicable

Example error response:

```json
{
  "success": false,
  "error": {
    "code": "INVALID_CONTENT_TYPE",
    "message": "The provided content type is not supported",
    "details": {
      "providedType": "audiobook",
      "supportedTypes": ["text", "image", "video", "code", "pdf", "document"]
    }
  }
}
```

## 10. Rate Limiting

Rate limiting is implemented to protect the API from abuse and ensure fair usage.

### Rate Limit Headers

Rate limit information is provided in response headers:

- `X-RateLimit-Limit`: Total requests allowed per time window
- `X-RateLimit-Remaining`: Remaining requests in current time window
- `X-RateLimit-Reset`: Time (in seconds) until the rate limit resets

### Rate Limit Configuration

Rate limits vary by endpoint and authentication method:
- Unauthenticated requests: 60 requests per hour
- Authenticated requests with API key: 1000 requests per hour
- High-volume API keys: Custom limits by arrangement

When rate limits are exceeded, the API returns a `429 Too Many Requests` status code.

## 11. Pagination

All list endpoints support pagination with the following query parameters:

- `limit`: Number of items per page (default: 20, max: 100)
- `offset`: Zero-based offset for pagination (default: 0)

Pagination metadata is included in the response:

```json
{
  "success": true,
  "data": [...],
  "meta": {
    "pagination": {
      "limit": 20,
      "offset": 20,
      "total": 156,
      "next": "/api/v1/content?limit=20&offset=40",
      "previous": "/api/v1/content?limit=20&offset=0"
    }
  }
}
```

## 12. Examples

### Process a Text File

Request:
```http
POST /api/v1/content
Content-Type: application/json
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

{
  "content": "This is a sample text document about artificial intelligence. Claude is an AI assistant created by Anthropic.",
  "type": "text",
  "filename": "sample.txt",
  "metadata": {
    "title": "Sample Text Document",
    "tags": ["sample", "ai"]
  },
  "processingOptions": {
    "extractEntities": true
  }
}
```

Response:
```json
{
  "success": true,
  "data": {
    "id": "c123456789",
    "type": "text",
    "filename": "sample.txt",
    "status": "processing",
    "metadata": {
      "title": "Sample Text Document",
      "tags": ["sample", "ai"],
      "contentLength": 102,
      "mimeType": "text/plain"
    },
    "processingId": "p987654321",
    "createdAt": "2025-05-14T03:45:21Z",
    "links": {
      "self": "/api/v1/content/c123456789",
      "processing": "/api/v1/processing/p987654321"
    }
  }
}
```

### Get Processing Results

Request:
```http
GET /api/v1/processing/p987654321
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Response:
```json
{
  "success": true,
  "data": {
    "id": "p987654321",
    "status": "completed",
    "contentId": "c123456789",
    "startedAt": "2025-05-14T03:45:21Z",
    "completedAt": "2025-05-14T03:45:35Z",
    "results": {
      "entities": [
        {
          "id": "e111222333",
          "type": "person",
          "name": "Claude",
          "properties": {
            "description": "AI assistant",
            "organization": "Anthropic"
          }
        },
        {
          "id": "e444555666",
          "type": "organization",
          "name": "Anthropic",
          "properties": {
            "industry": "Artificial Intelligence"
          }
        }
      ],
      "analysis": {
        "topics": ["artificial intelligence", "AI assistants"],
        "summary": "Brief text mentioning AI and specifically Claude, an AI assistant created by Anthropic."
      }
    }
  }
}
```

### Start a Batch Processing Job

Request:
```http
POST /api/v1/batches
Content-Type: application/json
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

{
  "name": "Process Research Documents",
  "description": "Process all PDF files in the research directory",
  "directories": [
    {
      "path": "/data/research",
      "pattern": "*.pdf",
      "recursive": true
    }
  ],
  "processingOptions": {
    "maxConcurrent": 3,
    "extractEntities": true,
    "enableChunking": true,
    "chunkSize": 300000
  }
}
```

Response:
```json
{
  "success": true,
  "data": {
    "id": "b123456789",
    "name": "Process Research Documents",
    "status": "queued",
    "createdAt": "2025-05-14T04:12:33Z",
    "itemsTotal": 0,
    "itemsProcessed": 0,
    "itemsFailed": 0,
    "links": {
      "self": "/api/v1/batches/b123456789",
      "status": "/api/v1/batches/b123456789/status",
      "items": "/api/v1/batches/b123456789/items"
    }
  }
}
```

## 13. WebSocket API

In addition to the REST API, a WebSocket API is provided for real-time updates.

### WebSocket Connection

Connect to the WebSocket server at:
```
wss://{host}/api/v1/ws
```

Authentication is performed with a token in the URL:
```
wss://{host}/api/v1/ws?token={jwt_token}
```

### WebSocket Events

The server emits the following events:

#### Content Processing Events
- `processing:started` - Content processing started
- `processing:completed` - Content processing completed
- `processing:failed` - Content processing failed
- `entity:created` - New entity created during processing

#### Batch Processing Events
- `batch:started` - Batch processing started
- `batch:progress` - Batch processing progress update
- `batch:completed` - Batch processing completed
- `batch:failed` - Batch processing failed
- `batch:item:started` - Processing started for a batch item
- `batch:item:completed` - Processing completed for a batch item
- `batch:item:failed` - Processing failed for a batch item

#### System Events
- `system:status` - System status update

Event messages follow a consistent format:
```json
{
  "event": "processing:completed",
  "data": {
    "id": "p987654321",
    "contentId": "c123456789",
    "results": { ... }
  },
  "timestamp": "2025-05-14T03:45:35Z"
}
```

## 14. API Documentation

The API is documented using the OpenAPI 3.0 specification, available at:
```
/api/docs
```

Interactive documentation is available through Swagger UI at:
```
/api/docs/ui
```

## 15. Future Extensions

Planned API extensions:
- Advanced search capabilities with faceted search and filters
- Bulk operations for content and entities
- Webhooks for event notifications
- Streaming API for large content processing
- Custom entity extraction models and configurations
- Multi-tenant support
- API SDK for common programming languages