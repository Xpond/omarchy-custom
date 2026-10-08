#!/usr/bin/env python3
"""Headless Quickshell regressions using the production process handlers."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from plugin_shell import check as check_plugin_shell
from wheel_refresh import check as check_wheel_refresh
from wheel_scans import check as check_wheel_scans
from wheel_menu import check as check_wheel_menu
from file_runtime import check as check_file_runtime
from files_lifecycle import check as check_files_lifecycle
from wheel_settings import check as check_wheel_settings
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

    def run(name, body, extra=None, expected=()):
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
        qslog.check(log, *expected)
        print("ok:", name)
        return log

    check_plugin_shell(repo, base, run, block)
    check_wheel_refresh(wheel, run, block)

    check_wheel_scans(wheel, run, block)
    check_wheel_menu(wheel, base, run, block, line)
    check_file_runtime(files, ops, base, run, block)
    check_files_lifecycle(files, run, block, line)

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

    check_wheel_settings(wheel, base, env, run, block, line)
