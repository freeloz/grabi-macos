#!/bin/zsh
# Embeds Sparkle.framework (from the SwiftPM binary artifact) into a Grabi
# .app bundle and points the executable's rpath at Contents/Frameworks.
#
# Grabi is NOT sandboxed, so Sparkle's XPC services (only needed inside the
# sandbox) are stripped — less to sign, less to audit.
#
# Usage: scripts/embed-sparkle.sh <path/to/Grabi.app>
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: embed-sparkle.sh <Grabi.app>}"
SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SRC" ] || { echo "Sparkle artifact not found — run 'swift build' first"; exit 1; }

mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$SRC" "$APP/Contents/Frameworks/"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

# The SwiftPM-linked binary loads @rpath/Sparkle.framework/...; inside the
# bundle that resolves via Contents/Frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/Grabi" 2>/dev/null || true  # already present on rebuilds
