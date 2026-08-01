#!/bin/bash
RIPPED_BASE="/Users/hippolytebuisson/Movies/Ripped/Billions (2016)"
TREATED_BASE="/Users/hippolytebuisson/Movies/Treated"
SCRIPT="/Users/hippolytebuisson/Movies/scripts/optimize_video_v2.sh"
LOG="/Users/hippolytebuisson/Movies/scripts/optimize_billions_s4-7.log"

touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

SHOW="Billions (2016)"

echo "=========================================="
echo "Starting batch optimization: $(date)"
echo "Seasons 4-7 | $SCRIPT"
echo "=========================================="

for season in 04 05 06 07; do
    season_dir="$RIPPED_BASE/Season $season"
    echo ""
    echo "=== Season $season ==="
    
    for ep in $(seq -w 1 12); do
        input_file="$season_dir/$SHOW - S${season}E${ep}.mkv"
        
        if [ ! -f "$input_file" ]; then
            echo "S${season}E${ep}: input not found, skipping"
            continue
        fi
        
        output_name="$SHOW/$SHOW - S${season}E${ep}.mkv"
        target_dir="$TREATED_BASE/$SHOW"
        mkdir -p "$target_dir"
        
        if [ -f "$TREATED_BASE/$output_name" ]; then
            echo "S${season}E${ep}: already exists, skipping"
            continue
        fi
        
        echo ""
        echo "--- Starting S${season}E${ep}: $(date) ---"
        "$SCRIPT" "$input_file" "$output_name" < /dev/null
        EXIT=$?
        if [ $EXIT -eq 0 ]; then
            echo "--- Finished S${season}E${ep}: $(date) ---"
        else
            echo "--- FAILED S${season}E${ep} (exit $EXIT): $(date) ---"
        fi
        
        echo "Cooling down for 1 minute before the next episode..."
        sleep 60
    done
done

echo ""
echo "=========================================="
echo "All done: $(date)"
echo "=========================================="