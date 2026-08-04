#!/bin/bash
# ============================================================================
# RESTRUCTURE BREAKING BAD — cp-only, zero deletions, zero overwrites
# Maps disc MKV rips → Jellyfin season folders
#
# NEVER REPLACE THIS PATTERN WITHOUT EXPLICITLY CHECKING:
#   - All mv / cp commands are null-delimited (spaces safe)
#   - Renumbering always uses a temp prefix stage
#   - Source files are removed *only after verification* (or left for user review)
# ============================================================================
set -e
TARGET="/Users/hippolytebuisson/Movies/Ripped/Breaking Bad (2008)"
SRC="/Users/hippolytebuisson/Movies/Ripped"

# ---------------------------------------------------------------------------
# Season definitions: source disc folders in episode order
# ---------------------------------------------------------------------------
declare -a S01_DISCS=("Breaking_Bad_Season_1_Disc_1" "Breaking_Bad_Season_1_Disc_2" "Breaking_Bad_Season_1_Disc_3")
declare -a S02_DISCS=("Breaking_Bad_Season_2_Disc_1" "Breaking_Bad_Season_2_Disc_2" "Breaking_Bad_Season_2_Disc_3" "Breaking_Bad_Season_2_Disc_4")
declare -a S03_DISCS=("BREAKING_BAD_S3_D1" "BREAKING_BAD_S3_D2" "BREAKING_BAD_S3_D3" "BREAKING_BAD_S3_D4")
declare -a S04_DISCS=("Breaking_Bad_Season_4_Disc_1" "Breaking_Bad_Season_4_Disc_2" "Breaking_Bad_Season_4_Disc_3" "Breaking_Bad_Season_4_Disc_4")
declare -a S05_DISCS=("Breaking_Bad_Season_5_Disc_1" "Breaking_Bad_Season_5_Disc_2" "Breaking_Bad_Season_5_Disc_3" "Breaking_Bad_Final_Season_Disc_1" "Breaking_Bad_Final_Season_Disc_2" "Breaking_Bad_Final_Season_Disc_3")

# ---------------------------------------------------------------------------
# Helper: copy disc files sequentially into a season folder
# ---------------------------------------------------------------------------
process_season() {
    local SEASON_NUM="$1"
    local SHOW_NAME="Breaking Bad (2008)"
    shift
    local -a DISCS=("$@")
    local TARGET_DIR="$TARGET/Season $(printf '%02d' $SEASON_NUM)"
    mkdir -p "$TARGET_DIR"

    if [ "${#DISCS[@]}" -eq 0 ]; then
        echo "  No source discs found; you probably need to re-rip them"
        return 0
    fi

    echo "[S${SEASON_NUM}] source discs: $#"

    # Phase 1: copy all files with temp names, build file list with durations
    local -a ALL_FILES=()
    for disc in "${DISCS[@]}"; do
        local d="$SRC/$disc"
        ! [ -d "$d" ] && echo "  WARNING: no source folder $d" && continue
        while IFS= read -r -d '' mkv; do
            local dur_s dur_m
            if dur_s=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mkv" 2>/dev/null) && [ -n "$dur_s" ]; then
                dur_m=$(echo "$dur_s" | awk '{printf "%.0f", $1/60}')
            else
                dur_m="??"
            fi
            echo "  $disc :: $(basename "$mkv")  (${dur_m}m)" >&2
            ALL_FILES+=("$mkv|$disc|${dur_m}")
        done < <(find "$d" -maxdepth 1 -name "*.mkv" -print0 | sort -z)
    done

    echo "  [READ] ${#ALL_FILES[@]} files" >&2

    # Phase 2: detect features (anomalous durations)
    local -a REAL_EPISODES
    local -a FEATURETTES
    # All BB episodes are 43–58 min. Anything < 40 min is a featurette
    for entry in "${ALL_FILES[@]}"; do
        local dur_m="${entry##*|}"
        local path="${entry%%|*}"
        if [ "$dur_m" != "??" ] && [ "$dur_m" -lt 40 ]; then
            FEATURETTES+=("$entry")
        else
            REAL_EPISODES+=("$entry")
        fi
    done

    echo "  Real episodes: ${#REAL_EPISODES[@]}  Featurettes: ${#FEATURETTES[@]}" >&2

    # Phase 3: copy real episodes with clean numbering
    local EP=0
    for entry in "${REAL_EPISODES[@]}"; do
        EP=$((EP+1))
        local src_path="${entry%|*}"
        local dest="$TARGET_DIR/$SHOW_NAME - S${SEASON_NUM}E$(printf '%02d' $EP).mkv"
        if [ -f "$dest" ]; then
            echo "  SKIP (exists): $dest" >&2
            continue
        fi
        "$RSYNC_BIN" "$src_path" "$dest" || cp "$src_path" "$dest"
        echo "  OK: S${SEASON_NUM}E$(printf '%02d' $EP) (<- $(basename "$src_path"))" >&2
    done

    # Phase 4: copy featurettes with descriptive names
    for entry in "${FEATURETTES[@]}"; do
        local src_path="${entry%|*}"
        local dur="${entry##*|}"
        local base=$(basename "$src_path")
        local dest="$TARGET_DIR/$SHOW_NAME - Featurette-${base%.mkv}.mkv"
        if [ -f "$dest" ]; then
            echo "  SKIP: $dest" >&2
            continue
        fi
        "$RSYNC_BIN" "$src_path" "$dest" || cp "$src_path" "$dest"
        echo "  Featurette: $(basename "$src_path")" >&2
    done

    echo "  => $SEASON_NUM: $EP real episodes, ${#FEATURETTES[@]} featurettes" >&2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

RSYNC_BIN=$(command -v rsync || echo "")

for season in "01" "02" "03" "04" "05" "06" "07"; do

    process_season "$season" "${DISK_GROUP[@]}"
done