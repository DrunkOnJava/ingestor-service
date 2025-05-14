#!/bin/bash
# Content type processors for different file formats
#
# This module provides specialized processors for different content types
# Each processor extracts text and metadata appropriate for the content type

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
    source "$(dirname "${BASH_SOURCE[0]}")/content.sh" 2>/dev/null || true
    source "$(dirname "${BASH_SOURCE[0]}")/entity_extractors.sh" 2>/dev/null || true
    MODULES_LOADED=1
fi

# Initialize content processors
init_content_processors() {
    log_debug "Initializing content processors" "content_processors" "init_content_processors"
    
    # Create temporary directory if needed
    if [[ ! -d "$TEMP_DIR" ]]; then
        mkdir -p "$TEMP_DIR"
        log_debug "Created temporary directory: $TEMP_DIR" "content_processors" "init_content_processors"
    fi
    
    # Register available processors
    CONTENT_PROCESSORS["text/plain"]="process_text_plain"
    CONTENT_PROCESSORS["text/markdown"]="process_text_markdown"
    CONTENT_PROCESSORS["text/html"]="process_text_html"
    CONTENT_PROCESSORS["application/pdf"]="process_application_pdf"
    CONTENT_PROCESSORS["application/json"]="process_application_json"
    CONTENT_PROCESSORS["application/xml"]="process_application_xml"
    CONTENT_PROCESSORS["image/jpeg"]="process_image_jpeg"
    CONTENT_PROCESSORS["image/png"]="process_image_png"
    CONTENT_PROCESSORS["video/mp4"]="process_video_mp4"
    CONTENT_PROCESSORS["video/quicktime"]="process_video_quicktime"
    CONTENT_PROCESSORS["application/zip"]="process_application_zip"
    CONTENT_PROCESSORS["application/octet-stream"]="process_application_binary"
    CONTENT_PROCESSORS["text/csv"]="process_text_csv"
    CONTENT_PROCESSORS["application/vnd.openxmlformats-officedocument.wordprocessingml.document"]="process_office_docx"
    CONTENT_PROCESSORS["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"]="process_office_xlsx"
    CONTENT_PROCESSORS["application/vnd.openxmlformats-officedocument.presentationml.presentation"]="process_office_pptx"
    
    # Additional common document types
    CONTENT_PROCESSORS["application/rtf"]="process_text_rtf"
    CONTENT_PROCESSORS["application/vnd.ms-word"]="process_office_doc"
    CONTENT_PROCESSORS["application/vnd.ms-excel"]="process_office_xls"
    CONTENT_PROCESSORS["application/vnd.ms-powerpoint"]="process_office_ppt"
    CONTENT_PROCESSORS["text/x-python"]="process_code_python"
    CONTENT_PROCESSORS["text/javascript"]="process_code_javascript"
    CONTENT_PROCESSORS["text/x-c"]="process_code_c"
    CONTENT_PROCESSORS["application/x-sh"]="process_code_shell"
    
    # Additional image formats
    CONTENT_PROCESSORS["image/gif"]="process_image_gif"
    CONTENT_PROCESSORS["image/svg+xml"]="process_image_svg"
    CONTENT_PROCESSORS["image/webp"]="process_image_webp"
    
    # Audio formats
    CONTENT_PROCESSORS["audio/mpeg"]="process_audio_mp3"
    CONTENT_PROCESSORS["audio/wav"]="process_audio_wav"
    CONTENT_PROCESSORS["audio/ogg"]="process_audio_ogg"
    
    # Default fallbacks by category
    CONTENT_PROCESSORS["text/*"]="process_text_generic"
    CONTENT_PROCESSORS["image/*"]="process_image_generic"
    CONTENT_PROCESSORS["video/*"]="process_video_generic"
    CONTENT_PROCESSORS["application/*"]="process_application_generic"
    CONTENT_PROCESSORS["audio/*"]="process_audio_generic"
    CONTENT_PROCESSORS["text/x-*"]="process_code_generic"
    
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
    local processed_content
    processed_content=$($processor "$file_path" "$options")
    local processor_exit_code=$?
    
    # If processing failed, return the error
    if [[ $processor_exit_code -ne 0 ]]; then
        echo "$processed_content"
        return $processor_exit_code
    fi
    
    # Check if entity extraction is enabled in options
    if [[ "$options" == *"extract_entities=true"* || "$options" == *"extract_entities=1"* ]]; then
        log_info "Extracting entities from processed content" "content_processors" "process_content"
        
        # Check if entity_extractors module is available
        if type extract_entities &>/dev/null; then
            # Extract entities from the processed content
            local entities
            entities=$(extract_entities "$file_path" "$content_type" "$options")
            local extraction_exit_code=$?
            
            if [[ $extraction_exit_code -eq 0 && -n "$entities" ]]; then
                # Add entities to the processed content JSON
                # First check if processed_content is valid JSON
                if echo "$processed_content" | jq . >/dev/null 2>&1; then
                    # If content already has an "entities" field, don't overwrite it
                    if echo "$processed_content" | jq -e '.entities' >/dev/null 2>&1; then
                        log_debug "Content already has entities field, not overwriting" "content_processors" "process_content"
                    else
                        # Add entities field to the JSON
                        processed_content=$(echo "$processed_content" | jq --argjson entities "$entities" '. + {entities: $entities}')
                    fi
                else
                    log_warning "Processed content is not valid JSON, can't add entities" "content_processors" "process_content"
                fi
            else
                log_warning "Entity extraction failed or returned empty results" "content_processors" "process_content"
            fi
        else
            log_warning "Entity extraction module not available" "content_processors" "process_content"
        fi
    fi
    
    echo "$processed_content"
    return $processor_exit_code
}

# Text processors
process_text_plain() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing plain text file: $file_path" "content_processors" "process_text_plain"
    
    # Simple processing - just read the file content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata
    local lines="$(wc -l < "$file_path")"
    local words="$(wc -w < "$file_path")"
    local size="$(wc -c < "$file_path")"
    
    # Create JSON metadata
    local metadata="{\"lines\":$lines,\"words\":$words,\"size\":$size,\"encoding\":\"UTF-8\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/plain\"}"
    
    return 0
}

process_text_markdown() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing markdown file: $file_path" "content_processors" "process_text_markdown"
    
    # Read the markdown content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata (titles, structure)
    local title="$(head -n 1 "$file_path" | sed 's/^#* //' | sed 's/"/\\"/g')"
    local headings="$(grep -E '^#{1,6} ' "$file_path" | sed 's/^#* //' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local codeblocks="$(grep -c '```' "$file_path")"
    
    # Create JSON metadata
    local metadata="{\"title\":\"$title\",\"headings\":\"$headings\",\"codeblocks\":$codeblocks}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/markdown\"}"
    
    return 0
}

process_text_html() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing HTML file: $file_path" "content_processors" "process_text_html"
    
    # Read the HTML content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract text content (simplified approach)
    local text_content="$(cat "$file_path" | sed 's/<[^>]*>//g' | sed '/^$/d')"
    local escaped_text="$(json_escape "$text_content")"
    
    # Extract title
    local title="$(grep -o '<title>[^<]*</title>' "$file_path" | sed 's/<title>\(.*\)<\/title>/\1/' | sed 's/"/\\"/g')" 
    
    # Extract metadata
    local links="$(grep -o 'href="[^"]*"' "$file_path" | sed 's/href="//g' | sed 's/"//g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local images="$(grep -o 'src="[^"]*"' "$file_path" | sed 's/src="//g' | sed 's/"//g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    
    # Create JSON metadata
    local metadata="{\"title\":\"$title\",\"links\":\"$links\",\"images\":\"$images\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_text\",\"html\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/html\"}"
    
    return 0
}

process_text_csv() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing CSV file: $file_path" "content_processors" "process_text_csv"
    
    # Read the CSV content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract headers (first line)
    local headers="$(head -n 1 "$file_path" | sed 's/"/\\"/g')"
    
    # Count rows and columns
    local rows="$(wc -l < "$file_path")"
    local columns="$(head -n 1 "$file_path" | awk -F, '{print NF}')"
    
    # Create JSON metadata
    local metadata="{\"headers\":\"$headers\",\"rows\":$rows,\"columns\":$columns}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/csv\"}"
    
    return 0
}

process_text_rtf() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing RTF file: $file_path" "content_processors" "process_text_rtf"
    
    # Check if 'unrtf' is available
    if ! command -v unrtf &> /dev/null; then
        log_warning "unrtf not found, using fallback extraction" "content_processors" "process_text_rtf"
        
        # Read raw content (not ideal for RTF)
        local content="$(cat "$file_path" | tr -d '\000' | grep -v '^[\{\}\\]' | tr -s ' ')"
        local escaped_content="$(json_escape "$content")"
        
        # Create minimal metadata
        local metadata="{\"title\":\"$(basename "$file_path")\",\"format\":\"RTF\"}"
        
        # Generate result
        echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/rtf\"}"
        return 0
    fi
    
    # Extract text using unrtf
    local temp_file="${TEMP_DIR}/$(basename "$file_path").txt"
    unrtf --text "$file_path" > "$temp_file" 2>/dev/null
    
    # Read the extracted text
    local content="$(cat "$temp_file" | sed '1,3d')" # Remove unrtf header
    local escaped_content="$(json_escape "$content")"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Create metadata
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local metadata="{\"format\":\"RTF\",\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/rtf\"}"
    
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

# Application processors
process_application_pdf() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing PDF file: $file_path" "content_processors" "process_application_pdf"
    
    # Check if pdftotext is available
    if ! command -v pdftotext &> /dev/null; then
        log_warning "pdftotext not found, using fallback extraction" "content_processors" "process_application_pdf"
        
        # Create minimal metadata
        local metadata="{\"title\":\"$(basename "$file_path")\",\"pages\":0}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/pdf\",\"error\":\"pdftotext not available\"}"
        return 1
    fi
    
    # Create temporary file for extracted text
    local temp_file="${TEMP_DIR}/$(basename "$file_path").txt"
    
    # Extract text from PDF
    pdftotext "$file_path" "$temp_file"
    
    # Read the extracted text
    local content="$(cat "$temp_file")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata if pdfinfo is available
    local metadata="{}"
    if command -v pdfinfo &> /dev/null; then
        local info="$(pdfinfo "$file_path")"
        local title="$(echo "$info" | grep "Title:" | sed 's/Title:\s*//' | sed 's/"/\\"/g')"
        local author="$(echo "$info" | grep "Author:" | sed 's/Author:\s*//' | sed 's/"/\\"/g')"
        local pages="$(echo "$info" | grep "Pages:" | sed 's/Pages:\s*//')"
        local created="$(echo "$info" | grep "CreationDate:" | sed 's/CreationDate:\s*//' | sed 's/"/\\"/g')"
        
        metadata="{\"title\":\"$title\",\"author\":\"$author\",\"pages\":$pages,\"created\":\"$created\"}"
    else
        log_warning "pdfinfo not found, using limited metadata" "content_processors" "process_application_pdf"
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        metadata="{\"title\":\"$title\"}"
    fi
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/pdf\"}"
    
    return 0
}

process_application_json() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing JSON file: $file_path" "content_processors" "process_application_json"
    
    # Read the JSON content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Validate JSON if jq is available
    local valid=true
    if command -v jq &> /dev/null; then
        if ! cat "$file_path" | jq . >/dev/null 2>&1; then
            valid=false
            log_warning "Invalid JSON file: $file_path" "content_processors" "process_application_json"
        fi
    fi
    
    # Extract metadata
    local size="$(wc -c < "$file_path")"
    local keys=""
    if $valid && command -v jq &> /dev/null; then
        keys="$(cat "$file_path" | jq -r 'keys | join("|")' 2>/dev/null || echo "")"
        keys="$(echo "$keys" | sed 's/"/\\"/g')"
    fi
    
    # Create JSON metadata
    local metadata="{\"valid\":$valid,\"size\":$size,\"keys\":\"$keys\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/json\"}"
    
    return 0
}

process_application_xml() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing XML file: $file_path" "content_processors" "process_application_xml"
    
    # Read the XML content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata
    local root_elem="$(grep -o '<[^? ][^ >]*' "$file_path" | head -n 1 | sed 's/<//g' | sed 's/"/\\"/g')"
    local size="$(wc -c < "$file_path")"
    
    # Create JSON metadata
    local metadata="{\"root_element\":\"$root_elem\",\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/xml\"}"
    
    return 0
}

process_office_docx() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing DOCX file: $file_path" "content_processors" "process_office_docx"
    
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log_warning "unzip not found, using fallback extraction" "content_processors" "process_office_docx"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/vnd.openxmlformats-officedocument.wordprocessingml.document\",\"error\":\"unzip not available\"}"
        return 1
    fi
    
    # Create temporary directory for extraction
    local temp_dir="${TEMP_DIR}/$(basename "$file_path")_$(date +%s%N | cut -b1-13)"
    mkdir -p "$temp_dir"
    
    # Extract DOCX contents
    unzip -q "$file_path" -d "$temp_dir"
    
    # Extract text content (simplified approach)
    local content=""
    if [[ -f "$temp_dir/word/document.xml" ]]; then
        content="$(cat "$temp_dir/word/document.xml" | sed 's/<[^>]*>//g' | sed '/^$/d')"
    fi
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata from core.xml if it exists
    local metadata="{}"
    if [[ -f "$temp_dir/docProps/core.xml" ]]; then
        local title="$(grep -o '<dc:title>[^<]*</dc:title>' "$temp_dir/docProps/core.xml" | sed 's/<dc:title>\(.*\)<\/dc:title>/\1/' | sed 's/"/\\"/g')"
        local creator="$(grep -o '<dc:creator>[^<]*</dc:creator>' "$temp_dir/docProps/core.xml" | sed 's/<dc:creator>\(.*\)<\/dc:creator>/\1/' | sed 's/"/\\"/g')"
        local created="$(grep -o '<dcterms:created>[^<]*</dcterms:created>' "$temp_dir/docProps/core.xml" | sed 's/<dcterms:created>\(.*\)<\/dcterms:created>/\1/' | sed 's/"/\\"/g')"
        local modified="$(grep -o '<dcterms:modified>[^<]*</dcterms:modified>' "$temp_dir/docProps/core.xml" | sed 's/<dcterms:modified>\(.*\)<\/dcterms:modified>/\1/' | sed 's/"/\\"/g')"
        
        metadata="{\"title\":\"$title\",\"creator\":\"$creator\",\"created\":\"$created\",\"modified\":\"$modified\"}"
    else
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        metadata="{\"title\":\"$title\"}"
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/vnd.openxmlformats-officedocument.wordprocessingml.document\"}"
    
    return 0
}

process_office_doc() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing DOC file: $file_path" "content_processors" "process_office_doc"
    
    # Check if antiword is available
    if ! command -v antiword &> /dev/null; then
        log_warning "antiword not found, using fallback extraction" "content_processors" "process_office_doc"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/vnd.ms-word\",\"error\":\"antiword not available\"}"
        return 1
    fi
    
    # Extract text using antiword
    local temp_file="${TEMP_DIR}/$(basename "$file_path").txt"
    antiword "$file_path" > "$temp_file" 2>/dev/null
    
    # Read the extracted text
    local content="$(cat "$temp_file")"
    local escaped_content="$(json_escape "$content")"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Create basic metadata
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local title="$(basename "$file_path" | sed 's/"/\\"/g')"
    local metadata="{\"title\":\"$title\",\"size\":$size,\"format\":\"MS Word Document\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/vnd.ms-word\"}"
    
    return 0
}

process_office_xlsx() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing XLSX file: $file_path" "content_processors" "process_office_xlsx"
    
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log_warning "unzip not found, using fallback extraction" "content_processors" "process_office_xlsx"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\",\"error\":\"unzip not available\"}"
        return 1
    fi
    
    # Create temporary directory for extraction
    local temp_dir="${TEMP_DIR}/$(basename "$file_path")_$(date +%s%N | cut -b1-13)"
    mkdir -p "$temp_dir"
    
    # Extract XLSX contents
    unzip -q "$file_path" -d "$temp_dir"
    
    # Extract metadata from workbook.xml if it exists
    local sheet_names=""
    if [[ -f "$temp_dir/xl/workbook.xml" ]]; then
        sheet_names="$(grep -o '<sheet name="[^"]*"' "$temp_dir/xl/workbook.xml" | sed 's/<sheet name="//g' | sed 's/"//g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    fi
    
    # Create minimal content representation
    local content="XLSX file with sheets: $sheet_names"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata from core.xml if it exists
    local metadata="{}"
    if [[ -f "$temp_dir/docProps/core.xml" ]]; then
        local title="$(grep -o '<dc:title>[^<]*</dc:title>' "$temp_dir/docProps/core.xml" | sed 's/<dc:title>\(.*\)<\/dc:title>/\1/' | sed 's/"/\\"/g')"
        local creator="$(grep -o '<dc:creator>[^<]*</dc:creator>' "$temp_dir/docProps/core.xml" | sed 's/<dc:creator>\(.*\)<\/dc:creator>/\1/' | sed 's/"/\\"/g')"
        
        metadata="{\"title\":\"$title\",\"creator\":\"$creator\",\"sheets\":\"$sheet_names\"}"
    else
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        metadata="{\"title\":\"$title\",\"sheets\":\"$sheet_names\"}"
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"}"
    
    return 0
}

process_office_xls() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing XLS file: $file_path" "content_processors" "process_office_xls"
    
    # Check if xls2csv is available (part of catdoc package)
    if ! command -v xls2csv &> /dev/null; then
        log_warning "xls2csv not found, using fallback extraction" "content_processors" "process_office_xls"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/vnd.ms-excel\",\"error\":\"xls2csv not available\"}"
        return 1
    fi
    
    # Extract CSV using xls2csv
    local temp_file="${TEMP_DIR}/$(basename "$file_path").csv"
    xls2csv "$file_path" > "$temp_file" 2>/dev/null
    
    # Read the extracted text
    local content="$(cat "$temp_file")"
    local escaped_content="$(json_escape "$content")"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Create basic metadata
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local title="$(basename "$file_path" | sed 's/"/\\"/g')"
    local metadata="{\"title\":\"$title\",\"size\":$size,\"format\":\"MS Excel Spreadsheet\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/vnd.ms-excel\"}"
    
    return 0
}

process_office_pptx() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing PPTX file: $file_path" "content_processors" "process_office_pptx"
    
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log_warning "unzip not found, using fallback extraction" "content_processors" "process_office_pptx"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/vnd.openxmlformats-officedocument.presentationml.presentation\",\"error\":\"unzip not available\"}"
        return 1
    fi
    
    # Create temporary directory for extraction
    local temp_dir="${TEMP_DIR}/$(basename "$file_path")_$(date +%s%N | cut -b1-13)"
    mkdir -p "$temp_dir"
    
    # Extract PPTX contents
    unzip -q "$file_path" -d "$temp_dir"
    
    # Extract text content (simplified approach)
    local content=""
    local slides=0
    
    # Count slides
    if [[ -d "$temp_dir/ppt/slides" ]]; then
        slides="$(find "$temp_dir/ppt/slides" -name "*.xml" | wc -l)"
        
        # Extract text from slides
        for slide in "$temp_dir/ppt/slides/slide"*.xml; do
            if [[ -f "$slide" ]]; then
                content+="$(cat "$slide" | sed 's/<[^>]*>//g' | sed '/^$/d')"
                content+=$'\n---\n'
            fi
        done
    fi
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata from core.xml if it exists
    local metadata="{}"
    if [[ -f "$temp_dir/docProps/core.xml" ]]; then
        local title="$(grep -o '<dc:title>[^<]*</dc:title>' "$temp_dir/docProps/core.xml" | sed 's/<dc:title>\(.*\)<\/dc:title>/\1/' | sed 's/"/\\"/g')"
        local creator="$(grep -o '<dc:creator>[^<]*</dc:creator>' "$temp_dir/docProps/core.xml" | sed 's/<dc:creator>\(.*\)<\/dc:creator>/\1/' | sed 's/"/\\"/g')"
        
        metadata="{\"title\":\"$title\",\"creator\":\"$creator\",\"slides\":$slides}"
    else
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        metadata="{\"title\":\"$title\",\"slides\":$slides}"
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/vnd.openxmlformats-officedocument.presentationml.presentation\"}"
    
    return 0
}

process_office_ppt() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing PPT file: $file_path" "content_processors" "process_office_ppt"
    
    # Check if catppt is available (part of catdoc package)
    if ! command -v catppt &> /dev/null; then
        log_warning "catppt not found, using fallback extraction" "content_processors" "process_office_ppt"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/vnd.ms-powerpoint\",\"error\":\"catppt not available\"}"
        return 1
    fi
    
    # Extract text using catppt
    local temp_file="${TEMP_DIR}/$(basename "$file_path").txt"
    catppt "$file_path" > "$temp_file" 2>/dev/null
    
    # Read the extracted text
    local content="$(cat "$temp_file")"
    local escaped_content="$(json_escape "$content")"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Create basic metadata
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local title="$(basename "$file_path" | sed 's/"/\\"/g')"
    local metadata="{\"title\":\"$title\",\"size\":$size,\"format\":\"MS PowerPoint Presentation\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/vnd.ms-powerpoint\"}"
    
    return 0
}

process_application_zip() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing ZIP file: $file_path" "content_processors" "process_application_zip"
    
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log_warning "unzip not found, using fallback extraction" "content_processors" "process_application_zip"
        
        # Create minimal metadata
        local title="$(basename "$file_path" | sed 's/"/\\"/g')"
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result with empty text
        echo "{\"text\":\"\",\"metadata\":$metadata,\"content_type\":\"application/zip\",\"error\":\"unzip not available\"}"
        return 1
    fi
    
    # Extract file list
    local file_list="$(unzip -l "$file_path" | tail -n +4 | head -n -2 | awk '{print $4}' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    
    # Count files and get total size
    local file_count="$(unzip -l "$file_path" | tail -n +4 | head -n -2 | wc -l)"
    local total_size="$(unzip -l "$file_path" | tail -n -2 | head -n 1 | awk '{print $1}')"
    
    # Create content summary
    local content="ZIP archive containing $file_count files:\n\n$(unzip -l "$file_path" | head -n -2 | tail -n +4 | awk '{print $4}')"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"file_count\":$file_count,\"total_size\":$total_size,\"files\":\"$file_list\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/zip\"}"
    
    return 0
}

process_application_binary() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing binary file: $file_path" "content_processors" "process_application_binary"
    
    # Get file information using 'file' command
    local file_info="$(file "$file_path" | sed 's/"/\\"/g')"
    
    # Create simple metadata
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local mimetype="$(file --mime-type -b "$file_path" | sed 's/"/\\"/g')"
    
    # Create basic content description
    local content="Binary file: $(basename "$file_path")\nType: $mimetype\nSize: $size bytes\nInfo: $file_info"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"size\":$size,\"mimetype\":\"$mimetype\",\"file_info\":\"$file_info\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/octet-stream\"}"
    
    return 0
}

process_application_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing generic application file: $file_path" "content_processors" "process_application_generic"
    
    # Default to binary processor for unknown application types
    process_application_binary "$file_path" "$options"
    
    return $?
}

# Code processors
process_code_python() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing Python code file: $file_path" "content_processors" "process_code_python"
    
    # Read the code content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata
    local imports="$(grep -E '^import|^from .* import' "$file_path" | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local classes="$(grep -E '^class ' "$file_path" | sed 's/class \([^(:]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local functions="$(grep -E '^def ' "$file_path" | sed 's/def \([^(]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local docstring=""
    
    # Try to extract module docstring (first string after imports)
    if grep -q '"""' "$file_path"; then
        docstring="$(sed -n '/^"""/,/"""/p' "$file_path" | sed 's/^"""\(.*\)"""/\1/g' | head -1 | sed 's/"/\\"/g')"
    fi
    
    # Create JSON metadata
    local metadata="{\"imports\":\"$imports\",\"classes\":\"$classes\",\"functions\":\"$functions\",\"docstring\":\"$docstring\",\"language\":\"python\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/x-python\"}"
    
    return 0
}

process_code_javascript() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing JavaScript code file: $file_path" "content_processors" "process_code_javascript"
    
    # Read the code content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata
    local imports="$(grep -E 'import |require\(' "$file_path" | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local functions="$(grep -E 'function [a-zA-Z0-9_]+\(' "$file_path" | sed 's/function \([^(]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local classes="$(grep -E 'class [a-zA-Z0-9_]+ ' "$file_path" | sed 's/class \([^ {]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    
    # Create JSON metadata
    local metadata="{\"imports\":\"$imports\",\"functions\":\"$functions\",\"classes\":\"$classes\",\"language\":\"javascript\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/javascript\"}"
    
    return 0
}

process_code_c() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing C/C++ code file: $file_path" "content_processors" "process_code_c"
    
    # Read the code content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata
    local includes="$(grep -E '^#include' "$file_path" | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local functions="$(grep -E '^[a-zA-Z0-9_]+ [a-zA-Z0-9_]+\(' "$file_path" | sed 's/[a-zA-Z0-9_]* \([^(]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    local structs="$(grep -E '^struct [a-zA-Z0-9_]+ ' "$file_path" | sed 's/struct \([^ {]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    
    # Determine if C or C++
    local lang="c"
    if grep -q "class" "$file_path" || grep -q "namespace" "$file_path" || [[ "$file_path" =~ \.(cpp|cxx|cc|hpp)$ ]]; then
        lang="c++"
    fi
    
    # Create JSON metadata
    local metadata="{\"includes\":\"$includes\",\"functions\":\"$functions\",\"structs\":\"$structs\",\"language\":\"$lang\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/x-c\"}"
    
    return 0
}

process_code_shell() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing shell script file: $file_path" "content_processors" "process_code_shell"
    
    # Read the code content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Extract metadata
    local shebang="$(head -n 1 "$file_path" | grep -E '^#!' | sed 's/"/\\"/g')"
    local functions="$(grep -E '^[a-zA-Z0-9_]+\(\)' "$file_path" | sed 's/\([^(]*\).*/\1/g' | sed 's/"/\\"/g' | tr '\n' '|' | sed 's/|$//')"
    
    # Determine shell type from shebang
    local shell_type="sh"
    if [[ "$shebang" =~ bash ]]; then
        shell_type="bash"
    elif [[ "$shebang" =~ zsh ]]; then
        shell_type="zsh"
    elif [[ "$shebang" =~ ksh ]]; then
        shell_type="ksh"
    fi
    
    # Create JSON metadata
    local metadata="{\"shebang\":\"$shebang\",\"functions\":\"$functions\",\"shell_type\":\"$shell_type\",\"language\":\"shell\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/x-sh\"}"
    
    return 0
}

process_code_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing generic code file: $file_path" "content_processors" "process_code_generic"
    
    # Read the code content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Try to determine language type based on file extension
    local ext="${file_path##*.}"
    local lang="unknown"
    case "$ext" in
        py)    lang="python" ;;
        js)    lang="javascript" ;;
        ts)    lang="typescript" ;;
        c|h)   lang="c" ;;
        cpp|cxx|cc|hpp) lang="c++" ;;
        java)  lang="java" ;;
        rb)    lang="ruby" ;;
        php)   lang="php" ;;
        go)    lang="go" ;;
        rs)    lang="rust" ;;
        swift) lang="swift" ;;
        sh|bash) lang="shell" ;;
        pl)    lang="perl" ;;
        cs)    lang="csharp" ;;
        r)     lang="r" ;;
        *)     lang="unknown" ;;
    esac
    
    # Create JSON metadata
    local lines="$(wc -l < "$file_path")"
    local size="$(wc -c < "$file_path")"
    local metadata="{\"language\":\"$lang\",\"extension\":\"$ext\",\"lines\":$lines,\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/plain\"}"
    
    return 0
}

# Image processors
process_image_jpeg() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing JPEG image: $file_path" "content_processors" "process_image_jpeg"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract image dimensions if identify (ImageMagick) is available
    local width=0
    local height=0
    if command -v identify &> /dev/null; then
        width="$(identify -format "%w" "$file_path" 2>/dev/null || echo 0)"
        height="$(identify -format "%h" "$file_path" 2>/dev/null || echo 0)"
    fi
    
    # Extract EXIF data if exiftool is available
    local exif_data="{}"
    if command -v exiftool &> /dev/null; then
        local date_taken="$(exiftool -s -s -s -DateTimeOriginal "$file_path" 2>/dev/null || echo "")"
        local camera_model="$(exiftool -s -s -s -Model "$file_path" 2>/dev/null || echo "")"
        local gps_position="$(exiftool -s -s -s -GPSPosition "$file_path" 2>/dev/null || echo "")"
        
        # Escape JSON special characters
        date_taken="$(echo "$date_taken" | sed 's/"/\\"/g')"
        camera_model="$(echo "$camera_model" | sed 's/"/\\"/g')"
        gps_position="$(echo "$gps_position" | sed 's/"/\\"/g')"
        
        exif_data="{\"date_taken\":\"$date_taken\",\"camera_model\":\"$camera_model\",\"gps_position\":\"$gps_position\"}"
    fi
    
    # Create content description
    local content="JPEG image: $(basename "$file_path")\nDimensions: ${width}x${height}\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"width\":$width,\"height\":$height,\"size\":$size,\"exif\":$exif_data}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"image/jpeg\"}"
    
    return 0
}

process_image_png() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing PNG image: $file_path" "content_processors" "process_image_png"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract image dimensions if identify (ImageMagick) is available
    local width=0
    local height=0
    if command -v identify &> /dev/null; then
        width="$(identify -format "%w" "$file_path" 2>/dev/null || echo 0)"
        height="$(identify -format "%h" "$file_path" 2>/dev/null || echo 0)"
    fi
    
    # Check for transparency
    local alpha="false"
    if command -v identify &> /dev/null; then
        if identify -format "%A" "$file_path" 2>/dev/null | grep -q "True"; then
            alpha="true"
        fi
    fi
    
    # Create content description
    local content="PNG image: $(basename "$file_path")\nDimensions: ${width}x${height}\nSize: $size bytes\nTransparency: $alpha"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"width\":$width,\"height\":$height,\"size\":$size,\"has_alpha\":$alpha}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"image/png\"}"
    
    return 0
}

process_image_gif() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing GIF image: $file_path" "content_processors" "process_image_gif"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract image dimensions if identify (ImageMagick) is available
    local width=0
    local height=0
    local frames=1
    if command -v identify &> /dev/null; then
        width="$(identify -format "%w" "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        height="$(identify -format "%h" "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        frames="$(identify "$file_path" 2>/dev/null | wc -l || echo 1)"
    fi
    
    # Determine if animated
    local is_animated="false"
    if [ "$frames" -gt 1 ]; then
        is_animated="true"
    fi
    
    # Create content description
    local content="GIF image: $(basename "$file_path")\nDimensions: ${width}x${height}\nSize: $size bytes\nAnimated: $is_animated\nFrames: $frames"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"width\":$width,\"height\":$height,\"size\":$size,\"is_animated\":$is_animated,\"frames\":$frames}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"image/gif\"}"
    
    return 0
}

process_image_svg() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing SVG image: $file_path" "content_processors" "process_image_svg"
    
    # Read the SVG content
    local content="$(cat "$file_path")"
    local escaped_content="$(json_escape "$content")"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract SVG properties
    local width="$(grep -o 'width="[^"]*"' "$file_path" | head -1 | sed 's/width="\([^"]*\)"/\1/')"
    local height="$(grep -o 'height="[^"]*"' "$file_path" | head -1 | sed 's/height="\([^"]*\)"/\1/')"
    local viewBox="$(grep -o 'viewBox="[^"]*"' "$file_path" | head -1 | sed 's/viewBox="\([^"]*\)"/\1/' | sed 's/"/\\"/g')"
    
    # Create description
    local description="SVG image: $(basename "$file_path")\nSize: $size bytes\nDimensions: $width × $height"
    local escaped_description="$(json_escape "$description")"
    
    # Create JSON metadata
    local metadata="{\"width\":\"$width\",\"height\":\"$height\",\"viewBox\":\"$viewBox\",\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_description\",\"svg\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"image/svg+xml\"}"
    
    return 0
}

process_image_webp() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing WebP image: $file_path" "content_processors" "process_image_webp"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract image dimensions if identify (ImageMagick) is available
    local width=0
    local height=0
    if command -v identify &> /dev/null; then
        width="$(identify -format "%w" "$file_path" 2>/dev/null || echo 0)"
        height="$(identify -format "%h" "$file_path" 2>/dev/null || echo 0)"
    fi
    
    # Create content description
    local content="WebP image: $(basename "$file_path")\nDimensions: ${width}x${height}\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"width\":$width,\"height\":$height,\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"image/webp\"}"
    
    return 0
}

process_image_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing generic image file: $file_path" "content_processors" "process_image_generic"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local mimetype="$(file --mime-type -b "$file_path" | sed 's/"/\\"/g')"
    
    # Extract image dimensions if identify (ImageMagick) is available
    local width=0
    local height=0
    if command -v identify &> /dev/null; then
        width="$(identify -format "%w" "$file_path" 2>/dev/null || echo 0)"
        height="$(identify -format "%h" "$file_path" 2>/dev/null || echo 0)"
    fi
    
    # Create content description
    local content="Image file: $(basename "$file_path")\nType: $mimetype\nDimensions: ${width}x${height}\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"width\":$width,\"height\":$height,\"size\":$size,\"mimetype\":\"$mimetype\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"$mimetype\"}"
    
    return 0
}

# Video processors
process_video_mp4() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing MP4 video: $file_path" "content_processors" "process_video_mp4"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract video info if ffprobe (FFmpeg) is available
    local duration=0
    local width=0
    local height=0
    local codec=""
    local bitrate=0
    local fps=0
    
    if command -v ffprobe &> /dev/null; then
        duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        width="$(ffprobe -v error -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        height="$(ffprobe -v error -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        codec="$(ffprobe -v error -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo "")"
        bitrate="$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        fps="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 | bc -l 2>/dev/null || echo 0)"
        # Round fps to two decimal places
        fps=$(printf "%.2f" $fps 2>/dev/null || echo 0)
    fi
    
    # Extract metadata if available
    local title="$(basename "$file_path" | sed 's/"/\\"/g')"
    if command -v ffprobe &> /dev/null; then
        local title_meta="$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null)"
        if [[ -n "$title_meta" ]]; then
            title="$(echo "$title_meta" | sed 's/"/\\"/g')"
        fi
    fi
    
    # Create content description
    local content="MP4 video: $(basename "$file_path")\nTitle: $title\nDuration: ${duration}s\nResolution: ${width}x${height}\nCodec: $codec\nFPS: $fps\nBitrate: $bitrate\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"title\":\"$title\",\"duration\":$duration,\"width\":$width,\"height\":$height,\"codec\":\"$codec\",\"fps\":$fps,\"bitrate\":$bitrate,\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"video/mp4\"}"
    
    return 0
}

process_video_quicktime() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing QuickTime video: $file_path" "content_processors" "process_video_quicktime"
    
    # Similar to MP4 processing
    process_video_mp4 "$file_path" "$options"
    
    return $?
}

process_video_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing generic video file: $file_path" "content_processors" "process_video_generic"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local mimetype="$(file --mime-type -b "$file_path" | sed 's/"/\\"/g')"
    
    # Extract video info if ffprobe (FFmpeg) is available
    local duration=0
    local width=0
    local height=0
    if command -v ffprobe &> /dev/null; then
        duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        width="$(ffprobe -v error -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        height="$(ffprobe -v error -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
    fi
    
    # Create content description
    local content="Video file: $(basename "$file_path")\nType: $mimetype\nDuration: ${duration}s\nResolution: ${width}x${height}\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"duration\":$duration,\"width\":$width,\"height\":$height,\"size\":$size,\"mimetype\":\"$mimetype\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"$mimetype\"}"
    
    return 0
}

# Audio processors
process_audio_mp3() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing MP3 audio file: $file_path" "content_processors" "process_audio_mp3"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract audio info if ffprobe (FFmpeg) is available
    local duration=0
    local bitrate=0
    local sample_rate=0
    local channels=0
    
    if command -v ffprobe &> /dev/null; then
        duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        bitrate="$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        sample_rate="$(ffprobe -v error -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        channels="$(ffprobe -v error -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
    fi
    
    # Extract metadata if available
    local title="$(basename "$file_path" | sed 's/"/\\"/g')"
    local artist=""
    local album=""
    
    if command -v ffprobe &> /dev/null; then
        local title_meta="$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null)"
        if [[ -n "$title_meta" ]]; then
            title="$(echo "$title_meta" | sed 's/"/\\"/g')"
        fi
        
        artist="$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo "")"
        artist="$(echo "$artist" | sed 's/"/\\"/g')"
        
        album="$(ffprobe -v error -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo "")"
        album="$(echo "$album" | sed 's/"/\\"/g')"
    fi
    
    # Create content description
    local content="MP3 audio: $(basename "$file_path")\nTitle: $title\nArtist: $artist\nAlbum: $album\nDuration: ${duration}s\nBitrate: $bitrate\nSample Rate: ${sample_rate}Hz\nChannels: $channels\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"title\":\"$title\",\"artist\":\"$artist\",\"album\":\"$album\",\"duration\":$duration,\"bitrate\":$bitrate,\"sample_rate\":$sample_rate,\"channels\":$channels,\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"audio/mpeg\"}"
    
    return 0
}

process_audio_wav() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing WAV audio file: $file_path" "content_processors" "process_audio_wav"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract audio info if ffprobe (FFmpeg) is available
    local duration=0
    local sample_rate=0
    local channels=0
    local bit_depth=0
    
    if command -v ffprobe &> /dev/null; then
        duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        sample_rate="$(ffprobe -v error -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        channels="$(ffprobe -v error -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        bit_depth="$(ffprobe -v error -show_entries stream=bits_per_sample -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
    fi
    
    # Create content description
    local content="WAV audio: $(basename "$file_path")\nDuration: ${duration}s\nSample Rate: ${sample_rate}Hz\nChannels: $channels\nBit Depth: $bit_depth\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"duration\":$duration,\"sample_rate\":$sample_rate,\"channels\":$channels,\"bit_depth\":$bit_depth,\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"audio/wav\"}"
    
    return 0
}

process_audio_ogg() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing OGG audio file: $file_path" "content_processors" "process_audio_ogg"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    
    # Extract audio info if ffprobe (FFmpeg) is available
    local duration=0
    local sample_rate=0
    local channels=0
    local codec=""
    
    if command -v ffprobe &> /dev/null; then
        duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        sample_rate="$(ffprobe -v error -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        channels="$(ffprobe -v error -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        codec="$(ffprobe -v error -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo "")"
    fi
    
    # Create content description
    local content="OGG audio: $(basename "$file_path")\nCodec: $codec\nDuration: ${duration}s\nSample Rate: ${sample_rate}Hz\nChannels: $channels\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"codec\":\"$codec\",\"duration\":$duration,\"sample_rate\":$sample_rate,\"channels\":$channels,\"size\":$size}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"audio/ogg\"}"
    
    return 0
}

process_audio_generic() {
    local file_path="$1"
    local options="$2"
    
    log_debug "Processing audio file: $file_path" "content_processors" "process_audio_generic"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local mimetype="$(file --mime-type -b "$file_path" | sed 's/"/\\"/g')"
    
    # Extract audio info if ffprobe (FFmpeg) is available
    local duration=0
    local sample_rate=0
    local channels=0
    local codec=""
    
    if command -v ffprobe &> /dev/null; then
        duration="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null || echo 0)"
        sample_rate="$(ffprobe -v error -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        channels="$(ffprobe -v error -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo 0)"
        codec="$(ffprobe -v error -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file_path" 2>/dev/null | head -n 1 || echo "")"
    fi
    
    # Create content description
    local content="Audio file: $(basename "$file_path")\nType: $mimetype\nDuration: ${duration}s\nSample Rate: ${sample_rate}Hz\nChannels: $channels\nCodec: $codec\nSize: $size bytes"
    local escaped_content="$(json_escape "$content")"
    
    # Create JSON metadata
    local metadata="{\"duration\":$duration,\"sample_rate\":$sample_rate,\"channels\":$channels,\"codec\":\"$codec\",\"size\":$size,\"mimetype\":\"$mimetype\"}"
    
    # Generate result
    echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"$mimetype\"}"
    
    return 0
}

# Fallback processor for unknown content types
process_fallback() {
    local file_path="$1"
    local options="$2"
    
    log_warning "Using fallback processor for unknown content type: $(file --mime-type -b "$file_path")" "content_processors" "process_fallback"
    
    # Get basic file info
    local size="$(stat -f %z "$file_path" 2>/dev/null || stat -c %s "$file_path" 2>/dev/null || echo 0)"
    local mimetype="$(file --mime-type -b "$file_path" | sed 's/"/\\"/g')"
    local file_info="$(file "$file_path" | sed 's/"/\\"/g')"
    
    # Attempt to determine if it's text or binary
    if file -b "$file_path" | grep -q text; then
        # It seems to be text, try to extract some content
        local content="$(head -n 100 "$file_path" 2>/dev/null || cat "$file_path")"
        local escaped_content="$(json_escape "$content")"
        
        # Create content description
        local description="Text file (unknown format): $(basename "$file_path")\nType: $mimetype\nSize: $size bytes\nInfo: $file_info"
        local escaped_description="$(json_escape "$description")"
        
        # Create JSON metadata
        local metadata="{\"size\":$size,\"mimetype\":\"$mimetype\",\"file_info\":\"$file_info\"}"
        
        # Generate result
        echo "{\"text\":\"$escaped_content\",\"description\":\"$escaped_description\",\"metadata\":$metadata,\"content_type\":\"$mimetype\"}"
    else
        # It's binary, use binary processor
        process_application_binary "$file_path" "$options"
    fi
    
    return 0
}

# Initialize content processors if not already
if [[ -z "${CONTENT_PROCESSORS[*]}" ]]; then
    # Create the associative array
    declare -A CONTENT_PROCESSORS
    
    # Initialize processors
    init_content_processors
fi