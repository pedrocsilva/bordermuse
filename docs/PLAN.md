# Delivery plan

Three tracks share geometry compatibility. Windows targets the complete macOS
alpha.2 feature set without requiring further macOS features first.

## A. Validate and polish macOS

1. Build the current source on macOS and run the automated suite. Review the
   actual app at its minimum window size and in light/dark mode. Exercise import
   panels, drag/drop, Finder opening, keyboard focus, photo navigation and VoiceOver.
2. Exercise empty/loading states, invalid settings, denied file access, export
   progress, per-file errors/retry, cancellation and quitting during export.
   Record reproducible issues and fix blockers before cosmetic refinements.
3. Export a representative real photo batch: JPEG/PNG/TIFF, orientations,
   sRGB/Display P3, 8/16-bit where supported, metadata kept/removed and optional
   resizing. Inspect in Preview and the source editor. Verify dimensions/margins,
   color, metadata and that originals/existing outputs remain intact.
4. Run the benchmark with varied resolutions and batch sizes. Record time,
   peak memory, hardware and responsiveness; fix observed problems and rerun.
5. Test a downloaded universal build on independent Apple silicon and Intel Macs.
   Keep the current ad hoc signing status visible in download instructions.
   Paid Developer ID signing, notarization and stapling are deferred.

**Done:** blocking issues are resolved; dated results identify source revision,
macOS/hardware, tested flows and remaining limitations. Real photo checks,
accessibility, performance and installation have evidence beyond automated builds.
Keep personal photo data out of Git.

## B. Make the first external integration work

1. Select one partner editor. Establish its language/platform, build system,
   rendering/export pipeline, expected settings and representative input/output.
   This is the next missing input; do not assume both editors use the same stack.
2. Use the root Swift package or implement the smallest required language port.
   Run all 20 measured cases plus integer-boundary, invalid-input and overflow
   checks appropriate to that language. Keep resize and fill policies in the host.
3. Integrate preview and export through the same geometry call. Verify matching
   prepared dimensions/settings produce the same margins and canvas in both paths.
4. Add an executable example in that stack and test consumption outside this
   checkout. Document installation, API, coordinate mapping, errors and licensing.
5. Pin a reviewed package version/revision in the partner editor. Collect feedback,
   settle the small public API, then use the second editor to check portability.

**Done:** one real editor imports the package, passes shared conformance, and
exports correctly through its own renderer without depending on the macOS app.
A maintainer can reproduce the integration from the documentation.

## C. Deliver Windows feature parity

1. Run the unchanged 20-case corpus and boundary checks through portable .NET.
2. Verify WIC output for orientation, precision, color, metadata and original/output
   protection, using synthetic shared fixtures and representative real photos.
3. Exercise the native WinUI workflow, cancellation/retry, keyboard, Narrator,
   drag/drop, high contrast and display scaling.
4. Test a complete self-contained build on an independent Windows PC before
   publishing a Windows alpha. Keep unverified gates visible in
   [Windows parity](WINDOWS_PARITY.md).

**Done:** the full macOS feature checklist has Windows evidence and a reproducible
installable artifact; a successful compile alone does not establish parity.

## Current baseline and gates

macOS and Windows have native workspaces and separate rendering adapters over
portable geometry. Shared conformance, format/depth/color/metadata tests,
public-photo comparisons and native Windows cancellation/retry and contrast-mode
checks have passed. Dated Windows evidence is in [the parity checklist](WINDOWS_PARITY.md).

Remaining desktop release gates are hands-on accessibility, full keyboard and
file-panel/drag-drop interactions, display scaling, visual photo review and
independent downloaded-app installation. A partner-editor integration also needs
a selected host; it is separate from shipping the desktop apps.

Before claiming readiness: check CI for the exact revision, perform the manual
checks above and compare packaged artifacts with their manifest. Existing release
or audit claims are not substitutes for validating changed source.

## Longer term

After these tracks, prioritize from actual usage: additional border colors,
watched folders, Finder actions and richer CLI workflows. Evaluate iOS and web independently. Share geometry/conformance across all implementations;
share rendering only where platform requirements justify it. Package API stability
and reliable distribution matter before broad platform promises.
