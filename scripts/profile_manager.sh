#!/bin/bash
# Ingestor System - Performance Profile Manager
# 
# Utility script to manage profiling settings and generate benchmarks
# for the ingestor-system components

set -eo pipefail

# Base paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INGESTOR_HOME="${HOME}/.ingestor"
PROFILING_LOG_DIR="${INGESTOR_HOME}/logs/profiling"
BENCHMARK_DIR="${INGESTOR_HOME}/benchmarks"

# Import required modules
source "${PROJECT_ROOT}/src/modules/profiler.sh"

# Create necessary directories
mkdir -p "$PROFILING_LOG_DIR" "$BENCHMARK_DIR"

# Display help information
show_help() {
    cat << EOF
Ingestor System - Performance Profile Manager

Usage: profile_manager.sh [COMMAND] [OPTIONS]

Commands:
  enable            Enable performance profiling
  disable           Disable performance profiling
  benchmark [TYPE]  Run benchmarks for different operations
  analyze [FILE]    Analyze profiling logs and generate report
  clean [AGE]       Clean old profiling logs (default: 30 days)
  help              Show this help message

Benchmark Types:
  all               Run all benchmarks (default)
  database          Run database benchmarks
  content           Run content processing benchmarks
  claude            Run Claude AI benchmarks
  custom FILE       Run custom benchmark script

Options:
  --output, -o PATH  Specify output file for reports
  --verbose, -v      Enable verbose output
  --format, -f TYPE  Report format (markdown, json, csv)

Examples:
  profile_manager.sh enable              # Enable profiling
  profile_manager.sh benchmark database  # Run database benchmarks
  profile_manager.sh analyze             # Analyze most recent profiling log
  profile_manager.sh clean 7             # Clean logs older than 7 days

For more information, see: README.md
EOF
}

# Enable profiling
enable_profiling() {
    # Create a configuration file to enable profiling
    cat > "${INGESTOR_HOME}/profiling_enabled" << EOF
# Profiling enabled on $(date)
# To disable, run: profile_manager.sh disable
PROFILING_ENABLED=true
EOF

    echo "Performance profiling enabled."
    echo "All ingestor operations will now be profiled."
    echo "To disable profiling, run: profile_manager.sh disable"
}

# Disable profiling
disable_profiling() {
    # Remove the configuration file
    if [[ -f "${INGESTOR_HOME}/profiling_enabled" ]]; then
        rm "${INGESTOR_HOME}/profiling_enabled"
    fi
    
    echo "Performance profiling disabled."
}

# Run benchmarks
run_benchmarks() {
    local benchmark_type="${1:-all}"
    local output_file="${BENCHMARK_DIR}/benchmark_results_$(date +%Y%m%d_%H%M%S).md"
    
    echo "Running $benchmark_type benchmarks..."
    
    # Enable profiling for benchmarks
    init_profiler true
    
    case "$benchmark_type" in
        all)
            run_database_benchmarks
            run_content_benchmarks
            run_claude_benchmarks
            ;;
        database)
            run_database_benchmarks
            ;;
        content)
            run_content_benchmarks
            ;;
        claude)
            run_claude_benchmarks
            ;;
        custom)
            if [[ -n "$2" && -f "$2" ]]; then
                echo "Running custom benchmark script: $2"
                source "$2"
            else
                echo "Error: Custom benchmark script not specified or not found."
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown benchmark type: $benchmark_type"
            show_help
            exit 1
            ;;
    esac
    
    # Generate benchmark report
    local report_file=$(generate_profiling_report "$output_file")
    
    # Save benchmarks
    save_benchmarks
    
    echo "Benchmarks completed."
    echo "Results saved to: $report_file"
}

# Run database benchmarks
run_database_benchmarks() {
    echo "Setting up database benchmarks..."
    
    # Create a test database
    local test_db_dir="${BENCHMARK_DIR}/test_db"
    mkdir -p "$test_db_dir"
    
    # Create a simple SQLite database
    local test_db="${test_db_dir}/benchmark.sqlite"
    
    # Create schema file
    local schema_file="${test_db_dir}/schema.sql"
    cat > "$schema_file" << EOF
CREATE TABLE IF NOT EXISTS benchmark_data (
    id INTEGER PRIMARY KEY,
    content TEXT,
    metadata TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS benchmark_index (
    id INTEGER PRIMARY KEY,
    data_id INTEGER,
    key TEXT,
    value TEXT,
    FOREIGN KEY (data_id) REFERENCES benchmark_data(id)
);

CREATE INDEX IF NOT EXISTS idx_benchmark_index_key ON benchmark_index(key);
EOF

    # Source necessary modules for database operations
    source "${PROJECT_ROOT}/src/modules/logging.sh"
    source "${PROJECT_ROOT}/src/modules/database.sh"
    source "${PROJECT_ROOT}/src/modules/database_profiled.sh"
    
    # Initialize the database
    echo "Creating test database..."
    profile_function "db_init_benchmark" init_database "$test_db" "$schema_file" true
    
    # Benchmark database inserts
    echo "Benchmarking database inserts..."
    for i in {1..100}; do
        local content="This is test content for benchmark record $i. It contains enough text to simulate a small document."
        local metadata="{\"benchmark\": true, \"iteration\": $i, \"type\": \"test\"}"
        
        # Prepare query
        local query="INSERT INTO benchmark_data (content, metadata) VALUES ('$content', '$metadata')"
        profile_function "db_insert_benchmark" safe_db_query "$test_db" "$query"
        
        # Add some index entries
        local data_id=$i
        for j in {1..5}; do
            local key="key_$j"
            local value="value_${i}_$j"
            local index_query="INSERT INTO benchmark_index (data_id, key, value) VALUES ($data_id, '$key', '$value')"
            profile_function "db_index_benchmark" safe_db_query "$test_db" "$index_query"
        done
    done
    
    # Benchmark database queries
    echo "Benchmarking database queries..."
    
    # Simple query
    profile_function "db_query_simple_benchmark" safe_db_query "$test_db" "SELECT * FROM benchmark_data LIMIT 10"
    
    # Complex query with joins
    local complex_query="SELECT d.id, d.content, i.key, i.value 
                        FROM benchmark_data d 
                        JOIN benchmark_index i ON d.id = i.data_id 
                        WHERE i.key = 'key_3' 
                        ORDER BY d.id DESC 
                        LIMIT 20"
    profile_function "db_query_complex_benchmark" safe_db_query "$test_db" "$complex_query"
    
    # Benchmark database vacuum
    echo "Benchmarking database vacuum..."
    profile_function "db_vacuum_benchmark" safe_db_query "$test_db" "VACUUM"
    
    # Benchmark database backup
    echo "Benchmarking database backup..."
    profile_function "db_backup_benchmark" sqlite3 "$test_db" ".backup '${test_db_dir}/backup.sqlite'"
    
    echo "Database benchmarks completed."
}

# Run content processing benchmarks
run_content_benchmarks() {
    echo "Setting up content processing benchmarks..."
    
    # Create test files directory
    local test_files_dir="${BENCHMARK_DIR}/test_files"
    mkdir -p "$test_files_dir"
    
    # Source necessary modules
    source "${PROJECT_ROOT}/src/modules/logging.sh"
    source "${PROJECT_ROOT}/src/modules/content.sh"
    source "${PROJECT_ROOT}/src/modules/content_profiled.sh"
    
    # Create test files
    echo "Creating test files..."
    
    # Text file
    local text_file="${test_files_dir}/benchmark_text.txt"
    cat > "$text_file" << EOF
This is a simple text file for benchmarking content processing.
It contains multiple lines of plain text.
This will be used to measure the performance of text processing functions.

The file has multiple paragraphs to test paragraph chunking.

This paragraph is separated by blank lines from others.
Content detection should properly identify this as a text file.

The performance of content processing is measured in milliseconds.
We want to optimize the most frequently used and slowest operations.
EOF

    # JSON file
    local json_file="${test_files_dir}/benchmark_data.json"
    cat > "$json_file" << EOF
{
  "benchmark": true,
  "type": "test",
  "data": [
    {
      "id": 1,
      "name": "Test Item 1",
      "value": 42
    },
    {
      "id": 2,
      "name": "Test Item 2",
      "value": 84
    },
    {
      "id": 3,
      "name": "Test Item 3",
      "value": 126
    }
  ],
  "metadata": {
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "1.0"
  }
}
EOF
    
    # Python file
    local python_file="${test_files_dir}/benchmark_script.py"
    cat > "$python_file" << EOF
#!/usr/bin/env python3
"""
Benchmark test file for content processing.
This is a simple Python script used to test code content detection.
"""

import os
import sys
import json

def main():
    """Main function for the benchmark script."""
    print("Running benchmark script")
    
    data = {
        "status": "success",
        "message": "This is a benchmark test"
    }
    
    print(json.dumps(data, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF
    
    # Benchmark content detection
    echo "Benchmarking content detection..."
    profile_function "content_detect_text_benchmark" detect_content_type "$text_file"
    profile_function "content_detect_json_benchmark" detect_content_type "$json_file"
    profile_function "content_detect_python_benchmark" detect_content_type "$python_file"
    
    # Benchmark text chunking
    echo "Benchmarking content chunking..."
    
    # Generate larger text for chunking test
    local large_text_file="${test_files_dir}/benchmark_large_text.txt"
    for i in {1..50}; do
        cat "$text_file" >> "$large_text_file"
    done
    
    # Test different chunking strategies
    profile_function "content_chunk_size_benchmark" chunk_text_file "$large_text_file" 1000 100 "size"
    profile_function "content_chunk_paragraph_benchmark" chunk_text_file "$large_text_file" 1000 100 "paragraph"
    
    echo "Content processing benchmarks completed."
}

# Run Claude AI benchmarks
run_claude_benchmarks() {
    echo "Setting up Claude AI benchmarks..."
    
    # Create mock Claude functions for benchmarking if needed
    if ! command -v analyze_with_claude &> /dev/null; then
        # Create mock function
        analyze_with_claude() {
            local content_path="$1"
            local content_type="$2"
            
            # Simulate API delay
            sleep 0.5
            
            # Return mock response
            echo '{"analysis": "This is a mock analysis for benchmarking", "confidence": 0.95}'
        }
    fi
    
    # Source necessary modules
    source "${PROJECT_ROOT}/src/modules/logging.sh"
    if [[ -f "${PROJECT_ROOT}/src/modules/claude.sh" ]]; then
        source "${PROJECT_ROOT}/src/modules/claude.sh"
    fi
    source "${PROJECT_ROOT}/src/modules/claude_profiled.sh"
    
    # Test files for Claude
    local test_files_dir="${BENCHMARK_DIR}/test_files"
    mkdir -p "$test_files_dir"
    
    # Short text for analysis
    local short_text="${test_files_dir}/claude_short.txt"
    cat > "$short_text" << EOF
This is a short text sample for Claude AI analysis. It should be processed quickly 
as it contains only a few sentences about a general topic. The purpose of this text
is to measure the baseline performance of Claude API calls.
EOF
    
    # Medium text for analysis
    local medium_text="${test_files_dir}/claude_medium.txt"
    cat > "$medium_text" << EOF
This medium-length text sample contains more detailed information for Claude AI analysis.
It discusses various topics including technology, science, and philosophy.

Technology continues to advance at a rapid pace, with artificial intelligence leading
the way. Claude, as an AI assistant, represents the culmination of years of research
and development in natural language processing and machine learning.

Science helps us understand the world through empirical observation and experimentation.
From physics to biology, scientific disciplines provide frameworks for examining reality.

Philosophy asks fundamental questions about existence, knowledge, ethics, and logic.
It encourages critical thinking and challenges assumptions about the nature of reality.

This text should be processed with moderate speed as it contains several paragraphs
on different topics, requiring more contextual understanding and processing power.
EOF
    
    # Benchmark Claude analysis
    echo "Benchmarking Claude AI analysis..."
    profile_function "claude_analyze_short_benchmark" analyze_with_claude "$short_text" "text"
    profile_function "claude_analyze_medium_benchmark" analyze_with_claude "$medium_text" "text"
    
    # Benchmark embeddings (if available)
    if type generate_embeddings &>/dev/null; then
        echo "Benchmarking Claude AI embeddings..."
        profile_function "claude_embeddings_benchmark" generate_embeddings "This is a short text for embedding generation"
    fi
    
    # Benchmark summarization (if available)
    if type claude_summarize &>/dev/null; then
        echo "Benchmarking Claude AI summarization..."
        profile_function "claude_summarize_benchmark" claude_summarize "$(cat "$medium_text")"
    fi
    
    echo "Claude AI benchmarks completed."
}

# Analyze profiling logs
analyze_logs() {
    local log_file="$1"
    local output_format="${2:-markdown}"
    local output_file="${3:-}"
    
    # If no log file specified, use the most recent
    if [[ -z "$log_file" ]]; then
        log_file=$(find "$PROFILING_LOG_DIR" -name "profiling_*.log" -type f | sort -r | head -n 1)
        if [[ -z "$log_file" ]]; then
            echo "Error: No profiling logs found in $PROFILING_LOG_DIR"
            exit 1
        fi
    fi
    
    echo "Analyzing profiling log: $log_file"
    
    # If no output file specified, create one
    if [[ -z "$output_file" ]]; then
        output_file="${PROFILING_LOG_DIR}/analysis_$(date +%Y%m%d_%H%M%S).${output_format}"
    fi
    
    # Load the data from the log file
    local line_count=$(wc -l < "$log_file")
    echo "Log contains $line_count lines."
    
    # Skip header line
    tail -n +2 "$log_file" > "${PROFILING_LOG_DIR}/temp_analysis.csv"
    
    # Process based on output format
    case "$output_format" in
        markdown)
            generate_markdown_report "${PROFILING_LOG_DIR}/temp_analysis.csv" "$output_file"
            ;;
        json)
            generate_json_report "${PROFILING_LOG_DIR}/temp_analysis.csv" "$output_file"
            ;;
        csv)
            # Just copy the processed CSV
            cp "${PROFILING_LOG_DIR}/temp_analysis.csv" "$output_file"
            ;;
        *)
            echo "Error: Unknown output format: $output_format"
            exit 1
            ;;
    esac
    
    # Clean up
    rm "${PROFILING_LOG_DIR}/temp_analysis.csv"
    
    echo "Analysis completed and saved to: $output_file"
}

# Generate Markdown report
generate_markdown_report() {
    local csv_file="$1"
    local output_file="$2"
    
    # Start the Markdown report
    cat > "$output_file" << EOF
# Ingestor System Performance Analysis
**Generated:** $(date)

## Summary of Operations
EOF
    
    # Process CSV data
    awk -F, '
    BEGIN {
        # Initialize variables
        operations_count = 0
    }
    
    {
        # Parse fields
        operation = $1
        duration = $2
        
        # Track operations and durations
        if (!seen[operation]) {
            operations[operations_count] = operation
            operations_count++
            seen[operation] = 1
            min_duration[operation] = duration
            max_duration[operation] = duration
        }
        
        # Update statistics
        count[operation]++
        total_duration[operation] += duration
        if (duration < min_duration[operation]) min_duration[operation] = duration
        if (duration > max_duration[operation]) max_duration[operation] = duration
    }
    
    END {
        # Generate Markdown table header
        print("| Operation | Count | Avg Duration (ms) | Min | Max |")
        print("|-----------|------:|------------------:|----:|----:|")
        
        # Generate rows
        for (i = 0; i < operations_count; i++) {
            op = operations[i]
            avg = total_duration[op] / count[op]
            printf("| %s | %d | %.2f | %d | %d |\n", 
                   op, count[op], avg, min_duration[op], max_duration[op])
        }
        
        # Add detailed sections
        print("\n## Operation Details\n")
        for (i = 0; i < operations_count; i++) {
            op = operations[i]
            print("### " op)
            print("- **Count:** " count[op] " executions")
            print("- **Average Duration:** " total_duration[op] / count[op] " ms")
            print("- **Total Duration:** " total_duration[op] " ms")
            print("- **Range:** " min_duration[op] " - " max_duration[op] " ms")
            print("")
        }
        
        # Add recommendations
        print("## Optimization Opportunities\n")
        print("Operations with highest average execution time:")
        
        # Sort operations by average time (crude implementation)
        for (i = 0; i < operations_count; i++) {
            sorted_ops[i] = operations[i]
            sorted_avg[sorted_ops[i]] = total_duration[operations[i]] / count[operations[i]]
        }
        
        # Crude bubble sort
        for (i = 0; i < operations_count; i++) {
            for (j = i + 1; j < operations_count; j++) {
                if (sorted_avg[sorted_ops[i]] < sorted_avg[sorted_ops[j]]) {
                    temp = sorted_ops[i]
                    sorted_ops[i] = sorted_ops[j]
                    sorted_ops[j] = temp
                }
            }
        }
        
        # List top 5 operations by average time
        for (i = 0; i < 5 && i < operations_count; i++) {
            op = sorted_ops[i]
            avg = sorted_avg[op]
            print("1. **" op "**: " avg " ms average (" count[op] " executions)")
        }
    }
    ' "$csv_file" >> "$output_file"
}

# Generate JSON report
generate_json_report() {
    local csv_file="$1"
    local output_file="$2"
    
    # Process CSV data to JSON
    awk -F, '
    BEGIN {
        print("{")
        print("  \"generated\": \"" strftime("%Y-%m-%d %H:%M:%S") "\",")
        print("  \"operations\": [")
        first_operation = 1
    }
    
    {
        # Parse fields
        operation = $1
        duration = $2
        
        # Track operations and durations
        if (!seen[operation]) {
            if (!first_operation) {
                print("    },")
            } else {
                first_operation = 0
            }
            
            seen[operation] = 1
            min_duration[operation] = duration
            max_duration[operation] = duration
            print("    {")
            print("      \"name\": \"" operation "\",")
            print("      \"statistics\": {")
            
            # Start total and count
            count[operation] = 1
            total_duration[operation] = duration
        } else {
            # Update statistics
            count[operation]++
            total_duration[operation] += duration
        }
        
        # Update min/max
        if (duration < min_duration[operation]) min_duration[operation] = duration
        if (duration > max_duration[operation]) max_duration[operation] = duration
    }
    
    END {
        # Generate final JSON
        for (operation in seen) {
            if (!output_done[operation]) {
                avg = total_duration[operation] / count[operation]
                print("        \"count\": " count[operation] ",")
                print("        \"total_duration_ms\": " total_duration[operation] ",")
                print("        \"average_duration_ms\": " avg ",")
                print("        \"min_duration_ms\": " min_duration[operation] ",")
                print("        \"max_duration_ms\": " max_duration[operation])
                print("      }") # close statistics
                
                output_done[operation] = 1
            }
        }
        
        print("    }") # close last operation
        print("  ]") # close operations array
        print("}") # close main object
    }
    ' "$csv_file" > "$output_file"
}

# Clean old profiling logs
clean_logs() {
    local age="${1:-30}"  # Default to 30 days
    
    echo "Cleaning profiling logs older than $age days..."
    
    # Find and delete old logs
    local count=$(find "$PROFILING_LOG_DIR" -name "profiling_*.log" -type f -mtime "+$age" | wc -l)
    if [[ $count -gt 0 ]]; then
        find "$PROFILING_LOG_DIR" -name "profiling_*.log" -type f -mtime "+$age" -delete
        echo "Deleted $count old profiling logs."
    else
        echo "No old logs found to clean."
    fi
    
    # Find and delete old reports
    local report_count=$(find "$PROFILING_LOG_DIR" -name "profiling_report_*.md" -type f -mtime "+$age" | wc -l)
    if [[ $report_count -gt 0 ]]; then
        find "$PROFILING_LOG_DIR" -name "profiling_report_*.md" -type f -mtime "+$age" -delete
        echo "Deleted $report_count old profiling reports."
    else
        echo "No old reports found to clean."
    fi
}

# Main function
main() {
    local command="$1"
    shift
    
    case "$command" in
        enable)
            enable_profiling
            ;;
        disable)
            disable_profiling
            ;;
        benchmark)
            run_benchmarks "$@"
            ;;
        analyze)
            analyze_logs "$@"
            ;;
        clean)
            clean_logs "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Error: Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    main "$@"
fi