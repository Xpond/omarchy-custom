#!/usr/bin/env python3
"""GPU captures: every design draws beside the password field, a missing one leaves the plain
background, and the car clears the frame on unlock. Opens a temporary preview, never a lock.

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

stages = [{"name": "parked"}, {"name": "departed", "drive": 1}]
# Last, since they unload the car: other designs at runtime, then one that is missing.
stages += [{"name": "design-tunnel", "design": "tunnel"}, {"name": "design-mycelium", "design": "mycelium"},
           {"name": "design-shore", "design": "shore"}, {"name": "design-meadow", "design": "meadow"},
           {"name": "design-wallpaper", "design": "wallpaper"},
           {"name": "design-missing", "design": "missing"}]
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
  property bool waitingForColony: false
  property double preparationStarted: 0
  function prepare() {
    var s = stages[stage]
    if (s.design) {
      waitingForColony = s.design === "mycelium"
      preparationStarted = Date.now()
      lock.design = s.design
      lock.backgroundPath = OUTPUT + "/lock/rally/neon-city.png"
      lock.loadBackground = true
      // The wallpaper loads asynchronously.
      capture.interval = waitingForColony ? 20 : s.design === "meadow" ? 4000 : 1500
      capture.restart()
      return
    }
    if (s.drive) {
      car.drive = s.drive
      // The body's shapes stay parked; its pose moves them.
      var right = -Infinity
      car.parts.forEach(part => part.screen.forEach(p => {
        right = Math.max(right, part.axle === undefined ? car.bodyPose.times(Qt.vector3d(p[0], p[1], 0)).x : p[0])
      }))
      console.log("EXIT", car.mapToItem(lock, right, 0).x)
    }
    capture.restart()
  }
  // After every onCompleted, so the host has loaded its design.
  Component.onCompleted: Qt.callLater(prepare)
  Timer { id: capture; interval: 450; onTriggered: {
    // Colony preparation is incremental; measure growth after its textures are ready.
    if (waitingForColony) {
      if (Date.now() - preparationStarted > 10000) { console.error("FAIL colony preparation"); Qt.exit(1); return }
      waitingForColony = !lock.testScene.colony || lock.testScene.drawn < 4
      capture.interval = waitingForColony ? 20 : 1500
      capture.restart()
      return
    }
    lock.grabToImage(function(result) {
      if (!result.saveToFile(OUTPUT + "/" + stages[stage].name + ".png")) {
        console.error("FAIL capture"); Qt.exit(1); return
      }
      stage++
      if (stage === stages.length) { console.log("PASS captures"); Qt.quit() }
      else prepare()
    })
  } }
}
'''.replace("STAGES", json.dumps(stages)).replace("OUTPUT", json.dumps(str(output)))
(output / "shell.qml").write_text(qml)
env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="generic",
           QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", XDG_CACHE_HOME=str(output / "cache"))
# File logs avoid inherited pipes.
with (output / "render.log").open("w") as log:
    result = subprocess.run(["timeout", "60s", "quickshell", "--no-color", "-p", str(output / "shell.qml")],
                            env=env, stdout=log, stderr=log, timeout=63)
log = (output / "render.log").read_text()
assert result.returncode == 0 and "PASS captures" in log, log
assert not re.search(r"ERROR|FATAL|ReferenceError|TypeError|Failed to|shader.*error", log, re.I), log
assert float(re.search(r"EXIT (-?[\d.]+)", log)[1]) < 0, "car remains visible when unlock completes"
print("ok: the car parks and drives out of frame without shader or QML errors:", output)

def pixel(name, x, y):
    return subprocess.check_output(["magick", f"{output / name}.png[1x1+{x}+{y}]", "-depth", "8", "RGB:-"]).hex()
def lit(name, crop):
    return float(subprocess.check_output(["magick", output / f"{name}.png", "-crop", crop, "-colorspace", "gray",
                                          "-threshold", "25%", "-format", "%[fx:mean]", "info:"]))

# The field is the host's: it stays on every design, and when a design fails to load.
for name in ("parked", "design-tunnel", "design-mycelium", "design-shore", "design-meadow", "design-wallpaper", "design-missing"):
    assert pixel(name, 960, 922) == "8fd0ff", name + ": the password field's edge is missing"
assert lit("design-tunnel", "1920x880+0+0") > 0.01, "switching to the tunnel design drew no lines"
# A second and a half after preparation, the colony has grown about the centre, with no line beyond it, above
# the field's glow: only the dark ground, which never comes to a tenth of white.
assert lit("design-mycelium", "600x600+660+240") > 0.003, "switching to the mycelium design grew nothing"
beyond = subprocess.check_output(["magick", output / "design-mycelium.png", "-alpha", "off", "-fill", "black",
                                  "-draw", "rectangle 610,190 1310,890", "-draw", "rectangle 0,860 1920,1080",
                                  "-colorspace", "gray", "-threshold", "10%", "-format", "%[fx:mean*w*h]", "info:"])
assert float(beyond) == 0, "the mycelium shows lines its growth hasn't reached"
# Whenever in the surf it opens, water fills the top edge and sand the bottom corner, beyond the
# highest run up.
sea, sand = bytes.fromhex(pixel("design-shore", 960, 10)), bytes.fromhex(pixel("design-shore", 200, 1040))
assert sea[2] > sea[0] + 5 and sand[0] > sand[2] + 40, f"switching to the shore design drew no beach: {sea.hex()} {sand.hex()}"
assert pixel("design-wallpaper", 960, 300) != "080a0f", "switching to the wallpaper design showed nothing"
assert lit("design-meadow", "1920x880+0+0") > 0.005, "switching to the meadow design grew no flowers"
assert pixel("design-missing", 960, 300) == "080a0f", "a missing design must leave the plain background"
print("ok: designs switch at runtime, and a missing one leaves the plain background and the field")
