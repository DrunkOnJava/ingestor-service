-- Base database schema for ingestor system

-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- Database metadata
CREATE TABLE IF NOT EXISTS db_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Insert metadata
INSERT OR REPLACE INTO db_metadata (key, value) VALUES 
  ('schema_version', '1.0'),
  ('created_at', datetime('now')),
  ('ingestor_version', '1.0.0');

-- System settings
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Insert default settings
INSERT OR REPLACE INTO settings (key, value, description) VALUES
  ('entity_confidence_threshold', '0.5', 'Minimum confidence threshold for entity extraction'),
  ('entity_max_count', '50', 'Maximum number of entities to extract per content'),
  ('chunk_max_size', '4194304', 'Maximum chunk size in bytes (4MB)'),
  ('chunk_overlap', '419430', 'Chunk overlap in bytes (10% of max size)'),
  ('chunk_strategy', 'paragraph', 'Default chunking strategy (paragraph, line, token, character)'),
  ('default_content_type', 'text/plain', 'Default content type if not specified');

-- User table for tracking who added content
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_login TEXT
);

-- Insert system user
INSERT OR IGNORE INTO users (id, username) VALUES (1, 'system');