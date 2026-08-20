#!/bin/zsh
# Compila y empaqueta RecordApp como un .app en dist/.
#
# ¿Por qué un bundle? macOS atribuye los permisos de TCC (pantalla, cámara,
# micrófono) al "responsable" del proceso: un binario suelto lanzado desde
# Terminal hereda los permisos de Terminal. Con el bundle, los permisos son
# de RecordApp, como en cualquier app normal.
#
# Nota: la firma es ad-hoc (sin cuenta de developer). macOS puede volver a
# pedir el permiso de Grabación de Pantalla tras recompilar, porque la
# identidad ad-hoc cambia con cada build.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP=dist/RecordApp.app

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/RecordApp" "$APP/Contents/MacOS/RecordApp"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

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
