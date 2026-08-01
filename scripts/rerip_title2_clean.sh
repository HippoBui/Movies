#!/bin/bash
NOTIFY_SCRIPT="/Users/hippolytebuisson/Movies/scripts/notify.sh"

notify() {
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" "$1"
    else
        echo "$1"
    fi
}

# Find device path dynamically
DRV_LINE=$("/Applications/MakeMKV.app/Contents/MacOS/makemkvcon" -r info 2>/dev/null | grep "^DRV:0,")
dev=$(echo "$DRV_LINE" | awk -F'"' '{print $6}')
if [ -z "$dev" ]; then
    dev="/dev/rdisk4"
fi

DEST_DIR="/Users/hippolytebuisson/Movies/Ripped/BILLIONS_SEASON_5_DISC_4"
TARGET_FILE="${DEST_DIR}/B2_t02.mkv"

notify "💿 *Starting clean rerip of Title 2 (Billions S5D4)...*"

if [ -f "$TARGET_FILE" ]; then
    rm -f "$TARGET_FILE"
fi

# Run MakeMKV
caffeinate -dims /Applications/MakeMKV.app/Contents/MacOS/makemkvcon -r --progress=-same mkv disc:0 2 "$DEST_DIR"
RIP_STATUS=$?

if [ $RIP_STATUS -eq 0 ] && [ -f "$TARGET_FILE" ]; then
    notify "✅ *Rerip of Title 2 Completed successfully.* Ejecting..."
else
    notify "❌ *Rerip of Title 2 Failed.* Exit code: $RIP_STATUS"
fi

# Eject
diskutil unmountDisk force "$dev" 2>/dev/null
diskutil eject "$dev" || drutil eject

# Start autoloader back up
notify "🔄 *Starting autoloader back up...*"
nohup bash /Users/hippolytebuisson/Movies/scripts/autoloader.sh > /Users/hippolytebuisson/Movies/scripts/autoloader.log 2>&1 &
