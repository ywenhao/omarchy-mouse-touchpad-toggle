#!/usr/bin/env bash
# Disable and remove the installed plugin from ~/.config/omarchy/plugins.

set -euo pipefail

PLUGIN_ID="dev.ywenhao.mouse-touchpad-toggle"
DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
SRC="$(cd "$(dirname "$0")" && pwd)"
NAME_FILE="${HOME}/.local/state/omarchy/toggles/hypr/touchpad-disabled-name"
MANAGED_FILE="${HOME}/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed"
OLD_MANAGED_FILE="${HOME}/.local/state/omarchy/plugins/local.mouse-touchpad-toggle/managed"

echo "Uninstalling ${PLUGIN_ID}"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
  omarchy plugin disable local.mouse-touchpad-toggle 2>/dev/null || true
fi

# Restore before deleting the installed scripts. Only an ownership marker from
# this plugin authorizes changing the user's touchpad state.
if [[ -f $MANAGED_FILE || -f $OLD_MANAGED_FILE ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy toggle touchpad on >/dev/null 2>&1 || true
  elif [[ -x $SRC/bin/apply-touchpad ]]; then
    "$SRC/bin/apply-touchpad" on >/dev/null 2>&1 || true
  elif [[ -x $DEST/bin/apply-touchpad ]]; then
    "$DEST/bin/apply-touchpad" on >/dev/null 2>&1 || true
  fi
  rm -f "$NAME_FILE" "$MANAGED_FILE" "$OLD_MANAGED_FILE"
fi

if [[ -e $DEST || -L $DEST ]]; then
  rm -rf "$DEST"
  echo "Removed ${DEST}"
else
  echo "No install found at ${DEST}"
fi
rm -rf "${HOME}/.config/omarchy/plugins/local.mouse-touchpad-toggle"

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

rm -f "$MANAGED_FILE"
rmdir "${HOME}/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle" 2>/dev/null || true
rm -f "$OLD_MANAGED_FILE"
rmdir "${HOME}/.local/state/omarchy/plugins/local.mouse-touchpad-toggle" 2>/dev/null || true

echo "Done."
