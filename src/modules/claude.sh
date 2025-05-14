#!/bin/bash
# Claude AI integration module for ingestor

# Initialize Claude API
init_claude() {
    # Check if API key is available
    if [[ -z "$CLAUDE_API_KEY" ]]; then
        log_error "Claude API key not found. Please set it in the configuration."
        return 1
    fi
    
    log_debug "Claude API initialized"
    return 0
}

# Call Claude API with content and prompt
claude_api_call() {
    local content="$1"
    local prompt="$2"
    local max_retries=${3:-3}
    local retry_delay=${4:-2}
    
    log_debug "Making Claude API call with prompt type: $prompt"
    
    # Check if API key is set
    if [[ -z "$CLAUDE_API_KEY" ]]; then
        log_error "Claude API key not set"
        return 1
    fi
    
    # Format payload based on content type
    local payload
    local content_type
    
    # Detect if content is a file path or raw text
    if [[ -f "$content" ]]; then
        # Handle different file types
        content_type=$(file --mime-type -b "$content")
        
        if [[ "$content_type" =~ ^image/ ]]; then
            # For image content, use base64 encoding
            local base64_content
            base64_content=$(base64 -i "$content")
            payload=$(create_image_payload "$base64_content" "$prompt")
        elif [[ "$content_type" =~ ^(text/|application/json|application/xml) ]]; then
            # For text content, read the file
            local file_content
            file_content=$(cat "$content")
            payload=$(create_text_payload "$file_content" "$prompt")
        else
            # Unsupported content type
            log_error "Unsupported content type for Claude API: $content_type"
            return 1
        fi
    else
        # Assume raw text content
        payload=$(create_text_payload "$content" "$prompt")
    fi
    
    # Make API request to Claude
    local response
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "$payload")
        
        # Check if request was successful
        if [[ "$response" == *"content"* && "$response" != *"error"* ]]; then
            # Extract the response content from the JSON
            echo "$response" | jq -r '.content[0].text' 2>/dev/null || echo "$response"
            return 0
        else
            log_warning "Claude API call failed (attempt $((retry_count + 1))): $response"
            
            # Increment retry counter
            retry_count=$((retry_count + 1))
            
            if [[ $retry_count -lt $max_retries ]]; then
                log_info "Retrying in $retry_delay seconds..."
                sleep $retry_delay
                
                # Increase delay for next retry (exponential backoff)
                retry_delay=$((retry_delay * 2))
            fi
        fi
    done
    
    log_error "Claude API call failed after $max_retries attempts"
    return 1
}

# Create payload for text analysis
create_text_payload() {
    local content="$1"
    local prompt_type="$2"
    
    # Get the appropriate system prompt for this content type
    local system_prompt
    system_prompt=$(get_system_prompt "$prompt_type")
    
    # Create the JSON payload
    cat << EOF
{
    "model": "claude-3-opus-20240229",
    "max_tokens": 4096,
    "temperature": 0.7,
    "system": "$system_prompt",
    "messages": [
        {
            "role": "user",
            "content": "$content"
        }
    ]
}
EOF
}

# Create payload for image analysis
create_image_payload() {
    local base64_content="$1"
    local prompt_type="$2"
    
    # Get the appropriate system prompt for this content type
    local system_prompt
    system_prompt=$(get_system_prompt "$prompt_type")
    
    # Create the JSON payload
    cat << EOF
{
    "model": "claude-3-opus-20240229",
    "max_tokens": 4096,
    "temperature": 0.7,
    "system": "$system_prompt",
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": "$base64_content"
                    }
                },
                {
                    "type": "text",
                    "text": "Analyze this image and provide detailed information about it."
                }
            ]
        }
    ]
}
EOF
}

# Get system prompt for different content types
get_system_prompt() {
    local prompt_type="$1"
    
    case "$prompt_type" in
        text)
            echo "You are an AI assistant specialized in analyzing text content. Extract key information, including:
                - Main topics and themes
                - Key entities (people, places, organizations, dates)
                - Important facts and figures
                - Summary of content
                - Sentiment and tone analysis
                - Categories or tags that apply to this content
                
                Return your analysis as a JSON object with these keys: topics, entities, facts, summary, sentiment, categories.
                Ensure that your response is properly formatted JSON."
            ;;
        text_entities)
            echo "You are an AI assistant specialized in extracting named entities from text. Your task is to identify all entities mentioned in the text, including:
                - People (individual names, titles, etc.)
                - Organizations (companies, institutions, agencies, groups, etc.)
                - Locations (cities, countries, addresses, regions, etc.)
                - Dates and Times (specific dates, durations, periods, etc.)
                - Products (specific named products, services, etc.)
                - Technologies (programming languages, platforms, frameworks, etc.)
                - Events (conferences, meetings, historical events, etc.)
                - Other important entities that don't fit these categories
                
                For each entity, provide:
                1. The exact name as it appears in the text
                2. The entity type (person, organization, location, date, product, technology, event, other)
                3. Any relevant context around the entity's mention
                4. A confidence score (0.0-1.0) indicating your certainty about this entity
                5. The approximate position or line number in the text
                
                Return your results in this JSON format:
                {
                  \"entities\": [
                    {
                      \"name\": \"Entity name\",
                      \"type\": \"person|organization|location|date|product|technology|event|other\",
                      \"mentions\": [
                        {
                          \"context\": \"Surrounding text or context of the mention\",
                          \"position\": 0,
                          \"relevance\": 0.85
                        }
                      ]
                    }
                  ]
                }
                
                Ensure that your response is properly formatted JSON."
            ;;
        text_entities_custom)
            echo "You are an AI assistant specialized in extracting specific types of named entities from text based on user requirements. Extract only the entity types specified in the options, with high precision.
                
                For each entity, provide:
                1. The exact name as it appears in the text
                2. The entity type (from the requested types)
                3. Any relevant context around the entity's mention
                4. A confidence score (0.0-1.0) indicating your certainty about this entity
                5. The approximate position or line number in the text
                
                Return your results in this JSON format:
                {
                  \"entities\": [
                    {
                      \"name\": \"Entity name\",
                      \"type\": \"[requested type]\",
                      \"mentions\": [
                        {
                          \"context\": \"Surrounding text or context of the mention\",
                          \"position\": 0,
                          \"relevance\": 0.85
                        }
                      ]
                    }
                  ]
                }
                
                Ensure that your response is properly formatted JSON and only includes the requested entity types."
            ;;
        image)
            echo "You are an AI assistant specialized in analyzing images. Extract key information, including:
                - Visual description of what's in the image
                - Objects and elements present
                - People (if any) and their appearances/activities
                - Setting or environment
                - Text visible in the image (if any)
                - Colors and composition
                - Likely purpose or context of the image
                
                Return your analysis as a JSON object with these keys: description, objects, people, setting, visible_text, colors, purpose.
                Ensure that your response is properly formatted JSON."
            ;;
        image_entities)
            echo "You are an AI assistant specialized in identifying entities in images. Your task is to identify all important entities visible in the image, including:
                - People (individuals, groups, etc.)
                - Organizations (logos, branding, etc.)
                - Locations (identifiable places, landmarks, etc.)
                - Products (identifiable branded items, etc.)
                - Text (signs, labels, writing visible in the image)
                - Other significant objects or elements
                
                For each entity, provide:
                1. The name or description of the entity
                2. The entity type (person, organization, location, product, text, other)
                3. A brief description of the entity's visual appearance
                4. A confidence score (0.0-1.0) indicating your certainty about this entity
                5. The general location in the image (e.g., 'center', 'top-left', etc.)
                
                Return your results in this JSON format:
                {
                  \"entities\": [
                    {
                      \"name\": \"Entity name or description\",
                      \"type\": \"person|organization|location|product|text|other\",
                      \"mentions\": [
                        {
                          \"context\": \"Visual description and location in image\",
                          \"position\": \"center|top|bottom|left|right|top-left|etc.\",
                          \"relevance\": 0.85
                        }
                      ]
                    }
                  ]
                }
                
                Ensure that your response is properly formatted JSON."
            ;;
        video_metadata)
            echo "You are an AI assistant specialized in analyzing video metadata. Extract key information, including:
                - Video format, duration, and dimensions
                - Encoding information and quality
                - Audio tracks and their properties
                - Creation date and other temporal metadata
                - Likely content type based on technical attributes
                
                Return your analysis as a JSON object with these keys: format_analysis, quality_assessment, audio_analysis, temporal_metadata, content_type_guess.
                Ensure that your response is properly formatted JSON."
            ;;
        video_frame)
            echo "You are an AI assistant specialized in analyzing video frames. Extract key information, including:
                - Visual description of what's in the frame
                - Objects and elements present
                - People (if any) and their appearances/activities
                - Setting or environment
                - Text visible in the frame (if any)
                - Visual quality and composition
                - What this frame might represent in the context of a video
                
                Return your analysis as a JSON object with these keys: description, objects, people, setting, visible_text, composition, context.
                Ensure that your response is properly formatted JSON."
            ;;
        video_frames_summary)
            echo "You are an AI assistant specialized in analyzing collections of video frames. Extract key information, including:
                - Overview of video content based on the frames
                - Scene changes and transitions
                - Main subjects or focus of the video
                - Activities or events depicted
                - Visual style and quality
                - Temporal progression (if evident)
                
                Return your analysis as a JSON object with these keys: content_overview, scenes, main_subjects, activities, style, progression.
                Ensure that your response is properly formatted JSON."
            ;;
        pdf)
            echo "You are an AI assistant specialized in analyzing PDF documents. Extract key information, including:
                - Document title and author (if available)
                - Main topics and themes
                - Key entities (people, places, organizations, dates)
                - Important facts, figures, and statistics
                - Executive summary of content
                - Document structure and organization
                - Categories or tags that apply to this document
                
                Return your analysis as a JSON object with these keys: document_info, topics, entities, facts, summary, structure, categories.
                Ensure that your response is properly formatted JSON."
            ;;
        pdf_entities)
            echo "You are an AI assistant specialized in extracting entities from PDF documents. Your task is to identify all entities mentioned in the PDF content, including:
                - People (authors, individuals mentioned, etc.)
                - Organizations (companies, institutions, etc. mentioned or affiliated)
                - Locations (geographical locations mentioned)
                - Dates (publication date, dates mentioned in content)
                - Document properties (title, subject, keywords, etc.)
                - Key terms and concepts specific to the document domain
                
                For each entity, provide:
                1. The exact name as it appears in the text
                2. The entity type (person, organization, location, date, document_property, key_term, other)
                3. Any relevant context around the entity's mention
                4. A confidence score (0.0-1.0) indicating your certainty about this entity
                5. The section or part of the document where it appears
                
                Return your results in this JSON format:
                {
                  \"entities\": [
                    {
                      \"name\": \"Entity name\",
                      \"type\": \"person|organization|location|date|document_property|key_term|other\",
                      \"mentions\": [
                        {
                          \"context\": \"Surrounding text or context of the mention\",
                          \"position\": \"document section or description\",
                          \"relevance\": 0.85
                        }
                      ]
                    }
                  ]
                }
                
                Ensure that your response is properly formatted JSON."
            ;;
        pdf_chunk)
            echo "You are an AI assistant specialized in analyzing chunks of PDF documents. Extract key information from this chunk, including:
                - Main topics and themes in this section
                - Key entities (people, places, organizations, dates)
                - Important facts, figures, and statistics
                - Summary of this section
                - How this section likely relates to the larger document
                
                Return your analysis as a JSON object with these keys: topics, entities, facts, summary, context.
                Ensure that your response is properly formatted JSON."
            ;;
        code)
            echo "You are an AI assistant specialized in analyzing code. Extract key information, including:
                - Programming language and version (if identifiable)
                - Purpose and functionality of the code
                - Key components (classes, functions, methods)
                - Dependencies and imports
                - Coding patterns and paradigms used
                - Potential issues or vulnerabilities
                - Documentation quality and code readability
                - Suggestions for improvement or optimization
                
                Return your analysis as a JSON object with these keys: language, purpose, components, dependencies, patterns, issues, quality, suggestions.
                Ensure that your response is properly formatted JSON."
            ;;
        code_entities)
            echo "You are an AI assistant specialized in extracting entities from source code. Your task is to identify all important code entities, including:
                - Classes and structs
                - Functions and methods
                - Variables and constants
                - Imports and dependencies
                - APIs and frameworks used
                - File paths and resources referenced
                - Programming language(s)
                
                For each entity, provide:
                1. The exact name as it appears in the code
                2. The entity type (class, function, variable, import, api, file_path, language)
                3. The purpose or role of the entity in the code (if apparent)
                4. A confidence score (0.0-1.0) indicating your certainty about this entity
                5. The line number or location in the code (if determinable)
                
                Return your results in this JSON format:
                {
                  \"entities\": [
                    {
                      \"name\": \"Entity name\",
                      \"type\": \"class|function|variable|import|api|file_path|language\",
                      \"mentions\": [
                        {
                          \"context\": \"Code snippet or context around the entity\",
                          \"position\": line number or description,
                          \"relevance\": 0.85
                        }
                      ]
                    }
                  ]
                }
                
                Ensure that your response is properly formatted JSON."
            ;;
        generic)
            echo "You are an AI assistant specialized in analyzing various types of content. Extract as much meaningful information as possible, including:
                - Content type and format assessment
                - Main topics or purpose
                - Key entities or components
                - Important information or data points
                - Summary of content
                - Categories or tags that apply to this content
                
                Return your analysis as a JSON object with these keys: content_type, topics, entities, key_points, summary, categories.
                Ensure that your response is properly formatted JSON."
            ;;
        generic_entities)
            echo "You are an AI assistant specialized in extracting entities from any type of content. Your task is to identify all significant entities in the content, regardless of format. Look for:
                - People (individual names, titles, etc.)
                - Organizations (companies, institutions, groups, etc.)
                - Locations (places, addresses, regions, etc.)
                - Dates and Times (specific dates, times, durations, etc.)
                - Products and Services
                - Technical Terms and Concepts
                - Media References (books, articles, movies, etc.)
                - Other important entities specific to the content
                
                For each entity, provide:
                1. The exact name as it appears in the content
                2. The most appropriate entity type
                3. Any relevant context around the entity's mention
                4. A confidence score (0.0-1.0) indicating your certainty about this entity
                5. Any additional metadata relevant to the entity
                
                Return your results in this JSON format:
                {
                  \"entities\": [
                    {
                      \"name\": \"Entity name\",
                      \"type\": \"person|organization|location|date|product|technical|media|other\",
                      \"mentions\": [
                        {
                          \"context\": \"Surrounding context of the mention\",
                          \"position\": description of location in content,
                          \"relevance\": 0.85
                        }
                      ]
                    }
                  ]
                }
                
                Ensure that your response is properly formatted JSON."
            ;;
        *)
            echo "You are an AI assistant. Analyze the provided content and extract key information in a structured way.
                Return your analysis as properly formatted JSON with appropriate keys for the type of content."
            ;;
    esac
}

# Analyze content with Claude
analyze_with_claude() {
    local content="$1"
    local prompt_type="$2"
    
    # Initialize Claude API if needed
    if ! init_claude; then
        log_error "Failed to initialize Claude API"
        return 1
    fi
    
    # Call Claude API
    local response
    response=$(claude_api_call "$content" "$prompt_type")
    
    # Check if response is valid JSON
    if ! echo "$response" | jq . > /dev/null 2>&1; then
        log_warning "Claude response is not valid JSON, attempting to fix"
        
        # Try to extract JSON block if present
        if [[ "$response" =~ \{.*\} ]]; then
            response=$(echo "$response" | grep -o "{.*}" | head -1)
            
            # Validate JSON again
            if ! echo "$response" | jq . > /dev/null 2>&1; then
                log_error "Failed to extract valid JSON from Claude response"
                
                # Create minimal valid JSON with error message
                response="{\"error\": \"Failed to get valid JSON response\", \"raw_response\": \"${response//\"/\\\"}\"}}"
            fi
        else
            # Create minimal valid JSON with error message
            response="{\"error\": \"Failed to get valid JSON response\", \"raw_response\": \"${response//\"/\\\"}\"}}"
        fi
    fi
    
    echo "$response"
}

# Extract entities using Claude
extract_entities_with_claude() {
    local content="$1"
    local content_type="$2"
    local options="$3"
    
    log_debug "Extracting entities with Claude from: $content ($content_type)" "claude" "extract_entities_with_claude"
    
    # Determine the appropriate prompt type based on content type
    local prompt_type="text_entities"
    
    case "$content_type" in
        "text/plain"|"text/markdown"|"text/html"|"text/csv")
            prompt_type="text_entities"
            ;;
        "application/pdf")
            prompt_type="pdf_entities"
            ;;
        "text/x-python"|"text/javascript"|"text/x-c"|"application/x-sh")
            prompt_type="code_entities"
            ;;
        "image/jpeg"|"image/png"|"image/gif"|"image/svg+xml")
            prompt_type="image_entities"
            ;;
        *)
            prompt_type="generic_entities"
            ;;
    esac
    
    # If options include specific entity types to extract, use the custom prompt
    if [[ "$options" == *"entity_types="* ]]; then
        if [[ "$prompt_type" == "text_entities" ]]; then
            prompt_type="text_entities_custom"
        fi
    fi
    
    # Call Claude API with the appropriate prompt
    local response
    response=$(analyze_with_claude "$content" "$prompt_type")
    
    # Extract entities from the response
    local entities
    entities=$(echo "$response" | jq -r '.entities // []' 2>/dev/null)
    
    if [[ "$entities" == "null" || "$entities" == "[]" ]]; then
        log_warning "No entities found in Claude response" "claude" "extract_entities_with_claude"
        echo "[]"
    else
        echo "$entities"
    fi
    
    return 0
}