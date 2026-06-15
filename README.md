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
docker-compose.yml                         Optional legacy Compose service
flake.nix                                  Nix-pinned host Bifrost and tools
Taskfile.yml                               go-task commands for Bifrost and ccusage
.env.example                               Local environment template
bifrost/config.json                        Bifrost app-dir config
bifrost-check/config.json                  Disposable host-run check config
launchd/com.local.ai-budget-manager...     macOS launchd template
scripts/bifrost-compose.sh                 Optional Compose helper
scripts/install-launchd.sh                 Install macOS LaunchAgent
scripts/uninstall-launchd.sh               Remove macOS LaunchAgent
macos/BifrostBudgetBar                     Swift macOS menu bar budget app
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

## Start with Nix on the Host

```bash
nix run .#bifrost-host
```

Bifrost listens on:

```text
http://127.0.0.1:18080
```

Run the disposable check config on a separate port:

```bash
nix run .#bifrost-check
```

The check instance listens on:

```text
http://127.0.0.1:18082
```

It copies `bifrost-check/config.json` into `.run-bifrost-check` and stores
temporary SQLite state there. Change bind addresses or ports in `.env`:

```dotenv
BIFROST_BIND_HOST=127.0.0.1
BIFROST_PORT=18080
BIFROST_CHECK_BIND_HOST=127.0.0.1
BIFROST_CHECK_PORT=18082
```

## Dev Shell

Enter a shell with `bifrost-http`, go-task, jq, and `ccusage`:

```bash
nix develop
```

Run the pinned Bifrost binary directly:

```bash
bifrost-http -host 127.0.0.1 -port 18080 -app-dir ./bifrost
```

Run ccusage through the flake app:

```bash
nix run .#ccusage -- daily
nix run .#ccusage -- monthly
nix run .#ccusage -- claude blocks
```

## Taskfile commands

Inside `nix develop`, use `task` as the main command surface:

```bash
task --list
```

Bifrost tasks:

```bash
task bifrost:up
task bifrost:check
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

The `ccusage` command is installed from the `ryoppippi/ccusage` flake input.
It can also be called directly with:

```bash
nix run .#ccusage -- daily
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
nix run .#bifrost-host
```

Bifrost uses `config_store` with SQLite. If you edit entities in
`bifrost/config.json`, Bifrost reconciles those changes into the local database
on startup. UI/API-only changes are stored in `bifrost/config.db`.

## macOS Menu Bar Budget App

`macos/BifrostBudgetBar` is a small Swift/AppKit status bar app. It polls the
local Bifrost governance API, shows budget progress in the menu bar, and exposes
budget controls from the click menu:

- login startup toggle through a LaunchAgent
- automatic reset schedule: off, daily, weekly, monthly, or cron
- manual reset now
- raise budget by a saved default amount
- raise budget by any custom dollar amount
- edit the default raise amount
- choose exactly one displayed budget from registered common/vendor budgets
- set a common default budget that applies to the whole Virtual Key
- add or update vendor-specific budgets for any provider configured on the Virtual Key
- edit Bifrost URL, Virtual Key ID, Budget ID, and reset duration

Run it directly:

```bash
swift run --package-path macos/BifrostBudgetBar BifrostBudgetBar -- \
  --base-url http://127.0.0.1:18080 \
  --vk-id vk-personal \
  --budget-id budget-personal-daily-hard
```

For a monthly Claude Code Virtual Key, point the app at that key and budget:

```bash
BIFROST_VIRTUAL_KEY_ID=vk-claude-code \
BIFROST_BUDGET_ID=budget-claude-code-monthly \
swift run --package-path macos/BifrostBudgetBar BifrostBudgetBar
```

The app also accepts:

```text
BIFROST_BASE_URL              default: http://127.0.0.1:18080
BIFROST_VIRTUAL_KEY_ID        default: vk-personal
BIFROST_BUDGET_ID             optional; selects one budget by id
BIFROST_BUDGET_RESET_DURATION optional; selects a budget by reset duration
BIFROST_REFRESH_SECONDS       default: 60
BIFROST_ADMIN_TOKEN           optional bearer token if your Bifrost admin API requires it
```

Daily, weekly, monthly, and cron resets are evaluated by the running app against
the macOS system clock. Weekly means Monday 00:00. Monthly means day 1 00:00.
Cron uses five fields: `minute hour day month weekday`, for example:

```text
0 0 1 * *
```

Vendor budgets are read from Bifrost `provider_configs[].budgets`, so the app is
not hardcoded to Anthropic or OpenAI. Any provider/vendor that Bifrost returns on
the selected Virtual Key can receive a vendor-specific budget. The displayed
budget menu intentionally lists only budgets that already exist, so budgetless
vendors do not create a long list of zero rows. Use `Add Vendor Budget` to create
one explicitly. `Set Common Default Budget` edits the Virtual Key level budget,
which applies across all providers on that key.

The app's `Launch at Login` menu item writes or removes its own LaunchAgent.

## Test request

Use the personal Virtual Key from `.env`:

```bash
source .env

curl -X POST "http://127.0.0.1:18080/v1/chat/completions" \
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
http://127.0.0.1:18080/v1
```

Use `BIFROST_VK_PERSONAL` as the client API key if your client sends
OpenAI-style bearer auth; otherwise send `x-bf-vk` explicitly.

## Codex and Claude Code Checks

Start the disposable check gateway:

```bash
nix run .#bifrost-check
```

Check that Codex and Claude Code account auth exists locally without printing
secrets:

```bash
jq -r '.auth_mode // empty' ~/.codex/auth.json
claude auth status
```

### Claude Code Enterprise or Max account budget

Claude Code Enterprise/Max account auth can stay in Claude Code. The login flow
does not need to go through Bifrost, but the model requests must use Bifrost as
`ANTHROPIC_BASE_URL` so Bifrost can apply the Virtual Key budget.

Use `ANTHROPIC_CUSTOM_HEADERS` for the Bifrost Virtual Key. Do not use
`ANTHROPIC_AUTH_TOKEN` for this mode because Claude Code needs the
`Authorization` bearer token for its Anthropic account/OAuth session:

```bash
source .env
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_API_KEY
ANTHROPIC_BASE_URL=http://127.0.0.1:18082/anthropic \
ANTHROPIC_CUSTOM_HEADERS="x-bf-vk: $BIFROST_VK_PERSONAL" \
claude -p --model sonnet "Reply with one short sentence."
```

In this mode Bifrost uses the `x-bf-vk` header for governance and forwards the
Claude Code OAuth bearer upstream for Anthropic Claude models. This is the path
to use when the upstream capacity is your Claude Code Enterprise/Max plan and
the budget must be enforced by Bifrost.

Bifrost's documented generic Claude Code mode is different: it uses the Virtual
Key as `ANTHROPIC_AUTH_TOKEN`. That is useful when Bifrost should route to
normal provider API keys, but it does not use the Claude Code account session:

```bash
source .env
ANTHROPIC_BASE_URL=http://127.0.0.1:18082/anthropic \
ANTHROPIC_AUTH_TOKEN="$BIFROST_VK_PERSONAL" \
claude -p "Reply with one short sentence."
```

Codex CLI can target Bifrost through a custom model provider. Use the Bifrost
Virtual Key as the provider API key:

```bash
source .env
OPENAI_API_KEY="$BIFROST_VK_PERSONAL" \
codex exec \
  -c 'model_provider="bifrost-openai"' \
  -c 'model_providers.bifrost-openai={name="Bifrost OpenAI", base_url="http://127.0.0.1:18082/openai/v1", env_key="OPENAI_API_KEY", wire_api="responses"}' \
  -m openai/gpt-4o-mini \
  "Reply with one short sentence."
```

For Codex/ChatGPT subscription auth, Bifrost cannot currently reuse the local
ChatGPT login as an OpenAI upstream API credential. Codex can still be budgeted
through Bifrost, but the upstream OpenAI-compatible provider needs a real
provider API key.

The check config therefore supports two cases:

- Claude Code Enterprise/Max account upstream: no `ANTHROPIC_API_KEY` is needed
  for Anthropic Claude-model requests when using the `ANTHROPIC_CUSTOM_HEADERS`
  command above.
- Normal Bifrost routing to providers such as OpenAI, Anthropic API, Gemini,
  Bedrock, Vertex, and others: configure the provider credentials expected by
  that provider.

## macOS launchd

The LaunchAgent runs:

```bash
<repo>/result-bifrost-http/bin/bifrost-http -host 127.0.0.1 -port 18080 -app-dir <repo>/bifrost
```

It starts Bifrost on the host at login and keeps it alive. The plist sources
`<repo>/.env` before launching so `bifrost/config.json` can use environment
references such as `env.BIFROST_ENCRYPTION_KEY`, `env.OPENAI_API_KEY`, and
`env.ANTHROPIC_API_KEY`.

The installer resolves the host binary with:

```bash
nix build --out-link result-bifrost-http .#bifrost-http
```

Set `BIFROST_BIN=/absolute/path/to/bifrost-http` only when you want to bypass
the Nix-pinned binary.

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
~/Library/Logs/ai-budget-manager/bifrost-host-launchd.out.log
~/Library/Logs/ai-budget-manager/bifrost-host-launchd.err.log
```

## Using Headroom

For the budget-headroom use case, put Headroom before Bifrost:

```text
App / Agent -> Headroom -> Bifrost -> Provider
```

Configure Headroom's upstream OpenAI-compatible base URL as:

```text
http://127.0.0.1:18080/v1
```

Make sure Headroom preserves the Bifrost governance credential, either as
`x-bf-vk` or as the OpenAI-compatible bearer token expected by your client path.
