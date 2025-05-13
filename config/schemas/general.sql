-- General Content Database Schema

-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- Database Settings
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA auto_vacuum = INCREMENTAL;

-- Content Types Table
CREATE TABLE content_types (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    mime_pattern TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default content types
INSERT INTO content_types (name, description, mime_pattern) VALUES
    ('text', 'Plain text documents', 'text/%'),
    ('image', 'Image files', 'image/%'),
    ('video', 'Video files', 'video/%'),
    ('document', 'Document files', 'application/pdf'),
    ('code', 'Source code files', 'text/x-%'),
    ('json', 'JSON data files', 'application/json'),
    ('xml', 'XML data files', 'application/xml'),
    ('generic', 'Other file types', '%/%');

-- Generic Content Table
CREATE TABLE generic_content (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    metadata TEXT,  -- JSON
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

-- Text Content Table
CREATE TABLE texts (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    content TEXT NOT NULL,
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

-- Text Chunks Table
CREATE TABLE text_chunks (
    id INTEGER PRIMARY KEY,
    text_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    content TEXT NOT NULL,
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(text_path, chunk_number),
    FOREIGN KEY(text_path) REFERENCES texts(file_path) ON DELETE CASCADE
);

-- Image Content Table
CREATE TABLE images (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    width INTEGER,
    height INTEGER,
    creation_date TEXT,
    metadata TEXT,  -- JSON
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

-- Video Content Table
CREATE TABLE videos (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    duration REAL,
    width INTEGER,
    height INTEGER,
    metadata TEXT,  -- JSON
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

-- Document Content Table
CREATE TABLE documents (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    content TEXT,
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

-- Document Chunks Table
CREATE TABLE document_chunks (
    id INTEGER PRIMARY KEY,
    document_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    content TEXT NOT NULL,
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(document_path, chunk_number),
    FOREIGN KEY(document_path) REFERENCES documents(file_path) ON DELETE CASCADE
);

-- Code Content Table
CREATE TABLE code (
    id INTEGER PRIMARY KEY,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    language TEXT NOT NULL,
    content TEXT NOT NULL,
    analysis TEXT,  -- JSON
    imported_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

-- Tags Table
CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Content Tags Table
CREATE TABLE content_tags (
    id INTEGER PRIMARY KEY,
    content_id INTEGER NOT NULL,
    content_type TEXT NOT NULL,  -- 'text', 'image', 'video', etc.
    tag_id INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(content_id, content_type, tag_id),
    FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

-- Entities Table
CREATE TABLE entities (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    entity_type TEXT NOT NULL,  -- 'person', 'organization', 'location', etc.
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Content Entities Table
CREATE TABLE content_entities (
    id INTEGER PRIMARY KEY,
    content_id INTEGER NOT NULL,
    content_type TEXT NOT NULL,  -- 'text', 'image', 'video', etc.
    entity_id INTEGER NOT NULL,
    relevance REAL,  -- 0.0 to 1.0
    context TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(content_id, content_type, entity_id),
    FOREIGN KEY(entity_id) REFERENCES entities(id) ON DELETE CASCADE
);

-- Search Terms Table
CREATE TABLE search_terms (
    id INTEGER PRIMARY KEY,
    term TEXT NOT NULL UNIQUE,
    frequency INTEGER DEFAULT 1,
    last_searched TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Search Results Table
CREATE TABLE search_results (
    id INTEGER PRIMARY KEY,
    search_term_id INTEGER NOT NULL,
    content_id INTEGER NOT NULL,
    content_type TEXT NOT NULL,  -- 'text', 'image', 'video', etc.
    relevance REAL,  -- 0.0 to 1.0
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(search_term_id, content_id, content_type),
    FOREIGN KEY(search_term_id) REFERENCES search_terms(id) ON DELETE CASCADE
);

-- Create indexes for performance
CREATE INDEX idx_texts_filename ON texts(filename);
CREATE INDEX idx_images_filename ON images(filename);
CREATE INDEX idx_videos_filename ON videos(filename);
CREATE INDEX idx_documents_filename ON documents(filename);
CREATE INDEX idx_code_filename ON code(filename);
CREATE INDEX idx_code_language ON code(language);
CREATE INDEX idx_tags_name ON tags(name);
CREATE INDEX idx_entities_name ON entities(name);
CREATE INDEX idx_entities_type ON entities(entity_type);
CREATE INDEX idx_search_terms_term ON search_terms(term);

-- Set up FTS tables for full-text search
CREATE VIRTUAL TABLE texts_fts USING fts5(
    content, 
    analysis,
    content='texts',
    content_rowid='id'
);

CREATE VIRTUAL TABLE documents_fts USING fts5(
    content,
    analysis,
    content='documents',
    content_rowid='id'
);

CREATE VIRTUAL TABLE code_fts USING fts5(
    content,
    analysis,
    content='code',
    content_rowid='id'
);

-- Triggers to keep FTS tables in sync
CREATE TRIGGER texts_ai AFTER INSERT ON texts BEGIN
    INSERT INTO texts_fts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;
CREATE TRIGGER texts_ad AFTER DELETE ON texts BEGIN
    INSERT INTO texts_fts(texts_fts, rowid, content, analysis) VALUES('delete', old.id, old.content, old.analysis);
END;
CREATE TRIGGER texts_au AFTER UPDATE ON texts BEGIN
    INSERT INTO texts_fts(texts_fts, rowid, content, analysis) VALUES('delete', old.id, old.content, old.analysis);
    INSERT INTO texts_fts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;

CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO documents_fts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;
CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
    INSERT INTO documents_fts(documents_fts, rowid, content, analysis) VALUES('delete', old.id, old.content, old.analysis);
END;
CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN
    INSERT INTO documents_fts(documents_fts, rowid, content, analysis) VALUES('delete', old.id, old.content, old.analysis);
    INSERT INTO documents_fts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;

CREATE TRIGGER code_ai AFTER INSERT ON code BEGIN
    INSERT INTO code_fts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;
CREATE TRIGGER code_ad AFTER DELETE ON code BEGIN
    INSERT INTO code_fts(code_fts, rowid, content, analysis) VALUES('delete', old.id, old.content, old.analysis);
END;
CREATE TRIGGER code_au AFTER UPDATE ON code BEGIN
    INSERT INTO code_fts(code_fts, rowid, content, analysis) VALUES('delete', old.id, old.content, old.analysis);
    INSERT INTO code_fts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;