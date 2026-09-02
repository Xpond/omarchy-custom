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

The three shell files are **package-owned**: `omarchy update` overwrites them.
Re-run `install.sh` afterwards.

## The one thing that will bite you

Smooth animation depends on `env = QSG_RENDER_LOOP,threaded` in
`~/.config/hypr/hyprland.conf`. Without it Qt drives animations from a 16ms
timer — 62Hz against a 144Hz display — and every panel judders.

Hyprland exports `env` only at compositor startup, so **after adding it you
must log out and back in.** Until you do, `omarchy restart shell` (and so
`install.sh`) respawns the shell from Hyprland's old environment and the
judder silently returns. Verify with:

```bash
tr '\0' '\n' < /proc/$(pgrep -x quickshell)/environ | grep QSG
```

## Everything else

[`docs/centered-panels.md`](docs/centered-panels.md) — what changed and why,
the Hyprland/Quickshell findings worth not rediscovering, how to measure
frame timing properly, and the tunables.
