#!/bin/zsh
# Distribución interina de Grabi (beta, sin cuenta de Apple Developer):
# compila release, firma con la identidad local estable y genera un DMG
# presentable con instrucciones. Regenera todo con:
#
#   ./make-interim-release.sh
#
# Cuando llegue la cuenta de Apple Developer:
#   1. SIGN_IDENTITY="Developer ID Application: Tu Nombre (TEAMID)"
#   2. Añadir la notarización (notarytool submit + stapler) tras crear el DMG.
# Nada más cambia.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:-Grabi Dev}"
# HARDENED=0 ./make-interim-release.sh para firmar sin hardened runtime si
# alguna versión de macOS diera problemas sin notarización.
HARDENED="${HARDENED:-1}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
APP=dist/Grabi.app
DMG=dist/Grabi-$VERSION.dmg
STAGE=dist/dmg-stage

# 1. Identidad de firma (estable: los permisos TCC persisten entre versiones)
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "No existe la identidad \"$SIGN_IDENTITY\". Créala con:"
  echo "  ./scripts/crear-identidad-firma.sh"
  exit 1
fi

# 2. Build release + bundle
swift build -c release
rm -rf "$APP" "$STAGE" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/RecordApp "$APP/Contents/MacOS/Grabi"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bundles de recursos SPM (Localizable.strings de cada target): Bundle.module
# los busca en Contents/Resources del .app.
BUILD_DIR=".build/release"
for b in "$BUILD_DIR"/Record_*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done
# Descripciones de uso (TCC) localizadas
for l in Support/InfoPlist/*.lproj; do
  mkdir -p "$APP/Contents/Resources/$(basename "$l")"
  cp "$l/InfoPlist.strings" "$APP/Contents/Resources/$(basename "$l")/"
done

# 3. Firma (sin --deep: la app no tiene bundles anidados)
if [[ "$HARDENED" == "1" ]]; then
  codesign --force --options runtime \
    --entitlements Support/Grabi.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
  echo "Firmada: \"$SIGN_IDENTITY\" + hardened runtime (lista para notarizar)"
else
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
  echo "Firmada: \"$SIGN_IDENTITY\" (sin hardened runtime)"
fi
codesign --verify --strict "$APP" && echo "Verificación de firma: OK"

# 4. DMG presentable: app + alias a Aplicaciones + instrucciones + fondo
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Grabi.app"
ln -s /Applications "$STAGE/Aplicaciones"
cp docs/instalar-grabi.html "$STAGE/LÉEME · Cómo instalar.html"
cp Support/dmg-fondo.png "$STAGE/.background/fondo.png"

hdiutil create -volname "Grabi $VERSION" -srcfolder "$STAGE" -ov -format UDRW \
  -fs HFS+ "$DMG.rw.dmg" > /dev/null

# Layout de Finder (fondo, tamaño de ventana, posiciones). Best-effort: si la
# automatización de Finder no tiene permiso, el DMG sale igual, solo sin fondo.
MOUNT=$(hdiutil attach "$DMG.rw.dmg" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $3}')
if [[ -n "$MOUNT" ]]; then
  osascript <<EOF 2>/dev/null || echo "⚠️  Sin permiso para automatizar Finder: DMG sin layout personalizado"
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
    set position of item "Aplicaciones" of container window to {480, 210}
    set position of item "LÉEME · Cómo instalar.html" of container window to {330, 350}
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

echo "✅ $DMG listo ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
echo "   Compárte­lo junto con docs/instalar-grabi.html (también va dentro del DMG)."
