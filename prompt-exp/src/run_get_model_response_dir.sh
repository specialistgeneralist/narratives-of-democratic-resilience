#!/bin/bash
# find .json files in input dir, run get_model_response.py on each

# Usage: ./run_get_model_response_dir.sh <input_dir>
# Example: ./run_get_model_response_dir.sh ../data/llm_prompting_direct/input

# Check if the input directory is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <input_dir>"
  exit 1
fi

# run get_model_response.py on each .json file in the input directory
for file in "$1"/*.json; do
  # Check if the file exists
  if [ -f "$file" ]; then
    # Get the base name of the file (without the directory)
    base_name=$(basename "$file")
    # Run get_model_response.py on the file
    echo "Processing $base_name..."
    python3 get_model_responses.py "$file"
  else
    echo "No .json files found in $1"
  fi
done
