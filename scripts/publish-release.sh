#!/bin/zsh
# Publica una release de Grabi para macOS:
#   1. Compila y firma el DMG (make-interim-release.sh).
#   2. Calcula el SHA-256 y lo publica junto al DMG.
#   3. Sube todo a R2 (dl.grabi.net) de forma versionada + actualiza "latest".
#   4. Crea la GitHub Release con el DMG y los checksums adjuntos.
#
# Uso:  ./scripts/publish-release.sh
#
# Requiere: identidad de firma "Grabi Dev" en el llavero, gh CLI autenticada
# y credenciales de Cloudflare (CLOUDFLARE_API_TOKEN en el entorno, o una
# sesión de wrangler ya iniciada). El token NUNCA se escribe en disco.
#
# Estructura en el bucket (por plataforma, listo para futuras plataformas):
#   macos/v<versión>/Grabi-<versión>.dmg          (inmutable)
#   macos/v<versión>/Grabi-<versión>.dmg.sha256
#   macos/v<versión>/SHA256SUMS.txt
#   macos/latest/Grabi.dmg (+ .sha256)            (siempre la última)
#   macos/latest.json                              (manifiesto con url+sha256)
set -euo pipefail
cd "$(dirname "$0")/.."

export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-0ef61977f8d1fc1e483034fdbde55f9e}"
BUCKET="grabi-releases"
PLATFORM="macos"

# 1. Build + firma
./make-interim-release.sh

V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
DMG="dist/Grabi-$V.dmg"
[ -f "$DMG" ] || { echo "No existe $DMG"; exit 1; }

# 2. Checksums
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(stat -f %z "$DMG")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
printf '%s\n' "$SHA" > "$STAGE/Grabi-$V.dmg.sha256"
printf '%s  Grabi-%s.dmg\n' "$SHA" "$V" > "$STAGE/SHA256SUMS.txt"
/usr/bin/env python3 - "$V" "$SHA" "$SIZE" > "$STAGE/latest.json" <<'PY'
import json, sys, datetime
v, sha, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
print(json.dumps({
    "platform": "macos", "version": v, "minOS": "macOS 13",
    "url": f"https://dl.grabi.net/macos/v{v}/Grabi-{v}.dmg",
    "sha256": sha, "sizeBytes": size,
    "publishedAt": datetime.date.today().isoformat(),
    "signature": {"type": "self-signed", "identity": "Grabi Dev",
                  "note": "Interim beta signing; Developer ID + notarization pending"},
}, indent=2))
PY

# 3. Subida a R2 (dl.grabi.net)
put() { npx -y wrangler r2 object put "$BUCKET/$1" --file "$2" --content-type "$3" --remote; }
put "$PLATFORM/v$V/Grabi-$V.dmg"        "$DMG"                       application/x-apple-diskimage
put "$PLATFORM/v$V/Grabi-$V.dmg.sha256" "$STAGE/Grabi-$V.dmg.sha256" text/plain
put "$PLATFORM/v$V/SHA256SUMS.txt"      "$STAGE/SHA256SUMS.txt"      text/plain
put "$PLATFORM/latest/Grabi.dmg"        "$DMG"                       application/x-apple-diskimage
put "$PLATFORM/latest/Grabi.dmg.sha256" "$STAGE/Grabi-$V.dmg.sha256" text/plain
put "$PLATFORM/latest.json"             "$STAGE/latest.json"         application/json

# 4. Verificación end-to-end: lo que sirve el CDN es byte a byte lo subido
sleep 5
REMOTE_SHA=$(curl -fsSL "https://dl.grabi.net/$PLATFORM/v$V/Grabi-$V.dmg" | shasum -a 256 | awk '{print $1}')
[ "$REMOTE_SHA" = "$SHA" ] || { echo "SHA remoto NO coincide"; exit 1; }
echo "✅ dl.grabi.net sirve v$V con SHA-256 verificado."

# 5. Tag + GitHub Release
git tag "v$V" 2>/dev/null || true
git push origin "v$V"
gh release create "v$V" "$DMG" "$STAGE/SHA256SUMS.txt" \
  --title "Grabi $V (macOS)" \
  --notes "DMG firmado (identidad interina \"Grabi Dev\", hardened runtime).

**Descarga recomendada:** https://dl.grabi.net/macos/v$V/Grabi-$V.dmg
**SHA-256:** \`$SHA\`

Verifica la descarga con: \`shasum -a 256 Grabi-$V.dmg\`" \
  2>/dev/null || echo "(la release v$V ya existía en GitHub)"
echo "✅ Release v$V publicada."
