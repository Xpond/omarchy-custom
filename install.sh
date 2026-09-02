#!/bin/bash
# Install the centered-panel patch into the packaged Omarchy shell.
#
# These three files are package-owned, so `omarchy update` overwrites them.
# This script is idempotent and is wired to run automatically afterwards via
# ~/.config/omarchy/hooks/post-update.d/ (see hooks/), so an update repairs
# itself instead of silently reverting the shell to stock.
#
# When an update ships a NEW version of a patched file, the patch is rebased
# onto it with a three-way merge rather than blindly overwritten -- blind
# overwriting would discard upstream's fixes without a word. A file whose
# merge conflicts is left exactly as upstream shipped it and reported loudly,
# because a half-merged QML file breaks the whole shell.
set -uo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILES=(Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml)

applied=()   # patch copied in
rebased=()   # patch re-based onto a new upstream version first
conflicts=() # merge failed, left stock, needs a human
failed=()    # copy itself failed (e.g. no sudo)

for f in "${FILES[@]}"; do
  installed="$SHELL_DIR/$f"
  ours="$REPO/shell/$f"
  base="$REPO/orig/$f"

  # Already patched — nothing to do. This is the common case on a re-run.
  cmp -s "$installed" "$ours" && continue

  # Installed differs from our pristine baseline, so upstream shipped a new
  # version of this file. Rebase rather than clobber.
  if ! cmp -s "$installed" "$base"; then
    merged=$(mktemp)
    cp "$ours" "$merged"
    if git merge-file -q "$merged" "$base" "$installed"; then
      cp "$merged" "$ours"      # patch, now on the new base
      cp "$installed" "$base"   # new pristine baseline
      rebased+=("$f")
    else
      conflicts+=("$f")
      rm -f "$merged"
      continue
    fi
    rm -f "$merged"
  fi

  if sudo cp "$ours" "$installed"; then applied+=("$f"); else failed+=("$f"); fi
done

(( ${#rebased[@]} )) && printf 'rebased onto new upstream: %s\n' "${rebased[*]}"
(( ${#applied[@]} )) && printf 'installed: %s\n' "${applied[*]}"
(( ${#applied[@]} + ${#conflicts[@]} + ${#failed[@]} )) || echo "already up to date"

# Anything unpatched leaves the shell stock, which is the exact failure this
# script exists to prevent -- so say so on screen AND on the desktop, since
# `omarchy update` output scrolls past.
broken=("${conflicts[@]}" "${failed[@]}")
if (( ${#broken[@]} )); then
  printf '\n\e[31mNOT PATCHED: %s\e[0m\n' "${broken[*]}" >&2
  (( ${#conflicts[@]} )) && {
    echo "Conflicted against a new upstream version; left as upstream shipped it." >&2
    echo "Rebase by hand: diff orig/ against shell/ for the file(s) above." >&2
  }
  command -v notify-send >/dev/null &&
    notify-send -u critical "Centered panels" "Not patched after update: ${broken[*]}"
fi

omarchy restart shell

# Check BEHAVIOUR, not configuration. The judder that cost this project days
# was a config line that was present, valid, accepted without error -- and
# silently inert, because legacy `env =` is ignored by Omarchy's Lua parser.
# Grepping the config would have "passed" the whole time. QSGRenderThread
# exists only under QSG_RENDER_LOOP=threaded; under `basic` the scene graph
# renders on the GUI thread and no such thread is created.
render_ok=0
for _ in $(seq 20); do
  pid=$(pgrep -x quickshell | head -1)
  if [[ -n $pid ]] && grep -qs QSGRenderThread /proc/"$pid"/task/*/comm; then
    render_ok=1; break
  fi
  sleep 0.5
done

if (( ! render_ok )); then
  printf '\n\e[31mNOT on the threaded render loop — animations will judder.\e[0m\n' >&2
  echo 'Expected: hl.env("QSG_RENDER_LOOP", "threaded") in ~/.config/hypr/looknfeel.lua' >&2
  echo 'The legacy `env = QSG_RENDER_LOOP,threaded` form in hyprland.conf is' >&2
  echo 'accepted silently and does nothing. Then: hyprctl reload && omarchy restart shell' >&2
  command -v notify-send >/dev/null &&
    notify-send -u critical "Centered panels" "Shell is not on the threaded render loop — animations will judder"
fi

# Non-zero so the post-update hook prints "Hook failed" instead of passing
# silently with a stock or juddering shell.
(( ${#broken[@]} == 0 && render_ok == 1 ))
