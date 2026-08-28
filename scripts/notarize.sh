#!/bin/zsh
# Notariza un .app o un .dmg con Apple y le grapa el ticket.
#
# Notarizar es lo que hace que macOS abra Grabi sin el aviso de "app
# dañada": Apple revisa el binario firmado con Developer ID y devuelve un
# ticket; `stapler` lo pega al archivo para que funcione incluso sin red.
#
# Requisito de una sola vez (las credenciales quedan en el llavero, nunca
# en el repo):
#
#   xcrun notarytool store-credentials grabi-notary \
#     --apple-id <tu-apple-id> \
#     --team-id F6X8HM2S7A \
#     --password <app-specific-password de appleid.apple.com>
#
# Uso:  scripts/notarize.sh dist/Grabi.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-dist/Grabi.dmg}"
PROFILE="${NOTARY_PROFILE:-grabi-notary}"
TEAM_ID="F6X8HM2S7A"

[[ -e "$TARGET" ]] || { echo "✗ No existe: $TARGET"; exit 1; }

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "✗ Faltan las credenciales de notarización."
  echo "  Créalas una vez con:"
  echo "    xcrun notarytool store-credentials $PROFILE \\"
  echo "      --apple-id <apple-id> --team-id $TEAM_ID --password <app-specific-password>"
  exit 1
fi

# Un .app hay que comprimirlo: notarytool solo acepta dmg, pkg o zip.
UPLOAD="$TARGET"
TEMP_ZIP=""
if [[ "$TARGET" == *.app ]]; then
  TEMP_ZIP="${TARGET%.app}.zip"
  rm -f "$TEMP_ZIP"
  ditto -c -k --keepParent "$TARGET" "$TEMP_ZIP"
  UPLOAD="$TEMP_ZIP"
fi

echo "→ Enviando a Apple: $UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait

# El ticket se grapa al artefacto original (el .app, no el zip).
echo "→ Grapando el ticket"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

[[ -n "$TEMP_ZIP" ]] && rm -f "$TEMP_ZIP"

echo "→ Veredicto de Gatekeeper:"
spctl --assess --type execute --verbose "$TARGET" 2>&1 | tail -2 || true
echo "✅ Notarizado: $TARGET"
