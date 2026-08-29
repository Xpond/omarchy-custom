# Centered shell panels — Omarchy prototype

Makes Omarchy's bar panels (Display, Audio, Network, Power…) open **centered
on screen**, over a **blurred desktop**, with a **slide-in transition** and
**Ctrl+Left/Right** to move between panels.

Panel content and styling are untouched — only where the card sits, what's
behind it, and how it arrives.

## Layout

    orig/     pristine v4.0.0.alpha files — the revert source, never edit
    shell/    patched copies, mirroring /usr/share/omarchy/shell/
    install.sh / revert.sh

## What changed

| File | Change |
|---|---|
| `Ui/KeyboardPanel.qml` | `centerOnScreen` placement in `cardOrigin`; full-screen scrim; `slideX/slideY` transform driven by `entryMotion` |
| `Ui/PanelKeyCatcher.qml` | Ctrl+Left/Right → `tabRequested` (bare arrows still drive sliders) |
| `plugins/bar/Bar.qml` | `lastSwitchDirection`, so the incoming panel knows which side to slide in from |

Plus, in `~/.config/hypr/looknfeel.lua` (backed up as `*.bak.centered-panel`):

```lua
decoration = { blur = { enabled = true, size = 8, passes = 3 } }

hl.layer_rule({
  match = { namespace = "omarchy-keyboard-panel" },
  blur = true,
  ignore_alpha = 0.05,
})
```

Two things that cost time here, worth writing down:

1. **Omarchy 4 uses Hyprland's Lua parser.** Legacy `layerrule = blur on, ...`
   lines in a `.conf` file are silently ignored — no error, no warning, no
   blur. Layer rules must go through `hl.layer_rule({...})`.
2. **`ignore_alpha` must sit below the scrim's alpha.** Hyprland skips blur on
   regions it considers too transparent, so a 0.32 scrim needs a threshold
   below 0.32 or the blur never renders — while the dim still does, which
   makes it look like the scrim itself is broken.

Note: `layerrule = blur on, match:namespace logout_dialog` in your
`hyprland.conf` is legacy syntax too, and has never done anything. Left alone —
it predates this work.

## Caveat

The three shell files are **package-owned**. `omarchy update` overwrites them.
Re-run `install.sh` after an update, or `revert.sh` to back out entirely.

## Tuning

In `shell/Ui/KeyboardPanel.qml`:

- `scrimAlpha` (0.32) — backdrop darkness
- `centerOnScreen` (true) — set false for stock bar-anchored placement
- `entryMotion` duration (220ms) and `Style.space(56)` / `Style.space(20)` —
  slide distance and speed
