#!/bin/bash

# Configuration
RIP_SCRIPT="$(dirname "$0")/rip_disc.sh"
LOCK_FILE="/tmp/makemkv_autoloader.lock"

# Function to check if a disc is inserted
check_disc() {
    # Primary: MakeMKV's raw hardware access check
    local drv_line=$("/Applications/MakeMKV.app/Contents/MacOS/makemkvcon" -r info 2>/dev/null | grep "^DRV:0,")
    local device_path=$(echo "$drv_line" | awk -F'"' '{print $6}')
    
    if [ -n "$device_path" ]; then
        return 0 # Disc present
    fi

    # Fallback 1: check macOS diskutil for external optical media
    if diskutil list 2>/dev/null | grep -q "external, physical"; then
        return 0
    fi

    # Fallback 2: check drutil status
    if drutil status 2>/dev/null | grep -q "Space Used:"; then
        local space_used=$(drutil status 2>/dev/null | grep "Space Used:" | awk '{print $3}')
        if [ "$space_used" != "00:00:00" ] && [ -n "$space_used" ]; then
            return 0
        fi
    fi

    return 1 # No disc
}

echo "Starting MakeMKV autoloader monitor..."

while true; do
    if check_disc; then
        if [ ! -f "$LOCK_FILE" ]; then
            echo "Disc detected. Creating lock file and starting rip script."
            touch "$LOCK_FILE"
            
            # Adding a longer delay (20s) to allow the disc to fully mount/spin up before starting MakeMKV
            sleep 20
            
            if [ -x "$RIP_SCRIPT" ]; then
                "$RIP_SCRIPT"
            else
                echo "Rip script not found or not executable: $RIP_SCRIPT"
            fi
            
            # Wait for the drive to actually be empty before removing the lock.
            while check_disc; do
                sleep 5
            done
            
            echo "Drive is empty. Removing lock file."
            rm -f "$LOCK_FILE"
        fi
    else
        # No disc, ensure lock file is removed if it somehow got left behind
        if [ -f "$LOCK_FILE" ]; then
            rm -f "$LOCK_FILE"
        fi
    fi
    
    # Poll every 5 seconds
    sleep 5
done
