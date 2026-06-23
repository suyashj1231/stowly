#!/bin/bash
# Package ReelPlanner as a standalone macOS menu-bar app (no terminal needed).
# Usage: ./build_app.sh   ->   produces ./ReelPlanner.app
set -euo pipefail
cd "$(dirname "$0")"

echo "Building release…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="ReelPlanner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/ReelPlanner" "$APP/Contents/MacOS/ReelPlanner"

# Bundled SwiftPM resources (extract_reel.py lives in ReelPlanner_ReelPlanner.bundle)
if [ -d "$BIN_DIR/ReelPlanner_ReelPlanner.bundle" ]; then
  cp -R "$BIN_DIR/ReelPlanner_ReelPlanner.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ReelPlanner</string>
    <key>CFBundleIdentifier</key><string>com.suyash.reelplanner</string>
    <key>CFBundleName</key><string>ReelPlanner</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so it launches locally without Gatekeeper complaints.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "(codesign skipped)"

echo "✓ Built $APP"
echo "  Run:        open $APP"
echo "  Install:    move it to /Applications, then add to System Settings > General > Login Items"
