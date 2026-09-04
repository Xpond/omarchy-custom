# The wheel

A radial control center for Omarchy, on `SUPER+A`.

Eight panels sit on a ring, reachable by direction; typing turns the hub into
a search over every entry in the Omarchy menu, every installed app, every open
window, and every theme and font. It replaces reaching for eight separate
`SUPER+CTRL` shortcuts with one key and a direction.

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
| type anything | search menu actions, apps, windows, themes and fonts |
| `Esc` | clear the query, then close |
| `SUPER+W` | close the wheel and whatever it opened |

Mouse works too: the whole screen is a compass around center, so a flick in
any direction selects that slice. Release of `SUPER+A` commits it.

## The comet

An accent arc rides the dial under the selected disc. It is drawn from two
followers chasing one target (`arcTarget`) at different speeds -- `arcHead`
over 90ms, `arcTail` over 300ms -- so the gap between them is a readout of how
fast the ring is being turned, with no velocity tracking or timers anywhere.
Step slowly and both settle on the selection, leaving a short arc bracketing
the disc. Hold `←`/`→` at the 40Hz key repeat and the tail falls several
slices behind, stretching the arc into a streak that runs around the ring and
retracts when you let go. `select()` adds the shortest delta to `arcTarget`
rather than assigning it, which keeps the target unwrapped so a lap past north
runs forward instead of unwinding backwards; the drag is clamped at 300° since
an arc past a full turn is just the circle again.

The dial's stroke runs through every disc's **center**, so slice labels sit
outside the ring on their own spokes rather than hung under their discs -- a
label below the east or west disc lands exactly on the arc's path. The reach
is measured to the label box's nearest edge (`|cos|·width + |sin|·height`) so
every label clears its disc by `labelGap` whatever its width and angle, and it
is measured from the disc's *grown* radius so selecting a slice does not close
the gap as the disc scales up.

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

**Legacy Hyprland dispatchers do nothing.** Omarchy 4's Hyprland takes Lua
dispatchers — `hyprctl` wraps the argument as `hl.dispatch(<arg>)`, so the
legacy string form is rejected at runtime and the action never happens. Same
trap as `env =` in `hyprland.conf` and `layerrule`: accepted by the tooling,
inert in practice. Two of these bit this project.

`killactive` fails loudly, with a nonzero exit; use `hl.dsp.window.close()`.
Focusing a window fails *silently*: Quickshell's `HyprlandToplevel.activate()`
returns without error and focus simply does not move, because it sends
`focuswindow` under the hood. Use `hl.dsp.focus({ window = "address:0x..." })`.
Note the `0x` — Quickshell reports the address without it, and Hyprland only
matches it with one.

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

Applications come from `shell.appLibrary` (`services/AppLibrary.qml`), which
wraps Quickshell's `DesktopEntries`: it sorts, drops entries marked hidden,
resolves an icon name to a file, and launches through `uwsm-app -- gtk-launch`
so an app does not inherit the compositor's service scope.

Open windows come from `Hyprland.toplevels`. A row carries the window's address
rather than its toplevel object, so it can never go stale on a window that has
since closed, and focusing one is a `Hyprland.dispatch` — see the trap below.

Themes and fonts are `omarchy theme list` and `omarchy font list`, run once at
startup and fired back as `omarchy theme set '<name>'`. Both are otherwise
buried: `style.theme` in the menu shells out to `omarchy-theme-switcher`, a
second overlay on top of the first.

The live half of the index — apps, windows, themes, fonts — is rebuilt when the
wheel opens. That is the only moment any of it has to be correct, and it means
they are all as fresh as the keystroke that asked for them. The menu half is
not rebuilt: `MenuIndex.menuRows()` runs once per file load, because flattening
271 entries costs 1.6ms against 0.4ms for everything else together, and it
returns the same answer every time. Opening the wheel costs 0.5ms of index
work; a keystroke costs 0.06ms to search all 352 rows.

Every query term must appear somewhere in the row, so terms narrow. Rows then
sort on four keys: **rank** (label-prefix, then label-substring, then a hit
anywhere else — breadcrumb, alias, app id), **kind** (slice, window, app,
theme/font, menu), **recency**, and finally **label length**, which floats
"Screenshot" over "Stop Screenrecording".

An open window is never a weak hit: matching one at all counts as rank 0. A
window's title is written by the program, so a query lands mid-string
("…Omarchy Plugins - Brave") where a menu label has it at the front — without
this the window you are looking at sorts below seven rows offering to install
the thing.

Recency orders the windows among themselves, most recently focused first, and
is inert for every other row. Hyprland publishes a `focusHistoryID`, but only
inside each toplevel's cached IPC object, which is **not** re-fetched when
focus moves — it keeps reporting the order from whenever the list was last
pulled. `Hyprland.activeToplevel` does track focus, so the wheel accumulates
the order from that instead, and falls back to the cached history for windows
it has not yet seen focused (everything, for a moment after a shell restart).

`when:` conditions are **not** evaluated — they need a bash round trip per
entry, which the shell's own menu batches at startup. Hardware-specific rows
therefore appear in search on machines they don't apply to.

## Known limits

- Opens on the primary monitor only, same as the emoji overlay.
- A window is found by its title or its app id, never by what is running
  inside it: a terminal holding a Claude Code session is titled after the
  session's topic, so `claude` will not find it. Searching the app id
  (`kitty`) lists every window of that app, most recent first.
- The 8 ring slices are hard-coded in `Wheel.qml`; there is no config file yet.
