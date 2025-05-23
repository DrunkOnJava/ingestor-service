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
        elif [[ "$first_line" =~ ^\<\?xml || "$first_line" =~ ^\<html || "$first_line" =~ ^\<!DOCTYPE ]]; then
            echo "application/xml"
        elif [[ "$first_line" =~ ^(import|from|def|class) ]]; then
            echo "text/x-python"
        else
            echo "text/plain"
        fi
    fi
}

# Process content based on detected type with chunking support
process_content() {
    local content_path="$1"
    local database="$2"
    local enable_chunking="${3:-$ENABLE_CHUNKING}"  # Use global or provided value
    local chunk_size="${4:-$CHUNK_SIZE}"            # Use global or provided value
    local chunk_overlap="${5:-$CHUNK_OVERLAP}"      # Use global or provided value
    local chunk_strategy="${6:-$CHUNK_STRATEGY}"    # Use global or provided value
    
    # Get content type
    local content_type
    content_type=$(detect_content_type "$content_path")
    
    if [[ -z "$content_type" ]]; then
        log_error "Failed to detect content type for: $content_path"
        return 1
    fi
    
    log_info "Processing content of type: $content_type for database: $database"
    log_debug "Chunking settings: enabled=$enable_chunking, size=$chunk_size, overlap=$chunk_overlap, strategy=$chunk_strategy"
    
    # Check file size to determine if chunking is needed
    local file_size
    file_size=$(stat -f%z "$content_path")
    
    # Process content based on type and chunking settings
    local should_chunk=false
    
    # Only chunk if enabled and file is large enough
    if [[ "$enable_chunking" == "true" && $file_size -gt $chunk_size ]]; then
        # Determine if this content type can be chunked effectively
        case "$content_type" in
            text/*|application/json|application/xml|application/pdf|application/javascript)
                should_chunk=true
                ;;
            text/x-python|text/x-c|text/x-java|text/x-javascript|text/x-typescript)
                # Code files can be chunked, but prefer paragraph strategy for them
                should_chunk=true
                [[ "$chunk_strategy" == "size" ]] && chunk_strategy="paragraph"
                ;;
            *)
                # Other types (images, videos, binaries) are not good candidates for chunking
                should_chunk=false
                ;;
        esac
    fi
    
    log_debug "Content chunking decision: $should_chunk"
    
    # Process based on content type, with chunking if appropriate
    case "$content_type" in
        image/*)
            process_image "$content_path" "$database"
            ;;
        video/*)
            process_video "$content_path" "$database"
            ;;
        application/pdf)
            if [[ "$should_chunk" == "true" ]]; then
                process_pdf_with_chunking "$content_path" "$database" "$chunk_size" "$chunk_overlap" "$chunk_strategy"
            else
                process_pdf "$content_path" "$database"
            fi
            ;;
        text/plain)
            if [[ "$should_chunk" == "true" ]]; then
                process_text_with_chunking "$content_path" "$database" "$chunk_size" "$chunk_overlap" "$chunk_strategy"
            else
                process_text "$content_path" "$database"
            fi
            ;;
        text/x-python|text/x-c|text/x-java|application/json|application/xml|text/x-javascript|text/x-typescript)
            if [[ "$should_chunk" == "true" ]]; then
                process_code_with_chunking "$content_path" "$database" "$content_type" "$chunk_size" "$chunk_overlap" "$chunk_strategy"
            else
                process_code "$content_path" "$database" "$content_type"
            fi
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
    
    log_info "PDF processing completed successfully"
    return 0
}

# Process PDF documents with chunking
process_pdf_with_chunking() {
    local pdf_path="$1"
    local database="$2"
    local chunk_size="$3"
    local chunk_overlap="$4"
    local chunk_strategy="$5"
    
    log_info "Processing PDF with chunking: $pdf_path"
    
    # Extract text content
    local text_file="${TEMP_DIR}/text_$(basename "$pdf_path").txt"
    
    if ! pdftotext "$pdf_path" "$text_file" 2>/dev/null; then
        log_warning "Failed to extract text from PDF, falling back to non-chunked processing"
        return process_pdf "$pdf_path" "$database"
    fi
    
    # Create chunks from the extracted text
    if ! chunk_text_file "$text_file" "$chunk_size" "$chunk_overlap" "$chunk_strategy"; then
        log_error "Failed to chunk PDF text"
        return 1
    fi
    
    # Store the parent entry first
    local parent_analysis="${TEMP_DIR}/parent_analysis_$(basename "$pdf_path").json"
    
    # Create a minimal analysis for the parent record
    cat > "$parent_analysis" << EOF
{
    "chunk_info": {
        "original_file": "$(basename "$pdf_path")",
        "chunking_strategy": "$chunk_strategy",
        "chunk_size": $chunk_size,
        "chunk_overlap": $chunk_overlap,
        "file_size": $(stat -f%z "$pdf_path")
    },
    "summary": "This PDF was processed in chunks due to its size. See individual chunks for detailed analysis."
}
EOF
    
    # Store parent record with minimal text content (first 1000 chars)
    local short_text="${TEMP_DIR}/short_text_$(basename "$pdf_path").txt"
    head -c 1000 "$text_file" > "$short_text"
    
    if ! store_document_data "$database" "$pdf_path" "$short_text" "$parent_analysis"; then
        log_warning "Failed to store parent PDF record, but will continue with chunks"
    fi
    
    # Process each chunk
    local success_count=0
    local chunk_count=0
    local pdf_basename=$(basename "$pdf_path")
    
    for chunk in "${TEMP_DIR}"/chunk_text_"${pdf_basename}"_*.txt; do
        if [[ ! -f "$chunk" ]]; then
            continue  # Skip if no chunks are found
        fi
        
        ((chunk_count++))
        local chunk_basename=$(basename "$chunk")
        log_info "Processing PDF chunk ${chunk_count}: $chunk_basename"
        
        local chunk_analysis="${TEMP_DIR}/analysis_${chunk_basename}.json"
        if ! analyze_with_claude "$chunk" "pdf_chunk" > "$chunk_analysis"; then
            log_warning "Failed to analyze PDF chunk: $chunk_basename"
            continue
        fi
        
        # Store chunk data
        if store_document_chunk "$database" "$pdf_path" "$chunk" "$chunk_analysis"; then
            ((success_count++))
        else
            log_warning "Failed to store PDF chunk: $chunk_basename"
        fi
    done
    
    log_info "PDF chunking completed. Processed $success_count/$chunk_count chunks successfully."
    
    if [[ $success_count -eq 0 && $chunk_count -gt 0 ]]; then
        log_error "Failed to process any chunks successfully"
        return 1
    fi
    
    return 0
}

# Process text files
process_text() {
    local text_path="$1"
    local database="$2"
    
    # Source error handler if not already loaded
    if [[ -z "${ERROR_HANDLER_INITIALIZED+x}" ]]; then
        if [[ -f "${PROJECT_ROOT}/src/modules/error_handler.sh" ]]; then
            source "${PROJECT_ROOT}/src/modules/error_handler.sh"
            init_error_handler
        fi
    fi
    
    log_info "Processing text: $text_path"
    
    # Validate inputs
    if [[ -z "$text_path" ]]; then
        handle_critical_error "Text path not specified" 2
        return 1
    fi
    
    if [[ -z "$database" ]]; then
        handle_critical_error "Database not specified" 2
        return 1
    fi
    
    # Check if text file exists and is readable
    if ! check_file "$text_path" "text file"; then
        return 1
    fi
    
    # Check system resources before processing
    if ! check_system_resources 50000 25000; then
        log_error "Insufficient system resources to process text file"
        return 1
    fi
    
    # Begin transaction for atomic processing
    begin_transaction "process_text"
    
    # Create temp directory for analysis if it doesn't exist
    if ! check_directory "$TEMP_DIR" "temporary directory"; then
        fail_transaction "Failed to create temporary directory"
        return 1
    fi
    
    # Analyze text with Claude (with retry)
    local analysis_file="${TEMP_DIR}/analysis_$(basename "$text_path").json"
    local analyze_cmd="analyze_with_claude \"$text_path\" \"text\" > \"$analysis_file\""
    
    if ! retry_command "$analyze_cmd" 3 5 120 "Analyze text with Claude"; then
        fail_transaction "Failed to analyze text with Claude"
        log_error "Failed to analyze text with Claude after retries"
        end_transaction
        return 1
    fi
    
    # Verify analysis file was created
    if ! check_file "$analysis_file" "analysis file"; then
        fail_transaction "Analysis file not created"
        log_error "Analysis file not created at $analysis_file"
        end_transaction
        return 1
    fi
    
    # Store data in database (with retry)
    local store_cmd="store_text_data \"$database\" \"$text_path\" \"$analysis_file\""
    
    if ! retry_command "$store_cmd" 3 2 30 "Store text data in database"; then
        fail_transaction "Failed to store text data in database"
        log_error "Failed to store text data in database after retries"
        end_transaction
        return 1
    fi
    
    # Transaction complete
    end_transaction
    
    log_info "Text processing completed successfully"
    return 0
}

# Process text files with chunking
process_text_with_chunking() {
    local text_path="$1"
    local database="$2"
    local chunk_size="$3"
    local chunk_overlap="$4"
    local chunk_strategy="$5"
    
    log_info "Processing text with chunking: $text_path"
    
    # Create chunks
    if ! chunk_text_file "$text_path" "$chunk_size" "$chunk_overlap" "$chunk_strategy"; then
        log_error "Failed to chunk text file"
        return 1
    fi
    
    # Store the parent entry first
    local parent_analysis="${TEMP_DIR}/parent_analysis_$(basename "$text_path").json"
    
    # Create a minimal analysis for the parent record
    cat > "$parent_analysis" << EOF
{
    "chunk_info": {
        "original_file": "$(basename "$text_path")",
        "chunking_strategy": "$chunk_strategy",
        "chunk_size": $chunk_size,
        "chunk_overlap": $chunk_overlap,
        "file_size": $(stat -f%z "$text_path")
    },
    "summary": "This file was processed in chunks due to its size. See individual chunks for detailed analysis."
}
EOF
    
    # Store parent record
    if ! store_text_data "$database" "$text_path" "$parent_analysis"; then
        log_warning "Failed to store parent text record, but will continue with chunks"
    fi
    
    # Process each chunk
    local success_count=0
    local chunk_count=0
    
    for chunk in "${TEMP_DIR}"/chunk_"$(basename "$text_path")"_*.txt; do
        if [[ ! -f "$chunk" ]]; then
            continue  # Skip if no chunks are found
        fi
        
        ((chunk_count++))
        local chunk_basename=$(basename "$chunk")
        log_info "Processing text chunk ${chunk_count}: $chunk_basename"
        
        local chunk_analysis="${TEMP_DIR}/analysis_${chunk_basename}.json"
        if ! analyze_with_claude "$chunk" "text_chunk" > "$chunk_analysis"; then
            log_warning "Failed to analyze text chunk: $chunk_basename"
            continue
        fi
        
        # Store chunk data
        if store_text_chunk "$database" "$text_path" "$chunk" "$chunk_analysis"; then
            ((success_count++))
        else
            log_warning "Failed to store text chunk: $chunk_basename"
        fi
    done
    
    log_info "Text chunking completed. Processed $success_count/$chunk_count chunks successfully."
    
    if [[ $success_count -eq 0 && $chunk_count -gt 0 ]]; then
        log_error "Failed to process any chunks successfully"
        return 1
    fi
    
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
        text/x-javascript) language="javascript" ;;
        text/x-typescript) language="typescript" ;;
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

# Process code files with chunking
process_code_with_chunking() {
    local code_path="$1"
    local database="$2"
    local content_type="$3"
    local chunk_size="$4"
    local chunk_overlap="$5"
    local chunk_strategy="$6"
    
    log_info "Processing code with chunking: $code_path (type: $content_type)"
    
    # Determine language from content type
    local language
    case "$content_type" in
        text/x-python) language="python" ;;
        text/x-c) language="c" ;;
        text/x-java) language="java" ;;
        text/x-javascript) language="javascript" ;;
        text/x-typescript) language="typescript" ;;
        application/json) language="json" ;;
        application/xml) language="xml" ;;
        *) language="unknown" ;;
    esac
    
    # For code files, paragraph strategy often works better as it can preserve function/class boundaries
    if [[ "$chunk_strategy" == "size" ]]; then
        log_info "Switching to paragraph chunking strategy for code file"
        chunk_strategy="paragraph"
    fi
    
    # Create chunks
    if ! chunk_text_file "$code_path" "$chunk_size" "$chunk_overlap" "$chunk_strategy"; then
        log_error "Failed to chunk code file"
        return 1
    fi
    
    # Store the parent entry first
    local parent_analysis="${TEMP_DIR}/parent_analysis_$(basename "$code_path").json"
    
    # Create a minimal analysis for the parent record
    cat > "$parent_analysis" << EOF
{
    "chunk_info": {
        "original_file": "$(basename "$code_path")",
        "chunking_strategy": "$chunk_strategy",
        "chunk_size": $chunk_size,
        "chunk_overlap": $chunk_overlap,
        "file_size": $(stat -f%z "$code_path"),
        "language": "$language"
    },
    "summary": "This code file was processed in chunks due to its size. See individual chunks for detailed analysis."
}
EOF
    
    # Store parent record
    if ! store_code_data "$database" "$code_path" "$language" "$parent_analysis"; then
        log_warning "Failed to store parent code record, but will continue with chunks"
    fi
    
    # Process each chunk
    local success_count=0
    local chunk_count=0
    local code_basename=$(basename "$code_path")
    
    # Code chunks will be stored in a separate table
    # We'll need to add a code_chunks table to the schema and a store_code_chunk function
    # For now, we'll process the chunks as regular code and add file paths that indicate they're chunks
    
    for chunk in "${TEMP_DIR}"/chunk_"${code_basename}"_*.txt; do
        if [[ ! -f "$chunk" ]]; then
            continue  # Skip if no chunks are found
        fi
        
        ((chunk_count++))
        local chunk_basename=$(basename "$chunk")
        local chunk_number=$(echo "$chunk_basename" | grep -o '[0-9]*' || echo "$chunk_count")
        log_info "Processing code chunk ${chunk_count}: $chunk_basename"
        
        # Analyze chunk with Claude
        local chunk_analysis="${TEMP_DIR}/analysis_${chunk_basename}.json"
        if ! analyze_with_claude "$chunk" "code" > "$chunk_analysis"; then
            log_warning "Failed to analyze code chunk: $chunk_basename"
            continue
        fi
        
        # Create a synthetic path for the chunk to avoid conflicts
        local chunk_path="${code_path}.chunk${chunk_number}"
        
        # Store chunk as a separate code entry with modified path
        if store_code_data "$database" "$chunk_path" "$language" "$chunk_analysis"; then
            ((success_count++))
        else
            log_warning "Failed to store code chunk: $chunk_basename"
        fi
    done
    
    log_info "Code chunking completed. Processed $success_count/$chunk_count chunks successfully."
    
    if [[ $success_count -eq 0 && $chunk_count -gt 0 ]]; then
        log_error "Failed to process any chunks successfully"
        return 1
    fi
    
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

# Split a large file into smaller chunks using different strategies
chunk_text_file() {
    local file_path="$1"
    local chunk_size=${2:-500000}     # Default size in bytes (~500KB)
    local chunk_overlap=${3:-5000}    # Default overlap in bytes (~5KB)
    local chunk_strategy=${4:-"size"} # Default strategy: size, paragraph, sentence
    local output_dir="${TEMP_DIR}"
    local basename
    basename=$(basename "$file_path")
    
    log_info "Chunking file: $file_path with strategy: $chunk_strategy"
    log_info "Chunk size: $chunk_size bytes, overlap: $chunk_overlap bytes"
    
    # Create a unique prefix for this file's chunks
    local chunk_prefix="${output_dir}/chunk_${basename}_"
    
    # Determine content type to handle appropriately
    local content_type
    content_type=$(detect_content_type "$file_path")
    
    # For binary/non-text files, only use size-based chunking
    if [[ "$content_type" != "text/"* && \
          "$content_type" != "application/json" && \
          "$content_type" != "application/xml" && \
          "$content_type" != "application/pdf" && \
          "$content_type" != *"script"* ]]; then
        log_info "Non-text file detected, using size-based chunking"
        chunk_strategy="size"
    fi
    
    case "$chunk_strategy" in
        "size")
            # Simple size-based chunking
            if ! split -b "$chunk_size" --additional-suffix=.txt "$file_path" "$chunk_prefix"; then
                log_error "Failed to chunk file by size"
                return 1
            fi
            ;;
            
        "paragraph")
            # Paragraph-based chunking (empty lines as separators)
            # First, create a temporary working file
            local temp_work_file="${output_dir}/temp_work_$(date +%s).txt"
            cp "$file_path" "$temp_work_file"
            
            # Process file paragraph by paragraph
            local chunk_num=1
            local chunk_content=""
            local chunk_size_bytes=0
            local chunk_file="${chunk_prefix}${chunk_num}.txt"
            
            # Read file line by line
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Check if line is empty (paragraph boundary)
                if [[ -z "$line" && -n "$chunk_content" ]]; then
                    # Add the paragraph separator
                    chunk_content+=$'\n\n'
                    chunk_size_bytes=$((chunk_size_bytes + 2))
                    
                    # Check if chunk has reached target size
                    if [[ $chunk_size_bytes -ge $chunk_size ]]; then
                        # Write chunk to file
                        echo "$chunk_content" > "$chunk_file"
                        
                        # Start new chunk with overlap
                        if [[ $chunk_overlap -gt 0 ]]; then
                            # Get the last part of the current chunk for overlap
                            local overlap_content
                            overlap_content=$(echo "$chunk_content" | tail -c "$chunk_overlap")
                            chunk_content="$overlap_content"
                            chunk_size_bytes=${#overlap_content}
                        else
                            chunk_content=""
                            chunk_size_bytes=0
                        fi
                        
                        # Increment chunk number
                        chunk_num=$((chunk_num + 1))
                        chunk_file="${chunk_prefix}${chunk_num}.txt"
                    fi
                else
                    # Add line to current chunk
                    chunk_content+="$line"$'\n'
                    chunk_size_bytes=$((chunk_size_bytes + ${#line} + 1))
                fi
            done < "$temp_work_file"
            
            # Write last chunk if there's content
            if [[ -n "$chunk_content" ]]; then
                echo "$chunk_content" > "$chunk_file"
            fi
            
            # Clean up
            rm -f "$temp_work_file"
            ;;
            
        "sentence")
            # Sentence-based chunking (using simple heuristics: ., !, ?)
            # First, create a temporary working file
            local temp_work_file="${output_dir}/temp_work_$(date +%s).txt"
            cp "$file_path" "$temp_work_file"
            
            # Create a Python script for sentence splitting (more reliable than bash)
            local py_script="${output_dir}/sentence_splitter.py"
            cat > "$py_script" << 'EOF'
#!/usr/bin/env python3
import re
import sys
import os

def split_into_sentences(text):
    # Basic sentence boundary detection
    sentence_endings = r'(?<!\w\.\w.)(?<![A-Z][a-z]\.)(?<=\.|\?|\!)\s'
    sentences = re.split(sentence_endings, text)
    return sentences

def chunk_sentences(sentences, chunk_size, overlap_size, output_prefix):
    current_chunk = []
    current_size = 0
    chunk_num = 1
    
    for sentence in sentences:
        sentence_size = len(sentence)
        
        # If adding this sentence would exceed the chunk size and we already have content
        if current_size + sentence_size > chunk_size and current_chunk:
            # Write the current chunk
            with open(f"{output_prefix}{chunk_num}.txt", 'w') as f:
                f.write(' '.join(current_chunk))
            
            # Handle overlap
            if overlap_size > 0:
                # Calculate how many sentences to keep for overlap
                overlap_content = []
                overlap_size_so_far = 0
                
                for s in reversed(current_chunk):
                    if overlap_size_so_far + len(s) <= overlap_size:
                        overlap_content.insert(0, s)
                        overlap_size_so_far += len(s) + 1  # +1 for space
                    else:
                        break
                
                current_chunk = overlap_content
                current_size = overlap_size_so_far
            else:
                current_chunk = []
                current_size = 0
                
            chunk_num += 1
        
        # Add the sentence to the current chunk
        current_chunk.append(sentence)
        current_size += sentence_size + 1  # +1 for space
    
    # Write the last chunk if there's anything left
    if current_chunk:
        with open(f"{output_prefix}{chunk_num}.txt", 'w') as f:
            f.write(' '.join(current_chunk))

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python sentence_splitter.py <input_file> <output_prefix> <chunk_size> <overlap_size>")
        sys.exit(1)
        
    input_file = sys.argv[1]
    output_prefix = sys.argv[2]
    chunk_size = int(sys.argv[3])
    overlap_size = int(sys.argv[4])
    
    with open(input_file, 'r') as f:
        text = f.read()
    
    sentences = split_into_sentences(text)
    chunk_sentences(sentences, chunk_size, overlap_size, output_prefix)
    
    print(f"Created {chunk_num} chunks")
EOF
            
            # Make the script executable
            chmod +x "$py_script"
            
            # Run the Python script
            if ! python3 "$py_script" "$temp_work_file" "$chunk_prefix" "$chunk_size" "$chunk_overlap"; then
                log_error "Failed to chunk file by sentences"
                return 1
            fi
            
            # Clean up
            rm -f "$temp_work_file" "$py_script"
            ;;
            
        *)
            log_error "Unknown chunking strategy: $chunk_strategy, falling back to size-based chunking"
            split -b "$chunk_size" --additional-suffix=.txt "$file_path" "$chunk_prefix"
            ;;
    esac
    
    # Count the created chunks
    local chunk_count
    chunk_count=$(ls "${chunk_prefix}"*.txt 2>/dev/null | wc -l)
    
    if [[ $chunk_count -eq 0 ]]; then
        log_error "No chunks were created. Check file permissions and disk space."
        return 1
    fi
    
    log_info "Successfully created $chunk_count chunks using $chunk_strategy strategy"
    return 0
}

# Utility function to extract specific metadata fields from an image
extract_image_metadata() {
    local image_path="$1"
    local field="$2"
    
    exiftool -"$field" -s -s -s "$image_path" 2>/dev/null || echo "Unknown"
}