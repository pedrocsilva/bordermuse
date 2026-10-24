#!/usr/bin/env bash
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BM_QA="$BM_ROOT/build/qa/sandbox"
BM_PROBE="$BM_QA/BorderMuseSandboxProbe.app"
mkdir -p "$BM_PROBE/Contents/MacOS" "$BM_QA/unselected"
printf 'Synthetic QA fixture\n' > "$BM_QA/unselected/unselected.txt"
cat > "$BM_PROBE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bordermuse.sandbox-qa</string>
<key>CFBundleExecutable</key><string>SandboxProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun swiftc "$BM_ROOT/scripts/macos/sandbox-probe.swift" -o "$BM_PROBE/Contents/MacOS/SandboxProbe"
codesign --force --sign - --options runtime \
  --entitlements "$BM_ROOT/apps/macos/BorderMuse/Resources/BorderMuse.entitlements" "$BM_PROBE"
codesign --verify --strict "$BM_PROBE"
codesign -d --entitlements - --xml "$BM_ROOT/build/macos/BorderMuse.app" > "$BM_QA/app-entitlements.plist"
codesign -d --entitlements - --xml "$BM_PROBE" > "$BM_QA/probe-entitlements.plist"
python3 - "$BM_ROOT" "$BM_QA" <<'PY'
import pathlib, plistlib, sys
root, qa = map(pathlib.Path, sys.argv[1:])
expected = plistlib.loads((root / 'apps/macos/BorderMuse/Resources/BorderMuse.entitlements').read_bytes())
actual = plistlib.loads((qa / 'app-entitlements.plist').read_bytes())
probe = plistlib.loads((qa / 'probe-entitlements.plist').read_bytes())
assert actual == probe == expected, 'Signed app, probe, and source entitlements must match exactly'
assert set(actual) == {'com.apple.security.app-sandbox', 'com.apple.security.files.user-selected.read-write'}
PY
# No NSOpenPanel and no extension grants are passed to the probe.
"$BM_PROBE/Contents/MacOS/SandboxProbe" "$BM_QA/unselected" > "$BM_QA/report.json"
cat "$BM_QA/report.json"
test ! -e "$BM_QA/unselected/unselected-output.txt"
