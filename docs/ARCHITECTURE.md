# Architecture

Border Muse is a product family built around consistent framing geometry. The
macOS app and CLI are consumers; other applications can use geometry with their
own renderers.

```text
apps/macos ─┬─> packages/imaging-apple ─> geometry-swift
apps/cli ───┘
external editors / examples ───────────> geometry-swift
```

## Boundaries and layout

| Location | Responsibility |
| --- | --- |
| `Package.swift` | Public Swift geometry product, usable through this repository URL |
| `packages/geometry-swift/Sources/` | Positive dimensions, ratios, exact canvas/margin calculation; Foundation only |
| `geometry/` | Normative Python reference, one measured JSON corpus, Python/Swift conformance checks |
| `packages/imaging-apple/` | macOS image decoding, orientation, resizing, compositing, color, metadata and encoding |
| `apps/macos/` | SwiftUI workspace, sessions, presets, file access and batch export |
| `apps/cli/` | Command-line file export through the Apple adapter |
| `examples/swift-editor/` | Independent consumer of the geometry product, without app/rendering dependencies |

The root Swift package has no Apple imaging or app dependencies. Conformance
fixtures are bundled as test resources from the canonical JSON, without searching
parent directories. Python remains the normative arithmetic reference. The Apple
adapter is a local package; external geometry consumers do not need it.

## Data flow

1. The host decodes and orients the image, then deliberately resizes if requested.
2. Geometry takes the prepared integer dimensions, target ratio and thickness.
3. It returns canvas dimensions and four margins. The photo begins at
   `(left, top)` in a canvas coordinate system whose origin is the top left.
4. The host fills the canvas, places the content and encodes according to its own
   format, color and metadata policy. Renderers with a bottom-left origin convert
   coordinates at this boundary.

Identical prepared dimensions and settings must produce identical geometry.
Matching geometry does not establish identical resize filters, color or encoded
bytes. Version output behavior explicitly; app/package versions are separate
from the geometry contract. See [the specification](GEOMETRY_SPEC.md).

## Review findings and decisions

- Geometry and macOS rendering previously shared a package boundary. They now
  have separate dependency graphs, with geometry importable at the repository root.
- Content reduction now belongs to the imaging adapter; rounding in that stage
  cannot change the canvas formula.
- Apps and CLI live together under `apps/`; language implementations and platform
  rendering stay under `packages/`. Add folders when implementations exist.
- Shared fixtures remain language-neutral; keep measurements and confirmed
  corrections intact as APIs and package names evolve.
- The macOS session and image processor are cohesive enough for the current
  scope. Revisit their decomposition when concrete behavior needs it.

## Next integration boundary

Choose the first external editor and inspect its language, renderer, coordinate
system and export pipeline. Prefer the current Swift package when applicable;
otherwise add a small native port running the same corpus. Decide on a compiled
bridge only if a real integration justifies its build/distribution cost.

Linux conformance and an independent consumer are configured in CI. macOS app
and rendering checks remain separate. Windows/iOS support and non-Swift packages
need their own validation before being advertised.
