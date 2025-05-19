#!/bin/bash

# Output file name
OUTPUT_FILE="project_code_summary.txt"

# Get the name of this script
SCRIPT_NAME=$(basename "$0")

# Reset output file
> "$OUTPUT_FILE"

# Counter for numbered output
counter=1

# Collect unignored files (tracked + untracked but not ignored)
FILES=$(git ls-files --cached --others --exclude-standard)

# Loop through all eligible files
while IFS= read -r file; do
  # Skip directories, the script itself, and non-readable files
  if [[ -f "$file" && -r "$file" && $(basename "$file") != "$SCRIPT_NAME" ]]; then
    echo "$counter. $file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n\n" >> "$OUTPUT_FILE"
    ((counter++))
  fi
done <<< "$FILES"

echo "✅ Code summary saved to: $OUTPUT_FILE"
