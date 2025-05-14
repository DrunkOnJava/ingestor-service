-- Test schema for ingestor system

-- Images table
CREATE TABLE IF NOT EXISTS images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    width INTEGER,
    height INTEGER,
    creation_date TEXT,
    metadata TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Videos table
CREATE TABLE IF NOT EXISTS videos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    duration REAL,
    width INTEGER,
    height INTEGER,
    metadata TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Documents table
CREATE TABLE IF NOT EXISTS documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    mime_type TEXT NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Document chunks table
CREATE TABLE IF NOT EXISTS document_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Texts table
CREATE TABLE IF NOT EXISTS texts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Text chunks table
CREATE TABLE IF NOT EXISTS text_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    chunk_number INTEGER NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Code table
CREATE TABLE IF NOT EXISTS code (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    language TEXT NOT NULL,
    content TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Generic content table
CREATE TABLE IF NOT EXISTS generic_content (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    content_type TEXT NOT NULL,
    metadata TEXT,
    analysis TEXT,
    imported_at TEXT NOT NULL
);

-- Create full-text search tables
CREATE VIRTUAL TABLE IF NOT EXISTS fts_documents USING fts5(
    content, analysis,
    content=documents, content_rowid=id
);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_texts USING fts5(
    content, analysis,
    content=texts, content_rowid=id
);

CREATE VIRTUAL TABLE IF NOT EXISTS fts_code USING fts5(
    content, analysis,
    content=code, content_rowid=id
);

-- Create triggers to keep FTS tables in sync
CREATE TRIGGER IF NOT EXISTS documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO fts_documents(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;

CREATE TRIGGER IF NOT EXISTS texts_ai AFTER INSERT ON texts BEGIN
    INSERT INTO fts_texts(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;

CREATE TRIGGER IF NOT EXISTS code_ai AFTER INSERT ON code BEGIN
    INSERT INTO fts_code(rowid, content, analysis) VALUES (new.id, new.content, new.analysis);
END;