#!/bin/bash
# Install plugins and rebase the shell patches onto upstream changes.
set -uo pipefail

SHELL_DIR=/usr/share/omarchy/shell
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FILES=(Ui/KeyboardPanel.qml Ui/PanelKeyCatcher.qml plugins/bar/Bar.qml
       plugins/clipboard/Clipboard.qml services/PluginShellApi.qml shell.qml)
CONF=~/.config/omarchy/shell.json
STATE=~/.local/state/omarchy-custom

# Hook failures can scroll away, so report them on the desktop too.
alert() {
  printf '\n\e[31m%s\e[0m\n' "$1" >&2
  printf '%s\n' "${@:2}" >&2
  command -v notify-send >/dev/null && notify-send -u critical "omarchy-custom" "$1"
}

# ------------------------------------------------------------------ plugins
# Link plugins for live editing and register them idempotently via a temp file.
command -v jq >/dev/null || { alert "jq is required to register plugins"; exit 1; }
mkdir -p ~/.config/omarchy/plugins ~/.local/bin || exit 1
if [[ ! -e $CONF ]]; then
  printf '{"plugins": []}\n' > "$CONF" || exit 1
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

# Files.qml resolves its opener through PATH.
ln -sfn "$REPO"/bin/omarchy-open-path ~/.local/bin/omarchy-open-path || plugins_ok=0
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
failed=()    # backup or installation failed

for f in "${FILES[@]}"; do
  installed="$SHELL_DIR/$f"
  ours="$REPO/patches/shell/$f"
  base="$REPO/patches/orig/$f"
  saved="$STATE/orig/$f"
  written="$STATE/installed/$f"
  prev="$written"
  [[ -f $prev ]] || prev="$REPO/.installed/$f"  # older installs have no backup

  # Never treat an incomplete copy as upstream and overwrite its recovery backup.
  if [[ -f $written.pending ]]; then
    if ! cmp -s "$installed" "$written" && ! cmp -s "$installed" "$saved"; then
      alert "Incomplete shell write: $f; left untouched" "Restore from backup before retrying: $saved"
      failed+=("$f"); continue
    fi
    rm -f "$written.pending" || { failed+=("$f"); continue; }
  fi
  cmp -s "$installed" "$ours" && continue

  # Rebase only a real upstream change, not the previous version of our patch.
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

  # Save the current machine's file, not the repository's mutable merge base.
  # Reinstalling our own patch must not replace its original backup.
  if ! mkdir -p "$(dirname "$saved")" "$(dirname "$written")"; then
    failed+=("$f"); continue
  fi
  if [[ ! -f $saved ]] || ! cmp -s "$installed" "$prev"; then
    if ! { cp -p "$installed" "$saved.new" && mv "$saved.new" "$saved"; }; then
      rm -f "$saved.new"
      failed+=("$f"); continue
    fi
  fi
  # Record the expected bytes before copying so an interrupted install is recoverable.
  if ! { touch "$written.pending" && cp "$ours" "$written.new" && mv "$written.new" "$written"; }; then
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
(( ${#applied[@]} + ${#conflicts[@]} + ${#failed[@]} )) || echo "already up to date"

broken=("${conflicts[@]}" "${failed[@]}")
if (( ${#broken[@]} )); then
  msg=("Not patched: ${broken[*]}")
  (( ${#conflicts[@]} )) && msg+=("Merge conflicted; installed files left untouched." \
                                  "Rebase by hand: diff orig/ against shell/ for the file(s) above.")
  alert "${msg[@]}"
fi

omarchy restart shell

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
  'Expected hl.env("QSG_RENDER_LOOP", "threaded") in ~/.config/hypr/looknfeel.lua;' \
  'the legacy `env =` form in hyprland.conf is accepted silently and does nothing.' \
  'Then: hyprctl reload && omarchy restart shell'

# Report missing user-owned Lua config without rewriting it or failing the hook.
cfg=()
grep -qs omarchy-wheel ~/.config/hypr/looknfeel.lua ||
  cfg+=("looknfeel.lua: no layer rule for namespace omarchy-wheel -- Hyprland fades its map and unmap")
grep -qs omarchy-files ~/.config/hypr/looknfeel.lua ||
  cfg+=("looknfeel.lua: no layer rule for namespace omarchy-files -- Hyprland fades its map and unmap")
grep -qs "summon xpo.wheel" ~/.config/hypr/bindings.lua ||
  cfg+=("bindings.lua: nothing runs 'omarchy-shell -q shell summon xpo.wheel' -- the wheel has no key")
(( ${#cfg[@]} )) && printf 'missing config:\n' && printf '  %s\n' "${cfg[@]}"

# Fail the hook when installation or rendering failed.
(( plugins_ok == 1 && ${#broken[@]} == 0 && render_ok == 1 ))
