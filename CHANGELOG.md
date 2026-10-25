# Changelog

## Unreleased

- Built-in Mobile reference geometry preset: 5:4, thickness 10, photo up to 2,048 px
  before the border, preserving quality/metadata choices. Original and Custom
  sizes remain available; the final canvas may exceed the photo-size limit.
- Native Apple/Windows tests run full-size synthetic inputs through reduction and
  rendering against all 20 unchanged measured Mobile geometries and four margins.

- Windows development app with portable .NET geometry/core, native WinUI workspace
  and WIC image rendering. Targets the complete macOS feature set; manual
  accessibility, interaction and independent installation gates remain open.
- Shared US English string catalog generates both native app resources in CI.
- Cleaner action labels and Windows menus, compact export settings and validation
  that remains visible at minimum window height.
- Original, up to 2,048 px and Custom photo-size choices on both platforms, applied
  before the border without enlarging smaller photos.
- Scale-aware Windows reduction preserves 16-bit precision and suppresses aliasing.
- Windows development packages include source/runtime metadata and file checksums;
  CI checks bundled runtime loading, live cancellation, retry and contrast themes.
- Windows menu quit now shares the export-confirmation path with the window
  close button, preventing an active batch from being abandoned without a choice.
- Opt-in public-photo comparison checks both renderers at original and reduced
  sizes, with metadata retained and removed.

## 0.1.0-alpha.2 — 2026-10-24

- Native macOS photo framing with preview, presets and batch export.
- Portable Swift geometry package, Python reference and shared measured fixtures.
- Apple image renderer, developer CLI and independent Swift integration example.

Local validation covered automated conformance and rendering checks, batch export,
cancellation and quitting during export, presets, output preservation, public-photo
orientation/color/metadata comparisons, and a packaged app copied outside the checkout.

Manual VoiceOver, drag/drop, complete keyboard navigation and live minimum-window/
appearance checks remain pending. Independent downloaded-app installation checks,
including Intel and macOS 14, are also pending. Current builds are ad hoc signed
and are not Developer ID signed or notarized; macOS may block installation.

The app and package API are experimental. See [the plan](docs/PLAN.md) for validation
and [release guidance](docs/RELEASE.md) for distribution requirements.
