# Development and verification

Python 3.9+ runs the reference and release-tool tests without dependencies:

```bash
python3 -m unittest discover -s geometry -p 'test_*.py'
python3 -m unittest discover -s scripts/release -p 'test_*.py'
```

Swift 5.9+ builds the portable geometry package and independent consumer:

```bash
swift test
swift run --package-path examples/swift-editor
```

On macOS with full Xcode (app minimum macOS 14; renderer/CLI macOS 12):

```bash
bash scripts/macos/test.sh
bash scripts/macos/build.sh
open apps/macos/BorderMuse.xcodeproj
swift build --package-path apps/cli -c release
```

The Xcode scheme and executable are `BorderMuse`. Build a universal app with
`bash scripts/macos/build.sh universal`. The CLI executable is `bordermuse`;
use `swift run --package-path apps/cli bordermuse --help` for options.
Scripts select `/Applications/Xcode.app` when present without global changes.

## Verification boundaries

- Root Swift/Python tests compare all 20 measured canvases and four margins;
  boundary checks cover arithmetic beyond the measured sample.
- Apple adapter tests/verification generate synthetic images for orientation,
  formats, depth, color, metadata, resizing and output protection.
- App tests cover sessions, export behavior and native presentation snapshots.
- `bash scripts/macos/test-ui.sh` needs an unlocked desktop and Xcode automation
  permission. It does not replace manual VoiceOver and interaction review.
- `bash scripts/macos/benchmark.sh` records generated-image performance under
  `build/qa/`; use real batches locally as well.
- `bash scripts/macos/test-sandbox.sh` probes the signed app's file entitlements
  after a build. It needs macOS and is separate from ordinary unit tests.

CI runs portable Swift on Linux and macOS app/renderer builds on Apple silicon
and Intel. `BORDER_MUSE_SKIP_RENDER_TESTS=1` skips two snapshot/render checks on
hosted Intel runners with unavailable Metal; the remaining tests still run.
Manual and independent installation checks are tracked in [the plan](PLAN.md).

## App and artwork conventions

App-owned strings live in `en-US.lproj/Localizable.strings`. Presets use the
app's Application Support directory under `BorderMuse/presets-v1.json`.
Use native macOS controls and system typography; UI colors are defined in
`apps/macos/BorderMuse/Workspace/WorkspaceStyle.swift`. Keep preview appearance
separate from export fill. Brand artwork and icon generation are in
[assets/brand](../assets/brand/README.md).
