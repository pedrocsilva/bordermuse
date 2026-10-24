# Border Muse

- Border Muse is the brand; use `BorderMuse` in Swift names and `bordermuse` in CLI names.
- Keep geometry portable. Apps and rendering adapters depend on it, never the reverse.
- Before geometry changes, read [the specification](docs/GEOMETRY_SPEC.md). Preserve exact arithmetic, symmetric margins and all 20 measured cases. Orientation, resizing and fill color are separate concerns. Discuss output changes before implementing them.
- Preserve fixture inputs, outputs, filenames, hashes and confirmed corrections. New ports must run the shared conformance cases.
- Preserve original photos and existing output files. Use synthetic test images; do not commit personal photos, metadata, logs or credentials.
- Edit app-owned US English text in `resources/strings/en-US.json`. CI generates platform catalogs before building; for local builds run `python3 scripts/localization/generate.py`. Do not edit generated catalogs directly. System dialogs follow the OS.
- Run the relevant checks in [Development](docs/DEVELOPING.md). Report what actually ran and any remaining validation.
