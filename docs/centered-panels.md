# Centered shell panels — state of the work

Omarchy 4.0.0.alpha · Quickshell 0.3.1 · Hyprland 0.56.2 · DP-3 1920x1080 **@144Hz**

Makes Omarchy's bar panels (Display, Audio, Network, Power…) open centered on
screen over a blurred desktop, instead of tucked against the bar edge beside
their widget.

**Working:** centering, blur, Ctrl+Left/Right panel switching, the
panel-to-panel handoff, and the open/close animation.

The animation problem that dominated sessions 1–2 was **not in the QML at
all** — Qt was rendering the whole shell at 62Hz on a 144Hz display. One env
var fixed it; see [The render loop](#the-render-loop-read-this-first).

---

## 1. How to work on this

```bash
~/xpo/omarchy-custom/install.sh   # patch the packaged shell, restart it
~/xpo/omarchy-custom/revert.sh    # restore Omarchy's QML and remove managed desktop setup
```

`install.sh` needs a sudo password, so it must be run from a terminal
(`! ~/xpo/omarchy-custom/install.sh` inside Claude Code). It is idempotent —
re-running when nothing has changed prints `already up to date` and exits.

```
orig/     upstream merge bases, updated by successful rebases
shell/    patched copies, mirroring /usr/share/omarchy/shell/
docs/     this file
```

### The constraint that shapes everything

The files being changed are **shared shell chrome**, not plugins.
`omarchy plugin clone` cannot reach them, and `/usr/share/omarchy/` is
package-owned, so **`omarchy update` overwrites all five** and the shell
silently reverts to stock. This happened on the 4.0.0.alpha → 4.0.2 update.
The user ruled out cloning panels and ruled out changing panel styling, which
is what put the work in shared chrome.

**This is now self-repairing.** `omarchy update` runs `omarchy-hook
post-update` right after migrations, and `install.sh` installs a hook there
with this checkout's path baked in. Rerun `install.sh` after moving the
checkout. `revert.sh` removes the hook, so a later update cannot reinstall
the patch behind you.

The hook is a one-line trampoline into `install.sh` on purpose — `omarchy hook
install` *copies* the file, so any logic living in the hook would drift from
the repo.

**Re-applying is not just copying.** An update may ship a new version of a
patched file (4.0.2 changed `Bar.qml`: added an `omarchy.bar` IpcHandler and
`textFormat: Text.PlainText` on the tooltip). Blindly restoring our copy would
have discarded both without a word. So `install.sh` checks each installed
file against pacman's checksum for the installed package and against this
checkout's patch history:

| Installed file is | Action |
|---|---|
| `shell/` | already patched — skip |
| any recorded or committed version of our patch | our previous version — replace it |
| stock, same as `orig/` | upstream unchanged — copy the patch in |
| stock, different from `orig/` | new upstream version — **three-way merge**, then re-baseline `orig/` |
| anything else | changed outside this project — left untouched and reported |

A merge that conflicts leaves the installed file untouched, reports
it on stderr *and* via `notify-send`, and exits non-zero so the hook logs
`Hook failed`. It never writes conflict markers into a QML file — that would
break the entire shell, which is far worse than losing the patch.

`revert.sh` writes stock back only over files that are ours, and only bytes
matching pacman's checksum: `orig/` when it matches, otherwise the file from the
cached package. Anything else stays in place and produces an error. See the
[install and revert summary](../README.md#revert).

---

## 2. What changed

Six package-owned QML files plus Hyprland config.

| File | Change |
|---|---|
| `Ui/KeyboardPanel.qml` | `centerOnScreen` placement in `cardOrigin`; `slideX`/`slideY`/`originScale` transform; entry/exit animations; reports surface visibility to the bar |
| `Ui/PanelKeyCatcher.qml` | Ctrl+Left/Right → `tabRequested`; Backspace asks `xpo.wheel back` (19 lines) |
| `plugins/bar/Bar.qml` | `PanelScrim` — the shared blurred backdrop; `lastSwitchDirection`; `visiblePanelSurfaces` counter |
| `plugins/clipboard/Clipboard.qml` | Backspace past an empty filter asks `xpo.wheel back` — it rolls its own key handler instead of using `PanelKeyCatcher`; drops its own scrim for the shared one (18 lines) |
| `services/PluginShellApi.qml` | narrow peer-panel, popout, and shared-scrim callbacks without exposing host objects |
| `shell.qml` | grants menu plugins control of enabled non-authentication UI plugins and implements the callbacks above |

The managed block in `~/.config/hypr/hyprland.lua` supplies these settings
(the original prototype kept them manually in `looknfeel.lua`):

```lua
hl.config({ decoration = { blur = { enabled = true, size = 4, passes = 2 } } })

-- The one blurred surface. Everything else stands on it.
hl.layer_rule({
  match = { namespace = "omarchy-panel-scrim" },
  blur = true,
  ignore_alpha = 0.05,
  no_anim = true,
  animation = "none",
})

-- Overlay blur would blur the shared backdrop again on every animation frame.
hl.layer_rule({
  match = { namespace = "^(omarchy-wheel|omarchy-files)$" },
  blur = false,
  no_anim = true,
  animation = "none",
})
```

`config/hyprland.lua` is the installed source of truth. It explicitly disables
blur on the wheel/files overlays, then installation reloads Hyprland and checks
for configuration errors. Revert removes only the managed block.

### Why the scrim lives in the bar

Panels are separate layer surfaces that unmap and remap as you tab between
them — and so are the wheel, the browser and the clipboard, which unmap and
remap as the wheel hands over to whatever you picked. A scrim inside any of
them blinks out mid-handoff and takes Hyprland's blur with it. One bar-owned
surface stays mapped across the whole interaction, and every one of those
surfaces holds a count on it (`panelSurfaceVisible`) rather than drawing its
own.

Ordering is by **Wayland layer**, not by `layer_rule`'s `order` field:

```
Overlay   omarchy-keyboard-panel   the card — opaque, stays sharp
Overlay   omarchy-wheel            the ring
Overlay   omarchy-files            the browser card
Overlay   omarchy-clipboard        the clipboard card
Top       omarchy-panel-scrim      the blurred wash, held by all of the above
Top       omarchy-bar
```

`order` was tried first and did not hold — the scrim came out above the panel
and blurred the card along with the desktop. Layer separation is a protocol
guarantee; `order` is a hint.

### Why `shell.qml` is patched: plugin capabilities

4.0.3 stopped handing plugins the host `ShellRoot`. A plugin now gets a
`services/PluginShellApi.qml` facade, closed over its own id.

Trust is decided by **which directory the plugin was scanned from**, nothing
else — `PluginRegistry.parseScanOutput` sets `__isFirstParty` from the scan
kind, and only `/usr/share/omarchy/shell/plugins` scans first-party. Our
plugins are symlinked into `~/.config/omarchy/plugins`, so they scan third
party. Symlinking them into the packaged directory instead does not work:
that scan is `find … -type f` with no `-L`, so it neither descends a
symlinked directory nor matches a symlinked file.

The wheel exists to launch *other* plugins, so the stock facade denies several
things it needs — silently, because a denied call just returns `false`:

| Call | Sandboxed result |
|---|---|
| `shell.toggle("omarchy.menu", …)` | `false` — no panel ever opens |
| `shell.summon("xpo.files", …)` | `false` — browser never opens |
| `shell.isPluginOpen(other)` / `hide(other)` | `false` — close-others and Backspace-to-wheel dead |
| `shell.appLibrary` | `null` — app launching dead |
| shared surface reporting | absent — shared scrim never maps |
| peer-panel coordination | absent — surfaces can stack and fight for focus |

`PluginShellApi` now exposes only the missing operations as callbacks closed
over the caller's id. A plugin with kind `menu` may summon, hide, toggle, and
inspect enabled non-authentication UI plugins. Visual plugins may report one
mapped surface and claim their own popout object; the bar validates ownership.
The host closes peer panels internally, so neither its panel maps nor the live
Bar object cross the facade. Files uses the public shell IPC for its one call
back to the wheel.

`pluginShellFor` now returns the scoped facade for every third-party plugin.
No namespace or plugin id is a trust grant: an unrelated `xpo.*` manifest,
including a replacement using one of these ids, still receives only the narrow
capabilities declared by its kinds.

This is a QML capability boundary, not an OS sandbox. Plugin code still has
the Quickshell APIs available to its process.

**Keep capability checks on the original registry manifest.** Passing a
manifest through an Instantiator model role converts its arrays to QML
sequences. `Array.isArray(manifest.kinds)` then returns false, silently denying
the wheel's menu and visual capabilities. The panel loader passes the host
registry's original manifest to `pluginShellFor()` to preserve those arrays.
This fixes the missing shared blur without granting the plugin ShellRoot.

`tests/plugin_shell.py`, included in the runtime suite, exercises the actual
loader and API factory together. It checks restricted host access, menu
capabilities, backdrop counting, duplicate reports, and panel handoffs.
An isolated Wayland comparison against `0ca54c8` confirmed that the registry
manifest restores `omarchy-panel-scrim`; the installed fix was also confirmed
on the desktop.

---

## 3. Findings worth not rediscovering

### The render loop (read this first)

**Qt renders this shell at 62Hz on a 144Hz display unless told otherwise.** On
NVIDIA + Wayland Qt falls back to the `basic` scene-graph render loop, which
advances animations from a fixed 16ms timer instead of vsync. Every animation
step is then held for 2 or 3 refreshes in an uneven 2,2,3 pattern — textbook
judder, on every panel, in both directions. Measured with a bare `qml6` app:

| `QSG_RENDER_LOOP` | median frame | implied |
|---|---|---|
| *(default)* | 15.9ms | 63Hz |
| `threaded` | **6.9ms** | **145Hz** |
| `basic` | 16.0ms | 62Hz |

The installer now includes this line in its managed Hyprland block:

```lua
hl.env("QSG_RENDER_LOOP", "threaded")
```

**It must be `hl.env()` in Lua.** Writing `env = QSG_RENDER_LOOP,threaded` in
`hyprland.conf` is silently ignored — the same legacy-syntax trap as
`layerrule` below. `hyprctl configerrors` stays clean, the line looks right,
and the var is simply never exported. That cost a full reboot to discover.
(`hyprland.conf` *is* loaded — its binds work — so this is specifically the
`env` keyword, not the file.) Omarchy launches the shell from a `hyprland.start`
callback, after configuration is parsed. Installation also reloads configuration
before restarting the shell. Older manual `looknfeel.lua` settings remain untouched.

In-shell, that took the entry animation from ~12 rendered frames to ~44.

One side effect worth knowing: `threaded` exposes a latent binding loop in
stock `plugins/panels/power/Panel.qml` (`opened`) that `basic` never
surfaced — it appears in the journal the moment the render loop changes. It
was harmless here (this box has no battery, and power binds
`open: root.opened && root.batteryPresent`, so that panel could never open —
verified as 0 layer surfaces while "open", against clock's 1), and it is now
moot: the widget was dead weight on a desktop and has been turned off with
`omarchy plugin disable omarchy.power`, which stops the panel being
instantiated at all. If you re-enable it on a machine with a battery, expect
the warning back; it is stock, package-owned, and not worth another patched
file.

The `height` loops in `network/Panel.qml` are unrelated, intermittent, and
predate all of this work — they appear on shell starts going back well before
the prototype.

`hl.env` takes effect on `hyprctl reload` — no logout needed. Apply it with
`hyprctl reload && omarchy restart shell`.

### Verify it, don't assume it

This was claimed fixed three times while still broken, because "the env var is
in a config file" proves nothing. Two checks that prove it, both reboot-free:

```bash
# 1. Does a process spawned by Hyprland actually get the var?
hyprctl dispatch 'hl.dsp.exec_cmd("sh -c \"env > /tmp/q\"")'; grep QSG /tmp/q
```

```bash
# 2. Did the render loop really change? This thread exists ONLY under
#    `threaded` -- `basic` renders on the GUI thread.
P=$(pgrep -x quickshell); cat /proc/$P/task/*/comm | grep QSGRenderThread
```

Check 2 is the strong one: it observes the running shell's actual behaviour
rather than its configuration. Note `hyprctl dispatch` needs the Lua
dispatcher form (`hl.dsp.exec_cmd`); the legacy `hyprctl dispatch exec cmd`
errors out on this parser.

One dead line nearby, pre-existing and left alone: `hyprland.conf:9` sources
`~/.local/share/omarchy/default/hypr/envs.conf`, which does not exist —
Hyprland ignores a missing `source` in silence. Harmless: the NVIDIA vars it
would have set are set anyway by Omarchy's `default/hypr/nvidia.lua`, which
also picks `direct` vs `egl` rather than hardcoding one. (`~/.config/hypr/envs.conf`
duplicated those and was never sourced either; deleted.)

Check `systemctl --user show-environment` before concluding a var is unset —
this session's env arrives through uwsm, not only through Hyprland.

### Everything else

**Omarchy 4 uses Hyprland's Lua parser.** Legacy `layerrule = blur on, …`
lines in a `.conf` file are **silently ignored** — no error, no warning,
`hyprctl configerrors` stays clean. Layer rules must go through
`hl.layer_rule({...})`. (The pre-existing `layerrule = blur on, match:namespace
logout_dialog` at `~/.config/hypr/hyprland.conf:31` is legacy syntax and has
never done anything. Left alone — it predates this work.)

**`hyprctl keyword` cannot set layerrules** on this parser: *"keyword can't
work with non-legacy parsers."* Edit the Lua and `hyprctl reload`.

**`ignore_alpha` must sit below the scrim's own alpha.** Hyprland skips blur on
regions it considers too transparent. At a 0.32 scrim a default threshold
suppressed the blur entirely while the dim still rendered — which looks exactly
like a broken scrim rather than a blur problem.

**Only the scrim surface is blurred.** Every other shell surface — the panels,
`omarchy-wheel`, `omarchy-files`, `omarchy-clipboard` — draws a card over it
and nothing behind. That is what makes a handover seamless: they unmap and
remap as you tab between them and as the wheel opens what you picked, and blur
bound to any of them blinks out mid-switch. Blurring one of them *as well as*
the scrim is not free either — it blurs an already blurred desktop a second
time inside the card, and recomputes a fullscreen blur on every frame the
wheel's ring spins.

**Every Omarchy shell layer surface sets `no_anim = true, animation = "none"`**
(see `default/hypr/apps/omarchy-shell.lua`). Without it Hyprland runs its own
fade on map/unmap, and on a *blurred* surface that means recomputing a
fullscreen blur every frame of the fade. Adding this cut the post-close churn
from 278ms to 132ms.

**Never animate the scrim's alpha,** for the same reason — one QML fade cost a
fullscreen blur recompute per frame. It snaps on, and is *held* through the
close by a timer instead.

**`backingWindowVisible` is Qt-side, and fires in the same millisecond as
`open`.** An earlier draft of this doc claimed panel surfaces cost ~100ms to
map and that the entry animation had to wait for that edge. Per-frame traces
disprove it: `open=true`, `mapped=true` and `entry-start` all land at t=0. Two
fixes built on that premise (latching the fade to the map edge, animating the
card's height) were measured to be no-ops and were reverted.

What *is* real is the delay before the first **rendered** frame, and it is
per-panel work rather than surface mapping — see §5.

**Qt Quick already applies transforms on the GPU.** `layer.enabled` to "avoid
re-rasterization" was based on a false premise and made things measurably
worse — it only added an FBO allocation and an extra render-to-texture pass.

**`In*` easing is wrong for a dismissal.** `InQuint` covers `0.5⁵ = 3%` of the
distance by the halfway point, so the card hangs still while the fade runs,
then jumps. Both directions want fast-start (`Out*`) curves.

---

## 4. Measuring, instead of guessing

Every wrong turn in this project came from tuning motion by eye or by theory.
Three separate hypotheses (per-panel `onOpenedChanged` work, fade/motion
desync, mid-animation resize) all survived code review and all died on contact
with a frame trace. Measure first.

### The instrument that works: an in-QML frame probe

`FrameAnimation` (Qt 6.4+) fires once per *rendered* frame, so it reports what
the compositor actually showed — dropped frames included. Drop this inside the
card in `Ui/KeyboardPanel.qml`, buffering to an array so the logging itself
does not perturb what it measures:

```qml
property double t0: 0          // set in onOpenChanged when open goes true
property var probeRows: []

FrameAnimation {
  running: root.open || card.opacity > 0 || root.popoutSwitching
  onTriggered: root.probeRows.push([
    Math.round(Date.now() - root.t0),
    Math.round(frameTime * 10000) / 10,   // ms since previous rendered frame
    card.slideY, card.originScale, card.opacity, card.height
  ].join(","))
  onRunningChanged: if (!running) {
    for (var i = 0; i < root.probeRows.length; i++) console.log("[fr]", root.probeRows[i])
    root.probeRows = []
  }
}
```

Drive it over IPC so runs are repeatable, and strip journald's ANSI prefix —
anchoring a grep on `^[fr]` silently matches nothing:

```bash
since=$(date '+%Y-%m-%d %H:%M:%S.%6N')
omarchy-shell -q omarchy.monitor open;  sleep 1.5
omarchy-shell -q omarchy.monitor close; sleep 1.5
journalctl -t omarchy-shell --since "$since" --no-pager -o cat \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '\[fr\].*'
```

Read the second column. A healthy trace on this box is a wall of ~6.9ms. A
wall of ~16ms means the render loop is wrong (see §3) — not that your
animation is wrong. A single large value is real latency; find what runs in
that window.

### Measuring the render loop on its own

Qt's chosen render loop is a process-wide property, so it can be measured
outside the shell entirely. `console.log` from a bare `qml6` may be swallowed
depending on how it is invoked; returning the number through the exit code is
immune to that:

```qml
FrameAnimation {
  running: true
  onTriggered: { /* collect frameTime for ~140 frames, then: */
    Qt.exit(Math.round(medianFrameTimeMs * 10)) }
}
```

```bash
for rl in default threaded basic; do
  QSG_RENDER_LOOP=$rl qml6 tick.qml; echo "$rl -> $(($? ))/10 ms"
done
```

Note `/usr/bin/qml` is **Qt 5.15** on this box; you want `qml6`.

### Video capture — a last resort

Session 1 built a `gpu-screen-recorder` + `ffmpeg` per-frame-diff pipeline
(`grim` is far too slow; NVENC is broken here, so CPU encoding and a small
region). It found the 278ms close tail and the 104ms open gap, but CPU encoding
at 144fps drops frames of its own, so absolute counts are untrustworthy and
only relative comparisons hold. The QML probe above is strictly better: exact,
cheap, and it reports values as well as timing. Reach for video only when you
need to see something the QML side cannot report.

---

## 5. Resolved: the open/close animation

Sessions 1–2 treated this as an animation-code problem. It was not. The shared
QML was correct throughout; **Qt was rendering the shell at 62Hz on a 144Hz
display** (§3). Setting `QSG_RENDER_LOOP=threaded` fixed it, and the panels are
smooth. `KeyboardPanel.qml` needed **no change at all** — the net QML diff for
session 2 is zero.

Hypotheses that were disproven, so they are not re-litigated:

| Hypothesis | Verdict |
|---|---|
| Heavy panels' `onOpenedChanged` work starves the animation | **No.** `clock` does no work on open and juddered identically. |
| The fade starts ~100ms before the motion (map latency) | **No.** `open` and `mapped` land in the same millisecond. |
| Content resize moves the card mid-animation | **No.** All four panels probed settle `contentHeight` before the card is visible. |

### What is still open

**Latency before the first frame**, which is sluggishness rather than judder:
monitor 152ms, bluetooth 74ms, clock 44ms, network 37ms. Only `monitor` is bad
enough to notice, and it is the 4 processes `refresh()` spawns on open. If it
becomes worth fixing, defer that work until after the entry animation — but
note this needs a per-panel patch, so it means more package-owned files.

**The scrim cut on close.** `panelScrimHoldMs` (150) outlives
`closeFadeDuration` (130), so the fullscreen blur snaps off *after* the card
has gone, with nothing on screen to mask the largest luminance change in the
interaction. Untested idea: drop it to ~80ms so the cut happens while the card
is still moving. It contradicts the documented rule in §6, so change it alone
and look at it.

---

## 6. Tunables

`patches/shell/Ui/KeyboardPanel.qml`:

| Knob | Value | Effect |
|---|---|---|
| `centerOnScreen` | `true` | false restores stock bar-anchored placement |
| `openMotionDuration` | `260` | entry length |
| `closeMotionDuration` | `150` | exit length |
| `fadeDuration` | `180` | open fade |
| `closeFadeDuration` | `130` | close fade |
| `emergeScale` | `0.96` | start scale — above ~0.9 glyph stretching becomes visible |
| `travelFraction` | `0.12` | share of the distance to the button that is travelled |
| `maxTravel` | `Style.space(56)` | cap on that travel; also the handoff slide distance |

`patches/shell/plugins/bar/Bar.qml`:

| Knob | Value | Effect |
|---|---|---|
| `panelScrimColor` | `Color.menu.scrim` | the one backdrop, behind panels, wheel, browser and clipboard alike |
| `panelScrimHoldMs` | `150` | **must stay >= `closeFadeDuration`** or the backdrop drops out early |

Installed blur strength comes from `config/hyprland.lua` (`size 4, passes 2`).
Put personal overrides after the managed block in your main Hyprland config.
`passes` has the most effect; `passes 1` for a lighter frost.

> Two cross-file couplings, both easy to break: `panelScrimHoldMs` >=
> `closeFadeDuration`, and `bar.lastSwitchDirection` / `bar.panelSurfaceVisible()`
> are a contract `KeyboardPanel` depends on. Both are commented on each side.
