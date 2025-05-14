-- Search schema for ingestor system

-- Full-text search for content
CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts5(
  title, 
  description, 
  content,
  content='content_chunks',
  content_rowid='id'
);

-- Create triggers to keep FTS in sync

-- Insert trigger
CREATE TRIGGER IF NOT EXISTS content_fts_insert
AFTER INSERT ON content_chunks
BEGIN
  INSERT INTO content_fts(rowid, title, description, content)
  SELECT 
    new.id,
    (SELECT title FROM content WHERE id = new.content_id),
    (SELECT description FROM content WHERE id = new.content_id),
    new.chunk_text
  ;
END;

-- Delete trigger
CREATE TRIGGER IF NOT EXISTS content_fts_delete
AFTER DELETE ON content_chunks
BEGIN
  DELETE FROM content_fts WHERE rowid = old.id;
END;

-- Update trigger
CREATE TRIGGER IF NOT EXISTS content_fts_update
AFTER UPDATE ON content_chunks
BEGIN
  DELETE FROM content_fts WHERE rowid = old.id;
  INSERT INTO content_fts(rowid, title, description, content)
  SELECT 
    new.id,
    (SELECT title FROM content WHERE id = new.content_id),
    (SELECT description FROM content WHERE id = new.content_id),
    new.chunk_text
  ;
END;

-- Content title/description update trigger
CREATE TRIGGER IF NOT EXISTS content_meta_update
AFTER UPDATE OF title, description ON content
BEGIN
  -- Update all FTS entries for this content
  UPDATE content_fts
  SET 
    title = new.title,
    description = new.description
  WHERE rowid IN (SELECT id FROM content_chunks WHERE content_id = new.id);
END;

-- Entity full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS entity_fts USING fts5(
  name,
  type,
  description,
  content='entities',
  content_rowid='id'
);

-- Create triggers to keep entity FTS in sync

-- Insert trigger
CREATE TRIGGER IF NOT EXISTS entity_fts_insert
AFTER INSERT ON entities
BEGIN
  INSERT INTO entity_fts(rowid, name, type, description)
  VALUES (new.id, new.name, new.entity_type, new.description);
END;

-- Delete trigger
CREATE TRIGGER IF NOT EXISTS entity_fts_delete
AFTER DELETE ON entities
BEGIN
  DELETE FROM entity_fts WHERE rowid = old.id;
END;

-- Update trigger
CREATE TRIGGER IF NOT EXISTS entity_fts_update
AFTER UPDATE ON entities
BEGIN
  DELETE FROM entity_fts WHERE rowid = old.id;
  INSERT INTO entity_fts(rowid, name, type, description)
  VALUES (new.id, new.name, new.entity_type, new.description);
END;

-- Search terms table to track search history
CREATE TABLE IF NOT EXISTS search_terms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  term TEXT NOT NULL,
  search_count INTEGER DEFAULT 1,
  last_searched_at TEXT NOT NULL DEFAULT (datetime('now')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Create indexes for search terms
CREATE INDEX IF NOT EXISTS idx_search_terms ON search_terms(term);
CREATE INDEX IF NOT EXISTS idx_search_terms_count ON search_terms(search_count);

-- Search results cache
CREATE TABLE IF NOT EXISTS search_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  search_hash TEXT NOT NULL UNIQUE,  -- Hash of search query and parameters
  search_query TEXT NOT NULL,
  search_params TEXT,
  results TEXT,  -- JSON array of result IDs
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL
);

-- Create index for search cache lookups
CREATE INDEX IF NOT EXISTS idx_search_cache_hash ON search_cache(search_hash);
CREATE INDEX IF NOT EXISTS idx_search_cache_expires ON search_cache(expires_at);