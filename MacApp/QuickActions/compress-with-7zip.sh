#!/bin/bash
#
# Quick Action: Compress with 7-Zip
#
# This script is used by the Automator Quick Action / macOS Shortcut
# to compress selected files in Finder using 7-Zip.
#
# Install: Copy the .workflow to ~/Library/Services/
# Or use: Automator → New → Quick Action → Run Shell Script
#

# Find 7zz binary
SEVENZZ=""
CANDIDATES=(
    "/Applications/7-Zip.app/Contents/Resources/7zz"
    "/usr/local/bin/7zz"
    "/opt/homebrew/bin/7zz"
    "$HOME/.local/bin/7zz"
)

for candidate in "${CANDIDATES[@]}"; do
    if [ -x "$candidate" ]; then
        SEVENZZ="$candidate"
        break
    fi
done

if [ -z "$SEVENZZ" ]; then
    osascript -e 'display dialog "7zz binary not found. Please install 7-Zip for Mac." with title "7-Zip Error" buttons {"OK"} default button "OK" with icon caution'
    exit 1
fi

# Get files from arguments (Automator passes them as arguments)
FILES=("$@")

if [ ${#FILES[@]} -eq 0 ]; then
    osascript -e 'display dialog "No files selected." with title "7-Zip" buttons {"OK"} default button "OK"'
    exit 0
fi

# Determine output archive name
FIRST_FILE="${FILES[0]}"
DIR="$(dirname "$FIRST_FILE")"

if [ ${#FILES[@]} -eq 1 ]; then
    BASENAME="$(basename "$FIRST_FILE" | sed 's/\.[^.]*$//')"
else
    BASENAME="Archive"
fi

# Ask user for format
FORMAT=$(osascript -e '
    set formatChoice to choose from list {"7z (Best compression)", "ZIP (Most compatible)", "tar.gz (Unix standard)", "tar.xz (Best tar compression)", "tar.zst (Fast compression)"} with title "7-Zip - Compress" with prompt "Choose archive format:" default items {"7z (Best compression)"}
    if formatChoice is false then
        return "cancelled"
    end if
    return item 1 of formatChoice
')

if [ "$FORMAT" = "cancelled" ]; then
    exit 0
fi

# Map format choice to 7zz flags
case "$FORMAT" in
    "7z"*)
        EXT="7z"
        TYPE_FLAG="7z"
        ;;
    "ZIP"*)
        EXT="zip"
        TYPE_FLAG="zip"
        ;;
    "tar.gz"*)
        EXT="tar.gz"
        TYPE_FLAG="gzip"
        ;;
    "tar.xz"*)
        EXT="tar.xz"
        TYPE_FLAG="xz"
        ;;
    "tar.zst"*)
        EXT="tar.zst"
        TYPE_FLAG="zstd"
        ;;
    *)
        EXT="7z"
        TYPE_FLAG="7z"
        ;;
esac

OUTPUT="$DIR/$BASENAME.$EXT"

# Avoid overwriting existing files
COUNTER=1
while [ -e "$OUTPUT" ]; do
    OUTPUT="$DIR/${BASENAME}_${COUNTER}.$EXT"
    COUNTER=$((COUNTER + 1))
done

# Compress
"$SEVENZZ" a -t"$TYPE_FLAG" -mx=5 "$OUTPUT" "${FILES[@]}" 2>&1

if [ $? -eq 0 ]; then
    osascript -e "display notification \"Archive created: $(basename "$OUTPUT")\" with title \"7-Zip\" subtitle \"Compression complete\""
else
    osascript -e 'display dialog "Compression failed. Check the files and try again." with title "7-Zip Error" buttons {"OK"} default button "OK" with icon caution'
fi
