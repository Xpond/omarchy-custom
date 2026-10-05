#!/usr/bin/env python3
"""Closed file panels must not restart previews when their directory changes,
and popping out into a window must keep the preview it had."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import qslog

repo = Path(__file__).resolve().parents[1]
source = (repo / "plugins/xpo.files/Files.qml").read_text()
selection = re.search(r"^  onSelChanged: .*", source, re.M)[0]
shown = re.search(r"^  readonly property bool shown: .*", source, re.M)[0]
lifecycle = re.search(r"^  onShownChanged: \{.*?^  }", source, re.M | re.S)[0]
pop_out = re.search(r"^  function popOut\(\) \{.*?^  }", source, re.M | re.S)[0]
settle = re.search(r"^  Timer \{\n    id: settle.*?^  }", source, re.M | re.S)[0]
ordering = "\n".join(re.findall(r"^  readonly property var (?:orderedEntries|rows): .*", source, re.M))
with tempfile.TemporaryDirectory(prefix="files-lifecycle-") as temporary:
    base = Path(temporary)
    shutil.copyfile(repo / "plugins/xpo.files/FilesIndex.js", base / "FilesIndex.js")
    (base / "shell.qml").write_text('''import QtQuick
import Quickshell
import "FilesIndex.js" as FilesIndex
Scope {
  id: root
  property bool opened: false
  property bool windowed: false
  property var shell: null
  property var sel: null
  property var settledSel: null
  property bool editing: false
  property bool dirty: false
  property bool discarding: false
  property string naming: ""
  property int stage: 0
  property var entries: []
  property string query: ""
  property string order: "name"
  QtObject { id: ops; property string doomed: "" }
  function check(ok, message) {
    if (!ok) { console.error("FAIL", message); Qt.exit(1) }
  }
''' + "\n".join([shown, ordering, selection, lifecycle, settle, pop_out]) + '''
  Component.onCompleted: {
    entries = [{ name: "zAlpha", size: 9, isDir: false },
               { name: "alpha", size: 2, isDir: false }]
    query = "alpha"
    check(rows[0].name === "alpha", "prefix ordering")
    order = "size"
    check(rows[0].name === "zAlpha", "order change did not rebuild sorting")
    entries = [{ name: "newAlpha", size: 3, isDir: false }]
    check(rows.length === 1 && rows[0].name === "newAlpha", "directory update left stale rows")
    query = "missing"
    check(rows.length === 0, "query change left stale rows")
    query = ""
    check(rows.length === 1, "clearing query lost full listing")
    sel = ({ path: "initial" })
  }
  Timer { interval: 120; running: true; repeat: true; onTriggered: {
    switch (root.stage++) {
    case 0:
      root.check(!root.settledSel, "initial closed selection started preview")
      root.opened = true; break
    case 1:
      root.check(root.settledSel === root.sel, "opening did not preview cached selection")
      root.sel = ({ path: "visible-change" }); break
    case 2:
      root.check(root.settledSel === root.sel, "visible selection did not settle")
      root.opened = false
      root.sel = ({ path: "hidden-change" }); break
    case 3:
      root.check(!root.settledSel, "hidden directory update restarted preview")
      root.opened = true; break
    case 4:
      root.check(root.settledSel === root.sel, "reopen did not preview updated selection")
      root.sel = ({ path: "pending" }); root.opened = false; break
    case 5:
      root.check(!root.settledSel, "close did not cancel pending preview")
      root.opened = true; break
    case 6:
      root.popOut()
      root.check(root.settledSel === root.sel, "popping out dropped the preview")
      root.sel = ({ path: "windowed-change" }); break
    case 7:
      root.check(root.settledSel === root.sel, "windowed selection did not settle")
      root.sel = ({ path: "closing" }); root.windowed = false; break
    case 8:
      root.check(!root.settledSel, "closing the window did not cancel pending preview")
      console.log("PASS"); Qt.quit()
    }
  } }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
               XDG_RUNTIME_DIR=str(base / "runtime"), XDG_CACHE_HOME=str(base / "cache"))
    result = subprocess.run(["quickshell", "--no-color", "-p", str(base / "shell.qml")],
                            env=env, capture_output=True, text=True, timeout=5)
    log = result.stdout + result.stderr
    assert result.returncode == 0 and "PASS" in log, log
    qslog.check(log)
    print("ok: hidden preview suppression, visible updates, reopen, pending close and the window")
