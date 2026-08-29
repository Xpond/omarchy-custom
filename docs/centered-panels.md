# Centered shell panels — state of the work

Omarchy 4.0.0.alpha · Quickshell 0.3.1 · Hyprland 0.56.2 · DP-3 1920x1080 **@144Hz**

Makes Omarchy's bar panels (Display, Audio, Network, Power…) open centered on
screen over a blurred desktop, instead of tucked against the bar edge beside
their widget.

**Working:** centering, blur, Ctrl+Left/Right panel switching, and the
panel-to-panel handoff transition.
**Not working:** the open/close animation. That is the whole of the remaining
work — see [Open problem](#open-problem-the-open-close-animation).

---

## 1. How to work on this

```bash
~/xpo/custom/quickshell/install.sh   # patch the packaged shell, restart it
~/xpo/custom/quickshell/revert.sh    # restore pristine QML + hypr config
```

`install.sh` needs a sudo password, so it must be run by the user from a
terminal (`! ~/xpo/custom/quickshell/install.sh` inside Claude Code). It keeps
**one** pristine backup per file (`*.omarchy-original`, taken on first run
only) and warns solely when a packaged file matches neither `orig/` nor
`shell/` — which is the real signal that `omarchy update` shipped a new
version.

```
orig/     pristine v4.0.0.alpha files — the revert source, never edit
shell/    patched copies, mirroring /usr/share/omarchy/shell/
docs/     this file
```

### The constraint that shapes everything

The files being changed are **shared shell chrome**, not plugins.
`omarchy plugin clone` cannot reach them, and `/usr/share/omarchy/` is
package-owned, so **`omarchy update` will overwrite all three.** Re-run
`install.sh` afterwards. The user ruled out cloning panels and ruled out
changing panel styling, which is what put the work in shared chrome.

---

## 2. What changed

Three package-owned QML files (~260 added lines total) plus Hyprland config.

| File | Change |
|---|---|
| `Ui/KeyboardPanel.qml` | `centerOnScreen` placement in `cardOrigin`; `slideX`/`slideY`/`originScale` transform; entry/exit animations; reports surface visibility to the bar |
| `Ui/PanelKeyCatcher.qml` | Ctrl+Left/Right → `tabRequested` (9 lines) |
| `plugins/bar/Bar.qml` | `PanelScrim` — the shared blurred backdrop; `lastSwitchDirection`; `visiblePanelSurfaces` counter |

`~/.config/hypr/looknfeel.lua` (backed up as `*.bak.centered-panel`):

```lua
decoration = { blur = { enabled = true, size = 4, passes = 2 } }

hl.layer_rule({
  match = { namespace = "omarchy-panel-scrim" },
  blur = true,
  ignore_alpha = 0.05,
  no_anim = true,
  animation = "none",
})
```

### Why the scrim lives in the bar

Panels are separate layer surfaces that unmap and remap as you tab between
them. A scrim inside a panel blinks out mid-handoff and takes Hyprland's blur
with it. One bar-owned surface stays mapped across the whole interaction.

Ordering is by **Wayland layer**, not by `layer_rule`'s `order` field:

```
Overlay   omarchy-keyboard-panel   the card — opaque, stays sharp
Top       omarchy-panel-scrim      the blurred wash
Top       omarchy-bar
```

`order` was tried first and did not hold — the scrim came out above the panel
and blurred the card along with the desktop. Layer separation is a protocol
guarantee; `order` is a hint.

---

## 3. Findings worth not rediscovering

**Omarchy 4 uses Hyprland's Lua parser.** Legacy `layerrule = blur on, …`
lines in a `.conf` file are **silently ignored** — no error, no warning,
`hyprctl configerrors` stays clean. Layer rules must go through
`hl.layer_rule({...})`. (The pre-existing `layerrule = blur on, match:namespace
logout_dialog` at `~/.config/hypr/hyprland.conf:31` is legacy syntax and has
never done anything. Left alone — it predates this work.)

**`hyprctl keyword` cannot set layerrules** on this parser: *"keyword can't
work with non-legacy parsers."* Edit the Lua and `hyprctl reload`.

**`ignore_alpha` must sit below the scrim's own alpha.** Hyprland skips blur on
regions it considers too transparent. At `panelScrimAlpha 0.32` a default
threshold suppressed the blur entirely while the dim still rendered — which
looks exactly like a broken scrim rather than a blur problem.

**Every Omarchy shell layer surface sets `no_anim = true, animation = "none"`**
(see `default/hypr/apps/omarchy-shell.lua`). Without it Hyprland runs its own
fade on map/unmap, and on a *blurred* surface that means recomputing a
fullscreen blur every frame of the fade. Adding this cut the post-close churn
from 278ms to 132ms.

**Never animate the scrim's alpha,** for the same reason — one QML fade cost a
fullscreen blur recompute per frame. It snaps on, and is *held* through the
close by a timer instead.

**Panel surfaces cost ~100ms to map.** Quickshell creates the layer surface when
`visible` flips, and the compositor maps it some frames later. Omarchy hit this
too and solved it for the bar by parking it off-screen rather than unmapping —
see the comment in `BarPanel`, which puts it at ~150ms to rebuild vs ~20ms to
tear down.

**Qt Quick already applies transforms on the GPU.** `layer.enabled` to "avoid
re-rasterization" was based on a false premise and made things measurably
worse — it only added an FBO allocation and an extra render-to-texture pass.

**`In*` easing is wrong for a dismissal.** `InQuint` covers `0.5⁵ = 3%` of the
distance by the halfway point, so the card hangs still while the fade runs,
then jumps. Both directions want fast-start (`Out*`) curves.

---

## 4. Measuring, instead of guessing

Most of the wrong turns here came from tuning motion by eye and by theory. The
measurement pipeline below is what actually found the real bugs, and it is
cheap to re-run.

`grim` is far too slow — 14 captures yielded **one** frame of a 200ms
animation. Use `gpu-screen-recorder`. NVENC is broken on this box (driver
supports nvenc API 13.0, the bundled FFmpeg needs 13.1), so force CPU encoding,
and record a **region** so the CPU encoder can keep up:

```bash
gpu-screen-recorder -w region -region 900x700+510+340 -f 144 -fm cfr \
  -encoder cpu -fallback-cpu-encoding yes -cursor no -o rec.mp4 &
sleep 2; omarchy-shell omarchy.monitor open
sleep 1.5; omarchy-shell omarchy.monitor close     # ALWAYS record both halves
sleep 1.2; kill -INT %1
```

Per-frame change, which is what exposes dead frames and trailing churn:

```bash
ffmpeg -v error -i rec.mp4 -vf \
 "scale=300:233,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
 -f null - | paste - -
```

A healthy animation is a smooth decaying series. `0.00` between changes is a
dead frame. Drive panels over IPC (`omarchy-shell omarchy.monitor open|close`)
so runs are repeatable.

**Caveat:** CPU encoding at 144fps may itself drop frames, so alternating
zero-rows are not conclusive proof of compositor stutter. Relative comparisons
between two runs are trustworthy; absolute frame counts are not.

---

## 5. Open problem: the open/close animation

The user's verdict on the current state: **worse than no animation.** The
`monitor` panel "janks big time", others less so. Animation is required — it
is the point of the project, not a nice-to-have.

### What the recordings established

- The animation originally never rendered at all: **one** changed frame in the
  whole window, 71/72 identical. It was running to completion against a window
  the compositor had not mapped yet. Starting it on `backingWindowVisible`
  fixed that, and is what finally made the motion visible — and its problems
  along with it.
- The backdrop arrived **104ms before the card**. Fixed via
  `visiblePanelSurfaces`, so blur and card appear together.
- Close is now a clean decay: `3.40 → 2.69 → 2.02 → 1.35 → 0.98 → 0.49 → 0.26
  → 0.15`, then one frame where the scrim snaps off.
- Open still has dead frames and, per the user, visible jank.

### The leading hypothesis

Jank tracks **what each panel does on open**, not the animation code, which is
shared and identical for all of them:

| Panel | Processes | `onOpenedChanged` | User reports |
|---|---|---|---|
| `monitor` | 4 | `refresh()` — respawns queries, rebuilds displays/brightness/scale | janks badly |
| `power` | 4 | yes | janks |
| `bluetooth` | 0 | yes (5 timers) | — |
| `clock` | 0 | **none** | fine |

Heavy panels spawn processes and rebuild their models in the same frames as the
entry animation, against a **6.9ms budget** at 144Hz.

A secondary possibility, **unverified**: that work changes the content height,
and since a centered card's origin depends on `contentHeight`, the card
re-centres mid-animation. An attempt to confirm this by measuring the card's
bounding box across frames was **inconclusive** — the brightness threshold
caught blurred background rather than isolating the card. Worth retrying with a
better isolation method before acting on it.

### Options for next session

1. **Defer panel work until the entry animation finishes.** Targets the leading
   hypothesis directly. Means patching `monitor`/`power`/`bluetooth`/`audio`
   `Panel.qml` — more package-owned files, and a test pass per panel.
2. **Pre-map panel surfaces** (park off-screen, as `BarPanel` does) to remove
   the ~100ms open latency. Costs one always-mapped fullscreen surface per
   panel.
3. **Shrink the panel surface.** It is fullscreen only to catch outside clicks —
   but the scrim is already fullscreen and could do that instead, taking the
   panel surface from 1920x1080 to ~380x330 and cutting allocation cost. A
   cheaper variant of (2).
4. **Confirm the resize theory first** with a better card-isolation method,
   before committing to (1).

Recommended order: **4 → 1 → 3**. Verify the cause, fix the cause, then reduce
latency. Change one variable per install and re-measure — every regression in
this project came from stacking untested changes.

---

## 6. Tunables

`shell/Ui/KeyboardPanel.qml`:

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

`shell/plugins/bar/Bar.qml`:

| Knob | Value | Effect |
|---|---|---|
| `panelScrimAlpha` | `0.32` | backdrop darkness |
| `panelScrimHoldMs` | `150` | **must stay >= `closeFadeDuration`** or the backdrop drops out early |

Blur strength lives in `~/.config/hypr/looknfeel.lua` (`size 4, passes 2`).
`passes` has the most effect; `passes 1` for a lighter frost.

> Two cross-file couplings, both easy to break: `panelScrimHoldMs` >=
> `closeFadeDuration`, and `bar.lastSwitchDirection` / `bar.panelSurfaceVisible()`
> are a contract `KeyboardPanel` depends on. Both are commented on each side.
