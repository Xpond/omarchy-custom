#!/usr/bin/env python3
"""GPU regression for fine strand edges. Requires Quickshell, qsb and ImageMagick.

Run: python3 tests/mycelium-render.py [/tmp/mycelium-render]
Renders a throwaway colony through the production scene and shader, without locking.
"""
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/mycelium-render").resolve()
design = out / "design"
shutil.copytree(repo / "lock/mycelium", design, dirs_exist_ok=True)
scene = (design / "Scene.qml").read_text()
clock = "running: !root.host.blanked && (root.spreading || leaving.running)"
assert scene.count(clock) == 1, "cannot freeze the scene clock"
(design / "Scene.qml").write_text(scene.replace(clock, "running: false"))
# Inspect only line coverage, so ground texture and tip colour cannot disguise aliasing.
shader = (design / "mycelium.frag").read_text()
assert shader.count("vec4(mix(base, colour, line), 1.0)") == 1, "cannot isolate line coverage"
(design / "mycelium.frag").write_text(shader.replace("vec4(mix(base, colour, line), 1.0)", "vec4(vec3(line), 1.0)"))
subprocess.run(["/usr/lib/qt6/bin/qsb", "--glsl", "100 es,120,150", "--hlsl", "50", "--msl", "12",
                "-o", str(design / "mycelium.frag.qsb"), str(design / "mycelium.frag")], check=True)
# Three fine, constant-width strands at a shallow angle: the original triangular teeth are
# easiest to see here. Growth crosses the packed step's 255 -> 256 byte boundary.
(design / "grow.js").write_text('''.pragma library
function begin(aspect) { return function() { return grow(aspect) } }
function grow(aspect) {
  var strands = [], fronts = [];
  [2, 3, 4].forEach(function(bin, n) {
    var run = [];
    for (var i = 0; i <= 120; i++) {
      var x = -180 + i * 3, y = -180 + n * 65 + i * 0.42;
      if (i) {
        var front = fronts[200 + i] = fronts[200 + i] || [];
        (front[bin] = front[bin] || []).push(run[run.length-2], run[run.length-1], x, y);
      }
      run.push(x, y);
    }
    strands[bin] = [run];
  });
  return {strands: strands, fronts: fronts, light: {cols: 1, rows: 1, px: [0,0,0,255]}};
}
''')
(out / "shell.qml").write_text('''import QtQuick
import Quickshell
Window {
  width: 600; height: 540; visible: true
  property int stage: 0
  property var stages: [
    {name: "1080", scale: 1, grown: 1000}, {name: "4k", scale: 2, grown: 1000},
    {name: "before", scale: 1, grown: 255.25}, {name: "after", scale: 1, grown: 255.75}
  ]
  Item { id: host; property bool blanked: false }
  Loader {
    id: scene; width: 1920 * stages[stage].scale; height: 1080 * stages[stage].scale
    source: "design/Scene.qml"
    onLoaded: { item.host = host; prepare() }
  }
  function prepare() { scene.item.time = 4; scene.item.grown = stages[stage].grown; snap.restart() }
  Timer { id: snap; interval: 500; onTriggered: scene.item.grabToImage(function(r) {
    if (!r.saveToFile(OUTPUT + "/" + stages[stage].name + ".png")) { Qt.exit(1); return }
    if (stage === stages.length - 1) Qt.quit(); else { stage++; prepare() }
  }) }
}
'''.replace("OUTPUT", json.dumps(str(out))))
env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
           QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", XDG_CACHE_HOME=str(out / "cache"))
result = subprocess.run(["quickshell", "--no-color", "-p", str(out / "shell.qml")],
                        env=env, capture_output=True, text=True, timeout=20)
(out / "render.log").write_text(result.stdout + result.stderr)
assert result.returncode == 0, result.stdout + result.stderr
assert not any(word in result.stdout + result.stderr for word in ["ERROR", "ReferenceError", "TypeError"])

def pixels(name, crop):
    return subprocess.check_output(["magick", str(out / (name + ".png")), "-crop", crop,
                                    "+repage", "-colorspace", "gray", "-depth", "8", "gray:-"])

for name, scale in [("1080", 1), ("4k", 2)]:
    for strand in range(3):
        width = 260 * scale
        data = pixels(name, f"{width}x{60*scale}+{810*scale}+{(350+65*strand)*scale}")
        peaks = [max(data[x::width]) for x in range(width)]
        # A uniform strand should not develop regularly spaced bright teeth. The old bilinear
        # reconstruction fluctuates by 19% at 1080p; smooth reconstruction stays below 16%.
        variation = statistics.pstdev(peaks) / statistics.mean(peaks)
        assert min(peaks) > 0, f"{name}: broken strand {strand}"
        assert variation < 0.16, f"{name}: strand {strand} has {variation:.1%} brightness variation"
        print(f"{name}, strand {strand}: {variation:.1%} brightness variation")

before = pixels("before", "400x230+760+320")
after = pixels("after", "400x230+760+320")
gain = (sum(after) - sum(before)) / 255
assert 0 < gain < 15, f"growth jumps across the packed byte boundary: {gain} pixels"
assert max(pixels("after", "80x230+1030+320")) == 0, "growth reveals future segments"
print(f"ok: smooth strands at 1080p and 4K; continuous growth across step 256 ({gain:.2f} pixels)")
