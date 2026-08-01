#!/bin/bash
LOCK_FILE="/tmp/makemkv_autoloader.lock"
NOTIFY_SCRIPT="/Users/hippolytebuisson/Movies/scripts/notify.sh"

notify() {
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" "$1"
    else
        echo "$1"
    fi
}

echo "Acquiring autoloader lock to pause it..."
touch "$LOCK_FILE"

notify "⏳ *Rerip Title 2 queued.* Please insert Billions Season 5 Disc 4. I've paused the autoloader."

# Wait for disc
echo "Waiting for disc insertion..."
while true; do
    drv_line=$("/Applications/MakeMKV.app/Contents/MacOS/makemkvcon" -r info 2>/dev/null | grep "^DRV:0,")
    dev=$(echo "$drv_line" | awk -F'"' '{print $6}')
    disc_name=$(echo "$drv_line" | awk -F'"' '{print $4}')
    disc_name=$(echo "$disc_name" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    if [ -n "$dev" ] && [ "$disc_name" = "BILLIONS_SEASON_5_DISC_4" ]; then
        break
    fi
    sleep 3
done

notify "💿 *Disc detected:* \`$disc_name\` (\`$dev\`). Starting extraction of Title 2..."

DEST_DIR="/Users/hippolytebuisson/Movies/Ripped/$disc_name"
TARGET_FILE="${DEST_DIR}/B2_t02.mkv"

if [ -f "$TARGET_FILE" ]; then
    echo "Removing old corrupted file: $TARGET_FILE"
    rm -f "$TARGET_FILE"
fi

# Run MakeMKV for title 2
echo "Ripping Title 2..."
caffeinate -dims /Applications/MakeMKV.app/Contents/MacOS/makemkvcon -r --progress=-same mkv disc:0 2 "$DEST_DIR"

if [ $? -eq 0 ] && [ -f "$TARGET_FILE" ]; then
    notify "✅ *Rerip of Title 2 Completed successfully.* Ejecting disc..."
else
    notify "❌ *Rerip of Title 2 Failed.* Check logs."
fi

# Eject
diskutil unmountDisk force "$dev" 2>/dev/null
diskutil eject "$dev" || drutil eject

# Wait for drive to be empty
echo "Waiting for disc removal..."
while true; do
    drv_line=$("/Applications/MakeMKV.app/Contents/MacOS/makemkvcon" -r info 2>/dev/null | grep "^DRV:0,")
    dev=$(echo "$drv_line" | awk -F'"' '{print $6}')
    if [ -z "$dev" ]; then
        break
    fi
    sleep 3
done

echo "Releasing autoloader lock..."
rm -f "$LOCK_FILE"
notify "🔄 *Autoloader resumed.* Ready for the next disc."
