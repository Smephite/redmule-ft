#!/bin/bash

# Help message function
usage() {
    echo "Usage: $0 <filename_pattern>"
    echo "Example: $0 vulnerability_20250310_2159"
    exit 1
}

# Check if argument is provided
if [ $# -ne 1 ]; then
    echo "Error: Missing filename pattern."
    usage
fi

filename_pattern=$1
min_row_number=9999999999  # Initialize with a high value
min_file=""

# Process files with the given pattern
for i in {0..9}; do
    file="${filename_pattern}_${i}.csv"

    if [ -f "$file" ]; then
        last_line=$(tail -n1 "$file")
        row_number=$(echo "$last_line" | cut -d',' -f1)

        # Remove leading zeros
        row_number=$(echo $row_number | sed 's/^0*//')

        if [[ $row_number -lt $min_row_number ]]; then
            min_row_number=$row_number
            min_file=$file
        fi
    else
        echo "Warning: File $file not found, skipping..."
    fi
done

# Output result
echo "Minimum row number: $min_row_number in file $min_file"
