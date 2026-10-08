# Tests

Run the existing entry points from the repository root:

| Command | Coverage and layout |
| --- | --- |
| `node tests/check.js` | File indexing/navigation, wheel menus/input/settings/ring/folders, shell panels, actions, file operations, sky and trails. Imports the focused JavaScript suites. |
| `python3 tests/runtime.py` | Offscreen QML behavior. Calls `plugin_shell.py`, `wheel_refresh.py`, `wheel_scans.py`, `wheel_menu.py`, `file_runtime.py` (including `file_edits.py`), `files_lifecycle.py`, and `wheel_settings.py`. |
| `python3 tests/install.py` | Install/revert, package updates and failure recovery using temporary paths. `install_fixture.py` supplies the isolated system and command stubs. |
| `python3 tests/desktop.py` | Hyprland setup by `scripts/user-config.py`: personal edits survive install/revert, interrupted or rejected installs roll back, and the shipped Lua (run through `desktop.lua`) binds the saved shortcut. `install.py` reuses its `prepare` and `verify`. |

Each JavaScript suite can also run alone, for example
`node tests/wheel-ring.js`. `qml.js` and `wheel-source.js` contain shared
source-loading helpers; the Python modules listed above are called by their
entry points, rather than run separately.

These four commands are not the entire suite. Additional checks and their
dependencies are documented with the features:

- [Wheel](../docs/wheel.md)
- [Files](../docs/files.md)
- [Shell panels](../docs/centered-panels.md)
- [Lock screen](../docs/lockscreen.md)

`lock-render.py` uses native Wayland windows; the other rendering suites use
offscreen fixtures. `lock-process.py` simulates the compositor and authentication.
