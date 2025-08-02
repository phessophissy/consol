#!/bin/bash

# Check if file argument is provided
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <coverage-report-file>"
    exit 1
fi

input_file="$1"

# Check if file exists
if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found"
    exit 1
fi

# Create a temporary file for output
temp_file=$(mktemp)

# Extract only the table portion and convert to markdown
awk '
BEGIN {
    in_table = 0
}

# Start of table (╭ character)
/^╭/ { 
    in_table = 1
    next
}

# End of table (╰ character) 
/^╰/ { 
    in_table = 0
    exit
}

# Skip the separator line with + and = characters
/^\+[=]+\+$/ { next }

# Skip separator lines with dashes between | (including long dash lines)
/^\|[-]+/ { next }

# Process actual table content rows (lines starting with | and containing data)
in_table && /^\|/ && !/^\|[-]+/ {
    # Clean up the line - remove leading/trailing spaces and pipes
    gsub(/^\| */, "")
    gsub(/ *\|$/, "")
    
    # Replace internal separators with markdown format
    gsub(/ *\| */, " | ")
    
    # Print the row with surrounding |
    print "| " $0 " |"
    
    # Add separator line after header row (first data row)
    if (!header_printed) {
        # Count the number of columns (header has 5 columns)
        print "|---|---|---|---|---|"
        header_printed = 1
    }
}
' "$input_file" > "$temp_file"

# Replace the original file with the processed content
mv "$temp_file" "$input_file"

echo "Coverage report converted to markdown table in $input_file" 