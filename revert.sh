#!/bin/bash
# Remove installed plugins and restore this machine's unchanged shell patches.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=~/.config/omarchy/shell.json
STATE=~/.local/state/omarchy-custom

# Remove first: even a later revert failure must not reinstall on the next update.
rm -f ~/.config/omarchy/hooks/post-update.d/centered-panels
echo "removed post-update hook"

python3 "$REPO/scripts/user-config.py" revert ~/.config/hypr/hyprland.lua "$STATE" ~/.local/bin

# Remove each plugin link and registration.
for p in "$REPO"/plugins/*/; do
  id=$(basename "$p")
  rm -f ~/.config/omarchy/plugins/"$id"
  # A missing config must not prevent restoring package files.
  if [[ -f $CONF ]]; then
    jq --arg id "$id" '.plugins = [.plugins[]? | select(.id != $id)]' \
       "$CONF" > "$CONF.new" && mv "$CONF.new" "$CONF"
  fi
  echo "removed $id"
done

failed=0
for f in Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml \
         plugins/clipboard/Clipboard.qml services/PluginShellApi.qml shell.qml; do
  installed="$SHELL_DIR/$f"
  saved="$STATE/orig/$f"
  written="$STATE/installed/$f"
  if [[ ! -f $saved || ! -f $written ]]; then
    if [[ -f $saved || -f $written || -f $written.pending || -f $REPO/.installed/$f ]] ||
       cmp -s "$installed" "$REPO/patches/shell/$f"; then
      echo "Not restored: $f — no complete installation backup; left untouched" >&2
      failed=1
    fi
    continue
  fi
  # A failed install or interrupted revert may already have left the saved bytes.
  if ! cmp -s "$installed" "$saved"; then
    if ! cmp -s "$installed" "$written"; then
      echo "Not restored: $f — changed since installation; backup: $saved" >&2
      failed=1; continue
    fi
    if ! touch "$written.pending" || ! sudo cp "$saved" "$installed" || ! cmp -s "$saved" "$installed"; then
      echo "Could not restore $f; backup retained: $saved" >&2
      failed=1; continue
    fi
  fi
  rm -f "$saved" "$written" "$written.pending" "$REPO/.installed/$f"
  echo "restored $f"
done

omarchy restart shell
(( failed == 0 ))
