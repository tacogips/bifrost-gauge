#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "launchd setup is only available on macOS." >&2
  exit 1
fi

label="com.local.bifrost-gage.bifrost"
legacy_label="com.local.ai-budget-manager.bifrost"

for current_label in "$label" "$legacy_label"; do
  plist="$HOME/Library/LaunchAgents/$current_label.plist"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
done

echo "Uninstalled $label"
