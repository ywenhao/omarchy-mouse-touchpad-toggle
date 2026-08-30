# Mouse Touchpad Toggle for Omarchy

An Omarchy Quattro **service** plugin that disables the laptop touchpad while a
mouse is connected, and restores it when every mouse is gone.

## Features

- USB and Bluetooth mice detected via udev (`ID_INPUT_MOUSE=1`)
- Touchpads and trackpoints are never treated as mice
- Event-driven with `udevadm monitor`, plus a short safety poll
- Multiple mice supported at once
- Uses Omarchy's native touchpad persistence (`omarchy toggle touchpad` path)
- Works with Hyprland's Lua config (`hyprctl eval` / `hl.device`)
- Optional OSD notifications
- Configurable bus filters and name ignore patterns
- No root required

## Install

```sh
omarchy plugin add https://github.com/ywenhao/omarchy-mouse-touchpad-toggle.git --enable
```

## Configure

Edit the plugin's `config.json` (hot-reloads on save):

`~/.config/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/config.json`

```json
{
  "disableOnUsbMouse": true,
  "disableOnBluetoothMouse": true,
  "disableOnOtherMouse": false,
  "restoreOnDisconnect": true,
  "notify": false,
  "ignoreNamePatterns": []
}
```

| Key | Default | Meaning |
|-----|---------|---------|
| `disableOnUsbMouse` | `true` | React to `ID_BUS=usb` mice |
| `disableOnBluetoothMouse` | `true` | React to `ID_BUS=bluetooth` mice |
| `disableOnOtherMouse` | `false` | React to other buses (rare) |
| `restoreOnDisconnect` | `true` | Re-enable the touchpad when no mice remain |
| `notify` | `false` | Show Omarchy OSD when the touchpad changes |
| `ignoreNamePatterns` | `[]` | Case-insensitive substrings to ignore |

## How it works

1. `bin/detect-mice` walks `/dev/input/event*` and keeps devices with
   `ID_INPUT_MOUSE=1`, excluding touchpads and pointing sticks.
2. `Service.qml` listens for input udev events, debounces, and rechecks.
3. When a relevant mouse appears, `bin/apply-touchpad off` runs the same
   Hyprland Lua call Omarchy uses:

   ```sh
   hyprctl eval 'hl.device({ name = "...", enabled = false })'
   ```

4. The disabled device name is written to
   `~/.local/state/omarchy/toggles/hypr/touchpad-disabled-name`, so a Hyprland
   reload keeps the touchpad off.
5. When the last mouse disconnects, the plugin restores the touchpad the same
   way (`enabled = true`) and clears that state file.

Ownership of an auto-disable is tracked in:

`~/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed`

so a shell restart still knows whether this plugin should restore on unplug.

## Dependencies and security

The plugin runs unsandboxed with your user permissions, like every Omarchy shell
plugin. It does not use `sudo`, install packages, start systemd services, or
access the network.

It uses commands included with a standard Omarchy installation: Bash, `udevadm`,
`hyprctl`, `omarchy-hw-touchpad`, and optionally `omarchy-osd`.

## Status

```sh
omarchy-shell mouse-touchpad-toggle status
omarchy-shell mouse-touchpad-toggle refresh
```

## Update

```sh
omarchy plugin update dev.ywenhao.mouse-touchpad-toggle
```

## Remove

```sh
omarchy plugin remove dev.ywenhao.mouse-touchpad-toggle
```

## Local development

```sh
./install.sh    # copy into ~/.config/omarchy/plugins and enable
./uninstall.sh  # disable, remove install, restore touchpad if managed
omarchy plugin validate .
```

## License

MIT
