# bifrost-gauge

Local Bifrost setup for LLM budget management, plus a macOS menu bar app that
shows and edits the current budget.

## Install bifrost-gauge

```bash
brew tap tacogips/tap
brew install --cask bifrost-gauge
open -a bifrost-gauge
```

This installs the macOS menu bar app. Bifrost itself still needs to be running
locally; the setup below starts Bifrost on `http://127.0.0.1:18080`.

Bifrost official links:

- Docs: https://docs.getbifrost.ai/
- Provider setup: https://docs.getbifrost.ai/quickstart/gateway/provider-configuration
- GitHub: https://github.com/maximhq/bifrost

## What This Gives You

- Bifrost running locally on `http://127.0.0.1:18080`
- one local Virtual Key: `vk-personal`
- one daily hard budget: `budget-personal-daily-hard`, currently `$10`
- `bifrost-gauge`, a macOS menu bar app for budget status and controls

Budget state is owned by Bifrost. `bifrost-gauge` only reads and updates Bifrost
through its governance API.

## Requirements

- macOS
- Nix
- Xcode 26.5 with Swift 6.3.2 for building `bifrost-gauge`
- at least one provider API key, for example `OPENAI_API_KEY` or
  `ANTHROPIC_API_KEY`

## 1. Configure Secrets

```bash
cp .env.example .env
```

Edit `.env`:

```dotenv
BIFROST_ENCRYPTION_KEY=<generate with openssl rand -base64 32>
BIFROST_VK_PERSONAL=sk-bf-local-personal-vk-change-me
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
```

Generate the encryption key:

```bash
openssl rand -base64 32
```

## 2. Start Bifrost

Run it in the foreground:

```bash
nix run .#bifrost-host
```

Open the Bifrost UI:

```text
http://127.0.0.1:18080
```

Check the budget:

```bash
curl -fsS http://127.0.0.1:18080/api/governance/budgets \
  | jq '.budgets[] | select(.id == "budget-personal-daily-hard")'
```

## 3. Run bifrost-gauge

```bash
swift run bifrost-gauge
```

The app stores user-editable settings here:

```text
~/.config/bifrost-gauge/bifrost-gauge-config.json
```

Use the menu bar item to change:

- Bifrost URL
- selected registered Virtual Key
- displayed budget window
- Bifrost budget reset duration and calendar alignment
- budget usage refresh interval
- default raise amount
- Allow Over-Budget Requests on/off

## 4. Run Bifrost as a macOS Daemon

Install the LaunchAgent:

```bash
scripts/install-launchd.sh
```

Check status:

```bash
launchctl print "gui/$(id -u)/com.local.bifrost-gauge.bifrost"
```

Logs:

```text
~/Library/Logs/bifrost-gauge/bifrost-host-launchd.out.log
~/Library/Logs/bifrost-gauge/bifrost-host-launchd.err.log
```

Uninstall:

```bash
scripts/uninstall-launchd.sh
```

The generated plist is based on:

```text
launchd/com.local.bifrost-gauge.bifrost.plist.template
```

## Change the Port

Edit `.env`:

```dotenv
BIFROST_BIND_HOST=127.0.0.1
BIFROST_PORT=18080
```

Then restart Bifrost. If using launchd, rerun:

```bash
scripts/install-launchd.sh
```

Also update `bifrost-gauge`:

```json
{
  "baseURL": "http://127.0.0.1:18080"
}
```

in:

```text
~/.config/bifrost-gauge/bifrost-gauge-config.json
```

## Test a Request

```bash
source .env

curl -fsS http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-bf-vk: $BIFROST_VK_PERSONAL" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "Reply with ok"}]
  }'
```

## More Details

- Vendor-specific setup: [docs/vendor-setup.md](docs/vendor-setup.md)
- macOS daemon, plist example, and gauge config:
  [docs/macos-launchd-and-gauge.md](docs/macos-launchd-and-gauge.md)
- macOS app details: [docs/bifrost-gauge.md](docs/bifrost-gauge.md)

## License

MIT
