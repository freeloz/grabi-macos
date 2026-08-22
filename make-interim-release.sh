#!/bin/zsh
# Interim distribution of Grabi (beta, no Apple Developer account):
# builds release, signs with the stable local identity, and generates a
# presentable DMG with instructions. Regenerate everything with:
#
#   ./make-interim-release.sh
#
# When the Apple Developer account arrives:
#   1. SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   2. Add notarization (notarytool submit + stapler) after creating the DMG.
# Nothing else changes.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:-Grabi Dev}"
# HARDENED=0 ./make-interim-release.sh to sign without hardened runtime if
# some macOS version misbehaves without notarization.
HARDENED="${HARDENED:-1}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
APP=dist/Grabi.app
DMG=dist/Grabi-$VERSION.dmg
STAGE=dist/dmg-stage

# 1. Signing identity (stable: TCC permissions persist across versions)
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "The identity \"$SIGN_IDENTITY\" does not exist. Create it with:"
  echo "  ./scripts/create-signing-identity.sh"
  exit 1
fi

# 2. Release build + bundle — universal (Apple Silicon + Intel)
swift build -c release --arch arm64 --arch x86_64
rm -rf "$APP" "$STAGE" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/RecordApp "$APP/Contents/MacOS/Grabi"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# SPM resource bundles (each target's Localizable.strings): Bundle.module
# looks for them in the .app's Contents/Resources.
BUILD_DIR=".build/apple/Products/Release"
for b in "$BUILD_DIR"/Record_*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done
# Localized usage descriptions (TCC)
for l in Support/InfoPlist/*.lproj; do
  mkdir -p "$APP/Contents/Resources/$(basename "$l")"
  cp "$l/InfoPlist.strings" "$APP/Contents/Resources/$(basename "$l")/"
done

# 3. Embed Sparkle (auto-updates), then sign inside-out: Sparkle's nested
#    executables first, then the framework, then the app. The entitlements
#    include disable-library-validation because "Grabi Dev" has no Team ID.
scripts/embed-sparkle.sh "$APP"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ "$HARDENED" == "1" ]]; then
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/Updater.app"
  codesign --force --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE"
  codesign --force --options runtime \
    --entitlements Support/Grabi.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed: \"$SIGN_IDENTITY\" + hardened runtime (ready to notarize)"
else
  codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
  codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE/Versions/B/Updater.app"
  codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE"
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed: \"$SIGN_IDENTITY\" (no hardened runtime)"
fi
codesign --verify --strict "$APP" && echo "Signature verification: OK"

# 4. Presentable DMG: app + alias to Applications + instructions + background
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Grabi.app"
ln -s /Applications "$STAGE/Applications"
cp docs/install-grabi.html "$STAGE/README · How to install.html"
cp Support/dmg-fondo.png "$STAGE/.background/fondo.png"

hdiutil create -volname "Grabi $VERSION" -srcfolder "$STAGE" -ov -format UDRW \
  -fs HFS+ "$DMG.rw.dmg" > /dev/null

# Finder layout (background, window size, positions). Best-effort: if Finder
# automation lacks permission, the DMG still ships, just without background.
MOUNT=$(hdiutil attach "$DMG.rw.dmg" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $3}')
if [[ -n "$MOUNT" ]]; then
  osascript <<EOF 2>/dev/null || echo "⚠️  No permission to automate Finder: DMG without custom layout"
tell application "Finder"
  tell disk "$(basename "$MOUNT")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 860, 560}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set background picture of viewOptions to file ".background:fondo.png"
    set position of item "Grabi.app" of container window to {180, 210}
    set position of item "Applications" of container window to {480, 210}
    set position of item "README · How to install.html" of container window to {330, 350}
    close
    open
    delay 1
    close
  end tell
end tell
EOF
  sync
  hdiutil detach "$MOUNT" -quiet
fi

hdiutil convert "$DMG.rw.dmg" -format UDZO -o "$DMG" > /dev/null
rm -f "$DMG.rw.dmg"
rm -rf "$STAGE"

echo "✅ $DMG ready ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
echo "   Share it together with docs/install-grabi.html (also included inside the DMG)."
