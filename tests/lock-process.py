#!/usr/bin/env python3
"""Offscreen lifecycle test: simulated compositor, stubbed display commands, no PAM authentication."""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lock-process-") as directory:
    out = Path(directory)
    home, runtime, stubs = out / "home", out / "runtime", out / "bin"
    data = home / ".local/share/wheely"
    worker = data / "lock-session"
    sources = out / "sources"
    shutil.copytree(repo / "lock-session", sources)
    worker.mkdir(parents=True)
    for name in ["Bridge.qml", "shell.qml"]:
        (worker / name).symlink_to(sources / name)
    shutil.copytree(repo / "lock", data / "lock")
    lock = out / "installed"
    shutil.copytree(repo / "patches/shell/plugins/lock", lock)
    (worker / "Lock").symlink_to(lock)
    (out / "Lock").symlink_to(lock)
    shutil.copytree("/usr/share/omarchy/shell/Commons", out / "installed-commons")
    (worker / "Commons").symlink_to(out / "installed-commons")
    (out / "Commons").symlink_to(worker / "Commons")
    runtime.mkdir(mode=0o700)
    stubs.mkdir()
    config = home / ".config/wheely"
    config.mkdir(parents=True)
    (config / "lock-design").write_text("mycelium\n")
    for name in ["omarchy-hyprland-session-locked", "fprintd-list", "omarchy-system-wake",
                 "omarchy-brightness-display", "omarchy-brightness-keyboard"]:
        # A wake leaves its file until it finishes, so one killed with its worker stays behind.
        command = 'touch "$HOME/wake.$$"; sleep 2; rm "$HOME/wake.$$"' if name == "omarchy-system-wake" else 'exit 1'
        path = stubs / name
        path.write_text("#!/bin/sh\n" + command + "\n")
        path.chmod(0o755)
    source = (lock / "Service.qml").read_text()
    source = source.replace("import QtQuick\n", "import QtQuick\nimport QtQuick.Window as QW\n")
    source = re.sub(r"  function realScreenCount\(\) \{.*?\n  }", "  function realScreenCount() { return 1 }", source, flags=re.S)
    source = source.replace("WlSessionLock {", "TestSessionLock {")
    source = source.replace("WlSessionLockSurface {", "Loader { active: sessionLock.locked; sourceComponent: QW.Window {\ntransientParent: null\nwidth: 1920; height: 1080; visible: true\nproperty bool firstFrame: true\nonFrameSwapped: if (firstFrame) { firstFrame = false; console.log('LOCK_FRAME', Date.now()) }")
    source = source.replace("  PanelWindow {", "  }\n  PanelWindow {")
    source = source.replace("PanelWindow {", "QW.Window {\ntransientParent: null\nwidth: 1920; height: 1080\nproperty int frames: 0\nonFrameSwapped: if (++frames === 30) console.log(\"RENDERED\")")
    source = re.sub(r"^    (anchors \{ top:.*|WlrLayershell\..*|exclusionMode:.*)\n", "", source, flags=re.M)
    # Only the offscreen test contains this synthetic authentication entry point.
    source = source.replace('target: "lock"', 'target: "lock"\nfunction authenticated(): string { root.driveOffThenUnlock(); return "ok" }')
    (lock / "Service.qml").write_text(source)
    (lock / "TestSessionLock.qml").write_text('''import QtQuick
Item {
 property bool locked: false
 property bool secure: locked
 signal lockStateChanged()
 signal secureStateChanged()
 onLockedChanged: lockStateChanged()
 onSecureChanged: secureStateChanged()
}''')
    (out / "shell.qml").write_text('''import QtQuick
import Quickshell
import "Lock" as Lock
ShellRoot { Lock.Service {} }
''')
    env = dict(os.environ, HOME=str(home), PATH=str(stubs) + ":/usr/bin",
               QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic", QT_QUICK_BACKEND="rhi",
               QSG_RHI_BACKEND="opengl", QSG_RENDER_LOOP="threaded", XDG_RUNTIME_DIR=str(runtime),
               XDG_CACHE_HOME=str(out / "cache"), QS_DISABLE_FILE_WATCHER="1")
    env.pop("OMARCHY_LOCK_SESSION", None)

    def ipc(action, child=False):
        result = subprocess.run(["quickshell", "ipc", "-p", str(worker if child else out),
                                 "call", "lock", action], env=env, capture_output=True, text=True, timeout=3)
        return result.stdout.strip() if result.returncode == 0 else ""

    def status():
        return json.loads(ipc("status") or "{}")

    def until(check, message, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = check()
            if value:
                return value
            time.sleep(0.05)
        logs = "\n".join(p.read_text() for p in runtime.glob("quickshell/by-id/*/log.log"))
        raise AssertionError(message + "\n" + logs)

    def child_pid():
        result = subprocess.run(["quickshell", "list", "-p", str(worker), "-j"],
                                env=env, capture_output=True, text=True, timeout=3)
        instances = json.loads(result.stdout) if result.stdout.lstrip().startswith("[") else []
        return instances[0]["pid"] if instances else None

    def rss(pid):
        return int(re.search(r"VmRSS:\s+(\d+)", Path(f"/proc/{pid}/status").read_text())[1]) / 1024

    def start():
        return subprocess.Popen(["quickshell", "--no-color", "-p", str(out)], env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    parent = start()
    try:
        until(lambda: status().get("passwordPam"), "bridge did not start")
        time.sleep(1)
        until(lambda: not child_pid(), "initial worker did not retire")
        baseline = rss(parent.pid)
        for cycle, design in enumerate(["mycelium", "rally", "mycelium"]):
            (config / "lock-design").write_text(design + "\n")
            assert ipc("preview") == "ok"
            pid = until(child_pid, "preview worker did not start")
            time.sleep(5)
            logs = "\n".join(p.read_text() for p in runtime.glob("quickshell/by-id/*/log.log"))
            assert logs.count("RENDERED") >= cycle + 1, ipc("status", child=True) + "\n" + ipc("status") + "\n" + logs
            print(f"loaded {design}: worker RSS {rss(pid):.1f} MiB", flush=True)
            assert ipc("hidePreview") == "ok"
            until(lambda: not child_pid(), "closed preview retained its worker")
            retained = rss(parent.pid) - baseline
            assert retained < 12, f"parent retained {retained:.1f} MiB after {design}"
            print(f"ok: {design} worker {pid} exits; parent RSS change {retained:.1f} MiB", flush=True)

        entry = worker / "shell.qml"
        original = entry.read_text()
        entry.write_text("invalid qml\n")
        assert ipc("lock") == "ok"
        until(lambda: not status().get("requested") and not child_pid(), "failed launch stayed pending")
        entry.write_text(original)
        requested_at = time.time() * 1000
        assert ipc("lock") == "ok"
        until(lambda: status().get("secure"), "lock never became secure")
        def first_frame():
            logs = "\n".join(p.read_text() for p in runtime.glob("quickshell/by-id/*/log.log"))
            return re.search(r"LOCK_FRAME (\d+)", logs)
        frame = until(first_frame, "lock surface never rendered")
        print(f"lock request to first frame: {int(frame[1]) - requested_at:.0f} ms", flush=True)
        pid = child_pid()
        parent.terminate()
        parent.wait(timeout=3)
        time.sleep(1)
        assert Path(f"/proc/{pid}").exists(), "shell exit killed the active lock"
        parent = start()
        until(lambda: status().get("secure"), "shell restart did not reconnect")
        assert child_pid() == pid, "shell restart replaced the active lock"
        parent.kill()
        parent.wait(timeout=3)
        time.sleep(1)
        parent = start()
        until(lambda: status().get("secure"), "shell crash did not reconnect")
        assert child_pid() == pid, "shell crash replaced the active lock"
        os.kill(pid, signal.SIGKILL)
        until(lambda: child_pid() and child_pid() != pid and status().get("secure"), "crashed lock did not recover")
        assert ipc("authenticated", child=True) == "ok"
        until(lambda: not status().get("locked"), "authenticated unlock did not release")
        until(lambda: not child_pid(), "unlock retained its worker")
        until(lambda: not list(home.glob("wake.*")), "worker exited before its wake command finished", timeout=3)
        print("ok: failed launch retries, shell restart/crash reconnects, worker crash recovers, unlock/wake retires", flush=True)
    finally:
        subprocess.run(["quickshell", "kill", "-p", str(worker)], env=env, capture_output=True)
        parent.terminate()
        parent.wait(timeout=3)
