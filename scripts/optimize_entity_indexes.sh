#!/bin/bash
# Script to apply entity table indexes to existing databases
# This script optimizes entity-related queries by adding specialized indexes

# Set default values for logging
export LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_DIR="${LOG_DIR:-/tmp/ingestor-logs}"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Source required modules
MODULE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/src/modules"
source "$MODULE_DIR/logging.sh" 2>/dev/null || { echo "Error: Could not source logging module"; exit 1; }
source "$MODULE_DIR/structured_logging.sh" 2>/dev/null || { echo "Error: Could not source structured logging module"; exit 1; }
source "$MODULE_DIR/database.sh" 2>/dev/null || { echo "Error: Could not source database module"; exit 1; }

# Default database directory
DEFAULT_DB_DIR="$HOME/.ingestor/databases"

# Function to display usage information
show_usage() {
    echo "Usage: $0 [options] [database_path]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -a, --all           Optimize all databases in the default directory"
    echo "  -d, --db-dir DIR    Specify custom database directory"
    echo "  -v, --verbose       Enable verbose output"
    echo ""
    echo "Examples:"
    echo "  $0 -a                   # Optimize all databases"
    echo "  $0 path/to/database.db  # Optimize specific database"
    echo "  $0 -d /data/dbs -a      # Optimize all databases in custom directory"
    echo ""
}

# Function to optimize a single database
optimize_database() {
    local db_path="$1"
    
    # Check if file exists and is an SQLite database
    if [[ ! -f "$db_path" ]]; then
        log_error "Database file not found: $db_path" "optimize_entity_indexes" "optimize_database"
        return 1
    fi
    
    # Verify it's a valid SQLite database
    if ! sqlite3 "$db_path" "PRAGMA quick_check;" &>/dev/null; then
        log_error "Not a valid SQLite database: $db_path" "optimize_entity_indexes" "optimize_database"
        return 1
    fi
    
    log_info "Optimizing entity indexes for database: $db_path" "optimize_entity_indexes" "optimize_database"
    
    # Check if entities table exists
    local has_entities_table
    has_entities_table=$(sqlite3 "$db_path" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='entities';")
    
    if [[ "$has_entities_table" -eq "0" ]]; then
        log_warning "Database does not have entities table, skipping: $db_path" "optimize_entity_indexes" "optimize_database"
        return 0
    fi
    
    # Path to the entity indexes SQL script
    local index_script="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/config/schemas/entity_indexes.sql"
    
    if [[ ! -f "$index_script" ]]; then
        log_error "Entity index script not found: $index_script" "optimize_entity_indexes" "optimize_database"
        return 1
    fi
    
    # Apply the indexes
    log_debug "Applying entity indexes from $index_script" "optimize_entity_indexes" "optimize_database"
    if sqlite3 "$db_path" < "$index_script"; then
        log_info "Successfully optimized entity indexes in: $db_path" "optimize_entity_indexes" "optimize_database"
        
        # Get index statistics
        local index_count
        index_count=$(sqlite3 "$db_path" "SELECT count(*) FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%entities%';")
        log_info "Added/verified $index_count entity-related indexes" "optimize_entity_indexes" "optimize_database"
        
        # Record the optimization in the database
        sqlite3 "$db_path" "CREATE TABLE IF NOT EXISTS maintenance_log (
            id INTEGER PRIMARY KEY,
            operation TEXT NOT NULL,
            details TEXT,
            executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );"
        
        sqlite3 "$db_path" "INSERT INTO maintenance_log (operation, details) VALUES (
            'entity_indexes_optimization', 
            'Added entity indexes for improved performance'
        );"
        
        return 0
    else
        log_error "Failed to apply entity indexes to: $db_path" "optimize_entity_indexes" "optimize_database"
        return 1
    fi
}

# Parse command-line arguments
OPTIMIZE_ALL=false
DB_DIR="$DEFAULT_DB_DIR"
VERBOSE=false
DB_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -a|--all)
            OPTIMIZE_ALL=true
            shift
            ;;
        -d|--db-dir)
            DB_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            export LOG_LEVEL="debug"
            shift
            ;;
        *)
            if [[ -z "$DB_PATH" ]]; then
                DB_PATH="$1"
            else
                log_error "Unknown argument: $1" "optimize_entity_indexes" "main"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check arguments
if [[ "$OPTIMIZE_ALL" == "true" && -n "$DB_PATH" ]]; then
    log_error "Cannot specify both --all and a specific database path" "optimize_entity_indexes" "main"
    show_usage
    exit 1
fi

# Main execution
if [[ "$OPTIMIZE_ALL" == "true" ]]; then
    # Check if database directory exists
    if [[ ! -d "$DB_DIR" ]]; then
        log_error "Database directory not found: $DB_DIR" "optimize_entity_indexes" "main"
        exit 1
    fi
    
    log_info "Optimizing all databases in: $DB_DIR" "optimize_entity_indexes" "main"
    
    # Find all SQLite databases
    db_count=0
    success_count=0
    
    # Find files with .db extension and try to optimize each one
    for db in "$DB_DIR"/*.db; do
        if [[ -f "$db" ]]; then
            ((db_count++))
            if optimize_database "$db"; then
                ((success_count++))
            fi
        fi
    done
    
    # Report results
    if [[ $db_count -eq 0 ]]; then
        log_warning "No databases found in: $DB_DIR" "optimize_entity_indexes" "main"
        exit 0
    else
        if [[ $success_count -eq $db_count ]]; then
            log_info "Successfully optimized all $db_count databases" "optimize_entity_indexes" "main"
            exit 0
        else
            log_warning "Optimized $success_count of $db_count databases" "optimize_entity_indexes" "main"
            exit 1
        fi
    fi
else
    # Optimize a specific database
    if [[ -z "$DB_PATH" ]]; then
        log_error "No database specified. Use -a to optimize all databases or provide a database path." "optimize_entity_indexes" "main"
        show_usage
        exit 1
    fi
    
    if optimize_database "$DB_PATH"; then
        exit 0
    else
        exit 1
    fi
fi