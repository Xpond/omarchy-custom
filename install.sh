#!/bin/bash
# Install plugins and rebase the shell patches onto upstream changes.
set -uo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILES=(Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml
       plugins/clipboard/Clipboard.qml services/PluginShellApi.qml shell.qml)
CONF=~/.config/omarchy/shell.json
STATE=~/.local/state/omarchy-custom
source "$REPO/scripts/shell-files.sh"

# Hook failures can scroll away, so report them on the desktop too.
alert() {
  printf '\n\e[31m%s\e[0m\n' "$1" >&2
  printf '%s\n' "${@:2}" >&2
  command -v notify-send >/dev/null && notify-send -u critical "omarchy-custom" "$1"
}

# ------------------------------------------------------------------ plugins
# Link plugins for live editing and register them idempotently via a temp file.
command -v jq >/dev/null || { alert "jq is required to register plugins"; exit 1; }
command -v python3 >/dev/null || { alert "python3 is required to manage user configuration"; exit 1; }
command -v hyprctl >/dev/null || { alert "hyprctl is required to validate user configuration"; exit 1; }
python3 "$REPO/scripts/user-config.py" install ~/.config/hypr/hyprland.lua "$STATE" ~/.local/bin || exit 1
mkdir -p ~/.config/omarchy/plugins ~/.local/bin || exit 1
if [[ ! -e $CONF ]]; then
  cp "${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json" "$CONF" || exit 1
fi
plugins_ok=1
ids=()
for p in "$REPO"/plugins/*/; do
  id=$(basename "$p")
  if ln -sfn "${p%/}" ~/.config/omarchy/plugins/"$id" &&
     jq --arg id "$id" 'if any(.plugins[]?; .id == $id) then .
                        else .plugins = (.plugins // []) + [{id: $id}] end' \
        "$CONF" > "$CONF.new" && mv "$CONF.new" "$CONF"; then
    ids+=("$id")
  else
    plugins_ok=0
    rm -f "$CONF.new"
    alert "Could not register $id in shell.json"
  fi
done

(( ${#ids[@]} )) && echo "plugins: ${ids[*]}"

# The copied hook is a shell-quoted trampoline back to this checkout.
hook_dir=$(mktemp -d) || exit 1
printf '#!/bin/bash\nexec %q\n' "$REPO/install.sh" > "$hook_dir/centered-panels" &&
  omarchy hook install post-update "$hook_dir/centered-panels" || {
    plugins_ok=0
    alert "Could not install the post-update hook"
  }
rm -rf "$hook_dir"

# ------------------------------------------------------------------- patches
applied=()   # patch copied in
rebased=()   # patch re-based onto a new upstream version first
conflicts=() # merge failed; installed file left untouched
foreign=()   # neither stock nor ours; installed file left untouched
failed=()    # recording or installation failed

for f in "${FILES[@]}"; do
  installed="$SHELL_DIR/$f"
  ours="$REPO/patches/shell/$f"
  base="$REPO/patches/orig/$f"
  written="$STATE/installed/$f"
  cmp -s "$installed" "$ours" && continue

  # Stock that differs from the merge base is a new upstream version to rebase onto.
  # Any version of our patch is simply replaced; anything else is not ours to touch.
  if is_stock "$f" "$installed"; then
    if ! cmp -s "$installed" "$base"; then
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
  elif ! is_ours "$f" "$installed"; then
    foreign+=("$f"); continue
  fi

  # Record the bytes, then mark the copy pending, so an interrupted copy is still ours.
  if ! { mkdir -p "$(dirname "$written")" && cp "$ours" "$written.new" &&
         mv "$written.new" "$written" && touch "$written.pending"; }; then
    rm -f "$written.new"
    failed+=("$f"); continue
  fi
  if sudo cp "$ours" "$installed" && cmp -s "$ours" "$installed" && rm -f "$written.pending"; then
    applied+=("$f")
  else
    failed+=("$f")
  fi
done

(( ${#rebased[@]} )) && printf 'rebased onto new upstream: %s\n' "${rebased[*]}"
(( ${#applied[@]} )) && printf 'installed: %s\n' "${applied[*]}"
(( ${#applied[@]} + ${#conflicts[@]} + ${#foreign[@]} + ${#failed[@]} )) || echo "already up to date"

broken=("${conflicts[@]}" "${foreign[@]}" "${failed[@]}")
if (( ${#broken[@]} )); then
  msg=("Not patched: ${broken[*]}")
  (( ${#conflicts[@]} )) && msg+=("Merge conflicted; installed files left untouched." \
                                  "Rebase by hand: diff orig/ against shell/ for: ${conflicts[*]}")
  (( ${#foreign[@]} )) && msg+=("Files changed outside this project, left untouched: ${foreign[*]}" \
                                "Reinstall the omarchy package to restore them, then rerun install.sh.")
  alert "${msg[@]}"
fi

omarchy restart shell || { alert "Could not restart Omarchy shell"; exit 1; }

# Verify the render thread itself; legacy Lua config can be accepted but inert.
render_ok=0
for _ in $(seq 20); do
  pid=$(pgrep -x quickshell | head -1)
  if [[ -n $pid ]] && grep -qs QSGRenderThread /proc/"$pid"/task/*/comm; then
    render_ok=1; break
  fi
  sleep 0.5
done

(( render_ok )) || alert "Not on the threaded render loop — animations will judder" \
  'Check the managed block at the end of ~/.config/hypr/hyprland.lua;' \
  'Then: hyprctl reload && omarchy restart shell'

# Fail the hook when installation or rendering failed.
(( plugins_ok == 1 && ${#broken[@]} == 0 && render_ok == 1 ))
