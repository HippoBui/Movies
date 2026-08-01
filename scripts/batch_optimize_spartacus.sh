#!/bin/bash
RIPPED_DIR="/Users/hippolytebuisson/Movies/Ripped/Spartacus (2010)"
TREATED_DIR="/Users/hippolytebuisson/Movies/Treated"
SCRIPT="/Users/hippolytebuisson/Movies/scripts/optimize_video.sh"

# Loop through all mkv files in the Spartacus ripped directory
find "$RIPPED_DIR" -type f -name "*.mkv" | sort | while read -r input_file; do
    # Calculate relative path
    rel_path="${input_file#$RIPPED_DIR/}"
    # Calculate output name
    output_name="Spartacus (2010)/$rel_path"
    
    # Ensure directory exists in Treated
    target_dir="$TREATED_DIR/Spartacus (2010)/$(dirname "$rel_path")"
    mkdir -p "$target_dir"
    
    # Check if it already exists to avoid re-encoding if interrupted
    if [ -f "$TREATED_DIR/$output_name" ]; then
        echo "File $output_name already exists, skipping."
        continue
    fi
    
    echo "Starting optimization for $input_file"
    "$SCRIPT" "$input_file" "$output_name" < /dev/null
    
    echo "Cooling down for 10 minutes before the next episode..."
    sleep 600
done
