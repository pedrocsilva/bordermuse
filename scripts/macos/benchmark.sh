#!/usr/bin/env bash
set -euo pipefail
BM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export BORDERMUSE_BENCHMARK=1
BM_REPORT="${1:-$BM_ROOT/build/qa/performance.json}"
case "$BM_REPORT" in /*) ;; *) BM_REPORT="$BM_ROOT/$BM_REPORT" ;; esac
export BORDERMUSE_BENCHMARK_REPORT="$BM_REPORT"
export BORDERMUSE_BENCHMARK_FIXTURES="$BM_ROOT/build/qa/benchmark-fixtures"
swift "$BM_ROOT/scripts/macos/make-benchmark-fixtures.swift" "$BORDERMUSE_BENCHMARK_FIXTURES"
swift test -c release --package-path "$BM_ROOT/apps/macos" --filter PerformanceBenchmarks
