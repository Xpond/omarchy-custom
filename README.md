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

Plus, in `~/.config/hypr/` (backed up as `*.bak.centered-panel`):

- `looknfeel.lua` — `decoration.blur.enabled = true` (Omarchy ships it off, so
  layer blur was inert)
- `hyprland.conf` — `layerrule = blur on, match:namespace omarchy-keyboard-panel`

## Caveat

The three shell files are **package-owned**. `omarchy update` overwrites them.
Re-run `install.sh` after an update, or `revert.sh` to back out entirely.

## Tuning

In `shell/Ui/KeyboardPanel.qml`:

- `scrimAlpha` (0.32) — backdrop darkness
- `centerOnScreen` (true) — set false for stock bar-anchored placement
- `entryMotion` duration (220ms) and `Style.space(56)` / `Style.space(20)` —
  slide distance and speed
