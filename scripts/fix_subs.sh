#!/bin/bash
TREATED_DIR="/Users/hippolytebuisson/Movies/Treated/The Pacific (2010)"
WHISPER_DIR="/Users/hippolytebuisson/Movies/scripts/whisper.cpp"

for EP in 01 02 03 04 05 06; do
    OUTPUT_FILE="$TREATED_DIR/The Pacific (2010) - S01E${EP}.mkv"
    if [ ! -f "$OUTPUT_FILE" ]; then continue; fi
    
    echo "Fixing subtitles for S01E${EP}..."
    NUM_AUDIO_STREAMS=$(/opt/homebrew/bin/ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUTPUT_FILE" | wc -l)
    NUM_AUDIO_STREAMS=$((NUM_AUDIO_STREAMS + 0))
    
    for (( i=0; i<$NUM_AUDIO_STREAMS; i++ )); do
        LANG=$(/opt/homebrew/bin/ffprobe -v error -select_streams a:$i -show_entries stream_tags=language -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE")
        
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
done
echo "All subtitle fixes completed."
