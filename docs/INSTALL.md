# Install Border Muse

## macOS

Requires macOS 14+. Check [GitHub releases](https://github.com/pedrocsilva/bordermuse/releases)
for available builds and their source revision. Downloads may predate current
source; they remain experimental.

1. Download a DMG or ZIP and `SHA256SUMS.txt` from the same release.
2. Compare `shasum -a 256 /path/to/download.dmg` (or `.zip`) with the published hash.
3. Open the DMG and copy **Border Muse.app** to Applications, or move the unzipped app there.

Current packaging uses ad hoc signing, without Developer ID or notarization.
macOS may block the download. If you trust the source, use the system's Open
Anyway option under Privacy & Security after the first launch attempt. Building
from source is an alternative; see [Development](DEVELOPING.md).

Source photos and existing output files are preserved. Exports currently use
white borders and retain source JPEG/PNG/single-image TIFF format. JPEG is
re-encoded when rendered. Metadata is kept by default and may include location.
RAW, HEIC, HDR and animated/multipage inputs are unsupported.

Report problems with source/release revision, macOS version, Mac architecture,
input format and reproduction steps. Check personal photos and metadata before
sharing them. Native accessibility and independent installation validation remain
part of [the delivery plan](PLAN.md).

## Windows development builds

Windows is in development with full macOS feature parity as the acceptance target.
There is no Windows release yet. For a tested development revision, open its
[Windows parity workflow](https://github.com/pedrocsilva/bordermuse/actions/workflows/windows.yml)
and download the `BorderMuse-windows-development-x64` artifact from a successful run.
Extract the complete ZIP to a folder and run `BorderMuse.exe` there. Keep the
runtime files and `Legal` folder together; the executable alone is insufficient.
The app includes its .NET and Windows App SDK runtimes and is unsigned.
`BorderMuse-build.json` identifies the source commit, app version, architecture
and bundled .NET versions; `SHA256SUMS.txt` lists the packaged file hashes.

The automated workflow uses Windows x64. Narrator, real drag/drop and file panels,
display scaling/high contrast, visual photo review and clean-machine installation
still need hands-on validation. See [Windows parity](WINDOWS_PARITY.md) before
interpreting a development build as release-ready. Build from source with the
[Windows development instructions](DEVELOPING.md#windows-development).
