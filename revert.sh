#!/bin/bash
# Remove installed plugins and put back Omarchy's own shell files where ours are installed.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONF=~/.config/omarchy/shell.json
STATE=~/.local/state/omarchy-custom
source "$REPO/scripts/shell-files.sh"

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

# Only bytes matching pacman's checksum are written, and only over files that are ours.
failed=0
stock=$(mktemp)
trap 'rm -f "$stock"' EXIT
for f in Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml \
         plugins/clipboard/Clipboard.qml services/PluginShellApi.qml shell.qml; do
  installed="$SHELL_DIR/$f"
  written="$STATE/installed/$f"
  if [[ -z $(stock_sum "$f") ]]; then
    echo "Not restored: $f — no package checksum to verify stock against; left untouched" >&2
    failed=1; continue
  fi
  if ! is_stock "$f" "$installed"; then
    if ! is_ours "$f" "$installed"; then
      echo "Not restored: $f — changed outside this project; left untouched" >&2
      failed=1; continue
    fi
    if ! stock_copy "$f" "$stock"; then
      echo "Not restored: $f — no verified stock copy in patches/orig or the package cache" >&2
      failed=1; continue
    fi
    mkdir -p "$(dirname "$written")"
    if ! touch "$written.pending" || ! sudo cp "$stock" "$installed" || ! is_stock "$f" "$installed"; then
      echo "Could not restore $f; rerun revert.sh" >&2
      failed=1; continue
    fi
    echo "restored $f"
  fi
  rm -f "$written" "$written.pending"
done
find "$STATE" -depth -type d -empty -delete 2>/dev/null || true

omarchy restart shell
(( failed == 0 ))
