# The wheel

A radial control center for Omarchy, on `SUPER+A`.

Your bar's panels sit on a ring, reachable by direction; typing turns the hub
into a search over every entry in the Omarchy menu, every installed app, every
open window, and every theme and font. It replaces reaching for a handful of
separate `SUPER+CTRL` shortcuts with one key and a direction.

The ring is for things that have a widget. Everything else in the menu —
Install, Remove, Update and the rest — is one search away instead of one more
disc, because a ring you have to read is slower than a word you can type.

    plugins/xpo.wheel/
      manifest.json   kind: "overlay", keepLoaded
      Wheel.qml       surface, input model, ring and result UI
      MenuIndex.js    JSONC parsing, flattening, search

## Keys

| | |
|---|---|
| `SUPER+A` | open (tap — do not hold, see below) |
| `↑` `↓` `←` `→` | jump to the slice at that compass point, then `←`/`→` step around the ring |
| `Enter` | fire the highlighted slice, or open it if it is a submenu |
| type anything | search menu entries, apps, windows, themes and fonts |
| `Backspace` | delete a character, then go up one level |
| `Ctrl+W` `Ctrl+Backspace` | delete the last word of the query |
| `Ctrl+U` | clear the query |
| `Ctrl+V` | paste into the query, runs of whitespace collapsed to one space |
| `Esc` | clear the query, then go up one level, then close |
| `SUPER+W` | close the wheel and whatever it opened |

Mouse works too: the whole screen is a compass around center, so a flick in
any direction selects that slice. Release of `SUPER+A` commits it. The scroll
wheel steps the ring one slice per notch, or the result list while searching.

Clicking the field or the result stack does nothing, rather than closing the
wheel: everywhere else a click away closes it, and the two surfaces you are
most likely to hit by accident -- the thing shaped like a text field, and the
gap beside a row you missed -- must not count as "away". Neither is clickable
in any other sense, and neither shows a hover state, because there is nothing
to click for: the field always holds the keyboard, so a click can do nothing a
keystroke does not already do.

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

## Transitions

One tempo, `fadeDuration`, drives the whole wheel: the open, the close, and
the ring-to-results swap.

The exit fade is the half that used to be missing. `visible` follows `opened`,
so dropping it unmapped the layer surface the same frame it asked for the
fade -- the wheel eased in and vanished out. `close()` now drops `shown` to run
the fade and a timer releases the surface once it has finished. Firing a slice
keeps the instant unmap: the target panel grabs the keyboard on the next tick
and a layer surface still holding an exclusive grab hands it a window without
focus, so `close(true)` skips the fade. Only cancelling gets it. Reopening
mid-fade cancels the pending unmap and counts as a fresh open.

Typing swaps the ring for the results by fading rather than switching
`visible`: the ring draws back to 0.94 while the stack grows from
`transformOrigin: Item.Top`, pinned under the pill. Both still drop out of
`visible` once faded -- the result rows carry `MouseArea`s, so a transparent
stack would keep catching clicks meant for the ring behind it.

The results are not a card. Each row is a capsule wearing the disc's own fill
and hairline, standing on the scrim the way a disc does, one size down from the
field so the field stays the largest thing in the hole. A box holding rows is a
second surface language, and the jump from a dial of discs into one is the
thing the wheel's geometry exists to avoid. Selection is the same signature
everywhere -- accent fill, accent hairline, accent label -- on a disc, on a
bead, and on a row of the file browser.

Opening spins the comet once around the ring -- the wheel introduces itself
with the streak it already draws. `spin` is a `Timer` that steps `arcTarget`
by a whole slice every 25ms for one lap, and it has to work that way: the
streak *is* the gap the two followers open up behind a jump, so a target that
slides smoothly is tracked almost exactly and draws no trail at all. Eight
45-degree jumps 25ms apart is the same 40Hz input a held arrow delivers, which
is why it produces the same streak. Selecting during the lap stops the timer.

The comet shows while anything is selected or while `arcDrag` is non-zero, so
it stays up past the end of the lap for as long as the tail needs to catch up,
then fades on its own.

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

**Every entry in the menu is a row.** Entries with an `action` run it. Entries
without one are submenus, and they are rows too — searching `install` has to
find Install, not only the things filed under it; picking one turns the ring
into its children, `Backspace` goes back up, and the hub prints where you are.
That is the only reason the ring drills at all; the default ring has no
submenus on it.

The exception is a `provider`, whose rows the menu generates at runtime — the
app list, the installed fonts. The wheel cannot render those, so a provider row
hands the whole route to `omarchy-menu summon <id>` rather than being dropped.
That also covers any provider a later Omarchy adds that `MenuIndex.js` has
never heard of.

That invariant is checked rather than asserted. `check.js` runs the real index
against this machine's real menu files:

    node plugins/xpo.wheel/check.js

- every entry whose `when` passes, and that is not a submenu emptied by its
  children's, appears in `menuRows()`
- every row has an action or a node
- no node opens onto an empty ring
- `Wheel.qml` calls only what `MenuIndex.js` defines
- the shipped bar and this machine's bar both give an even ring

Run it after touching `MenuIndex.js`, and against a new Omarchy release — the
menu file is upstream's, and a new entry shape is exactly what would slip
through. As of Omarchy 4.0.2: 320 entries in, 241 rows out, 0 unreachable. The
79 absent are rows whose `when` failed on this machine.

`when:` is evaluated. Every condition in both menu files goes out as **one**
bash script — each line echoes its own id when its condition holds — rather
than a subprocess per entry. It runs once at startup, in the background, and
takes about 1.2s for the 144 conditions in the stock menu; pressing `SUPER+A`
is not the moment to spend that, and installing a package is rare enough that
one stale reading until the next shell restart is the right trade. A `when`
that fails hides the row, and a submenu whose children all failed is hidden
too, so a slice never drills into an empty ring. On this machine that is 239
rows out of 320 — the other 81 are for hardware and packages that aren't here.

`checked:` is **not** evaluated. It only appends a ✓, and it would have to
re-run on every open to be true.

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
they are all as fresh as the keystroke that asked for them. The menu half is a
binding rather than a per-open rebuild: flattening the menu costs several times
what everything else costs together, and it only changes when the menu files
load or when the conditions come back. When they do come back — after the wheel
is already on screen — the ring re-reads them on its own, and `onStaticRowsChanged`
tells the index to rebuild, since that half is built by hand.

Every query term must appear somewhere in the row, so terms narrow. Rows then
sort on four keys: **rank** (label-prefix, then label-substring, then a hit
anywhere else — breadcrumb, alias, app id), **kind** (slice, window, app,
theme/font, menu), **recency**, and finally **label length**, which floats
"Screenshot" over "Stop Screenrecording".

`search()` and `fileRows()` both scan the whole index and sort every hit before
they truncate, so the depth they are asked for costs only the rows themselves.
They are asked for 40, and the stack shows 8 of them: `resultTop` is the first
row on screen and `showResult()` walks it by one whenever the selection steps
past an edge, jumping outright when the selection wraps around an end. The
`Repeater` is fed that window, so eight delegates exist however deep the list
runs. A rail beside the stack -- the same one the file browser runs beside its
list -- is what says the ninth row is there at all.

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

## What it remembers

Every pick is counted, keyed by `MenuIndex.keyOf` -- a panel's plugin id, a
menu entry's dotted id, `app:` plus a desktop id, or a theme/font command --
and the count is a sort key in `search()` ranked under `kind`. So habit breaks
ties *inside* a kind (which of forty themes, which of the eleven "Toggle"
rows) and never reorders the kinds themselves: that an app beats a menu row
offering to install it is a fact about the query, while a use count is only a
guess.

Windows are deliberately uncounted -- their address is new on every launch, so
counting them would grow the file without bound, and they already sort on live
focus order. `check.js` holds both invariants: every counted row has a key,
and no two share one.

The counts live in `~/.local/state/omarchy/wheel-uses.json`, written through on
each pick rather than batched at exit -- the wheel is a plugin in a shell that
gets restarted, so no orderly shutdown is guaranteed to arrive. Delete the file
to forget everything. There is no decay: what you reach for through a wheel is
stable for months, and a half-life is a second knob to be wrong about.

## The ring

By default the ring is the panels your bar carries, in a fixed order, plus the
clipboard overlay — which is not a bar widget, so nothing in the bar vouches
for it. Adding a widget to the bar adds it to the wheel; the wheel is not a
second list to keep in sync with the first. A machine that has never edited its
bar has no user config, so the layout Omarchy ships
(`$OMARCHY_PATH/config/omarchy/shell.json`) is read instead — otherwise the
ring would offer panels that machine has no widget for.

To choose the ring yourself, write `~/.config/omarchy/wheel.json`:

```json
{
  "slices": [
    "omarchy.audio",
    "omarchy.network",
    "omarchy.clipboard",
    "system",
    "trigger.capture",
    "style"
  ]
}
```

Each id is either a panel — `omarchy.audio`, `network`, `bluetooth`, `monitor`,
`clock`, `tailscale`, `agents`, `dropbox`, `power`, `clipboard` — or a menu id from
`omarchy-menu.jsonc`. A menu id that has an action runs it; one that is a
submenu drills the ring into it. Ids that name nothing are dropped. The file is
watched, so the ring changes as you save; delete it to go back to the bar's
widgets.

Every icon in that catalogue is one the widget itself already draws. Tailscale
and Dropbox have no Nerd Font glyph — Omarchy renders each as a QML shape of
its own — so those two carry an `iconFile` and the wheel loads that component
off `omarchyPath`. There is no codepoint that stands in for a product's mark,
and picking one that looks close is how you ship a logo the product doesn't
have.

**Keep the count even.** East and west are half a turn apart, so half a turn
has to be a whole number of steps, which only happens when the count is even.
An even ring is rotated so two slices land at 3 and 9 o'clock, flanking the
field; an odd one is still evenly spaced but anchors north instead, and nothing
sits beside the field. Eight got this for free at 45° apart and never had to
say so.

The catalogue is sized so the default lands even on a stock machine: the bar
Omarchy ships carries seven of these plus the clipboard overlay. Changing
`PANELS` means re-checking that.

The ring sizes itself to what it holds. It keeps a constant arc distance per
slice and grows its radius to pay for it, so a disc and its label have the same
room at fourteen slices as at eight. Growth stops before the labels would run
off the short edge of the screen, and only then do the discs shrink to fit the
chord between their neighbours.

Slices are evenly spaced; the only choice is where the first one goes, which is
`sliceOrigin` — `90 % step` on an even count so a slice lands on east and one
on west, `0` on an odd one so the ring at least stays symmetric about the
vertical.

## Known limits

- Opens on the primary monitor only, same as the emoji overlay.
- A window is found by its title or its app id, never by what is running
  inside it: a terminal holding a Claude Code session is titled after the
  session's topic, so `claude` will not find it. Searching the app id
  (`kitty`) lists every window of that app, most recent first.
- `when` answers are read once per shell start, so a package installed since
  then shows the stale row until the next restart.
- An odd-sized ring has nothing at 3 and 9 o'clock. Add or drop a slice.
