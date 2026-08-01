#!/bin/bash
OPT_SCRIPT="/Users/hippolytebuisson/Movies/scripts/optimize_video_v2.sh"
RIPPED="/Users/hippolytebuisson/Movies/Ripped/Billions (2016)"
LOG="/Users/hippolytebuisson/Movies/scripts/optimize_batch.log"

touch "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo "================================================"
echo "Starting batch optimization: $(date)"
echo "================================================"

for season in 01 02 03; do
  season_dir="${RIPPED}/Season ${season}"
  echo ""
  echo "=== Processing Season ${season} ==="
  
  for ep in $(seq -w 1 12); do
    input="${season_dir}/Billions (2016) - S${season}E${ep}.mkv"
    output_name="Billions (2016)/Billions (2016) - S${season}E${ep}.mkv"
    
    if [ ! -f "$input" ]; then
      echo "S${season}E${ep}: input not found, skipping"
      continue
    fi
    
    # Check if already done
    output="/Users/hippolytebuisson/Movies/Treated/${output_name}"
    if [ -f "$output" ]; then
      echo "S${season}E${ep}: already exists, skipping"
      continue
    fi
    
    echo ""
    echo "--- Starting S${season}E${ep}: $(date) ---"
    bash "$OPT_SCRIPT" "$input" "$output_name"
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
      echo "--- Finished S${season}E${ep}: $(date) ---"
    else
      echo "--- FAILED S${season}E${ep} (exit $EXIT): $(date) ---"
    fi
  done
done

echo ""
echo "================================================"
echo "Batch optimization complete: $(date)"
echo "================================================"