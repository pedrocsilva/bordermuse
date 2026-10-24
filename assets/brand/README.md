# Border Muse brand assets

Canonical symbol, wordmark and app-icon artwork for Border Muse.

- `symbol-ink.svg` / `symbol-paper.svg`: transparent one-color symbol.
- `logo-ink.svg` / `logo-paper.svg`: horizontal symbol and editable wordmark.
- `app-icon.svg`: vector master for the light macOS icon.
- `app-icon-1024.png`: raster master used to build the native icon set.
- `manifest.json`: asset metadata and file hashes.

The symbol uses a portrait mat and narrow diagonal corner opening. Preserve
the proportions and cut.
Ink is `#171717`; paper is `#FFFFFF`. The native app uses SF Pro, neutral light/dark
surfaces and a blue accent. UI tokens live in
`apps/macos/BorderMuse/Workspace/WorkspaceStyle.swift`. The wordmark uses Helvetica Neue with system
fallbacks; fonts are neither embedded nor distributed.

Generate the native app resource from the raster master:

```bash
swift scripts/macos/make-icon.swift build/BorderMuse.iconset
iconutil --convert icns --output apps/macos/BorderMuse/Resources/AppIcon.icns build/BorderMuse.iconset
```

The artwork is original project artwork under the repository's MIT license.
It is brand geometry, separate from photo export geometry.
