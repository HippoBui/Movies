#!/bin/bash
RIPPED_DIR="/Users/hippolytebuisson/Movies/Ripped/Seal Team"
TREATED_DIR="/Users/hippolytebuisson/Movies/Treated"
SCRIPT="/Users/hippolytebuisson/Movies/scripts/optimize_video.sh"

# Loop through all mkv files in the Seal Team ripped directory
find "$RIPPED_DIR" -type f -name "*.mkv" | sort | while read -r input_file; do
    # Calculate relative path (e.g. "Season 01/SEAL Team - S01E01.mkv")
    rel_path="${input_file#$RIPPED_DIR/}"
    # Calculate output name for optimize_video.sh (e.g. "Seal Team/Season 01/SEAL Team - S01E01.mkv")
    output_name="Seal Team/$rel_path"
    
    # Ensure directory exists in Treated
    target_dir="$TREATED_DIR/Seal Team/$(dirname "$rel_path")"
    mkdir -p "$target_dir"
    
    # Run the optimization (it will skip if we don't want to overwrite, but optimize_video overwrites by default)
    # Actually wait, we should check if it already exists to avoid re-encoding if interrupted.
    if [ -f "$TREATED_DIR/$output_name" ]; then
        # If it has a reasonable size, maybe it's done? Or maybe just rely on the script.
        echo "File $output_name already exists, skipping."
        continue
    fi
    
    echo "Starting optimization for $input_file"
    "$SCRIPT" "$input_file" "$output_name" < /dev/null
    
    echo "Cooling down for 10 minutes before the next episode..."
    sleep 600
done
