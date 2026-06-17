#!/bin/bash

# ----------------------------------
# Frigate Cleanup Script
# ----------------------------------

set -o errexit
set -o nounset
set -o pipefail

# -------- CONFIG --------

FRIGATE_DATA_DIR="/synology/frigate"
CONFIGURATION_FILE="/root/frigate/config/config.yml"
LOG_FILE="$FRIGATE_DATA_DIR/frigate_cleanup.log"

EXCLUDED_DIRS=("cache" "faces" "review" "triggers" "export")

# -------- MODE --------

DRY_RUN=true
if [[ "${1:-}" == "-delete" || "${1:-}" == "--delete" ]]; then
    DRY_RUN=false
fi

# -------- START --------

clear

RECORDINGS_DIR="$FRIGATE_DATA_DIR/recordings"
CLIPS_BASE="$FRIGATE_DATA_DIR/clips"

CAMERA_PARENT_DIRS=(
    "$CLIPS_BASE/previews"
    "$CLIPS_BASE/thumbs"
    "$CLIPS_BASE/review"
    "$CLIPS_BASE/triggers"
)

MODE_STR=$( [ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "LIVE DELETE" )
NOW=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$NOW] $1" >> "$LOG_FILE"
}

echo "------------------------------------------"
echo "Frigate Cleanup Script"
echo "ℹ️ Mode: $MODE_STR"
echo "------------------------------------------"

# ----------------------------------
# SAFETY VALIDATION
# ----------------------------------

if [[ "$CLIPS_BASE" == "/" || "$RECORDINGS_DIR" == "/" ]]; then
    echo "❌ FATAL: Refusing to operate on root filesystem"
    exit 1
fi

if [[ ! -d "$CLIPS_BASE" || ! -d "$RECORDINGS_DIR" ]]; then
    echo "❌ ERROR: Invalid data directories"
    exit 1
fi

if [[ ! -f "$CONFIGURATION_FILE" ]]; then
    echo "❌ ERROR: Config not found: $CONFIGURATION_FILE"
    exit 1
fi

log "Starting cleanup ($MODE_STR)"

# ----------------------------------
# READ CONFIG
# ----------------------------------

mapfile -t CAMERAS < <(yq -r '.cameras | keys | .[]' "$CONFIGURATION_FILE")

# -------- Retention --------

KEEP_DAYS=0
while IFS= read -r days; do
    if [[ "$days" =~ ^[0-9]+$ ]] && (( days > KEEP_DAYS )); then
        KEEP_DAYS=$days
    fi
done < <(yq -r '
.. 
| select(type == "object") 
| (
  .retain.days? //
  .continuous.days? //
  .motion.days?
) // empty
' "$CONFIGURATION_FILE")

[[ "$KEEP_DAYS" -eq 0 ]] && KEEP_DAYS=10
FIND_DAYS=$((KEEP_DAYS + 1))

# -------- CONFIG DISPLAY --------

echo ""
echo "Configuration:"
echo "📹 Cameras configured : ${#CAMERAS[@]}"
echo "  Cameras:"
for cam in "${CAMERAS[@]}"; do
    echo "    - $cam"
done

echo ""
echo "🔁 Retention : $KEEP_DAYS days (effective=$FIND_DAYS)"

# ----------------------------------
# HELPERS
# ----------------------------------

normalize() {
    echo "$1" | tr -d '\r' | xargs
}

is_camera_prefix() {
    local prefix=$(normalize "$1")
    for cam in "${CAMERAS[@]}"; do
        [[ "$(normalize "$cam")" == "$prefix" ]] && return 0
    done
    return 1
}

safe_delete_file() {
    local file="$1"
    if [[ "$file" == "$CLIPS_BASE/"* ]]; then
        rm -f "$file"
    else
        echo "❌ BLOCKED FILE DELETE: $file"
        log "Blocked file delete: $file"
    fi
}

safe_delete_dir() {
    local dir="$1"
    if [[ "$dir" == "$CLIPS_BASE/"* ]]; then
        rm -rf "$dir"
        log "Deleted directory: $dir"
    else
        echo "❌ BLOCKED DIR DELETE: $dir"
        log "Blocked dir delete: $dir"
    fi
}

safe_delete_recording() {
    local folder="$1"
    local target="$RECORDINGS_DIR/$folder"

    if [[ "$target" == "$RECORDINGS_DIR/"* ]]; then
        rm -rf "$target"
        log "Deleted recording folder: $target"
    else
        echo "❌ BLOCKED RECORDING DELETE: $target"
        log "Blocked recording delete: $target"
    fi
}

# ----------------------------------
# RECORDINGS CLEANUP
# ----------------------------------

echo ""
echo "🔍 Scanning recordings..."

cd "$RECORDINGS_DIR"

mapfile -t ALL_FOLDERS < <(ls -d 20[0-9][0-9]-* 2>/dev/null | sort)

COUNT=${#ALL_FOLDERS[@]}
CUTOFF=$((COUNT - KEEP_DAYS))

OLD_FOLDERS=()
if (( CUTOFF > 0 )); then
    OLD_FOLDERS=("${ALL_FOLDERS[@]:0:$CUTOFF}")
fi

# ----------------------------------
# CLIPS CLEANUP
# ----------------------------------

echo "🔍 Scanning clips..."

FILES_ALL=$(mktemp)
FILES_DELETE=$(mktemp)
FILES_AGED=$(mktemp)

find "$CLIPS_BASE" -type f > "$FILES_ALL"

current_time=$(date +%s)

while read -r file; do

    for ex in "${EXCLUDED_DIRS[@]}"; do
        [[ "$file" == *"/$ex/"* ]] && continue 2
    done

    file_mtime=$(stat -c %Y "$file")
    age_days=$(( (current_time - file_mtime) / 86400 ))

    if (( age_days > FIND_DAYS )); then
        echo "$file" >> "$FILES_DELETE"
        echo "$file" >> "$FILES_AGED"
    fi

done < "$FILES_ALL"

# ----------------------------------
# DIRECTORY CLEANUP
# ----------------------------------

declare -A ORPHAN_CAM_MAP

for parent in "${CAMERA_PARENT_DIRS[@]}"; do
    [[ -d "$parent" ]] || continue

    for dir in "$parent"/*; do
        [[ -d "$dir" ]] || continue

        name=$(basename "$dir")

        if ! is_camera_prefix "$name"; then
            ORPHAN_CAM_MAP["$name"]=1

            if [[ "$DRY_RUN" = false ]]; then
                safe_delete_dir "$dir"
            fi
        fi
    done
done

# ----------------------------------
# COUNTS + SIZES
# ----------------------------------

AGED_COUNT=$(wc -l < "$FILES_AGED")
TOTAL_COUNT=$AGED_COUNT

get_size() {
    if (( $1 > 0 )); then
        xargs -a "$2" du -ch 2>/dev/null | tail -1 | awk '{print $1}'
    else
        echo "0"
    fi
}

AGED_SIZE=$(get_size "$AGED_COUNT" "$FILES_AGED")

# ----------------------------------
# SUMMARY
# ----------------------------------

echo ""
echo "------------------------------------------"
echo "Cleanup Summary"
echo "------------------------------------------"

echo ""
echo "📁 Recordings"
echo "  Folders to remove : ${#OLD_FOLDERS[@]}"

echo ""
echo "🎞 Clips"
echo ""
echo "  ⏳ Aged Files"
echo "    Files : $AGED_COUNT"
echo "    Size  : $AGED_SIZE"

echo ""
echo "  📊 Total"
echo "    Files : $TOTAL_COUNT"
echo "    Size  : $AGED_SIZE"

echo ""
echo "📂 Orphan Camera Directories"

if (( ${#ORPHAN_CAM_MAP[@]} == 0 )); then
    echo "  Names : none"
else
    echo "  Names:"
    for cam in $(printf "%s\n" "${!ORPHAN_CAM_MAP[@]}" | sort); do
        echo "    $cam"
    done

    if (( ${#ORPHAN_CAM_MAP[@]} > 5 )); then
        echo ""
        echo "⚠️ WARNING: High orphan camera count (${#ORPHAN_CAM_MAP[@]})"
    fi
fi

# ----------------------------------
# EXECUTE DELETE
# ----------------------------------

if [[ "$DRY_RUN" = false ]]; then
    for folder in "${OLD_FOLDERS[@]}"; do
        safe_delete_recording "$folder"
    done

    while read -r f; do
        safe_delete_file "$f"
    done < "$FILES_DELETE"
fi

rm -f "$FILES_ALL" "$FILES_DELETE" "$FILES_AGED"

# ----------------------------------
# FOOTER
# ----------------------------------

echo ""
echo "------------------------------------------"
echo "ℹ️ Mode: $MODE_STR"
echo "------------------------------------------"

log "Cleanup finished ($MODE_STR)"
