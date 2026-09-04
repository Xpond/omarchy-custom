# The wheel

A radial control center for Omarchy, on `SUPER+A`.

Eight panels sit on a ring, reachable by direction; typing turns the hub into
a search over every entry in the Omarchy menu. It replaces reaching for eight
separate `SUPER+CTRL` shortcuts with one key and a direction.

    plugins/xpo.wheel/
      manifest.json   kind: "overlay", keepLoaded
      Wheel.qml       surface, input model, ring and result UI
      MenuIndex.js    JSONC parsing, flattening, search

## Keys

| | |
|---|---|
| `SUPER+A` | open (tap — do not hold, see below) |
| `↑` `↓` `←` `→` | `↑` Audio · `↓` Menu · `←` Display · `→` System, then `←`/`→` step around the ring |
| `Enter` | fire the highlighted slice |
| type anything | search all 271 menu actions |
| `Esc` | clear the query, then close |
| `SUPER+W` | close the wheel and whatever it opened |

Mouse works too: the whole screen is a compass around center, so a flick in
any direction selects that slice. Release of `SUPER+A` commits it.

## Why a plugin and not a patch

Third-party plugins live in `~/.config/omarchy/plugins/<id>/` and are
discovered from a `manifest.json`. The shell injects `shell` into the loaded
item, which means a plugin can call `shell.toggle("omarchy.audio")` and drive
every existing panel without touching packaged code. Nothing in
`/usr/share/omarchy` is modified, so `omarchy update` cannot break it and
there is no merge to maintain.

`import qs.Commons` and `import qs.Ui` resolve from a third-party plugin, so
the theme singletons (`Color`, `Style`, `Border`) and shared widgets
(`CursorSurface`, `BorderSurface`) are all available. The wheel has no colours
of its own — it reads the `[menu]` theme tokens, so it follows theme switches
for free.

## Traps

**`SUPER`+arrows never reach the client.** Hyprland binds `SUPER+↑/↓/←/→` to
"Focus on <dir> window" and consumes them before any surface sees them. The
hold-a-modifier-and-flick-with-arrows gesture is therefore impossible on a
stock Omarchy keymap; the wheel is tap-then-arrow instead. Bare arrows reach
it fine, confirmed by logging `Keys.onPressed`.

**The pointer-enter is a synthetic move.** When the layer surface maps, Wayland
delivers a pointer enter carrying the cursor's current position, and Qt raises
it as `onPositionChanged`. Arming selection on that means a bare tap fires
whichever slice the cursor happened to point at. The first sample is kept as an
origin and selection only arms once the pointer has travelled past a threshold.

**`omarchyPath` is injected after the component loads.** The host sets it in
the Loader's `onLoaded`, which is *after* first binding evaluation — a
`FileView` bound to it reads an empty path and fails. Default it from
`Quickshell.env("OMARCHY_PATH")` and let the injection override.

**Editing a plugin needs a shell restart.** `rescanPlugins` re-walks manifests
but QML components are cached, so changed code keeps running the old version.
Use `omarchy-restart-shell`.

**`SUPER+W` must be conditional.** The wheel is a layer surface, not a window,
so a plain `killactive` with the wheel up closes whatever window sits behind
the scrim. `bin/omarchy-wheel-close` asks the wheel to close first and falls
through to close-window only when nothing of ours was on screen. It fails
*open*: any unreachable shell still closes the window, on a 0.5s timeout,
because this runs on every window close.

Two things about that script are load-bearing, and both were bugs first:

**`hyprctl dispatch killactive` does nothing.** Omarchy 4's Hyprland takes Lua
dispatchers — `hyprctl` wraps the argument as `hl.dispatch(<arg>)`, so the
legacy string form is rejected at runtime with a nonzero exit and the window
simply never closes. Use `hyprctl dispatch 'hl.dsp.window.close()'`. This is
the same trap as `env =` in `hyprland.conf` and `layerrule`: the old syntax is
accepted by the tooling and inert in practice.

**Do not use `omarchy-shell -q` when you need the answer.** Quiet mode
suppresses stdout (`if (( !QUIET )) && [[ -n $output ]]`), so the result never
comes back and every press takes the fallback. Plain `omarchy-shell` still
writes failures to stderr, so redirecting stderr keeps the fail-open
behaviour.

## Search

`MenuIndex.js` reads both menu definitions —
`$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` and
`~/.config/omarchy/extensions/omarchy-menu.jsonc` — strips JSONC comments and
trailing commas, and merges the user's over the defaults by id. Ids are dotted
(`trigger.capture.qr`), so an entry's breadcrumb is just its ancestors' labels.

Entries without an `action` are submenus and are skipped; their labels still
appear as breadcrumbs. That yields 271 searchable rows from 320 entries.

Every query term must appear somewhere in the row, so terms narrow. Ranking is
label-prefix, then label-substring, then a hit anywhere else (breadcrumb,
alias, description), with shorter labels breaking ties.

`when:` conditions are **not** evaluated — they need a bash round trip per
entry, which the shell's own menu batches at startup. Hardware-specific rows
therefore appear in search on machines they don't apply to.

## Known limits

- Opens on the primary monitor only, same as the emoji overlay.
- The 8 ring slices are hard-coded in `Wheel.qml`; there is no config file yet.
