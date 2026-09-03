# omarchy-custom

Personal customizations to [Omarchy](https://omarchy.org): shell plugins we
own outright, and patches to the parts of the packaged shell we don't.

    plugins/    our Quickshell plugins, symlinked into ~/.config/omarchy/plugins/
    patches/
      shell/    patched copies, mirroring /usr/share/omarchy/shell/
      orig/     pristine upstream copies — the revert source, never edit
    bin/        scripts our keybinds point at
    hooks/      omarchy post-update hooks
    docs/       the long-form writeups
    install.sh / revert.sh

The split matters: anything under `plugins/` is user-owned and survives
`omarchy update` untouched, so prefer a plugin over a patch whenever the
shell's plugin API can carry the idea. `patches/` is for the rest, and costs
a merge on every upstream release.

## What's here

**The wheel** (`plugins/xpo.wheel/`) — a radial control center on `SUPER+A`.
Eight panels on a ring reachable by direction, and a search field in the hub
that covers every entry in the Omarchy menu (271 actions). `SUPER+W` closes
the wheel and anything it opened, falling back to close-window.
See [`docs/wheel.md`](docs/wheel.md).

**Centered panels** (`patches/shell/`) — the bar's panels open centered over a
blurred desktop instead of tucked against their bar widget, with `q`/`Escape`
to close and `Ctrl+Left/Right` to move between them.
See [`docs/centered-panels.md`](docs/centered-panels.md).

## Use

```bash
./install.sh   # patch the packaged shell, restart it (asks for sudo)
./revert.sh    # restore pristine QML + hypr config
```

Only `patches/` needs installing. Plugins are picked up from the symlink, and
editing one needs `omarchy-restart-shell` — QML components are cached, so
`rescanPlugins` alone will not reload changed code.

The patched shell files are **package-owned**, so `omarchy update` overwrites
them. That is repaired automatically by a post-update hook:

```bash
omarchy hook install post-update ~/xpo/omarchy-custom/hooks/centered-panels
```

`install.sh` is idempotent. When an update ships a *new* version of a patched
file it rebases the patch onto it with a three-way merge rather than clobbering
upstream's changes; a conflict leaves the file stock and shouts via
`notify-send` instead of writing broken QML. It tells a new upstream from our
own previous patch by way of the `.installed/` mirror — without that it reads
every edit of our own patch as an upstream change, and the rebase's success
path overwrites `patches/orig/`, the revert source.

## The one thing that will bite you

Smooth animation depends on `hl.env("QSG_RENDER_LOOP", "threaded")` in
`~/.config/hypr/looknfeel.lua`. Without it Qt drives animations from a 16ms
timer — 62Hz against a 144Hz display — and every panel judders.

**It must be the Lua `hl.env()` form.** `env = QSG_RENDER_LOOP,threaded` in
`hyprland.conf` is accepted silently and does nothing.

`install.sh` checks this for you and shouts via `notify-send` if the shell
comes up on the wrong render loop. To check by hand:

```bash
P=$(pgrep -x quickshell); cat /proc/$P/task/*/comm | grep QSGRenderThread
```

That thread exists only under the threaded render loop — config presence
proves nothing, which is exactly how this stayed broken for days.

## Hyprland config we own

Three edits live outside this repo, in `~/.config/hypr/` (backed up as
`*.bak.wheel`):

    looknfeel.lua   QSG_RENDER_LOOP, and blur layer rules for the panel
                    scrim and the wheel
    bindings.lua    SUPER+A (press opens the wheel, release commits),
                    SUPER+W (close wheel/panel, else close window)
