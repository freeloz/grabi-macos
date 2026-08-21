#!/bin/zsh
# Compila y empaqueta Grabi como .app en dist/.
#
# ¿Por qué un bundle? macOS atribuye los permisos de TCC (pantalla, cámara,
# micrófono) al "responsable" del proceso: un binario suelto lanzado desde
# Terminal hereda los permisos de Terminal. Con el bundle, los permisos son
# de Grabi, como en cualquier app normal.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP=dist/Grabi.app

swift build -c "$CONFIG"

rm -rf "$APP" dist/RecordApp.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/RecordApp" "$APP/Contents/MacOS/Grabi"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Bundles de recursos SPM (Localizable.strings de cada target): Bundle.module
# los busca en Contents/Resources del .app.
BUILD_DIR=".build/$CONFIG"
for b in "$BUILD_DIR"/Record_*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done
# Descripciones de uso (TCC) localizadas
for l in Support/InfoPlist/*.lproj; do
  mkdir -p "$APP/Contents/Resources/$(basename "$l")"
  cp "$l/InfoPlist.strings" "$APP/Contents/Resources/$(basename "$l")/"
done

# Firma: con la identidad local estable "Grabi Dev" si existe (los permisos
# de TCC sobreviven a las recompilaciones); si no, ad-hoc (los permisos de
# pantalla se pierden en cada build nuevo).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Grabi Dev"; then
  codesign --force --sign "Grabi Dev" "$APP"
  echo "Firmada con identidad estable: Grabi Dev"
else
  codesign --force --sign - "$APP"
  echo "⚠️  Firma ad-hoc: macOS pedirá el permiso de pantalla tras cada rebuild"
fi

echo "✅ Listo: $APP"
echo "Ábrela con: open $APP"
