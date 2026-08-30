# Mouse Touchpad Toggle

Omarchy **service** plugin that disables the laptop touchpad while a mouse is
connected, and restores it when every mouse is gone.

Works with Omarchy Quattro / Hyprland Lua config. It does **not** use
`hyprctl keyword` (that fails with non-legacy parsers). Touchpad state is
applied the same way as `omarchy toggle touchpad`:

```bash
hyprctl eval 'hl.device({ name = "...", enabled = false })'
```

Persistence uses Omarchy's existing file:

`~/.local/state/omarchy/toggles/hypr/touchpad-disabled-name`

so a Hyprland reload keeps the disabled state.

## Features

- USB and Bluetooth mice via **udev** (`ID_INPUT_MOUSE=1`, excluding touchpads / trackpoints)
- Event-driven with `udevadm monitor` (plus a 5s safety poll)
- Multiple mice supported
- Optional OSD notifications
- Configurable bus filters and name ignore patterns
- No root required
- Install / uninstall scripts for local checkouts

## Layout

```
omarchy-mouse-touchpad-toggle/
├── manifest.json
├── Service.qml
├── config.json
├── bin/
│   ├── detect-mice
│   └── apply-touchpad
├── install.sh
├── uninstall.sh
├── LICENSE
└── README.md
```

## Install (local)

```bash
cd ~/code/omarchy-mouse-touchpad-toggle
./install.sh
```

This **copies** the checkout into `~/.config/omarchy/plugins/local.mouse-touchpad-toggle`
(Omarchy rejects symlinks in plugin folders), rescans plugins, and enables the service.

Re-run `./install.sh` after editing the checkout, or develop directly under the installed path
(saves hot-reload). If status IPC is unavailable after install, run `omarchy restart shell`.
## Install (from git)

Once published:

```bash
omarchy plugin add https://github.com/YOU/omarchy-mouse-touchpad-toggle.git --enable --yes
```

## Uninstall

```bash
./uninstall.sh
# or
omarchy plugin disable local.mouse-touchpad-toggle
omarchy plugin remove local.mouse-touchpad-toggle --yes
```

## Config

Edit `config.json` next to the plugin (hot-reloads on save):

```json
{
  "disableOnUsbMouse": true,
  "disableOnBluetoothMouse": true,
  "disableOnOtherMouse": false,
  "restoreOnDisconnect": true,
  "notify": false,
  "ignoreNamePatterns": ["virtual", "tablet"]
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `disableOnUsbMouse` | `true` | React to `ID_BUS=usb` mice |
| `disableOnBluetoothMouse` | `true` | React to `ID_BUS=bluetooth` mice |
| `disableOnOtherMouse` | `false` | React to other buses (rare) |
| `restoreOnDisconnect` | `true` | Re-enable touchpad when no mice remain |
| `notify` | `false` | Show Omarchy OSD on change |
| `ignoreNamePatterns` | `[]` | Case-insensitive substrings to ignore |

## Manual checks

```bash
# What udev thinks is a mouse right now
./bin/detect-mice

# Force touchpad off/on using Omarchy's persistence path
./bin/apply-touchpad off
./bin/apply-touchpad on

# Plugin status over shell IPC
omarchy-shell mouse-touchpad-toggle status
omarchy-shell mouse-touchpad-toggle refresh
```

## Notes

- If the touchpad was already disabled (e.g. `omarchy toggle touchpad off`) before a mouse appeared, this plugin will **not** reclaim ownership and will not force it back on when the mouse leaves.
- Touchpads and trackpoints are never treated as mice.
- `omarchy plugin validate .` should succeed against the Omarchy manifest schema.
