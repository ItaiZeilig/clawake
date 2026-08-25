#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="release/Clawake.app"
ASSETS="$HOME/Documents/cc-caffeine/assets"
VERSION="1.0.0"

echo "Building release binary..."
swift build -c release >/dev/null

echo "Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Clawake "$APP/Contents/MacOS/Clawake"

# Use the @2x (44px) art at menu-bar size for retina crispness.
cp "$ASSETS/car-active@2x.png" "$APP/Contents/Resources/car-active.png"
cp "$ASSETS/car-idle@2x.png"   "$APP/Contents/Resources/car-idle.png"
cp "$ASSETS/AppIcon.icns"      "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Clawake</string>
  <key>CFBundleDisplayName</key><string>Clawake</string>
  <key>CFBundleIdentifier</key><string>app.clawake.desktop</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>Clawake</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so it launches cleanly on this Mac.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Creating DMG..."
rm -f "release/Clawake-${VERSION}-arm64.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Clawake" -srcfolder "$STAGE" -ov -format UDZO \
  "release/Clawake-${VERSION}-arm64.dmg" >/dev/null
rm -rf "$STAGE"

echo "Done."
echo "  app: $(du -sh "$APP" | cut -f1)"
echo "  dmg: $(du -h "release/Clawake-${VERSION}-arm64.dmg" | cut -f1)  ->  release/Clawake-${VERSION}-arm64.dmg"
