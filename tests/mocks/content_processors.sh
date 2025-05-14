#!/bin/bash
# Mock content processors for testing

# Source mock logging
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/structured_logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/content.sh"

# Default log level
LOG_LEVEL="${LOG_LEVEL:-info}"

# Default temp directory
TEMP_DIR="${TEMP_DIR:-/tmp/ingestor-temp}"
mkdir -p "$TEMP_DIR" 2>/dev/null || true

# Create the associative array
declare -A CONTENT_PROCESSORS

# Initialize content processors
init_content_processors() {
    log_debug "Initializing content processors" "content_processors" "init_content_processors"
    
    # Register available processors
    CONTENT_PROCESSORS["text/plain"]="process_text_plain"
    CONTENT_PROCESSORS["text/markdown"]="process_text_markdown"
    CONTENT_PROCESSORS["text/html"]="process_text_html"
    CONTENT_PROCESSORS["application/json"]="process_application_json"
    CONTENT_PROCESSORS["application/xml"]="process_application_xml"
    CONTENT_PROCESSORS["text/csv"]="process_text_csv"
    
    # Default fallbacks by category
    CONTENT_PROCESSORS["text/*"]="process_text_generic"
    CONTENT_PROCESSORS["application/*"]="process_application_generic"
    
    log_debug "Content processors initialized" "content_processors" "init_content_processors"
}

# Helper function to JSON escape string
json_escape() {
    local content="$1"
    content="${content//\\/\\\\}"    # Escape backslashes
    content="${content//\"/\\\"}"    # Escape double quotes
    content="${content//	/\\t}"     # Escape tabs
    content="${content//$'\n'/\\n}"  # Escape newlines
    content="${content//$'\r'/\\r}"  # Escape carriage returns
    echo "$content"
}

# Main content processing function
process_content() {
    local file_path="$1"
    local content_type="$2"
    local options="$3"
    
    log_info "Processing content: $file_path ($content_type)" "content_processors" "process_content"
    
    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path" "content_processors" "process_content"
        return 1
    fi
    
    # Get the processor for this content type
    local processor="${CONTENT_PROCESSORS[$content_type]}"
    
    # If no exact match, try generic handler based on category
    if [[ -z "$processor" ]]; then
        local category="${content_type%%/*}/*"
        processor="${CONTENT_PROCESSORS[$category]}"
        
        # If still no match, use the fallback processor
        if [[ -z "$processor" ]]; then
            log_warning "No processor found for content type: $content_type, using fallback" "content_processors" "process_content"
            processor="process_fallback"
        else
            log_debug "Using category processor: $processor for $content_type" "content_processors" "process_content"
        fi
    else
        log_debug "Using specific processor: $processor for $content_type" "content_processors" "process_content"
    fi
    
    # Process content using the appropriate processor
    $processor "$file_path" "$options"
    
    return $?
}

# Text processors
process_text_plain() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing plain text file: $file_path" "content_processors" "process_text_plain"
    
    # Simple processing - just read the file content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"lines\":10,\"words\":100,\"size\":1000},\"content_type\":\"text/plain\"}"
    
    return 0
}

process_text_markdown() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing markdown file: $file_path" "content_processors" "process_text_markdown"
    
    # Read first line as title
    local title="$(head -n 1 "$file_path" | sed 's/^#* //' | sed 's/"/\\"/g')"
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"title\":\"$title\"},\"content_type\":\"text/markdown\"}"
    
    return 0
}

process_text_html() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing HTML file: $file_path" "content_processors" "process_text_html"
    
    # Extract title if present
    local title="$(grep -o '<title>[^<]*</title>' "$file_path" | sed 's/<title>\(.*\)<\/title>/\1/' | sed 's/"/\\"/g')"
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"title\":\"$title\"},\"content_type\":\"text/html\"}"
    
    return 0
}

process_application_json() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing JSON file: $file_path" "content_processors" "process_application_json"
    
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"valid\":true},\"content_type\":\"application/json\"}"
    
    return 0
}

process_application_xml() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing XML file: $file_path" "content_processors" "process_application_xml"
    
    # Extract root element
    local root_elem="$(grep -o '<[^? ][^ >]*' "$file_path" | head -n 1 | sed 's/<//g' | sed 's/"/\\"/g')"
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"root_element\":\"$root_elem\"},\"content_type\":\"application/xml\"}"
    
    return 0
}

process_text_csv() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing CSV file: $file_path" "content_processors" "process_text_csv"
    
    # Extract headers
    local headers="$(head -n 1 "$file_path" | sed 's/"/\\"/g')"
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"headers\":\"$headers\",\"rows\":3,\"columns\":3},\"content_type\":\"text/csv\"}"
    
    return 0
}

process_text_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing generic text file: $file_path" "content_processors" "process_text_generic"
    
    # Similar to plain text but with less assumptions
    process_text_plain "$file_path" "$options"
    
    return $?
}

process_application_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing generic application file: $file_path" "content_processors" "process_application_generic"
    
    # Generic application processor
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{\"mimetype\":\"application/octet-stream\"},\"content_type\":\"application/octet-stream\"}"
    
    return 0
}

process_fallback() {
    local file_path="$1"
    local options="$2"
    
    log_warning "Using fallback processor: $file_path" "content_processors" "process_fallback"
    
    # Fallback for unknown types
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON result
    echo "{\"text\":\"$escaped_content\",\"metadata\":{},\"content_type\":\"application/octet-stream\"}"
    
    return 0
}

# Initialize content processors if not already
if [[ -z "${CONTENT_PROCESSORS[*]}" ]]; then
    init_content_processors
fi