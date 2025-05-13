#!/bin/bash
# Content detection and processing module

# Detect content type based on file or input
detect_content_type() {
    local input="$1"
    
    if [[ -f "$input" ]]; then
        # Use file command to detect MIME type
        local mime_type
        mime_type=$(file --mime-type -b "$input")
        log_debug "Detected MIME type for file: $mime_type"
        echo "$mime_type"
    else
        # Text-based detection - try to guess content type from content
        local first_line
        first_line=$(head -n 1 "$input")
        
        if [[ "$first_line" =~ ^\{.*\}$ || "$first_line" =~ ^[[:space:]]*\{.*\}[[:space:]]*$ ]]; then
            echo "application/json"
        elif [[ "$first_line" =~ ^<\?xml || "$first_line" =~ ^<html || "$first_line" =~ ^<!DOCTYPE ]]; then
            echo "application/xml"
        elif [[ "$first_line" =~ ^(import|from|def|class) ]]; then
            echo "text/x-python"
        else
            echo "text/plain"
        fi
    fi
}

# Process content based on detected type
process_content() {
    local content_path="$1"
    local database="$2"
    
    # Get content type
    local content_type
    content_type=$(detect_content_type "$content_path")
    
    log_info "Processing content of type: $content_type for database: $database"
    
    # Determine appropriate processor
    case "$content_type" in
        image/*)
            process_image "$content_path" "$database"
            ;;
        video/*)
            process_video "$content_path" "$database"
            ;;
        application/pdf)
            process_pdf "$content_path" "$database"
            ;;
        text/plain)
            process_text "$content_path" "$database"
            ;;
        text/x-python|text/x-c|text/x-java|application/json|application/xml)
            process_code "$content_path" "$database" "$content_type"
            ;;
        *)
            log_warning "Unsupported content type: $content_type"
            process_generic "$content_path" "$database" "$content_type"
            ;;
    esac
}

# Process image files
process_image() {
    local image_path="$1"
    local database="$2"
    
    log_info "Processing image: $image_path"
    
    # Extract image metadata
    local metadata_file="${TEMP_DIR}/metadata_$(basename "$image_path").json"
    
    # Create a temp file for extracted EXIF data
    if ! exiftool -json "$image_path" > "$metadata_file" 2>/dev/null; then
        log_warning "Failed to extract metadata from image"
        # Create empty JSON to avoid errors
        echo "{}" > "$metadata_file"
    fi
    
    # Analyze image with Claude
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$image_path").json"
    if ! analyze_with_claude "$image_path" "image" > "$analysis_file"; then
        log_error "Failed to analyze image with Claude"
        return 1
    fi
    
    # Store data in database
    if ! store_image_data "$database" "$image_path" "$metadata_file" "$analysis_file"; then
        log_error "Failed to store image data in database"
        return 1
    fi
    
    log_info "Image processing completed successfully"
    return 0
}

# Process video files
process_video() {
    local video_path="$1"
    local database="$2"
    
    log_info "Processing video: $video_path"
    
    # Extract video metadata
    local metadata_file="${TEMP_DIR}/metadata_$(basename "$video_path").json"
    
    # Use ffprobe to get video metadata
    if ! ffprobe -v quiet -print_format json -show_format -show_streams "$video_path" > "$metadata_file" 2>/dev/null; then
        log_warning "Failed to extract metadata from video"
        # Create empty JSON to avoid errors
        echo "{}" > "$metadata_file"
    fi
    
    # Extract frame samples
    local frames_dir="${TEMP_DIR}/frames_$(basename "$video_path")"
    mkdir -p "$frames_dir"
    
    # Extract a few sample frames for analysis
    if ! ffmpeg -i "$video_path" -vf "fps=1/60" -frames:v 5 "${frames_dir}/frame_%03d.jpg" &>/dev/null; then
        log_warning "Failed to extract frames from video"
    fi
    
    # Analyze video with Claude
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$video_path").json"
    
    # First, analyze metadata
    local temp_analysis="${TEMP_DIR}/temp_analysis.json"
    if ! analyze_with_claude "$metadata_file" "video_metadata" > "$temp_analysis"; then
        log_error "Failed to analyze video metadata with Claude"
        return 1
    fi
    
    # Then, analyze frames if available
    if [[ -d "$frames_dir" && "$(ls -A "$frames_dir")" ]]; then
        for frame in "$frames_dir"/*.jpg; do
            local frame_analysis="${TEMP_DIR}/frame_analysis_$(basename "$frame").json"
            if analyze_with_claude "$frame" "video_frame" > "$frame_analysis"; then
                # Combine frame analyses
                # This is a simplified version - in reality, you'd want to merge these more intelligently
                echo "Frame $(basename "$frame"): $(cat "$frame_analysis")" >> "${TEMP_DIR}/all_frames_analysis.txt"
            fi
        done
        
        # Analyze the collected frame analyses
        if [[ -f "${TEMP_DIR}/all_frames_analysis.txt" ]]; then
            analyze_with_claude "${TEMP_DIR}/all_frames_analysis.txt" "video_frames_summary" >> "$temp_analysis"
        fi
    fi
    
    # Move temp analysis to final analysis file
    mv "$temp_analysis" "$analysis_file"
    
    # Store data in database
    if ! store_video_data "$database" "$video_path" "$metadata_file" "$analysis_file"; then
        log_error "Failed to store video data in database"
        return 1
    fi
    
    # Clean up frame directory
    rm -rf "$frames_dir"
    
    log_info "Video processing completed successfully"
    return 0
}

# Process PDF documents
process_pdf() {
    local pdf_path="$1"
    local database="$2"
    
    log_info "Processing PDF: $pdf_path"
    
    # Extract text content
    local text_file="${TEMP_DIR}/text_$(basename "$pdf_path").txt"
    
    if ! pdftotext "$pdf_path" "$text_file" 2>/dev/null; then
        log_warning "Failed to extract text from PDF"
        # Create empty file to avoid errors
        touch "$text_file"
    fi
    
    # If the text file is too large, we need to chunk it
    local file_size
    file_size=$(stat -f%z "$text_file")
    
    if [[ $file_size -gt 1000000 ]]; then
        log_info "Large PDF detected ($file_size bytes), chunking content"
        chunk_text_file "$text_file"
        
        # Process each chunk
        for chunk in "${TEMP_DIR}"/chunk_*.txt; do
            local chunk_analysis="${TEMP_DIR}/analysis_$(basename "$chunk").json"
            if ! analyze_with_claude "$chunk" "pdf_chunk" > "$chunk_analysis"; then
                log_warning "Failed to analyze PDF chunk: $(basename "$chunk")"
                continue
            fi
            
            # Store chunk data
            store_document_chunk "$database" "$pdf_path" "$chunk" "$chunk_analysis"
        done
    else
        # Analyze PDF with Claude
        local analysis_file="${TEMP_DIR}/analysis_$(basename "$pdf_path").json"
        if ! analyze_with_claude "$text_file" "pdf" > "$analysis_file"; then
            log_error "Failed to analyze PDF with Claude"
            return 1
        fi
        
        # Store data in database
        if ! store_document_data "$database" "$pdf_path" "$text_file" "$analysis_file"; then
            log_error "Failed to store PDF data in database"
            return 1
        fi
    fi
    
    log_info "PDF processing completed successfully"
    return 0
}

# Process text files
process_text() {
    local text_path="$1"
    local database="$2"
    
    log_info "Processing text: $text_path"
    
    # Check file size to determine if chunking is needed
    local file_size
    file_size=$(stat -f%z "$text_path")
    
    if [[ $file_size -gt 1000000 ]]; then
        log_info "Large text file detected ($file_size bytes), chunking content"
        chunk_text_file "$text_path"
        
        # Process each chunk
        for chunk in "${TEMP_DIR}"/chunk_*.txt; do
            local chunk_analysis="${TEMP_DIR}/analysis_$(basename "$chunk").json"
            if ! analyze_with_claude "$chunk" "text_chunk" > "$chunk_analysis"; then
                log_warning "Failed to analyze text chunk: $(basename "$chunk")"
                continue
            fi
            
            # Store chunk data
            store_text_chunk "$database" "$text_path" "$chunk" "$chunk_analysis"
        done
    else
        # Analyze text with Claude
        local analysis_file="${TEMP_DIR}/analysis_$(basename "$text_path").json"
        if ! analyze_with_claude "$text_path" "text" > "$analysis_file"; then
            log_error "Failed to analyze text with Claude"
            return 1
        fi
        
        # Store data in database
        if ! store_text_data "$database" "$text_path" "$analysis_file"; then
            log_error "Failed to store text data in database"
            return 1
        fi
    fi
    
    log_info "Text processing completed successfully"
    return 0
}

# Process code files
process_code() {
    local code_path="$1"
    local database="$2"
    local content_type="$3"
    
    log_info "Processing code: $code_path (type: $content_type)"
    
    # Determine language from content type
    local language
    case "$content_type" in
        text/x-python) language="python" ;;
        text/x-c) language="c" ;;
        text/x-java) language="java" ;;
        application/json) language="json" ;;
        application/xml) language="xml" ;;
        *) language="unknown" ;;
    esac
    
    # Analyze code with Claude
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$code_path").json"
    if ! analyze_with_claude "$code_path" "code" > "$analysis_file"; then
        log_error "Failed to analyze code with Claude"
        return 1
    fi
    
    # Store data in database
    if ! store_code_data "$database" "$code_path" "$language" "$analysis_file"; then
        log_error "Failed to store code data in database"
        return 1
    fi
    
    log_info "Code processing completed successfully"
    return 0
}

# Generic processor for unsupported content types
process_generic() {
    local file_path="$1"
    local database="$2"
    local content_type="$3"
    
    log_info "Processing generic content: $file_path (type: $content_type)"
    
    # Try to analyze with Claude anyway
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$file_path").json"
    if ! analyze_with_claude "$file_path" "generic" > "$analysis_file"; then
        log_error "Failed to analyze content with Claude"
        return 1
    fi
    
    # Store basic metadata
    local metadata_file="${TEMP_DIR}/metadata_$(basename "$file_path").json"
    local file_size
    file_size=$(stat -f%z "$file_path")
    
    cat > "$metadata_file" << EOF
{
    "filename": "$(basename "$file_path")",
    "path": "$file_path",
    "size": $file_size,
    "content_type": "$content_type",
    "last_modified": "$(date -r "$file_path" +"%Y-%m-%d %H:%M:%S")"
}
EOF
    
    # Store data in database
    if ! store_generic_data "$database" "$file_path" "$content_type" "$metadata_file" "$analysis_file"; then
        log_error "Failed to store generic data in database"
        return 1
    fi
    
    log_info "Generic content processing completed successfully"
    return 0
}

# Split a large text file into smaller chunks
chunk_text_file() {
    local file_path="$1"
    local chunk_size=${2:-500000} # Default to ~500KB chunks
    local output_dir="${TEMP_DIR}"
    local basename
    basename=$(basename "$file_path")
    
    log_info "Chunking text file: $file_path into $chunk_size byte pieces"
    
    # Use split to create chunks
    split -b "$chunk_size" "$file_path" "${output_dir}/chunk_${basename}_"
    
    log_info "Created $(ls "${output_dir}"/chunk_${basename}_* | wc -l) chunks"
}

# Utility function to extract specific metadata fields from an image
extract_image_metadata() {
    local image_path="$1"
    local field="$2"
    
    exiftool -"$field" -s -s -s "$image_path" 2>/dev/null || echo "Unknown"
}