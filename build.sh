#!/bin/bash
# Builds PortBar.app.  Usage:  ./build.sh           → build/PortBar.app
#                              ./build.sh install   → also copy to /Applications and launch
#                              ./build.sh zip       → also make build/PortBar.zip to share
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PortBar.app
VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
BUILD_NUMBER=$(echo "$VERSION" | tr -d '.')

echo "→ Compiling (universal, release)…"
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -Osize >/dev/null
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PortBar

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PortBar"
strip -x "$APP/Contents/MacOS/PortBar" 2>/dev/null || true
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PortBar</string>
  <key>CFBundleDisplayName</key><string>PortBar</string>
  <key>CFBundleIdentifier</key><string>com.portbar.app</string>
  <key>CFBundleExecutable</key><string>PortBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "✓ Built $APP v$VERSION ($(du -sh "$APP" | cut -f1))"

case "${1:-}" in
  install)
    pkill -x PortBar 2>/dev/null || true
    rm -rf /Applications/PortBar.app
    cp -R "$APP" /Applications/
    open /Applications/PortBar.app
    echo "✓ Installed to /Applications and launched — look for the terminal icon in your menu bar"
    ;;
  zip)
    ditto -c -k --keepParent "$APP" build/PortBar.zip
    echo "✓ build/PortBar.zip ($(du -h build/PortBar.zip | cut -f1))"
    ;;
esac
