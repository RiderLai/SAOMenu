#!/bin/bash
# Builds build/SAOMenu.app (universal: Apple Silicon + Intel, macOS 12+).
# Usage: ./build.sh [run|package]   package -> dist/SAOMenu.zip
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SAOMenu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN="$APP/Contents/MacOS/SAOMenu"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos12.0" Sources/main.swift \
    -o "build/SAOMenu-$arch" \
    -framework Cocoa -framework WebKit -framework Carbon -framework AVFoundation
done
lipo -create build/SAOMenu-arm64 build/SAOMenu-x86_64 -output "$BIN"
rm build/SAOMenu-arm64 build/SAOMenu-x86_64

cp -R Resources/. "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SAOMenu</string>
  <key>CFBundleDisplayName</key><string>SAO Menu</string>
  <key>CFBundleIdentifier</key><string>local.sao-menu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>SAOMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "run" ]]; then
  pkill -x SAOMenu 2>/dev/null || true
  open "$APP"
fi

if [[ "${1:-}" == "package" ]]; then
  mkdir -p dist
  rm -f dist/SAOMenu.zip
  ditto -c -k --keepParent "$APP" dist/SAOMenu.zip
  echo "Packaged dist/SAOMenu.zip"
fi
