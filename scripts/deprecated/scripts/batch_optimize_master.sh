#!/bin/bash
RIPPED_BASE="/Users/hippolytebuisson/Movies/Ripped"
TREATED_BASE="/Users/hippolytebuisson/Movies/Treated"
SCRIPT="/Users/hippolytebuisson/Movies/scripts/optimize_video_v2.sh"

SHOWS=("The Pacific (2010)")

for SHOW in "${SHOWS[@]}"; do
    SHOW_RIPPED_DIR="$RIPPED_BASE/$SHOW"
    
    if [ ! -d "$SHOW_RIPPED_DIR" ]; then
        echo "Skipping $SHOW: Ripped directory not found."
        continue
    fi
    
    echo "=========================================="
    echo "Starting batch optimization for: $SHOW"
    echo "=========================================="
    
    # Loop through all mkv files in the show's ripped directory
    find "$SHOW_RIPPED_DIR" -type f -name "*.mkv" | sort | while read -r input_file; do
        # Calculate relative path
        rel_path="${input_file#$SHOW_RIPPED_DIR/}"
        # Calculate output name
        output_name="$SHOW/$rel_path"
        
        # Ensure directory exists in Treated
        target_dir="$TREATED_BASE/$SHOW/$(dirname "$rel_path")"
        mkdir -p "$target_dir"
        
        # Check if it already exists to avoid re-encoding if interrupted
        if [ -f "$TREATED_BASE/$output_name" ]; then
            echo "File $output_name already exists, skipping."
            continue
        fi
        
        echo "Starting optimization for $input_file"
        "$SCRIPT" "$input_file" "$output_name" < /dev/null
        
        echo "Cooling down for 1 minute before the next episode..."
        sleep 60
    done
done

echo "All shows completely processed!"
