#!/bin/bash
OPT_SCRIPT="/Users/hippolytebuisson/Movies/scripts/optimize_video_v2.sh"
RIPPED="/Users/hippolytebuisson/Movies/Ripped/Billions (2016)"
LOG="/Users/hippolytebuisson/Movies/scripts/optimize_batch.log"

echo "" >> "$LOG"
echo "================================================" >> "$LOG"
echo "Starting Season 3 optimization: $(date)" >> "$LOG"
echo "================================================" >> "$LOG"

for ep in $(seq -w 1 12); do
  input="${RIPPED}/Season 03/Billions (2016) - S03E${ep}.mkv"
  output_name="Billions (2016)/Billions (2016) - S03E${ep}.mkv"
  
  if [ ! -f "$input" ]; then
    echo "S03E${ep}: input not found, skipping" >> "$LOG"
    continue
  fi
  
  output="/Users/hippolytebuisson/Movies/Treated/${output_name}"
  if [ -f "$output" ]; then
    echo "S03E${ep}: already exists, skipping" >> "$LOG"
    continue
  fi
  
  echo "" >> "$LOG"
  echo "--- Starting S03E${ep}: $(date) ---" >> "$LOG"
  bash "$OPT_SCRIPT" "$input" "$output_name" >> "$LOG" 2>&1
  EXIT=$?
  if [ $EXIT -eq 0 ]; then
    echo "--- Finished S03E${ep}: $(date) ---" >> "$LOG"
  else
    echo "--- FAILED S03E${ep} (exit $EXIT): $(date) ---" >> "$LOG"
  fi
done

echo "" >> "$LOG"
echo "================================================" >> "$LOG"
echo "Season 3 optimization complete: $(date)" >> "$LOG"
echo "================================================" >> "$LOG"
