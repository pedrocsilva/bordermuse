#!/usr/bin/env bash
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
python3 -m unittest discover -s "$BM_ROOT/geometry" -p 'test_*.py'
swift test --package-path "$BM_ROOT"
swift run --package-path "$BM_ROOT/packages/imaging-apple" bordermuse-verify "$BM_ROOT"
swift test --package-path "$BM_ROOT/packages/imaging-apple"
swift test --package-path "$BM_ROOT/apps/macos"
