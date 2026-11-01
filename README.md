# outlook-fontsize-shortcuts


Keyboard shortcuts for changing text display size in Outlook for Mac, with support for both New and Legacy Outlook via Hammerspoon.

<details>
<summary>Status and limitations</summary>

**Project status: archived independent automation project.** I developed this
Hammerspoon configuration independently alongside my main professional work. The
repository is no longer actively maintained and remains available as a starting point
to adapt, rather than a ready-to-use, supported Outlook product. Outlook's interface,
localization and macOS permissions can change. Review the configuration and test
shortcuts and settings on your own system before relying on them; responsibility for
any adaptation and use remains with you.

</details>

| Shortcut | Action |
|----------|--------|
| `Ctrl+Alt+Cmd+G` | Increase text size |
| `Ctrl+Alt+Cmd+K` | Decrease text size |
| `Ctrl+Alt+Cmd+T` | Toggle between increase and decrease |

Use it to avoid digging through Outlook settings every time you want larger or smaller interface text.

## How it works

```mermaid
flowchart LR
    Key[Keyboard shortcut] --> HS[Hammerspoon module]
    HS --> UI[Outlook settings or preferences]
    UI --> Size[Existing text display-size control]
```

## Supported Outlook modes

- `auto`: default; tries New Outlook first, then falls back to Legacy Outlook
- `new`: forces the `Outlook -> Settings...` path
- `legacy`: forces the `Outlook -> Preferences...` path

More on the behavior of each mode: [docs/modes.md](docs/modes.md)

## Prerequisites

- macOS
- Outlook for Mac installed and signed in
- [Hammerspoon](https://www.hammerspoon.org/)
- Accessibility permission for Hammerspoon in `System Settings -> Privacy & Security -> Accessibility`

Install Hammerspoon with Homebrew if needed:

```bash
brew install hammerspoon
```

## Install

```bash
git clone https://github.com/sebastianspicker/outlook-fontsize-shortcuts.git
cd outlook-fontsize-shortcuts
cp init.lua outlook-font.lua ~/.hammerspoon/
cp -R outlook_font ~/.hammerspoon/
cp -n outlook-font.json ~/.hammerspoon/outlook-font.json   # optional overrides; -n keeps an existing file
```

If you already have `~/.hammerspoon/init.lua`, merge this repo's `init.lua` changes instead of overwriting the file.

When upgrading, copy `outlook-font.lua` and `outlook_font/` again and re-merge any `init.lua` changes. A leftover `outlook_font/util.lua` from older versions is unused and can be deleted.

Reload Hammerspoon with `Ctrl+Alt+Cmd+R` or from its menubar icon.

## Usage

Default shortcuts:

- `Ctrl+Alt+Cmd+G`: increase text size
- `Ctrl+Alt+Cmd+K`: decrease text size
- `Ctrl+Alt+Cmd+T`: toggle between increase and decrease

You can also use the Hammerspoon menubar item for mouse-driven control.

## Configuration

`~/.hammerspoon/outlook-font.json` is optional. It accepts JSON with `//` and `/* */` comments. Keys you leave out keep their built-in defaults, which are defined in `outlook_font/config.lua`. Invalid values are reset to their defaults, and a notification lists them.

| Key | Default | Purpose |
|-----|---------|---------|
| `mode` | `"auto"` | `"auto"`, `"new"` or `"legacy"` (see [docs/modes.md](docs/modes.md)) |
| `delays.activate` / `waitInterval` / `timeout` | `0.1` / `0.05` / `3` | Seconds after activating Outlook / polling interval / wait limit for windows and panes |
| `retry.attempts` / `interval` | `2` / `0.2` | Retries after the first attempt / pause between them |
| `overlayDuration`, `showOverlay` | `1.2`, `true` | On-screen overlay after a change |
| `hotkeys.increase` / `decrease` / `toggle` | `ctrl+alt+cmd` + `g` / `k` / `t` | `{ "mods": [...], "key": "x" }`; set `toggle` to `false` to disable it |
| `appNames` | `["Outlook", "Microsoft Outlook"]` | Fallback app names if the bundle id lookup fails |
| `settingsMenu`, `preferencesMenu` | `Outlook > Settings…`, `Outlook > Preferences…` | Menu paths for New and Legacy Outlook |
| `headerLabels`, `generalLabels`, `labelTexts` | English, German, French, Spanish | Localized texts used to find the settings controls |
| `overlayText.larger` / `smaller` | `"Larger"` / `"Smaller"` | Overlay text; also matched against New Outlook's size-button titles |
| `closeWindowKeystroke` | `{ "mods": ["cmd"], "key": "w" }` | Keystroke that closes the settings window |

Notes:

- Arrays replace the defaults instead of extending them. To add a language, repeat the default entries as well.
- If you change `overlayText`, New Outlook's size buttons may no longer match by title. In that case the buttons are picked by position: last for larger, first for smaller.

The repo's [`outlook-font.json`](outlook-font.json) lists the commonly tuned keys with their default values.

If you are moving from an older legacy-only setup, see [docs/migration-from-legacy.md](docs/migration-from-legacy.md).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Hotkeys do nothing | Confirm Hammerspoon is running, then re-check Accessibility permissions and reload the config. |
| Timeout waiting for the Outlook window | Increase `delays.timeout` in `outlook-font.json`. |
| Wrong Outlook path is selected | Set `"mode": "new"` or `"mode": "legacy"` explicitly. |
| Legacy behavior used to rely on `right_arrow_count` | This repo no longer uses that setting; see the migration guide. |
| Buttons or slider are not found | Outlook's UI or language probably changed. Inspect it with Accessibility Inspector, then add the visible texts to `headerLabels`, `generalLabels` or `labelTexts`. |

## Development

The code targets Lua 5.4, the version Hammerspoon embeds. You need a `luarocks` configured for Lua 5.4 and [StyLua](https://github.com/JohnnyMorganz/StyLua).

```bash
make tools   # installs luacheck into ./.luarocks
make check   # fmt-check + lint
```

## Security

See [SECURITY.md](SECURITY.md).
