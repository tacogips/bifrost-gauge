# bifrost-gage

Small macOS menu bar app for local Bifrost budget status and controls.

## Run

```bash
swift run --package-path macos/bifrost-gage bifrost-gage -- \
  --base-url http://127.0.0.1:18080 \
  --vk-id vk-personal \
  --budget-id budget-personal-daily-hard
```

Environment variables are also supported:

```bash
export BIFROST_BASE_URL=http://127.0.0.1:18080
export BIFROST_VIRTUAL_KEY_ID=vk-personal
export BIFROST_BUDGET_ID=budget-personal-daily-hard
export BIFROST_REFRESH_SECONDS=60
swift run --package-path macos/bifrost-gage bifrost-gage
```

If `BIFROST_BUDGET_ID` is omitted, the app picks a `1M` budget first and then
falls back to the first budget returned by Bifrost.

## Menu Controls

Click the menu bar item to:

- refresh current Bifrost budget progress
- reset budget usage now
- raise the selected budget by the saved default amount
- raise the selected budget by a custom dollar amount
- set the default raise amount
- set automatic reset schedule: off, daily, weekly, monthly, or cron
- edit the cron expression using system clock time
- select exactly one budget for menu bar progress
- set a common default budget for the whole Virtual Key
- add or update vendor-specific budgets for providers on the Virtual Key
- edit Bifrost base URL, Virtual Key ID, Budget ID, or reset duration
- toggle "Launch at Login"; the app writes or removes its own LaunchAgent

Daily, weekly, monthly, and cron resets are evaluated by the running app against
the macOS system clock. Weekly means Monday 00:00. Monthly means day 1 00:00.
Cron uses five fields: `minute hour day month weekday`, for example `0 0 1 * *`.

Vendor budgets come from Bifrost `provider_configs[].budgets`. The app handles
whatever provider names Bifrost returns and does not special-case Anthropic.
Budgetless vendors are not shown in the displayed budget list; create one through
`Add Vendor Budget` when you actually want that vendor to have an explicit limit.
The common default budget is the Virtual Key level budget and applies across all
providers on that key.

## Reset and Raise

For a common budget, reset sends:

```json
{
  "budgets": [
    {
      "id": "budget-id",
      "max_limit": 20.0,
      "reset_duration": "1M"
    }
  ],
  "reset_budget_usage": true
}
```

For a vendor budget, the same operation is sent under the matching
`provider_configs[].budgets` entry while preserving the other provider configs.
Both paths use `PUT /api/governance/virtual-keys/{vk_id}`. The app sends the
complete current budget set for the edited scope so that update calls do not
delete other budget windows.

Raise sends the same scope with the selected budget's `max_limit` increased by
the chosen dollar amount.
