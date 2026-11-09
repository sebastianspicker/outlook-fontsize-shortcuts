# Migration From Older Legacy-Only Setups

If you previously used a legacy-only version of this tool, move to this repo as follows.

## Files

Old setup:

- `init.lua`
- `outlook_legacy_fontsize.lua`

Current setup:

- `init.lua`
- `outlook-font.lua`
- `outlook_font/`
- optional `outlook-font.json`

## Config mapping

Legacy-only config:

- `right_arrow_count`
- `delays_us`
- `timeout_seconds`
- `hotkeys.*.position`

Current config:

- `delays.timeout`, `delays.waitInterval`, `delays.activate`
- `retry.attempts`, `retry.interval`
- `hotkeys.increase`, `hotkeys.decrease`, `hotkeys.toggle`

## What changed

- You no longer need `right_arrow_count`. The current runtime finds the legacy slider directly through Accessibility APIs instead of navigating tabs with arrow keys.
- You no longer set slider positions directly. `increase` and `decrease` move one step at a time.
- New and Legacy Outlook are detected automatically.

## Example `outlook-font.json`

```jsonc
{
  "delays": {
    "timeout": 5
  },
  "hotkeys": {
    "increase": { "mods": ["ctrl", "alt", "cmd"], "key": "g" },
    "decrease": { "mods": ["ctrl", "alt", "cmd"], "key": "k" },
    "toggle": { "mods": ["ctrl", "alt", "cmd"], "key": "t" }
  }
}
```
