# Mouse Touchpad Toggle for Omarchy

An Omarchy Quattro **service** plugin that disables the laptop touchpad while a
mouse is connected, and restores it when every mouse is gone.

## Features

- USB and Bluetooth mice detected via udev (`ID_INPUT_MOUSE=1`)
- Touchpads and trackpoints are never treated as mice
- Event-driven with `udevadm monitor`, plus a bounded 30-second safety poll
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

The configuration file is capped at 16 KiB. `ignoreNamePatterns` accepts at
most 32 strings of at most 128 characters each. Invalid or oversized
configuration falls back to the defaults above.

## How it works

1. `bin/plugin-helper` runs one supervised, size-capped `udevadm info
   --export-db` scan with a two-second total deadline. A timeout fails the scan
   closed instead of reporting that every mouse disappeared.
2. `Service.qml` listens for input udev events, debounces, and rechecks.
3. When a relevant mouse appears, the helper runs the same Hyprland Lua call
   Omarchy uses, then persists state through its descriptor-safe writer:

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
If the touchpad was already disabled by the user, the plugin leaves it alone and
does not claim ownership. Disabling or removing the plugin restores the touchpad
only when this marker proves the plugin changed it.

The helper opens state/config directories and files without following symlinks,
validates opened descriptors for type, owner, permissions, and size, writes
owner-only temporary files, then uses descriptor-relative atomic replacement
and file/directory `fsync`. Mouse and config outputs use Python's JSON encoder
and are capped before QML buffers or parses them.

## Dependencies and security

The plugin runs unsandboxed with your user permissions, like every Omarchy shell
plugin. It requires no elevated privileges, package installation, system
services, or network access.

It uses commands included with a standard Omarchy installation: the system
`/usr/bin/python3` (standard library only), `udevadm`, `setpriv` (util-linux),
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

Omarchy unloads the service before deleting it. If the plugin owns the current
auto-disable, unloading invokes Omarchy's built-in touchpad restore command
before the plugin directory is removed, so the touchpad is not left disabled.

## Local development

```sh
omarchy plugin validate .
python3 -m unittest discover -s tests -v  # optional contributor check
```

## License

MIT
