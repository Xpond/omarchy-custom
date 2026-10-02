#!/usr/bin/env python3
"""GPU wind regression: rooted stems, in the lettering and on the near bank, bend together and
move by fractions of a pixel.
Run: python3 tests/meadow-render.py [/tmp/meadow-wind-render]
Requires Quickshell, qsb and ImageMagick. Uses synthetic stems, never locks.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

repo = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/meadow-wind-render").resolve()
times = [t + step for t in range(7) for step in (0, 1 / 144)]
design = out / "design"
shutil.copytree(repo / "lock/meadow", design, dirs_exist_ok=True)
# One straight, leafless plant makes displacement measurable independently of the garden
# layout; the later declaration replaces garden.js's own.
with open(design / "garden.js", "a") as garden:
    garden.write('''function garden(aspect) {
  return { plants: [{ x: 800, y: 270, root: 840, bend: 0, waves: 0, radius: 6, kind: 0, phase: 0, tilt: 1,
                      leaves: 0, start: 0, letter: true }] }
}
''')
# The near bank paints nothing and grows one such flower, low in its sharp clearing.
with open(design / "foreground.js", "a") as near:
    near.write('''function draw(c, width) {
  return [{ x: 560, y: 790, root: 880, bend: 0, waves: 0, radius: 6, kind: 0, phase: 0, tilt: 1,
            leaves: 0, start: 0, letter: false }]
}
''')
scene = (design / "Scene.qml").read_text()
grass = "    Plants { part: 0; count: root.garden ? 1200 : 0; rows: 7 }\n"
assert scene.count(grass) == 1
(design / "Scene.qml").write_text(scene.replace(grass, ""))
shader = (design / "meadow.frag").read_text()
assert shader.count("vec4(color,1.0) * qt_Opacity") == 1
assert shader.count("color = color * (1.0 - near.a) + near.rgb;") == 1
(design / "meadow.frag").write_text(shader.replace("vec4(color,1.0) * qt_Opacity", "vec4(vec3(plant.a),1.0)")
                                    .replace("color = color * (1.0 - near.a) + near.rgb;", "plant.a = max(plant.a,near.a);"))
subprocess.run(["/usr/lib/qt6/bin/qsb", "--glsl", "100 es,120,150", "--hlsl", "50", "--msl", "12",
                "-o", str(design / "meadow.frag.qsb"), str(design / "meadow.frag")], check=True)
(out / "shell.qml").write_text('''import QtQuick
import Quickshell
Window {
  width: 960; height: 540; visible: true
  Item { id: host; property bool blanked: false }
  property int stage: 0
  property int factor: 1
  property var times: TIMES
  Loader {
    id: scene; width: 1920 * factor; height: 1080 * factor
    Component.onCompleted: setSource("design/Scene.qml", {host: host, grown: 4})
    onLoaded: ready.start()
  }
  Timer { id: ready; interval: 30; repeat: true; onTriggered: {
    if (scene.item.drawn >= 3) { stop(); capture.restart() }
  } }
  Timer { id: capture; interval: 40; onTriggered: scene.item.grabToImage(function(r) {
    if (!r.saveToFile(OUTPUT + "/" + factor + "-" + stage + ".png")) { Qt.exit(1); return }
    stage++
    if (stage === times.length) {
      if (factor === 2) { Qt.quit(); return }
      stage = 0; factor = 2; scene.item.time = 0; ready.start()
    } else { scene.item.time = times[stage]; capture.restart() }
  }) }
}
'''.replace("OUTPUT", json.dumps(str(out))).replace("TIMES", json.dumps(times)))
env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic",
           QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", XDG_CACHE_HOME=str(out / "cache"))
result = subprocess.run(["quickshell", "--no-color", "-p", str(out / "shell.qml")],
                        env=env, capture_output=True, text=True, timeout=30)
(out / "render.log").write_text(result.stdout + result.stderr)
assert result.returncode == 0, result.stdout + result.stderr
assert not any(word in result.stdout + result.stderr for word in ["ERROR", "ReferenceError", "TypeError", "Failed to"])


def stem(scale, x, fractions):
    """Checks the stem in an 80-pixel column around x, from its root up, at every stage."""
    height = 1080 * scale
    centers = []
    for stage in range(len(times)):
        data = subprocess.check_output(["magick", out / f"{scale}-{stage}.png", "-crop",
            f"80x{height}+{x * scale - 40}+0", "+repage", "-colorspace", "gray", "-depth", "8", "gray:-"])
        positions = []
        for fraction in fractions:
            row = data[int(height * fraction) * 80:(int(height * fraction) + 1) * 80]
            assert sum(row) > 0, "wind broke the stem"
            positions.append(sum(i * v for i, v in enumerate(row)) / sum(row))
        centers.append(positions)
    roots = [frame[0] for frame in centers]
    assert max(roots) - min(roots) < .05, "wind moves the roots"
    for root, lower, middle, tip in centers:
        direction = 1 if tip >= root else -1
        assert -.05 <= direction * (lower - root) <= direction * (middle - root) + .05
        assert direction * (middle - root) <= direction * (tip - root) + .05, "stem bends back on itself"
    steps = [abs(centers[i + 1][3] - centers[i][3]) for i in range(0, len(times), 2)]
    assert .005 < max(steps) < .8, f"wind snaps between pixels: {max(steps):.3f}px step"
    return max(steps)


for scale in (1, 2):
    lettering, near = stem(scale, 960, (.82, .72, .55, .35)), stem(scale, 672, (.975, .95, .92, .89))
    print(f"ok: {1080 * scale}p roots stay fixed, stems bend together, largest wind step = {lettering:.3f}px "
          f"in the lettering, {near:.3f}px on the near bank")
