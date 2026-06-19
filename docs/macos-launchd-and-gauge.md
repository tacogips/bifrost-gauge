# macOS launchd and bifrost-gauge Setup

This guide covers running Bifrost as a macOS LaunchAgent and configuring the
`bifrost-gauge` menu bar app.

## Bifrost LaunchAgent

Install the LaunchAgent:

```bash
scripts/install-launchd.sh
```

The installer:

- builds the pinned Bifrost binary with Nix
- writes `~/Library/LaunchAgents/com.local.bifrost-gauge.bifrost.plist`
- starts the agent immediately
- keeps it alive with launchd

The generated plist is based on
`launchd/com.local.bifrost-gauge.bifrost.plist.template`.

## Plist Example

The generated plist runs this shape of command:

```xml
<key>ProgramArguments</key>
<array>
  <string>/bin/bash</string>
  <string>-lc</string>
  <string>set -a; if [ -f "<repo>/.env" ]; then . "<repo>/.env"; fi; set +a; cd "<repo>/bifrost" &amp;&amp; exec "<repo>/result-bifrost-http/bin/bifrost-http" -host "${BIFROST_BIND_HOST:-127.0.0.1}" -port "${BIFROST_PORT:-18080}" -log-level "${BIFROST_LOG_LEVEL:-info}" -log-style "${BIFROST_LOG_STYLE:-pretty}" -app-dir "<repo>/bifrost"</string>
</array>

<key>RunAtLoad</key>
<true/>

<key>KeepAlive</key>
<true/>
```

Do not edit the generated plist by hand unless you are debugging launchd. Edit
`.env` or the template, then rerun `scripts/install-launchd.sh`.

## Change Host or Port

Set these in `.env`:

```dotenv
BIFROST_BIND_HOST=127.0.0.1
BIFROST_PORT=18080
BIFROST_LOG_LEVEL=info
BIFROST_LOG_STYLE=pretty
```

Then reinstall or restart the LaunchAgent:

```bash
scripts/install-launchd.sh
```

Check status:

```bash
launchctl print "gui/$(id -u)/com.local.bifrost-gauge.bifrost"
```

Read logs:

```bash
tail -f ~/Library/Logs/bifrost-gauge/bifrost-host-launchd.out.log
tail -f ~/Library/Logs/bifrost-gauge/bifrost-host-launchd.err.log
```

Uninstall:

```bash
scripts/uninstall-launchd.sh
```

## Use a Custom Bifrost Binary

Normally the installer builds:

```bash
nix build --out-link result-bifrost-http .#bifrost-http
```

To bypass the pinned Nix binary:

```bash
BIFROST_BIN=/absolute/path/to/bifrost-http scripts/install-launchd.sh
```

## bifrost-gauge Config File

`bifrost-gauge` stores user-editable settings in:

```text
~/.config/bifrost-gauge/bifrost-gauge-config.json
```

The app creates the directory and file automatically. Changes made through the
menu bar app, including Bifrost URL changes, Virtual Key selection, budget
window selection, display mode, and budget usage refresh interval, are written
back to this JSON file. Budget reset timing remains Bifrost state and is not
stored as local app cron state.

Example:

```json
{
  "baseURL": "http://127.0.0.1:18080",
  "menuBarDisplayMode": "pieAndPercent",
  "refreshSeconds": 10,
  "virtualKeyID": "vk-personal"
}
```

`menuBarDisplayMode` accepts all non-empty pie chart, percentage, and spend
amount combinations: `pie`, `percent`, `spendAmount`, `pieAndPercent`,
`pieAndSpendAmount`, `percentAndSpendAmount`, and
`pieAndPercentAndSpendAmount`.

Optional keys:

```json
{
  "adminToken": "",
  "resetDuration": "1d"
}
```

## bifrost-gauge URL Settings

There are four ways to configure the Bifrost URL. Saved JSON config wins over
environment defaults, matching the app's previous persistent-settings behavior.

Edit JSON:

```json
{
  "baseURL": "http://127.0.0.1:18080"
}
```

Use environment variables for first-run/default values:

```bash
BIFROST_BASE_URL=http://127.0.0.1:18080 \
swift run bifrost-gauge
```

Use CLI flags for first-run/default values:

```bash
swift run bifrost-gauge -- \
  --base-url http://127.0.0.1:18080
```

Use the app menu:

```text
Virtual Key -> <registered Bifrost Virtual Key>
Bifrost Settings -> Set Base URL...
```

The Virtual Key menu is populated from `GET /api/governance/virtual-keys`.
`BIFROST_VIRTUAL_KEY_ID` and `--vk-id` remain optional first-run defaults, but
the app menu switches only between Virtual Keys already registered in Bifrost.

Menu changes are saved to
`~/.config/bifrost-gauge/bifrost-gauge-config.json`.

Use `Bifrost Budget Reset` in the menu to update the selected Bifrost budget's
`reset_duration` and the Virtual Key `calendar_aligned` flag. The app sends
these changes through `PUT /api/governance/virtual-keys/{vk_id}` while
preserving current `max_limit` values and other budgets. Budget update objects
omit `id`; Bifrost reconciles the desired budget window from `max_limit` and
`reset_duration`. The app does not run local daily, weekly, monthly, or cron
reset checks when fetching budget status. Bifrost `calendar_aligned` reset
windows must be day, week, month, or year durations; use rolling alignment for
minute or hour durations.

The menu edits the budget set returned by
`GET /api/governance/virtual-keys/{vk_id}`. The separate
`GET /api/governance/budgets` index can include Virtual-Key-related budgets that
the current Bifrost governance API exposes as read-only; those entries are not
mixed into the editable menu state.

## Match Port Changes

If Bifrost is moved to port `18081`, set both sides:

```dotenv
# .env
BIFROST_PORT=18081
```

```json
{
  "baseURL": "http://127.0.0.1:18081"
}
```

Then restart Bifrost and refresh `bifrost-gauge`.

## Saved Budget Limit Restore

Bifrost governance enforces budgets. When an active budget's usage exceeds
`max_limit`, Bifrost rejects inference with a budget exceeded error. This is the
hard backstop that protects the upstream provider account.

`bifrost-gauge` does not change a budget's `max_limit` to allow over-budget
requests. The budget remains the budget. Configure Bifrost itself if you need a
non-blocking over-budget policy.
