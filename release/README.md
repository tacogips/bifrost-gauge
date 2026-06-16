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

For a trusted public artifact, run the package task with notarization enabled on
the local macOS release machine:

```bash
BIFROST_GAUGE_NOTARIZE=1 task package-macos-app -- <version>
```

The script reads `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_PASSWORD`, and
`APPLE_TEAM_ID` from the environment. If they are not set, it uses `kinko export`
from this repository path, or from `BIFROST_GAUGE_SIGNING_ENV_DIR` when set. The
Developer ID certificate must already be available in the local keychain.

Expected GitHub Release asset name:

```text
bifrost-gauge_<version>_aarch64.app.zip
```
