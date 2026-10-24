#!/usr/bin/env bash
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BM_MODE="${1:-native}"
BM_APP="$BM_ROOT/build/macos/BorderMuse.app"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
case "$BM_MODE" in
  native) BM_ARCH_ARGS=(--arch "$(uname -m)") ;;
  universal) BM_ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
  *) echo "usage: $0 [native|universal]" >&2; exit 2 ;;
esac
swift build --package-path "$BM_ROOT/apps/macos" -c release "${BM_ARCH_ARGS[@]}"
BM_BIN_DIR="$(swift build --package-path "$BM_ROOT/apps/macos" -c release "${BM_ARCH_ARGS[@]}" --show-bin-path)"
mkdir -p "$BM_APP/Contents/MacOS" "$BM_APP/Contents/Resources"
cp "$BM_BIN_DIR/BorderMuse" "$BM_APP/Contents/MacOS/BorderMuse"
cp "$BM_ROOT/apps/macos/BorderMuse/Resources/Info.plist" "$BM_APP/Contents/Info.plist"
# SwiftPM's resource accessor searches Bundle.main.resourceURL.
for BM_RESOURCE in "$BM_BIN_DIR"/*.bundle; do
  [ -d "$BM_RESOURCE" ] || continue
  ditto "$BM_RESOURCE" "$BM_APP/Contents/Resources/$(basename "$BM_RESOURCE")"
done
cp "$BM_ROOT/apps/macos/BorderMuse/Resources/AppIcon.icns" "$BM_APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --entitlements "$BM_ROOT/apps/macos/BorderMuse/Resources/BorderMuse.entitlements" "$BM_APP"
codesign --verify --strict "$BM_APP"
echo "Local ad hoc build (not notarized): $BM_APP"
