#!/bin/zsh
# Publishes a Grabi release for macOS, end to end:
#   1. Builds and signs the DMG (make-interim-release.sh).
#   2. Computes the SHA-256 and signs the update with the Sparkle EdDSA key
#      (read from the login Keychain — see docs/RELEASING.md; never on disk).
#   3. Uploads everything to R2 (dl.grabi.net) versioned + updates "latest".
#   4. Regenerates and uploads appcast.xml (the canonical update feed;
#      latest.json is derived from the same data for the website).
#   5. Verifies what the CDN serves (SHA byte-for-byte + appcast consistency).
#   6. Creates the GitHub Release with the DMG and checksums attached.
#
# Usage:  ./scripts/publish-release.sh
#
# Per-release notes are REQUIRED at releases/v<version>/notes.en.html
# (optional localized variants: notes.<lang>.html for es/pt/fr/de).
#
# Requires: "Grabi Dev" signing identity + Sparkle EdDSA private key in the
# keychain, an authenticated gh CLI, and Cloudflare credentials
# (CLOUDFLARE_API_TOKEN in the environment, or a wrangler session).
set -euo pipefail
cd "$(dirname "$0")/.."

export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-0ef61977f8d1fc1e483034fdbde55f9e}"
BUCKET="grabi-releases"
PLATFORM="macos"
BASE_URL="https://dl.grabi.net/$PLATFORM"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
BUILDNUM=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" Support/Info.plist)
NOTES_DIR="releases/v$V"
[ -f "$NOTES_DIR/notes.en.html" ] || {
  echo "Missing $NOTES_DIR/notes.en.html — write the release notes first."; exit 1; }

# 1. Build + signing
./make-interim-release.sh
DMG="dist/Grabi-$V.dmg"
[ -f "$DMG" ] || { echo "$DMG does not exist"; exit 1; }
[ -x "$SIGN_UPDATE" ] || { echo "sign_update not found — run 'swift build' first"; exit 1; }

# 2. Checksums + EdDSA update signature (key comes from the login Keychain)
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(stat -f %z "$DMG")
ED_ATTRS=$($SIGN_UPDATE "$DMG")   # → sparkle:edSignature="…" length="…"
ED_SIG=$(echo "$ED_ATTRS" | sed -E 's/.*edSignature="([^"]+)".*/\1/')
[ -n "$ED_SIG" ] || { echo "EdDSA signing failed"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
printf '%s\n' "$SHA" > "$STAGE/Grabi-$V.dmg.sha256"
printf '%s  Grabi-%s.dmg\n' "$SHA" "$V" > "$STAGE/SHA256SUMS.txt"

# 3. latest.json (for the website; derived from the same release data)
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

# 4. appcast.xml: fetch the current feed and prepend this release's <item>.
#    The feed on R2 is the single canonical update source.
curl -fsSL "$BASE_URL/appcast.xml" -o "$STAGE/appcast-old.xml" 2>/dev/null || true
PUBDATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
/usr/bin/env python3 - "$V" "$BUILDNUM" "$SIZE" "$ED_SIG" "$PUBDATE" "$NOTES_DIR" \
  "$STAGE/appcast-old.xml" "$STAGE/appcast.xml" <<'PY'
import sys, os, html, xml.dom.minidom
v, build, size, sig, pubdate, notes_dir, old_path, out_path = sys.argv[1:9]

descs = []
for lang in ["en", "es", "pt", "fr", "de"]:
    p = os.path.join(notes_dir, f"notes.{lang}.html")
    if os.path.exists(p):
        body = open(p).read().strip()
        attr = "" if lang == "en" else f' xml:lang="{lang}"'
        descs.append(f"      <description{attr}><![CDATA[\n{body}\n      ]]></description>")

item = f"""    <item>
      <title>Grabi {v}</title>
      <pubDate>{pubdate}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
{chr(10).join(descs)}
      <enclosure url="https://dl.grabi.net/macos/v{v}/Grabi-{v}.dmg"
                 length="{size}" type="application/octet-stream"
                 sparkle:edSignature="{sig}"/>
    </item>"""

MARK = "<!-- ITEMS -->"
skeleton = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Grabi</title>
    <link>https://dl.grabi.net/macos/appcast.xml</link>
    <language>en</language>
    {MARK}
  </channel>
</rss>"""

feed = open(old_path).read() if os.path.exists(old_path) else skeleton
if MARK not in feed:
    sys.exit("existing appcast lacks the ITEMS marker — refusing to guess")
if f"<sparkle:shortVersionString>{v}<" in feed:
    sys.exit(f"version {v} already in the appcast — bump the version first")
feed = feed.replace(MARK, MARK + "\n" + item, 1)
open(out_path, "w").write(feed)
xml.dom.minidom.parse(out_path)  # hard fail on malformed XML
print(f"appcast: added {v} (build {build}), {feed.count('<item>')} item(s) total")
PY

# 5. Upload to R2 (dl.grabi.net)
put() { npx -y wrangler r2 object put "$BUCKET/$1" --file "$2" --content-type "$3" --remote; }
put "$PLATFORM/v$V/Grabi-$V.dmg"        "$DMG"                       application/x-apple-diskimage
put "$PLATFORM/v$V/Grabi-$V.dmg.sha256" "$STAGE/Grabi-$V.dmg.sha256" text/plain
put "$PLATFORM/v$V/SHA256SUMS.txt"      "$STAGE/SHA256SUMS.txt"      text/plain
put "$PLATFORM/latest/Grabi.dmg"        "$DMG"                       application/x-apple-diskimage
put "$PLATFORM/latest/Grabi.dmg.sha256" "$STAGE/Grabi-$V.dmg.sha256" text/plain
put "$PLATFORM/latest.json"             "$STAGE/latest.json"         application/json
put "$PLATFORM/appcast.xml"             "$STAGE/appcast.xml"         application/xml

# 6. End-to-end checks: the CDN must serve exactly what we published.
sleep 5
REMOTE_SHA=$(curl -fsSL "$BASE_URL/v$V/Grabi-$V.dmg" | shasum -a 256 | awk '{print $1}')
[ "$REMOTE_SHA" = "$SHA" ] || { echo "Remote SHA does NOT match"; exit 1; }
REMOTE_CAST=$(curl -fsSL "$BASE_URL/appcast.xml")
echo "$REMOTE_CAST" | grep -q "sparkle:edSignature=\"$ED_SIG\"" || {
  echo "Remote appcast is missing this release's EdDSA signature"; exit 1; }
echo "$REMOTE_CAST" | grep -q "<sparkle:shortVersionString>$V<" || {
  echo "Remote appcast is missing version $V"; exit 1; }
echo "✅ dl.grabi.net serves v$V: SHA-256 verified, appcast consistent."

# 7. Tag + GitHub Release
git tag "v$V" 2>/dev/null || true
git push origin "v$V"
gh release create "v$V" "$DMG" "$STAGE/SHA256SUMS.txt" \
  --title "Grabi $V (macOS)" \
  --notes "Signed DMG (interim \"Grabi Dev\" identity, hardened runtime).
Existing installs with Grabi ≥ 0.1.4 update themselves via Sparkle.

**Recommended download:** https://dl.grabi.net/macos/v$V/Grabi-$V.dmg
**SHA-256:** \`$SHA\`

Verify the download with: \`shasum -a 256 Grabi-$V.dmg\`" \
  2>/dev/null || echo "(release v$V already existed on GitHub)"
echo "✅ Release v$V published."
