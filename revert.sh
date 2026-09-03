#!/bin/bash
# Restore the packaged Omarchy shell and the Hyprland config this prototype
# touched. Safe to run at any time.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

for f in Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml; do
  sudo cp "$REPO/patches/orig/$f" "$SHELL_DIR/$f"
  echo "restored $f"
done

for f in hyprland.conf looknfeel.lua; do
  if [[ -f ~/.config/hypr/$f.bak.centered-panel ]]; then
    cp ~/.config/hypr/"$f".bak.centered-panel ~/.config/hypr/"$f"
    echo "restored ~/.config/hypr/$f"
  fi
done

hyprctl reload >/dev/null
omarchy restart shell
