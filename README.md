# omarchy-custom

Personal customizations to [Omarchy](https://omarchy.org): shell plugins we
own outright, and patches to the parts of the packaged shell we don't.

    plugins/    our Quickshell plugins, symlinked into ~/.config/omarchy/plugins/
    patches/
      shell/    patched copies, mirroring /usr/share/omarchy/shell/
      orig/     pristine upstream copies — the revert source, never edit
    bin/        scripts the keybinds and the browser call
    docs/       the long-form writeups
    install.sh / revert.sh

The split matters: anything under `plugins/` is user-owned and survives
`omarchy update` untouched, so prefer a plugin over a patch whenever the
shell's plugin API can carry the idea. `patches/` is for the rest, and costs
a merge on every upstream release.

## What's here

**The wheel** (`plugins/xpo.wheel/`) — a radial control center on `SUPER+A`.
Your bar's panels on a ring reachable by direction, and a search field in the
hub that covers the Omarchy menu, installed apps, open windows, themes and
fonts — and, behind a leading `/`, every path under `$HOME`. Pick the ring
yourself in `~/.config/omarchy/wheel.json`.
`SUPER+W` closes the wheel and anything it opened, falling back to
close-window.
`node plugins/xpo.wheel/check.js` verifies every menu entry is reachable.
See [`docs/wheel.md`](docs/wheel.md).

**The files browser** (`plugins/xpo.files/`) — a two-column directory browser
the wheel opens by searching `files`. Type to filter, `/` to type a path,
arrows to walk it; the right pane previews folders, images, rendered Markdown
and syntax-highlighted code. `Ctrl+E` edits the file you are looking at,
`Ctrl+X`/`Ctrl+C`/`Ctrl+V` move and copy, `F2` renames, `Del` trashes. Home is
the floor and it opens there every time.
See [`docs/files.md`](docs/files.md).

**Centered panels** (`patches/shell/`) — the bar's panels open centered over a
blurred desktop instead of tucked against their bar widget, with `Escape` to
close and `Ctrl+Left/Right` to move between them.
See [`docs/centered-panels.md`](docs/centered-panels.md).

## Requirements

Tested with Omarchy **4.0.2**, Quickshell **0.3.1**, and Qt **6.11.2** on
Hyprland. Other versions have not been verified.

- Installation: Bash, Git, `jq`, `sudo`, and the Omarchy CLI.
- File search: `fd`. File operations use standard GNU utilities and `gio`
  (trash); path copying uses `wl-copy`.
- Opening files: `xdg-mime`, `xdg-open`, and `setsid`.
- Optional: Python 3 with Pygments for syntax colours, ImageMagick `identify`
  for image dimensions, and `notify-send` for desktop installation alerts.
  Without the first two, plain text previews and image previews still work.

## Use

```bash
./install.sh   # link the plugins, patch the packaged shell, restart it
./revert.sh    # remove plugins and hook, restore the pristine packaged QML
```

`install.sh` links every directory under `plugins/` into
`~/.config/omarchy/plugins/`, registers each id in `~/.config/omarchy/shell.json`
— a plugin the shell cannot find listed there is one it does not load, and
`omarchy refresh shell` rewrites that file from the defaults — and puts
`bin/omarchy-open-path` on `PATH`, which the browser runs by name.

**Only the patch wants root.** It writes three package-owned files under
`/usr/share/omarchy/shell`, and that is the only `sudo` in the script: asked
per file, and only when that file actually differs, so a re-run that finds
everything in place never prompts. Everything else lives under `$HOME`.

Two pieces are deliberately *not* installed, only checked for and named on
stdout: the layer rules in `~/.config/hypr/looknfeel.lua` (without them the
wheel and the browser get no blur) and the `SUPER+A` binding in `bindings.lua`.
Both are hand-kept Lua carrying your own comments, and a script splicing lines
into those fails worse than a missing line it tells you about.

Links, not copies: editing the repo *is* editing the installed plugin. It still
needs `omarchy-restart-shell` — QML components are cached, so `rescanPlugins`
alone will not reload changed code.

The patched shell files are **package-owned**, so `omarchy update` overwrites
them. `install.sh` generates and installs a post-update hook pointing to this
checkout, wherever you cloned it. Keep the checkout at that location; after
moving it, rerun `install.sh`. `revert.sh` removes the hook too, so a later
update does not reinstall the customization.

A missing `shell.json` is created. Existing invalid JSON is preserved and
registration failure returns a nonzero exit code.

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

These edits live outside this repo, in `~/.config/hypr/`:

    looknfeel.lua   the global blur enable, QSG_RENDER_LOOP, and blur layer
                    rules for the panel scrim, the wheel and the browser
    bindings.lua    SUPER+A (press opens the wheel, release commits),
                    SUPER+W (close wheel/panel, else close window)

`install.sh` names any of these that is missing but never writes them, and
`revert.sh` leaves them alone. There are `*.bak.centered-panel` copies in that
directory from the first prototype run; they predate everything above, so treat
them as history rather than as a restore point.

## Checks

```bash
node tests/check.js
python3 tests/install.py
python3 tests/runtime.py
node plugins/xpo.wheel/check.js
```

The first three use fixtures; the last checks this machine's real Omarchy menu.
The runtime fixtures use Quickshell offscreen and do not change the clipboard.
