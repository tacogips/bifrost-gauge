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
selection, menu bar display mode, and refresh period are written back to that
JSON file. Budget reset timing is Bifrost state, not local app cron state.

Example:

```json
{
  "baseURL": "http://127.0.0.1:18080",
  "menuBarDisplayMode": "pieAndPercent",
  "refreshSeconds": 10,
  "virtualKeyID": "vk-personal"
}
```

`menuBarDisplayMode` supports every non-empty combination of pie chart,
percentage, and spend amount: `pie`, `percent`, `spendAmount`,
`pieAndPercent`, `pieAndSpendAmount`, `percentAndSpendAmount`, and
`pieAndPercentAndSpendAmount`.

See [macOS launchd and bifrost-gauge Setup](macos-launchd-and-gauge.md)
for LaunchAgent setup, port changes, and URL configuration.

## Menu Controls

Click the menu bar item to:

- refresh current Bifrost budget progress
- reset budget usage
- set the selected budget limit from Budget Settings
- select one budget window within the current Virtual Key from Budget Settings
- set the selected Bifrost budget `reset_duration` from Budget Settings
- toggle Bifrost `calendar_aligned` resets from Budget Settings
- switch between registered Bifrost Virtual Keys
- switch menu bar display between any combination of percent, pie, and spend amount
- set the automatic refresh period from Bifrost Settings
- edit the Bifrost base URL from Bifrost Settings
- view the app version and active Bifrost connection details from About Bifrost
- toggle "Launch at Login"; the app writes or removes its own LaunchAgent

Bifrost owns reset scheduling. `bifrost-gauge` updates each budget's
`reset_duration` and the Virtual Key's `calendar_aligned` setting through the
Bifrost governance API; it does not evaluate local daily, weekly, monthly, or
cron reset schedules at fetch time. When `calendar_aligned` is enabled, Bifrost
supports day, week, month, and year reset windows; turn it off before using
minute or hour reset durations.

The editable budget surface is the selected Virtual Key detail response from
`GET /api/governance/virtual-keys/{vk_id}`. Bifrost may also expose
Virtual-Key-related budgets through `GET /api/governance/budgets`; that index is
read-only in the current governance API and is not mixed into the editable menu
state. This keeps the menu aligned with the same budget set that
`PUT /api/governance/virtual-keys/{vk_id}` updates.

Refresh loads the selected Virtual Key and then fetches
`/api/governance/budgets` only to refresh provider budget snapshots. The menu
bar Virtual Key budget indicator is calculated from the editable budget set
returned by the selected Virtual Key detail endpoint.

When a Bifrost budget is active, Bifrost returns an error after usage exceeds
`max_limit`. `bifrost-gauge` does not change `max_limit` to bypass this
enforcement. Configure Bifrost itself if you need a non-blocking over-budget
policy.

## Reset and Edit

Reset Usage sends the current Virtual Key budget set:

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

Updates use `PUT /api/governance/virtual-keys/{vk_id}`. Except for Reset, the
app sends `reset_budget_usage=false` so current usage is preserved. The app
sends the complete current Virtual Key budget set so that update calls do not
delete other budget windows. Budget update objects intentionally omit `id`;
Bifrost reconciles the desired budget window from `max_limit` and
`reset_duration`.

Set Budget Limit sends the selected budget's `max_limit` changed and
`reset_budget_usage=false`, so existing usage is preserved and progress is
recalculated against the new limit. Reset duration changes send the same scope
with only the selected budget's `reset_duration` changed; other budgets and
`max_limit` values are preserved. The calendar-aligned toggle and vendor budget
updates also preserve current usage.
