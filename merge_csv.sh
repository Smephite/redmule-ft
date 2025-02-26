#!/bin/bash

# Usage: ./merge_csv.sh "<file_pattern>"
# Example: ./merge_csv.sh "vulnerability_20250226_*"
# If no pattern is provided, it will merge all available CSVs.

# Ensure the user provides a quoted pattern
if [[ $# -ne 1 ]]; then
    echo "Error: Please provide exactly one file pattern in double quotes."
    echo "Usage: $0 \"vulnerability_20250226_*\""
    exit 1
fi

# Get the user-defined file pattern
file_pattern=$1

# Find all matching CSV files
csv_files=($(ls $file_pattern 2>/dev/null))

# Check if any CSV files exist
if [ ${#csv_files[@]} -eq 0 ]; then
    echo "No CSV files found matching the pattern '$file_pattern'!"
    exit 1
fi

# Extract the common filename prefix (remove wildcards and trailing parts)
common_part=$(echo "$file_pattern" | sed -E 's/[*?].*//')

# Define the output file using the common filename part and timestamp
output_file="${common_part}.csv"

echo "Merging ${#csv_files[@]} CSV files into $output_file..."

# Extract header from the first CSV file
head -n 1 "${csv_files[0]}" > "$output_file"

# Concatenate all CSV files excluding the header, then sort by first column (seed)
tail -n +2 -q "${csv_files[@]}" | sort -t, -k1,1n >> "$output_file"

echo "Merge complete: $output_file"
