
#!/bin/bash
set -euo pipefail

APP_NAME="LCD Prank Overlay"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/$APP_NAME.app"

mkdir -p "$ROOT/dist" "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -parse-as-library "$ROOT/Sources/main.swift" \
  -o "$APP/Contents/MacOS/LCDPrankOverlay" \
  -framework SwiftUI -framework AppKit -framework Carbon -framework ServiceManagement

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>LCDPrankOverlay</string>
  <key>CFBundleName</key>
  <string>LCD Prank Overlay</string>
  <key>CFBundleDisplayName</key>
  <string>LCD Prank Overlay</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.lcdprankoverlay</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built: $APP"
