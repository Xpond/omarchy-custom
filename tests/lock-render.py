#!/usr/bin/env python3
"""GPU captures and material isolation checks. Opens a temporary preview, never a lock.

Run from the desktop: python3 tests/lock-render.py [/tmp/lock-render]
Requires Quickshell, ImageMagick and a working Wayland/OpenGL session.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from lock_pixels import check
from lock_parts import check_parts

repo = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/lock-render").resolve()
output.mkdir(parents=True, exist_ok=True)
# Standalone theme values, with the production host, car, shader, scenery and animations.
colors = {"background": "#080a0f", "lock.borderError": "#ff4444", "lock.text": "#ffffff",
          "lock.placeholder": "#929575", "lock.selection": "#445577", "lock.textError": "#ff4444"}
def standalone(source):
    source = source.replace("import qs.Commons", "")
    source = source.replace("Style.font.heading", "16").replace("Style.font.family", '"monospace"')
    return re.sub(r"Color\.(?:lock\.)?\w+", lambda m: json.dumps(colors[m[0][6:]]), source)
shutil.rmtree(output / "lock", ignore_errors=True)
shutil.copytree(repo / "lock", output / "lock")
for design in (output / "lock").glob("*/*.qml"):
    design.write_text(standalone(design.read_text()))
(output / "LockView.qml").write_text(standalone((repo / "patches/shell/plugins/lock/LockView.qml").read_text()))
def patch(name, *edits):
    source = (output / name).read_text()
    for old, new in edits:
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    (output / name).write_text(source)
patch("LockView.qml", ("  id: root", "  id: root\n  property alias testScene: scene.item"))
patch("lock/rally/Scene.qml", ("  property Item host", "  property Item host\n  property alias testCar: car"))
patch("lock/rally/Car.qml", ("  id: car", "  id: car\n  property bool testUnlit: false\n  property bool testSharp: false"))
patch("lock/rally/Paintwork.qml",
      ("property real amount: car.painted > 0 ? 1 : 0", "property real amount: !car.testUnlit && car.painted > 0 ? 1 : 0"),
      ("property real amount: car.painted\n", "property real amount: car.testSharp ? 0 : car.painted\n"))

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
# Last, since they unload the car: other designs at runtime, then one that is missing.
stages += [{"name": "design-tunnel", "design": "tunnel"}, {"name": "design-mycelium", "design": "mycelium"},
           {"name": "design-wallpaper", "design": "wallpaper"}, {"name": "design-missing", "design": "missing"}]
qml = '''import QtQuick
import Quickshell
Window {
  width: 960; height: 540; visible: true
  LockView { id: lock; width: 1920; height: 1080; loadBackground: false; inputEnabled: false
    designs: OUTPUT + "/lock/"; design: "rally"
  }
  readonly property var car: lock.testScene ? lock.testScene.testCar : null
  property var stages: STAGES
  property int stage: 0
  property var wingFills: null
  function prepare() {
    var s = stages[stage]
    if (s.design) {
      lock.design = s.design
      lock.backgroundPath = OUTPUT + "/lock/rally/neon-city.png"
      lock.loadBackground = true
      // The wallpaper loads asynchronously.
      capture.interval = 1500
      capture.restart()
      return
    }
    car.testUnlit = s.unlit || false
    car.testSharp = s.sharp || false
    lock.width = s.width || 1920; lock.height = s.height || 1080
    car.drive = s.drive || 0
    // The paint stage sits partway through the sweep, which follows the last outline landing.
    car.clock = s.paint !== undefined ? car.traced + s.paint * car.paintTime
      : s.clock || car.duration
    if (s.hideWing) {
      wingFills = car.fills
      car.fills = wingFills.map((paths, tone) => tone >= 62 && tone <= 71 ? [] : paths)
    }
    if (s.drive && s.drive < 0.9) {
      // Follow a point inside the sail panel through pitch, scale and translation.
      var p = car.fills[45][1]
      var q = car.mapToItem(lock, p[0].x * 0.2 + p[2].x * 0.35 + p[3].x * 0.45,
        p[0].y * 0.2 + p[2].y * 0.35 + p[3].y * 0.45)
      console.log("SAIL", s.name, Math.round(q.x), Math.round(q.y))
    }
    if (s.drive === 1) {
      var right = -Infinity
      car.parts.forEach(part => part.screen.forEach(p => { right = Math.max(right, p[0]) }))
      console.log("EXIT", car.mapToItem(lock, right, 0).x)
    }
    capture.restart()
  }
  // After every onCompleted, so the host has loaded its design.
  Component.onCompleted: Qt.callLater(prepare)
  Timer { id: capture; interval: 450; onTriggered: lock.grabToImage(function(result) {
    if (!result.saveToFile(OUTPUT + "/" + stages[stage].name + ".png")) {
      console.error("FAIL capture"); Qt.exit(1); return
    }
    if (wingFills) { car.fills = wingFills; wingFills = null }
    stage++
    if (stage === stages.length) { console.log("PASS captures"); Qt.quit() }
    else prepare()
  }) }
}
'''.replace("STAGES", json.dumps(stages)).replace("OUTPUT", json.dumps(str(output)))
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

def pixel(name, x, y):
    return subprocess.check_output(["magick", f"{output / name}.png[1x1+{x}+{y}]", "-depth", "8", "RGB:-"]).hex()
def lit(name, crop):
    return float(subprocess.check_output(["magick", output / f"{name}.png", "-crop", crop, "-colorspace", "gray",
                                          "-threshold", "25%", "-format", "%[fx:mean]", "info:"]))

# The field is the host's: it stays on every design, and when a design fails to load.
for name in ("parked", "design-tunnel", "design-mycelium", "design-wallpaper", "design-missing"):
    assert pixel(name, 960, 922) == "8fd0ff", name + ": the password field's edge is missing"
assert lit("design-tunnel", "1920x880+0+0") > 0.01, "switching to the tunnel design drew no lines"
# A second and a half in, the colony has grown about the centre, and no line shows beyond it, above
# the field's glow: only the dark ground, which never comes to a tenth of white.
assert lit("design-mycelium", "600x600+660+240") > 0.003, "switching to the mycelium design grew nothing"
beyond = subprocess.check_output(["magick", output / "design-mycelium.png", "-alpha", "off", "-fill", "black",
                                  "-draw", "rectangle 610,190 1310,890", "-draw", "rectangle 0,860 1920,1080",
                                  "-colorspace", "gray", "-threshold", "10%", "-format", "%[fx:mean*w*h]", "info:"])
assert float(beyond) == 0, "the mycelium shows lines its growth hasn't reached"
assert pixel("design-wallpaper", 960, 300) != "080a0f", "switching to the wallpaper design showed nothing"
assert pixel("design-missing", 960, 300) == "080a0f", "a missing design must leave the plain background"
print("ok: designs switch at runtime, and a missing one leaves the plain background and the field")
