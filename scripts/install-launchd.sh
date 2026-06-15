#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "launchd setup is only available on macOS." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
label="com.local.ai-budget-manager.bifrost"
template="$repo_root/launchd/$label.plist.template"
launch_agents_dir="$HOME/Library/LaunchAgents"
log_dir="${BIFROST_LAUNCHD_LOG_DIR:-$HOME/Library/Logs/ai-budget-manager}"
nix_bin="${NIX_BIN:-$(command -v nix || true)}"

if [ -z "$nix_bin" ]; then
  echo "Could not find nix. Set NIX_BIN=/absolute/path/to/nix and retry." >&2
  exit 1
fi

mkdir -p "$launch_agents_dir" "$log_dir"
plist="$launch_agents_dir/$label.plist"

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

repo_root_escaped="$(escape_sed_replacement "$repo_root")"
nix_bin_escaped="$(escape_sed_replacement "$nix_bin")"
log_dir_escaped="$(escape_sed_replacement "$log_dir")"

sed \
  -e "s/__REPO_ROOT__/$repo_root_escaped/g" \
  -e "s/__NIX_BIN__/$nix_bin_escaped/g" \
  -e "s/__LOG_DIR__/$log_dir_escaped/g" \
  "$template" > "$plist"

launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl enable "gui/$(id -u)/$label"
launchctl kickstart -k "gui/$(id -u)/$label"

cat <<EOF
Installed $label

Plist:
  $plist

Logs:
  $log_dir/bifrost-launchd.out.log
  $log_dir/bifrost-launchd.err.log

Status:
  launchctl print gui/$(id -u)/$label
EOF
