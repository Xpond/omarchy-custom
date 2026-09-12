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
      manifest.json    kind: "overlay", keepLoaded
      Wheel.qml        surface, geometry, state, and the comet
      WheelRing.qml    discs, labels, illumination and the disc mask
      RingTrack.qml    ring shader bindings and the visible trail's clock
      ring.frag       antialiased circle, fading trail and disc cutouts
      WheelResults.qml the ring unrolled: the ranked list and its rail
      Sky.qml          day/night palette, sun/moon positions and logo lighting
      Fluid.qml        transparent fluid ShaderEffect and its uniform interface
      fluid.frag       merging contours bent by the sun and moon (compiled to .qsb)
      QuietPoints.qml  stationary background points with three depth levels
      logo.frag        path reveal, runner light, and bevel (compiled to .qsb)
      mark.png         stroke mask, path distance, and bevel normals
      LICENSE.hyprglaze MIT notice for the adapted fluid shader
      PanelIcon.qml    a first-party panel's own mark, loaded from it
      ClickShield.qml  a surface that stops a click reaching the scrim
      MenuIndex.js     JSONC parsing, flattening, search
      MenuKeys.js      the key map: which verb a key means

The ring and the results take the dial as `wheel`, the way the browser's own
components take their panel, so each one's single dependency is visible at the
call site. The key maps are libraries rather than QML: they decide which verb a
key means and the dial performs it, which is what lets a test press a key.

## Keys

| | |
|---|---|
| `SUPER+A` | open (tap — do not hold, see below) |
| `↑` `↓` `←` `→` | jump to the slice at that compass point, then `←`/`→` step around the ring |
| `Enter` | fire the highlighted slice, or open it if it is a submenu |
| `↑` `↓` `Ctrl+P` `Ctrl+N` | step the result list while searching |
| `Home` `End` | the first and last of the forty results, from wherever you are |
| type anything | search menu entries, apps, windows, themes and fonts |
| `Backspace` | delete the character before the caret, then go up one level |
| `Ctrl+W` `Ctrl+Backspace` | delete the word before the caret |
| `←` `→` | move the caret through the query |
| `Ctrl+A` `Ctrl+E` | the start and the end of the query |
| `Ctrl+U` `Ctrl+K` | cut to the start, or to the end |
| `Ctrl+V` | paste at the caret, runs of whitespace collapsed to one space |
| `Ctrl+Y` | copy the highlighted path and close |
| `Esc` | clear the query, then go up one level, then close |
| `SUPER+W` | close the wheel and whatever it opened |

`Backspace` inside a panel the wheel opened closes it and brings the wheel
back. A panel cannot tell the wheel from its own bar button, so it does not
try: it calls `xpo.wheel back`, and the wheel returns `none` for a panel it did
not open, leaving the key to mean what it always did there.

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

`ring.frag` draws the resting circle and colored trail in one antialiased
2px stroke. A live alpha mask cuts out each disc at its animated size, keeping
the track hidden beneath translucent fills. The trail has softly fading ends
and no exterior glow.

For ordinary navigation, `arcHead` and `arcTail` follow the selection target
at different speeds. Charge shortens the head's response from 90ms to 45ms
and lengthens the tail's from 300ms to 460ms. Their separation controls trail
length and disc illumination. `select()` accumulates the shortest angular
delta, so crossing north continues forward. At rest, the arc brackets the
selected disc.

During sustained spin, `RingTrack.qml` advances the visible head at 180°/s:
one lap every two seconds, independent of key repeat. The trail reaches at
most 240°, leaving a third of the ring clear. The resting circle fades away,
leaving only the head and fading tail. Selection still updates immediately;
on release the trail rejoins it along the shortest arc over 300ms, while the
resting circle and even selection bracket return.

Disc lighting eases across both ends of the trail and leaves a 260ms
afterglow. As charge builds, individual passes blend into a dim shared glow
with a gentle moving highlight. Selection's fill, border weight, scale and
label emphasis diminish during fast spinning and return as it slows, so the
comet carries the motion without the discs flashing on every key repeat.

The dial's stroke runs through every disc's **center**, so slice labels sit
outside the ring on their own spokes rather than hung under their discs -- a
label below the east or west disc lands exactly on the arc's path. The reach
is measured to the label box's nearest edge (`|cos|·width + |sin|·height`) so
every label clears its disc by `labelGap` whatever its width and angle, and it
is measured from the disc's *grown* radius so selecting a slice does not close
the gap as the disc scales up.

## Logo and background points

Sustained spinning draws the Omarchy mark along its strokes over about 2.2s.
`markReveal` interpolates the 40ms hold updates; when the drawing completes,
`markPhase` continues the same light along the path on a 1.4s loop, with a tail
spanning 12% of the path. Only the head and fading tail are visible;
the completed path and its contact shadow
clear behind them. Releasing the key drains the reveal and pauses the runner.
The mark keeps its geometry, with rounded bevels, a satin finish, and the wheel's diffuse `MultiEffect`
shadow. A grazing key light separates the bright shoulder from the dark
underside; the runner adds a soft local reflection along the curved strokes.
That key is not a fixed corner — it is the `key` uniform, pointed at whichever
of the sun or the moon is up (see **The day**), so the mark is lit from the
left at dawn, from overhead at noon and from the right at dusk. The bevel
normals are baked into `mark.png`'s GB channels. The head retains its material
shading while the tail fades in opacity along the path.

The shared hue cycle approaches OKLCH lightness 0.78 as spin builds, even with
a dark theme accent; the logo's satin highlight retains some of that colour.

`QuietPoints.qml` fills cells of roughly 100×90px with stationary, jittered
points: 228 at 1920×1080. Three sizes and brightness levels suggest depth;
the nearest lights have faint halos and highlights. The field sits behind
the logo and wheel, with lower brightness around the controls.

## The day

The scene sits above the shared blurred-desktop scrim: `Sky.qml` draws a
translucent sky, `Fluid.qml` adds transparent contours, and `QuietPoints.qml`
draws stars above them. The logo and controls sit in front. The fluid and
stars fade around the controls to keep that area readable.

All layers follow `markReveal`, appearing during a sustained spin and fading
when it stops. `daylight` counts one day per unit on the existing 40ms timer,
advancing by `0.0012 + 0.0045 * charge` per tick: roughly 7s per day at full
spin. It continues through the release fade, pauses when charge and hold have
drained, and resets on close. The value never wraps, so its interpolated
motion keeps moving forward across midnight.

The sun follows an ellipse: `elevation = sin(phase * 2π)` and
`azimuth = -cos(phase * 2π)`. It rises on the left, passes overhead at noon,
and sets on the right. The moon follows the same arc half a day later.
`bodyPosition(side)` supplies the normalized screen positions used by both
the radial glows and fluid deformation. One `Body` component draws both lights.

Daylight follows positive elevation. The `dusk` curve spans both sides of the
horizon, letting twilight colour and haze linger after sunset. Dawn progresses
through violet, rose and pale gold; sunset falls from gold through copper into
purple. Elevation selects within each palette; azimuth blends morning and
evening smoothly. The sky stays translucent, with noon brightness held down
for legibility.

The logo shares the sky's lighting. `keyFacing` hands the direction from sun
to moon, passing through frontal light at the horizon. `keyColor` tints the
bevel highlight and diffuse light; moonlight is blue and its `keyStrength`
is 72% of daylight. The mark keeps its own base colour and runner reflection.

The fluid shader sums six slowly moving fields into merging contour lines.
It samples that field through a local deformation around each sky light:
the sun's influence is broader and stronger, the moon's smaller and gentler.
Both fade with their body's visibility. The clear area around the controls
stays fixed while the fluid bends. Between lines, the fluid adds at most
2.5% tint, leaving the sky and desktop blur visible.

Stars dim in daylight. Their `MultiEffect` blur follows `dusk`, softening them
at twilight and sharpening them as night deepens. `blurMax: 16` makes that
change visible on 1.8–6px points. The layer remains allocated throughout the
reveal to avoid recreating its framebuffer and shader twice per cycle.

The fluid shader is adapted from [slastra/hyprglaze](https://github.com/slastra/hyprglaze/blob/120c5082aba3ee2d675ed9be8f705d9239d1755c/shaders/fluid.frag).
Its MIT notice is in `plugins/xpo.wheel/LICENSE.hyprglaze`. Only the shader
math is used; the scene needs no daemon, audio capture, or window watcher.

Assets are shipped ready to load. To rebuild the shaders from the repo root
using Qt Shader Tools:

```bash
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o plugins/xpo.wheel/logo.frag.qsb plugins/xpo.wheel/logo.frag
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o plugins/xpo.wheel/fluid.frag.qsb plugins/xpo.wheel/fluid.frag
/usr/lib/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o plugins/xpo.wheel/ring.frag.qsb plugins/xpo.wheel/ring.frag
node tests/check.js
omarchy restart shell
```

`tests/scene.js`, included by `tests/check.js`, checks the shaders' QML
uniform interfaces and the sky's arc, day/night, haze and light directions.
`tests/trails.js` checks disc-light continuity, trail length, visible speed,
and the transition between spinning and selection.
Render visual checks on a graphics backend: Qt's offscreen software renderer
does not reproduce the shaders and star blur. Restart the shell after editing;
rescanning manifests can leave the old QML cached.

To rebuild `mark.png`, run `python3 scripts/generate-mark.py 4` with NumPy and
ImageMagick available. The generator writes coverage to alpha, path distance
to R, and bevel normal XY to GB. An optional output path after the stroke
width allows comparison before replacing the shipped asset.

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
Use `omarchy restart shell`.

**The wheel does not own its backdrop.** The wash and the blur behind the ring
are one scrim surface owned by the bar, which the centered panels, the browser
and the clipboard hold a count on too. The wheel takes that count when it opens
and drops it when it unmaps (`holdScrim`). This is the whole reason opening a
panel from the wheel no longer flashes: the wheel's own surface goes, the
panel's arrives, and the thing carrying the blur was never either of them.
Drawing a scrim on the wheel instead — which is what it used to do — unmaps the
blur along with the wheel, and the desktop snaps sharp for the frames in
between. See `docs/centered-panels.md` for the scrim itself.

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
- every call site in the plugin names something `MenuIndex.js` defines
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

`search()` sorts its matches. File mode has too many to sort: it buckets them
by rank and name length as it scans, keeping only the first 40 of each tie,
which is every row that could be read. Closing cancels the scan and rejects
whatever it was about to say; reopening starts a fresh one. `Enter` on a path
opens the browser there, whether or not the browser was already up.

Both are asked for 40, and the stack shows 8: `resultTop` is the first
row on screen and `showResult()` walks it by one whenever the selection steps
past an edge, jumping outright when the selection wraps around an end. The
`Repeater` is fed that window, so eight delegates exist however deep the list
runs. A rail beside the stack -- the same one the file browser runs beside its
list -- is what says the ninth row is there at all, and `Home` and `End` are
what reach the two ends of it without walking.

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
