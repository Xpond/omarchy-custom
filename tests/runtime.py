#!/usr/bin/env python3
"""Headless Quickshell regressions using the production process handlers."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from plugin_shell import check as check_plugin_shell
from wheel_refresh import check as check_wheel_refresh
import qslog

repo = Path(__file__).resolve().parents[1]
wheel = (repo / "plugins/xpo.wheel/Wheel.qml").read_text()
ops = (repo / "plugins/xpo.files/FilesOps.qml").read_text()
files = (repo / "plugins/xpo.files/Files.qml").read_text()


def block(source, pattern):
    return re.search(pattern + r".*?^  }", source, re.S | re.M).group()


def line(source, pattern):
    return re.search(pattern, source, re.M).group() + "\n"


with tempfile.TemporaryDirectory(prefix="omarchy-runtime-") as temporary:
    base = Path(temporary)
    for name, plugin in [("FilesIndex.js", "xpo.files"), ("MenuIndex.js", "xpo.wheel"), ("MenuKeys.js", "xpo.wheel")]:
        shutil.copyfile(repo / "plugins" / plugin / name, base / name)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
               QT_FORCE_STDERR_LOGGING="1", XDG_RUNTIME_DIR=str(base / "runtime"),
               XDG_CACHE_HOME=str(base / "cache"))

    def run(name, body, extra=None):
        qml = base / (name + ".qml")
        qml.write_text('''import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "FilesIndex.js" as FilesIndex
import "MenuIndex.js" as MenuIndex
import "MenuKeys.js" as MenuKeys
Scope {
  id: root
  Timer { interval: 3000; running: true; onTriggered: { console.error("FAIL timeout"); Qt.exit(1) } }
''' + body + "\n}\n")
        result = subprocess.run(["quickshell", "--no-color", "-p", str(qml)],
                                env=dict(env, **(extra or {})), capture_output=True,
                                text=True, timeout=6)
        log = result.stdout + result.stderr
        assert result.returncode == 0 and "PASS" in log, log
        qslog.check(log)
        print("ok:", name)
        return log

    check_plugin_shell(repo, base, run, block)
    check_wheel_refresh(wheel, run, block)

    # A wheel's scan state around the real walks, with `fd` swapped for scans that say which
    # epoch asked for them. Everything else -- the epoch, the guards, the join -- is production code.
    handlers = wheel[wheel.index("  property int scanEpoch:"):wheel.index(
        "  // Omarchy's menu re-checks its rows on every open")]

    def scan(seconds, folder_seconds="5", folders="[]"):
        out = """
  property bool opened: true
  property string mode: ""
  property string listing: ""
  property var files: null
  property var folders: """ + folders + """
  property real daylight: 0
  property string editing: ""
  function paths() { return root.files ? JSON.stringify(root.files.paths) : "null" }
""" + block(wheel, r"  component FileScan: Process \{") + "\n"
        for name, wait in [("home", seconds), ("folder", folder_seconds)]:
            command = ["sh", "-c", "sleep " + wait + '; printf "/epoch-%s/' + name + '\\n" "$1"', "scan"]
            out += "  FileScan { id: " + name + "Scan; command: " + json.dumps(command)[:-1] + ", String(epoch)] }\n"
        return out + handlers

    run("scan-close-reopen", scan("0.15") + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 30; running: true; onTriggered: {
    root.opened = false; root.opened = true; root.scanFiles()
  } }
  Timer { interval: 600; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-1/home"]') { console.error("FAIL stale scan", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")
    run("scan-close", scan("5") + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 30; running: true; onTriggered: root.opened = false }
  Timer { interval: 500; running: true; onTriggered: {
    if (root.files !== null || homeScan.running) { console.error("FAIL retained scan"); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # The skip list's suggestions are home's scanned folders, so showing it scans home as `/` does,
    # and leaves the added folders unscanned.
    run("scan-skip-list", scan("0.05", "0.05", '["/x"]') + """
  Component.onCompleted: root.listing = "skipped"
  Timer { interval: 400; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-0/home"]') { console.error("FAIL the skip list scanned", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # Subfolders are listed only while a path is typed into the folders list: a model with no
    # folder lists the working directory and watches it.
    run("subfolders-on-demand", """
  property string listing: ""
  property string query: ""
""" + block(wheel, r"  readonly property var subfolderPaths:") + "\n"
        + block(wheel, r"  Loader \{\n    id: subfolders") + """
  Timer { interval: 300; running: true; onTriggered: {
    if (subfolders.item || root.subfolderPaths.length) { console.error("FAIL listed", root.subfolderPaths); Qt.exit(1) }
    root.listing = "folders"; root.query = "/us"
  } }
  Timer { interval: 900; running: true; onTriggered: {
    if (root.subfolderPaths.indexOf("/usr") < 0) { console.error("FAIL /", root.subfolderPaths); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # Home answers without waiting for a slow added folder, which joins when it lands; a folder
    # that lands first waits for home rather than showing alone.
    for name, home_wait, folder_wait, early in [("scan-home-first", "0.05", "1", '["/epoch-0/home"]'),
                                                ("scan-folder-first", "0.6", "0.05", "null")]:
        run(name, scan(home_wait, folder_wait, '["/x"]') + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 400; running: true; onTriggered: {
    if (root.paths() !== '%s') { console.error("FAIL early", root.paths()); Qt.exit(1) }
  } }
  Timer { interval: 1600; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-0/home","/epoch-0/folder"]') { console.error("FAIL late", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""" % early)

    # A finished scan is the open's own: reopening scans again, and home's new paths never show
    # beside the last open's folder paths.
    run("scan-done-reopen", scan("0.05", "0.3", '["/x"]') + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 600; running: true; onTriggered: { root.opened = false; root.opened = true; root.scanFiles() } }
  Timer { interval: 800; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-1/home"]') { console.error("FAIL reopened", root.paths()); Qt.exit(1) }
  } }
  Timer { interval: 1400; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-1/home","/epoch-1/folder"]') { console.error("FAIL rescanned", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # The field and the query are one value both ways, and queryAt is the field's own
    # caret: typing edits from inside, Esc clears from outside, and Ctrl+W places the
    # caret after it assigns the query. The real lines are the fixture.
    run("query-field", '''
  property string query: ""
''' + line(wheel, r"^  property alias queryAt:.*$") + '''
  TextInput {
    id: searchInput
''' + line(wheel, r"^ +text: root\.query$") + line(wheel, r"^ +onTextChanged:.*$") + '''
  }
  Timer { interval: 1; running: true; onTriggered: {
    searchInput.insert(0, "firefox")
    if (root.query !== "firefox") { console.error("FAIL typing missed the query", root.query); Qt.exit(1); return }
    root.query = "fox"; root.queryAt = 1
    if (searchInput.text + "|" + searchInput.cursorPosition !== "fox|1") {
      console.error("FAIL the caret did not land", searchInput.text, searchInput.cursorPosition); Qt.exit(1); return
    }
    root.query = ""
    if (searchInput.text !== "" || root.queryAt !== 0) { console.error("FAIL caret left behind", root.queryAt); Qt.exit(1); return }
    searchInput.insert(0, "a"); root.query = "b"
    if (searchInput.text !== "b") { console.error("FAIL typing cut the field loose", searchInput.text); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')

    # History opens from its own search, so the query clears before the list shows; typing then
    # leaves history for search, while a folder list keeps its typing. The real handlers are the fixture.
    run("history-open", '''
  property string query: "history"
  property string listing: ""
  property int resultIndex: 3
  property int resultTop: 0
''' + block(wheel, r"  onQueryChanged: \{") + "\n" + block(wheel, r"  function edit\(") + '''
  Timer { interval: 1; running: true; onTriggered: {
    root.edit({ setting: "history" })
    if (root.listing + "|" + root.query !== "history|") {
      console.error("FAIL history did not open from its own search", root.listing, root.query); Qt.exit(1); return
    }
    root.query = "l"
    if (root.listing !== "") { console.error("FAIL typing stayed in history"); Qt.exit(1); return }
    root.query = ""; root.listing = "folders"; root.query = "/m"
    if (root.listing !== "folders") { console.error("FAIL typing left a folder list"); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')

    # A pick runs once the wheel has faded out and unmapped, and a second click during the fade
    # runs nothing. The backdrop goes as the fade starts. The real pick, close, fade and unmap are the fixture.
    run("launch-after-fade", '''
  property bool opened: true
  property bool shown: true
  property var queued: null
  property int fadeDuration: 130
  property var backdrop: []
  property QtObject shell: QtObject {
    function releasePopout(owner) {}
    function hide(id) {}
    function panelSurfaceVisible(shown) { root.backdrop.push(shown) }
  }
  property var slices: []
  property int launchedAt: -1
  property string editing: ""
  property real daylight: 0
  property var copied: []
  property int picks: 0
  function countUse(e) { root.picks++ }
  function copy(text) { root.copied.push(text) }
  function dropScan() {}
''' + "\n".join(block(wheel, pattern) for pattern in [r"  function run\(", r"  function close\(",
                                                      r"  Timer \{\n    id: unmap", r"  function dismiss\(",
                                                      r"  onOpenedChanged: \{"]) + '''
  Timer { interval: 1; running: true; onTriggered: { root.run({ copy: "first" }); root.run({ copy: "second" }) } }
  Timer { interval: 60; running: true; onTriggered: {
    if (root.copied.length || root.backdrop.join() !== "false") {
      console.error("FAIL ran before the wheel unmapped, or kept the backdrop", root.backdrop); Qt.exit(1)
    }
  } }
  Timer { interval: 400; running: true; onTriggered: {
    if (JSON.stringify(root.copied) + root.picks !== '["first"]1') {
      console.error("FAIL", JSON.stringify(root.copied), root.picks); Qt.exit(1)
    } else { console.log("PASS"); Qt.quit() }
  } }
''')

    # A check asked for while one runs has to run once that one ends, with the newer script, and
    # an answer that comes back unchanged must rebuild nothing.
    run("conditions-recheck", '''
  property var menuItems: ({ slow: { label: "Slow", action: "s", when: "sleep 0.3" } })
  property string conditionText: ""
  property int changes: 0
  property int settled: -1
  onConditionsChanged: root.changes++
''' + line(wheel, r"^  readonly property var conditions:.*$") + block(wheel, r"  Process {\n    id: conditionScan")
        + "\n" + block(wheel, r"  function checkConditions\(") + "\n" + line(wheel, r"^  onMenuItemsChanged:.*$") + '''
  Component.onCompleted: root.checkConditions()
  Timer { interval: 100; running: true; onTriggered:
    root.menuItems = MenuIndex.merge(root.menuItems, { quick: { label: "Quick", action: "q", when: "true" } }) }
  Timer { interval: 1200; running: true; onTriggered: {
    if (!root.conditions.when.quick) { console.error("FAIL the check asked mid-run was lost"); Qt.exit(1); return }
    root.settled = root.changes
    root.checkConditions()
  } }
  Timer { interval: 2200; running: true; onTriggered: {
    if (root.changes !== root.settled) { console.error("FAIL an unchanged answer rebuilt"); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
''')

    # Saving the user's menu shows at once, and an entry taken out of it is gone, not merged over.
    menus = base / "menus"
    menus.mkdir()
    (menus / "default.jsonc").write_text('{"system": {"label": "System"}, "system.lock": {"label": "Lock", "action": "l"}}')
    (menus / "user.jsonc").write_text('{"notes": {"label": "Notes", "action": "n"}}')
    default_menu = block(wheel, r'  FileView {\n    path: root\.omarchyPath \+ "/default/omarchy/omarchy-menu\.jsonc"')
    user_menu = block(wheel, r'  FileView {\n    path: Quickshell\.env\("HOME"\) \+ "/\.config/omarchy/extensions/omarchy-menu\.jsonc"')
    run("menu-reload", '''
  property var defaultMenu: ({})
  property var userMenu: ({})
  property string lockText: ""
''' + line(wheel, r"^  readonly property var menuItems:[^\n]*\n.*$")
        + default_menu.replace('root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"', json.dumps(str(menus / "default.jsonc")))
        + "\n" + user_menu.replace('Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"', json.dumps(str(menus / "user.jsonc"))) + '''
  FileView { id: editor; path: ''' + json.dumps(str(menus / "user.jsonc")) + '''; atomicWrites: true }
  Timer { interval: 400; running: true; onTriggered: {
    if (!root.menuItems.notes || !root.menuItems["system.lock"]) { console.error("FAIL menus did not load"); Qt.exit(1); return }
    editor.setText('{"todo": {"label": "Todo", "action": "t"}}')
  } }
  Timer { interval: 1400; running: true; onTriggered: {
    var ids = Object.keys(root.menuItems).sort().join(" ")
    if (ids !== "system system.lock todo") { console.error("FAIL", ids); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
''')

    for name, content, expected in [("empty", b"", True),
                                     ("latin1", b"caf\xe9\n", False),
                                     ("late-invalid", b"a" * 2048 + b"\xe9", False),
                                     ("unicode", "café हिन्दी 😀 �\n".encode(), True)]:
        target = base / name
        target.write_bytes(content)
        run("fileview-" + name, '''
  FileView {
    path: ''' + json.dumps(str(target)) + '''
    onLoaded: {
      if (FilesIndex.isUtf8(data()) !== ''' + str(expected).lower() + ''') {
        console.error("FAIL encoding"); Qt.exit(1)
      } else { console.log("PASS"); Qt.quit() }
    }
  }
''')

    # Emptying a file and saving it. `saving` has to tell the text it is
    # writing from having nothing to write, and "" is both.
    (base / "wipe.md").write_bytes(b"line one\nline two\n")
    run("save-emptied",
        '  property string target: ' + json.dumps(str(base / "wipe.md")) + '\n'
        + """
  property var ops: ({ fileNote: "" })
  property var preview: ({ editorText: "" })
  property bool editing: true
  property bool dirty: true
  property bool saveError: false
  property bool utf8: false
  property string fullText: ""
  property int flashes: 0
  Timer { id: savedFlash; interval: 1500; onRunningChanged: if (running) root.flashes++ }
  Timer { id: verifySave; interval: 150; onTriggered: previewFile.reload() }
"""
        + block(files, r"  property var saving:") + "\n"
        + block(files, r"  FileView {\n    id: previewFile").replace("root.previewPath", "root.target") + """
  Timer { interval: 200; running: true; onTriggered: root.save() }
  Timer { interval: 1200; running: true; onTriggered: {
    if (root.saving !== null) { console.error("FAIL save never settled"); Qt.exit(1) }
    else if (root.dirty) { console.error("FAIL still dirty after a clean save"); Qt.exit(1) }
    else if (root.flashes !== 1) { console.error("FAIL no saved confirmation", root.flashes); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")
    assert (base / "wipe.md").read_bytes() == b"", "the emptied file must actually be empty"

    # Replace the external clipboard owner, preserving the actual shell pipeline
    # and QML completion handler. Nothing touches the desktop clipboard.
    (base / "wl-copy").write_text('#!/bin/sh\ncat > "$CHECK_COPY"\nexit "$CHECK_COPY_EXIT"\n')
    (base / "wl-copy").chmod(0o755)
    captured = base / "clipboard"
    selected = "/home/test/a '$file with spaces.txt"
    clipboard = '''
  // FilesOps borrows the selection from its panel; here it is its own.
  property var panel: root
  property bool editing: false
  property string home: "/home/test"
  property var sel: ({path: ''' + json.dumps(selected) + '''})
  property var op: null
  property string fileNote: ""
  function note(text) { root.fileNote = text }
''' + block(ops, r"  function run\(") + block(ops, r"  function copyPath\(") + block(ops, r"  Process {\n    id: filer") + '''
  Component.onCompleted: {
    root.copyPath()
    if (root.fileNote) { console.error("FAIL premature success"); Qt.exit(1) }
  }
  onFileNoteChanged: {
    var failed = Quickshell.env("CHECK_COPY_EXIT") !== "0"
    if (failed ? root.fileNote !== "copy path failed" : root.fileNote.indexOf("copied ") !== 0) {
      console.error("FAIL completion", root.fileNote); Qt.exit(1)
    } else { console.log("PASS"); Qt.quit() }
  }
'''
    for code in [0, 127]:
        run("clipboard-" + str(code), clipboard,
            {"PATH": str(base) + ":" + os.environ["PATH"], "CHECK_COPY": str(captured),
             "CHECK_COPY_EXIT": str(code)})
        assert captured.read_text() == selected

    # Every star shares one gradient, so a tint change costs three stops, not three per star.
    shutil.copyfile(repo / "plugins/xpo.wheel/QuietPoints.qml", base / "QuietPoints.qml")
    run("stars-share-tint", '''
  Item {
    width: 1920; height: 1080
    QuietPoints {
      id: stars
      anchors.fill: parent
      progress: 0; quietRadius: 400; tint: "#7aa2f7"; daylight: 0; haze: 0
    }
  }
  Timer { interval: 50; running: true; onTriggered: {
    stars.tint = "#e0af68"
    var points = null, shared = null
    for (var c = 0; c < stars.children.length; c++)
      if (stars.children[c].itemAt) points = stars.children[c]
    for (var i = 0; i < points.count; i++) {
      var parts = points.itemAt(i).children
      for (var p = 0; p < parts.length; p++) {
        if (!parts[p].gradient) continue
        shared = shared || parts[p].gradient
        if (parts[p].gradient !== shared) { console.error("FAIL own gradient", i); Qt.exit(1); return }
      }
    }
    var want = [Qt.lighter(stars.tint, 1.6), stars.tint, Qt.darker(stars.tint, 1.6)]
    for (var s = 0; s < 3; s++)
      if (!Qt.colorEqual(shared.stops[s].color, want[s])) { console.error("FAIL stop", s); Qt.exit(1); return }
    if (points.count !== 228) { console.error("FAIL count", points.count); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')

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
    # must see the new key. An edit by hand is read back by the same rule as the Hyprland block.
    home = base / "home"
    (home / ".config/omarchy").mkdir(parents=True)
    reload = block(wheel, r"  Process \{\n    id: hyprReload")
    reload = re.sub(r"command: \[.*\]", 'command: ["sh", "-c", "cat $HOME/.config/omarchy/wheel-shortcut >> $HOME/reloads"]', reload)
    run("shortcut-save", '''
  property string shortcut: "unset"
  property int stage: 0
  QtObject { id: bindList; property bool running: false }
  Process { id: edit; property string text; command: ["sh", "-c", "printf %s \\"$1\\" > $HOME/.config/omarchy/wheel-shortcut", "sh", text] }
  function check(ok, message) { if (!ok) { console.error("FAIL", message); Qt.exit(1) } }
''' + block(wheel, r"  FileView \{\n    id: shortcutFile") + "\n" + reload + "\n" + block(wheel, r"  function saveShortcut\(") + '''
  Timer { interval: 150; running: true; repeat: true; onTriggered: {
    switch (root.stage++) {
    case 0:
      root.check(root.shortcut === "SUPER + A", "a missing file is not SUPER + A: " + root.shortcut)
      root.saveShortcut("SUPER + SHIFT + B"); break
    case 1:
      root.check(root.shortcut === "SUPER + SHIFT + B" && bindList.running, "the bindings were not read again")
      edit.text = "ALT + SPACE\\n"; edit.running = true; break
    case 2:
      root.check(root.shortcut === "ALT + SPACE", "an edit by hand was missed: " + root.shortcut)
      edit.text = "rm -rf /\\n"; edit.running = true; break
    case 3:
      root.check(root.shortcut === "SUPER + A", "a bad file was believed: " + root.shortcut)
      console.log("PASS"); Qt.quit()
    }
  } }
''', {"HOME": str(home)})
    assert (home / "reloads").read_text() == "SUPER + SHIFT + B\n", "the reload ran before the write landed"
    assert (home / ".config/omarchy/wheel-shortcut").read_text() == "rm -rf /\n"
    print("ok: saving reloads Hyprland once the key is written; edits by hand are read by the block's rule")

    # The backdrop saves on every step, faster than key repeat: shell.toml ends on the last step and
    # keeps what another writer put there first, and Hyprland reloads once the blur's turn is written.
    home = base / "backdrop-home"
    (home / ".config/omarchy").mkdir(parents=True)
    (home / ".config/omarchy/shell.toml").write_text("[font]\nbase-size = 12\n")
    run("backdrop-save", """
  property int backdropDraft: 50
  readonly property int backdrop: backdropDraft
  property string editValue: ""
  property int stage: 0
  property var steps: [60, 70, 80, 90, 100, 80, 60, 40, 20, 0]
  QtObject { id: bindList; property bool running: false }
  Process { id: edit; command: ["sh", "-c", "printf '[font]\\\\nbase-size = 16\\\\n' > $HOME/.config/omarchy/shell.toml"] }
""" + block(wheel, r"  FileView \{\n    id: shellFile") + "\n" + block(wheel, r"  FileView \{\n    id: blurFile") + "\n"
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
  property string listing: ""
  property int stage: 0
  function dropScan() {}
  function scanFiles() {}
  Process { id: edit; property string text; command: ["sh", "-c", "printf %s \\"$1\\" > $HOME/.config/omarchy/wheel.json", "sh", text] }
  function check(ok, message) { if (!ok) { console.error("FAIL", message); Qt.exit(1) } }
''' + block(wheel, r"  FileView \{\n    id: ringFile") + "\n" + block(wheel, r"  function saveRing\(") + "\n"
        + block(wheel, r"  function saveList\(") + '''
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
      root.saveRing(["system", "omarchy.audio"]); break
    case 3:
      root.saveRing([]); break
    case 4:
      root.check(root.ringIds === null, "an empty ring did not follow the bar")
      edit.text = '{ "folders": ["/x"], "skipped": [], "other": 1 }'; edit.running = true; break
    case 5:
      root.check(JSON.stringify([root.savedFolders, root.savedSkipped]) === '[["/x"],null]', "the lists were misread")
      root.listing = "skipped"; root.saveList(["~/Android"]); break
    case 6:
      root.listing = "folders"; root.saveList([]); break
    case 7:
      root.check(root.savedFolders === null, "an emptied list did not go back to its default")
      console.log("PASS"); Qt.quit()
    }
  } }
''', {"HOME": str(home)})
    assert json.loads((home / ".config/omarchy/wheel.json").read_text()) == {"other": 1, "skipped": ["~/Android"]}
    print("ok: the ring saves on every change, a burst ends on its last ring, and the rest of wheel.json stays")
