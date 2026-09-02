# Centered shell panels — Omarchy prototype

Makes Omarchy's bar panels (Display, Audio, Network, Power…) open **centered
on screen**, over a **blurred desktop**, with a **slide-in transition** and
**Ctrl+Left/Right** to move between panels.

Panel content and styling are untouched — only where the card sits, what's
behind it, and how it arrives.

## Layout

    orig/     pristine v4.0.0.alpha files — the revert source, never edit
    shell/    patched copies, mirroring /usr/share/omarchy/shell/
    docs/     centered-panels.md — the full writeup
    install.sh / revert.sh

## Use

```bash
./install.sh   # patch the packaged shell, restart it (asks for sudo)
./revert.sh    # restore pristine QML + hypr config
```

The three shell files are **package-owned**, so `omarchy update` overwrites
them and the shell reverts to stock. That is repaired automatically by a
post-update hook:

```bash
omarchy hook install post-update ~/xpo/custom/quickshell/hooks/centered-panels
```

`install.sh` is idempotent, and when an update ships a *new* version of a
patched file it rebases the patch onto it with a three-way merge rather than
clobbering upstream's changes. A conflict leaves the file stock and shouts via
`notify-send` instead of writing broken QML.

## The one thing that will bite you

Smooth animation depends on `hl.env("QSG_RENDER_LOOP", "threaded")` in
`~/.config/hypr/looknfeel.lua`. Without it Qt drives animations from a 16ms
timer — 62Hz against a 144Hz display — and every panel judders.

**It must be the Lua `hl.env()` form.** `env = QSG_RENDER_LOOP,threaded` in
`hyprland.conf` is accepted silently and does nothing.

`install.sh` now checks this for you and shouts via `notify-send` if the
shell comes up on the wrong render loop. To check by hand:

```bash
P=$(pgrep -x quickshell); cat /proc/$P/task/*/comm | grep QSGRenderThread
```

That thread exists only under the threaded render loop — config presence
proves nothing, which is exactly how this stayed broken for days.

## Everything else

[`docs/centered-panels.md`](docs/centered-panels.md) — what changed and why,
the Hyprland/Quickshell findings worth not rediscovering, how to measure
frame timing properly, and the tunables.
