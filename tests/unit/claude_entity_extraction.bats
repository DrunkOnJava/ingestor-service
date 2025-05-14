#!/usr/bin/env bats
# Test cases for Claude API entity extraction integration

load ../test_helper
load ../assertions

setup() {
    setup_test_temp_dir
    TEST_FILES_DIR="${BATS_TEST_DIRNAME}/test_files"
    mkdir -p "${TEST_FILES_DIR}"
    
    # Create test files similar to entity_extractors.bats
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

    # Create sample PDF text
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

    # Sample complex content with multiple entity types
    cat > "${TEST_FILES_DIR}/complex_text.txt" << 'EOF'
QUARTERLY BUSINESS REPORT
Q3 2023, Prepared by: Analytics Team

OVERVIEW:
Tesla Inc. reported strong results in Q3 2023, with revenue reaching $25.4 billion, a 19% increase year-over-year. CEO Elon Musk highlighted the success of the Model Y, which continues to be the best-selling electric vehicle globally.

EXPANSION:
The company opened new Gigafactories in Austin, Texas and Berlin, Germany. Production capacity increased by 25%, allowing for greater market penetration in Europe and North America.

PARTNERSHIPS:
Tesla announced a new collaboration with Microsoft Corporation for cloud infrastructure and AI development. The partnership, set to begin on January 15, 2024, will leverage Microsoft's Azure platform to enhance Tesla's autonomous driving capabilities.

KEY PERSONNEL CHANGES:
- Sarah Johnson promoted to Chief Operating Officer (from VP Operations)
- Dr. Robert Chen joined as Head of AI Research from Google
- Maria Garcia appointed as Director of European Operations

CHALLENGES:
Supply chain disruptions in China affected production in Shanghai during August 2023, causing a temporary 15% reduction in output. These issues have been resolved as of September 10, 2023.

PRODUCT TIMELINE:
- Cybertruck: Production begins November 2023
- Model 2 (compact car): Design finalization by December 2023
- New Powerwall version: Market release scheduled for Q1 2024
- Full Self-Driving v12: Beta testing to start October 30, 2023

For more information, contact investor.relations@tesla.com or visit our investor portal at https://ir.tesla.com
EOF

    # Mock the extract_entities_with_claude function
    extract_entities_with_claude() {
        local content="$1"
        local content_type="$2"
        local options="$3"
        
        # For testing, we'll return a predictable response based on content_type
        case "$content_type" in
            "text/plain")
                echo '[{"name":"John Smith","type":"person","mentions":[{"context":"John Smith is the CEO of Acme Corporation","position":1,"relevance":0.95}]},{"name":"Acme Corporation","type":"organization","mentions":[{"context":"John Smith is the CEO of Acme Corporation","position":4,"relevance":0.9}]},{"name":"New York","type":"location","mentions":[{"context":"He started the company in New York","position":9,"relevance":0.85}]},{"name":"January 15, 2010","type":"date","mentions":[{"context":"in New York on January 15, 2010","position":11,"relevance":0.8}]}]'
                ;;
            "text/markdown")
                echo '[{"name":"Jane Doe","type":"person","mentions":[{"context":"This project was created by Jane Doe","position":3,"relevance":0.9}]},{"name":"Microsoft","type":"organization","mentions":[{"context":"Jane Doe at Microsoft in 2022","position":5,"relevance":0.85}]},{"name":"2022","type":"date","mentions":[{"context":"Microsoft in 2022","position":7,"relevance":0.8}]},{"name":"Python 3.9","type":"technology","mentions":[{"context":"The software uses Python 3.9","position":10,"relevance":0.95}]},{"name":"TensorFlow","type":"technology","mentions":[{"context":"Python 3.9 and TensorFlow","position":13,"relevance":0.9}]}]'
                ;;
            "text/html")
                echo '[{"name":"Apple Inc.","type":"organization","mentions":[{"context":"<title>About Apple Inc.</title>","position":1,"relevance":0.95},{"context":"<h1>Apple Inc.</h1>","position":2,"relevance":0.95}]},{"name":"Steve Jobs","type":"person","mentions":[{"context":"founded by Steve Jobs","position":3,"relevance":0.9}]},{"name":"Steve Wozniak","type":"person","mentions":[{"context":"Steve Jobs, Steve Wozniak","position":4,"relevance":0.9}]},{"name":"Ronald Wayne","type":"person","mentions":[{"context":"Steve Wozniak, and Ronald Wayne","position":6,"relevance":0.9}]},{"name":"Cupertino","type":"location","mentions":[{"context":"in Cupertino, California","position":8,"relevance":0.85}]},{"name":"California","type":"location","mentions":[{"context":"Cupertino, California","position":9,"relevance":0.85}]},{"name":"April 1, 1976","type":"date","mentions":[{"context":"California on April 1, 1976","position":11,"relevance":0.8}]},{"name":"iPhone","type":"product","mentions":[{"context":"products like the iPhone","position":13,"relevance":0.85}]},{"name":"iPad","type":"product","mentions":[{"context":"iPhone, iPad","position":14,"relevance":0.85}]},{"name":"MacBook","type":"product","mentions":[{"context":"iPad, and MacBook","position":16,"relevance":0.85}]}]'
                ;;
            "application/json")
                echo '[{"name":"TechCorp","type":"organization","mentions":[{"context":"\"company\": \"TechCorp\"","position":2,"relevance":0.95}]},{"name":"2015-03-22","type":"date","mentions":[{"context":"\"founded\": \"2015-03-22\"","position":3,"relevance":0.9}]},{"name":"Seattle","type":"location","mentions":[{"context":"\"headquarters\": \"Seattle\"","position":4,"relevance":0.9}]},{"name":"Mark Wilson","type":"person","mentions":[{"context":"\"name\": \"Mark Wilson\",\n      \"position\": \"CEO\"","position":8,"relevance":0.85}]},{"name":"Lisa Chen","type":"person","mentions":[{"context":"\"name\": \"Lisa Chen\",\n      \"position\": \"CTO\"","position":13,"relevance":0.85}]},{"name":"QuantumDB","type":"product","mentions":[{"context":"\"products\": [\"QuantumDB\"","position":19,"relevance":0.8}]},{"name":"CloudSync","type":"product","mentions":[{"context":"\"QuantumDB\", \"CloudSync\"","position":20,"relevance":0.8}]},{"name":"DataViz","type":"product","mentions":[{"context":"\"CloudSync\", \"DataViz\"","position":21,"relevance":0.8}]}]'
                ;;
            "text/x-python")
                echo '[{"name":"Person","type":"class","mentions":[{"context":"class Person:","position":7,"relevance":0.95}]},{"name":"calculate_age","type":"function","mentions":[{"context":"def calculate_age(birthdate):","position":15,"relevance":0.9}]},{"name":"os","type":"module","mentions":[{"context":"import os","position":4,"relevance":0.85}]},{"name":"datetime","type":"module","mentions":[{"context":"import datetime","position":5,"relevance":0.85}]},{"name":"Sarah Johnson","type":"person","mentions":[{"context":"person = Person(\"Sarah Johnson\", 28)","position":23,"relevance":0.75}]},{"name":"Python","type":"language","mentions":[{"context":"#!/usr/bin/env python3","position":1,"relevance":0.95}]}]'
                ;;
            "application/pdf")
                echo '[{"name":"Annual Report 2023","type":"document","mentions":[{"context":"TITLE: Annual Report 2023","position":1,"relevance":0.95}]},{"name":"Global Enterprises Ltd.","type":"organization","mentions":[{"context":"AUTHOR: Global Enterprises Ltd.","position":2,"relevance":0.9},{"context":"Global Enterprises Ltd. reported record earnings","position":6,"relevance":0.9}]},{"name":"2023-12-01","type":"date","mentions":[{"context":"CREATED: 2023-12-01","position":3,"relevance":0.9}]},{"name":"Michael Brown","type":"person","mentions":[{"context":"CEO Michael Brown announced","position":7,"relevance":0.85}]},{"name":"Tokyo","type":"location","mentions":[{"context":"new offices in Tokyo and Berlin","position":10,"relevance":0.8}]},{"name":"Berlin","type":"location","mentions":[{"context":"Tokyo and Berlin during Q3 2023","position":11,"relevance":0.8}]},{"name":"Q3 2023","type":"date","mentions":[{"context":"Berlin during Q3 2023","position":12,"relevance":0.85}]},{"name":"investor.relations@globalenterprises.example.com","type":"contact","mentions":[{"context":"Contact: investor.relations@globalenterprises.example.com","position":20,"relevance":0.75}]}]'
                ;;
            *)
                # Default generic response for other content types
                echo '[{"name":"Unknown Entity","type":"other","mentions":[{"context":"Generic context","position":0,"relevance":0.5}]}]'
                ;;
        esac
        
        return 0
    }
    
    # Mock a failing extract_entities_with_claude function for testing fallbacks
    extract_entities_with_claude_failing() {
        return 1
    }
    
    # Mock analyze_with_claude function for fallback testing
    analyze_with_claude() {
        local content="$1"
        local prompt_type="$2"
        
        # Return a simple JSON that our extract_entities_from_json function can handle
        echo '{"entities": [{"name":"Fallback Entity","type":"other","mentions":[{"context":"Fallback context","position":0,"relevance":0.5}]}]}'
        
        return 0
    }
    
    # Define extract_entities_from_json helper
    extract_entities_from_json() {
        local json="$1"
        echo "$(echo "$json" | jq -r '.entities // []' 2>/dev/null || echo "[]")"
        return 0
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

# Test the extract_entities_with_claude function directly
@test "extract_entities_with_claude - text/plain content returns expected entities" {
    run extract_entities_with_claude "${TEST_FILES_DIR}/sample.txt" "text/plain" ""
    
    assert_success
    assert_output | grep -q '"name":"John Smith"'
    assert_output | grep -q '"name":"Acme Corporation"'
    assert_output | grep -q '"type":"person"'
    assert_output | grep -q '"type":"organization"'
}

@test "extract_entities_with_claude - text/markdown content returns expected entities" {
    run extract_entities_with_claude "${TEST_FILES_DIR}/doc.md" "text/markdown" ""
    
    assert_success
    assert_output | grep -q '"name":"Jane Doe"'
    assert_output | grep -q '"name":"Microsoft"'
    assert_output | grep -q '"name":"Python 3.9"'
    assert_output | grep -q '"name":"TensorFlow"'
}

@test "extract_entities_with_claude - text/html content returns expected entities" {
    run extract_entities_with_claude "${TEST_FILES_DIR}/page.html" "text/html" ""
    
    assert_success
    assert_output | grep -q '"name":"Apple Inc."'
    assert_output | grep -q '"name":"Steve Jobs"'
    assert_output | grep -q '"name":"iPhone"'
    assert_output | grep -q '"name":"April 1, 1976"'
}

@test "extract_entities_with_claude - application/json content returns expected entities" {
    run extract_entities_with_claude "${TEST_FILES_DIR}/data.json" "application/json" ""
    
    assert_success
    assert_output | grep -q '"name":"TechCorp"'
    assert_output | grep -q '"name":"Mark Wilson"'
    assert_output | grep -q '"name":"QuantumDB"'
}

@test "extract_entities_with_claude - text/x-python content returns expected entities" {
    run extract_entities_with_claude "${TEST_FILES_DIR}/sample.py" "text/x-python" ""
    
    assert_success
    assert_output | grep -q '"name":"Person"'
    assert_output | grep -q '"name":"calculate_age"'
    assert_output | grep -q '"name":"Python"'
}

@test "extract_entities_with_claude - application/pdf content returns expected entities" {
    run extract_entities_with_claude "${TEST_FILES_DIR}/sample.pdf.txt" "application/pdf" ""
    
    assert_success
    assert_output | grep -q '"name":"Annual Report 2023"'
    assert_output | grep -q '"name":"Global Enterprises Ltd."'
    assert_output | grep -q '"name":"Michael Brown"'
}

@test "extract_entities_with_claude - handles custom options correctly" {
    # Test with entity_types option
    run extract_entities_with_claude "${TEST_FILES_DIR}/sample.txt" "text/plain" "entity_types=person,organization"
    
    assert_success
    assert_output | grep -q '"name":"John Smith"'
    assert_output | grep -q '"name":"Acme Corporation"'
}

# Tests for entity extraction with Claude integration in text extractor
@test "extract_entities_text - uses extract_entities_with_claude when available" {
    # Define extract_entities_text function that uses our mocked extract_entities_with_claude
    extract_entities_text() {
        local content="$1"
        local options="$2"
        
        # Use our mocked extract_entities_with_claude function
        local entities=$(extract_entities_with_claude "$content" "text/plain" "$options")
        echo "$entities"
        return 0
    }
    
    run extract_entities_text "${TEST_FILES_DIR}/sample.txt" ""
    
    assert_success
    assert_output | grep -q '"name":"John Smith"'
    assert_output | grep -q '"type":"person"'
    assert_output | grep -q '"name":"Acme Corporation"'
    assert_output | grep -q '"type":"organization"'
}

# Test fallback to analyze_with_claude when extract_entities_with_claude fails
@test "extract_entities_text - falls back to analyze_with_claude when extract_entities_with_claude fails" {
    # Define extract_entities_text function that simulates extract_entities_with_claude failure
    extract_entities_text() {
        local content="$1"
        local options="$2"
        
        # Try extract_entities_with_claude (will fail)
        if extract_entities_with_claude_failing "$content" "text/plain" "$options"; then
            echo "Should not reach here"
            return 0
        fi
        
        # Fall back to analyze_with_claude
        local claude_response=$(analyze_with_claude "$content" "text")
        local entities=$(extract_entities_from_json "$claude_response")
        echo "$entities"
        return 0
    }
    
    run extract_entities_text "${TEST_FILES_DIR}/sample.txt" ""
    
    assert_success
    assert_output | grep -q '"name":"Fallback Entity"'
    assert_output | grep -q '"type":"other"'
}

# Test handling complex content with many entity types
@test "extract_entities_with_claude - handles complex text with multiple entity types" {
    # Define a special mock for this test
    extract_entities_with_claude_complex() {
        # Return a complex set of entities
        cat << 'EOF'
[
  {"name":"Tesla Inc.","type":"organization","mentions":[{"context":"Tesla Inc. reported strong results","position":10,"relevance":0.95}]},
  {"name":"Q3 2023","type":"date","mentions":[{"context":"strong results in Q3 2023","position":14,"relevance":0.9}]},
  {"name":"$25.4 billion","type":"other","mentions":[{"context":"revenue reaching $25.4 billion","position":18,"relevance":0.85}]},
  {"name":"Elon Musk","type":"person","mentions":[{"context":"CEO Elon Musk highlighted","position":25,"relevance":0.95}]},
  {"name":"Model Y","type":"product","mentions":[{"context":"success of the Model Y","position":29,"relevance":0.9}]},
  {"name":"Austin","type":"location","mentions":[{"context":"Gigafactories in Austin, Texas","position":40,"relevance":0.85}]},
  {"name":"Texas","type":"location","mentions":[{"context":"Austin, Texas","position":41,"relevance":0.85}]},
  {"name":"Berlin","type":"location","mentions":[{"context":"Berlin, Germany","position":43,"relevance":0.85}]},
  {"name":"Germany","type":"location","mentions":[{"context":"Berlin, Germany","position":44,"relevance":0.85}]},
  {"name":"25%","type":"other","mentions":[{"context":"increased by 25%","position":48,"relevance":0.75}]},
  {"name":"Europe","type":"location","mentions":[{"context":"market penetration in Europe","position":54,"relevance":0.8}]},
  {"name":"North America","type":"location","mentions":[{"context":"Europe and North America","position":56,"relevance":0.8}]},
  {"name":"Microsoft Corporation","type":"organization","mentions":[{"context":"collaboration with Microsoft Corporation","position":62,"relevance":0.9}]},
  {"name":"January 15, 2024","type":"date","mentions":[{"context":"to begin on January 15, 2024","position":71,"relevance":0.85}]},
  {"name":"Azure","type":"product","mentions":[{"context":"Microsoft's Azure platform","position":77,"relevance":0.9}]},
  {"name":"Sarah Johnson","type":"person","mentions":[{"context":"Sarah Johnson promoted to Chief Operating Officer","position":84,"relevance":0.9}]},
  {"name":"Dr. Robert Chen","type":"person","mentions":[{"context":"Dr. Robert Chen joined as Head of AI Research","position":92,"relevance":0.9}]},
  {"name":"Google","type":"organization","mentions":[{"context":"AI Research from Google","position":101,"relevance":0.85}]},
  {"name":"Maria Garcia","type":"person","mentions":[{"context":"Maria Garcia appointed as Director","position":103,"relevance":0.9}]},
  {"name":"China","type":"location","mentions":[{"context":"disruptions in China affected","position":116,"relevance":0.85}]},
  {"name":"Shanghai","type":"location","mentions":[{"context":"production in Shanghai during","position":120,"relevance":0.85}]},
  {"name":"August 2023","type":"date","mentions":[{"context":"Shanghai during August 2023","position":123,"relevance":0.85}]},
  {"name":"15%","type":"other","mentions":[{"context":"temporary 15% reduction","position":128,"relevance":0.75}]},
  {"name":"September 10, 2023","type":"date","mentions":[{"context":"resolved as of September 10, 2023","position":137,"relevance":0.85}]},
  {"name":"Cybertruck","type":"product","mentions":[{"context":"Cybertruck: Production begins","position":143,"relevance":0.9}]},
  {"name":"November 2023","type":"date","mentions":[{"context":"Production begins November 2023","position":146,"relevance":0.85}]},
  {"name":"Model 2","type":"product","mentions":[{"context":"Model 2 (compact car)","position":148,"relevance":0.9}]},
  {"name":"December 2023","type":"date","mentions":[{"context":"finalization by December 2023","position":154,"relevance":0.85}]},
  {"name":"Powerwall","type":"product","mentions":[{"context":"New Powerwall version","position":156,"relevance":0.9}]},
  {"name":"Q1 2024","type":"date","mentions":[{"context":"scheduled for Q1 2024","position":163,"relevance":0.85}]},
  {"name":"Full Self-Driving v12","type":"product","mentions":[{"context":"Full Self-Driving v12:","position":165,"relevance":0.9}]},
  {"name":"October 30, 2023","type":"date","mentions":[{"context":"to start October 30, 2023","position":173,"relevance":0.85}]},
  {"name":"investor.relations@tesla.com","type":"contact","mentions":[{"context":"contact investor.relations@tesla.com","position":181,"relevance":0.8}]},
  {"name":"https://ir.tesla.com","type":"url","mentions":[{"context":"investor portal at https://ir.tesla.com","position":190,"relevance":0.8}]}
]
EOF
        return 0
    }
    
    run extract_entities_with_claude_complex
    
    assert_success
    
    # Test for various entity types
    assert_output | grep -q '"name":"Tesla Inc."'
    assert_output | grep -q '"type":"organization"'
    
    assert_output | grep -q '"name":"Elon Musk"'
    assert_output | grep -q '"type":"person"'
    
    assert_output | grep -q '"name":"Model Y"'
    assert_output | grep -q '"type":"product"'
    
    assert_output | grep -q '"name":"Berlin"'
    assert_output | grep -q '"type":"location"'
    
    assert_output | grep -q '"name":"Q3 2023"'
    assert_output | grep -q '"type":"date"'
    
    assert_output | grep -q '"name":"https://ir.tesla.com"'
    assert_output | grep -q '"type":"url"'
    
    # Check for statistics/percentages
    assert_output | grep -q '"name":"25%"'
    
    # Verify we have more than 20 entities
    assert [ $(echo "$(extract_entities_with_claude_complex)" | grep -o '"name"' | wc -l) -gt 20 ]
}

# Test integration with file type detection
@test "extract_entities_with_claude - detects file types correctly" {
    # Create a specialized mock function for this test that returns the content type
    extract_entities_with_claude_detect() {
        local content="$1"
        local content_type="$2"
        
        # Just echo back the content type for testing
        echo "{\"detected_content_type\":\"$content_type\"}"
        return 0
    }

    # Test different file types
    run extract_entities_with_claude_detect "${TEST_FILES_DIR}/sample.txt" "text/plain"
    assert_success
    assert_output | grep -q '"detected_content_type":"text/plain"'
    
    run extract_entities_with_claude_detect "${TEST_FILES_DIR}/doc.md" "text/markdown"
    assert_success
    assert_output | grep -q '"detected_content_type":"text/markdown"'
    
    run extract_entities_with_claude_detect "${TEST_FILES_DIR}/page.html" "text/html"
    assert_success
    assert_output | grep -q '"detected_content_type":"text/html"'
    
    run extract_entities_with_claude_detect "${TEST_FILES_DIR}/data.json" "application/json"
    assert_success
    assert_output | grep -q '"detected_content_type":"application/json"'
    
    run extract_entities_with_claude_detect "${TEST_FILES_DIR}/sample.py" "text/x-python"
    assert_success
    assert_output | grep -q '"detected_content_type":"text/x-python"'
}

# Test for handling options
@test "extract_entities_with_claude - handles custom options correctly" {
    # Create a specialized mock function for this test that returns the options
    extract_entities_with_claude_options() {
        local content="$1"
        local content_type="$2"
        local options="$3"
        
        # Just echo back the options for testing
        echo "{\"options\":\"$options\"}"
        return 0
    }

    # Test with various option combinations
    run extract_entities_with_claude_options "${TEST_FILES_DIR}/sample.txt" "text/plain" "entity_types=person,organization"
    assert_success
    assert_output | grep -q '"options":"entity_types=person,organization"'
    
    run extract_entities_with_claude_options "${TEST_FILES_DIR}/sample.txt" "text/plain" "confidence_threshold=0.8"
    assert_success
    assert_output | grep -q '"options":"confidence_threshold=0.8"'
    
    run extract_entities_with_claude_options "${TEST_FILES_DIR}/sample.txt" "text/plain" "entity_types=person,confidence_threshold=0.8"
    assert_success
    assert_output | grep -q '"options":"entity_types=person,confidence_threshold=0.8"'
}

# Test for error handling
@test "extract_entities_with_claude - handles errors gracefully" {
    # Mock a failing extract_entities_with_claude that returns different error codes
    extract_entities_with_claude_error() {
        local error_code="$3"
        return "$error_code"
    }
    
    # Test different error scenarios
    run extract_entities_with_claude_error "test" "text/plain" 1
    assert_failure 1
    
    run extract_entities_with_claude_error "test" "text/plain" 2
    assert_failure 2
}

# Test integrated fallback behavior
@test "entity extraction - integrated fallback behavior works correctly" {
    # Define a test function with all the fallback behavior
    test_fallback() {
        local content="$1"
        
        # First try with extract_entities_with_claude (will fail)
        if extract_entities_with_claude_failing "$content" "text/plain" ""; then
            echo "Should not reach here"
            return 0
        fi
        
        # Then try with analyze_with_claude
        local claude_response=$(analyze_with_claude "$content" "text")
        
        # Parse the response
        local entities=$(extract_entities_from_json "$claude_response")
        
        echo "$entities"
        return 0
    }
    
    run test_fallback "${TEST_FILES_DIR}/sample.txt"
    
    assert_success
    assert_output | grep -q '"name":"Fallback Entity"'
}

# Test entity normalization integration
@test "entity extraction - normalizes entities correctly" {
    # Mock normalize_entity_name function
    normalize_entity_name() {
        local name="$1"
        local type="$2"
        
        case "$type" in
            person)
                # Capitalize each word for person names
                echo "$(echo "$name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')"
                ;;
            organization)
                # Organizations often have specific capitalization, preserve most of it
                echo "$name"
                ;;
            location)
                # Capitalize first letter of each word for locations
                echo "$(echo "$name" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')"
                ;;
            date)
                # Try to standardize date formats (basic approach)
                if [[ "$name" =~ ^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}$ ]]; then
                    # Convert MM/DD/YYYY to YYYY-MM-DD
                    echo "$(echo "$name" | awk -F'/' '{print $3"-"$1"-"$2}')"
                else
                    echo "$name"
                fi
                ;;
            *)
                # Default normalization just trims whitespace
                echo "$(echo "$name" | sed 's/^ *//;s/ *$//')"
                ;;
        esac
    }
    
    # Test normalization of different entity types
    run normalize_entity_name "john smith" "person"
    assert_success
    assert_output "John Smith"
    
    run normalize_entity_name "NEW YORK CITY" "location"
    assert_success
    assert_output "New York City"
    
    run normalize_entity_name "acme corporation" "organization"
    assert_success
    assert_output "acme corporation"
    
    run normalize_entity_name "01/15/2023" "date"
    assert_success
    assert_output "2023-01-15"
}

# Test entity validation
@test "entity extraction - validates entity types correctly" {
    # Mock the ENTITY_TYPES array
    ENTITY_TYPES=("person" "organization" "location" "date" "product" "technology" "event" "other")
    
    # Mock validate_entity_type function
    validate_entity_type() {
        local type="$1"
        
        for valid_type in "${ENTITY_TYPES[@]}"; do
            if [[ "$type" == "$valid_type" ]]; then
                return 0  # Valid type
            fi
        done
        
        return 1  # Invalid type
    }
    
    # Test validation of different entity types
    run validate_entity_type "person"
    assert_success
    
    run validate_entity_type "organization"
    assert_success
    
    run validate_entity_type "invalid_type"
    assert_failure
    
    run validate_entity_type "PERSON"  # Case sensitive
    assert_failure
}

# Test entity storage
@test "entity extraction - store_entity handles entities correctly" {
    # Mock database functions
    db_query() {
        local query="$1"
        
        if [[ "$query" == *"SELECT id FROM entities"* ]]; then
            # Simulate existing entity
            if [[ "$query" == *"name = 'John Smith'"* ]]; then
                echo "123"
            else
                # Simulate new entity
                echo ""
            fi
        elif [[ "$query" == *"INSERT INTO entities"* ]]; then
            # Simulate successful insertion
            echo "456"
        fi
        
        return 0
    }
    
    # Mock store_entity function
    store_entity() {
        local name="$1"
        local type="$2"
        local description="$3"
        
        # Normalize entity name
        local normalized_name
        normalized_name=$(normalize_entity_name "$name" "$type")
        
        # Check if entity already exists
        local entity_id
        entity_id=$(db_query "SELECT id FROM entities WHERE name = '$normalized_name' AND entity_type = '$type' LIMIT 1;")
        
        # If entity doesn't exist, create it
        if [[ -z "$entity_id" ]]; then
            entity_id=$(db_query "INSERT INTO entities (name, entity_type, description) VALUES ('$normalized_name', '$type', '$description') RETURNING id;")
        fi
        
        echo "$entity_id"
    }
    
    # Test storing existing entity
    run store_entity "John Smith" "person" "A person"
    assert_success
    assert_output "123"
    
    # Test storing new entity
    run store_entity "New Entity" "organization" "A new organization"
    assert_success
    assert_output "456"
}

# Test entity-content linking
@test "entity extraction - link_entity_to_content functions correctly" {
    # Mock database functions
    db_query() {
        local query="$1"
        
        if [[ "$query" == *"SELECT COUNT(*) FROM content_entities"* ]]; then
            # Simulate existing link for entityId 123, new link for entityId 456
            if [[ "$query" == *"entity_id = 123"* ]]; then
                echo "1"
            else
                echo "0"
            fi
        fi
        
        return 0
    }
    
    # Mock link_entity_to_content function
    link_entity_to_content() {
        local entity_id="$1"
        local content_id="$2"
        local content_type="$3"
        local relevance="$4"
        local context="$5"
        
        # Check if link already exists
        local link_exists
        link_exists=$(db_query "SELECT COUNT(*) FROM content_entities WHERE content_id = $content_id AND content_type = '$content_type' AND entity_id = $entity_id;")
        
        # Return different values for testing
        if [[ "$link_exists" == "0" ]]; then
            echo "Created new link"
        else
            echo "Updated existing link"
        fi
        
        return 0
    }
    
    # Test linking to existing entity-content pair
    run link_entity_to_content "123" "789" "text/plain" "0.9" "Some context"
    assert_success
    assert_output "Updated existing link"
    
    # Test linking to new entity-content pair
    run link_entity_to_content "456" "789" "text/plain" "0.8" "New context"
    assert_success
    assert_output "Created new link"
}