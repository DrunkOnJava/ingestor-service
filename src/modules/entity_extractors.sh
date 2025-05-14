#!/bin/bash
# Entity extraction module for ingestor
#
# This module extracts named entities from different content types.
# Entities include people, organizations, locations, dates, and other
# domain-specific items used for content analysis and search.

# Set default values for logging variables
export LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_DIR="${LOG_DIR:-/tmp/ingestor-logs}"
export TEMP_DIR="${TEMP_DIR:-/tmp/ingestor-temp}"

# Create directories if they don't exist
mkdir -p "$LOG_DIR" "$TEMP_DIR" 2>/dev/null || true

# Load required modules
if [[ -z "$MODULES_LOADED" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/structured_logging.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/database.sh" 2>/dev/null || true
    source "$(dirname "${BASH_SOURCE[0]}")/claude.sh" 2>/dev/null || true
    MODULES_LOADED=1
fi

# Entity types
declare -a ENTITY_TYPES=(
    "person"
    "organization"
    "location"
    "date"
    "product"
    "technology"
    "event"
    "other"
)

# Initialize entity extractors
init_entity_extractors() {
    log_debug "Initializing entity extractors" "entity_extractors" "init_entity_extractors"
    
    # Create temporary directory if needed
    if [[ ! -d "$TEMP_DIR" ]]; then
        mkdir -p "$TEMP_DIR"
        log_debug "Created temporary directory: $TEMP_DIR" "entity_extractors" "init_entity_extractors"
    fi
    
    # Register available extractors
    declare -A ENTITY_EXTRACTORS
    ENTITY_EXTRACTORS["text/plain"]="extract_entities_text"
    ENTITY_EXTRACTORS["text/markdown"]="extract_entities_text"
    ENTITY_EXTRACTORS["text/html"]="extract_entities_text"
    ENTITY_EXTRACTORS["application/json"]="extract_entities_json"
    ENTITY_EXTRACTORS["application/xml"]="extract_entities_xml"
    ENTITY_EXTRACTORS["application/pdf"]="extract_entities_pdf"
    ENTITY_EXTRACTORS["text/csv"]="extract_entities_csv"
    ENTITY_EXTRACTORS["text/x-python"]="extract_entities_code"
    ENTITY_EXTRACTORS["text/javascript"]="extract_entities_code"
    ENTITY_EXTRACTORS["text/x-c"]="extract_entities_code"
    ENTITY_EXTRACTORS["application/x-sh"]="extract_entities_code"
    ENTITY_EXTRACTORS["image/jpeg"]="extract_entities_image"
    ENTITY_EXTRACTORS["image/png"]="extract_entities_image"
    ENTITY_EXTRACTORS["video/mp4"]="extract_entities_video"
    
    # Default fallbacks by category
    ENTITY_EXTRACTORS["text/*"]="extract_entities_text_generic"
    ENTITY_EXTRACTORS["image/*"]="extract_entities_image_generic"
    ENTITY_EXTRACTORS["video/*"]="extract_entities_video_generic"
    ENTITY_EXTRACTORS["application/*"]="extract_entities_generic"
    ENTITY_EXTRACTORS["text/x-*"]="extract_entities_code_generic"
    
    # Setup entity extraction configuration
    export ENTITY_CONFIDENCE_THRESHOLD="${ENTITY_CONFIDENCE_THRESHOLD:-0.5}"
    export ENTITY_MAX_COUNT="${ENTITY_MAX_COUNT:-50}"
    export ENTITY_DB_OPTIMIZE="${ENTITY_DB_OPTIMIZE:-true}"
    
    # Check if we need to apply database optimizations automatically
    if [[ "$ENTITY_DB_OPTIMIZE" == "true" ]] && type optimize_entity_indexes &>/dev/null; then
        log_debug "Database optimization for entities is enabled" "entity_extractors" "init_entity_extractors"
    fi
    
    log_debug "Entity extractors initialized" "entity_extractors" "init_entity_extractors"
}

# Main entity extraction function
extract_entities() {
    local content="$1"
    local content_type="$2"
    local options="$3"
    
    log_info "Extracting entities from content: $content ($content_type)" "entity_extractors" "extract_entities"
    
    # Check if content exists (could be file path or raw text)
    if [[ -n "$content" && ! -f "$content" && ${#content} -lt 10 ]]; then
        log_error "Invalid content: $content" "entity_extractors" "extract_entities"
        return 1
    fi
    
    # Get the extractor for this content type
    local extractor="${ENTITY_EXTRACTORS[$content_type]}"
    
    # If no exact match, try generic handler based on category
    if [[ -z "$extractor" ]]; then
        local category="${content_type%%/*}/*"
        extractor="${ENTITY_EXTRACTORS[$category]}"
        
        # If still no match, use the fallback extractor
        if [[ -z "$extractor" ]]; then
            log_warning "No entity extractor found for content type: $content_type, using fallback" "entity_extractors" "extract_entities"
            extractor="extract_entities_fallback"
        else
            log_debug "Using category extractor: $extractor for $content_type" "entity_extractors" "extract_entities"
        fi
    else
        log_debug "Using specific extractor: $extractor for $content_type" "entity_extractors" "extract_entities"
    fi
    
    # Extract entities using the appropriate extractor
    $extractor "$content" "$options"
    
    return $?
}

# Helper function to normalize entity name
normalize_entity_name() {
    local name="$1"
    local type="$2"
    
    # Basic normalization
    name="${name//\"/}"   # Remove quotes
    name="${name//  / }"  # Replace double spaces with single space
    name="$(echo "$name" | sed 's/^ *//;s/ *$//')"  # Trim whitespace
    
    # Type-specific normalization
    case "$type" in
        person)
            # Capitalize first letter of each word for person names
            name="$(echo "$name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')"
            ;;
        organization)
            # Organizations often have specific capitalization, preserve most of it
            name="$(echo "$name" | sed 's/^ *//;s/ *$//')"  # Just trim whitespace
            ;;
        location)
            # Capitalize first letter of each word for locations
            name="$(echo "$name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')"
            ;;
        date)
            # Try to standardize date formats (basic approach)
            if [[ "$name" =~ ^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$ ]]; then
                # Convert MM/DD/YYYY to YYYY-MM-DD (very basic)
                name="$(echo "$name" | awk -F'/' '{print $3"-"$1"-"$2}')"
            fi
            ;;
        *)
            # Default normalization just trims whitespace
            name="$(echo "$name" | sed 's/^ *//;s/ *$//')"
            ;;
    esac
    
    echo "$name"
}

# Helper function to validate entity type
validate_entity_type() {
    local type="$1"
    
    for valid_type in "${ENTITY_TYPES[@]}"; do
        if [[ "$type" == "$valid_type" ]]; then
            return 0  # Valid type
        fi
    done
    
    return 1  # Invalid type
}

# Helper function to store entity in database
store_entity() {
    local name="$1"
    local type="$2"
    local description="$3"
    local db_name="${4:-}"
    
    log_debug "Storing entity: $name ($type)" "entity_extractors" "store_entity"
    
    # Normalize entity name
    local normalized_name
    normalized_name=$(normalize_entity_name "$name" "$type")
    
    # Validate entity type
    if ! validate_entity_type "$type"; then
        log_warning "Invalid entity type: $type, defaulting to 'other'" "entity_extractors" "store_entity"
        type="other"
    fi
    
    # Escape entity name for SQL
    normalized_name="${normalized_name//\'/\'\'}"
    
    # Check if entity already exists
    local entity_id
    entity_id=$(db_query "SELECT id FROM entities WHERE name = '$normalized_name' AND entity_type = '$type' LIMIT 1;")
    
    # If entity doesn't exist, create it
    if [[ -z "$entity_id" ]]; then
        description="${description//\'/\'\'}"
        entity_id=$(db_query "INSERT INTO entities (name, entity_type, description) VALUES ('$normalized_name', '$type', '$description') RETURNING id;")
        
        # Apply entity optimization if this is the first entity
        if [[ -n "$entity_id" && "$entity_id" == "1" && "$ENTITY_DB_OPTIMIZE" == "true" ]] && type optimize_entity_indexes &>/dev/null; then
            # Only if we have the database name
            if [[ -n "$db_name" ]]; then
                log_debug "First entity stored, optimizing database indexes" "entity_extractors" "store_entity"
                # Run in background to avoid slowing down the current operation
                (optimize_entity_indexes "$db_name" >/dev/null 2>&1 &)
            fi
        fi
    fi
    
    echo "$entity_id"
}

# Helper function to link entity to content
link_entity_to_content() {
    local entity_id="$1"
    local content_id="$2"
    local content_type="$3"
    local relevance="$4"
    local context="$5"
    
    log_debug "Linking entity $entity_id to content $content_id ($content_type)" "entity_extractors" "link_entity_to_content"
    
    # Escape context for SQL
    context="${context//\'/\'\'}"
    
    # Check if link already exists
    local link_exists
    link_exists=$(db_query "SELECT COUNT(*) FROM content_entities WHERE content_id = $content_id AND content_type = '$content_type' AND entity_id = $entity_id;")
    
    # If link doesn't exist, create it
    if [[ "$link_exists" == "0" ]]; then
        db_query "INSERT INTO content_entities (content_id, content_type, entity_id, relevance, context) VALUES ($content_id, '$content_type', $entity_id, $relevance, '$context');"
    else
        # Update existing link with new relevance and context
        db_query "UPDATE content_entities SET relevance = $relevance, context = '$context' WHERE content_id = $content_id AND content_type = '$content_type' AND entity_id = $entity_id;"
    fi
    
    return $?
}

# Helper function to extract entities from JSON
extract_entities_from_json() {
    local json="$1"
    
    local entities_json
    entities_json=$(echo "$json" | jq -r '.entities // []' 2>/dev/null)
    
    if [[ "$entities_json" == "null" || "$entities_json" == "[]" ]]; then
        log_warning "No entities found in JSON response" "entity_extractors" "extract_entities_from_json"
        echo "[]"
        return 0
    fi
    
    echo "$entities_json"
}

# Text entity extractor
extract_entities_text() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from text content" "entity_extractors" "extract_entities_text"
    
    # Determine if content is a file path or raw text
    local text_content
    if [[ -f "$content" ]]; then
        text_content=$(cat "$content")
    else
        text_content="$content"
    fi
    
    # Start with empty entities array
    local entities="[]"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using extract_entities_with_claude for text entity extraction" "entity_extractors" "extract_entities_text"
        
        # Determine content type based on file extension or content
        local content_type="text/plain"
        if [[ -f "$content" ]]; then
            local file_ext="${content##*.}"
            case "$file_ext" in
                md|markdown) content_type="text/markdown" ;;
                html|htm)   content_type="text/html" ;;
                txt)        content_type="text/plain" ;;
                csv)        content_type="text/csv" ;;
                *)          content_type="text/plain" ;;
            esac
        fi
        
        # Call the extract_entities_with_claude function with appropriate content type
        entities=$(extract_entities_with_claude "$text_content" "$content_type" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_text"
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_text"
            entities="[]" # Reset for fallback methods
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if [[ "$entities" == "[]" && $(type analyze_with_claude &>/dev/null; echo $?) -eq 0 ]]; then
        log_debug "Using analyze_with_claude for text entity extraction" "entity_extractors" "extract_entities_text"
        
        # Prepare system prompt for entity extraction
        local entity_prompt="text_entities"
        
        # If options include specific entity types to extract, customize the prompt
        if [[ "$options" == *"entity_types"* ]]; then
            entity_prompt="text_entities_custom"
        fi
        
        local claude_response
        claude_response=$(analyze_with_claude "$text_content" "$entity_prompt")
        
        # Extract entities from Claude's response
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_text"
        else
            log_warning "analyze_with_claude returned empty results, using rule-based extraction" "entity_extractors" "extract_entities_text"
            entities="[]" # Reset for rule-based extraction
        fi
    fi
    
    # If both Claude methods failed or aren't available, use rule-based extraction
    if [[ "$entities" == "[]" ]]; then
        log_warning "Claude API methods not available or failed, using rule-based entity extraction" "entity_extractors" "extract_entities_text"
        
        # More robust entity extraction using grep/sed with context
        # Create a temporary file for processing
        local temp_file
        temp_file="${TEMP_DIR}/entity_extraction_$(date +%s).txt"
        echo "$text_content" > "$temp_file"
        
        # Create JSON array for entities
        entities="["
        local first_entity=true
        
        # Extract PERSON entities
        log_debug "Extracting person entities" "entity_extractors" "extract_entities_text"
        
        # Match potential full names
        local persons
        persons=$(grep -o -E '\b[A-Z][a-z]+ ([A-Z]\.? )?[A-Z][a-z]+\b' "$temp_file" | sort | uniq)
        
        # Handle titles (Mr., Dr., etc.) followed by names
        local titled_persons
        titled_persons=$(grep -o -E '\b(Mr\.|Mrs\.|Ms\.|Dr\.|Prof\.) [A-Z][a-z]+ ([A-Z][a-z]+)?\b' "$temp_file" | sort | uniq)
        
        # Combine and deduplicate
        persons=$(echo -e "${persons}\n${titled_persons}" | sort | uniq)
        
        # Add person entities with context
        if [[ -n "$persons" ]]; then
            while IFS= read -r person; do
                if [[ -n "$person" ]]; then
                    # Get context (3 words before and after, if available)
                    local context
                    context=$(grep -o -E '.{0,30}'"$person"'.{0,30}' "$temp_file" | head -1)
                    context="${context//\"/\\\"}" # Escape quotes for JSON
                    
                    # Get approximate position (line number)
                    local position
                    position=$(grep -n "$person" "$temp_file" | head -1 | cut -d: -f1)
                    position=${position:-0}
                    
                    # Add to entities JSON
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    
                    entities+="{\"name\":\"$person\",\"type\":\"person\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.75}]}"
                fi
            done <<< "$persons"
        fi
        
        # Extract ORGANIZATION entities
        log_debug "Extracting organization entities" "entity_extractors" "extract_entities_text"
        
        # Match common organization patterns
        local organizations
        organizations=$(grep -o -E '\b[A-Z][A-Za-z0-9]* (Inc\.|Corp\.|Ltd\.|LLC|Company|Association|Foundation|University|Technologies|Group|Institute|Agency|Department)\b' "$temp_file" | sort | uniq)
        
        # Match capitalized multi-word names that could be organizations
        local capitalized_orgs
        capitalized_orgs=$(grep -o -E '\b([A-Z][a-z]+ ){1,3}(Inc\.|Corp\.|Ltd\.|LLC|Company|Association|Foundation|University|Technologies|Group|Institute|Agency|Department)\b' "$temp_file" | sort | uniq)
        
        # Combine and deduplicate
        organizations=$(echo -e "${organizations}\n${capitalized_orgs}" | sort | uniq)
        
        # Add organization entities with context
        if [[ -n "$organizations" ]]; then
            while IFS= read -r org; do
                if [[ -n "$org" ]]; then
                    # Escape org name for grep (to handle parentheses, etc.)
                    local escaped_org
                    escaped_org=$(echo "$org" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
                    
                    # Get context
                    local context
                    context=$(grep -o -E '.{0,30}'"$escaped_org"'.{0,30}' "$temp_file" | head -1)
                    context="${context//\"/\\\"}"
                    
                    # Get approximate position
                    local position
                    position=$(grep -n "$escaped_org" "$temp_file" | head -1 | cut -d: -f1)
                    position=${position:-0}
                    
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    
                    entities+="{\"name\":\"$org\",\"type\":\"organization\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.7}]}"
                fi
            done <<< "$organizations"
        fi
        
        # Extract LOCATION entities
        log_debug "Extracting location entities" "entity_extractors" "extract_entities_text"
        
        # Match common location patterns
        local locations
        locations=$(grep -o -E '\b(in|at|from|to) ([A-Z][a-z]+ )+([A-Z][a-z]+)?\b' "$temp_file" | sed 's/^in //;s/^at //;s/^from //;s/^to //' | sort | uniq)
        
        # Match countries and major cities (very basic list)
        local major_locations="United States|Canada|UK|Australia|China|Japan|Russia|Germany|France|Italy|Spain|Brazil|India|Mexico|New York|London|Paris|Tokyo|Berlin|Rome|Moscow|Beijing|Los Angeles|Chicago|Toronto|Sydney|Amsterdam|Dubai"
        local common_locations
        common_locations=$(grep -o -E '\b('"$major_locations"')\b' "$temp_file" | sort | uniq)
        
        # Combine and deduplicate
        locations=$(echo -e "${locations}\n${common_locations}" | sort | uniq)
        
        # Add location entities with context
        if [[ -n "$locations" ]]; then
            while IFS= read -r location; do
                if [[ -n "$location" ]]; then
                    # Escape location name for grep
                    local escaped_location
                    escaped_location=$(echo "$location" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
                    
                    # Get context
                    local context
                    context=$(grep -o -E '.{0,30}'"$escaped_location"'.{0,30}' "$temp_file" | head -1)
                    context="${context//\"/\\\"}"
                    
                    # Get approximate position
                    local position
                    position=$(grep -n "$escaped_location" "$temp_file" | head -1 | cut -d: -f1)
                    position=${position:-0}
                    
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    
                    entities+="{\"name\":\"$location\",\"type\":\"location\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.65}]}"
                fi
            done <<< "$locations"
        fi
        
        # Extract DATE entities
        log_debug "Extracting date entities" "entity_extractors" "extract_entities_text"
        
        # Match various date formats
        local dates
        dates=$(grep -o -E '\b[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}\b|\b[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\b|\b(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2},? [0-9]{4}\b|\b[0-9]{1,2} (January|February|March|April|May|June|July|August|September|October|November|December),? [0-9]{4}\b' "$temp_file" | sort | uniq)
        
        # Add date entities with context
        if [[ -n "$dates" ]]; then
            while IFS= read -r date; do
                if [[ -n "$date" ]]; then
                    # Escape date for grep
                    local escaped_date
                    escaped_date=$(echo "$date" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
                    
                    # Get context
                    local context
                    context=$(grep -o -E '.{0,30}'"$escaped_date"'.{0,30}' "$temp_file" | head -1)
                    context="${context//\"/\\\"}"
                    
                    # Get approximate position
                    local position
                    position=$(grep -n "$escaped_date" "$temp_file" | head -1 | cut -d: -f1)
                    position=${position:-0}
                    
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    
                    entities+="{\"name\":\"$date\",\"type\":\"date\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.8}]}"
                fi
            done <<< "$dates"
        fi
        
        # Extract PRODUCT entities (basic patterns)
        log_debug "Extracting product entities" "entity_extractors" "extract_entities_text"
        
        local products
        products=$(grep -o -E '\b[A-Z][a-z]+ (Pro|Plus|Ultra|Mini|Max|Lite|Premium|Professional|Enterprise|Ultimate|Elite|Standard)\b|\b[A-Z][a-z]+ [0-9]+( Pro| Ultra)?\b' "$temp_file" | sort | uniq)
        
        # Add product entities with context
        if [[ -n "$products" ]]; then
            while IFS= read -r product; do
                if [[ -n "$product" ]]; then
                    # Escape product for grep
                    local escaped_product
                    escaped_product=$(echo "$product" | sed 's/[][\.*^$(){}?+|/]/\\&/g')
                    
                    # Get context
                    local context
                    context=$(grep -o -E '.{0,30}'"$escaped_product"'.{0,30}' "$temp_file" | head -1)
                    context="${context//\"/\\\"}"
                    
                    # Get approximate position
                    local position
                    position=$(grep -n "$escaped_product" "$temp_file" | head -1 | cut -d: -f1)
                    position=${position:-0}
                    
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    
                    entities+="{\"name\":\"$product\",\"type\":\"product\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.6}]}"
                fi
            done <<< "$products"
        fi
        
        # Clean up
        entities+="]"
        rm -f "$temp_file"
    fi
    
    echo "$entities"
    return 0
}

# JSON entity extractor
extract_entities_json() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from JSON content" "entity_extractors" "extract_entities_json"
    
    # Determine if content is a file path or raw text
    local json_content
    if [[ -f "$content" ]]; then
        json_content=$(cat "$content")
    else
        json_content="$content"
    fi
    
    # Check if JSON is valid
    if ! echo "$json_content" | jq . >/dev/null 2>&1; then
        log_error "Invalid JSON content" "entity_extractors" "extract_entities_json"
        echo "[]"
        return 1
    fi
    
    # Extract entities from JSON structure (keys can be entities)
    local entities="[]"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using extract_entities_with_claude for JSON entity extraction" "entity_extractors" "extract_entities_json"
        
        # Call the extract_entities_with_claude function
        entities=$(extract_entities_with_claude "$json_content" "application/json" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_json"
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_json"
            entities="[]" # Reset for fallback methods
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if [[ "$entities" == "[]" && $(type analyze_with_claude &>/dev/null; echo $?) -eq 0 ]]; then
        log_debug "Using analyze_with_claude for JSON entity extraction" "entity_extractors" "extract_entities_json"
        
        local claude_response
        claude_response=$(analyze_with_claude "$json_content" "generic")
        
        # Extract entities from Claude's response
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_json"
        else
            log_warning "analyze_with_claude returned empty results, using basic extraction" "entity_extractors" "extract_entities_json"
            entities="[]" # Reset for rule-based extraction
        fi
    fi
    
    # If both Claude methods failed or aren't available, use basic JSON extraction
    if [[ "$entities" == "[]" ]]; then
        log_warning "Claude API methods not available or failed, using basic JSON entity extraction" "entity_extractors" "extract_entities_json"
        
        # Basic entity extraction from JSON structure
        # Get top-level keys as potential entities
        local keys
        keys=$(echo "$json_content" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        # Create entities array
        entities="["
        
        if [[ -n "$keys" ]]; then
            local first=true
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    # Only add comma if not the first entity
                    if ! $first; then
                        entities+=","
                    else
                        first=false
                    fi
                    
                    # Add key as entity
                    entities+="{\"name\":\"$key\",\"type\":\"other\",\"mentions\":[{\"context\":\"\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$keys"
        fi
        
        entities+="]"
    fi
    
    echo "$entities"
    return 0
}

# XML entity extractor
extract_entities_xml() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from XML content" "entity_extractors" "extract_entities_xml"
    
    # Determine if content is a file path or raw text
    local xml_content
    if [[ -f "$content" ]]; then
        xml_content=$(cat "$content")
    else
        xml_content="$content"
    fi
    
    # Start with empty entities array
    local entities="[]"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using extract_entities_with_claude for XML entity extraction" "entity_extractors" "extract_entities_xml"
        
        # Call the extract_entities_with_claude function
        entities=$(extract_entities_with_claude "$xml_content" "application/xml" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_xml"
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_xml"
            entities="[]" # Reset for fallback methods
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if [[ "$entities" == "[]" && $(type analyze_with_claude &>/dev/null; echo $?) -eq 0 ]]; then
        log_debug "Using analyze_with_claude for XML entity extraction" "entity_extractors" "extract_entities_xml"
        
        local claude_response
        claude_response=$(analyze_with_claude "$xml_content" "generic")
        
        # Extract entities from Claude's response
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_xml"
        else
            log_warning "analyze_with_claude returned empty results, using basic extraction" "entity_extractors" "extract_entities_xml"
            entities="[]" # Reset for basic extraction
        fi
    fi
    
    # If both Claude methods failed or aren't available, use basic XML extraction
    if [[ "$entities" == "[]" ]]; then
        log_warning "Claude API methods not available or failed, using basic XML entity extraction" "entity_extractors" "extract_entities_xml"
        
        # Basic entity extraction from XML structure
        # Extract XML tag names as potential entities
        local tags
        tags=$(echo "$xml_content" | grep -o -E '<[^/!][^>]*>' | sed 's/<\([^ >]*\).*/\1/g' | sort | uniq)
        
        # Create entities array
        entities="["
        
        if [[ -n "$tags" ]]; then
            local first=true
            while IFS= read -r tag; do
                if [[ -n "$tag" ]]; then
                    # Only add comma if not the first entity
                    if ! $first; then
                        entities+=","
                    else
                        first=false
                    fi
                    
                    # Add tag as entity
                    entities+="{\"name\":\"$tag\",\"type\":\"other\",\"mentions\":[{\"context\":\"\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$tags"
        fi
        
        entities+="]"
    fi
    
    echo "$entities"
    return 0
}

# Generic fallback entity extractor
extract_entities_fallback() {
    local content="$1"
    local options="$2"
    
    log_debug "Using fallback entity extractor" "entity_extractors" "extract_entities_fallback"
    
    # Determine if content is a file path or raw text
    local text_content
    if [[ -f "$content" ]]; then
        # Check if file is text or binary
        if file -b --mime-encoding "$content" | grep -q "binary"; then
            log_warning "Binary content, skipping entity extraction" "entity_extractors" "extract_entities_fallback"
            echo "[]"
            return 0
        fi
        text_content=$(cat "$content" 2>/dev/null || echo "")
    else
        text_content="$content"
    fi
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using extract_entities_with_claude for generic entity extraction" "entity_extractors" "extract_entities_fallback"
        
        # Determine MIME type if content is a file
        local mime_type="text/plain"
        if [[ -f "$content" ]]; then
            mime_type=$(file --mime-type -b "$content" 2>/dev/null || echo "text/plain")
        fi
        
        # Call extract_entities_with_claude with detected mime type
        local entities
        entities=$(extract_entities_with_claude "$text_content" "$mime_type" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_fallback"
            echo "$entities"
            return 0
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_fallback"
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if type analyze_with_claude &>/dev/null; then
        log_debug "Using analyze_with_claude for generic entity extraction" "entity_extractors" "extract_entities_fallback"
        
        local claude_response
        claude_response=$(analyze_with_claude "$text_content" "generic")
        
        # Extract entities from Claude's response
        local entities
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_fallback"
            echo "$entities"
            return 0
        else
            log_warning "analyze_with_claude returned empty results, using basic extraction" "entity_extractors" "extract_entities_fallback"
        fi
    fi
    
    # Use basic text entity extraction as final fallback
    log_warning "Claude API methods not available or failed, using basic text entity extraction" "entity_extractors" "extract_entities_fallback"
    extract_entities_text "$text_content" "$options"
    
    return $?
}

# Extract entities from chunked content
extract_entities_from_chunks() {
    local chunks_dir="$1"  # Directory containing the chunks
    local chunk_pattern="$2"  # Pattern to match chunk files (e.g., "chunk_*.txt")
    local content_type="$3"  # Content type for all chunks
    local options="$4"        # Options for extraction
    
    log_info "Extracting entities from chunked content in: $chunks_dir with pattern: $chunk_pattern" "entity_extractors" "extract_entities_from_chunks"
    
    # Verify inputs
    if [[ ! -d "$chunks_dir" ]]; then
        log_error "Chunks directory not found: $chunks_dir" "entity_extractors" "extract_entities_from_chunks"
        return 1
    fi
    
    # Find all chunk files
    local chunk_files=("$chunks_dir"/"$chunk_pattern")
    if [[ ${#chunk_files[@]} -eq 0 || ! -f "${chunk_files[0]}" ]]; then
        log_error "No chunk files found in $chunks_dir matching pattern $chunk_pattern" "entity_extractors" "extract_entities_from_chunks"
        return 1
    fi
    
    log_debug "Found ${#chunk_files[@]} chunks for processing" "entity_extractors" "extract_entities_from_chunks"
    
    # Create temporary directory for entity extraction results
    local temp_dir="${TEMP_DIR}/entities_$(date +%s)"
    mkdir -p "$temp_dir"
    
    # Dictionary to track unique entities across chunks
    declare -A entity_map
    local entity_count=0
    
    # Process each chunk and merge results
    for chunk_file in "${chunk_files[@]}"; do
        log_debug "Processing chunk: $chunk_file" "entity_extractors" "extract_entities_from_chunks"
        
        # Extract entities from this chunk
        local chunk_entities
        chunk_entities=$(extract_entities "$chunk_file" "$content_type" "$options")
        
        # If extraction failed, log warning but continue
        if [[ $? -ne 0 ]]; then
            log_warning "Failed to extract entities from chunk: $chunk_file" "entity_extractors" "extract_entities_from_chunks"
            continue
        fi
        
        # Save chunk entities to temporary file
        local chunk_result="$temp_dir/$(basename "$chunk_file").json"
        echo "$chunk_entities" > "$chunk_result"
        
        # Parse entities and add to our map, merging duplicates
        if command -v jq &>/dev/null; then
            # Use jq for JSON parsing if available
            local entities_count
            entities_count=$(jq 'length' "$chunk_result" 2>/dev/null || echo "0")
            
            if [[ "$entities_count" -gt 0 ]]; then
                # Process each entity in the chunk
                for i in $(seq 0 $((entities_count - 1))); do
                    local entity_name entity_type
                    entity_name=$(jq -r ".[${i}].name" "$chunk_result")
                    entity_type=$(jq -r ".[${i}].type" "$chunk_result")
                    
                    # Create a key for this entity (type:name)
                    local entity_key="${entity_type}:${entity_name}"
                    
                    # If we haven't seen this entity before, add it to our map
                    if [[ -z "${entity_map[$entity_key]+x}" ]]; then
                        entity_map[$entity_key]="$chunk_result:$i"
                        ((entity_count++))
                    else
                        # If we've seen this entity, update its reference to include this mention
                        entity_map[$entity_key]="${entity_map[$entity_key]},$chunk_result:$i"
                    fi
                done
            fi
        else
            # Basic fallback if jq isn't available
            log_warning "jq not available, using basic entity processing" "entity_extractors" "extract_entities_from_chunks"
            
            # Append chunk entities to main list
            cat "$chunk_result" >> "$temp_dir/all_entities.json"
        fi
    done
    
    log_info "Processed ${#chunk_files[@]} chunks, found $entity_count unique entities" "entity_extractors" "extract_entities_from_chunks"
    
    # Now merge the entities from all chunks
    local merged_entities="["
    local first_entity=true
    
    if command -v jq &>/dev/null; then
        # Process each unique entity
        for entity_key in "${!entity_map[@]}"; do
            # Skip if not a valid key
            if [[ -z "$entity_key" ]]; then continue; fi
            
            # Parse entity type and name
            local entity_type entity_name
            entity_type=${entity_key%%:*}
            entity_name=${entity_key#*:}
            
            # Get all references to this entity
            IFS=',' read -ra entity_refs <<< "${entity_map[$entity_key]}"
            
            # Prepare to merge mentions
            local all_mentions="[]"
            local entity_description=""
            
            # Process each reference
            for ref in "${entity_refs[@]}"; do
                local ref_file ref_index
                ref_file=${ref%%:*}
                ref_index=${ref#*:}
                
                # Get entity data
                if [[ -f "$ref_file" ]]; then
                    # Extract mentions from this reference
                    local mentions
                    mentions=$(jq -r ".[${ref_index}].mentions // []" "$ref_file" 2>/dev/null)
                    
                    # If this entity has a description, capture it
                    if [[ -z "$entity_description" ]]; then
                        entity_description=$(jq -r ".[${ref_index}].description // ''" "$ref_file" 2>/dev/null)
                    fi
                    
                    # Merge mentions (avoiding duplicates would require more sophisticated logic)
                    if [[ "$mentions" != "[]" && "$mentions" != "null" ]]; then
                        if [[ "$all_mentions" == "[]" ]]; then
                            all_mentions="$mentions"
                        else
                            # This is a simplified merge, a more sophisticated approach would deduplicate
                            # by comparing mention contexts
                            all_mentions=$(echo "$all_mentions" | jq -s ".[0] + .[1]" - <(echo "$mentions") 2>/dev/null || echo "[]")
                        fi
                    fi
                fi
            done
            
            # Add comma if needed
            if ! $first_entity; then
                merged_entities+=","
            else
                first_entity=false
            fi
            
            # Add the merged entity to the result
            entity_description=${entity_description//\"/\\\"} # Escape quotes for JSON
            merged_entities+="{\"name\":\"$entity_name\",\"type\":\"$entity_type\",\"description\":\"$entity_description\",\"mentions\":$all_mentions}"
        done
    else
        # Fallback to simple concatenation if jq isn't available
        if [[ -f "$temp_dir/all_entities.json" ]]; then
            # Very basic merge - might result in invalid JSON
            merged_entities=$(cat "$temp_dir/all_entities.json" | tr -d '[]' | sed 's/},{/},\n{/g')
            merged_entities="[${merged_entities}]"
        fi
    fi
    
    merged_entities+="]"
    
    # Clean up temporary files
    rm -rf "$temp_dir"
    
    echo "$merged_entities"
    return 0
}

# Helper function to store entity JSON output in the database
store_entities() {
    local db_name="$1"
    local content_path="$2"
    local entities_file="$3"
    
    log_debug "Storing entities from $entities_file in database $db_name" "entity_extractors" "store_entities"
    
    # Validate inputs
    if [[ -z "$db_name" || -z "$content_path" || -z "$entities_file" ]]; then
        log_error "Missing required parameters" "entity_extractors" "store_entities"
        return 1
    fi
    
    # Verify entities file exists
    if [[ ! -f "$entities_file" ]]; then
        log_error "Entities file not found: $entities_file" "entity_extractors" "store_entities"
        return 1
    fi
    
    # Read entity data from file
    local entities_json
    entities_json=$(cat "$entities_file" 2>/dev/null)
    
    if [[ -z "$entities_json" || "$entities_json" == "[]" ]]; then
        log_warning "No entities found in file: $entities_file" "entity_extractors" "store_entities"
        return 0
    fi
    
    # Parse entity data and store each entity
    local entity_count=0
    local success_count=0
    
    if command -v jq &>/dev/null; then
        # Get entity count
        local total_entities
        total_entities=$(jq 'length' <<< "$entities_json" 2>/dev/null || echo "0")
        
        # Process each entity
        for i in $(seq 0 $((total_entities - 1))); do
            local entity_name entity_type entity_description
            
            entity_name=$(jq -r ".[${i}].name" <<< "$entities_json" 2>/dev/null)
            entity_type=$(jq -r ".[${i}].type" <<< "$entities_json" 2>/dev/null)
            entity_description=$(jq -r ".[${i}].description // ''" <<< "$entities_json" 2>/dev/null)
            
            # Skip invalid entities
            if [[ -z "$entity_name" || -z "$entity_type" ]]; then
                log_warning "Skipping invalid entity at index $i" "entity_extractors" "store_entities"
                continue
            fi
            
            ((entity_count++))
            
            # Store entity in database
            local entity_id
            entity_id=$(store_entity "$entity_name" "$entity_type" "$entity_description" "$db_name")
            
            if [[ -z "$entity_id" ]]; then
                log_warning "Failed to store entity: $entity_name ($entity_type)" "entity_extractors" "store_entities"
                continue
            fi
            
            # Extract content ID from path (implementation depends on your database schema)
            local content_id content_type
            
            # This is a simplification - in a real implementation, you would need to look up
            # the content ID based on the path and content type
            content_id="1" # Placeholder
            content_type="text/plain" # Placeholder
            
            # Get mentions if available
            local mentions
            mentions=$(jq -r ".[${i}].mentions // []" <<< "$entities_json" 2>/dev/null)
            
            if [[ "$mentions" != "[]" && "$mentions" != "null" ]]; then
                # Get mention count
                local mention_count
                mention_count=$(jq 'length' <<< "$mentions" 2>/dev/null || echo "0")
                
                # Process each mention
                for j in $(seq 0 $((mention_count - 1))); do
                    local context relevance
                    
                    context=$(jq -r ".[${j}].context // ''" <<< "$mentions" 2>/dev/null)
                    relevance=$(jq -r ".[${j}].relevance // 0.5" <<< "$mentions" 2>/dev/null)
                    
                    # Link entity to content
                    if link_entity_to_content "$entity_id" "$content_id" "$content_type" "$relevance" "$context"; then
                        ((success_count++))
                    fi
                done
            else
                # If no mentions, create a default link
                if link_entity_to_content "$entity_id" "$content_id" "$content_type" "0.5" ""; then
                    ((success_count++))
                fi
            fi
        done
    else
        log_warning "jq not available, entity storage requires jq for JSON parsing" "entity_extractors" "store_entities"
        return 1
    fi
    
    log_info "Stored $success_count entity relations from $entity_count entities" "entity_extractors" "store_entities"
    return 0
}

# Placeholder functions for other content types
# These will be implemented in later phases

extract_entities_pdf() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from PDF" "entity_extractors" "extract_entities_pdf"
    
    # Try to use extract_entities_with_claude directly on the PDF if available
    if type extract_entities_with_claude &>/dev/null && [[ -f "$content" ]]; then
        log_debug "Using Claude for direct PDF entity extraction" "entity_extractors" "extract_entities_pdf"
        
        # Call extract_entities_with_claude with the PDF file
        local entities
        entities=$(extract_entities_with_claude "$content" "application/pdf" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            echo "$entities"
            return 0
        fi
        
        # If extraction failed, continue with traditional methods
        log_warning "Direct Claude PDF extraction failed, falling back to text extraction" "entity_extractors" "extract_entities_pdf"
    fi
    
    # Check if pdftotext is available
    if ! command -v pdftotext &> /dev/null; then
        log_warning "pdftotext not found, using fallback extraction" "entity_extractors" "extract_entities_pdf"
        extract_entities_fallback "$content" "$options"
        return $?
    fi
    
    # Create temporary file for extracted text
    local temp_file="${TEMP_DIR}/pdf_extraction_$(date +%s).txt"
    
    # Extract text from PDF
    pdftotext "$content" "$temp_file"
    
    # Extract metadata if pdfinfo is available
    local pdf_info=""
    if command -v pdfinfo &> /dev/null; then
        pdf_info=$(pdfinfo "$content")
    fi
    
    # Start with empty entities array
    local entities="[]"
    
    # Try to use Claude API if available
    if type analyze_with_claude &>/dev/null; then
        log_debug "Using Claude for PDF entity extraction" "entity_extractors" "extract_entities_pdf"
        
        # Combine text and metadata for Claude analysis
        local analysis_content
        analysis_content="PDF TEXT CONTENT:\n$(cat "$temp_file")\n\nPDF METADATA:\n$pdf_info"
        
        # Use PDF-specific Claude prompt if available, otherwise use text
        local entity_prompt="pdf"
        
        local claude_response
        claude_response=$(analyze_with_claude "$analysis_content" "$entity_prompt")
        
        # Extract entities from Claude's response
        entities=$(extract_entities_from_json "$claude_response")
    else
        log_warning "Claude API not available, using rule-based PDF entity extraction" "entity_extractors" "extract_entities_pdf"
        
        # Extract basic metadata entities from PDF info
        local metadata_entities="{}"
        
        if [[ -n "$pdf_info" ]]; then
            # Create JSON array for metadata entities
            metadata_entities="["
            local first_entity=true
            
            # Extract title
            local title
            title=$(echo "$pdf_info" | grep "Title:" | sed 's/Title:\s*//g' | sed 's/"/\\"/g')
            if [[ -n "$title" ]]; then
                if ! $first_entity; then
                    metadata_entities+=","
                else
                    first_entity=false
                fi
                metadata_entities+="{\"name\":\"$title\",\"type\":\"other\",\"mentions\":[{\"context\":\"PDF Title\",\"position\":0,\"relevance\":0.9}]}"
            fi
            
            # Extract author
            local author
            author=$(echo "$pdf_info" | grep "Author:" | sed 's/Author:\s*//g' | sed 's/"/\\"/g')
            if [[ -n "$author" ]]; then
                if ! $first_entity; then
                    metadata_entities+=","
                else
                    first_entity=false
                fi
                metadata_entities+="{\"name\":\"$author\",\"type\":\"person\",\"mentions\":[{\"context\":\"PDF Author\",\"position\":0,\"relevance\":0.9}]}"
            fi
            
            # Extract creation date
            local creation_date
            creation_date=$(echo "$pdf_info" | grep "CreationDate:" | sed 's/CreationDate:\s*//g' | sed 's/"/\\"/g')
            if [[ -n "$creation_date" ]]; then
                if ! $first_entity; then
                    metadata_entities+=","
                else
                    first_entity=false
                fi
                metadata_entities+="{\"name\":\"$creation_date\",\"type\":\"date\",\"mentions\":[{\"context\":\"PDF Creation Date\",\"position\":0,\"relevance\":0.9}]}"
            fi
            
            # Extract producer/creator application
            local producer
            producer=$(echo "$pdf_info" | grep "Producer:" | sed 's/Producer:\s*//g' | sed 's/"/\\"/g')
            if [[ -n "$producer" ]]; then
                if ! $first_entity; then
                    metadata_entities+=","
                else
                    first_entity=false
                fi
                metadata_entities+="{\"name\":\"$producer\",\"type\":\"technology\",\"mentions\":[{\"context\":\"PDF Producer\",\"position\":0,\"relevance\":0.8}]}"
            fi
            
            metadata_entities+="]"
        fi
        
        # Extract entities from the PDF text content
        local text_entities
        text_entities=$(extract_entities_text "$temp_file" "$options")
        
        # Combine metadata and text entities
        if [[ "$metadata_entities" == "{}" ]]; then
            entities="$text_entities"
        elif [[ "$text_entities" == "[]" ]]; then
            entities="$metadata_entities"
        else
            # Combine both arrays (remove closing bracket from first array and opening bracket from second)
            entities="${metadata_entities%]},${text_entities#[}"
        fi
    fi
    
    # Clean up
    rm -f "$temp_file"
    
    echo "$entities"
    return 0
}

extract_entities_csv() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from CSV" "entity_extractors" "extract_entities_csv"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using Claude for CSV entity extraction" "entity_extractors" "extract_entities_csv"
        
        # Call extract_entities_with_claude with the CSV content
        local entities
        entities=$(extract_entities_with_claude "$content" "text/csv" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            echo "$entities"
            return 0
        fi
    fi
    
    # Fall back to generic extraction if Claude extraction fails or is unavailable
    log_debug "Using fallback extraction for CSV" "entity_extractors" "extract_entities_csv"
    extract_entities_fallback "$content" "$options"
}

extract_entities_code() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from code" "entity_extractors" "extract_entities_code"
    
    # Determine if content is a file path or raw text
    local code_content
    if [[ -f "$content" ]]; then
        code_content=$(cat "$content")
    else
        code_content="$content"
    fi
    
    # Determine language from file extension or content patterns
    local language="unknown"
    local file_ext=""
    local mime_type="text/plain"
    
    if [[ -f "$content" ]]; then
        file_ext="${content##*.}"
        
        case "$file_ext" in
            py)      language="python"; mime_type="text/x-python" ;;
            js)      language="javascript"; mime_type="text/javascript" ;;
            ts)      language="typescript"; mime_type="text/typescript" ;;
            c|h)     language="c"; mime_type="text/x-c" ;;
            cpp|cxx|cc|hpp) language="cpp"; mime_type="text/x-c++" ;;
            java)    language="java"; mime_type="text/x-java" ;;
            rb)      language="ruby"; mime_type="text/x-ruby" ;;
            php)     language="php"; mime_type="text/x-php" ;;
            go)      language="go"; mime_type="text/x-go" ;;
            rs)      language="rust"; mime_type="text/x-rust" ;;
            swift)   language="swift"; mime_type="text/x-swift" ;;
            sh|bash) language="shell"; mime_type="application/x-sh" ;;
            pl)      language="perl"; mime_type="text/x-perl" ;;
            *)       language="unknown"; mime_type="text/plain" ;;
        esac
    else
        # Try to determine language from content patterns
        if [[ "$code_content" =~ import\ |def\ |class\ |if\ __name__\ ==\ .__main__.: ]]; then
            language="python"; mime_type="text/x-python"
        elif [[ "$code_content" =~ function\ |const\ |let\ |var\ |=>\ |import\ from ]]; then
            language="javascript"; mime_type="text/javascript"
        elif [[ "$code_content" =~ #include\ |int\ main\(|void\ main\( ]]; then
            language="c"; mime_type="text/x-c"
        elif [[ "$code_content" =~ \$|\@|\<?php ]]; then
            language="php"; mime_type="text/x-php"
        elif [[ "$code_content" =~ package\ |public\ class\ |import\ java ]]; then
            language="java"; mime_type="text/x-java"
        elif [[ "$code_content" =~ #!/bin/|function\ \(\)\ \{|echo\ \" ]]; then
            language="shell"; mime_type="application/x-sh"
        fi
    fi
    
    log_debug "Detected code language: $language" "entity_extractors" "extract_entities_code"
    
    # Start with empty entities array
    local entities="[]"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using Claude for code entity extraction" "entity_extractors" "extract_entities_code"
        
        # Add language to options if not empty
        local enhanced_options="$options"
        if [[ "$language" != "unknown" ]]; then
            enhanced_options="${options:+$options,}language=$language"
        fi
        
        # Call extract_entities_with_claude with the code content
        entities=$(extract_entities_with_claude "$code_content" "$mime_type" "$enhanced_options")
    elif type analyze_with_claude &>/dev/null; then
        log_debug "Using analyze_with_claude for code entity extraction" "entity_extractors" "extract_entities_code"
        
        local claude_response
        claude_response=$(analyze_with_claude "$code_content" "code")
        
        # Extract entities from Claude's response
        entities=$(extract_entities_from_json "$claude_response")
    else
        log_warning "Claude API not available, using rule-based code entity extraction" "entity_extractors" "extract_entities_code"
        
        # Create a temporary file for processing
        local temp_file="${TEMP_DIR}/code_extraction_$(date +%s).txt"
        echo "$code_content" > "$temp_file"
        
        # Create JSON array for entities
        entities="["
        local first_entity=true
        
        # Extract entities based on language
        case "$language" in
            python)
                # Extract Python classes
                local classes
                classes=$(grep -E '^class [A-Za-z0-9_]+(\(.*\))?:' "$temp_file" | sed 's/class \([A-Za-z0-9_]\+\).*/\1/g')
                
                # Add class entities
                if [[ -n "$classes" ]]; then
                    while IFS= read -r class; do
                        if [[ -n "$class" ]]; then
                            # Get context
                            local context
                            context=$(grep -A 1 "class $class" "$temp_file" | head -2 | tr '\n' ' ' | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n "class $class" "$temp_file" | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$class\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.9}]}"
                        fi
                    done <<< "$classes"
                fi
                
                # Extract Python functions
                local functions
                functions=$(grep -E '^def [A-Za-z0-9_]+\(' "$temp_file" | sed 's/def \([A-Za-z0-9_]\+\).*/\1/g')
                
                # Add function entities
                if [[ -n "$functions" ]]; then
                    while IFS= read -r function; do
                        if [[ -n "$function" ]]; then
                            # Get context
                            local context
                            context=$(grep -A 1 "def $function" "$temp_file" | head -2 | tr '\n' ' ' | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n "def $function" "$temp_file" | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$function\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.85}]}"
                        fi
                    done <<< "$functions"
                fi
                
                # Extract Python imports
                local imports
                imports=$(grep -E '^(import |from )' "$temp_file" | sed 's/import \([A-Za-z0-9_.]\+\).*/\1/g; s/from \([A-Za-z0-9_.]\+\).*/\1/g')
                
                # Add import entities
                if [[ -n "$imports" ]]; then
                    while IFS= read -r import; do
                        if [[ -n "$import" ]]; then
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$import\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Python import\",\"position\":0,\"relevance\":0.7}]}"
                        fi
                    done <<< "$imports"
                fi
                ;;
                
            javascript|typescript)
                # Extract JS/TS classes
                local classes
                classes=$(grep -E 'class [A-Za-z0-9_]+ (extends|implements|{)' "$temp_file" | sed 's/class \([A-Za-z0-9_]\+\).*/\1/g')
                
                # Add class entities
                if [[ -n "$classes" ]]; then
                    while IFS= read -r class; do
                        if [[ -n "$class" ]]; then
                            # Get context
                            local context
                            context=$(grep -A 1 "class $class" "$temp_file" | head -2 | tr '\n' ' ' | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n "class $class" "$temp_file" | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$class\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.9}]}"
                        fi
                    done <<< "$classes"
                fi
                
                # Extract JS/TS functions
                local functions
                functions=$(grep -E '(function [A-Za-z0-9_]+\(|[A-Za-z0-9_]+ = function\(|const [A-Za-z0-9_]+ = \([^)]*\) =>)' "$temp_file" | sed 's/function \([A-Za-z0-9_]\+\).*/\1/g; s/\([A-Za-z0-9_]\+\) = function.*/\1/g; s/const \([A-Za-z0-9_]\+\) =.*/\1/g')
                
                # Add function entities
                if [[ -n "$functions" ]]; then
                    while IFS= read -r function; do
                        if [[ -n "$function" ]]; then
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$function\",\"type\":\"technology\",\"mentions\":[{\"context\":\"JavaScript function\",\"position\":0,\"relevance\":0.85}]}"
                        fi
                    done <<< "$functions"
                fi
                
                # Extract JS/TS imports
                local imports
                imports=$(grep -E '(import |require\()' "$temp_file" | sed 's/.*from .\([^"'"'"']\+\).*/\1/g; s/.*require(.\([^"'"'"']\+\).*/\1/g')
                
                # Add import entities
                if [[ -n "$imports" ]]; then
                    while IFS= read -r import; do
                        if [[ -n "$import" ]]; then
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$import\",\"type\":\"technology\",\"mentions\":[{\"context\":\"JavaScript import\",\"position\":0,\"relevance\":0.7}]}"
                        fi
                    done <<< "$imports"
                fi
                ;;
                
            c|cpp)
                # Extract C/C++ functions
                local functions
                functions=$(grep -E '^[a-zA-Z0-9_]+ [a-zA-Z0-9_]+\(' "$temp_file" | grep -v '^if\|^for\|^while\|^switch' | sed 's/[a-zA-Z0-9_]\+ \([a-zA-Z0-9_]\+\).*/\1/g')
                
                # Add function entities
                if [[ -n "$functions" ]]; then
                    while IFS= read -r function; do
                        if [[ -n "$function" && "$function" != "(" ]]; then
                            # Get context
                            local context
                            context=$(grep -E "$function\\(" "$temp_file" | head -1 | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n -E "$function\\(" "$temp_file" | head -1 | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$function\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.85}]}"
                        fi
                    done <<< "$functions"
                fi
                
                # Extract C/C++ structs and classes
                local structs
                structs=$(grep -E '^(struct|class) [a-zA-Z0-9_]+' "$temp_file" | sed 's/\(struct\|class\) \([a-zA-Z0-9_]\+\).*/\2/g')
                
                # Add struct/class entities
                if [[ -n "$structs" ]]; then
                    while IFS= read -r struct; do
                        if [[ -n "$struct" ]]; then
                            # Get context
                            local type="struct"
                            if grep -q "class $struct" "$temp_file"; then
                                type="class"
                            fi
                            
                            local context
                            context=$(grep -A 1 "$type $struct" "$temp_file" | head -2 | tr '\n' ' ' | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n "$type $struct" "$temp_file" | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$struct\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.9}]}"
                        fi
                    done <<< "$structs"
                fi
                
                # Extract C/C++ includes
                local includes
                includes=$(grep -E '^#include' "$temp_file" | sed 's/#include [<"]\([^>"]*\)[>"].*/\1/g')
                
                # Add include entities
                if [[ -n "$includes" ]]; then
                    while IFS= read -r include; do
                        if [[ -n "$include" ]]; then
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$include\",\"type\":\"technology\",\"mentions\":[{\"context\":\"C/C++ include\",\"position\":0,\"relevance\":0.7}]}"
                        fi
                    done <<< "$includes"
                fi
                ;;
                
            shell)
                # Extract shell functions
                local functions
                functions=$(grep -E '^[a-zA-Z0-9_]+\(\)' "$temp_file" | sed 's/\([a-zA-Z0-9_]\+\)().*/\1/g')
                
                # Add function entities
                if [[ -n "$functions" ]]; then
                    while IFS= read -r function; do
                        if [[ -n "$function" ]]; then
                            # Get context
                            local context
                            context=$(grep -A 1 "^$function()" "$temp_file" | head -2 | tr '\n' ' ' | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n "^$function()" "$temp_file" | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$function\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.85}]}"
                        fi
                    done <<< "$functions"
                fi
                
                # Extract shell variables
                local variables
                variables=$(grep -E '^[A-Z_]+=.*$' "$temp_file" | sed 's/\([A-Z_]\+\)=.*/\1/g')
                
                # Add variable entities
                if [[ -n "$variables" ]]; then
                    while IFS= read -r variable; do
                        if [[ -n "$variable" ]]; then
                            # Get context
                            local context
                            context=$(grep -E "^$variable=" "$temp_file" | head -1 | sed 's/"/\\"/g')
                            
                            # Get position
                            local position
                            position=$(grep -n -E "^$variable=" "$temp_file" | head -1 | cut -d: -f1)
                            position=${position:-0}
                            
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$variable\",\"type\":\"technology\",\"mentions\":[{\"context\":\"$context\",\"position\":$position,\"relevance\":0.75}]}"
                        fi
                    done <<< "$variables"
                fi
                
                # Extract referenced commands
                local commands
                commands=$(grep -Eo '\b(grep|sed|awk|find|cat|echo|mv|cp|rm|mkdir|touch|chmod|chown|curl|wget|tar|zip|unzip|ssh|rsync)\b' "$temp_file" | sort | uniq)
                
                # Add command entities
                if [[ -n "$commands" ]]; then
                    while IFS= read -r command; do
                        if [[ -n "$command" ]]; then
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$command\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Shell command\",\"position\":0,\"relevance\":0.6}]}"
                        fi
                    done <<< "$commands"
                fi
                ;;
                
            *)
                # For unknown languages, extract generic code entities
                # Function-like patterns
                local functions
                functions=$(grep -E '(function |def |void |int |char |double |float |class |struct |interface |impl )' "$temp_file" | grep -o -E '[a-zA-Z0-9_]+\(' | sed 's/\(.*\)(/\1/g')
                
                # Add function entities
                if [[ -n "$functions" ]]; then
                    while IFS= read -r function; do
                        if [[ -n "$function" ]]; then
                            if ! $first_entity; then
                                entities+=","
                            else
                                first_entity=false
                            fi
                            
                            entities+="{\"name\":\"$function\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Function in $language code\",\"position\":0,\"relevance\":0.7}]}"
                        fi
                    done <<< "$functions"
                fi
                ;;
        esac
        
        # Add the language itself as an entity
        if [[ "$language" != "unknown" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            
            entities+="{\"name\":\"$language\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Programming language\",\"position\":0,\"relevance\":0.95}]}"
        fi
        
        # Finalize the entities array
        entities+="]"
        
        # Clean up
        rm -f "$temp_file"
    fi
    
    echo "$entities"
    return 0
}

extract_entities_image() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from image" "entity_extractors" "extract_entities_image"
    
    # Check if content is a file and exists
    if [[ -f "$content" ]]; then
        # Try to determine the image mime type
        local mime_type
        mime_type=$(file --mime-type -b "$content")
        
        # Try to use extract_entities_with_claude if available
        if type extract_entities_with_claude &>/dev/null; then
            log_debug "Using Claude for image entity extraction" "entity_extractors" "extract_entities_image"
            
            # Call extract_entities_with_claude with the image file
            local entities
            entities=$(extract_entities_with_claude "$content" "$mime_type" "$options")
            
            # Check if extraction was successful
            if [[ -n "$entities" && "$entities" != "[]" ]]; then
                echo "$entities"
                return 0
            fi
        fi
    fi
    
    # Fall back to generic extraction if Claude extraction fails or is unavailable
    log_debug "Using fallback extraction for image" "entity_extractors" "extract_entities_image"
    extract_entities_fallback "$content" "$options"
}

extract_entities_video() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from video" "entity_extractors" "extract_entities_video"
    
    # Check if content is a file and exists
    if [[ -f "$content" ]]; then
        # Try to determine the video mime type
        local mime_type
        mime_type=$(file --mime-type -b "$content")
        
        # Try to use extract_entities_with_claude if available
        if type extract_entities_with_claude &>/dev/null; then
            log_debug "Using Claude for video entity extraction" "entity_extractors" "extract_entities_video"
            
            # Extract video metadata if available
            local video_meta=""
            if command -v ffprobe &> /dev/null; then
                video_meta=$(ffprobe -v quiet -print_format json -show_format -show_streams "$content")
                
                # Call extract_entities_with_claude with the video metadata
                local entities
                entities=$(extract_entities_with_claude "$video_meta" "application/json" "$options,context=video_metadata")
                
                # Check if extraction was successful
                if [[ -n "$entities" && "$entities" != "[]" ]]; then
                    echo "$entities"
                    return 0
                fi
            else
                # Try direct extraction with the video file
                local entities
                entities=$(extract_entities_with_claude "$content" "$mime_type" "$options")
                
                # Check if extraction was successful
                if [[ -n "$entities" && "$entities" != "[]" ]]; then
                    echo "$entities"
                    return 0
                fi
            fi
        fi
    fi
    
    # Fall back to generic extraction if Claude extraction fails or is unavailable
    log_debug "Using fallback extraction for video" "entity_extractors" "extract_entities_video"
    extract_entities_fallback "$content" "$options"
}

extract_entities_text_generic() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from generic text" "entity_extractors" "extract_entities_text_generic"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using extract_entities_with_claude for generic text entity extraction" "entity_extractors" "extract_entities_text_generic"
        
        # Determine the appropriate content type
        local mime_type="text/plain"
        if [[ -f "$content" ]]; then
            local file_ext="${content##*.}"
            case "$file_ext" in
                md|markdown) mime_type="text/markdown" ;;
                html|htm)   mime_type="text/html" ;;
                txt)        mime_type="text/plain" ;;
                csv)        mime_type="text/csv" ;;
                *)          mime_type="text/plain" ;;
            esac
        fi
        
        # Call extract_entities_with_claude with the appropriate content type
        local entities
        entities=$(extract_entities_with_claude "$content" "$mime_type" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_text_generic"
            echo "$entities"
            return 0
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_text_generic"
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if type analyze_with_claude &>/dev/null; then
        log_debug "Using analyze_with_claude for generic text entity extraction" "entity_extractors" "extract_entities_text_generic"
        
        local claude_response
        claude_response=$(analyze_with_claude "$content" "text")
        
        # Extract entities from Claude's response
        local entities
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_text_generic"
            echo "$entities"
            return 0
        else
            log_warning "analyze_with_claude returned empty results, using standard extraction" "entity_extractors" "extract_entities_text_generic"
        fi
    fi
    
    # Fall back to standard text extraction
    extract_entities_text "$content" "$options"
}

extract_entities_image_generic() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from generic image" "entity_extractors" "extract_entities_image_generic"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null && [[ -f "$content" ]]; then
        log_debug "Using extract_entities_with_claude for generic image entity extraction" "entity_extractors" "extract_entities_image_generic"
        
        # Determine the image mime type
        local mime_type
        mime_type=$(file --mime-type -b "$content" 2>/dev/null || echo "image/jpeg")
        
        # Call extract_entities_with_claude with the image file and specific image prompt
        local enhanced_options="${options:+$options,}context=image"
        local entities
        entities=$(extract_entities_with_claude "$content" "$mime_type" "$enhanced_options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_image_generic"
            echo "$entities"
            return 0
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_image_generic"
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if type analyze_with_claude &>/dev/null && [[ -f "$content" ]]; then
        log_debug "Using analyze_with_claude for generic image entity extraction" "entity_extractors" "extract_entities_image_generic"
        
        local claude_response
        claude_response=$(analyze_with_claude "$content" "image")
        
        # Extract entities from Claude's response
        local entities
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_image_generic"
            echo "$entities"
            return 0
        else
            log_warning "analyze_with_claude returned empty results, using generic extraction" "entity_extractors" "extract_entities_image_generic"
        fi
    fi
    
    # Fall back to generic extraction
    extract_entities_fallback "$content" "$options"
}

extract_entities_video_generic() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from generic video" "entity_extractors" "extract_entities_video_generic"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null && [[ -f "$content" ]]; then
        log_debug "Using Claude for generic video entity extraction" "entity_extractors" "extract_entities_video_generic"
        
        # Determine the video mime type
        local mime_type
        mime_type=$(file --mime-type -b "$content")
        
        # Extract video metadata if available
        if command -v ffprobe &> /dev/null; then
            local video_meta
            video_meta=$(ffprobe -v quiet -print_format json -show_format -show_streams "$content")
            
            # Call extract_entities_with_claude with the video metadata
            local entities
            entities=$(extract_entities_with_claude "$video_meta" "application/json" "$options,context=video_metadata")
            
            # Check if extraction was successful
            if [[ -n "$entities" && "$entities" != "[]" ]]; then
                echo "$entities"
                return 0
            fi
        else
            # Try direct extraction
            local entities
            entities=$(extract_entities_with_claude "$content" "$mime_type" "$options")
            
            # Check if extraction was successful
            if [[ -n "$entities" && "$entities" != "[]" ]]; then
                echo "$entities"
                return 0
            fi
        fi
    fi
    
    # Fall back to generic extraction
    extract_entities_fallback "$content" "$options"
}

extract_entities_code_generic() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from generic code" "entity_extractors" "extract_entities_code_generic"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using extract_entities_with_claude for generic code entity extraction" "entity_extractors" "extract_entities_code_generic"
        
        # Determine language from file extension or content patterns if possible
        local language="unknown"
        local mime_type="text/plain"
        if [[ -f "$content" ]]; then
            local file_ext="${content##*.}"
            
            case "$file_ext" in
                py)       language="python"; mime_type="text/x-python" ;;
                js)       language="javascript"; mime_type="text/javascript" ;;
                ts)       language="typescript"; mime_type="text/typescript" ;;
                c|h)      language="c"; mime_type="text/x-c" ;;
                cpp|cxx)  language="cpp"; mime_type="text/x-c++" ;;
                java)     language="java"; mime_type="text/x-java" ;;
                sh|bash)  language="shell"; mime_type="application/x-sh" ;;
                *)        language="unknown"; mime_type="text/plain" ;;
            esac
        fi
        
        # Add language to options if identified
        local enhanced_options="${options:+$options,}content=code"
        if [[ "$language" != "unknown" ]]; then
            enhanced_options="$enhanced_options,language=$language"
        fi
        
        # Call extract_entities_with_claude with generic code type
        local entities
        entities=$(extract_entities_with_claude "$content" "$mime_type" "$enhanced_options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with Claude" "entity_extractors" "extract_entities_code_generic"
            echo "$entities"
            return 0
        else
            log_warning "extract_entities_with_claude returned empty results, trying fallback" "entity_extractors" "extract_entities_code_generic"
        fi
    fi
    
    # If extract_entities_with_claude failed or isn't available, try analyze_with_claude
    if type analyze_with_claude &>/dev/null; then
        log_debug "Using analyze_with_claude for generic code entity extraction" "entity_extractors" "extract_entities_code_generic"
        
        local claude_response
        claude_response=$(analyze_with_claude "$content" "code")
        
        # Extract entities from Claude's response
        local entities
        entities=$(extract_entities_from_json "$claude_response")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            log_debug "Successfully extracted entities with analyze_with_claude" "entity_extractors" "extract_entities_code_generic"
            echo "$entities"
            return 0
        else
            log_warning "analyze_with_claude returned empty results, using standard extraction" "entity_extractors" "extract_entities_code_generic"
        fi
    fi
    
    # Fall back to standard code extraction
    extract_entities_code "$content" "$options"
}

extract_entities_generic() {
    local content="$1"
    local options="$2"
    
    log_debug "Extracting entities from generic content" "entity_extractors" "extract_entities_generic"
    
    # Try to use extract_entities_with_claude if available
    if type extract_entities_with_claude &>/dev/null; then
        log_debug "Using Claude for generic content entity extraction" "entity_extractors" "extract_entities_generic"
        
        # Determine MIME type if content is a file
        local mime_type="text/plain"
        if [[ -f "$content" ]]; then
            mime_type=$(file --mime-type -b "$content")
        fi
        
        # Call extract_entities_with_claude with the detected mime type
        local entities
        entities=$(extract_entities_with_claude "$content" "$mime_type" "$options")
        
        # Check if extraction was successful
        if [[ -n "$entities" && "$entities" != "[]" ]]; then
            echo "$entities"
            return 0
        fi
    fi
    
    # Fall back to generic extraction
    extract_entities_fallback "$content" "$options"
}

# Initialize entity extractors if not already
if [[ -z "${ENTITY_EXTRACTORS[*]-}" ]]; then
    # Create the associative array
    declare -A ENTITY_EXTRACTORS
    
    # Initialize extractors
    init_entity_extractors
fi