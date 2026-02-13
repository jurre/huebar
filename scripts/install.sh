#!/bin/bash
set -euo pipefail

APP_NAME="HueBar"
BUNDLE_ID="com.jurre.huebar"
APP_DIR="$APP_NAME.app"
INSTALL_DIR="/Applications"

# Quit any running instance first
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

echo "Building release binary..."
swift build -c release --quiet

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
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
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

echo "Installing to $INSTALL_DIR..."
if [ -d "$INSTALL_DIR/$APP_DIR" ]; then
    rm -rf "$INSTALL_DIR/$APP_DIR"
fi
cp -R "$APP_DIR" "$INSTALL_DIR/"
rm -rf "$APP_DIR"

echo ""
echo "✅ $APP_NAME.app installed to $INSTALL_DIR"
echo "   Open it from Spotlight, Finder, or run:"
echo "   open /Applications/$APP_DIR"
