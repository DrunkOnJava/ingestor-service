#!/bin/bash
# Test script for entity extraction integration with Claude API

# Source the entity extraction module
source "$(dirname "$0")/../src/modules/entity_extractors.sh"

# Test extract_entities_with_claude function
echo "Testing entity extraction with Claude API..."

# Create test files
TEMP_DIR="${TEMP_DIR:-/tmp/ingestor-temp}"
mkdir -p "$TEMP_DIR"

# Create a text file with sample content
TEXT_FILE="$TEMP_DIR/sample_text.txt"
cat > "$TEXT_FILE" << EOF
John Smith is the CEO of Acme Corporation based in New York City.
The company was founded on January 15, 2005 and specializes in innovative technology solutions.
Their flagship product, SuperWidget Pro 2000, has been on the market since 2010.
For more information, contact jane.doe@acme.com or visit www.acmecorp.com.
EOF

# Create a JSON file with sample content
JSON_FILE="$TEMP_DIR/sample_data.json"
cat > "$JSON_FILE" << EOF
{
  "company": "Acme Corporation",
  "founded": "2005-01-15",
  "headquarters": "New York, NY",
  "leadership": {
    "CEO": "John Smith",
    "CTO": "Jane Doe"
  },
  "products": [
    {
      "name": "SuperWidget Pro 2000",
      "launchDate": "2010-05-20",
      "price": 299.99
    },
    {
      "name": "MegaService Plus",
      "launchDate": "2015-10-10",
      "price": 59.99
    }
  ]
}
EOF

# Create a code file with sample content
CODE_FILE="$TEMP_DIR/sample_code.py"
cat > "$CODE_FILE" << EOF
#!/usr/bin/env python
# Sample code for entity extraction testing

import os
import json
import datetime
from acme.widgets import SuperWidget

class WidgetProcessor:
    def __init__(self, config_path):
        self.config_path = config_path
        self.widgets = []
        self.load_config()
        
    def load_config(self):
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
            
    def process_widget(self, widget_id):
        """Process a widget with the given ID"""
        widget = SuperWidget(widget_id)
        widget.initialize()
        result = widget.process()
        self.widgets.append(widget)
        return result
        
def main():
    processor = WidgetProcessor('/etc/acme/widgets.json')
    result = processor.process_widget('SW2000-1234')
    print(f"Processing complete: {result}")
    
if __name__ == "__main__":
    main()
EOF

# Function to display test results
display_results() {
    local title="$1"
    local content="$2"
    local result="$3"
    
    echo ""
    echo "=== $title ==="
    echo "Content: $content"
    echo "Result:"
    echo "$result" | jq . 2>/dev/null || echo "$result"
    echo ""
}

# Test text entity extraction
echo "Testing text entity extraction..."
TEXT_RESULT=$(extract_entities "$TEXT_FILE" "text/plain")
display_results "Text Entity Extraction" "$TEXT_FILE" "$TEXT_RESULT"

# Test JSON entity extraction
echo "Testing JSON entity extraction..."
JSON_RESULT=$(extract_entities "$JSON_FILE" "application/json")
display_results "JSON Entity Extraction" "$JSON_FILE" "$JSON_RESULT"

# Test code entity extraction
echo "Testing code entity extraction..."
CODE_RESULT=$(extract_entities "$CODE_FILE" "text/x-python")
display_results "Code Entity Extraction" "$CODE_FILE" "$CODE_RESULT"

# Test generic entity extraction
echo "Testing generic entity extraction..."
GENERIC_RESULT=$(extract_entities "$TEXT_FILE" "unknown/type")
display_results "Generic Entity Extraction" "$TEXT_FILE" "$GENERIC_RESULT"

# Clean up
echo "Cleaning up test files..."
rm -f "$TEXT_FILE" "$JSON_FILE" "$CODE_FILE"

echo "Entity extraction tests completed."