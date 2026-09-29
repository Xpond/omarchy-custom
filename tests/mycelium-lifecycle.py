#!/usr/bin/env python3
"""Check the production scene's animation clocks through blank, wake and unlock."""
import os
from pathlib import Path
import shutil
import re
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/mycelium-lifecycle").resolve()
shutil.copytree(repo / "lock/mycelium", out / "design", dirs_exist_ok=True)
wake = re.search(r"^  onBlankedChanged: (.+)$", (repo / "patches/shell/plugins/lock/LockView.qml").read_text(), re.M)[1]
(out / "shell.qml").write_text('''import QtQuick
import Quickshell
Window {
  width: 960; height: 540; visible: true
  Item {
    id: host
    property bool blanked: false
    property bool loadBackground: true
    property bool driving: false
    function tell(name) { scene.item[name]() }
    onBlankedChanged: WAKE
  }
  Loader {
    id: scene; anchors.fill: parent
    Component.onCompleted: setSource("design/Scene.qml", {host: host})
    onLoaded: item.play()
  }
  property int stage: 0
  property real savedTime: 0
  property real savedGrowth: 0
  property double started: Date.now()
  function check(ok, message) {
    if (!ok) { console.error("FAIL " + message); Qt.exit(1) }
    return ok
  }
  Timer {
    interval: 300; running: true; repeat: true
    onTriggered: {
      var s = scene.item
      if (!s || !s.colony || s.drawn < 4 || (stage === 0 && s.grown < 5)) {
        check(Date.now() - started < 10000, "colony did not start growing")
        return
      }
      if (stage === 0) host.blanked = true
      if (stage === 1 && !check(s.time === savedTime && s.grown === 0, "blank did not pause and reset the scene")) return
      if (stage === 1) host.blanked = false
      if (stage === 2 && !check(s.time > savedTime && s.grown > 0, "one wake did not resume growth and drift")) return
      if (stage === 2) s.leave()
      if (stage === 3 && !check(s.time > savedTime && s.grown < savedGrowth && s.opacity < 1, "unlock stopped drift or retraction")) return
      if (stage === 4 && !check(s.opacity === 0 && s.grown === 0, "unlock did not finish within 600ms")) return
      if (stage === 5) {
        if (check(s.time === savedTime, "invisible scene still animates")) {
          console.log("PASS blank, automatic wake, unlock and invisible idle")
          Qt.quit()
        }
        return
      }
      savedTime = s.time; savedGrowth = s.grown; stage++
    }
  }
}
'''.replace('WAKE', wake))
runtime = out / 'runtime'
runtime.mkdir(mode=0o700, exist_ok=True)
env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
           QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", XDG_CACHE_HOME=str(out / "cache"), XDG_RUNTIME_DIR=str(runtime))
result = subprocess.run(["quickshell", "--no-color", "-p", str(out / "shell.qml")],
                        env=env, capture_output=True, text=True, timeout=20)
log = result.stdout + result.stderr
(out / "render.log").write_text(log)
assert result.returncode == 0 and "PASS " in log, log
# IPC is unused here and may be unavailable inside a sandbox.
errors = "\n".join(line for line in log.splitlines() if "ERROR quickshell.ipc: Failed to start IPC server" not in line)
assert not any(word in errors for word in ["ERROR", "ReferenceError", "TypeError"]), log
print("ok: mycelium pauses on blank, replays on one wake, and finishes unlock")
