#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "launchd setup is only available on macOS." >&2
  exit 1
fi

label="com.local.bifrost-gauge.bifrost"

plist="$HOME/Library/LaunchAgents/$label.plist"
launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
rm -f "$plist"

echo "Uninstalled $label"
