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

repo = Path(__file__).resolve().parents[1]
wheel = (repo / "plugins/xpo.wheel/Wheel.qml").read_text()
ops = (repo / "plugins/xpo.files/FilesOps.qml").read_text()
files = (repo / "plugins/xpo.files/Files.qml").read_text()


def block(source, pattern):
    return re.search(pattern + r".*?^  }", source, re.S | re.M).group()


with tempfile.TemporaryDirectory(prefix="omarchy-runtime-") as temporary:
    base = Path(temporary)
    for name, plugin in [("FilesIndex.js", "xpo.files"), ("MenuIndex.js", "xpo.wheel")]:
        shutil.copyfile(repo / "plugins" / plugin / name, base / name)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
               QT_FORCE_STDERR_LOGGING="1", XDG_RUNTIME_DIR=str(base / "runtime"),
               XDG_CACHE_HOME=str(base / "cache"))

    def run(name, body, extra=None):
        qml = base / (name + ".qml")
        qml.write_text('''import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import "FilesIndex.js" as FilesIndex
import "MenuIndex.js" as MenuIndex
Scope {
  id: root
  Timer { interval: 3000; running: true; onTriggered: { console.error("FAIL timeout"); Qt.exit(1) } }
''' + body + "\n}\n")
        result = subprocess.run(["quickshell", "--no-color", "-p", str(qml)],
                                env=dict(env, **(extra or {})), capture_output=True,
                                text=True, timeout=6)
        log = result.stdout + result.stderr
        assert result.returncode == 0 and "PASS" in log, log
        assert not any(error in log for error in ["TypeError", "ReferenceError", "FAIL"]), log
        print("ok:", name)

    check_plugin_shell(repo, base, run, block)

    # The real walk, with `fd` swapped for a scan that says which epoch asked
    # for it. Everything below it -- the epoch, the guards -- is production code.
    def scan(seconds):
        p = block(wheel, r"  Process {\n    id: fileScan")
        command = ["sh", "-c", "sleep " + seconds + '; printf "/epoch-%s/file\\n" "$1"', "scan"]
        return (p[:p.index("    command:")] + "    command: " + json.dumps(command)[:-1]
                + ", String(epoch)]\n" + p[p.index("    property int epoch:"):])
    handlers = wheel[wheel.index("  property int scanEpoch:"):wheel.index(
        '  Process {\n    running: true\n    command: ["omarchy", "theme", "list"]')]
    run("scan-close-reopen", '''
  property bool opened: true
  property string mode: ""
  property var files: null
''' + scan("0.15") + handlers + '''
  Component.onCompleted: root.mode = "file"
  Timer { interval: 30; running: true; onTriggered: {
    root.opened = false; root.opened = true; root.scanFiles()
  } }
  Timer { interval: 600; running: true; onTriggered: {
    if (!root.files || root.files.paths[0] !== "/epoch-1/file") {
      console.error("FAIL stale scan", JSON.stringify(root.files)); Qt.exit(1)
    } else { console.log("PASS"); Qt.quit() }
  } }
''')
    run("scan-close", '''
  property bool opened: true
  property string mode: ""
  property var files: null
''' + scan("5") + handlers + '''
  Component.onCompleted: root.mode = "file"
  Timer { interval: 30; running: true; onTriggered: root.opened = false }
  Timer { interval: 500; running: true; onTriggered: {
    if (root.files !== null || fileScan.running) { console.error("FAIL retained scan"); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
''')

    # Clearing the query anywhere has to carry the caret home. Only the real
    # onQueryChanged can fire that, so the binding itself is the fixture.
    changed = block(wheel, r"  onQueryChanged: \{")
    run("query-caret", '''
  property string query: ""
  property int queryAt: 0
  property int resultIndex: 0
  property int resultTop: 0
''' + changed + '''
  Timer { interval: 1; running: true; onTriggered: {
    root.query = "firefox"; root.queryAt = 7
    root.query = ""
    if (root.queryAt !== 0) { console.error("FAIL caret left behind", root.queryAt); Qt.exit(1) }
    root.query = "abc"; root.queryAt = 3
    root.query = "a"
    if (root.queryAt !== 1) { console.error("FAIL caret past the end", root.queryAt); Qt.exit(1) }
    console.log("PASS"); Qt.quit()
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
        assert target.read_bytes() == content

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
