-- Content schema for ingestor system

-- Content metadata
CREATE TABLE IF NOT EXISTS content (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_type TEXT NOT NULL,
  title TEXT,
  description TEXT,
  source TEXT,
  file_path TEXT,
  hash TEXT,
  size INTEGER,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Create indexes for content lookups
CREATE INDEX IF NOT EXISTS idx_content_type ON content(content_type);
CREATE INDEX IF NOT EXISTS idx_content_source ON content(source);
CREATE INDEX IF NOT EXISTS idx_content_hash ON content(hash);

-- Content chunks for large content
CREATE TABLE IF NOT EXISTS content_chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id INTEGER NOT NULL,
  chunk_index INTEGER NOT NULL,
  chunk_text TEXT,
  chunk_metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE
);

-- Create indexes for chunk lookups
CREATE INDEX IF NOT EXISTS idx_chunks_content_id ON content_chunks(content_id);
CREATE INDEX IF NOT EXISTS idx_chunks_content_index ON content_chunks(content_id, chunk_index);

-- Content tags
CREATE TABLE IF NOT EXISTS tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Content-tag relationships
CREATE TABLE IF NOT EXISTS content_tags (
  content_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (content_id, tag_id),
  FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- Create indexes for tag lookups
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);
CREATE INDEX IF NOT EXISTS idx_content_tags_tag ON content_tags(tag_id);

-- Content metadata fields - customizable fields for different content types
CREATE TABLE IF NOT EXISTS content_fields (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id INTEGER NOT NULL,
  field_name TEXT NOT NULL,
  field_value TEXT,
  field_type TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (content_id) REFERENCES content(id) ON DELETE CASCADE
);

-- Create indexes for content fields
CREATE INDEX IF NOT EXISTS idx_content_fields_content ON content_fields(content_id);
CREATE INDEX IF NOT EXISTS idx_content_fields_name ON content_fields(field_name);
CREATE INDEX IF NOT EXISTS idx_content_fields_lookup ON content_fields(content_id, field_name);

-- Content relationships - for linking related content items
CREATE TABLE IF NOT EXISTS content_relationships (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_content_id INTEGER NOT NULL,
  target_content_id INTEGER NOT NULL,
  relationship_type TEXT NOT NULL,
  strength REAL DEFAULT 0.5,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (source_content_id) REFERENCES content(id) ON DELETE CASCADE,
  FOREIGN KEY (target_content_id) REFERENCES content(id) ON DELETE CASCADE
);

-- Create indexes for content relationships
CREATE INDEX IF NOT EXISTS idx_content_rel_source ON content_relationships(source_content_id);
CREATE INDEX IF NOT EXISTS idx_content_rel_target ON content_relationships(target_content_id);
CREATE INDEX IF NOT EXISTS idx_content_rel_type ON content_relationships(relationship_type);