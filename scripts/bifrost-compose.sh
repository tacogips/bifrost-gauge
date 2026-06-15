#!/usr/bin/env bash
set -euo pipefail

repo_root="${BIFROST_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
compose_file="$repo_root/docker-compose.yml"

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "docker compose is required. Install Docker Desktop or Docker Compose." >&2
    return 127
  fi
}

usage() {
  cat <<'EOF'
Usage: scripts/bifrost-compose.sh <command> [extra docker compose args]

Commands:
  up        Start Bifrost in the background
  down      Stop and remove the Bifrost container
  restart   Restart Bifrost
  logs      Follow Bifrost logs
  pull      Pull the configured Bifrost image
  ps        Show Bifrost compose status
  config    Render the resolved docker compose config

Examples:
  scripts/bifrost-compose.sh up
  scripts/bifrost-compose.sh logs
  nix run .#bifrost -- restart
EOF
}

command_name="${1:-up}"
if [ "$#" -gt 0 ]; then
  shift
fi

compose_args=(--project-directory "$repo_root" -f "$compose_file")

case "$command_name" in
  up)
    compose "${compose_args[@]}" up -d "$@"
    ;;
  down)
    compose "${compose_args[@]}" down "$@"
    ;;
  restart)
    compose "${compose_args[@]}" restart "$@"
    ;;
  logs)
    compose "${compose_args[@]}" logs -f "$@"
    ;;
  pull)
    compose "${compose_args[@]}" pull "$@"
    ;;
  ps)
    compose "${compose_args[@]}" ps "$@"
    ;;
  config)
    compose "${compose_args[@]}" config "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $command_name" >&2
    usage >&2
    exit 2
    ;;
esac
