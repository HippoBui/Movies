#!/bin/bash

# Configuration
NOTIFY_SCRIPT="$(dirname "$0")/notify.sh"
MAKEMKVCON="/Applications/MakeMKV.app/Contents/MacOS/makemkvcon"
DDRESCUE="/opt/homebrew/bin/ddrescue"
BASE_DIR="/Users/hippolytebuisson/Movies/Ripped"
MIN_DURATION_SECS=120  # Skip titles shorter than 2 minutes (trailers, menus)

# Ensure base directory exists
mkdir -p "$BASE_DIR"

# Concurrency lock to prevent multiple instances from fighting over the drive
LOCK_DIR="/tmp/rip_disc.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another rip is already in progress. Exiting."
    exit 1
fi
# Ensure the lock is released when the script finishes or is killed
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# Function to send notification
notify() {
    local message="$1"
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" "$message"
    else
        echo "Notify script not found or not executable: $NOTIFY_SCRIPT"
    fi
}

######################################################################
# SMART TITLE SELECTION — Skip "Play All" composites and short extras
######################################################################
SELECTED_TITLES=""

select_titles() {
    echo "Pre-scanning disc for smart title selection..."
    
    local INFO_OUTPUT
    INFO_OUTPUT=$("$MAKEMKVCON" -r info disc:0 2>/dev/null)
    
    # Parse title durations from TINFO attribute 9 (format: "H:MM:SS")
    local -a tids=()
    local -a durations=()
    
    while IFS= read -r line; do
        local tid=$(echo "$line" | cut -d':' -f2 | cut -d',' -f1)
        local duration_str=$(echo "$line" | sed 's/.*,"//' | sed 's/".*//')
        local h=${duration_str%%:*}
        local rest=${duration_str#*:}
        local m=${rest%%:*}
        local s=${rest#*:}
        local total=$(( 10#$h * 3600 + 10#$m * 60 + 10#$s ))
        tids+=("$tid")
        durations+=("$total")
    done < <(echo "$INFO_OUTPUT" | grep '^TINFO:[0-9]*,9,')
    
    local count=${#tids[@]}
    if [ "$count" -eq 0 ]; then
        echo "No titles found during pre-scan. Falling back to rip all."
        SELECTED_TITLES="all"
        return
    fi
    
    # Step 1: Filter by minimum duration
    local -a kept_ids=()
    local -a kept_durs=()
    for (( i=0; i<count; i++ )); do
        if [ "${durations[$i]}" -ge "$MIN_DURATION_SECS" ]; then
            kept_ids+=("${tids[$i]}")
            kept_durs+=("${durations[$i]}")
            echo "  Title ${tids[$i]}: $(( durations[$i] / 60 ))m $(( durations[$i] % 60 ))s ✓"
        else
            echo "  Title ${tids[$i]}: $(( durations[$i] / 60 ))m $(( durations[$i] % 60 ))s ✗ (under ${MIN_DURATION_SECS}s, skipping)"
        fi
    done
    
    local kept_count=${#kept_ids[@]}
    if [ "$kept_count" -le 1 ]; then
        SELECTED_TITLES="${kept_ids[*]:-all}"
        echo "Selected titles: $SELECTED_TITLES"
        return
    fi
    
    # Step 2: Detect "Play All" composite title
    # The "Play All" title's duration ≈ sum of all individual episode durations
    local max_dur=0
    local max_idx=0
    for (( i=0; i<kept_count; i++ )); do
        if [ "${kept_durs[$i]}" -gt "$max_dur" ]; then
            max_dur="${kept_durs[$i]}"
            max_idx=$i
        fi
    done
    
    # Sum all other titles' durations
    local sum_others=0
    for (( i=0; i<kept_count; i++ )); do
        if [ "$i" -ne "$max_idx" ]; then
            sum_others=$(( sum_others + ${kept_durs[$i]} ))
        fi
    done
    
    # If longest title is within 20% of the sum of others, it's a "Play All"
    # Only apply when there are 3+ titles (need at least 2 real + 1 composite)
    if [ "$kept_count" -gt 2 ] && [ "$sum_others" -gt 0 ]; then
        local lower=$(( sum_others * 80 / 100 ))
        local upper=$(( sum_others * 120 / 100 ))
        if [ "$max_dur" -ge "$lower" ] && [ "$max_dur" -le "$upper" ]; then
            echo "  → Detected 'Play All' composite: Title ${kept_ids[$max_idx]} ($(( max_dur / 60 ))m ≈ sum of others $(( sum_others / 60 ))m). Skipping!"
            unset 'kept_ids[$max_idx]'
            kept_ids=("${kept_ids[@]}")
        fi
    fi
    
    SELECTED_TITLES="${kept_ids[*]}"
    echo "Selected titles: $SELECTED_TITLES"
}

echo "Starting Hybrid Ripping Pipeline..."

# Step 1: Detect Disc Name & Device Path using basic enumeration (bypasses hang)
DRV_LINE=$("$MAKEMKVCON" -r info 2>/dev/null | grep "^DRV:0,")
DISC_NAME=$(echo "$DRV_LINE" | awk -F'"' '{print $4}')
DEVICE_PATH=$(echo "$DRV_LINE" | awk -F'"' '{print $6}')

# Fallback to diskutil if MakeMKV fails/expires
if [ -z "$DEVICE_PATH" ]; then
    RAW_DISK=$(diskutil list 2>/dev/null | grep "external, physical" | awk '{print $1}' | head -n 1)
    if [ -n "$RAW_DISK" ]; then
        DEVICE_PATH="/dev/r${RAW_DISK#/dev/}"
    fi
fi

if [ -z "$DISC_NAME" ] && [ -n "$RAW_DISK" ]; then
    DISC_NAME=$(diskutil info "$RAW_DISK" 2>/dev/null | grep "Volume Name:" | awk -F':' '{print $2}' | xargs)
fi

# Fallback if name is empty
if [ -z "$DISC_NAME" ]; then
    DISC_NAME="Unknown_Disc_$(date +%s)"
fi

# Sanitize disc name (replace spaces with underscores, remove special characters)
DISC_NAME=$(echo "$DISC_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')

DEST_DIR="${BASE_DIR}/${DISC_NAME}"
mkdir -p "$DEST_DIR"

# Clean up logs older than 14 days in the Base Dir
find "$BASE_DIR" -name "ddrescue_*.log" -type f -mtime +14 -delete 2>/dev/null
find "$BASE_DIR" -name "makemkv_rip_*.log" -type f -mtime +14 -delete 2>/dev/null

if [ -z "$DEVICE_PATH" ]; then
    notify "❌ *Failed to detect device path.* MakeMKV couldn't find /dev/rdiskX."
    drutil eject
    exit 1
fi

######################################################################
# STAGE 1: MakeMKV Primary Pass
######################################################################
run_makemkv() {
    local LOG_FILE="${DEST_DIR}/makemkv_rip_$(date +%Y%m%d_%H%M%S).log"
    local START_TIME=$(date +%s)
    
    # Smart title selection (sets SELECTED_TITLES global variable)
    select_titles 2>&1 | tee -a "$LOG_FILE"
    # Re-run to set the variable (tee runs in a subshell)
    select_titles > /dev/null 2>&1
    
    notify "💿 *Optical disc detected.*
*Disc Name:* \`${DISC_NAME}\`
*Device:* \`${DEVICE_PATH}\`
*Titles to rip:* \`${SELECTED_TITLES}\`
Starting MakeMKV extraction (Plan A)..."

    # Rip each selected title (or all if pre-scan failed)
    local MAKEMKV_FAILED=0
    for tid in $SELECTED_TITLES; do
        echo "Ripping title $tid..." | tee -a "$LOG_FILE"
        caffeinate -dims script -q /dev/null "$MAKEMKVCON" -r --progress=-same mkv disc:0 "$tid" "$DEST_DIR" | tee -a "$LOG_FILE" | (
            while IFS= read -r line; do
                line="${line//$'\r'/}"
                if [[ "$line" == *"MEDIUM ERROR"* ]]; then
                    notify "⚠️ *Medium Error Detected.* MakeMKV hit a physical scratch.
*Disc:* \`${DISC_NAME}\`
Instantly aborting MakeMKV to trigger ddrescue..."
                    pkill -9 makemkvcon
                    break
                fi
            done
        )
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            MAKEMKV_FAILED=1
            break
        fi
    done

    local END_TIME=$(date +%s)
    local DURATION_MIN=$(( (END_TIME - START_TIME) / 60 ))
    local FOLDER_SIZE=$(du -sh "$DEST_DIR" 2>/dev/null | awk '{print $1}')
    
    # Check if titles were actually saved
    local SAVED_INFO=$(grep -i "titles saved" "$LOG_FILE" | tail -n 1)

    if [ $MAKEMKV_FAILED -eq 0 ] && [ -n "$SAVED_INFO" ] && ! echo "$SAVED_INFO" | grep -q "failed"; then
        notify "✅ *MakeMKV Rip Completed.*
*Disc Name:* \`${DISC_NAME}\`
*Time Taken:* ${DURATION_MIN} minutes
*Total Size:* ${FOLDER_SIZE}
*Status:* ${SAVED_INFO}

The disc has been ejected. Ready for the next one."
        return 0
    else
        # MakeMKV failed or no titles saved
        return 1
    fi
}

get_live_device_path() {
    local drv_line=$("$MAKEMKVCON" -r info 2>/dev/null | grep "^DRV:0,")
    local dev=$(echo "$drv_line" | awk -F'"' '{print $6}')
    if [ -n "$dev" ] && [ -c "$dev" ]; then
        echo "$dev"
        return
    fi
    local raw_disk=$(diskutil list 2>/dev/null | grep "external, physical" | awk '{print $1}' | head -n 1)
    if [ -n "$raw_disk" ]; then
        echo "/dev/r${raw_disk#/dev/}"
        return
    fi
    echo "$DEVICE_PATH"
}

######################################################################
# STAGE 2: ddrescue Emergency Fallback
######################################################################
run_ddrescue() {
    DEVICE_PATH=$(get_live_device_path)
    if [ ! -c "$DEVICE_PATH" ]; then
        echo "Error: Device node $DEVICE_PATH does not exist or disc is ejected."
        return 1
    fi

    local LOG_FILE="${DEST_DIR}/ddrescue_$(date +%Y%m%d_%H%M%S).log"
    local MAP_FILE="${DEST_DIR}/${DISC_NAME}.map"
    local ISO_FILE="${DEST_DIR}/${DISC_NAME}.iso"
    local START_TIME=$(date +%s)

    notify "⚠️ *MakeMKV Rip Failed.*
*Disc Name:* \`${DISC_NAME}\`
Disc is likely physically damaged or MakeMKV key expired.
*Falling back to ddrescue ISO extraction (Plan B)...*"

    # Unmount before ddrescue to avoid Permission Denied on raw device
    diskutil unmountDisk force "$DEVICE_PATH" 2>/dev/null

    local DD_FLAGS="-n -b 2048 -T 5m"
    if [ -f "$MAP_FILE" ]; then
        DD_FLAGS="$DD_FLAGS -R"
        echo "Map file found. Resuming ddrescue in REVERSE mode..."
    else
        echo "Starting fresh ddrescue in FORWARD mode..."
    fi

    # Execute ddrescue
    caffeinate -dims "$DDRESCUE" $DD_FLAGS "$DEVICE_PATH" "$ISO_FILE" "$MAP_FILE" 2>&1 | tr '\r' '\n' | tee "$LOG_FILE" > /dev/null

    local EXIT_CODE=${PIPESTATUS[0]}
    local END_TIME=$(date +%s)
    local DURATION_MIN=$(( (END_TIME - START_TIME) / 60 ))
    local FILE_SIZE=$(du -sh "$ISO_FILE" 2>/dev/null | awk '{print $1}')

    if [ $EXIT_CODE -eq 0 ]; then
        notify "✅ *ddrescue ISO Rip Completed.*
*Disc Name:* \`${DISC_NAME}\`
*Time Taken:* ${DURATION_MIN} minutes
*ISO Size:* ${FILE_SIZE}

The disc has been ejected. Ready for the next one."
    else
        notify "⚠️ *ddrescue Finished With Errors.*
*Disc Name:* \`${DISC_NAME}\`
*Time Taken:* ${DURATION_MIN} minutes
*ISO Size:* ${FILE_SIZE}

*(ddrescue hit unreadable sectors and skipped them. You can use the .map file to scrape later.)*

Ejecting disc."
    fi
}

######################################################################
# PIPELINE EXECUTION
######################################################################

MAP_FILE="${DEST_DIR}/${DISC_NAME}.map"
if [ -f "$MAP_FILE" ]; then
    echo "Map file found. Skipping MakeMKV and jumping directly to ddrescue."
    run_ddrescue
else
    if ! run_makemkv; then
        run_ddrescue
    fi
fi

# Eject using device path to ensure raw LibreDrives eject properly
diskutil unmountDisk force "$DEVICE_PATH" 2>/dev/null
diskutil eject "$DEVICE_PATH" || drutil eject
