#!/usr/bin/env python3
"""GPU captures and material isolation checks. Opens a temporary preview, never a lock.

Run from the desktop: python3 tests/lock-render.py [/tmp/lock-render]
Requires Quickshell, ImageMagick and a working Wayland/OpenGL session.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from lock_pixels import check
from lock_parts import check_parts

repo = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/lock-render").resolve()
output.mkdir(parents=True, exist_ok=True)
source = (repo / "patches/shell/plugins/lock/LockView.qml").read_text()
# Standalone theme values, with the production car, shader, scenery and animations.
source = source.replace("import qs.Commons", "")
source = source.replace("Style.font.heading", "16").replace("Style.font.family", '"monospace"')
colors = {"background": "#080a0f", "lock.borderError": "#ff4444", "lock.text": "#ffffff",
          "lock.placeholder": "#929575", "lock.selection": "#445577", "lock.textError": "#ff4444"}
source = re.sub(r"Color\.(?:lock\.)?\w+", lambda m: json.dumps(colors[m[0][6:]]), source)
source = source.replace("  id: root", "  id: root\n  property alias testCar: car\n"
                        "  property bool testUnlit: false\n  property bool testSharp: false", 1)
source = source.replace("property real amount: car.painted > 0 ? 1 : 0",
                        "property real amount: !root.testUnlit && car.painted > 0 ? 1 : 0")
source = source.replace("property real amount: car.painted\n", "property real amount: root.testSharp ? 0 : car.painted\n")
(output / "LockView.qml").write_text(source)

stages = [
    {"name": "unlit", "unlit": True},
    {"name": "parked"},
    {"name": "sharp", "sharp": True},
    {"name": "wingless", "hideWing": True},
    {"name": "trace-unlit", "clock": 1800, "unlit": True},
    {"name": "trace", "clock": 1800},
    {"name": "paint", "paint": 0.5},
    {"name": "pitch", "drive": 450 / 1100},
    {"name": "launch", "drive": 700 / 1100},
    {"name": "4k", "width": 3840, "height": 2160},
    {"name": "wingless-4k", "hideWing": True, "width": 3840, "height": 2160},
    {"name": "sharp-4k", "sharp": True, "width": 3840, "height": 2160},
    {"name": "pitch-4k", "drive": 450 / 1100, "width": 3840, "height": 2160},
    {"name": "launch-4k", "drive": 700 / 1100, "width": 3840, "height": 2160},
    {"name": "departed", "drive": 1},
]
stages += [{"name": f"drive-{t}", "drive": t / 1100} for t in [100, 200, 300, 350, 400, 475, 500, 600, 800]]
# Geometry probes read the unshaded pigment: the shader now darkens the cabin and lights the tyres.
stages += [{"name": "unlit-4k", "unlit": True, "width": 3840, "height": 2160}]
stages += [dict(s, name=s["name"] + "-unlit", unlit=True) for s in stages if 0 < s.get("drive", 0) < 0.9]
qml = '''import QtQuick
import Quickshell
Window {
  width: 960; height: 540; visible: true
  LockView { id: lock; width: 1920; height: 1080; loadBackground: false; inputEnabled: false
    paintShader: SHADER
    focusShader: FOCUS_SHADER
    sceneImage: SCENE
  }
  property var stages: STAGES
  property int stage: 0
  property var wingFills: null
  function prepare() {
    var s = stages[stage]
    lock.testUnlit = s.unlit || false
    lock.testSharp = s.sharp || false
    lock.width = s.width || 1920; lock.height = s.height || 1080
    lock.testCar.drive = s.drive || 0
    // The paint stage sits partway through the sweep, which follows the last outline landing.
    lock.testCar.clock = s.paint !== undefined ? lock.testCar.traced + s.paint * lock.testCar.paintTime
      : s.clock || lock.testCar.duration
    if (s.hideWing) {
      wingFills = lock.testCar.fills
      lock.testCar.fills = wingFills.map((paths, tone) => tone >= 62 && tone <= 71 ? [] : paths)
    }
    if (s.drive && s.drive < 0.9) {
      // Follow a point inside the sail panel through pitch, scale and translation.
      var p = lock.testCar.fills[45][1]
      var q = lock.testCar.mapToItem(lock, p[0].x * 0.2 + p[2].x * 0.35 + p[3].x * 0.45,
        p[0].y * 0.2 + p[2].y * 0.35 + p[3].y * 0.45)
      console.log("SAIL", s.name, Math.round(q.x), Math.round(q.y))
    }
    if (s.drive === 1) {
      var right = -Infinity
      lock.testCar.parts.forEach(part => part.screen.forEach(p => { right = Math.max(right, p[0]) }))
      console.log("EXIT", lock.testCar.mapToItem(lock, right, 0).x)
    }
    capture.restart()
  }
  Component.onCompleted: prepare()
  Timer { id: capture; interval: 450; onTriggered: lock.grabToImage(function(result) {
    if (!result.saveToFile(OUTPUT + "/" + stages[stage].name + ".png")) {
      console.error("FAIL capture"); Qt.exit(1); return
    }
    if (wingFills) { lock.testCar.fills = wingFills; wingFills = null }
    stage++
    if (stage === stages.length) { console.log("PASS captures"); Qt.quit() }
    else prepare()
  }) }
}
'''.replace("FOCUS_SHADER", json.dumps((repo / "shaders/car-focus.frag.qsb").as_uri()))
qml = qml.replace("SHADER", json.dumps((repo / "shaders/car-paint.frag.qsb").as_uri()))
qml = qml.replace("STAGES", json.dumps(stages)).replace("OUTPUT", json.dumps(str(output)))
qml = qml.replace("SCENE", json.dumps((repo / "assets/lock/neon-city.png").as_uri()))
(output / "shell.qml").write_text(qml)
env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="generic",
           QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", XDG_CACHE_HOME=str(output / "cache"))
# File-backed logs also avoid a crash handler keeping subprocess pipes open.
with (output / "render.log").open("w") as log:
    result = subprocess.run(["timeout", "150s", "quickshell", "--no-color", "-p", str(output / "shell.qml")],
                            env=env, stdout=log, stderr=log, timeout=153)
log = (output / "render.log").read_text()
assert result.returncode == 0 and "PASS captures" in log, log
assert not re.search(r"ERROR|FATAL|ReferenceError|TypeError|Failed to|shader.*error", log, re.I), log
assert float(re.search(r"EXIT (-?[\d.]+)", log)[1]) < 0, "car remains visible when unlock completes"

check_parts(output)
check(output, stages, log)
print("ok: captured paint sweep, drive-off and 4K without shader or QML errors:", output)
