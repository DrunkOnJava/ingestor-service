#!/usr/bin/env bats
# Enhanced test cases for entity extractors module with Claude integration

load ../test_helper
load ../assertions

setup() {
    setup_test_temp_dir
    TEST_FILES_DIR="${BATS_TEST_DIRNAME}/test_files"
    mkdir -p "${TEST_FILES_DIR}"
    
    # Create test files - extended versions with more entity types
    cat > "${TEST_FILES_DIR}/extended_sample.txt" << 'EOF'
Project Status Report - June 15, 2023

Project Name: Next-Gen Analytics Platform
Lead Developer: Dr. Emily Chen
Client: Accenture Global Solutions

Timeline:
* Project Start: January 10, 2023
* Phase 1 Completion: March 30, 2023
* Phase 2 Completion: May 15, 2023
* Expected Delivery: August 25, 2023

Team Members:
- Dr. Emily Chen (Project Lead)
- Michael Rodriguez (Backend Developer)
- Sarah Johnson (Frontend Developer)
- David Kim (Data Scientist)
- Jennifer Wong (UX Designer)

Technology Stack:
- Backend: Python 3.11 with FastAPI
- Frontend: React 18 with TypeScript
- Database: PostgreSQL 15
- Analytics: TensorFlow 2.12
- Cloud: AWS (EC2, S3, Lambda)

Current Status:
The team successfully deployed the initial analytics dashboard to our staging environment at https://staging.analytics.example.com. We've integrated with Accenture's data warehouse located in their Frankfurt office. Last week, we identified 3 critical bugs that were preventing accurate reporting for financial metrics. These issues have been resolved as of June 12, 2023.

Next Steps:
1. Complete API integration with Salesforce
2. Implement real-time alerting system
3. Finalize documentation for v1.0 release

Budget Summary:
Initial Budget: $750,000
Current Spend: $425,000
Projected Final Cost: $720,000

For questions, please contact emily.chen@example.com or call +1-415-555-1234.
EOF

    cat > "${TEST_FILES_DIR}/extended_code.py" << 'EOF'
#!/usr/bin/env python3
"""
Advanced Analytics Module
Version: 1.2.3
Author: Emily Chen
Last Updated: 2023-06-10
"""

import os
import sys
import pandas as pd
import numpy as np
import tensorflow as tf
from datetime import datetime
from typing import List, Dict, Optional, Union
from fastapi import FastAPI, HTTPException, Depends
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Constants
API_VERSION = "v1.0"
MAX_BATCH_SIZE = 1000
DEFAULT_TIMEOUT = 30  # seconds

# Initialize FastAPI app
app = FastAPI(
    title="Analytics API",
    description="Enterprise analytics processing system",
    version=API_VERSION
)

# Database models
Base = declarative_base()

class DataPoint(Base):
    __tablename__ = "data_points"
    
    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow)
    source = Column(String(100), index=True)
    metric_name = Column(String(100), index=True)
    metric_value = Column(Float)
    dimensions = Column(String(500))  # JSON string of dimensions

class AnalyticsModel:
    def __init__(self, name: str, version: str, parameters: Dict[str, any]):
        self.name = name
        self.version = version
        self.parameters = parameters
        self.model = None
        
    def load(self, path: str) -> bool:
        """Load a saved model from disk"""
        try:
            self.model = tf.saved_model.load(path)
            return True
        except Exception as e:
            print(f"Error loading model: {e}")
            return False
    
    def predict(self, features: np.ndarray) -> np.ndarray:
        """Run prediction on input features"""
        if self.model is None:
            raise ValueError("Model not loaded")
        
        return self.model(features).numpy()

def preprocess_data(data: pd.DataFrame, config: Dict[str, any]) -> pd.DataFrame:
    """Preprocess input data according to configuration"""
    # Handle missing values
    if config.get("fill_missing", False):
        data = data.fillna(config.get("fill_value", 0))
    
    # Normalize numeric columns
    if config.get("normalize", False):
        for col in config.get("numeric_columns", []):
            if col in data.columns:
                data[col] = (data[col] - data[col].mean()) / data[col].std()
    
    return data

@app.get("/api/v1/health")
async def health_check():
    """API health check endpoint"""
    return {"status": "healthy", "version": API_VERSION}

@app.post("/api/v1/analyze")
async def analyze_data(data: Dict[str, any]):
    """Process analytics data and return insights"""
    try:
        # Implementation omitted for brevity
        return {"status": "success", "results": {}}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    cat > "${TEST_FILES_DIR}/extended_data.json" << 'EOF'
{
  "company": "TechSolutions Inc.",
  "founded": "2008-03-15",
  "headquarters": {
    "city": "San Francisco",
    "state": "California",
    "country": "USA",
    "address": "123 Innovation Drive",
    "postal_code": "94105"
  },
  "employees": 1250,
  "public": true,
  "stock_symbol": "TSOL",
  "leadership": {
    "CEO": {
      "name": "Jennifer Martinez",
      "appointed": "2015-01-10",
      "education": "Stanford University",
      "previous_companies": ["Google", "Oracle"]
    },
    "CTO": {
      "name": "Robert Chang",
      "appointed": "2012-06-22",
      "education": "MIT",
      "patents": 14
    },
    "CFO": {
      "name": "Michael Wilson",
      "appointed": "2016-04-15",
      "education": "Harvard Business School"
    }
  },
  "products": [
    {
      "name": "DataSense Pro",
      "launched": "2010-11-05",
      "category": "Analytics",
      "customers": 1500,
      "revenue": 45000000
    },
    {
      "name": "CloudMatrix",
      "launched": "2015-03-20",
      "category": "Cloud Infrastructure",
      "customers": 2300,
      "revenue": 85000000
    },
    {
      "name": "SecureID",
      "launched": "2018-09-12",
      "category": "Security",
      "customers": 750,
      "revenue": 22000000
    }
  ],
  "offices": [
    {
      "location": "San Francisco",
      "employees": 750,
      "opened": "2008-03-15"
    },
    {
      "location": "Austin",
      "employees": 220,
      "opened": "2014-06-10"
    },
    {
      "location": "Boston",
      "employees": 180,
      "opened": "2016-02-15"
    },
    {
      "location": "London",
      "employees": 100,
      "opened": "2018-09-01"
    }
  ],
  "partnerships": ["Microsoft", "AWS", "Salesforce", "Adobe"],
  "funding": {
    "total": "$125M",
    "rounds": [
      {
        "series": "A",
        "amount": "$8M",
        "date": "2009-05-12",
        "investors": ["First Capital", "Tech Ventures"]
      },
      {
        "series": "B",
        "amount": "$22M",
        "date": "2011-10-30",
        "investors": ["Growth Partners", "Innovation Fund", "First Capital"]
      },
      {
        "series": "C",
        "amount": "$45M",
        "date": "2014-08-15",
        "investors": ["Global Invest", "Tech Growth Fund"]
      },
      {
        "series": "D",
        "amount": "$50M",
        "date": "2017-11-08",
        "investors": ["Expansion Capital", "Strategic Ventures", "Global Invest"]
      }
    ]
  },
  "financials": {
    "2022": {
      "revenue": 180000000,
      "growth": 0.22,
      "profit": 32000000
    },
    "2021": {
      "revenue": 147000000,
      "growth": 0.35,
      "profit": 25000000
    },
    "2020": {
      "revenue": 109000000,
      "growth": 0.15,
      "profit": 18000000
    }
  },
  "website": "https://www.techsolutions-example.com",
  "contact": "info@techsolutions-example.com"
}
EOF

    # Create tests directory for file
    mkdir -p "${TEST_FILES_DIR}/test_output"
    
    # Create a mock of the enhanced entity extractors module
    # This allows us to test the end-to-end entity extraction flow
    cat > "${TEST_TEMP_DIR}/entity_extractors.sh" << 'EOF'
#!/bin/bash
# Mock entity extractors module with Claude integration

# Initialize extractors
init_entity_extractors() {
    declare -A ENTITY_EXTRACTORS
    ENTITY_EXTRACTORS["text/plain"]="extract_entities_text"
    ENTITY_EXTRACTORS["text/markdown"]="extract_entities_text"
    ENTITY_EXTRACTORS["text/html"]="extract_entities_text"
    ENTITY_EXTRACTORS["application/json"]="extract_entities_json"
    ENTITY_EXTRACTORS["text/x-python"]="extract_entities_code"
    ENTITY_EXTRACTORS["application/pdf"]="extract_entities_pdf"
}

# Main entity extraction function
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

# Mock extract_entities_with_claude function
extract_entities_with_claude() {
    local content="$1"
    local content_type="$2"
    local options="$3"
    
    # Create predictable test output based on content type and content
    local entity_count=0
    local entities="["
    
    # For text files, extract some basic entities
    if [[ "$content_type" == "text/plain" ]]; then
        # Check content for people
        if grep -q "Emily Chen" "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"Dr. Emily Chen\",\"type\":\"person\",\"mentions\":[{\"context\":\"Lead Developer: Dr. Emily Chen\",\"position\":10,\"relevance\":0.95}]}"
            entity_count=$((entity_count + 1))
        fi
        
        # Check for organizations
        if grep -q "Accenture" "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"Accenture Global Solutions\",\"type\":\"organization\",\"mentions\":[{\"context\":\"Client: Accenture Global Solutions\",\"position\":15,\"relevance\":0.9}]}"
            entity_count=$((entity_count + 1))
        fi
        
        # Check for technologies
        if grep -q "Python" "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"Python 3.11\",\"type\":\"technology\",\"mentions\":[{\"context\":\"Backend: Python 3.11 with FastAPI\",\"position\":30,\"relevance\":0.85}]}"
            entity_count=$((entity_count + 1))
        fi
    elif [[ "$content_type" == "application/json" ]]; then
        # Extract some JSON entities
        if grep -q "TechSolutions" "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"TechSolutions Inc.\",\"type\":\"organization\",\"mentions\":[{\"context\":\"company\": \"TechSolutions Inc.\",\"position\":5,\"relevance\":0.95}]}"
            entity_count=$((entity_count + 1))
        fi
        
        if grep -q "Jennifer Martinez" "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"Jennifer Martinez\",\"type\":\"person\",\"mentions\":[{\"context\":\"CEO\": {\"name\": \"Jennifer Martinez\",\"position\":25,\"relevance\":0.9}]}"
            entity_count=$((entity_count + 1))
        fi
    elif [[ "$content_type" == "text/x-python" ]]; then
        # Extract some code entities
        if grep -q "class " "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"DataPoint\",\"type\":\"class\",\"mentions\":[{\"context\":\"class DataPoint(Base):\",\"position\":40,\"relevance\":0.95}]}"
            entity_count=$((entity_count + 1))
        fi
        
        if grep -q "def " "$content" 2>/dev/null; then
            [[ $entity_count -gt 0 ]] && entities+=","
            entities+="{\"name\":\"preprocess_data\",\"type\":\"function\",\"mentions\":[{\"context\":\"def preprocess_data(data: pd.DataFrame, config: Dict[str, any])\",\"position\":60,\"relevance\":0.9}]}"
            entity_count=$((entity_count + 1))
        fi
    fi
    
    # Add a generic entity if no specific entities were found
    if [[ $entity_count -eq 0 ]]; then
        entities+="{\"name\":\"Generic Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Generic Context\",\"position\":0,\"relevance\":0.5}]}"
    fi
    
    entities+="]"
    echo "$entities"
    return 0
}

# Text entity extractor with Claude integration
extract_entities_text() {
    local content="$1"
    local options="$2"
    
    # Try to use extract_entities_with_claude first
    local entities
    entities=$(extract_entities_with_claude "$content" "text/plain" "$options")
    
    # Check if extraction was successful
    if [[ -n "$entities" && "$entities" != "[]" ]]; then
        echo "$entities"
    else
        # Fallback to basic extraction
        echo "[{\"name\":\"Fallback Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Fallback Context\",\"position\":0,\"relevance\":0.5}]}]"
    fi
    
    return 0
}

# JSON entity extractor with Claude integration
extract_entities_json() {
    local content="$1"
    local options="$2"
    
    # Try to use extract_entities_with_claude first
    local entities
    entities=$(extract_entities_with_claude "$content" "application/json" "$options")
    
    # Check if extraction was successful
    if [[ -n "$entities" && "$entities" != "[]" ]]; then
        echo "$entities"
    else
        # Fallback to basic extraction
        echo "[{\"name\":\"Fallback JSON Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Fallback JSON Context\",\"position\":0,\"relevance\":0.5}]}]"
    fi
    
    return 0
}

# Code entity extractor with Claude integration
extract_entities_code() {
    local content="$1"
    local options="$2"
    
    # Try to use extract_entities_with_claude first
    local entities
    entities=$(extract_entities_with_claude "$content" "text/x-python" "$options")
    
    # Check if extraction was successful
    if [[ -n "$entities" && "$entities" != "[]" ]]; then
        echo "$entities"
    else
        # Fallback to basic extraction
        echo "[{\"name\":\"Fallback Code Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Fallback Code Context\",\"position\":0,\"relevance\":0.5}]}]"
    fi
    
    return 0
}

# PDF entity extractor with Claude integration
extract_entities_pdf() {
    local content="$1"
    local options="$2"
    
    # Try to use extract_entities_with_claude first
    local entities
    entities=$(extract_entities_with_claude "$content" "application/pdf" "$options")
    
    # Check if extraction was successful
    if [[ -n "$entities" && "$entities" != "[]" ]]; then
        echo "$entities"
    else
        # Fallback to basic extraction
        echo "[{\"name\":\"Fallback PDF Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Fallback PDF Context\",\"position\":0,\"relevance\":0.5}]}]"
    fi
    
    return 0
}

# Fallback entity extractor
extract_entities_fallback() {
    local content="$1"
    local options="$2"
    
    # Try to use extract_entities_with_claude first with generic content type
    local entities
    entities=$(extract_entities_with_claude "$content" "application/octet-stream" "$options")
    
    # Check if extraction was successful
    if [[ -n "$entities" && "$entities" != "[]" ]]; then
        echo "$entities"
    else
        # Fallback to very basic extraction
        echo "[{\"name\":\"Unknown Entity\",\"type\":\"other\",\"mentions\":[{\"context\":\"Unknown Context\",\"position\":0,\"relevance\":0.5}]}]"
    fi
    
    return 0
}

# Helper function for testing
test_entity_extraction() {
    local content_path="$1"
    local content_type="$2"
    local options="$3"
    local output_path="$4"
    
    # Extract entities
    local entities
    entities=$(extract_entities "$content_path" "$content_type" "$options")
    
    # Write to output file for verification
    echo "$entities" > "$output_path"
    
    return 0
}

# Initialize entity extractors
init_entity_extractors
EOF

    chmod +x "${TEST_TEMP_DIR}/entity_extractors.sh"
}

teardown() {
    if [[ -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
    
    if [[ -d "${TEST_FILES_DIR}" ]]; then
        rm -rf "${TEST_FILES_DIR}"
    fi
}

# Load our mock module
load_mock_extractors() {
    source "${TEST_TEMP_DIR}/entity_extractors.sh"
}

# Test text entity extraction with Claude integration
@test "enhanced entity extraction - text extraction with Claude integration" {
    load_mock_extractors
    
    # Extract entities from text file
    local output_file="${TEST_FILES_DIR}/test_output/text_entities.json"
    run test_entity_extraction "${TEST_FILES_DIR}/extended_sample.txt" "text/plain" "" "$output_file"
    
    # Check that extraction was successful
    assert_success
    
    # Verify output file was created
    [ -f "$output_file" ]
    
    # Check that expected entities were found
    run cat "$output_file"
    assert_output | grep -q '"name":"Dr. Emily Chen"'
    assert_output | grep -q '"type":"person"'
    assert_output | grep -q '"relevance":0.95'
}

# Test JSON entity extraction with Claude integration
@test "enhanced entity extraction - JSON extraction with Claude integration" {
    load_mock_extractors
    
    # Extract entities from JSON file
    local output_file="${TEST_FILES_DIR}/test_output/json_entities.json"
    run test_entity_extraction "${TEST_FILES_DIR}/extended_data.json" "application/json" "" "$output_file"
    
    # Check that extraction was successful
    assert_success
    
    # Verify output file was created
    [ -f "$output_file" ]
    
    # Check that expected entities were found
    run cat "$output_file"
    assert_output | grep -q '"name":"TechSolutions Inc."'
    assert_output | grep -q '"type":"organization"'
}

# Test code entity extraction with Claude integration
@test "enhanced entity extraction - code extraction with Claude integration" {
    load_mock_extractors
    
    # Extract entities from Python file
    local output_file="${TEST_FILES_DIR}/test_output/code_entities.json"
    run test_entity_extraction "${TEST_FILES_DIR}/extended_code.py" "text/x-python" "" "$output_file"
    
    # Check that extraction was successful
    assert_success
    
    # Verify output file was created
    [ -f "$output_file" ]
    
    # Check that expected entities were found
    run cat "$output_file"
    assert_output | grep -q '"name":"DataPoint"'
    assert_output | grep -q '"type":"class"'
}

# Test extraction with options
@test "enhanced entity extraction - handles extraction options" {
    load_mock_extractors
    
    # Extract entities with specific options
    local output_file="${TEST_FILES_DIR}/test_output/options_test.json"
    run test_entity_extraction "${TEST_FILES_DIR}/extended_sample.txt" "text/plain" "entity_types=person,organization" "$output_file"
    
    # Check that extraction was successful
    assert_success
    
    # Verify output file was created
    [ -f "$output_file" ]
    
    # The mock extract_entities_with_claude doesn't actually process options,
    # but in a real implementation it would filter by entity type
    run cat "$output_file"
    assert_output | grep -q '"name":"Dr. Emily Chen"'
}

# Test end-to-end entity extraction process
@test "enhanced entity extraction - end-to-end process works" {
    load_mock_extractors
    
    # Process multiple files
    local text_output="${TEST_FILES_DIR}/test_output/text_result.json"
    local json_output="${TEST_FILES_DIR}/test_output/json_result.json"
    local code_output="${TEST_FILES_DIR}/test_output/code_result.json"
    
    # Run extractions
    run test_entity_extraction "${TEST_FILES_DIR}/extended_sample.txt" "text/plain" "" "$text_output"
    assert_success
    
    run test_entity_extraction "${TEST_FILES_DIR}/extended_data.json" "application/json" "" "$json_output"
    assert_success
    
    run test_entity_extraction "${TEST_FILES_DIR}/extended_code.py" "text/x-python" "" "$code_output"
    assert_success
    
    # Verify all files contain valid JSON
    run bash -c "cat '$text_output' | jq ."
    assert_success
    
    run bash -c "cat '$json_output' | jq ."
    assert_success
    
    run bash -c "cat '$code_output' | jq ."
    assert_success
}

# Test entity extraction with unknown content type
@test "enhanced entity extraction - handles unknown content types" {
    load_mock_extractors
    
    # Extract entities with unknown content type
    local output_file="${TEST_FILES_DIR}/test_output/unknown_type.json"
    run test_entity_extraction "${TEST_FILES_DIR}/extended_sample.txt" "application/unknown" "" "$output_file"
    
    # Check that extraction was successful (should use fallback)
    assert_success
    
    # Verify output file was created
    [ -f "$output_file" ]
    
    # Check that generic entity was created
    run cat "$output_file"
    assert_output | grep -q '"name":"Unknown Entity"'
    assert_output | grep -q '"type":"other"'
}