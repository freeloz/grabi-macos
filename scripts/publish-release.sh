#!/bin/zsh
# Publishes a Grabi release for macOS:
#   1. Builds and signs the DMG (make-interim-release.sh).
#   2. Computes the SHA-256 and publishes it next to the DMG.
#   3. Uploads everything to R2 (dl.grabi.net) versioned + updates "latest".
#   4. Creates the GitHub Release with the DMG and checksums attached.
#
# Usage:  ./scripts/publish-release.sh
#
# Requires: "Grabi Dev" signing identity in the keychain, an authenticated
# gh CLI, and Cloudflare credentials (CLOUDFLARE_API_TOKEN in the
# environment, or an existing wrangler session). The token is NEVER written
# to disk.
#
# Bucket layout (per platform, ready for future platforms):
#   macos/v<version>/Grabi-<version>.dmg          (immutable)
#   macos/v<version>/Grabi-<version>.dmg.sha256
#   macos/v<version>/SHA256SUMS.txt
#   macos/latest/Grabi.dmg (+ .sha256)            (always the latest)
#   macos/latest.json                              (manifest with url+sha256)
set -euo pipefail
cd "$(dirname "$0")/.."

export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-0ef61977f8d1fc1e483034fdbde55f9e}"
BUCKET="grabi-releases"
PLATFORM="macos"

# 1. Build + signing
./make-interim-release.sh

V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
DMG="dist/Grabi-$V.dmg"
[ -f "$DMG" ] || { echo "$DMG does not exist"; exit 1; }

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

# 3. Upload to R2 (dl.grabi.net)
put() { npx -y wrangler r2 object put "$BUCKET/$1" --file "$2" --content-type "$3" --remote; }
put "$PLATFORM/v$V/Grabi-$V.dmg"        "$DMG"                       application/x-apple-diskimage
put "$PLATFORM/v$V/Grabi-$V.dmg.sha256" "$STAGE/Grabi-$V.dmg.sha256" text/plain
put "$PLATFORM/v$V/SHA256SUMS.txt"      "$STAGE/SHA256SUMS.txt"      text/plain
put "$PLATFORM/latest/Grabi.dmg"        "$DMG"                       application/x-apple-diskimage
put "$PLATFORM/latest/Grabi.dmg.sha256" "$STAGE/Grabi-$V.dmg.sha256" text/plain
put "$PLATFORM/latest.json"             "$STAGE/latest.json"         application/json

# 4. End-to-end check: what the CDN serves is byte-for-byte what was uploaded
sleep 5
REMOTE_SHA=$(curl -fsSL "https://dl.grabi.net/$PLATFORM/v$V/Grabi-$V.dmg" | shasum -a 256 | awk '{print $1}')
[ "$REMOTE_SHA" = "$SHA" ] || { echo "Remote SHA does NOT match"; exit 1; }
echo "✅ dl.grabi.net serves v$V with a verified SHA-256."

# 5. Tag + GitHub Release
git tag "v$V" 2>/dev/null || true
git push origin "v$V"
gh release create "v$V" "$DMG" "$STAGE/SHA256SUMS.txt" \
  --title "Grabi $V (macOS)" \
  --notes "Signed DMG (interim \"Grabi Dev\" identity, hardened runtime).

**Recommended download:** https://dl.grabi.net/macos/v$V/Grabi-$V.dmg
**SHA-256:** \`$SHA\`

Verify the download with: \`shasum -a 256 Grabi-$V.dmg\`" \
  2>/dev/null || echo "(release v$V already existed on GitHub)"
echo "✅ Release v$V published."
