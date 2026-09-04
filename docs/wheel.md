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

The whole index is rebuilt when the wheel opens. That is the only moment any of
it has to be correct, and it means windows, apps and menu entries are all as
fresh as the keystroke that asked for them.

Every query term must appear somewhere in the row, so terms narrow. Ranking is
label-prefix, then label-substring, then a hit anywhere else (breadcrumb,
alias, description), with shorter labels breaking ties. A dead heat past that
goes by `KIND` — slice, window, app, theme/font, menu — so "chromium", which
matches the app and the menu's install/set-default rows identically, lands on
the app.

`when:` conditions are **not** evaluated — they need a bash round trip per
entry, which the shell's own menu batches at startup. Hardware-specific rows
therefore appear in search on machines they don't apply to.

## Known limits

- Opens on the primary monitor only, same as the emoji overlay.
- A window is found by its title, and only ranks well when the title starts
  with the query. `brave` puts the browser's window last, behind seven menu
  rows, because its title reads "Browse Plugins | Omarchy Plugins - Brave".
  Searching the app id (`kitty`) lists every window of that app together,
  which is the reliable way in.
- The 8 ring slices are hard-coded in `Wheel.qml`; there is no config file yet.
