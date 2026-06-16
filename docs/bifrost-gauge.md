# bifrost-gauge

Small macOS menu bar app for local Bifrost budget status and controls.

## Run

```bash
swift run bifrost-gauge -- \
  --base-url http://127.0.0.1:18080
```

Environment variables are also supported:

```bash
export BIFROST_BASE_URL=http://127.0.0.1:18080
export BIFROST_REFRESH_SECONDS=10
swift run bifrost-gauge
```

The menu bar budget scope is the selected Bifrost Virtual Key. The Virtual Key
menu is populated from `GET /api/governance/virtual-keys`; choose one of the
registered keys there. `BIFROST_VIRTUAL_KEY_ID` and `--vk-id` are optional
first-run defaults only. If the selected Virtual Key has multiple budget
windows, the app picks a `1M` budget first and then falls back to the first
budget returned by Bifrost.

Persistent settings are stored in:

```text
~/.config/bifrost-gauge/bifrost-gauge-config.json
```

Menu changes such as Bifrost URL, Virtual Key selection, budget window
selection, menu bar display mode, refresh period, default raise
amount, and disabled budget enforcement restore values are written back to that
JSON file. Budget reset timing is Bifrost state, not local app cron state.

Example:

```json
{
  "baseURL": "http://127.0.0.1:18080",
  "defaultRaiseAmount": 5,
  "disabledBudgetLimits": {
    "virtual-key:vk-personal:common:1M": 10
  },
  "menuBarDisplayMode": "pieAndPercent",
  "refreshSeconds": 10,
  "virtualKeyID": "vk-personal"
}
```

See [macOS launchd and bifrost-gauge Setup](macos-launchd-and-gauge.md)
for LaunchAgent setup, port changes, and URL configuration.

## Menu Controls

Click the menu bar item to:

- refresh current Bifrost budget progress
- reset budget usage now from Budget Actions
- raise the selected budget by the saved default amount from Budget Actions
- raise the selected budget by a custom dollar amount from Budget Actions
- set the selected budget limit from Budget Settings
- select one budget window within the current Virtual Key from Budget Settings
- turn Allow Over-Budget Requests on or off from Budget Settings
- set the default raise amount from Budget Settings
- set the selected Bifrost budget `reset_duration` from Budget Settings
- toggle Bifrost `calendar_aligned` resets from Budget Settings
- switch between registered Bifrost Virtual Keys
- switch menu bar display between percent, pie, or pie plus percent
- set the automatic refresh period from Bifrost Settings
- edit the Bifrost base URL from Bifrost Settings
- toggle "Launch at Login"; the app writes or removes its own LaunchAgent

Bifrost owns reset scheduling. `bifrost-gauge` updates each budget's
`reset_duration` and the Virtual Key's `calendar_aligned` setting through the
Bifrost governance API; it does not evaluate local daily, weekly, monthly, or
cron reset schedules at fetch time. When `calendar_aligned` is enabled, Bifrost
supports day, week, month, and year reset windows; turn it off before using
minute or hour reset durations.

The menu only edits Virtual Key level budgets. It intentionally does not expose
provider-specific budget controls; use separate Virtual Keys when you want
separate Codex, Claude, or other client budgets.

When a Bifrost budget is active, Bifrost returns an error after usage exceeds
`max_limit`. The menu item `Allow Over-Budget Requests` controls whether those
over-budget requests keep going for the current Virtual Key. On mode keeps the
Bifrost budget entry but raises `max_limit` to a local high-water value and
stores the original limit in `disabledBudgetLimits` under
`virtual-key:<vk_id>:common:<reset_duration>`. Switching it Off restores the
saved limit only for the selected window.

## Reset and Raise

Reset sends the current Virtual Key budget set:

```json
{
  "budgets": [
    {
      "max_limit": 10.0,
      "reset_duration": "1M"
    }
  ],
  "reset_budget_usage": true
}
```

Updates use `PUT /api/governance/virtual-keys/{vk_id}`. The app sends the
complete current Virtual Key budget set so that update calls do not delete other
budget windows. Budget update objects intentionally omit `id`; Bifrost
reconciles the desired budget window from `max_limit` and `reset_duration`.

Raise sends the same scope with the selected budget's `max_limit` increased by
the chosen dollar amount. Reset duration changes send the same scope with only
the selected budget's `reset_duration` changed; other budgets and `max_limit`
values are preserved. The calendar-aligned toggle sends `calendar_aligned` in
the same `PUT /api/governance/virtual-keys/{vk_id}` payload.
