# macOS releases

The [prerelease workflow](../.github/workflows/release.yml) validates source,
runs CI, builds a universal Apple silicon/Intel app, verifies extracted artifacts
and publishes only on version-tag pushes. Stable publication is disabled.
Current packaging is ad hoc signed, without Developer ID or notarization.

## Prepare and publish

1. Complete checks for the intended revision and review the [delivery gates](PLAN.md).
2. Update `CHANGELOG.md`, `CFBundleShortVersionString` and `CFBundleVersion` in
   `apps/macos/BorderMuse/Resources/Info.plist`. Commit to `main`.
3. Tag with a new annotated `vX.Y.Z-alpha.N`, `-beta.N` or `-rc.N` (N starts at 1),
   matching the numeric app version, and push that tag.

The source must be clean and belong to `main`. Do not move or reuse published
tags. Failed checks prevent publication; existing releases are not overwritten.
Only the publication job has repository write permission.

To exercise tests and packaging without publishing:

```bash
gh workflow run release.yml --ref main
```

Manual runs use a synthetic `X.Y.Z-alpha.0` version and create an Actions artifact,
without a Git tag or GitHub Release. Review the actual run result before claiming
success. On macOS, local universal packaging uses:

```bash
bash scripts/macos/package-release.sh VERSION universal
bash scripts/release/verify-app.sh build/releases/VERSION VERSION
```

Outputs include ZIP, DMG, SHA-256 checksums and a manifest recording source commit,
architectures, signing status and geometry contract. Packaging includes the MIT
license and checks signature, sandbox entitlements, macOS minimum and US English
resources. Toolchains can change binary bytes; byte reproducibility is not promised.

Developer ID signing, notarization and stapling are deferred. Experimental builds
retain ad hoc signing and document the installation prompts. Independent
downloaded-app checks remain a release gate. See [installation](INSTALL.md).
