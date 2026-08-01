#!/bin/bash

# Configuration
NOTIFY_SCRIPT="$(dirname "$0")/notify.sh"
HANDBRAKE_CLI="HandBrakeCLI"
TREATED_DIR="/Users/hippolytebuisson/Movies/Treated"

# Ensure Handbrake is installed
if ! command -v "$HANDBRAKE_CLI" &> /dev/null; then
    # Sometimes homebrew bins aren't in PATH for cron/background scripts, try absolute path fallback
    if [ -x "/opt/homebrew/bin/HandBrakeCLI" ]; then
        HANDBRAKE_CLI="/opt/homebrew/bin/HandBrakeCLI"
    else
        echo "Error: HandBrakeCLI is not installed or not in PATH."
        echo "Please install it with: brew install handbrake"
        exit 1
    fi
fi

if [ -z "$1" ]; then
    echo "Usage: $0 <input_file> [output_file_name]"
    echo "Example: $0 \"../Ripped/Movie/title_t00.mkv\" \"My Movie (2024)\""
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_NAME="$2"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."
    exit 1
fi

BASENAME=$(basename "$INPUT_FILE")
BASENAME_NO_EXT="${BASENAME%.*}"

if [ -z "$OUTPUT_NAME" ]; then
    OUTPUT_NAME="$BASENAME_NO_EXT"
fi

# Ensure output has .mkv extension
if [[ "$OUTPUT_NAME" != *.mkv ]]; then
    OUTPUT_NAME="${OUTPUT_NAME}.mkv"
fi

OUTPUT_FILE="${TREATED_DIR}/${OUTPUT_NAME}"

# Ensure Treated directory exists
mkdir -p "$TREATED_DIR"

echo "Starting optimization for: $INPUT_FILE"
echo "Output will be saved to: $OUTPUT_FILE"

if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "🎬 *Starting Video Optimization*
*Input:* \`$BASENAME\`
*Output:* \`$OUTPUT_NAME\`
*Settings:* H.264 (Slow, RF 23) with Audio Passthrough & Whisper SRT"
fi

START_TIME=$(date +%s)

# Handbrake parameters:
# -e x264 : Video codec H.264 (AVC)
# -q 23 : Constant Quality RF 23 (More aggressive compression, massive space saving)
# --encoder-preset slow : Slow preset for maximum compression efficiency
# -E ac3 -B 640 : Compress all audio to Dolby Digital AC3 at 640kbps
# --all-audio : Select all audio tracks
# --all-subtitles : Select all subtitle tracks

"$HANDBRAKE_CLI" -i "$INPUT_FILE" -o "$OUTPUT_FILE" \
    -e x264 -q 23 --encoder-preset slow \
    -E ac3 -B 640 --all-audio

EXIT_CODE=$?
END_TIME=$(date +%s)
DURATION_MIN=$(( (END_TIME - START_TIME) / 60 ))

if [ $EXIT_CODE -eq 0 ]; then
    echo "Optimization completed successfully."
    
    echo "Extracting audio and generating text subtitles via Whisper for all tracks..."
    WHISPER_DIR="/Users/hippolytebuisson/Movies/scripts/whisper.cpp"
    
    # Ensure multi-lingual model is downloaded
    if [ ! -f "$WHISPER_DIR/models/ggml-small.bin" ]; then
        echo "Downloading multi-lingual Whisper model..."
        bash "$WHISPER_DIR/models/download-ggml-model.sh" small "$WHISPER_DIR/models"
    fi

    # Determine number of audio streams
    NUM_AUDIO_STREAMS=$(/opt/homebrew/bin/ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUTPUT_FILE" | wc -l)
    NUM_AUDIO_STREAMS=$((NUM_AUDIO_STREAMS + 0)) # sanitize
    
    for (( i=0; i<$NUM_AUDIO_STREAMS; i++ )); do
        LANG=$(/opt/homebrew/bin/ffprobe -v error -select_streams a:$i -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE")
        
        # Map 3-letter MKV language codes to Whisper 2-letter codes
        case "$LANG" in
            "eng") WHISPER_LANG="en" ;;
            "fre"|"fra") WHISPER_LANG="fr" ;;
            "spa") WHISPER_LANG="es" ;;
            "ger"|"deu") WHISPER_LANG="de" ;;
            "ita") WHISPER_LANG="it" ;;
            "jpn") WHISPER_LANG="ja" ;;
            "chi"|"zho") WHISPER_LANG="zh" ;;
            "por") WHISPER_LANG="pt" ;;
            "rus") WHISPER_LANG="ru" ;;
            "kor") WHISPER_LANG="ko" ;;
            "und"|"") WHISPER_LANG="auto" ;;
            *) WHISPER_LANG="auto" ;;
        esac

        if [ -z "$LANG" ] || [ "$LANG" = "und" ]; then
            LANG_SUFFIX="track${i}"
        else
            LANG_SUFFIX="$LANG"
        fi
        
        WAV_FILE="${OUTPUT_FILE%.mkv}.${LANG_SUFFIX}.wav"
        SRT_PREFIX="${OUTPUT_FILE%.mkv}.${LANG_SUFFIX}"
        
        echo "Processing audio track $i (Language: $WHISPER_LANG)..."
        /opt/homebrew/bin/ffmpeg -i "$OUTPUT_FILE" -map 0:a:$i -vn -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -y -loglevel warning
        
        "$WHISPER_DIR/build/bin/whisper-cli" -m "$WHISPER_DIR/models/ggml-small.bin" -f "$WAV_FILE" -osrt -of "$SRT_PREFIX" -l "$WHISPER_LANG" -mc 0 -sns
        
        rm -f "$WAV_FILE"
    done
    echo "Subtitles generated successfully!"

    INPUT_SIZE=$(du -sh "$INPUT_FILE" | awk '{print $1}')
    OUTPUT_SIZE=$(du -sh "$OUTPUT_FILE" | awk '{print $1}')
    
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" "✅ *Optimization Finished*
*Output:* \`$OUTPUT_NAME\`
*Original Size:* $INPUT_SIZE
*New Size:* $OUTPUT_SIZE
*Time Taken:* $DURATION_MIN minutes
*Subtitles:* Whisper SRT Generated!

*Original file kept.* You can manually delete it from the Ripped folder if everything looks good."
    fi
else
    echo "Error: Optimization failed with exit code $EXIT_CODE."
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" "⚠️ *Optimization Failed*
*Input:* \`$BASENAME\`
*Exit Code:* $EXIT_CODE"
    fi
    exit $EXIT_CODE
fi
