#!/bin/bash
# Install the centered-panel prototype into the packaged Omarchy shell.
#
# These files are package-owned: `omarchy update` will overwrite them.
# Re-run this script after an update, or run revert.sh to go back.
set -euo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

FILES=(Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml)

# Clear out timestamped backups from earlier versions of this script, which
# made a fresh copy on every single run.
old=$(sudo find "$SHELL_DIR" -name '*.qml.bak.[0-9]*' -print -delete 2>/dev/null | wc -l)
(( old > 0 )) && echo "removed $old stale timestamped backup(s)"

for f in "${FILES[@]}"; do
  installed="$SHELL_DIR/$f"
  backup="$installed.omarchy-original"

  # One backup, taken the first time only. On later runs the installed file is
  # already our own patched copy, so backing it up again just makes noise --
  # and would overwrite the pristine copy with a patched one.
  if [[ ! -f $backup ]]; then
    sudo cp -a "$installed" "$backup"
    echo "saved pristine $f -> $(basename "$backup")"
  fi

  # Only a file matching neither the pristine nor the patched copy is a
  # surprise; that means omarchy shipped a new version of it.
  if ! cmp -s "$installed" "$REPO/orig/$f" && ! cmp -s "$installed" "$REPO/shell/$f"; then
    echo "warning: $f does not match orig/ or shell/ -- omarchy probably updated it." >&2
    echo "         Re-baseline orig/ from the new packaged file before trusting this patch." >&2
  fi

  sudo cp "$REPO/shell/$f" "$installed"
  echo "installed $f"
done

omarchy restart shell
