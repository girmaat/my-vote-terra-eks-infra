#!/bin/bash

# Script and output file config
OUTPUT_FILE="project_code_summary.txt"
SCRIPT_NAME=$(basename "$0")

# Reset output file
> "$OUTPUT_FILE"

# Initialize file counter
counter=1

# Find all regular files (not dirs or symlinks)
find . -type f ! -path "./$SCRIPT_NAME" ! -path "./$OUTPUT_FILE" | while read -r file; do
  # Skip files ignored by git
  if git check-ignore -q "$file"; then
    continue
  fi

  # Skip binary files (optional)
  if grep -qIl . "$file"; then
    echo "$counter. ${file#./}" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n\n" >> "$OUTPUT_FILE"
    ((counter++))
  fi
done

echo "✅ Project summary written to: $OUTPUT_FILE"
