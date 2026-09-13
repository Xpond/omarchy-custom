# omarchy-custom

Personal customizations to [Omarchy](https://omarchy.org): shell plugins we
own outright, and patches to the parts of the packaged shell we don't.

    plugins/    our Quickshell plugins, symlinked into ~/.config/omarchy/plugins/
    patches/
      shell/    patched copies, mirroring /usr/share/omarchy/shell/
      orig/     upstream merge bases, updated by successful rebases
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

Tested with Omarchy **4.0.3**, Quickshell **0.3.1**, and Qt **6.11.2** on
Hyprland. Other versions have not been verified.

- Installation: Bash, Git, Python 3, `jq`, `sudo`, `hyprctl`, and the Omarchy CLI.
  Run from an active Omarchy session with `~/.config/hypr/hyprland.lua` present.
- File search: `fd`. File operations use standard GNU utilities and `gio`
  (trash); path copying uses `wl-copy`.
- Opening files: `xdg-mime`, `xdg-open`, and `setsid`.
- Optional: Pygments for syntax colours, ImageMagick `identify`
  for image dimensions, and `notify-send` for desktop installation alerts.
  Without the first two, plain text previews and image previews still work.

## Use

```bash
./install.sh   # link the plugins, patch the packaged shell, restart it
./revert.sh    # remove plugins and hook, restore recorded shell backups
```

`install.sh` links every directory under `plugins/` into
`~/.config/omarchy/plugins/`, registers each id in `~/.config/omarchy/shell.json`
— a plugin the shell cannot find listed there is one it does not load, and
`omarchy refresh shell` rewrites that file from the defaults — and puts
both `bin/omarchy-open-path` and `bin/omarchy-wheel-close` in `~/.local/bin`.

**Only the patch wants root.** It writes six package-owned files under
`/usr/share/omarchy/shell`, and that is the only `sudo` in the script: asked
per file, and only when that file actually differs, so a re-run that finds
everything in place never prompts. Everything else lives under `$HOME`.

Installation appends a marked block from `config/hyprland.lua` to your main
`~/.config/hypr/hyprland.lua`. It sets `SUPER+A` press/release, overrides
`SUPER+W` with the wheel-aware close helper, enables shared backdrop blur,
disables blur/fades on the wheel and files overlays, and sets the threaded
render loop. Existing binding and appearance files remain intact.
Hyprland is reloaded and checked for errors before the shell is restarted.

Links, not copies: editing the repo *is* editing the installed plugin. It still
needs `omarchy-restart-shell` — QML components are cached, so `rescanPlugins`
alone will not reload changed code.

The patched shell files are **package-owned**, so `omarchy update` overwrites
them. `install.sh` generates and installs a post-update hook pointing to this
checkout, wherever you cloned it. Keep the checkout at that location; after
moving it, rerun `install.sh`. `revert.sh` removes the hook too, so a later
update does not reinstall the customization.

A missing `shell.json` is copied from Omarchy's defaults. Existing invalid JSON
is preserved and registration failure returns a nonzero exit code.

`install.sh` is idempotent. When an update ships a *new* version of a patched
file it rebases the patch onto it with a three-way merge rather than clobbering
upstream's changes; a conflict leaves the installed file untouched and reports
it via `notify-send`. Successful rebases update the repository's merge bases.

Before writing each shell file, installation saves its current contents under
`~/.local/state/omarchy-custom/orig/` and the intended patch under `installed/`
in the same state directory. Reinstalling or updating our own patch retains
the original backup. If a package update or external edit replaces that patch,
the next successful rebase saves that replacement as the new restore point.

`revert.sh` restores only recorded files that still match the installed patch.
It preserves later edits and incomplete copies, retains their backups, and
returns failure with the affected paths. Resolve those files before retrying.
An incomplete install or restore is marked pending; retries preserve its backup until
the file matches the saved original or the complete intended patch.
Successful restoration clears that file's record; initial merge conflicts are
never restored over. Older installations without backups are left untouched
and reported: `.installed/` remains a legacy comparison source, not proof of
what existed before installation.

## The one thing that will bite you

Smooth animation depends on `hl.env("QSG_RENDER_LOOP", "threaded")` in the
managed Hyprland block. Without it Qt drives animations from a 16ms
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

The `BEGIN omarchy-custom` / `END omarchy-custom` block is managed by the
installer. Put personal overrides outside it. Revert removes the exact block,
preserving surrounding edits and restoring the bindings from your remaining
configuration. Older manual wheel bindings/rules remain in place.

The original config and ownership records live in
`~/.local/state/omarchy-custom/user-config.json`. Edited managed blocks or
conflicting helper files are reported and left untouched. Existing helper links
to this checkout are borrowed; revert removes only links the installer created.
Failed reload validation restores the previous config, links, and records.

## Checks

```bash
node tests/check.js
python3 tests/install.py
python3 tests/desktop.py
python3 tests/runtime.py
node plugins/xpo.wheel/check.js
```

All but the last use fixtures; the last checks this machine's real Omarchy menu.
The desktop fixture also executes the shipped configuration with Lua.
The runtime fixtures use Quickshell offscreen and do not change the clipboard.
They include the production plugin loader and facade together to catch QML
model conversion errors, as well as backdrop counting and popout ownership.
