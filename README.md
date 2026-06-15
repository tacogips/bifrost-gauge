# ai-budget-manager

Local Bifrost configuration for personal LLM budget management.

This repository runs Bifrost locally as an OpenAI-compatible gateway and seeds a
personal Virtual Key with a daily hard budget backstop. The intended policy is:

- normal soft budget: handled by a caller/proxy/wrapper in front of Bifrost
- emergency hard budget: enforced by Bifrost governance
- token reduction: put Headroom in front of Bifrost when you use it

Recommended topology:

```text
App / Agent
  -> Headroom, optional
  -> Bifrost on localhost
  -> LLM provider
```

## Files

```text
docker-compose.yml                         Local Bifrost service
flake.nix                                  Nix dev shell and nix run wrapper
Taskfile.yml                               go-task commands for Bifrost and ccusage
.env.example                               Local environment template
bifrost/config.json                        Bifrost app-dir config
launchd/com.local.ai-budget-manager...     macOS launchd template
scripts/bifrost-compose.sh                 Compose helper
scripts/install-launchd.sh                 Install macOS LaunchAgent
scripts/uninstall-launchd.sh               Remove macOS LaunchAgent
```

Runtime state is written under `./bifrost` as SQLite files. Those database files
are ignored by Git; `bifrost/config.json` is tracked.

## First-time setup

```bash
cp .env.example .env
```

Edit `.env`:

- set `BIFROST_ENCRYPTION_KEY`
- set `BIFROST_VK_PERSONAL`
- set provider keys such as `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`

Generate a local encryption key with:

```bash
openssl rand -base64 32
```

## Start with Docker Compose

```bash
docker compose up -d
```

Or use the helper:

```bash
scripts/bifrost-compose.sh up
scripts/bifrost-compose.sh logs
scripts/bifrost-compose.sh down
```

Bifrost listens on:

```text
http://127.0.0.1:8080
```

Change the bind address or port in `.env`:

```dotenv
BIFROST_BIND_HOST=127.0.0.1
BIFROST_PORT=8080
```

## Start with Nix

Enter a shell with Docker client, Docker Compose, go-task, jq, Node.js, and a
`ccusage` wrapper:

```bash
nix develop
```

Run Bifrost through the flake app:

```bash
nix run .#bifrost -- up
nix run .#bifrost -- logs
nix run .#bifrost -- restart
nix run .#bifrost -- down
```

Run ccusage through the flake app:

```bash
nix run .#ccusage -- daily
nix run .#ccusage -- monthly
nix run .#ccusage -- claude blocks
```

Docker Desktop or a Docker daemon must already be running. The flake supplies
client tools; it does not start the Docker daemon.

## Taskfile commands

Inside `nix develop`, use `task` as the main command surface:

```bash
task --list
```

Bifrost tasks:

```bash
task bifrost:up
task bifrost:logs
task bifrost:restart
task bifrost:down
```

ccusage tasks:

```bash
task ccusage:daily
task ccusage:weekly
task ccusage:monthly
task ccusage:session
task ccusage:blocks
task ccusage:blocks:live
```

Focused Claude Code and Codex reports:

```bash
task ccusage:claude:daily
task ccusage:claude:monthly
task ccusage:claude:blocks
task ccusage:codex:daily
task ccusage:codex:monthly
```

Pass extra flags after `--`:

```bash
task ccusage:daily -- --help
task ccusage:claude:daily -- --mode display
task ccusage:codex:daily -- --speed fast
```

The `ccusage` command provided by this flake delegates to:

```bash
npx --yes ccusage@latest
```

## Bifrost governance

The local config seeds one personal Virtual Key:

```json
{
  "id": "vk-personal",
  "value": "env.BIFROST_VK_PERSONAL"
}
```

It also seeds a daily hard budget:

```json
{
  "id": "budget-personal-daily-hard",
  "virtual_key_id": "vk-personal",
  "max_limit": 20.0,
  "reset_duration": "1d",
  "calendar_aligned": true
}
```

To change the hard daily backstop, edit `bifrost/config.json`:

```json
"max_limit": 20.0
```

Then restart:

```bash
scripts/bifrost-compose.sh restart
```

Bifrost uses `config_store` with SQLite. If you edit entities in
`bifrost/config.json`, Bifrost reconciles those changes into the local database
on startup. UI/API-only changes are stored in `bifrost/config.db`.

## Test request

Use the personal Virtual Key from `.env`:

```bash
source .env

curl -X POST "http://127.0.0.1:8080/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "x-bf-vk: $BIFROST_VK_PERSONAL" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [
      { "role": "user", "content": "Hello from local Bifrost" }
    ]
  }'
```

For OpenAI-compatible clients, point the base URL to:

```text
http://127.0.0.1:8080/v1
```

Use `BIFROST_VK_PERSONAL` as the client API key if your client sends
OpenAI-style bearer auth; otherwise send `x-bf-vk` explicitly.

## macOS launchd

The LaunchAgent runs:

```bash
nix develop <repo> --command <repo>/scripts/bifrost-compose.sh up
```

It starts at login and repeats every 300 seconds to make sure the compose
service is up. Docker's `restart: unless-stopped` handles container restarts.

Install:

```bash
scripts/install-launchd.sh
```

Check status:

```bash
launchctl print "gui/$(id -u)/com.local.ai-budget-manager.bifrost"
```

Uninstall:

```bash
scripts/uninstall-launchd.sh
```

Logs are written to:

```text
~/Library/Logs/ai-budget-manager/bifrost-launchd.out.log
~/Library/Logs/ai-budget-manager/bifrost-launchd.err.log
```

## Using Headroom

For the budget-headroom use case, put Headroom before Bifrost:

```text
App / Agent -> Headroom -> Bifrost -> Provider
```

Configure Headroom's upstream OpenAI-compatible base URL as:

```text
http://127.0.0.1:8080/v1
```

Make sure Headroom preserves the Bifrost governance credential, either as
`x-bf-vk` or as the OpenAI-compatible bearer token expected by your client path.
