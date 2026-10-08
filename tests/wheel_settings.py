"""Qt shortcut names and persistent wheel settings through real QML."""
import json
import re
import subprocess


def check(wheel, base, env, run, block, line):
    # Shortcut names come from Qt's real key codes, and every one is a key Hyprland can bind.
    keys = ["Key_A", "Key_Z", "Key_0", "Key_9", "Key_F1", "Key_F12", "Key_F24", "Key_Space", "Key_Return",
            "Key_Tab", "Key_Backspace", "Key_Escape", "Key_Delete", "Key_Insert", "Key_Home", "Key_End",
            "Key_PageUp", "Key_PageDown", "Key_Left", "Key_Right", "Key_Up", "Key_Down", "Key_Print",
            "Key_Comma", "Key_Period", "Key_Slash", "Key_Semicolon", "Key_Apostrophe", "Key_BracketLeft",
            "Key_BracketRight", "Key_Backslash", "Key_Minus", "Key_Equal", "Key_QuoteLeft"]
    log = run("shortcut-names", '''
  function named(key, modifiers) { return MenuKeys.shortcutOf({ key: key, modifiers: modifiers }) }
  Timer { interval: 1; running: true; onTriggered: {
    var keys = ''' + json.dumps(keys) + '''
    console.log("NAMES " + JSON.stringify(keys.map(function (k) { return named(Qt[k], Qt.MetaModifier) })))
    var all = Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier
    var cases = [[named(Qt.Key_B, all), "SUPER + CTRL + ALT + SHIFT + B"],
                 [named(Qt.Key_Backtab, Qt.ShiftModifier | Qt.MetaModifier), "SUPER + SHIFT + TAB"],
                 [named(Qt.Key_Space, Qt.AltModifier), "ALT + SPACE"],
                 [named(Qt.Key_Super_L, Qt.MetaModifier), null], [named(Qt.Key_Shift, Qt.ShiftModifier), null],
                 [named(Qt.Key_CapsLock, 0), null], [named(Qt.Key_Exclam, Qt.ShiftModifier), ""],
                 [named(Qt.Key_Enter, Qt.MetaModifier), ""]]
    for (var i = 0; i < cases.length; i++)
      if (cases[i][0] !== cases[i][1]) { console.error("FAIL", i, cases[i][0]); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')
    names = json.loads(re.search(r"NAMES (\[.*\])", log)[1])
    assert len(names) == len(keys) and all(n and n.startswith("SUPER + ") for n in names), names
    binds = base / "names.lua"
    binds.write_text("".join(f'hl.bind("{n}", hl.dsp.exec_cmd("true"))\n' for n in names))
    verdict = subprocess.run(["Hyprland", "--verify-config", "-c", str(binds)], env=env,
                             capture_output=True, text=True, timeout=20).stdout
    assert verdict.rstrip().endswith("config ok"), verdict
    print("ok: every shortcut name the wheel writes is a key Hyprland binds")

    # Saving writes the file, then reloads Hyprland, then reads the bindings again; the reload
    # must see the new key.
    home = base / "home"
    (home / ".config/omarchy").mkdir(parents=True)
    reload = block(wheel, r"  Process \{\n    id: hyprReload")
    reload = re.sub(r"command: \[.*\]", 'command: ["sh", "-c", "cat $HOME/.config/omarchy/wheel-shortcut >> $HOME/reloads"]', reload)
    setting_file = block(wheel, r"  component SettingFile: FileView \{") + "\n"
    run("shortcut-save", '''
  property string shortcut: "unset"
  property int stage: 0
  QtObject { id: bindList; property bool running: false }
  function check(ok, message) { if (!ok) { console.error("FAIL", message); Qt.exit(1) } }
''' + setting_file + block(wheel, r"  SettingFile \{\n    id: shortcutFile") + "\n" + reload + "\n" + block(wheel, r"  function saveShortcut\(") + '''
  Timer { interval: 150; running: true; repeat: true; onTriggered: {
    switch (root.stage++) {
    case 0:
      root.check(root.shortcut === "SUPER + A", "a missing file is not SUPER + A: " + root.shortcut)
      root.saveShortcut("SUPER + SHIFT + B"); break
    case 1:
      root.check(root.shortcut === "SUPER + SHIFT + B" && bindList.running, "the bindings were not read again")
      console.log("PASS"); Qt.quit()
    }
  } }
''', {"HOME": str(home)})
    assert (home / "reloads").read_text() == "SUPER + SHIFT + B\n", "the reload ran before the write landed"
    print("ok: saving reloads Hyprland once the key is written")

    # The backdrop saves on every step, faster than key repeat: shell.toml ends on the last step and
    # keeps what another writer put there first, and Hyprland reloads once the blur's turn is written.
    home = base / "backdrop-home"
    (home / ".config/omarchy").mkdir(parents=True)
    (home / ".config/omarchy/shell.toml").write_text("[font]\nbase-size = 12\n")
    run("backdrop-save", """
  property int backdropDraft: 50
  readonly property int backdrop: backdropDraft
  property int stage: 0
  property var steps: [60, 70, 80, 90, 100, 80, 60, 40, 20, 0]
  QtObject { id: bindList; property bool running: false }
  Process { id: edit; command: ["sh", "-c", "printf '[font]\\\\nbase-size = 16\\\\n' > $HOME/.config/omarchy/shell.toml"] }
""" + setting_file + line(wheel, r"^  SettingFile \{ id: blurFile.*$") + line(wheel, r"^  SettingFile \{ id: shellFile.*$")
        + reload.replace("wheel-shortcut", "wheel-blur") + "\n" + block(wheel, r"  function setBackdrop\(") + """
  Timer { id: burst; interval: 5; repeat: true; onTriggered: root.steps.length ? root.setBackdrop(root.steps.shift()) : stop() }
  Timer { interval: 150; running: true; repeat: true; onTriggered: {
    if (burst.running) return
    switch (root.stage++) {
    case 0: edit.running = true; break
    case 1: burst.start(); break
    case 2: console.log("PASS"); Qt.quit()
    }
  } }
""", {"HOME": str(home)})
    assert (home / ".config/omarchy/shell.toml").read_text() == "[font]\nbase-size = 16\n\n[menu]\nscrim-alpha = 0\n"
    assert (home / "reloads").read_text() == "off\n", "Hyprland reloaded other than after the blur's turn"
    print("ok: the backdrop saves every step, keeps another writer's edit, and reloads Hyprland once blur turns")

    # The ring editor saves on every key, faster than key repeat when Shift+arrow is held: a write
    # reloaded behind a newer one must never put an older ring back. The rest of wheel.json stays.
    run("ring-save", '''
  property var ringIds: "unset"
  property var savedFolders: "unset"
  property var savedSkipped: "unset"
  property int stage: 0
  Process { id: edit; property string text; command: ["sh", "-c", "printf %s \\"$1\\" > $HOME/.config/omarchy/wheel.json", "sh", text] }
  function check(ok, message) { if (!ok) { console.error("FAIL", message); Qt.exit(1) } }
''' + setting_file + block(wheel, r"  SettingFile \{\n    id: ringFile") + "\n" + block(wheel, r"  function saveRing\(") + '''
  Timer { id: burst; interval: 15; repeat: true; property int n: 0; onTriggered: {
    root.check(n === 0 || JSON.stringify(root.ringIds) === JSON.stringify(["omarchy.audio", "app:" + n]),
               "an older ring came back: " + JSON.stringify(root.ringIds))
    if (++n > 30) { stop(); return }
    root.saveRing(["omarchy.audio", "app:" + n])
  } }
  Timer { interval: 150; running: true; repeat: true; onTriggered: {
    if (burst.running) return
    switch (root.stage++) {
    case 0:
      root.check(root.ringIds === null, "a missing file is a ring: " + root.ringIds)
      burst.start(); break
    case 1:
      root.check(JSON.stringify(root.ringIds) === '["omarchy.audio","app:30"]', "the burst ended on " + JSON.stringify(root.ringIds))
      edit.text = '{ "slices": ["system"], "other": 1 }'; edit.running = true; break
    case 2:
      root.check(JSON.stringify(root.ringIds) === '["system"]', "an edit by hand was missed: " + JSON.stringify(root.ringIds))
      edit.text = '{ "folders": ["/x"], "skipped": [], "other": 1 }'; edit.running = true; break
    case 3:
      root.check(JSON.stringify([root.savedFolders, root.savedSkipped]) === '[["/x"],null]', "the lists were misread")
      root.saveRing(["system"]); break
    case 4:
      console.log("PASS"); Qt.quit()
    }
  } }
''', {"HOME": str(home)})
    assert json.loads((home / ".config/omarchy/wheel.json").read_text()) == {"folders": ["/x"], "skipped": [], "other": 1,
                                                                             "slices": ["system"]}
    print("ok: the ring saves on every change, a burst ends on its last ring, and the rest of wheel.json stays")
