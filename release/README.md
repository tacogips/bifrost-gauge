# bifrost-gage Release Artifacts

This directory is the local staging area for packaged `bifrost-gage` macOS app
artifacts.

Build an Apple Silicon app zip for the Homebrew Cask:

```bash
task package-macos-app -- <version>
```

This writes:

```text
release/bifrost-gage_<version>_aarch64.app.zip
release/bifrost-gage_<version>_aarch64.app.zip.sha256
```

The zip contains `bifrost-gage.app`. For public macOS distribution, publish a
Developer ID signed and notarized artifact, then update the Homebrew Cask SHA in
`tacogips/homebrew-tap`.

Expected GitHub Release asset name:

```text
bifrost-gage_<version>_aarch64.app.zip
```
