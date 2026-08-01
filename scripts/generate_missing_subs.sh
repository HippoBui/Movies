#!/bin/bash
WHISPER_DIR="/Users/hippolytebuisson/Movies/scripts/whisper.cpp"
TREATED_DIR="/Users/hippolytebuisson/Movies/Treated/Yellowstone (2018)/Season 01"

for OUTPUT_FILE in "$TREATED_DIR"/*.mkv; do
    echo "Processing missing subs for $OUTPUT_FILE"
    NUM_AUDIO_STREAMS=$(/opt/homebrew/bin/ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUTPUT_FILE" | wc -l)
    NUM_AUDIO_STREAMS=$((NUM_AUDIO_STREAMS + 0))
    
    for (( i=0; i<$NUM_AUDIO_STREAMS; i++ )); do
        LANG=$(/opt/homebrew/bin/ffprobe -v error -select_streams a:$i -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE")
        if [ -z "$LANG" ] || [ "$LANG" = "und" ]; then
            LANG_SUFFIX="track${i}"
        else
            LANG_SUFFIX="$LANG"
        fi
        
        WAV_FILE="${OUTPUT_FILE%.mkv}_${LANG_SUFFIX}.wav"
        SRT_PREFIX="${OUTPUT_FILE%.mkv}_${LANG_SUFFIX}"
        
        # Only generate if the SRT doesn't already exist
        if [ ! -f "${SRT_PREFIX}.srt" ]; then
            echo "Extracting audio track $i..."
            /opt/homebrew/bin/ffmpeg -i "$OUTPUT_FILE" -map 0:a:$i -vn -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -y -loglevel warning
            echo "Running whisper..."
            "$WHISPER_DIR/build/bin/whisper-cli" -m "$WHISPER_DIR/models/ggml-base.bin" -f "$WAV_FILE" -osrt -of "$SRT_PREFIX" -l auto > /dev/null 2>&1
            rm -f "$WAV_FILE"
        fi
    done
done
