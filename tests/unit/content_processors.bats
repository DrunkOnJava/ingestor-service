#!/usr/bin/env bats
# Test cases for content processors module

load ../test_helper
load ../assertions

setup() {
    setup_test_temp_dir
    TEST_FILES_DIR="${BATS_TEST_DIRNAME}/test_files"
    mkdir -p "${TEST_FILES_DIR}"
    
    # Create test files
    echo "Hello, World!" > "${TEST_FILES_DIR}/plain.txt"
    echo "# Markdown Title" > "${TEST_FILES_DIR}/doc.md"
    echo "<!DOCTYPE html><html><head><title>Test</title></head><body>Content</body></html>" > "${TEST_FILES_DIR}/page.html"
    echo '{"key":"value","number":123}' > "${TEST_FILES_DIR}/data.json"
    echo "<xml><root>Content</root></xml>" > "${TEST_FILES_DIR}/data.xml"
    echo "name,age,city
John,30,New York
Alice,25,London" > "${TEST_FILES_DIR}/data.csv"
    
    # Helper functions for testing
    
    # JSON escape function
    json_escape() {
        local content="$1"
        content="${content//\\/\\\\}"    # Escape backslashes
        content="${content//\"/\\\"}"    # Escape double quotes
        content="${content//	/\\t}"     # Escape tabs
        content="${content//$'\n'/\\n}"  # Escape newlines
        content="${content//$'\r'/\\r}"  # Escape carriage returns
        echo "$content"
    }
    
    # Text processors
    process_text_plain() {
        local file_path="$1"
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
        local content="$(cat "$file_path")"
        local escaped_content="$(json_escape "$content")"
        
        # Extract text content (simplified approach)
        local text_content="$(cat "$file_path" | sed 's/<[^>]*>//g' | sed '/^$/d')"
        local escaped_text="$(json_escape "$text_content")"
        
        # Extract title
        local title="$(grep -o '<title>[^<]*</title>' "$file_path" | sed 's/<title>\(.*\)<\/title>/\1/' | sed 's/"/\\"/g')" 
        
        # Create JSON metadata
        local metadata="{\"title\":\"$title\"}"
        
        # Generate result
        echo "{\"text\":\"$escaped_text\",\"html\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"text/html\"}"
        
        return 0
    }
    
    process_application_json() {
        local file_path="$1"
        local content="$(cat "$file_path")"
        local escaped_content="$(json_escape "$content")"
        
        # Create JSON metadata
        local metadata="{\"valid\":true}"
        
        # Generate result
        echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/json\"}"
        
        return 0
    }
    
    process_application_xml() {
        local file_path="$1"
        local content="$(cat "$file_path")"
        local escaped_content="$(json_escape "$content")"
        
        # Extract metadata
        local root_elem="$(grep -o '<[^? ][^ >]*' "$file_path" | head -n 1 | sed 's/<//g' | sed 's/"/\\"/g')"
        
        # Create JSON metadata
        local metadata="{\"root_element\":\"$root_elem\"}"
        
        # Generate result
        echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/xml\"}"
        
        return 0
    }
    
    process_text_csv() {
        local file_path="$1"
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
    
    process_text_generic() {
        process_text_plain "$1" "$2"
        return $?
    }
    
    process_application_generic() {
        local file_path="$1"
        local content="$(cat "$file_path")"
        local escaped_content="$(json_escape "$content")"
        
        # Create JSON metadata
        local metadata="{\"mimetype\":\"application/octet-stream\"}"
        
        # Generate result
        echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/octet-stream\"}"
        
        return 0
    }
    
    process_fallback() {
        local file_path="$1"
        
        # Only process existing files
        if [[ ! -f "$file_path" ]]; then
            echo "{\"error\":\"File not found\",\"content_type\":\"unknown\"}"
            return 1
        fi
        
        local content="$(cat "$file_path")"
        local escaped_content="$(json_escape "$content")"
        
        # Get file info
        local mimetype="application/octet-stream"
        
        # Create JSON metadata
        local metadata="{\"mimetype\":\"$mimetype\"}"
        
        # Generate result
        echo "{\"text\":\"$escaped_content\",\"metadata\":$metadata,\"content_type\":\"application/octet-stream\"}"
        
        return 0
    }
    
    # Main content processing function that selects the appropriate processor
    process_content() {
        local file_path="$1"
        local content_type="$2"
        
        # Check if file exists
        if [[ ! -f "$file_path" ]]; then
            echo "{\"error\":\"File not found\",\"file_path\":\"$file_path\"}"
            return 1
        fi
        
        # Select processor based on content type
        case "$content_type" in
            "text/plain")
                process_text_plain "$file_path"
                ;;
            "text/markdown")
                process_text_markdown "$file_path"
                ;;
            "text/html")
                process_text_html "$file_path"
                ;;
            "application/json")
                process_application_json "$file_path"
                ;;
            "application/xml")
                process_application_xml "$file_path"
                ;;
            "text/csv")
                process_text_csv "$file_path"
                ;;
            "text/"*)
                # Generic text handler for other text types
                process_text_generic "$file_path"
                ;;
            "application/"*)
                # Generic application handler for other application types
                process_application_generic "$file_path"
                ;;
            *)
                # Fallback for unknown types
                process_fallback "$file_path"
                ;;
        esac
        
        return $?
    }
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    
    if [[ -d "${TEST_FILES_DIR}" ]]; then
        rm -rf "${TEST_FILES_DIR}"
    fi
}

@test "json_escape function handles special characters" {
    # Create a test file with special characters
    local special_file="${TEST_FILES_DIR}/special.txt"
    echo -e "Line 1\nLine \"2\"\tTabbed\rCarriage return\\ Backslash" > "$special_file"
    
    run json_escape "$(cat "$special_file")"
    
    # Should return success
    assert_success
    
    # Output should have escaped characters
    assert_output "Line 1\\nLine \\\"2\\\"\\tTabbed\\rCarriage return\\\\ Backslash"
}

@test "process_text_plain with valid file" {
    run process_text_plain "${TEST_FILES_DIR}/plain.txt"
    
    # Should return success
    assert_success
    
    # Output should be valid JSON with expected content
    assert_output | grep -q '"text":"Hello, World!"'
    assert_output | grep -q '"content_type":"text/plain"'
}

@test "process_text_markdown with valid file" {
    run process_text_markdown "${TEST_FILES_DIR}/doc.md"
    
    # Should return success
    assert_success
    
    # Output should contain the title from the Markdown
    assert_output | grep -q '"title":"Markdown Title"'
    assert_output | grep -q '"content_type":"text/markdown"'
}

@test "process_text_html with valid file" {
    run process_text_html "${TEST_FILES_DIR}/page.html"
    
    # Should return success
    assert_success
    
    # Output should contain the HTML title
    assert_output | grep -q '"title":"Test"'
    assert_output | grep -q '"content_type":"text/html"'
}

@test "process_application_json with valid file" {
    run process_application_json "${TEST_FILES_DIR}/data.json"
    
    # Should return success
    assert_success
    
    # Output should be valid JSON with expected content
    assert_output | grep -q '"text":"{\\\"key\\\":\\\"value\\\"'
    assert_output | grep -q '"content_type":"application/json"'
}

@test "process_application_xml with valid file" {
    run process_application_xml "${TEST_FILES_DIR}/data.xml"
    
    # Should return success
    assert_success
    
    # Output should be valid JSON with expected content
    assert_output | grep -q '"root_element":"xml"'
    assert_output | grep -q '"content_type":"application/xml"'
}

@test "process_text_csv with valid file" {
    run process_text_csv "${TEST_FILES_DIR}/data.csv"
    
    # Should return success
    assert_success
    
    # Output should be valid JSON with expected content
    assert_output | grep -q '"headers":"name,age,city"'
    assert_output | grep -q '"content_type":"text/csv"'
}

@test "process_content with non-existent file" {
    run process_content "${TEST_FILES_DIR}/not_existent.txt" "text/plain"
    
    # Should return failure
    assert_failure
    
    # Output should contain error message
    assert_output | grep -q '"error":"File not found"'
}

@test "process_content selects correct processor" {
    # Test with plain text file
    run process_content "${TEST_FILES_DIR}/plain.txt" "text/plain"
    assert_success
    assert_output | grep -q '"content_type":"text/plain"'
    
    # Test with markdown file
    run process_content "${TEST_FILES_DIR}/doc.md" "text/markdown"
    assert_success
    assert_output | grep -q '"content_type":"text/markdown"'
    
    # Test with HTML file
    run process_content "${TEST_FILES_DIR}/page.html" "text/html"
    assert_success
    assert_output | grep -q '"content_type":"text/html"'
}

@test "process_content uses fallback for unknown mime type" {
    # Test with unknown mime type
    run process_content "${TEST_FILES_DIR}/plain.txt" "application/unknown"
    
    # Should return success (because it uses fallback)
    assert_success
    
    # Output should include fallback content type
    assert_output | grep -q '"content_type":"application/octet-stream"'
}

@test "process_content uses category handler for related mime type" {
    # Test with a text type that doesn't have a specific handler
    run process_content "${TEST_FILES_DIR}/plain.txt" "text/x-config"
    
    # Should return success (using text/* handler)
    assert_success
    
    # Output should indicate it was handled by the generic text processor
    assert_output | grep -q '"content_type":"text/plain"'
}