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

## Windows development

The Windows port targets feature parity; see [its acceptance checklist](WINDOWS_PARITY.md).
Install the .NET 10 SDK. Portable tests run on any supported .NET host:

```bash
dotnet test tests/dotnet/BorderMuse.Tests.csproj
```

On Windows (Windows 10 build 19041+ target; installation still needs validation):

```powershell
dotnet test tests/windows/BorderMuse.Windows.Tests.csproj
dotnet run --project apps/windows/BorderMuse.Windows.csproj -p:Platform=x64 -r win-x64
dotnet publish apps/windows/BorderMuse.Windows.csproj -c Release -p:Platform=x64 -r win-x64 -o build/windows/win-x64
dotnet run --project apps/cli-dotnet/bordermuse.csproj -- --help
```

CI also generates synthetic sRGB/P3 and custom-XMP inputs on macOS, then runs
`tests/windows-color` against them on Windows. Generate these locally with
`swift scripts/windows/make-color-fixtures.swift build/qa/shared-color` and set
`BORDERMUSE_COLOR_FIXTURES` to that folder for the color tests. The opt-in
`scripts/windows/test-ui.ps1` harness uses an isolated preset store and captures
the actual workspace in light/dark mode; it does not exercise assistive technology.

The Windows App SDK and .NET runtime are included in the self-contained app.
Run `BorderMuse.exe` from the complete published folder. Development ZIPs are
unsigned and are not Windows releases. The Windows CI workflow runs native codec
tests and uploads the self-contained folder for inspection.

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

Edit app text in the shared `resources/strings/en-US.json` catalog, then run:

```bash
python3 scripts/localization/generate.py
python3 -m unittest discover -s scripts/localization -p 'test_*.py'
python3 scripts/localization/generate.py --check
```

The generator writes macOS `Localizable.strings` and the embedded Windows JSON.
Both outputs are checked in for native builds; CI rejects stale or hand-edited
outputs. Installed apps need no generator or Python. Plain messages are strings;
formatted entries declare ordered, named `integer`/`string` arguments and use
`{name}` placeholders. The generator supplies Swift positional format specifiers
and .NET numeric formatting. Entries may declare platform `overrides` (Finder
versus Explorer) or `platforms` for platform-only messages. App text remains US English.

Presets use `BorderMuse/presets-v1.json` in macOS Application Support or the Windows roaming AppData folder.
Use native macOS controls and system typography; UI colors are defined in
`apps/macos/BorderMuse/Workspace/WorkspaceStyle.swift`. Keep preview appearance
separate from export fill. Brand artwork and icon generation are in
[assets/brand](../assets/brand/README.md).
