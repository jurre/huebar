#!/bin/bash
# Take screenshots of HueBar for the README.
# Uses macOS interactive window capture — just click the HueBar window when prompted.
#
# Usage:
#   ./scripts/screenshot.sh              # Capture all three (rooms, room-detail, light-detail)
#   ./scripts/screenshot.sh rooms        # Capture just one by name
#   ./scripts/screenshot.sh my-view      # Capture with a custom name

set -euo pipefail
cd "$(dirname "$0")/.."

SCREENSHOT_DIR="screenshots"
mkdir -p "$SCREENSHOT_DIR"

capture() {
    local name="$1"
    local file="$SCREENSHOT_DIR/$name.png"
    echo ""
    echo "📸 Ready to capture: $name"
    echo "   Navigate to the '$name' view, then press Enter."
    read -r
    echo "   Click the HueBar window..."
    screencapture -w -o "$file"
    if [ -f "$file" ]; then
        echo "   ✅ Saved to $file"
    else
        echo "   ❌ Capture cancelled"
    fi
}

if [ $# -ge 1 ]; then
    capture "$1"
else
    echo "HueBar Screenshot Tool"
    echo "======================"
    echo "This will capture three screenshots for the README."
    echo "For each one, navigate to the right view, press Enter, then click the HueBar window."
    capture "rooms"
    capture "room-detail"
    capture "light-detail"
    echo ""
    echo "🎉 Done! Screenshots saved to $SCREENSHOT_DIR/"
fi
