#!/bin/zsh
# El DMG que se publica en dl.grabi.net: build universal (Apple Silicon +
# Intel), firmado con Developer ID, con el perfil embebido para universal
# links, y NOTARIZADO con el ticket grapado al propio DMG.
#
#   ./make-interim-release.sh
#
# La firma vive en scripts/sign-app.sh, compartida con make-app.sh: este
# script tenía su propia copia y se quedó atrás — durante días publicó DMGs
# con la identidad interina mientras el build local ya salía notarizado.
#
# NOTARIZE=0 para saltarse la notarización (pruebas locales).
set -euo pipefail
cd "$(dirname "$0")"

NOTARIZE="${NOTARIZE:-1}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
APP=dist/Grabi.app
DMG=dist/Grabi-$VERSION.dmg
STAGE=dist/dmg-stage

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

# 3. Sparkle + firma (perfil, entitlements y binarios anidados incluidos)
scripts/embed-sparkle.sh "$APP"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
scripts/sign-app.sh "$APP" "$BUNDLE_ID"

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

# 5. Notarización del DMG. Se grapa al propio DMG para que Gatekeeper lo
#    acepte sin consultar a Apple — y sin red, que es el caso real de quien
#    lo descarga y lo abre después.
if [[ "$NOTARIZE" == "1" ]]; then
  scripts/notarize.sh "$DMG"
fi

echo "✅ $DMG ready ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
echo "   Share it together with docs/install-grabi.html (also included inside the DMG)."
