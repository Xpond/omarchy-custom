#!/bin/bash
# Install this repo into a live Omarchy: the plugins, the opener they call, and
# the centered-panel patch.
#
# Two halves, and only one of them wants root. The plugins are symlinked into
# ~/.config/omarchy/plugins and registered in ~/.config/omarchy/shell.json,
# all of it under $HOME and none of it touched by `omarchy update`. The patch
# writes three package-owned files under /usr/share/omarchy/shell, and that is
# the only reason sudo appears in this script at all -- asked for per file, and
# only when that file actually differs, so a re-run that finds everything in
# place never prompts.
#
# `omarchy update` overwrites those three files, so this script is idempotent
# and is wired to run automatically afterwards via
# ~/.config/omarchy/hooks/post-update.d/ (see hooks/), so an update repairs
# itself instead of silently reverting the shell to stock.
#
# When an update ships a NEW version of a patched file, the patch is rebased
# onto it with a three-way merge rather than blindly overwritten -- that would
# discard upstream's fixes without a word. A conflict leaves the file exactly
# as upstream shipped it: a half-merged QML file breaks the entire shell.
set -uo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILES=(Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml)
CONF=~/.config/omarchy/shell.json

# Both failure paths below leave the user with a broken shell, so both must be
# loud on screen AND on the desktop -- `omarchy update` output scrolls past.
alert() {
  printf '\n\e[31m%s\e[0m\n' "$1" >&2
  printf '%s\n' "${@:2}" >&2
  command -v notify-send >/dev/null && notify-send -u critical "omarchy-custom" "$1"
}

# ------------------------------------------------------------------ plugins
# Symlinks rather than copies: editing the repo IS editing the installed
# plugin, which is the whole reason these are plugins and not patches. -n so a
# re-run replaces the link instead of dropping a new one inside the old one.
# Linked and registered in one pass. A plugin the shell cannot find listed in
# shell.json is a plugin it does not load, and `omarchy refresh shell` rewrites
# that file from the defaults, so registering has to be repeatable rather than
# done once by hand. jq writes through a temp file: failing halfway into
# shell.json costs the whole shell config.
mkdir -p ~/.config/omarchy/plugins ~/.local/bin
ids=()
for p in "$REPO"/plugins/*/; do
  id=$(basename "$p")
  ln -sfn "${p%/}" ~/.config/omarchy/plugins/"$id"
  ids+=("$id")
  if jq --arg id "$id" 'if any(.plugins[]?; .id == $id) then .
                        else .plugins = (.plugins // []) + [{id: $id}] end' \
        "$CONF" > "$CONF.new"; then
    mv "$CONF.new" "$CONF"
  else
    rm -f "$CONF.new"
    alert "Could not register $id in shell.json"
  fi
done

# Files.qml runs the opener by name, so it has to be somewhere on PATH.
# ~/.local/bin is on Omarchy's. (omarchy-wheel-close is not here: the keybind
# names it by absolute path, so putting it on PATH would install nothing.)
ln -sfn "$REPO"/bin/omarchy-open-path ~/.local/bin/omarchy-open-path
echo "plugins: ${ids[*]}"

# ------------------------------------------------------------------- patches
applied=()   # patch copied in
rebased=()   # patch re-based onto a new upstream version first
conflicts=() # merge failed, left stock, needs a human
failed=()    # copy itself failed (e.g. no sudo)

for f in "${FILES[@]}"; do
  installed="$SHELL_DIR/$f"
  ours="$REPO/patches/shell/$f"
  base="$REPO/patches/orig/$f"
  prev="$REPO/.installed/$f"   # what this script last wrote to $installed

  # Already patched — nothing to do. This is the common case on a re-run.
  cmp -s "$installed" "$ours" && continue

  # After editing our own patch the installed file is the PREVIOUS patch, which
  # matches neither `ours` nor `base`. Comparing against base alone read that as
  # a new upstream and rebased our edit onto our own older patch -- which
  # conflicts once an edit lands in a hunk the patch already rewrote, and whose
  # success path overwrote orig/, the revert source. So rebase only when the
  # installed file matches neither what we last wrote nor the baseline.
  if ! cmp -s "$installed" "$prev" && ! cmp -s "$installed" "$base"; then
    merged=$(mktemp)
    cp "$ours" "$merged"
    git merge-file -q "$merged" "$base" "$installed"; ok=$?
    if (( ok == 0 )); then
      cp "$merged" "$ours"      # patch, now on the new base
      cp "$installed" "$base"   # new pristine baseline
      rebased+=("$f")
    fi
    rm -f "$merged"
    (( ok == 0 )) || { conflicts+=("$f"); continue; }
  fi

  if sudo cp "$ours" "$installed"; then
    applied+=("$f")
    mkdir -p "$(dirname "$prev")" && cp "$ours" "$prev"
  else
    failed+=("$f")
  fi
done

(( ${#rebased[@]} )) && printf 'rebased onto new upstream: %s\n' "${rebased[*]}"
(( ${#applied[@]} )) && printf 'installed: %s\n' "${applied[*]}"
(( ${#applied[@]} + ${#conflicts[@]} + ${#failed[@]} )) || echo "already up to date"

broken=("${conflicts[@]}" "${failed[@]}")
if (( ${#broken[@]} )); then
  msg=("Not patched: ${broken[*]}")
  (( ${#conflicts[@]} )) && msg+=("Conflicted against a new upstream version; left as upstream shipped it." \
                                  "Rebase by hand: diff orig/ against shell/ for the file(s) above.")
  alert "${msg[@]}"
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

(( render_ok )) || alert "Not on the threaded render loop — animations will judder" \
  'Expected hl.env("QSG_RENDER_LOOP", "threaded") in ~/.config/hypr/looknfeel.lua;' \
  'the legacy `env =` form in hyprland.conf is accepted silently and does nothing.' \
  'Then: hyprctl reload && omarchy restart shell'

# Config this script deliberately does NOT write. looknfeel.lua and
# bindings.lua are hand-kept Lua carrying the user's own comments, and a script
# splicing lines into those fails worse than a missing line it names out loud
# -- the same call the render-loop check above already makes. Advisory rather
# than fatal: this runs from a post-update hook, and a hook that fails the
# whole update over a keybind is a hook that gets uninstalled.
cfg=()
grep -qs omarchy-wheel ~/.config/hypr/looknfeel.lua ||
  cfg+=("looknfeel.lua: no layer rule for namespace omarchy-wheel -- the wheel gets no blur")
grep -qs omarchy-files ~/.config/hypr/looknfeel.lua ||
  cfg+=("looknfeel.lua: no layer rule for namespace omarchy-files -- the browser gets no blur")
grep -qs "summon xpo.wheel" ~/.config/hypr/bindings.lua ||
  cfg+=("bindings.lua: nothing runs 'omarchy-shell -q shell summon xpo.wheel' -- the wheel has no key")
(( ${#cfg[@]} )) && printf 'missing config:\n' && printf '  %s\n' "${cfg[@]}"

# Non-zero so the post-update hook prints "Hook failed" instead of passing
# silently with a stock or juddering shell.
(( ${#broken[@]} == 0 && render_ok == 1 ))
