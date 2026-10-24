#!/usr/bin/env bash
set -euo pipefail
BM_DIRECTORY="${1:?Pass the release directory}"
BM_VERSION="${2:?Pass the release version}"
BM_EXTRACT="$(mktemp -d)"
trap 'rm -rf "$BM_EXTRACT"' EXIT
ditto -x -k "$BM_DIRECTORY/BorderMuse-$BM_VERSION-macos-universal.zip" "$BM_EXTRACT"
BM_APP="$BM_EXTRACT/Border Muse.app"
codesign --verify --strict --verbose=2 "$BM_APP"
export BM_APP BM_VERSION
python3 - <<'PY'
import os, plistlib, re, subprocess
from pathlib import Path
app=Path(os.environ['BM_APP'])
executable=app/'Contents/MacOS/BorderMuse'
assert set(subprocess.check_output(['lipo','-archs',str(executable)],text=True).split())=={'arm64','x86_64'}
assert b'/Users/' not in executable.read_bytes(), 'Machine path in release executable'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleName']=='Border Muse' and info['LSMinimumSystemVersion']=='14.0'
assert info['CFBundleShortVersionString']==os.environ['BM_VERSION'].split('-')[0]
build_info=subprocess.check_output(['xcrun','vtool','-show-build',str(executable)],text=True)
assert re.findall(r'\bminos\s+(\S+)',build_info)==['14.0','14.0'], 'Both slices must support macOS 14'
assert (app/'Contents/Resources/Legal/LICENSE').is_file()
resources=list((app/'Contents/Resources').rglob('Localizable.strings'))
assert len(resources)==1 and resources[0].parent.name=='en-US.lproj'
entitlements=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
assert entitlements.get('com.apple.security.app-sandbox') is True
assert entitlements.get('com.apple.security.files.user-selected.read-write') is True
print('Extracted app: signature, sandbox, architectures, en-US resources and license verified')
PY
hdiutil verify "$BM_DIRECTORY/BorderMuse-$BM_VERSION-macos-universal.dmg"
