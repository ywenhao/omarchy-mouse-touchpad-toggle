#!/usr/bin/env bash
# Install this plugin into ~/.config/omarchy/plugins and enable it.
# Omarchy rejects symlinks inside plugin folders, so this copies files.

set -euo pipefail

PLUGIN_ID="local.mouse-touchpad-toggle"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"

echo "Installing ${PLUGIN_ID}"
echo "  from: ${SRC}"
echo "  to:   ${DEST}"

chmod +x "$SRC"/bin/detect-mice "$SRC"/bin/apply-touchpad "$SRC"/install.sh "$SRC"/uninstall.sh

# Unload any running copy before replacing files on disk (avoids crashing
# omarchy-shell by deleting QML that is still mounted).
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
fi
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins || true
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
mkdir -p "$DEST"

rsync -a \
  --exclude '.git/' \
  --exclude '.gitignore' \
  --exclude '.cursor/' \
  --exclude '*.swp' \
  --exclude '.DS_Store' \
  "$SRC"/ "$DEST"/

chmod +x "$DEST"/bin/detect-mice "$DEST"/bin/apply-touchpad "$DEST"/install.sh "$DEST"/uninstall.sh

omarchy plugin validate "$DEST"

omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin enable "$PLUGIN_ID"

# Migrate: if a mouse is already connected and the touchpad was disabled
# (possibly by an older install of this plugin), claim ownership so unplug
# still restores.
NAME_FILE="${HOME}/.local/state/omarchy/toggles/hypr/touchpad-disabled-name"
MANAGED_FILE="${HOME}/.local/state/omarchy/plugins/local.mouse-touchpad-toggle/managed"
if [[ -f $NAME_FILE ]] && "$DEST/bin/detect-mice" | grep -q '"total":[1-9]'; then
  mkdir -p "$(dirname "$MANAGED_FILE")"
  printf '1\n' >"$MANAGED_FILE"
fi

echo
echo "Enabled ${PLUGIN_ID}."
echo "Edit config: ${DEST}/config.json"
echo "Status:      omarchy-shell mouse-touchpad-toggle status"
echo "Disable:     omarchy plugin disable ${PLUGIN_ID}"
echo "Uninstall:   ${SRC}/uninstall.sh"
echo
echo "Note: local edits in ${SRC} are not live until you re-run install.sh"
echo "      (or develop directly under ${DEST})."
