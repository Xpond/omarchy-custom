#!/bin/bash
# Remove installed plugins and restore pristine shell files. Leave user config alone.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=~/.config/omarchy/shell.json

# Remove first: even a later revert failure must not reinstall on the next update.
rm -f ~/.config/omarchy/hooks/post-update.d/centered-panels
echo "removed post-update hook"

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
rm -f ~/.local/bin/omarchy-open-path

for f in Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml \
         plugins/clipboard/Clipboard.qml services/PluginShellApi.qml shell.qml; do
  sudo cp "$REPO/patches/orig/$f" "$SHELL_DIR/$f"
  echo "restored $f"
done

omarchy restart shell
