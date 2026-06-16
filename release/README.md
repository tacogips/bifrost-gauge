# bifrost-gauge Release Artifacts

This directory is the local staging area for packaged `bifrost-gauge` macOS app
artifacts.

Build an Apple Silicon app zip for the Homebrew Cask:

```bash
task package-macos-app -- <version>
```

This writes:

```text
release/bifrost-gauge_<version>_aarch64.app.zip
release/bifrost-gauge_<version>_aarch64.app.zip.sha256
```

The zip contains `bifrost-gauge.app`. For public macOS distribution, publish a
Developer ID signed and notarized artifact, then update the Homebrew Cask SHA in
`tacogips/homebrew-tap`.

Expected GitHub Release asset name:

```text
bifrost-gauge_<version>_aarch64.app.zip
```
