#!/usr/bin/env bash
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
bash "$BM_ROOT/scripts/macos/build.sh" "${1:-native}"
BM_STAGE="$(mktemp -d)"
trap 'rm -rf "$BM_STAGE"' EXIT
ditto "$BM_ROOT/build/macos/BorderMuse.app" "$BM_STAGE/BorderMuse.app"
ln -s /Applications "$BM_STAGE/Applications"
BM_DMG="$BM_ROOT/build/macos/BorderMuse-local.dmg"
rm -f "$BM_DMG"
hdiutil create -volname BorderMuse -srcfolder "$BM_STAGE" -format UDZO "$BM_DMG"
echo "Local testing DMG (not notarized): $BM_DMG"
