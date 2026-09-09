#!/bin/bash
# Undo install.sh: unlink the plugins, deregister them, and put the packaged
# Omarchy shell files back the way upstream shipped them.
#
# It deliberately does NOT touch ~/.config/hypr. install.sh does not write
# those files either, and the .bak.centered-panel copies it used to restore
# from are frozen at whenever the prototype first ran -- they predate the blur
# enable, every layer rule here and QSG_RENDER_LOOP, so putting them back threw
# away the config the shell needs. The backups are still on disk; restoring one
# is a decision, not a cleanup.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=~/.config/omarchy/shell.json

# Remove first: even a later revert failure must not reinstall on the next update.
rm -f ~/.config/omarchy/hooks/post-update.d/centered-panels
echo "removed post-update hook"

# Everything install.sh put under $HOME. The id has to leave shell.json along
# with the link: an id listed for a plugin that is no longer there is an error
# on every shell start.
for p in "$REPO"/plugins/*/; do
  id=$(basename "$p")
  rm -f ~/.config/omarchy/plugins/"$id"
  # Guarded: under `set -e` a missing shell.json would abort the revert here,
  # before the patched files -- the part that matters -- are put back.
  if [[ -f $CONF ]]; then
    jq --arg id "$id" '.plugins = [.plugins[]? | select(.id != $id)]' \
       "$CONF" > "$CONF.new" && mv "$CONF.new" "$CONF"
  fi
  echo "removed $id"
done
rm -f ~/.local/bin/omarchy-open-path

for f in Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml; do
  sudo cp "$REPO/patches/orig/$f" "$SHELL_DIR/$f"
  echo "restored $f"
done

omarchy restart shell
