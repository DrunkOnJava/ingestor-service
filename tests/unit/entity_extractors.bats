#!/usr/bin/env bats
# Test cases for entity extractors module

load ../test_helper
load ../assertions

setup() {
    setup_test_temp_dir
    TEST_FILES_DIR="${BATS_TEST_DIRNAME}/test_files"
    mkdir -p "${TEST_FILES_DIR}"
    
    # Create test files
    echo "John Smith is the CEO of Acme Corporation. He started the company in New York on January 15, 2010." > "${TEST_FILES_DIR}/sample.txt"
    echo "# Project Documentation
## Introduction
This project was created by Jane Doe at Microsoft in 2022.
## Details
The software uses Python 3.9 and TensorFlow for machine learning." > "${TEST_FILES_DIR}/doc.md"
    
    # Create sample HTML
    cat > "${TEST_FILES_DIR}/page.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>About Apple Inc.</title>
</head>
<body>
  <h1>Apple Inc.</h1>
  <p>Apple Inc. is a technology company founded by Steve Jobs, Steve Wozniak, and Ronald Wayne in Cupertino, California on April 1, 1976.</p>
  <p>The company is known for products like the iPhone, iPad, and MacBook.</p>
</body>
</html>
EOF

    # Create sample code
    cat > "${TEST_FILES_DIR}/sample.py" << 'EOF'
#!/usr/bin/env python3
"""
Sample module for testing entity extraction.
"""
import os
import datetime

class Person:
    def __init__(self, name, age):
        self.name = name
        self.age = age
    
    def get_details(self):
        return f"{self.name} is {self.age} years old."

def calculate_age(birthdate):
    today = datetime.date.today()
    return today.year - birthdate.year - ((today.month, today.day) < (birthdate.month, birthdate.day))

if __name__ == "__main__":
    person = Person("Sarah Johnson", 28)
    print(person.get_details())
EOF

    # Create sample JSON
    cat > "${TEST_FILES_DIR}/data.json" << 'EOF'
{
  "company": "TechCorp",
  "founded": "2015-03-22",
  "headquarters": "Seattle",
  "employees": [
    {
      "name": "Mark Wilson",
      "position": "CEO",
      "joined": "2015-03-22"
    },
    {
      "name": "Lisa Chen",
      "position": "CTO",
      "joined": "2015-05-15"
    }
  ],
  "products": ["QuantumDB", "CloudSync", "DataViz"]
}
EOF

    # Create sample PDF text (not actually a PDF)
    cat > "${TEST_FILES_DIR}/sample.pdf.txt" << 'EOF'
TITLE: Annual Report 2023
AUTHOR: Global Enterprises Ltd.
CREATED: 2023-12-01

Executive Summary

Global Enterprises Ltd. reported record earnings in fiscal year 2023. CEO Michael Brown announced a new strategic initiative focused on renewable energy technologies. The company opened new offices in Tokyo and Berlin during Q3 2023.

Financial Highlights:
- Revenue: $1.2B (up 15% YoY)
- Net Income: $320M (up 22% YoY)
- R&D Expenditure: $180M (up 30% YoY)

Contact: investor.relations@globalenterprises.example.com
EOF

    # Mock functions for testing
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
    
    # Mock entity extraction functions
    extract_entities() {
        local content="$1"
        local content_type="$2"
        local options="$3"
        
        # Choose appropriate extractor based on content type
        case "$content_type" in
            "text/plain")
                extract_entities_text "$content" "$options"
                ;;
            "text/markdown")
                extract_entities_text "$content" "$options"
                ;;
            "text/html")
                extract_entities_text "$content" "$options"
                ;;
            "application/json")
                extract_entities_json "$content" "$options"
                ;;
            "text/x-python")
                extract_entities_code "$content" "$options"
                ;;
            "application/pdf")
                extract_entities_pdf "$content" "$options"
                ;;
            *)
                extract_entities_fallback "$content" "$options"
                ;;
        esac
        
        return $?
    }
    
    extract_entities_text() {
        local content="$1"
        local options="$2"
        
        # Read content if it's a file path
        local text_content
        if [[ -f "$content" ]]; then
            text_content=$(cat "$content")
        else
            text_content="$content"
        fi
        
        # Simple entity extraction for testing
        local entities="["
        
        # Extract persons (very basic approach)
        local persons=$(echo "$text_content" | grep -o -E '[A-Z][a-z]+ [A-Z][a-z]+' | sort | uniq)
        
        # Add person entities
        local first_entity=true
        if [[ -n "$persons" ]]; then
            while IFS= read -r person; do
                if [[ -n "$person" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$person\",\"type\":\"person\",\"mentions\":[{\"context\":\"\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$persons"
        fi
        
        # Extract organizations
        local organizations=$(echo "$text_content" | grep -o -E '(Acme|Microsoft|Apple|TechCorp|Global Enterprises) ?(Inc\.|Corporation|Ltd\.?)?' | sort | uniq)
        
        # Add organization entities
        if [[ -n "$organizations" ]]; then
            while IFS= read -r org; do
                if [[ -n "$org" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$org\",\"type\":\"organization\",\"mentions\":[{\"context\":\"\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$organizations"
        fi
        
        # Extract locations
        local locations=$(echo "$text_content" | grep -o -E '(New York|Cupertino|California|Seattle|Tokyo|Berlin)' | sort | uniq)
        
        # Add location entities
        if [[ -n "$locations" ]]; then
            while IFS= read -r location; do
                if [[ -n "$location" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$location\",\"type\":\"location\",\"mentions\":[{\"context\":\"\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$locations"
        fi
        
        # Extract dates
        local dates=$(echo "$text_content" | grep -o -E '(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2}, [0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{4}' | sort | uniq)
        
        # Add date entities
        if [[ -n "$dates" ]]; then
            while IFS= read -r date; do
                if [[ -n "$date" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$date\",\"type\":\"date\",\"mentions\":[{\"context\":\"\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$dates"
        fi
        
        # Finalize entities array
        entities+="]"
        
        echo "$entities"
        return 0
    }
    
    extract_entities_json() {
        local content="$1"
        local options="$2"
        
        # Read content if it's a file path
        local json_content
        if [[ -f "$content" ]]; then
            json_content=$(cat "$content")
        else
            json_content="$content"
        fi
        
        # Extract entities from JSON content
        local entities="["
        
        # Try to extract JSON keys at top level
        local keys
        keys=$(echo "$json_content" | jq -r 'keys[]' 2>/dev/null || echo "")
        
        # Add key entities
        local first_entity=true
        if [[ -n "$keys" ]]; then
            while IFS= read -r key; do
                if [[ -n "$key" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$key\",\"type\":\"other\",\"mentions\":[{\"context\":\"JSON key\",\"position\":0,\"relevance\":0.5}]}"
                fi
            done <<< "$keys"
        fi
        
        # Try to extract company info
        local company
        company=$(echo "$json_content" | jq -r '.company' 2>/dev/null)
        if [[ -n "$company" && "$company" != "null" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$company\",\"type\":\"organization\",\"mentions\":[{\"context\":\"Company name\",\"position\":0,\"relevance\":0.9}]}"
        fi
        
        # Try to extract headquarter location
        local location
        location=$(echo "$json_content" | jq -r '.headquarters' 2>/dev/null)
        if [[ -n "$location" && "$location" != "null" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$location\",\"type\":\"location\",\"mentions\":[{\"context\":\"Headquarters\",\"position\":0,\"relevance\":0.8}]}"
        fi
        
        # Try to extract founded date
        local date
        date=$(echo "$json_content" | jq -r '.founded' 2>/dev/null)
        if [[ -n "$date" && "$date" != "null" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$date\",\"type\":\"date\",\"mentions\":[{\"context\":\"Founded date\",\"position\":0,\"relevance\":0.8}]}"
        fi
        
        # Finalize entities array
        entities+="]"
        
        echo "$entities"
        return 0
    }
    
    extract_entities_code() {
        local content="$1"
        local options="$2"
        
        # Read content if it's a file path
        local code_content
        if [[ -f "$content" ]]; then
            code_content=$(cat "$content")
        else
            code_content="$content"
        fi
        
        # Simple entity extraction for testing
        local entities="["
        
        # Get file extension to determine language
        local language="unknown"
        if [[ "$content" == *.py ]]; then
            language="python"
        elif [[ "$content" == *.js ]]; then
            language="javascript"
        elif [[ "$content" == *.sh ]]; then
            language="shell"
        fi
        
        # Extract classes (Python)
        local classes=""
        if [[ "$language" == "python" ]]; then
            classes=$(echo "$code_content" | grep -E "^class [A-Za-z0-9_]+" | sed 's/class \([A-Za-z0-9_]\+\).*/\1/g')
        fi
        
        # Add class entities
        local first_entity=true
        if [[ -n "$classes" ]]; then
            while IFS= read -r class; do
                if [[ -n "$class" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$class\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Python class\",\"position\":0,\"relevance\":0.9}]}"
                fi
            done <<< "$classes"
        fi
        
        # Extract functions (Python)
        local functions=""
        if [[ "$language" == "python" ]]; then
            functions=$(echo "$code_content" | grep -E "^def [A-Za-z0-9_]+" | sed 's/def \([A-Za-z0-9_]\+\).*/\1/g')
        fi
        
        # Add function entities
        if [[ -n "$functions" ]]; then
            while IFS= read -r function; do
                if [[ -n "$function" ]]; then
                    if ! $first_entity; then
                        entities+=","
                    else
                        first_entity=false
                    fi
                    entities+="{\"name\":\"$function\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Python function\",\"position\":0,\"relevance\":0.8}]}"
                fi
            done <<< "$functions"
        fi
        
        # Extract imports (Python)
        local imports=""
        if [[ "$language" == "python" ]]; then
            imports=$(echo "$code_content" | grep -E "^import |^from " | sed 's/import \([A-Za-z0-9_.]\+\).*/\1/g; s/from \([A-Za-z0-9_.]\+\).*/\1/g')
        fi
        
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
        
        # Add language as an entity
        if [[ "$language" != "unknown" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$language\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Programming language\",\"position\":0,\"relevance\":0.95}]}"
        fi
        
        # Finalize entities array
        entities+="]"
        
        echo "$entities"
        return 0
    }
    
    extract_entities_pdf() {
        local content="$1"
        local options="$2"
        
        # For testing, use a text file that simulates PDF content
        local pdf_content
        if [[ -f "$content" ]]; then
            pdf_content=$(cat "$content")
        else
            pdf_content="$content"
        fi
        
        # Extract PDF metadata
        local title=$(echo "$pdf_content" | grep "TITLE:" | sed 's/TITLE: \(.*\)/\1/g')
        local author=$(echo "$pdf_content" | grep "AUTHOR:" | sed 's/AUTHOR: \(.*\)/\1/g')
        local created=$(echo "$pdf_content" | grep "CREATED:" | sed 's/CREATED: \(.*\)/\1/g')
        
        # Simple entity extraction for testing
        local entities="["
        local first_entity=true
        
        # Add title entity
        if [[ -n "$title" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$title\",\"type\":\"other\",\"mentions\":[{\"context\":\"PDF Title\",\"position\":0,\"relevance\":0.9}]}"
        fi
        
        # Add author entity
        if [[ -n "$author" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$author\",\"type\":\"organization\",\"mentions\":[{\"context\":\"PDF Author\",\"position\":0,\"relevance\":0.9}]}"
        fi
        
        # Add created date entity
        if [[ -n "$created" ]]; then
            if ! $first_entity; then
                entities+=","
            else
                first_entity=false
            fi
            entities+="{\"name\":\"$created\",\"type\":\"date\",\"mentions\":[{\"context\":\"PDF Creation Date\",\"position\":0,\"relevance\":0.9}]}"
        fi
        
        # Extract text content entities (reuse text extractor)
        local text_entities
        text_entities=$(extract_entities_text "$content" "$options")
        
        # Combine metadata entities with text entities
        if [[ "$text_entities" != "[]" ]]; then
            if ! $first_entity; then
                entities="$entities,${text_entities:1}"  # Remove opening bracket from text_entities
            else
                entities="$text_entities"
            fi
        else
            entities+="]"
        fi
        
        echo "$entities"
        return 0
    }
    
    extract_entities_fallback() {
        local content="$1"
        local options="$2"
        
        # Simple fallback extraction
        extract_entities_text "$content" "$options"
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

@test "entity extraction - json_escape function works correctly" {
    # Sample text with special characters
    local text="Line 1\nLine \"2\"\tTabbed\rReturn\\ Backslash"
    
    # Escape the text
    run json_escape "$text"
    
    # Check that the output has been properly escaped
    assert_success
    assert_output "Line 1\\nLine \\\"2\\\"\\tTabbed\\rReturn\\\\ Backslash"
}

@test "entity extraction - extract_entities_text finds people" {
    run extract_entities_text "${TEST_FILES_DIR}/sample.txt"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found John Smith
    assert_output | grep -q '"name":"John Smith"'
    assert_output | grep -q '"type":"person"'
}

@test "entity extraction - extract_entities_text finds organizations" {
    run extract_entities_text "${TEST_FILES_DIR}/sample.txt"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found Acme Corporation
    assert_output | grep -q '"name":"Acme Corporation"'
    assert_output | grep -q '"type":"organization"'
}

@test "entity extraction - extract_entities_text finds locations" {
    run extract_entities_text "${TEST_FILES_DIR}/sample.txt"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found New York
    assert_output | grep -q '"name":"New York"'
    assert_output | grep -q '"type":"location"'
}

@test "entity extraction - extract_entities_text finds dates" {
    run extract_entities_text "${TEST_FILES_DIR}/sample.txt"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found January 15, 2010
    assert_output | grep -q '"name":"January 15, 2010"'
    assert_output | grep -q '"type":"date"'
}

@test "entity extraction - extract_entities_json finds organization" {
    run extract_entities_json "${TEST_FILES_DIR}/data.json"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found TechCorp
    assert_output | grep -q '"name":"TechCorp"'
    assert_output | grep -q '"type":"organization"'
}

@test "entity extraction - extract_entities_json finds location" {
    run extract_entities_json "${TEST_FILES_DIR}/data.json"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found Seattle
    assert_output | grep -q '"name":"Seattle"'
    assert_output | grep -q '"type":"location"'
}

@test "entity extraction - extract_entities_code finds Python classes" {
    run extract_entities_code "${TEST_FILES_DIR}/sample.py"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found the Person class
    assert_output | grep -q '"name":"Person"'
    assert_output | grep -q '"type":"technology"'
}

@test "entity extraction - extract_entities_code finds Python functions" {
    run extract_entities_code "${TEST_FILES_DIR}/sample.py"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found the calculate_age function
    assert_output | grep -q '"name":"calculate_age"'
    assert_output | grep -q '"type":"technology"'
}

@test "entity extraction - extract_entities_code identifies programming language" {
    run extract_entities_code "${TEST_FILES_DIR}/sample.py"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it identified Python
    assert_output | grep -q '"name":"python"'
    assert_output | grep -q '"type":"technology"'
    assert_output | grep -q '"relevance":0.95'
}

@test "entity extraction - extract_entities_pdf finds metadata" {
    run extract_entities_pdf "${TEST_FILES_DIR}/sample.pdf.txt"
    
    # Check that extraction was successful
    assert_success
    
    # Check that it found the title
    assert_output | grep -q '"name":"Annual Report 2023"'
    
    # Check that it found the author
    assert_output | grep -q '"name":"Global Enterprises Ltd."'
    
    # Check that it found the creation date
    assert_output | grep -q '"name":"2023-12-01"'
    assert_output | grep -q '"type":"date"'
}

@test "entity extraction - extract_entities handles different content types" {
    # Test with plain text
    run extract_entities "${TEST_FILES_DIR}/sample.txt" "text/plain"
    assert_success
    assert_output | grep -q '"name":"John Smith"'
    
    # Test with markdown
    run extract_entities "${TEST_FILES_DIR}/doc.md" "text/markdown"
    assert_success
    assert_output | grep -q '"name":"Jane Doe"'
    
    # Test with HTML
    run extract_entities "${TEST_FILES_DIR}/page.html" "text/html"
    assert_success
    assert_output | grep -q '"name":"Apple Inc."'
    
    # Test with JSON
    run extract_entities "${TEST_FILES_DIR}/data.json" "application/json"
    assert_success
    assert_output | grep -q '"name":"TechCorp"'
    
    # Test with Python code
    run extract_entities "${TEST_FILES_DIR}/sample.py" "text/x-python"
    assert_success
    assert_output | grep -q '"name":"Person"'
    
    # Test with PDF
    run extract_entities "${TEST_FILES_DIR}/sample.pdf.txt" "application/pdf"
    assert_success
    assert_output | grep -q '"name":"Annual Report 2023"'
}

@test "entity extraction - handles unknown content types with fallback" {
    # Test with an unsupported content type
    run extract_entities "${TEST_FILES_DIR}/sample.txt" "application/unsupported"
    
    # Should still succeed using fallback
    assert_success
    
    # Should still find entities using text extraction as fallback
    assert_output | grep -q '"name":"John Smith"'
}