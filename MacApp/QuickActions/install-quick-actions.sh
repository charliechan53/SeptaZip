#!/bin/bash
#
# Install Quick Actions for Finder right-click integration.
# Creates Automator workflows that appear in Finder's context menu.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICES_DIR="$HOME/Library/Services"

mkdir -p "$SERVICES_DIR"

echo "=== Installing 7-Zip Quick Actions ==="

# Create "Compress with 7-Zip" Quick Action
create_workflow() {
    local NAME="$1"
    local SCRIPT="$2"
    local ACCEPTS="$3"
    local WORKFLOW_DIR="$SERVICES_DIR/$NAME.workflow/Contents"

    mkdir -p "$WORKFLOW_DIR"

    # Copy the shell script
    cp "$SCRIPT_DIR/$SCRIPT" "$WORKFLOW_DIR/run.sh"
    chmod +x "$WORKFLOW_DIR/run.sh"

    # Create the workflow Info.plist
    cat > "$WORKFLOW_DIR/Info.plist" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
INFOPLIST

    echo "                <string>$NAME</string>" >> "$WORKFLOW_DIR/Info.plist"

    cat >> "$WORKFLOW_DIR/Info.plist" << 'INFOPLIST'
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
INFOPLIST

    # Create the Automator document.wflow
    cat > "$WORKFLOW_DIR/document.wflow" << WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key>
    <string>523</string>
    <key>AMApplicationVersion</key>
    <string>2.10</string>
    <key>AMDocumentVersion</key>
    <string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Optional</key>
                    <false/>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.path</string>
                    </array>
                </dict>
                <key>AMActionVersion</key>
                <string>1.0.2</string>
                <key>AMApplication</key>
                <array>
                    <string>Automator</string>
                </array>
                <key>AMBundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>AMCategory</key>
                <string>AMCategoryUtilities</string>
                <key>AMIconName</key>
                <string>Automator</string>
                <key>AMParameterProperties</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <dict/>
                    <key>inputMethod</key>
                    <dict/>
                    <key>shell</key>
                    <dict/>
                    <key>source</key>
                    <dict/>
                </dict>
                <key>AMProvides</key>
                <dict>
                    <key>Container</key>
                    <string>List</string>
                    <key>Types</key>
                    <array>
                        <string>com.apple.cocoa.path</string>
                    </array>
                </dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>"$WORKFLOW_DIR/run.sh" "\$@"</string>
                    <key>CheckedForUserDefaultShell</key>
                    <true/>
                    <key>inputMethod</key>
                    <integer>1</integer>
                    <key>shell</key>
                    <string>/bin/bash</string>
                    <key>source</key>
                    <string></string>
                </dict>
                <key>BundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key>
                <string>1.0.2</string>
                <key>CanShowSelectedItemsWhenRun</key>
                <false/>
                <key>CanShowWhenRun</key>
                <true/>
                <key>Category</key>
                <array>
                    <string>AMCategoryUtilities</string>
                </array>
                <key>Class Name</key>
                <string>RunShellScriptAction</string>
                <key>InputUUID</key>
                <string>B5A0B6E0-0001-0000-0000-000000000000</string>
                <key>Keywords</key>
                <array>
                    <string>Shell</string>
                    <string>Script</string>
                    <string>Command</string>
                    <string>Run</string>
                </array>
                <key>OutputUUID</key>
                <string>B5A0B6E0-0002-0000-0000-000000000000</string>
                <key>UUID</key>
                <string>B5A0B6E0-0003-0000-0000-000000000000</string>
                <key>UnlocalizedApplications</key>
                <array>
                    <string>Automator</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>connectors</key>
    <dict/>
    <key>workflowMetaData</key>
    <dict>
        <key>workflowTypeIdentifier</key>
        <string>com.apple.Automator.servicesMenu</string>
    </dict>
</dict>
</plist>
WFLOW

    echo "[OK] Installed: $NAME"
}

create_workflow "Compress with 7-Zip" "compress-with-7zip.sh" "public.item"
create_workflow "Extract with 7-Zip" "extract-with-7zip.sh" "public.item"

echo ""
echo "=== Quick Actions installed ==="
echo ""
echo "The Quick Actions are now available in Finder's right-click menu."
echo "If they don't appear immediately:"
echo "  1. Open System Settings → Privacy & Security → Extensions → Finder"
echo "  2. Make sure the 7-Zip actions are enabled"
echo "  3. Or: killall Finder"
