---
name: macos-cask-local-release
description: >-
  Use when releasing bifrost-gauge or another macOS Homebrew Cask from this repo,
  especially when building app zip artifacts, handling Apple signing/notarization
  credentials, publishing GitHub release assets, or updating tacogips/homebrew-tap.
  Follows the chilla local-release model: Apple certificate material stays in the
  local keychain/password manager and is never stored in GitHub Actions secrets or
  committed files.
---

# macOS Cask Local Release

Use this skill for macOS Cask releases from this repository.

## Credential Policy

- Keep Apple certificate material local. Do not add `APPLE_CERTIFICATE` or certificate passwords to GitHub Actions, repository files, release notes, or logs.
- Load release credentials from the local password-manager/kinko workflow and local keychain, following the local chilla release script model.
- Required environment variables for signed/notarized releases:
  - `APPLE_SIGNING_IDENTITY`
  - `APPLE_ID`
  - `APPLE_PASSWORD`
  - `APPLE_TEAM_ID`
- Before using them, verify only presence, never values:

```bash
for name in APPLE_SIGNING_IDENTITY APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID; do
  [ -n "${!name:-}" ] && echo "$name=set" || echo "$name=missing"
done
security find-identity -v -p codesigning | grep -F -- "$APPLE_SIGNING_IDENTITY" >/dev/null
```

## Release Flow

1. Verify the working tree and avoid committing unrelated user changes.
2. Build the app with Xcode Swift from `nix develop`; do not use Nixpkgs Swift.
3. Ensure the app bundle contains:
   - `Contents/Info.plist`
   - `Contents/MacOS/bifrost-gauge`
   - `Contents/Resources/AppIcon.icns`
   - `CFBundleIconFile` set to `AppIcon`
4. For signed releases, sign with Developer ID from the local keychain, notarize with `xcrun notarytool`, staple, and validate:

```bash
codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
```

5. Zip with `ditto -c -k --keepParent`.
6. Publish the asset to a public release location usable by Homebrew. If the source repo is private, host the Cask asset in `tacogips/homebrew-tap` releases.
7. Update `Casks/bifrost-gauge.rb` with the new version, URL, and SHA.
8. Verify:

```bash
brew fetch --cask tacogips/tap/bifrost-gauge
HOMEBREW_NO_GITHUB_API=1 brew audit --cask tacogips/tap/bifrost-gauge
```

## Safety Gates

- Run a precommit safety check before commits and pushes.
- Do not quote secret values in final output.
- If `brew audit --online` fails with GitHub keychain `Bad credentials`, use `HOMEBREW_NO_GITHUB_API=1` and report that the online audit is blocked by local GitHub credentials, not the Cask.
