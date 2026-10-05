# wheely

A radial control center, a file browser and centered shell panels for
[Omarchy](https://omarchy.org).

- **Wheel** (`SUPER+A`): your bar's panels on a ring. Start typing to search
  every panel, the Omarchy menu, every keybinding, apps, open windows
  (`workspace` lists them all), themes and fonts; begin
  with `/` to search files and folders under your home instead (`Ctrl+Enter`
  opens a terminal in one), or with `=`
  to calculate (`Enter` copies the answer). `SUPER+W`
  closes the wheel and any open shell panel, otherwise the active window. Its
  settings are search rows too: `wheely shortcut` changes the key that opens it.
  See [`docs/wheel.md`](docs/wheel.md).
- **Files**: a keyboard-driven directory browser with previews, opened from
  the wheel. See [`docs/files.md`](docs/files.md).
- **Centered panels**: bar panels open centered over a blurred desktop. See
  [`docs/centered-panels.md`](docs/centered-panels.md).
- **Lock screen**: swappable designs, picked in the wheel under Style ›
  Lockscreen Designs. `rally`: a 3D line-art Audi quattro assembles above the
  password field as comets trace its outlines, gains city reflections and gold
  rims, and drives off through a painted neon scene when you unlock.
  `tunnel`: Omarchy logos stacked into a neon line-art corridor you fly through, each
  with its own hue and a comet running through it like the wheel's.
  `mycelium`: a colony of fine hyphae grows from the centre until it has taken the
  screen, its tips glowing as they push on and lighting the dark ground, with more of it
  out of focus deeper down; it sways as in a hyperlapse, and draws back in when you unlock.
  `shore`: where the wash meets the sand, seen close from high above: the water's edge surges
  across the middle of the screen under a rope of foam and slides back, with ripples, glints and
  caustics in the shallow water; unlocking brings the tide in.
  `meadow`: wildflowers grow into “omarchy” above a low meadow, under a starlit sunset sky
  with drifting fireflies. The flowers sway gently and fade on unlock.
  `wallpaper`: Omarchy's own blurred wallpaper. Try one without locking:
  `omarchy-shell lock preview`. Work in progress; see
  [`docs/lockscreen.md`](docs/lockscreen.md).

Tested only on Omarchy 4.0.4 with Quickshell 0.3.1. It patches the packaged
shell, so it is not a plugin `omarchy plugin add` can install.

## Install

Needs `jq`, `python3`, `git`, `hyprctl`, `sudo`, `fd`, `wl-copy`, `gio`,
`xdg-open`, `xdg-mime` and `setsid`. Optional: Pygments for code colours and
ImageMagick's `identify` for image sizes. Run from your Omarchy session:

```bash
git clone https://github.com/Xpond/wheely
cd wheely
./install.sh
```

It links `plugins/` into `~/.config/omarchy/plugins/` and registers them in
`~/.config/omarchy/shell.json`, appends a marked block (keybinds, layer rules,
blur, render loop) to `~/.config/hypr/hyprland.lua`, links three helpers into
`~/.local/bin`, links the lock-screen designs in `lock/` into
`~/.local/share/wheely/`, patches eight shell files, installs a post-update
hook, and restarts the shell. Rerunning is safe. Keep the checkout where it is:
the hook points to it.

## Revert

```bash
./revert.sh
```

Removes the hook, plugins, Hyprland block and helper links, puts back Omarchy's
original shell files, and unlinks the lock-screen designs and forgets the chosen one
after a successful restore, then restarts the shell. Originals are checked against
pacman's checksums before they are written, and a shell file changed outside
this project is left untouched and reported.

## Why sudo

The eight patched files live in `/usr/share/omarchy/shell`, owned by the Omarchy
package. Copying them in (install) and restoring them (revert) are the only
`sudo` calls, and each runs only when a file actually needs changing.
Everything else stays in your home directory.

Because the package owns them, `omarchy update` overwrites them. The hook then
reruns `install.sh`, which merges the patches onto the new version; a conflict
leaves the shipped file as it is and is reported, on the desktop too when
`notify-send` is available.

## License

MIT, see [`LICENSE`](LICENSE). `patches/` holds original and modified Omarchy
shell files and `plugins/xpo.wheel/mark.png` is derived from Omarchy's icon,
both under [`LICENSE.omarchy`](LICENSE.omarchy). The fluid shader is adapted
from hyprglaze: [`LICENSE.hyprglaze`](plugins/xpo.wheel/LICENSE.hyprglaze).
