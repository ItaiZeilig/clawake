#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="release/Clawake.app"
VERSION="1.0.0"
DMG="release/Clawake-${VERSION}-arm64.dmg"
ENTITLEMENTS="Clawake.entitlements"

# Icon source: vendored assets/ (self-contained). Falls back to the original
# out-of-repo asset folder if someone still has it.
ASSETS="assets"
[ -d "$ASSETS" ] || ASSETS="$HOME/Documents/cc-caffeine/assets"

# --- Signing configuration -------------------------------------------------
# For a NOTARIZED release, export a Developer ID Application identity, e.g.:
#   export DEVID_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# and, to notarize + staple in one run, a stored notarytool profile:
#   export NOTARY_PROFILE="clawake-notary"
# With neither set, the app is ad-hoc signed (launches locally, NOT notarized).
DEVID_IDENTITY="${DEVID_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

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
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# --- Codesign --------------------------------------------------------------
if [ -n "$DEVID_IDENTITY" ]; then
  echo "Codesigning with Developer ID (hardened runtime)..."
  echo "  identity: $DEVID_IDENTITY"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVID_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "Ad-hoc signing (local only, NOT notarizable)..."
  echo "  set DEVID_IDENTITY to a 'Developer ID Application: ...' identity to sign for release."
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

# Packs the current (possibly stapled) $APP into a fresh $DMG, laid out as a
# "drag to Applications" installer window (icon positions + a branded background
# with an arrow), the way well-made Mac apps ship.
make_dmg() {
  rm -f "$DMG"
  local VOL="Clawake"
  local MNT="/Volumes/$VOL"
  local RW; RW="$(mktemp -d)/rw.dmg"

  # Detach any stale mount from a previous run.
  hdiutil detach "$MNT" >/dev/null 2>&1 || true

  # A read-write image, sized to the app plus headroom for the background asset.
  local MB; MB=$(( $(du -sm "$APP" | cut -f1) + 25 ))
  hdiutil create -volname "$VOL" -size "${MB}m" -fs HFS+ -ov "$RW" >/dev/null

  hdiutil attach "$RW" -noautoopen -mountpoint "$MNT" >/dev/null
  cp -R "$APP" "$MNT/"
  ln -sf /Applications "$MNT/Applications"
  mkdir -p "$MNT/.background"
  # HiDPI multi-rep TIFF (1x + 2x) so the background is crisp on Retina.
  cp "$ASSETS/dmg-bg.tiff" "$MNT/.background/background.tiff" 2>/dev/null || true

  # Lay out the Finder window. Needs permission to control Finder the first time.
  osascript <<OSA || echo "  (DMG layout via Finder was skipped; icons will use default positions)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 800, 510}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 12
    try
      set background picture of opts to file ".background:background.tiff"
    end try
    set position of item "Clawake.app" of container window to {150, 195}
    set position of item "Applications" of container window to {450, 195}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

  sync
  hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach "$MNT" -force >/dev/null 2>&1 || true

  # Compress to the final read-only DMG.
  hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
  rm -f "$RW"
}

# --- Notarize + staple -----------------------------------------------------
# Canonical order: notarize + staple the APP first, THEN build the DMG from the
# stapled app, THEN notarize + staple that DMG. A stapler ticket is keyed to the
# file's hash, so the DMG that gets stapled must be the exact one that was
# submitted (never rebuilt afterward, or stapling fails with "Record not found").
if [ -n "$DEVID_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "Notarizing the app..."
  APPZIP="$(mktemp -d)/Clawake.zip"
  ditto -c -k --keepParent "$APP" "$APPZIP"
  xcrun notarytool submit "$APPZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$APPZIP"
  xcrun stapler staple "$APP"          # app now carries its own ticket (offline-verifiable)

  echo "Creating DMG from the stapled app..."
  make_dmg

  echo "Signing the DMG..."
  codesign --force --sign "$DEVID_IDENTITY" --timestamp "$DMG"

  echo "Notarizing the DMG..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"          # staple the SAME dmg that was submitted

  echo "Verifying..."
  xcrun stapler validate "$APP"
  xcrun stapler validate "$DMG"
  spctl -a -t open --context context:primary-signature -vv "$DMG" || true
else
  echo "Creating DMG..."
  make_dmg
  if [ -n "$DEVID_IDENTITY" ]; then
    echo "Signed with Developer ID but NOTARY_PROFILE not set: skipping notarization."
    echo "  store a profile once, then re-run:"
    echo "    xcrun notarytool store-credentials clawake-notary \\"
    echo "      --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>"
    echo "    NOTARY_PROFILE=clawake-notary DEVID_IDENTITY=\"$DEVID_IDENTITY\" ./build-app.sh"
  fi
fi

echo "Done."
echo "  app: $(du -sh "$APP" | cut -f1)"
echo "  dmg: $(du -h "$DMG" | cut -f1)  ->  $DMG"
