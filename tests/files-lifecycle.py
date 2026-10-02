#!/usr/bin/env python3
"""Closed file panels must not restart previews when their directory changes."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
source = (repo / "plugins/xpo.files/Files.qml").read_text()
selection = re.search(r"^  onSelChanged: .*", source, re.M)[0]
opened = re.search(r"^  onOpenedChanged: \{.*?^  }", source, re.M | re.S)[0]
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
''' + ordering + "\n" + selection + "\n" + opened + "\n" + settle + '''
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
      console.log("PASS"); Qt.quit()
    }
  } }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
               XDG_RUNTIME_DIR=str(base / "runtime"), XDG_CACHE_HOME=str(base / "cache"))
    result = subprocess.run(["quickshell", "--no-color", "-p", str(base / "shell.qml")],
                            env=env, capture_output=True, text=True, timeout=5)
    log = result.stdout + result.stderr
    assert result.returncode == 0 and "PASS" in log and "FAIL" not in log, log
    assert not re.search(r"TypeError|ReferenceError|Cannot assign", log), log
    print("ok: hidden preview suppression, visible updates, reopen and pending close")
