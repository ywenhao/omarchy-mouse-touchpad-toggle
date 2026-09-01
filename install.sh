#!/usr/bin/env bash
# Install this plugin into ~/.config/omarchy/plugins and enable it.
# Omarchy rejects symlinks inside plugin folders, so this copies files.

set -euo pipefail

PLUGIN_ID="dev.ywenhao.mouse-touchpad-toggle"
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
OLD_DEST="${HOME}/.config/omarchy/plugins/local.mouse-touchpad-toggle"

echo "Installing ${PLUGIN_ID}"
echo "  from: ${SRC}"
echo "  to:   ${DEST}"

chmod +x "$SRC"/bin/detect-mice "$SRC"/bin/apply-touchpad "$SRC"/install.sh "$SRC"/uninstall.sh

# Unload any running copy before replacing files on disk (avoids crashing
# omarchy-shell by deleting QML that is still mounted).
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
  # Pre-rename id from the first publish.
  omarchy plugin disable local.mouse-touchpad-toggle 2>/dev/null || true
fi
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins || true
fi

mkdir -p "$(dirname "$DEST")"
if [[ -L $DEST ]]; then
  rm -f "$DEST"
fi
mkdir -p "$DEST"

rsync -a \
  --exclude '.git/' \
  --exclude '.gitignore' \
  --exclude '.cursor/' \
  --exclude '*.swp' \
  --exclude '.DS_Store' \
  --exclude 'config.json' \
  "$SRC"/ "$DEST"/

# Preserve user configuration on reinstalls and migrate it from the old plugin
# id when present. Copy repository defaults only for a genuinely fresh install.
if [[ ! -f $DEST/config.json ]]; then
  if [[ -f $OLD_DEST/config.json ]]; then
    cp "$OLD_DEST/config.json" "$DEST/config.json"
  else
    cp "$SRC/config.json" "$DEST/config.json"
  fi
fi
rm -rf "$OLD_DEST"

chmod +x "$DEST"/bin/detect-mice "$DEST"/bin/apply-touchpad "$DEST"/install.sh "$DEST"/uninstall.sh

omarchy plugin validate "$DEST"

# Migrate only ownership recorded by the pre-rename plugin. A generic existing
# touchpad disable may belong to the user and must not be claimed.
MANAGED_FILE="${HOME}/.local/state/omarchy/plugins/dev.ywenhao.mouse-touchpad-toggle/managed"
OLD_MANAGED_FILE="${HOME}/.local/state/omarchy/plugins/local.mouse-touchpad-toggle/managed"
if [[ -f $OLD_MANAGED_FILE && ! -f $MANAGED_FILE ]]; then
  mkdir -p "$(dirname "$MANAGED_FILE")"
  mv "$OLD_MANAGED_FILE" "$MANAGED_FILE"
  rmdir "$(dirname "$OLD_MANAGED_FILE")" 2>/dev/null || true
fi

omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin enable "$PLUGIN_ID"

echo
echo "Enabled ${PLUGIN_ID}."
echo "Edit config: ${DEST}/config.json"
echo "Status:      omarchy-shell mouse-touchpad-toggle status"
echo "Disable:     omarchy plugin disable ${PLUGIN_ID}"
echo "Uninstall:   ${SRC}/uninstall.sh"
echo
echo "Note: local edits in ${SRC} are not live until you re-run install.sh"
echo "      (or develop directly under ${DEST})."
