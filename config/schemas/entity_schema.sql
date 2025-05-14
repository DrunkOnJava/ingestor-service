-- Entity schema for ingestor system

-- Entities table
CREATE TABLE IF NOT EXISTS entities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  description TEXT,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Create indexes for entity lookups
CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name);
CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_entities_type_name ON entities(entity_type, name);

-- Content-entity relationships
CREATE TABLE IF NOT EXISTS content_entities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  content_id INTEGER NOT NULL,
  content_type TEXT NOT NULL,
  entity_id INTEGER NOT NULL,
  relevance REAL DEFAULT 0.5,
  context TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (entity_id) REFERENCES entities(id) ON DELETE CASCADE
);

-- Create indexes for content-entity lookups
CREATE INDEX IF NOT EXISTS idx_content_entities_content ON content_entities(content_id, content_type);
CREATE INDEX IF NOT EXISTS idx_content_entities_entity ON content_entities(entity_id);

-- Entity relationships
CREATE TABLE IF NOT EXISTS entity_relationships (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_entity_id INTEGER NOT NULL,
  target_entity_id INTEGER NOT NULL,
  relationship_type TEXT NOT NULL,
  strength REAL DEFAULT 0.5,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (source_entity_id) REFERENCES entities(id) ON DELETE CASCADE,
  FOREIGN KEY (target_entity_id) REFERENCES entities(id) ON DELETE CASCADE
);

-- Create indexes for entity relationship lookups
CREATE INDEX IF NOT EXISTS idx_entity_relationships_source ON entity_relationships(source_entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_relationships_target ON entity_relationships(target_entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_relationships_type ON entity_relationships(relationship_type);

-- Entity aliases for storing alternative names
CREATE TABLE IF NOT EXISTS entity_aliases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_id INTEGER NOT NULL,
  alias TEXT NOT NULL,
  confidence REAL DEFAULT 0.5,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (entity_id) REFERENCES entities(id) ON DELETE CASCADE
);

-- Create index for alias lookups
CREATE INDEX IF NOT EXISTS idx_entity_aliases_entity ON entity_aliases(entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_aliases_alias ON entity_aliases(alias);