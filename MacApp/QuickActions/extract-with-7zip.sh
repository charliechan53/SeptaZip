#!/bin/bash
#
# Quick Action: Extract with 7-Zip
#
# This script is used by the Automator Quick Action / macOS Shortcut
# to extract archives selected in Finder using 7-Zip.
#
# Install: Copy the .workflow to ~/Library/Services/
# Or use: Automator → New → Quick Action → Run Shell Script
#

# Find 7zz binary
SEVENZZ=""
CANDIDATES=(
    "/Applications/SeptaZip.app/Contents/Resources/7zz"
)

if [ "${SEPTAZIP_ALLOW_EXTERNAL_7ZZ:-0}" = "1" ]; then
    CANDIDATES+=(
        "/Applications/7-Zip.app/Contents/Resources/7zz"
        "/usr/local/bin/7zz"
        "/opt/homebrew/bin/7zz"
        "$HOME/.local/bin/7zz"
    )
fi

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

# Get files from arguments
FILES=("$@")

if [ ${#FILES[@]} -eq 0 ]; then
    osascript -e 'display dialog "No archives selected." with title "7-Zip" buttons {"OK"} default button "OK"'
    exit 0
fi

# Ask extraction mode
MODE=$(osascript -e '
    set modeChoice to choose from list {"Extract to subfolder", "Extract here (same folder)", "Choose destination..."} with title "7-Zip - Extract" with prompt "Where to extract?" default items {"Extract to subfolder"}
    if modeChoice is false then
        return "cancelled"
    end if
    return item 1 of modeChoice
')

if [ "$MODE" = "cancelled" ]; then
    exit 0
fi

ERRORS=0
SUCCESS=0

for ARCHIVE in "${FILES[@]}"; do
    DIR="$(dirname "$ARCHIVE")"
    BASENAME="$(basename "$ARCHIVE" | sed 's/\.[^.]*$//' | sed 's/\.tar$//')"

    case "$MODE" in
        "Extract to subfolder")
            DEST="$DIR/$BASENAME"
            mkdir -p "$DEST"
            ;;
        "Extract here"*)
            DEST="$DIR"
            ;;
        "Choose destination"*)
            DEST=$(osascript -e '
                set destFolder to choose folder with prompt "Extract to:" default location (POSIX file "'"$DIR"'")
                return POSIX path of destFolder
            ')
            if [ -z "$DEST" ]; then
                exit 0
            fi
            ;;
    esac

    "$SEVENZZ" x -o"$DEST" -aoa "$ARCHIVE" 2>&1

    if [ $? -le 1 ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    osascript -e "display notification \"$SUCCESS archive(s) extracted successfully\" with title \"7-Zip\" subtitle \"Extraction complete\""
else
    osascript -e "display notification \"$SUCCESS extracted, $ERRORS failed\" with title \"7-Zip\" subtitle \"Extraction finished with errors\""
fi
