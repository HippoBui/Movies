#!/bin/bash

# optimize_video_v2.sh
# Encodes video with HandBrake and extracts embedded subtitles via OCR (pgsrip/tesseract).
# Falls back to Whisper AI transcription if no subtitle tracks are found in the source.

# --- Configuration -----------------------------------------------------------
NOTIFY_SCRIPT="$(dirname "$0")/notify.sh"
HANDBRAKE_CLI="/opt/homebrew/bin/HandBrakeCLI"
FFMPEG="/opt/homebrew/bin/ffmpeg"
FFPROBE="/opt/homebrew/bin/ffprobe"
TESSERACT="/opt/homebrew/bin/tesseract"
TREATED_DIR="/Users/hippolytebuisson/Movies/Treated"
WHISPER_DIR="/Users/hippolytebuisson/Movies/scripts/whisper.cpp"

# --- Validate HandBrake ------------------------------------------------------
if [ ! -x "$HANDBRAKE_CLI" ]; then
    echo "Error: HandBrakeCLI not found at $HANDBRAKE_CLI"; exit 1
fi

# --- Args --------------------------------------------------------------------
if [ -z "$1" ]; then
    echo "Usage: $0 <input_file> [output_file_name]"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_NAME="$2"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."; exit 1
fi

BASENAME=$(basename "$INPUT_FILE")

if [ -z "$OUTPUT_NAME" ]; then
    OUTPUT_NAME="${BASENAME%.*}"
fi
if [[ "$OUTPUT_NAME" != *.mkv ]]; then
    OUTPUT_NAME="${OUTPUT_NAME}.mkv"
fi

OUTPUT_FILE="${TREATED_DIR}/${OUTPUT_NAME}"
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "================================================"
echo " Input:  $INPUT_FILE"
echo " Output: $OUTPUT_FILE"
echo "================================================"

notify() {
    if [ -x "$NOTIFY_SCRIPT" ]; then "$NOTIFY_SCRIPT" "$1"; fi
}

notify "*Starting Video Optimization*
*Input:* \`$BASENAME\`
*Output:* \`$OUTPUT_NAME\`
*Settings:* H.264 (Slow, RF 23) | AC3 640k | PGS->SRT subtitles"

START_TIME=$(date +%s)

# --- Stage 1: HandBrake encode -----------------------------------------------
echo ""
echo "[Stage 1] HandBrake encoding..."
"$HANDBRAKE_CLI" -i "$INPUT_FILE" -o "$OUTPUT_FILE" \
    -e x264 -q 23 --encoder-preset slow \
    -E ac3 -B 640 --all-audio

HBCODE=$?
END_TIME=$(date +%s)
DURATION_MIN=$(( (END_TIME - START_TIME) / 60 ))

if [ $HBCODE -ne 0 ]; then
    echo "Error: HandBrake failed (exit $HBCODE)."
    notify "*Optimization Failed* - \`$BASENAME\` - Exit: $HBCODE"
    exit $HBCODE
fi

echo "[Stage 1] Encoding done in ${DURATION_MIN} min."

# --- Helper: map 3-letter -> 2-letter lang codes -----------------------------
map_lang_codes() {
    local lang3="$1"
    case "$lang3" in
        "eng")       WHISPER_LANG="en"; TESS_LANG="eng" ;;
        "fre"|"fra") WHISPER_LANG="fr"; TESS_LANG="fra" ;;
        "spa")       WHISPER_LANG="es"; TESS_LANG="spa" ;;
        "ger"|"deu") WHISPER_LANG="de"; TESS_LANG="deu" ;;
        "ita")       WHISPER_LANG="it"; TESS_LANG="ita" ;;
        "por")       WHISPER_LANG="pt"; TESS_LANG="por" ;;
        "jpn")       WHISPER_LANG="ja"; TESS_LANG="jpn" ;;
        "chi"|"zho") WHISPER_LANG="zh"; TESS_LANG="chi_sim" ;;
        "rus")       WHISPER_LANG="ru"; TESS_LANG="rus" ;;
        "kor")       WHISPER_LANG="ko"; TESS_LANG="kor" ;;
        "dut"|"nld") WHISPER_LANG="nl"; TESS_LANG="nld" ;;
        *)           WHISPER_LANG="auto"; TESS_LANG="eng" ;;
    esac
}

# --- Stage 2: Subtitle extraction --------------------------------------------
echo ""
echo "[Stage 2] Scanning source for embedded subtitle tracks..."

SUBTITLE_STREAMS=$("$FFPROBE" -v error \
    -select_streams s \
    -show_entries stream=index,codec_name:stream_tags=language \
    -of csv=p=0 \
    "$INPUT_FILE" 2>/dev/null)

NUM_SUB_STREAMS=0
if [ -n "$SUBTITLE_STREAMS" ]; then
    NUM_SUB_STREAMS=$(echo "$SUBTITLE_STREAMS" | grep -c .)
fi

echo "  Found $NUM_SUB_STREAMS subtitle stream(s) in source."

# --- Option A: embedded subtitle tracks found -------------------------------
if [ "$NUM_SUB_STREAMS" -gt 0 ]; then
    echo "  Using embedded subtitle extraction..."
    SUB_IDX=0

    while IFS=',' read -r abs_idx codec lang; do
        lang=$(echo "$lang" | tr -d '\t\r\n ')
        map_lang_codes "$lang"

        if [ -z "$lang" ] || [ "$lang" = "und" ]; then
            LANG_TAG="track${SUB_IDX}"
        else
            LANG_TAG="$lang"
        fi

        SRT_OUT="${OUTPUT_FILE%.mkv}.${LANG_TAG}.srt"
        TEMP_BASE="/tmp/subsextract_$$_${SUB_IDX}"

        echo "  Stream $SUB_IDX | codec: $codec | lang: ${lang:-und}"

        # -- Text-based: direct conversion, zero loss --
        if [[ "$codec" == "subrip" || "$codec" == "ass" || "$codec" == "ssa" || "$codec" == "webvtt" ]]; then
            echo "    -> Text subtitle -- extracting directly..."
            "$FFMPEG" -i "$INPUT_FILE" \
                -map "0:s:${SUB_IDX}" -c:s srt \
                "$SRT_OUT" -y -loglevel warning \
                && echo "    [OK] $(basename "$SRT_OUT")"

        # -- Image-based: extract then OCR --
        elif [[ "$codec" == "dvd_subtitle" || "$codec" == "hdmv_pgs_subtitle" ]]; then
            echo "    -> Image subtitle ($codec) -- extracting for OCR..."

            if [[ "$codec" == "dvd_subtitle" ]]; then
                # VobSub: extract .sub/.idx pair via mkvextract, then OCR with vobsub2srt.py
                # Get the mkvmerge track ID (1-based) for this subtitle stream
                MKV_TRACK_ID=$(mkvmerge -i "$INPUT_FILE" 2>/dev/null | grep -i subtitle | awk 'NR=='"$((SUB_IDX+1))"'{print $3}' | tr -d ':')
                if [ -n "$MKV_TRACK_ID" ]; then
                    echo "    -> mkvextract track $MKV_TRACK_ID to VobSub..."
                    mkvextract "$INPUT_FILE" tracks "${MKV_TRACK_ID}:${TEMP_BASE}" 2>/dev/null
                    if [ -f "${TEMP_BASE}.idx" ] && [ -f "${TEMP_BASE}.sub" ]; then
                        echo "    -> Running vobsub2srt OCR (lang: $LANG_TAG)..."
                        python3 /Users/hippolytebuisson/Movies/scripts/vobsub2srt.py \
                            "${TEMP_BASE}.idx" "$LANG_TAG" "$SRT_OUT" \
                            && echo "    [OK] $(basename "$SRT_OUT")"
                    else
                        echo "    [WARN] mkvextract did not produce .sub/.idx files."
                    fi
                    rm -f "${TEMP_BASE}.sub" "${TEMP_BASE}.idx"
                else
                    echo "    [WARN] Could not determine mkvmerge track ID."
                fi

            elif [[ "$codec" == "hdmv_pgs_subtitle" ]]; then
                # PGS (Blu-ray): extract to temp MKV, then run pgsrip
                "$FFMPEG" -i "$INPUT_FILE" \
                    -map "0:s:${SUB_IDX}" -c:s copy \
                    "${TEMP_BASE}.mkv" -y -loglevel warning
                if [ -f "${TEMP_BASE}.mkv" ]; then
                    echo "    -> Running pgsrip OCR (lang: $LANG_TAG)..."
                    python3 -m pgsrip "${TEMP_BASE}.mkv" -l "${LANG_TAG/fre/fr}" -l "${LANG_TAG/eng/en}" \
                        -l "${LANG_TAG/spa/es}" -l "${LANG_TAG/por/pt}" \
                        && mv "${TEMP_BASE}"*.srt "$SRT_OUT" 2>/dev/null \
                        && echo "    [OK] $(basename "$SRT_OUT")"
                    rm -f "${TEMP_BASE}.mkv"
                fi
            fi

        else
            echo "    [WARN] Unknown codec '$codec' -- skipping."
        fi

        SUB_IDX=$((SUB_IDX + 1))
    done <<< "$SUBTITLE_STREAMS"

    echo "[Stage 2] Subtitle extraction complete."
    SUB_METHOD="Embedded subtitle OCR (pgsrip/tesseract)"

# --- Option B: no embedded subtitles -> Whisper fallback ----------------------
else
    echo "  No embedded subtitles found. Falling back to Whisper AI..."

    if [ ! -f "$WHISPER_DIR/models/ggml-small.bin" ]; then
        echo "  Downloading Whisper small model..."
        bash "$WHISPER_DIR/models/download-ggml-model.sh" small "$WHISPER_DIR/models"
    fi

    NUM_AUDIO=$("$FFPROBE" -v error -select_streams a \
        -show_entries stream=index -of csv=p=0 "$OUTPUT_FILE" | wc -l)
    NUM_AUDIO=$((NUM_AUDIO + 0))

    for (( i=0; i<NUM_AUDIO; i++ )); do
        LANG=$("$FFPROBE" -v error -select_streams a:$i \
            -show_entries stream_tags=language \
            -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE")
        map_lang_codes "$LANG"

        if [ -z "$LANG" ] || [ "$LANG" = "und" ]; then
            LANG_TAG="track${i}"
        else
            LANG_TAG="$LANG"
        fi

        WAV_FILE="${OUTPUT_FILE%.mkv}.${LANG_TAG}.wav"
        SRT_PREFIX="${OUTPUT_FILE%.mkv}.${LANG_TAG}"

        echo "  Whisper: audio track $i (lang: $WHISPER_LANG)..."
        "$FFMPEG" -i "$OUTPUT_FILE" \
            -map 0:a:$i -vn -ar 16000 -ac 1 -c:a pcm_s16le \
            "$WAV_FILE" -y -loglevel warning

        "$WHISPER_DIR/build/bin/whisper-cli" \
            -m "$WHISPER_DIR/models/ggml-small.bin" \
            -f "$WAV_FILE" -osrt -of "$SRT_PREFIX" \
            -l "$WHISPER_LANG" -mc 0 -sns

        rm -f "$WAV_FILE"
    done

    echo "[Stage 2] Whisper transcription complete."
    SUB_METHOD="Whisper AI transcription (no embedded subs found)"
fi

# --- Done --------------------------------------------------------------------
INPUT_SIZE=$(du -sh "$INPUT_FILE" | awk '{print $1}')
OUTPUT_SIZE=$(du -sh "$OUTPUT_FILE" | awk '{print $1}')
TOTAL_MIN=$(( ($(date +%s) - START_TIME) / 60 ))

notify "*Optimization Finished*
*Output:* \`$OUTPUT_NAME\`
*Size:* $INPUT_SIZE -> $OUTPUT_SIZE
*Time:* $TOTAL_MIN minutes
*Subtitles:* $SUB_METHOD"

echo ""
echo "================================================"
echo "Done!"
echo "   $INPUT_SIZE -> $OUTPUT_SIZE in ${TOTAL_MIN} min"
echo "   Subtitles: $SUB_METHOD"
echo "================================================"
