#!/usr/bin/env bash
# Experimental distribution only: ad hoc signed, never notarized by this script.
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BM_VERSION="${1:-0.1.0-alpha.1}"
BM_MODE="${2:-universal}"
if [[ ! "$BM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "Usage: $0 VERSION [native|universal]" >&2
  exit 2
fi
bash "$BM_ROOT/scripts/macos/build.sh" "$BM_MODE"
BM_OUTPUT="$BM_ROOT/build/releases/$BM_VERSION"
mkdir -p "$BM_OUTPUT"
BM_STAGE="$(mktemp -d)"
trap 'rm -rf "$BM_STAGE"' EXIT
BM_APP="$BM_STAGE/Border Muse.app"
ditto "$BM_ROOT/build/macos/BorderMuse.app" "$BM_APP"
mkdir -p "$BM_APP/Contents/Resources/Legal"
cp "$BM_ROOT/LICENSE" "$BM_APP/Contents/Resources/Legal/LICENSE"
BM_EXECUTABLE="$BM_APP/Contents/MacOS/BorderMuse"
# SwiftPM release builds may retain debug/source paths. Strip before re-signing.
strip -S -x "$BM_EXECUTABLE"
codesign --force --sign - --options runtime \
  --entitlements "$BM_ROOT/apps/macos/BorderMuse/Resources/BorderMuse.entitlements" "$BM_APP"
codesign --verify --strict "$BM_APP"
export BM_VERSION BM_ROOT BM_OUTPUT BM_EXECUTABLE BM_MODE
python3 - <<'PY'
import json, os, plistlib, subprocess
from pathlib import Path
root=Path(os.environ['BM_ROOT'])
assert b'/Users/' not in Path(os.environ['BM_EXECUTABLE']).read_bytes(), 'Machine path remains in release binary'
info=plistlib.loads((root/'apps/macos/BorderMuse/Resources/Info.plist').read_bytes())
version=os.environ['BM_VERSION']
assert version.split('-')[0] == info['CFBundleShortVersionString'], 'Release/app version mismatch'
architectures=subprocess.check_output(['lipo','-archs',os.environ['BM_EXECUTABLE']],text=True).split()
if os.environ['BM_MODE'] == 'universal':
    assert set(architectures) == {'arm64','x86_64'}, 'Universal app must contain both architectures'
manifest={
    'product':'Border Muse', 'version':version, 'appVersion':info['CFBundleShortVersionString'],
    'build':info['CFBundleVersion'], 'minimumMacOS':info['LSMinimumSystemVersion'],
    'architectures':architectures,
    'signature':'ad-hoc', 'notarized':False, 'geometryContract':'bordermuse-geometry-v1',
    'sourceCommit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),
}
(Path(os.environ['BM_OUTPUT'])/'release-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
cat > "$BM_STAGE/READ ME.txt" <<'NOTICE'
Border Muse — experimental macOS build

Requires macOS 14 or later. Copy Border Muse.app to Applications.
This build is ad hoc signed, not Developer ID signed or notarized. macOS may
block it. Read installation instructions and verify checksums before installing:
https://github.com/pedrocsilva/bordermuse/blob/main/docs/INSTALL.md

The source and original artwork are MIT licensed. LICENSE is included in the app.
Source, known limitations and feedback: https://github.com/pedrocsilva/bordermuse
NOTICE
BM_STEM="BorderMuse-$BM_VERSION-macos-$BM_MODE"
ditto -c -k --sequesterRsrc --keepParent "$BM_APP" "$BM_OUTPUT/$BM_STEM.zip"
ln -s /Applications "$BM_STAGE/Applications"
hdiutil create -ov -volname "Border Muse" -srcfolder "$BM_STAGE" -format UDZO "$BM_OUTPUT/$BM_STEM.dmg"
hdiutil verify "$BM_OUTPUT/$BM_STEM.dmg"
(
  cd "$BM_OUTPUT"
  shasum -a 256 "$BM_STEM.zip" "$BM_STEM.dmg" release-manifest.json > SHA256SUMS.txt
)
echo "Experimental release artifacts: $BM_OUTPUT"
