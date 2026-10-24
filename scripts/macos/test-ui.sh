#!/usr/bin/env bash
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BM_RESULT="$BM_ROOT/build/qa/ui-$(date +%Y%m%d-%H%M%S).xcresult"
mkdir -p "$BM_ROOT/build/qa"
BM_LOCK_STATE="$(ioreg -n Root -d1 | rg -o 'CGSSessionScreenIsLocked"=[A-Za-z]+' || true)"
if [[ "$BM_LOCK_STATE" == *'CGSSessionScreenIsLocked"=Yes'* ]]; then
  echo "Unlock the Mac desktop before running UI tests." >&2
  exit 3
fi
# automationmodetool describes the unattended policy. An authenticated Xcode
# session can run UI tests while it still reports disabled; let Xcode decide.
xcodebuild -project "$BM_ROOT/apps/macos/BorderMuse.xcodeproj" -scheme BorderMuse \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$BM_ROOT/build/xcode" -resultBundlePath "$BM_RESULT" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  test "$@"
