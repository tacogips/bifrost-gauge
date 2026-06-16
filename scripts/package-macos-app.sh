#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/package-macos-app.sh <version>

Builds a macOS app bundle release artifact for Homebrew Cask:

  release/bifrost-gauge_<version>_aarch64.app.zip
  release/bifrost-gauge_<version>_aarch64.app.zip.sha256

The version may be passed as 0.1.0 or v0.1.0.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

raw_version="${1:-}"
if [ -z "$raw_version" ]; then
  usage >&2
  exit 1
fi

case "$raw_version" in
  v*) version="${raw_version#v}" ;;
  *) version="$raw_version" ;;
esac

case "$version" in
  *[!0-9.]* | "" | *..* | .* | *.)
    echo "error: version must look like 0.1.0 or v0.1.0" >&2
    exit 1
    ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: macOS app packaging must run on Darwin" >&2
  exit 1
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "error: this packaging script currently produces only aarch64 artifacts" >&2
  exit 1
fi

require_command codesign
require_command ditto
require_command shasum
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="$repo_root/release"
app_path="$release_dir/bifrost-gauge.app"
zip_path="$release_dir/bifrost-gauge_${version}_aarch64.app.zip"
sha_path="$zip_path.sha256"
icon_path="$repo_root/Resources/AppIcon.icns"
required_swift_version="6.3.2"
developer_dir="${BIFROST_GAUGE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sdkroot="${BIFROST_GAUGE_SDKROOT:-$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
swift_bin="${BIFROST_GAUGE_XCODE_SWIFT:-$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift}"

if [ ! -x "$swift_bin" ]; then
  echo "error: Swift toolchain not found at $swift_bin" >&2
  exit 1
fi

swift_version="$("$swift_bin" --version 2>/dev/null | head -n 1 || true)"
case "$swift_version" in
  *"Apple Swift version $required_swift_version"* | *"Swift version $required_swift_version"*) ;;
  *)
    echo "error: expected Xcode Swift $required_swift_version, got: ${swift_version:-not available}" >&2
    exit 1
    ;;
esac

rm -rf "$app_path" "$zip_path" "$sha_path"
mkdir -p "$release_dir"

DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" "$swift_bin" build -c release
build_bin_dir="$(DEVELOPER_DIR="$developer_dir" SDKROOT="$sdkroot" "$swift_bin" build -c release --show-bin-path | tail -n 1)"
executable_path="$build_bin_dir/bifrost-gauge"

test -x "$executable_path"
test -f "$icon_path"

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$executable_path" "$app_path/Contents/MacOS/bifrost-gauge"
chmod 755 "$app_path/Contents/MacOS/bifrost-gauge"
cp "$icon_path" "$app_path/Contents/Resources/AppIcon.icns"

cat > "$app_path/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>bifrost-gauge</string>
  <key>CFBundleIdentifier</key>
  <string>com.tacogips.bifrost-gauge</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>bifrost-gauge</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

printf 'APPL????' > "$app_path/Contents/PkgInfo"

codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

ditto -c -k --norsrc --keepParent "$app_path" "$zip_path"
zip_sha="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
printf '%s  %s\n' "$zip_sha" "$(basename "$zip_path")" | tee "$sha_path"

echo "Wrote $zip_path"
echo "Wrote $sha_path"
