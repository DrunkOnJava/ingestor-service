#!/usr/bin/env python3
"""
Sample Python script for testing the ingestor system code processing functionality.
This file tests how the system handles code files and their specific formatting.
"""

import os
import sys
import json
from typing import Dict, List, Any, Optional


class DataProcessor:
    """A sample class that processes data files."""
    
    def __init__(self, input_dir: str, output_dir: str):
        """Initialize the data processor with input and output directories.
        
        Args:
            input_dir: Directory containing input files
            output_dir: Directory where processed files will be saved
        """
        self.input_dir = input_dir
        self.output_dir = output_dir
        self.processed_files = 0
    
    def process_file(self, filename: str) -> bool:
        """Process a single file.
        
        Args:
            filename: The name of the file to process
            
        Returns:
            bool: True if processing was successful, False otherwise
        """
        try:
            input_path = os.path.join(self.input_dir, filename)
            output_path = os.path.join(self.output_dir, f"processed_{filename}")
            
            # Read input file
            with open(input_path, 'r') as f:
                content = f.read()
            
            # Process content (simplified example)
            processed_content = content.upper()
            
            # Write output file
            with open(output_path, 'w') as f:
                f.write(processed_content)
            
            self.processed_files += 1
            return True
        except Exception as e:
            print(f"Error processing file {filename}: {e}")
            return False
    
    def process_all_files(self) -> Dict[str, Any]:
        """Process all files in the input directory.
        
        Returns:
            Dict: Statistics about the processing
        """
        success_count = 0
        failure_count = 0
        
        for filename in os.listdir(self.input_dir):
            if os.path.isfile(os.path.join(self.input_dir, filename)):
                if self.process_file(filename):
                    success_count += 1
                else:
                    failure_count += 1
        
        return {
            "processed_files": self.processed_files,
            "success_count": success_count,
            "failure_count": failure_count
        }


def main() -> int:
    """Main function to run the data processor.
    
    Returns:
        int: Exit code (0 for success, 1 for failure)
    """
    if len(sys.argv) != 3:
        print("Usage: python sample.py <input_dir> <output_dir>")
        return 1
    
    input_dir = sys.argv[1]
    output_dir = sys.argv[2]
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Initialize and run data processor
    processor = DataProcessor(input_dir, output_dir)
    stats = processor.process_all_files()
    
    # Print statistics
    print(json.dumps(stats, indent=2))
    
    # Return success if at least one file was processed
    return 0 if stats["success_count"] > 0 else 1


if __name__ == "__main__":
    sys.exit(main())