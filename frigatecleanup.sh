#!/bin/bash

# Version 1.0.0

# Recordings directory to clean (this contains directories so is cleaned differently)
RECORDINGS_DIR="/volume1/frigate/recordings"
# Directories to clean (non-recursive files older than KEEP_DAYS)
CLEANUP_DIRS=(
    "/volume1/frigate/clips"
    "/volume1/frigate/clips/review"
    # Add more directories here as needed
)

# Number of newest days to keep (safety buffer)
KEEP_DAYS=11

# Log file
LOG_FILE="/volume1/frigate/frigate_cleanup.log"

# Timestamp for logging
NOW=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$NOW] Starting Frigate cleanup..." >> "$LOG_FILE"

### Recordings cleanup ###
if [ ! -d "$RECORDINGS_DIR" ]; then
    echo "[$NOW] ERROR: Recordings directory not found: $RECORDINGS_DIR" >> "$LOG_FILE"
    exit 1
fi

cd "$RECORDINGS_DIR" || exit 1

# List date folders (YYYY-MM-DD), sort oldest to newest, skip newest KEEP_DAYS
OLD_FOLDERS=$(ls -d 20[0-9][0-9]-* 2>/dev/null | sort | head -n -"$KEEP_DAYS")

if [ -z "$OLD_FOLDERS" ]; then
    echo "[$NOW] No old folders to delete." >> "$LOG_FILE"
else
    # Log folders to delete
    echo "[$NOW] Will delete the following recordings folders:" >> "$LOG_FILE"
    echo "$OLD_FOLDERS" >> "$LOG_FILE"

    # Delete old folders
    echo "$OLD_FOLDERS" | xargs rm -rf

    echo "[$NOW] Recordings cleanup complete." >> "$LOG_FILE"
fi

### Directory cleanup ###
for DIR in "${CLEANUP_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        echo "[$NOW] Cleaning up old files in $DIR..." >> "$LOG_FILE"
        find "$DIR" -maxdepth 1 -type f -mtime +$KEEP_DAYS -print -delete >> "$LOG_FILE" 2>&1
        echo "[$NOW] Cleanup complete for $DIR." >> "$LOG_FILE"
    else
        echo "[$NOW] Directory not found: $DIR" >> "$LOG_FILE"
    fi
done

### Rotate log: keep last 200 lines only ###
if [ -f "$LOG_FILE" ]; then
    tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

echo "[$NOW] Frigate cleanup finished." >> "$LOG_FILE"
