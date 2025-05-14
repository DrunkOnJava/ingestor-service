-- Entity Tables Indexing Script
-- This script adds optimized indexes to the entity-related tables to improve query performance

-- Start transaction
BEGIN TRANSACTION;

-- Add composite index for entity_type and name 
-- This will improve lookups by entity type and partial name matches
CREATE INDEX IF NOT EXISTS idx_entities_type_name ON entities(entity_type, name);

-- Add index for entity creation date
-- Useful for finding recently added entities
CREATE INDEX IF NOT EXISTS idx_entities_creation_date ON entities(created_at);

-- Add better indexes for content_entities table
-- These improve lookups when searching for entities within specific content types
CREATE INDEX IF NOT EXISTS idx_content_entities_content ON content_entities(content_id, content_type);

-- Add index for relevance to help with filtering high-relevance entities
CREATE INDEX IF NOT EXISTS idx_content_entities_relevance ON content_entities(relevance);

-- Add composite index for entity_id and relevance
-- This helps when finding the most relevant mentions of a specific entity
CREATE INDEX IF NOT EXISTS idx_content_entities_entity_relevance ON content_entities(entity_id, relevance);

-- Update statistics to ensure the query planner uses the new indexes effectively
ANALYZE entities;
ANALYZE content_entities;

-- Commit transaction
COMMIT;

-- Enable the query planner to use the indexes effectively
PRAGMA optimize;