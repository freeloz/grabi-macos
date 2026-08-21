#!/bin/zsh
# Builds and packages Grabi as a .app in dist/.
#
# Why a bundle? macOS attributes the TCC permissions (screen, camera,
# microphone) to the process's "responsible" app: a bare binary launched
# from Terminal inherits Terminal's permissions. With the bundle, the
# permissions belong to Grabi, like any normal app.
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

# SPM resource bundles (each target's Localizable.strings): Bundle.module
# looks for them in the .app's Contents/Resources.
BUILD_DIR=".build/$CONFIG"
for b in "$BUILD_DIR"/Record_*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done
# Localized usage descriptions (TCC)
for l in Support/InfoPlist/*.lproj; do
  mkdir -p "$APP/Contents/Resources/$(basename "$l")"
  cp "$l/InfoPlist.strings" "$APP/Contents/Resources/$(basename "$l")/"
done

# Sparkle.framework (auto-updates) lives in Contents/Frameworks.
scripts/embed-sparkle.sh "$APP"

# Signing: with the stable local identity "Grabi Dev" if it exists (TCC
# permissions survive rebuilds); otherwise ad-hoc (screen permissions are
# lost on every new build).
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Grabi Dev"; then
  codesign --force --sign "Grabi Dev" "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "Grabi Dev" "$APP"
  echo "Signed with stable identity: Grabi Dev"
else
  codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign - "$APP"
  echo "⚠️  Ad-hoc signature: macOS will re-ask for the screen permission after each rebuild"
fi

echo "✅ Done: $APP"
echo "Open it with: open $APP"
