# omarchy-custom

A radial control center, a file browser and centered shell panels for
[Omarchy](https://omarchy.org).

- **Wheel** (`SUPER+A`): your bar's panels on a ring. Start typing to search
  every panel, the Omarchy menu, apps, open windows, themes and fonts; begin
  with `/` to search files and folders under your home instead. `SUPER+W`
  closes the wheel and any open shell panel, otherwise the active window. See
  [`docs/wheel.md`](docs/wheel.md).
- **Files**: a keyboard-driven directory browser with previews, opened from
  the wheel. See [`docs/files.md`](docs/files.md).
- **Centered panels**: bar panels open centered over a blurred desktop. See
  [`docs/centered-panels.md`](docs/centered-panels.md).
- **Lock screen**: a 3D line-art Audi quattro assembles above the password
  field as comets trace its outlines, gains city reflections and gold rims,
  and drives off through a painted neon scene when you unlock.
  Try it without locking: `omarchy-shell lock preview`. Work in progress; see
  [`docs/lockscreen.md`](docs/lockscreen.md).

Tested only on Omarchy 4.0.3 with Quickshell 0.3.1. It patches the packaged
shell, so it is not a plugin `omarchy plugin add` can install.

## Install

Needs `jq`, `python3`, `git`, `hyprctl`, `sudo`, `fd`, `wl-copy`, `gio`,
`xdg-open`, `xdg-mime` and `setsid`. Optional: Pygments for code colours and
ImageMagick's `identify` for image sizes. Run from your Omarchy session:

```bash
git clone https://github.com/Xpond/omarchy-custom
cd omarchy-custom
./install.sh
```

It links `plugins/` into `~/.config/omarchy/plugins/` and registers them in
`~/.config/omarchy/shell.json`, appends a marked block (keybinds, layer rules,
blur, render loop) to `~/.config/hypr/hyprland.lua`, links two helpers into
`~/.local/bin`, installs the compiled paint/focus shaders and scene artwork into
`~/.local/share/omarchy-custom/`, patches eight shell files, installs a post-update
hook, and restarts the shell. Rerunning is safe. Keep the checkout where it is:
the hook points to it.

## Revert

```bash
./revert.sh
```

Removes the hook, plugins, Hyprland block and helper links, puts back Omarchy's
original shell files, and removes the shaders and scene artwork after a successful
restore, then restarts the shell. Originals are checked against
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
