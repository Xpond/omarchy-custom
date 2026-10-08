#!/usr/bin/env python3
"""Exercise install/revert with temporary system paths and no desktop changes."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from desktop import verify
from install_fixture import Installer

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="omarchy-install-") as temporary:
    base = Path(temporary)
    fixture = Installer(source, base)
    conf = fixture.user / ".config/omarchy/shell.json"
    hook = fixture.user / ".config/omarchy/hooks/post-update.d/wheely"
    asset_dir = fixture.user / ".local/share/wheely"
    result = fixture.run()
    assert result.returncode == 0, result.stderr
    designs = asset_dir / "lock"
    assert designs.resolve() == fixture.repo / "lock"
    assert (asset_dir / "lock-session/shell.qml").resolve() == fixture.repo / "lock-session/shell.qml"
    assert (asset_dir / "lock-session/Bridge.qml").resolve() == fixture.repo / "lock-session/Bridge.qml"
    assert (asset_dir / "lock-session/Commons").readlink() == fixture.shell / "Commons"
    assert (asset_dir / "lock-session/Lock").readlink() == fixture.shell / "plugins/lock"
    verify(fixture.user, fixture.repo)
    expected = [{"id": "xpo.files"}, {"id": "xpo.wheel"}]
    assert json.loads(conf.read_text())["plugins"] == expected
    assert "plugins: xpo.files xpo.wheel" in result.stdout
    assert hook.exists()
    assert (fixture.user / ".config/omarchy/plugins/xpo.files").resolve() == fixture.repo / "plugins/xpo.files"
    print("ok: fresh install from a path containing spaces, quotes, and shell syntax")

    config = {"plugins": expected + [{"id": "other", "enabled": False}], "idle": {"lock": 30}}
    conf.write_text(json.dumps(config))
    assert fixture.run().returncode == 0
    assert json.loads(conf.read_text()) == config
    assert [p.name for p in hook.parent.iterdir()] == ["wheely"]
    # Execute the generated trampoline too, so quoting is checked by bash itself.
    result = subprocess.run([str(hook)], cwd=fixture.base, env=fixture.env, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert not (fixture.base / "injected").exists()
    print("ok: idempotent registration and generated hook execution")

    # An unrelated Quickshell instance must neither hide nor cause a render failure.
    for failure in ["render", "no-shell"]:
        result = fixture.run(failure=failure)
        assert result.returncode != 0, failure
        assert "threaded render loop" in result.stderr, result.stderr
    print("ok: render checks select the desktop shell and reject a missing render thread or shell")

    for failure in ["malformed", "mv", "hook"]:
        original = "{bad" if failure == "malformed" else json.dumps(config)
        conf.write_text(original)
        result = fixture.run(failure=failure)
        assert result.returncode != 0, failure
        assert conf.read_text() == original or failure == "hook", failure
        if failure != "hook":
            assert "plugins: xpo.files" not in result.stdout, failure
        assert not Path(str(conf) + ".new").exists(), failure
    print("ok: malformed JSON, failed mv, and hook failures return failure")

    conf.write_text(json.dumps(config))
    result = fixture.run("revert.sh")
    assert result.returncode == 0, result.stderr
    verify(fixture.user, fixture.repo, installed=False)
    assert not hook.exists()
    assert not (fixture.user / ".config/omarchy/plugins/xpo.files").is_symlink()
    assert json.loads(conf.read_text()) == {"plugins": [{"id": "other", "enabled": False}],
                                          "idle": {"lock": 30}}
    assert fixture.all_stock()
    assert not asset_dir.exists()
    assert fixture.run("revert.sh").returncode == 0
    print("ok: revert removes the hook and plugins, restores QML, and preserves other settings")

    # The state revert broke on: patches an older installer left without records, two of
    # them an older committed version of the patch.
    assert fixture.run().returncode == 0
    shutil.rmtree(fixture.user / ".local/state/wheely/installed")
    older = {}
    for relative in ["shell.qml", "services/PluginShellApi.qml"]:
        current = fixture.patched(relative)
        older[relative] = current + b"// older patch\n"
        (fixture.repo / "patches/shell" / relative).write_bytes(older[relative])
        fixture.git("commit", "-qam", "older patch")
        (fixture.repo / "patches/shell" / relative).write_bytes(current)
        fixture.git("commit", "-qam", "current patch")
        (fixture.shell / relative).write_bytes(older[relative])
    result = fixture.run("revert.sh")
    assert result.returncode == 0 and fixture.all_stock(), result.stdout + result.stderr
    print("ok: revert restores Omarchy's files from unrecorded and older versions of the patch")

    for relative, content in older.items():
        (fixture.shell / relative).write_bytes(content)
    result = fixture.run()
    assert result.returncode == 0 and "rebased" not in result.stdout, result.stdout + result.stderr
    assert all(fixture.installed(relative) == fixture.patched(relative) for relative in fixture.files)
    assert all((fixture.repo / "patches/orig" / relative).read_bytes() == fixture.stock[relative] for relative in fixture.files)
    assert fixture.run("revert.sh").returncode == 0 and fixture.all_stock()
    print("ok: an older committed patch is replaced on install and restored to stock on revert")

    relative = "shell.qml"
    update = fixture.stock[relative] + b"// upstream addition\n"
    assert fixture.run().returncode == 0
    fixture.publish({**fixture.stock, relative: update})
    (fixture.shell / relative).write_bytes(update)  # the package update replaced our patch
    result = fixture.run()
    assert result.returncode == 0 and "rebased onto new upstream: shell.qml" in result.stdout, result.stderr
    assert (fixture.repo / "patches/orig" / relative).read_bytes() == update
    assert fixture.installed(relative) != update and fixture.installed(relative).endswith(b"// upstream addition\n")
    assert fixture.run("revert.sh").returncode == 0 and fixture.installed(relative) == update
    fixture.publish(fixture.stock)
    for directory in ("orig", "shell"):
        (fixture.repo / "patches" / directory / relative).write_bytes((source / "patches" / directory / relative).read_bytes())
    (fixture.shell / relative).write_bytes(fixture.stock[relative])
    print("ok: a package update is rebased onto, and revert restores the updated stock file")

    relative = "plugins/bar/Bar.qml"
    edited = fixture.stock[relative] + b"// personal edit\n"
    (fixture.shell / relative).write_bytes(edited)
    result = fixture.run()
    assert result.returncode == 1 and fixture.installed(relative) == edited, result.stderr
    assert "changed outside" in result.stderr
    result = fixture.run("revert.sh")
    assert result.returncode == 1 and fixture.installed(relative) == edited and "changed outside" in result.stderr
    (fixture.shell / relative).write_bytes(fixture.stock[relative])
    assert fixture.all_stock()
    print("ok: files edited outside this project are neither patched over nor restored over")

    relative = "shell.qml"
    assert fixture.run(failure="partial").returncode == 1
    assert fixture.run("revert.sh").returncode == 0 and fixture.all_stock()
    assert fixture.run().returncode == 0 and fixture.installed(relative) == fixture.patched(relative)
    assert fixture.run("revert.sh", "partial").returncode == 1 and fixture.installed(relative) != fixture.stock[relative]
    assert designs.is_symlink(), "a failed revert must keep the lock screen's designs"
    assert fixture.run("revert.sh").returncode == 0 and fixture.all_stock()
    print("ok: interrupted installs and restores are recognised as ours and recover on retry")

    assert fixture.run().returncode == 0
    (fixture.repo / "patches/orig" / relative).write_bytes(b"a different repository baseline\n")
    assert fixture.run("revert.sh").returncode == 0 and fixture.all_stock()
    (fixture.repo / "patches/orig" / relative).write_bytes(fixture.stock[relative])
    assert fixture.run().returncode == 0
    (fixture.package / "local").rename(fixture.package / "hidden")
    result = fixture.run("revert.sh")
    assert result.returncode == 1 and "no package checksum" in result.stderr
    assert fixture.installed(relative) == fixture.patched(relative)
    (fixture.package / "hidden").rename(fixture.package / "local")
    assert fixture.run("revert.sh").returncode == 0 and fixture.all_stock()
    print("ok: stock comes from the cached package when needed, and is never guessed")
