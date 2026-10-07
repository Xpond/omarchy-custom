# The wheel

A radial control center for Omarchy, on `SUPER+A` or a key you choose (see **Settings**).

Your bar's panels sit on a ring, reachable by direction; typing turns the hub
into a search over every entry in the Omarchy menu, every installed app, every
open window, and every theme and font. It replaces reaching for a handful of
separate `SUPER+CTRL` shortcuts with one key and a direction.

The ring is for things that have a widget. Everything else in the menu —
Install, Remove, Update and the rest — is one search away instead of one more
disc, because a ring you have to read is slower than a word you can type.

    plugins/xpo.wheel/
      manifest.json    kinds: "overlay", "menu"; keepLoaded
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
      Calc.js          the calculator behind a leading `=`

The ring and the results take the dial as `wheel`, the way the browser's own
components take their panel, so each one's single dependency is visible at the
call site. The key maps are libraries rather than QML: they decide which verb a
key means and the dial performs it, which is what lets a test press a key.

## Keys

| | |
|---|---|
| `SUPER+A` | open (tap — do not hold, see below); again to close |
| `↑` `↓` `←` `→` | `↑`/`↓` jump to the slice at that compass point; `←`/`→` step around the ring |
| `Enter` | fire the highlighted slice, or open it if it is a submenu |
| `↑` `↓` `Ctrl+P` `Ctrl+N` | step the result list while searching |
| `Ctrl+Home` `Ctrl+End` | the first and last of the forty results, from wherever you are |
| type anything | search menu entries, apps, windows, themes and fonts |
| `Backspace` | delete the character before the caret, then go up one level |
| `Del` | delete the character after the caret |
| `Ctrl+W` `Ctrl+Backspace` | delete the word before the caret |
| `←` `→` | move the caret through the query; with `Ctrl`, a word at a time |
| `Home` `End` | the start and the end of the query; `Ctrl+E` also goes to the end |
| `Shift+←` `Shift+→` | select; with `Ctrl`, a word at a time |
| `Shift+Home` `Shift+End` | select to the start, or to the end |
| `Ctrl+A` | select the whole query |
| `Ctrl+U` `Ctrl+K` | cut to the start, or to the end |
| `Ctrl+V` | paste at the caret or over the selection, runs of whitespace collapsed to one space |
| `Ctrl+Y` | copy the highlighted path and close |
| `Ctrl+Enter` | open a terminal in the highlighted path's folder; on any other row, as `Enter` |
| `Esc` | clear the query, then go up one level, then close |
| `SUPER+W` | close the wheel and whatever it opened |

The query is a Qt `TextInput`, which types, deletes, moves and selects on its
own; `MenuKeys.js` sees every key before it does.

Until you type, the field reads `Search · / files · = calc`, and a lone `/`
names the two keys a path answers to, `Ctrl+Y` and `Ctrl+Enter`.
`tests/check.js` fails when a sigil joins `MODES` without a word in that
placeholder.

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
does not reproduce the shaders and star blur.

To rebuild `mark.png`, run `python3 scripts/generate-mark.py 4` with NumPy and
ImageMagick available. The generator writes coverage to alpha, path distance
to R, and bevel normal XY to GB. An optional output path after the stroke
width allows comparison before replacing the shipped asset.

## Transitions

One tempo, `fadeDuration`, drives the whole wheel: the open, the close, and
the ring-to-results swap.

`visible` follows `opened`, so dropping it unmaps the layer surface the same
frame it asks for the fade. `close()` drops `shown` to run the fade and a timer
releases the surface once it has finished. Firing a slice
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
discovered from a `manifest.json`. The shell injects a capability-scoped
facade into the loaded item. The wheel's `menu` kind may control enabled UI
plugins and use a detached application-library API, but it never receives the
host ShellRoot, Bar, or plugin-loader maps. Small versioned shell patches add
that facade support; the installer rebases them when Omarchy updates.

`import qs.Commons` and `import qs.Ui` resolve from a third-party plugin, so
the theme singletons (`Color`, `Style`, `Border`) and shared widgets
(`CursorSurface`, `BorderSurface`) are all available. The ring and results have
no colours of their own — they read the `[menu]` theme tokens, so they follow
theme switches for free.

## Traps

**`SUPER`+arrows never reach the client.** Hyprland binds `SUPER+↑/↓/←/→` to
"Focus on <dir> window" and consumes them before any surface sees them. The
hold-a-modifier-and-flick-with-arrows gesture is therefore impossible on a
stock Omarchy keymap; the wheel is tap-then-arrow instead. Bare arrows reach
it fine.

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
and drops it when it unmaps (`panelSurfaceVisible`). Drawing a scrim on the
wheel instead unmaps the blur along with the wheel, and the desktop snaps sharp
for the frames in between. See `docs/centered-panels.md` for the scrim itself.

**`SUPER+W` must be conditional.** The wheel is a layer surface, not a window,
so a plain `killactive` with the wheel up closes whatever window sits behind
the scrim. `bin/omarchy-wheel-close` asks the wheel to close first and falls
through to close-window only when nothing of ours was on screen. It fails
*open*: any unreachable shell still closes the window, on a 0.5s timeout,
because this runs on every window close.

Two things about that script are load-bearing:

**Legacy Hyprland dispatchers do nothing.** Omarchy 4's Hyprland takes Lua
dispatchers — `hyprctl` wraps the argument as `hl.dispatch(<arg>)`, so the
legacy string form is rejected at runtime and the action never happens. Same
trap as `env =` in `hyprland.conf` and `layerrule`: accepted by the tooling,
inert in practice.

`killactive` fails loudly, with a nonzero exit; use `hl.dsp.window.close()`.
Focusing a window fails *silently*: Quickshell's `HyprlandToplevel.activate()`
returns without error and focus simply does not move, because it sends
`focuswindow` under the hood. Use `hl.dsp.focus({ window = "address:0x..." })`.
Note the `0x` — Quickshell reports the address without it, and Hyprland only
matches it with one.

**A `var` reassigned an equal value still notifies.** QML compares a `string`
before notifying, but not a `var`: assigning an array or an object, even the
very same object, re-runs every binding on it. So whatever the wheel re-reads on
open is kept as raw text in a `string` (`conditionText`, `themeText`,
`lockText`…) and parsed by bindings on that, and an open whose answers have not
changed rebuilds nothing.

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
Both files are watched, as Omarchy's own menu watches them: an edit shows when
it is saved, and an entry taken out of the user's file is gone rather than
merged over.

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

An entry's `iconFont` is honoured. Omarchy draws its own marks — the Omarchy
logo, Codex, Cursor, Grok — from a font of its own, at codepoints a Nerd Font
fills with other glyphs, so drawn in the menu font they come out as a COBOL
logo and the like.

That invariant is checked rather than asserted. `check.js` runs the real index
against this machine's real menu files:

    node plugins/xpo.wheel/check.js

- every entry whose `when` passes, and that is not a submenu emptied by its
  children's, appears in `menuRows()`
- every row has an action or a node
- no node opens onto an empty ring
- every call site in the plugin names something `MenuIndex.js` defines
- the one batched script answers every `when` and `checked` the way each
  answers when asked alone
- the shipped bar and this machine's bar both give an even ring
- every keybinding, read with the wheel's own command, is found by its
  description on a row that runs it

Run it after touching `MenuIndex.js`, and against a new Omarchy release — the
menu file is upstream's, and a new entry shape is exactly what would slip
through.

`when:` and `checked:` are evaluated on every open, as Omarchy's own menu
re-checks its rows on every open, so a row follows state that changed under it:
Stop Screenrecording exists only while something records, and an Install row
turns into a Remove row once the package is in. Every check goes out as **one**
bash script, each line echoing `<id>:w` or `<id>:c` when its check holds.
Asked one at a time the package checks alone took over a second, so the script
asks `pacman -T` once for every package they name and answers
`omarchy-pkg-present` from that. Known readers in simple comparisons — such as
`[[ $(omarchy-default-browser) == brave ]]` — share one read. Other Bash expressions
run unchanged, preserving exit status, quoting and short-circuit guards. The script
takes about a quarter of a second, in the background: the wheel opens on the last answers
and the new ones land a moment later, rebuilding only if they changed (see the
trap above). With the theme, font and lock-design reads it costs about a third
of a second of CPU per open, twice what the wheel's own opening costs, all of
it in those processes: starting them holds the UI thread 1.4 ms, before the
wheel's first frame, and a probe animating at 144 Hz beside them lost no frames.

A `when` that fails hides the row, and a submenu whose children all failed is
hidden too, so a slice never drills into an empty ring. A `checked` that holds
appends ✓ to its row, on the ring and in search: the default browser,
terminal, editor and agent, the DNS, the update channel.

Applications come from `shell.appLibrary` (`services/AppLibrary.qml`), which
wraps Quickshell's `DesktopEntries`: it sorts, drops entries marked hidden,
resolves an icon name to a file, and launches through `uwsm-app -- gtk-launch`
so an app does not inherit the compositor's service scope.

Open windows come from `Hyprland.toplevels`. Their rows say
`Workspace <n> · <app id>`; launcher rows say `App`, so focusing an existing
window and launching an app are distinct choices. The workspace is the
toplevel's live one, since the cached IPC object goes stale like the focus
history below, and it is searchable: `workspace` lists every open window and
`workspace 2` the ones on 2 (the scratchpad reads `Workspace scratchpad`).
A window row carries its address rather than its toplevel
object, so it can never go stale on a window that has
since closed, and focusing one is a `Hyprland.dispatch` — see the trap above.

Themes and fonts are `omarchy theme list` and `omarchy font list`, re-read on
every open along with the current theme and font, which are marked ✓, and fired
back as `omarchy theme set '<name>'`. Each read takes a few milliseconds. Both
are otherwise buried: `style.theme` in the menu shells out to
`omarchy-theme-switcher`, a second overlay on top of the first. Lock-screen
designs come from `omarchy-lock-design list`, re-read the same way, but join
the menu as one Style › Lockscreen Designs submenu: search finds that entry,
and the designs, marked `search: false`, show only inside it. Picking one runs
`omarchy-lock-design set`, and each carries a `checked:` against
`omarchy-lock-design current`, so the chosen one's ✓ comes back with the rest.

Keybindings come from Omarchy's own keybindings menu (`SUPER+K`). Hyprland
reports every Lua bind as dispatcher `__lua` with an index, so `hyprctl binds`
cannot say what one does; `omarchy-menu-keybindings` recovers each command by
re-running `hyprland.lua` against a stub `hl`, and caches the result in
`~/.cache/omarchy/keybindings-<sha>.records`, keyed on `hyprctl binds`. The
wheel asks it to print, which refreshes that cache whenever the binds changed,
and reads the records on every open, in 16 ms and 20 ms of CPU. A record is
`KEYS → Description<TAB>kind<TAB>arg`. An `exec` bind runs its command as a
menu row does, and a `lua` bind goes to `Hyprland.dispatch`, as window focus
does. The rest cannot run from a row: a `sendshortcut` needs its web app
focused, and a mouse bind needs the mouse.

A binding that runs what a row already runs — the row's command, its panel's
toggle, or Omarchy's menu opened at it by id or alias — is not a second row. It
lends that row its description as search words, so `idle` finds Stay Awake
(Toggle locking on idle) and `ocr` finds Capture › Text. Bindings sharing a
command are one row. The wheel's own bindings (open, commit, close) are no rows, since
they mean nothing from inside it. Here the other 211 make 169 rows of their own and join
32 more. The keys themselves are never shown: the wheel is there so that none need
remembering.

A window action — Toggle floating, Full screen, Move window to workspace 3 —
acts on Hyprland's active window, and while the wheel holds the keyboard
`Hyprland.activeToplevel` reads null. Hyprland's own active window stays put,
though (`hyprctl activewindow` still names the window behind the wheel), so the
action lands whatever the timing. Fired 25 times through the wheel's `run()` at
a throwaway window, five of them with the wheel's surface still holding the
keyboard, it toggled that window every time and nothing else.

The live half of the index — apps, windows and live panels — is rebuilt when
the wheel opens. That is the only moment any of it has to be correct, and it means
they are all as fresh as the keystroke that asked for them. The menu half is a
binding rather than a per-open rebuild: flattening the menu costs several times
what everything else costs together, and it only changes when the menu files
load or when the conditions come back. When they do come back — after the wheel
is already on screen — the ring re-reads them on its own, and `onStaticRowsChanged`
tells the index to rebuild, since that half is built by hand. The theme and font
rows are a binding of their own, `styleRows`, rebuilt the same way when a
re-read changes them.

When rows refresh, selection follows the same action to its new position. If that
action disappears or its command changes, selection clears. A refresh cannot turn
a selected Logout into Reboot. A new search query still selects its first result.

App and window text accepts substrings: `calc` finds `Omacalc (Development)` even
without calculator keywords. Other rows still require each query term to start a
word, keeping menu searches narrow. Rows then
sort on six keys: **rank** (label-prefix, then a label word, then a hit
anywhere else — breadcrumb, alias, app id), **uses** (among equal matches,
the most picked first), **kind** (slice, window, app, theme/font, menu,
keybinding), an **exact label** (so "lock" puts Lock before
Lockscreen Designs until the designs are picked more), **recency**, and
finally **label length**, which floats
"Screenshot" over "Stop Screenrecording".

`node tests/wheel-search.js` covers matching and ranking, including issue #1's
calculator results. `node tests/wheel-binds.js` covers reading the records and
which bindings join which rows. `node tests/wheel-conditions.js` checks the
batched script, custom Bash included; `python3 tests/runtime.py` checks live
refresh, selection and menu-file changes, and like every test that starts
Quickshell, fails on a warning it doesn't expect (`tests/qslog.py`).

`search()` sorts its matches. File mode has too many to sort: it buckets them
by rank and name length as it scans, keeping only the first 40 of each tie,
which is every row that could be read. A file opened from the wheel before
leads its rank, most opened first, but never climbs into a better one. A bare
`/` lists those files, latest first, while the scan runs. Home and the folders
added outside it scan apart, so a slow folder, such as a network share still
mounting, holds back only its own paths: home's show as soon as they land, and
the folders' join them. Closing cancels both scans and rejects whatever they were
about to say; reopening starts fresh ones. `Enter` on a path
opens the browser there, whether or not the browser was already up. The browser
keeps to home, so a path from a folder outside it (Settings) opens the way the
browser opens a file, through `omarchy-open-path`.

Both are asked for 40, and the stack shows 8: `resultTop` is the first
row on screen and `showResult()` walks it by one whenever the selection steps
past an edge, jumping outright when the selection wraps around an end. The
`Repeater` is fed that window, so eight delegates exist however deep the list
runs. A rail beside the stack -- the same one the file browser runs beside its
list -- is what says the ninth row is there at all, and `Ctrl+Home` and
`Ctrl+End` are what reach the two ends of it without walking.

An open window whose words match is never a weak hit: it counts as rank 0. A
window's title is written by the program, so a query lands mid-string
("…Omarchy Plugins - Brave") where a menu label has it at the front — without
this the window you are looking at sorts below seven rows offering to install
the thing. A term found only inside a word ranks a window like any other row, or
`ar` would put a terminal titled `~/x/omarchy-custom` above Arch.

Recency orders the windows among themselves, most recently focused first, and
is inert for every other row. Hyprland publishes a `focusHistoryID`, but only
inside each toplevel's cached IPC object, which is **not** re-fetched when
focus moves — it keeps reporting the order from whenever the list was last
pulled. `Hyprland.activeToplevel` does track focus, so the wheel accumulates
the order from that instead, and falls back to the cached history for windows
it has not yet seen focused (everything, for a moment after a shell restart).

A leading `=` turns search into a calculator, `Calc.js`: `+ - * / ^` and
parentheses, with `^` binding tighter than a leading minus, as on paper
(`=-2^2` is -4). The answer shows fifteen significant digits, which also hides
float noise (`=0.1+0.2` is 0.3), centered under the query with a copy mark at
the row's end, and `Enter` copies exactly that and closes. Even the longest
answer, 23 characters, fits at the stock font size; anything wider is cut on
the left, as the query is. A half-typed sum, a unit or a letter shows "No
answer" rather than a guess; units and currency would need `qalc`, which
Omarchy does not ship. `node tests/wheel-calc.js` pins issue #8's sums and
checks 2000 random ones against JavaScript's own arithmetic.

## Settings

Settings are search rows. `wheely settings` lists every one, and each answers to its
own words (`wheely shortcut`, `keybind`). A setting row ends in its value, drawn as a
control in Omarchy's control fill and border, the way its panel rows end in a switch;
every other row ends in plain text, so a setting cannot pass for a result. Enter on
one changes it in place: the wheel stays up, and the row says what is happening.

**Wheely shortcut** is the key that opens the wheel, `SUPER + A` until you choose
another. Enter starts recording, and the row takes every key. The field shows the combo
pressed, where a value is typed, and the row, with its whole width, says what saving
would do: `enter saves`, `replaces Omarchy menu` when another binding holds it (the
wheel's own do not count), or why it cannot be had (`add SUPER, CTRL or ALT`, `closes
the wheel`, `pick another key` for a key with no name here, such as a shifted symbol).
One row cannot hold both: a long combo lost its key. Plain Enter saves; plain Esc gives
up, and the query comes back.

A bound combo never reaches a client, since Hyprland runs it instead (the `SUPER`+arrows
trap). So while the row records, the wheel holds a keyboard-shortcuts inhibitor
(Quickshell's `ShortcutInhibitor`), and Hyprland skips every binding while the focused
surface holds one, layer surfaces included (`isInhibited()` in its `ShortcutsInhibit.cpp`).
A taken combo is recorded and nothing it is bound to runs. Hyprland honours an inhibitor
only while its surface has the keyboard, and this one ends with the recording, so nothing
can be left stuck. With `binds:disable_keybind_grabbing = true` Hyprland ignores
inhibitors, and only free combos arrive.

Saving writes `~/.config/omarchy/wheel-shortcut`, then runs `hyprctl reload` once the
write has landed, as Omarchy's own toggles reload. The managed Hyprland block cannot
carry the key itself, because the installer refuses a block that was edited. It reads
the file as data instead, the way Omarchy reads a disabled input device's name, and binds
what it holds if that reads as keys joined by ` + `; anything else is `SUPER + A`. It
unbinds the key before binding it, so a taken key's binding is gone until the wheel
moves off it. The names come from Qt's key codes, and `tests/runtime.py` has Hyprland's
own `--verify-config` accept every one the wheel can write.

Pressing the key again with the wheel up closes it: the press is a `toggle`. Only the
release of the press that opened the wheel fires a flick. Press and release reach the
shell as separate processes, so a closing tap's release can land before its press, and
a release that fired or reopened would leave the wheel up.

**Wheely ring** reads `Bar` while the ring follows the bar and `Custom` once it
has been changed; Enter opens the ring editor (The ring).

**Backdrop** ends in Omarchy's own slider: how much the backdrop hides the desktop. Enter,
then ←/→ step it by a tenth, saved at once so the backdrop behind the wheel shows it. 0% is
a clear desktop; above it, each step darkens it over a blurred desktop. The tint is
Omarchy's `[menu] scrim-alpha` in `~/.config/omarchy/shell.toml`, which its own menus draw
too. The blur is `~/.config/omarchy/wheel-blur`, which the managed block reads like the
shortcut's file (`off` turns it off, and Hyprland's own blur with it); only crossing 0%
reloads Hyprland, which re-applies the layer rule to the open backdrop.

**Centered panels** reads `On` until it is turned off: Enter flips it. Off, every bar panel
opens beside its bar widget with no backdrop, whether the bar or the wheel opened it. It is
`[wheely] panels = native` in `~/.config/omarchy/shell.toml`, which the shell already
watches; each panel reads it through `Color.shellValues` as it opens (centered-panels.md).

**Searched folders** and **Skipped folders** change what `/` searches; until they do, it is
what it always was: home, hidden folders included, six levels deep, skipping every folder
named `.cache`, `.git` or `node_modules`. Searched folders adds folders outside home
(`Home + 1`), scanned beside home. Enter on either puts its list in the results: typing suggests
what to add, folders under home to skip as `/` would find them, or the subfolders of a path
typed from `/`, and Enter adds the one picked; Del removes the picked entry, and Esc is done.
Both are saved to `wheel.json` beside the ring (`"folders"`, `"skipped"`), and an emptied list
is its default again. A skip with a slash is that folder under home; one without is every
folder of that name. fd anchors a path only to the first folder it is given, home, so a
folder outside home is skipped only by name.

**Forget picks** ends in how many rows are remembered (What it remembers). It cannot be
undone, so Enter only asks: the field reads `Forget 57 picks`, Enter again forgets them,
on disk too, and Esc keeps them; other keys wait.

**Wheely history** answers to `history` rather than `settings`. Enter lists what you have
picked in the results, the latest first, files included; Enter on one runs it, and it comes
back to the top. Typing leaves history for search, where picks rank anyway, and Esc is done.

## What it remembers

Every pick is counted, keyed by `MenuIndex.keyOf` -- a panel's plugin id, a
menu entry's dotted id, `app:` plus a desktop id, or a theme/font or
keybinding command, so a binding keeps its count when its keys change, or
`file:` plus a path -- and the count sorts right under how well a row matches.
So `loc` puts a picked Lock over a never-picked LocalSend, while `br` keeps
Files, which matches only through its "browser" keyword, under every row whose
name starts with `br`, however often Files is picked.

Windows are deliberately uncounted -- their address is new on every launch, so
counting them would grow the file without bound, and they already sort on live
focus order. `check.js` holds both invariants: every counted row has a key,
and no two share one. Opening a setting row is no pick either, so the count on
Wheely history and Forget picks is exactly what history lists.

The counts live in `~/.local/state/omarchy/wheel-uses.json`, written through on
each pick rather than batched at exit -- the wheel is a plugin in a shell that
gets restarted, so no orderly shutdown is guaranteed to arrive. A pick moves
its key last, so the file reads oldest to newest and **Wheely history** needs no
clock. The **Forget picks** setting empties it. There is no decay: what you
reach for through a wheel is stable for months, and a half-life is a second knob
to be wrong about.

## The ring

By default the ring is the panels your bar carries — written as a bare id or as
an object with an `id`, as Omarchy reads either — in a fixed order, plus the
clipboard overlay — which is not a bar widget, so nothing in the bar vouches
for it. Adding a widget to the bar adds it to the wheel; the wheel is not a
second list to keep in sync with the first. A machine that has never edited its
bar has no user config, so the layout Omarchy ships
(`$OMARCHY_PATH/config/omarchy/shell.json`) is read instead — otherwise the
ring would offer panels that machine has no widget for.

Search does not follow the ring. Each open asks the shell's facade for every
bar widget the live bar can open and every enabled third-party panel or
overlay — Weather, clones, plugins such as Omastorm — so a panel is searchable
whether or not it has a disc. Omarchy's own panels come through its menu.
Clones borrow their source's mark, Weather uses its widget's own glyph, and
unknown panels a generic one.

To choose the ring yourself, open the **Wheely ring** setting: the ring becomes
its own editor, starting from the bar's ring. Type to find anything, and Enter
adds it after the selected slice, or last when none is. Del removes the selected
slice, Shift+←/→ swaps it with its neighbour, across north too, and Esc is done.
Ctrl+R, pressed twice, resets the ring to the bar's widgets, as removing the
last slice does. Every change is saved as it is made, to
`~/.config/omarchy/wheel.json`:

```json
{
  "slices": [
    "omarchy.audio",
    "app:chromium",
    "omarchy.clipboard",
    "system",
    "trigger.capture"
  ]
}
```

A slice is the key its picks are counted under (What it remembers): a panel's
plugin id, a menu id from `omarchy-menu.jsonc`, `app:` and a desktop id, or a
theme, font or keybinding command. So the ring takes anything search finds,
Weather, clones and third-party panels included, but no window, file or answer,
whose key would not outlast it, and no setting. An app wears its own icon, as
in search; a menu id with an action runs it, and a submenu drills the ring into
it. A key that names nothing is dropped, and the editor saves the ring as drawn,
so a slice that names nothing today, such as a widget taken off the bar, is gone
after the next edit. The file is watched, so a hand edit shows as you save, but
the editor writes it back without comments, keeping any other keys.

Every icon in `PANELS` is one the widget itself already draws. Tailscale
and Dropbox have no Nerd Font glyph — Omarchy renders each as a QML shape of
its own — so those two carry an `iconFile` and the wheel loads that component
off `omarchyPath`. There is no codepoint that stands in for a product's mark,
and picking one that looks close is how you ship a logo the product doesn't
have.

**Keep the count even.** East and west are half a turn apart, so half a turn
has to be a whole number of steps, which only happens when the count is even.
An even ring is rotated so two slices land at 3 and 9 o'clock, flanking the
field; an odd one is still evenly spaced but anchors north instead, and nothing
sits beside the field.

The catalogue is sized so the default lands even on a stock machine: the bar
Omarchy ships carries seven of these plus the clipboard overlay. Changing
`PANELS` means re-checking that.

The ring sizes itself to what it holds. It keeps a constant arc distance per
slice and grows its radius to pay for it, so a disc and its label have the same
room at fourteen slices as at eight. Growth stops before the labels would run
off the short edge of the screen, and only then do the discs shrink to fit the
chord between their neighbours.

## Known limits

- A window is found by its title or its app id, never by what is running
  inside it: a terminal holding a Claude Code session is titled after the
  session's topic, so `claude` will not find it. Searching the app id
  (`kitty`) lists every window of that app, most recent first.
