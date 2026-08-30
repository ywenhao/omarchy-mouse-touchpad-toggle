#!/usr/bin/env bash
# Disable and remove the installed plugin from ~/.config/omarchy/plugins.

set -euo pipefail

PLUGIN_ID="local.mouse-touchpad-toggle"
DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
SRC="$(cd "$(dirname "$0")" && pwd)"

echo "Uninstalling ${PLUGIN_ID}"

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
fi

if [[ -e $DEST || -L $DEST ]]; then
  rm -rf "$DEST"
  echo "Removed ${DEST}"
else
  echo "No install found at ${DEST}"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

# Restore touchpad if this plugin had disabled it.
if [[ -x $SRC/bin/apply-touchpad ]]; then
  "$SRC/bin/apply-touchpad" on 2>/dev/null || true
fi
rm -f "${HOME}/.local/state/omarchy/plugins/local.mouse-touchpad-toggle/managed"
rmdir "${HOME}/.local/state/omarchy/plugins/local.mouse-touchpad-toggle" 2>/dev/null || true

echo "Done."
