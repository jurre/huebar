#!/bin/bash
set -euo pipefail

APP_NAME="HueBar"
BUNDLE_ID="com.jurre.huebar"
APP_DIR="$APP_NAME.app"
INSTALL_DIR="/Applications"
VERSION="1.0"
SKIP_INSTALL=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-install)
            SKIP_INSTALL=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--no-install] [--version VERSION]"
            exit 1
            ;;
    esac
done

# Quit any running instance first, remember if it was running
WAS_RUNNING=false
if [ "$SKIP_INSTALL" = false ] && pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    WAS_RUNNING=true
    echo "Stopping running $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 1
    # Force kill if still running
    if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
        kill "$(pgrep -x "$APP_NAME")" 2>/dev/null || true
        sleep 1
    fi
fi

if [ ! -f ".build/release/$APP_NAME" ]; then
    echo "Building release binary..."
    swift build -c release --quiet
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/$APP_NAME "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy app icon
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc code sign so macOS doesn't block it
codesign --force --sign - "$APP_DIR"

if [ "$SKIP_INSTALL" = true ]; then
    # CI mode: create zip instead of installing
    echo "Creating distributable ZIP..."
    zip -r "$APP_NAME.zip" "$APP_DIR"
    rm -rf "$APP_DIR"
    echo "✅ $APP_NAME.zip created for distribution"
else
    # Local install mode
    echo "Installing to $INSTALL_DIR..."
    if [ -d "$INSTALL_DIR/$APP_DIR" ]; then
        rm -rf "$INSTALL_DIR/$APP_DIR"
    fi
    cp -R "$APP_DIR" "$INSTALL_DIR/"
    rm -rf "$APP_DIR"

    echo ""
    echo "✅ $APP_NAME.app installed to $INSTALL_DIR"

    if [ "$WAS_RUNNING" = true ]; then
        echo "Re-opening $APP_NAME..."
        open "$INSTALL_DIR/$APP_DIR"
    else
        echo "   Open it from Spotlight, Finder, or run:"
        echo "   open /Applications/$APP_DIR"
    fi
fi
