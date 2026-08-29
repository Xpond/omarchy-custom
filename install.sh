#!/bin/bash
# Install the centered-panel prototype into the packaged Omarchy shell.
#
# These files are package-owned: `omarchy update` will overwrite them.
# Re-run this script after an update, or run revert.sh to go back.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d%H%M%S)

FILES=(Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml)

# Refuse to run against a tree that no longer matches what we patched, so an
# update can't silently get half the prototype.
for f in "${FILES[@]}"; do
  if ! cmp -s "$SHELL_DIR/$f" "$REPO/orig/$f"; then
    echo "warning: $SHELL_DIR/$f differs from orig/$f" >&2
    echo "         (omarchy was probably updated -- re-baseline orig/ first)" >&2
  fi
done

for f in "${FILES[@]}"; do
  sudo cp -a "$SHELL_DIR/$f" "$SHELL_DIR/$f.bak.$STAMP"
  sudo cp "$REPO/shell/$f" "$SHELL_DIR/$f"
  echo "installed $f (backup: $f.bak.$STAMP)"
done

omarchy restart shell
