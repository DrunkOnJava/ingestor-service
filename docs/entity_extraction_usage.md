# Entity Extraction Usage Guide

This guide provides detailed instructions for using the Entity Extraction module in the Ingestor System. The module identifies, extracts, and stores named entities from various content types using both rule-based approaches and Claude AI integration.

## Table of Contents

1. [Basic Usage](#basic-usage)
2. [Content Types and Extractors](#content-types-and-extractors)
3. [Claude AI Integration](#claude-ai-integration)
4. [Configuration Options](#configuration-options)
5. [Entity Storage and Retrieval](#entity-storage-and-retrieval)
6. [Command Line Interface](#command-line-interface)
7. [Advanced Usage Patterns](#advanced-usage-patterns)
8. [Troubleshooting](#troubleshooting)
9. [Performance Optimization](#performance-optimization)
10. [Examples](#examples)

## Basic Usage

The entity extraction module can be used in three main ways:

1. As part of the content processing pipeline (automatic)
2. Explicitly from shell scripts
3. Through the CLI interface

### Basic Shell Script Usage

To use entity extraction in a shell script:

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Extract entities from a file
extracted_entities=$(extract_entities "/path/to/document.pdf" "application/pdf")

# Print the extracted entities
echo "$extracted_entities"
```

### Integrating with Content Processing

To enable entity extraction during content processing:

```bash
#!/bin/bash

# Source the content processors module
source "/path/to/ingestor-system/src/modules/content_processors.sh"

# Process content with entity extraction enabled
processed_content=$(process_content "/path/to/document.txt" "text/plain" "extract_entities=true")

# The processed_content will include extracted entities in the JSON response
echo "$processed_content" | jq '.entities'
```

## Content Types and Extractors

The entity extraction module supports various content types, each with a specialized extractor:

| Content Type | MIME Type | Supported Features |
|--------------|-----------|-------------------|
| Plain Text | `text/plain` | People, organizations, locations, dates, products |
| Markdown | `text/markdown` | Same as plain text, plus structured elements |
| HTML | `text/html` | Same as plain text, plus web elements |
| JSON | `application/json` | Keys, values, nested structures |
| XML | `application/xml` | Tags, attributes, nested structures |
| PDF | `application/pdf` | Document metadata, text content |
| Python Code | `text/x-python` | Classes, functions, imports, variables |
| JavaScript | `text/javascript` | Functions, classes, imports, variables |
| Shell Scripts | `application/x-sh` | Functions, variables, commands |
| C/C++ | `text/x-c` | Functions, structs, classes, includes |
| Images | `image/*` | Objects, people, text, scene elements (Claude only) |
| Videos | `video/*` | Metadata, keyframes (Claude only) |

### Example: Extracting from Different Content Types

```bash
# Extract from plain text
extract_entities "sample.txt" "text/plain"

# Extract from JSON
extract_entities "data.json" "application/json"

# Extract from Python code
extract_entities "script.py" "text/x-python"

# Extract from PDF
extract_entities "document.pdf" "application/pdf"
```

## Claude AI Integration

The entity extraction module integrates with Claude AI for advanced entity recognition. When available, it provides more accurate and comprehensive entity extraction.

### Requirements

- Claude API key set in environment: `CLAUDE_API_KEY`
- Network connectivity to Claude API endpoint
- JSON processing capability (`jq` installed)

### Fallback Mechanism

The module is designed to gracefully degrade when Claude API is unavailable:

1. First tries `extract_entities_with_claude` for specialized prompt-based extraction
2. Falls back to `analyze_with_claude` with a generic prompt if the specialized extraction fails
3. Uses rule-based extraction methods if Claude API is unavailable or returns errors

### Example: Forcing Claude API Usage

```bash
# Force Claude API usage with specialized entity type extraction
extract_entities "article.txt" "text/plain" "use_claude=true,entity_types=person,organization"

# Analyze with Claude but fall back if needed
extract_entities "code.py" "text/x-python" "use_claude=true,fallback=true"

# Disable Claude (force rule-based extraction)
extract_entities "data.json" "application/json" "use_claude=false"
```

## Configuration Options

The entity extraction module supports various configuration options that can be passed as the third parameter to `extract_entities`:

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `use_claude` | Whether to use Claude AI | `true` | `use_claude=false` |
| `entity_types` | Types of entities to extract | All types | `entity_types=person,organization,location` |
| `confidence_threshold` | Minimum confidence score (0-1) | `0.5` | `confidence_threshold=0.75` |
| `max_entities` | Maximum number of entities to extract | `50` | `max_entities=25` |
| `extract_mentions` | Whether to extract mention contexts | `true` | `extract_mentions=false` |
| `store_entities` | Whether to store entities in database | `true` | `store_entities=false` |
| `fallback` | Whether to use fallback extraction | `true` | `fallback=false` |

### Example: Using Configuration Options

```bash
# Extract only person and organization entities with high confidence
extract_entities "document.txt" "text/plain" "entity_types=person,organization,confidence_threshold=0.8"

# Extract entities without storing them in the database
extract_entities "report.pdf" "application/pdf" "store_entities=false,max_entities=100"

# Extract without mention contexts for a lightweight result
extract_entities "huge_document.txt" "text/plain" "extract_mentions=false"
```

## Entity Storage and Retrieval

Extracted entities are stored in the database for later retrieval and analysis.

### Database Schema

The entity extraction module uses two main tables:

1. `entities`: Stores unique entities with their types
2. `content_entities`: Links entities to the content they were found in

### Storing Entities Manually

```bash
# Extract entities without automatic storage
entities_json=$(extract_entities "document.txt" "text/plain" "store_entities=false")

# Store entities manually with a specific content ID
content_id=12345
echo "$entities_json" | jq -c '.[]' | while read -r entity; do
    name=$(echo "$entity" | jq -r '.name')
    type=$(echo "$entity" | jq -r '.type')
    
    # Store entity and get its ID
    entity_id=$(store_entity "$name" "$type" "Custom description")
    
    # Link entity to content
    if [[ -n "$entity_id" ]]; then
        link_entity_to_content "$entity_id" "$content_id" "text/plain" 0.9 "Manual linking"
    fi
done
```

### Retrieving Entities

```bash
# Initialize database connection
init_database "/path/to/database.db"

# Query for specific entity types
person_entities=$(db_query "SELECT * FROM entities WHERE entity_type = 'person';")

# Find entities for a specific content item
content_entities=$(db_query "
    SELECT e.name, e.entity_type, ce.relevance, ce.context
    FROM entities e
    JOIN content_entities ce ON e.id = ce.entity_id
    WHERE ce.content_id = 12345;
")

# Find content mentioning a specific entity
entity_mentions=$(db_query "
    SELECT c.id, c.title, ce.context, ce.relevance
    FROM content c
    JOIN content_entities ce ON c.id = ce.content_id
    JOIN entities e ON ce.entity_id = e.id
    WHERE e.name LIKE '%Claude%' AND e.entity_type = 'product';
")
```

## Command Line Interface

The entity extraction module can be used from the ingestor CLI tool:

```bash
# Extract entities from a file
ingestor extract-entities --file document.txt --type text/plain

# Extract specific entity types
ingestor extract-entities --file document.pdf --type application/pdf --entity-types person,organization

# Extract entities from multiple files
ingestor extract-entities --batch --directory /path/to/documents --extensions txt,pdf,json

# Extract entities and store in a specific database
ingestor extract-entities --file document.txt --database research.db --store-entities

# Extract with high confidence threshold
ingestor extract-entities --file document.txt --confidence-threshold 0.85
```

## Advanced Usage Patterns

### Batch Processing

For processing many files, use the batch processing pattern:

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Initialize database
init_database "entities.db"

# Process a directory of files
find /path/to/documents -type f -name "*.txt" | while read -r file; do
    echo "Processing $file..."
    
    # Extract entities with appropriate content type
    entities=$(extract_entities "$file" "text/plain" "confidence_threshold=0.7")
    
    # Check if entities were found
    entity_count=$(echo "$entities" | jq 'length')
    echo "Found $entity_count entities in $file"
done
```

### Custom Entity Types

You can extend the system with custom entity types:

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Add custom entity types to the ENTITY_TYPES array
ENTITY_TYPES+=(
    "medication"
    "medical_condition"
    "treatment"
)

# Create a custom extractor
extract_entities_medical() {
    local content="$1"
    local options="$2"
    
    # Try Claude API first
    if type extract_entities_with_claude &>/dev/null; then
        # Add custom entity types to options
        local enhanced_options="${options:+$options,}entity_types=medication,medical_condition,treatment"
        
        # Extract entities
        extract_entities_with_claude "$content" "text/plain" "$enhanced_options"
        return $?
    fi
    
    # Fallback to rule-based extraction
    # ... custom extraction logic ...
}

# Register the custom extractor
ENTITY_EXTRACTORS["medical/report"]="extract_entities_medical"

# Use the custom extractor
extract_entities "patient_record.txt" "medical/report"
```

## Troubleshooting

### Common Issues and Solutions

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| No entities extracted | Content not recognized | Verify file path and content type |
| | Claude API unavailable | Check API key and connectivity |
| | Content lacks recognizable entities | Try with more entity-rich content |
| Duplicate entities | Normalization not working | Check entity normalization functions |
| Entity type mismatch | Incorrect content type | Specify the correct content type |
| | Claude misclassification | Adjust confidence threshold |
| Slow extraction | Large content file | Use chunking options |
| | Network latency with Claude | Set longer timeout |
| Database errors | Incorrect permissions | Check database permissions |
| | Missing tables | Initialize database schema |

### Debugging Entity Extraction

For detailed debugging, set the log level to debug:

```bash
# Set debug log level
export LOG_LEVEL="debug"

# Run extraction with debugging
extract_entities "document.txt" "text/plain"

# Check logs
cat "/tmp/ingestor-logs/entity_extractors.log"
```

## Performance Optimization

For large content files or batch processing:

1. **Chunking**: Break large files into smaller chunks
   ```bash
   # Enable automatic chunking
   extract_entities "large_document.txt" "text/plain" "chunk_size=10000"
   ```

2. **Selective Entity Types**: Extract only specific entity types
   ```bash
   # Extract only the most important entity types
   extract_entities "document.txt" "text/plain" "entity_types=person,organization,location"
   ```

3. **Disable Mention Context**: Skip extracting mention contexts for faster processing
   ```bash
   # Extract entities without context
   extract_entities "document.txt" "text/plain" "extract_mentions=false"
   ```

4. **Database Batch Operations**: Use transactions for multiple operations
   ```bash
   # Begin transaction
   db_query "BEGIN TRANSACTION;"
   
   # Multiple entity operations...
   
   # Commit transaction
   db_query "COMMIT;"
   ```

5. **Database Index Optimization**: Apply specialized database indexes to improve query performance
   ```bash
   # Optimize manually
   optimize_entity_indexes "my_database"
   
   # Enable automatic optimization (applied when creating new databases and tables)
   export ENTITY_DB_OPTIMIZE="true"
   ```

6. **Parallel Processing**: Process multiple files concurrently
   ```bash
   # Using GNU Parallel
   find /path/to/documents -name "*.txt" | \
   parallel -j 4 "extract_entities {} text/plain > {}.entities.json"
   ```

## Examples

### Example 1: Basic Text Entity Extraction

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Sample text file
echo "John Smith is the CEO of Acme Corporation in New York. The company was founded on January 15, 2010." > sample.txt

# Extract entities
entities=$(extract_entities "sample.txt" "text/plain")

# Print the results
echo "$entities" | jq .

# Expected output:
# [
#   {
#     "name": "John Smith",
#     "type": "person",
#     "mentions": [{"context": "John Smith is the CEO", "position": 1, "relevance": 0.95}]
#   },
#   {
#     "name": "Acme Corporation",
#     "type": "organization",
#     "mentions": [{"context": "CEO of Acme Corporation", "position": 5, "relevance": 0.9}]
#   },
#   {
#     "name": "New York",
#     "type": "location",
#     "mentions": [{"context": "Corporation in New York", "position": 8, "relevance": 0.85}]
#   },
#   {
#     "name": "January 15, 2010",
#     "type": "date",
#     "mentions": [{"context": "founded on January 15, 2010", "position": 15, "relevance": 0.8}]
#   }
# ]
```

### Example 2: Code Entity Extraction

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Sample Python code
cat > sample.py << 'EOF'
import os
import datetime

class DataProcessor:
    def __init__(self, config_path):
        self.config_path = config_path
        
    def process_data(self, input_file):
        """Process data from input file"""
        print(f"Processing data from {input_file}")
        return True

if __name__ == "__main__":
    processor = DataProcessor("/etc/config.json")
    processor.process_data("data.csv")
EOF

# Extract entities
entities=$(extract_entities "sample.py" "text/x-python")

# Print the results
echo "$entities" | jq .

# Expected output includes:
# - Class: DataProcessor
# - Functions: process_data, __init__
# - Imports: os, datetime
# - Language: Python
```

### Example 3: Entity Storage and Retrieval

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Initialize database
init_database "entities.db"

# Sample text
echo "Apple Inc. was founded by Steve Jobs and Steve Wozniak in Cupertino, California on April 1, 1976." > sample.txt

# Extract and store entities
content_id=12345
extract_entities "sample.txt" "text/plain" "store_entities=true,content_id=$content_id"

# Retrieve entities for the content
entities=$(db_query "
    SELECT e.name, e.entity_type, ce.relevance 
    FROM entities e
    JOIN content_entities ce ON e.id = ce.entity_id
    WHERE ce.content_id = $content_id;
")

# Display the results
echo "$entities"
```

### Example 4: Using Claude AI for Complex Content

```bash
#!/bin/bash

# Source the entity extractors module
source "/path/to/ingestor-system/src/modules/entity_extractors.sh"

# Ensure Claude API key is set
export CLAUDE_API_KEY="your_api_key_here"

# Extract entities from complex content
entities=$(extract_entities "complex_report.pdf" "application/pdf" "use_claude=true,confidence_threshold=0.7")

# Filter for high-relevance entities only
high_relevance_entities=$(echo "$entities" | jq '[.[] | select(.mentions[0].relevance >= 0.8)]')

# Count entities by type
echo "Entity counts by type:"
echo "$high_relevance_entities" | jq 'group_by(.type) | map({type: .[0].type, count: length}) | sort_by(.count) | reverse'
```

This comprehensive guide provides developers with the information and examples needed to effectively use the entity extraction module in the Ingestor System.