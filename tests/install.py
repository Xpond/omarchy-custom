#!/usr/bin/env python3
"""Exercise install/revert with temporary system paths and no desktop changes."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
from desktop import prepare, verify

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="omarchy-install-") as temporary:
    base = Path(temporary)
    repo = base / "repo with ' $(touch injected)"
    user = base / "user"
    shell = base / "shell"
    stubs = base / "stubs"
    stubs.mkdir()
    prepare(source, repo, user, stubs)
    shutil.copytree(source / "patches", repo / "patches")
    shutil.copytree(source / "patches/orig", shell)
    shutil.copytree(source / "bin", repo / "bin")
    for plugin in (source / "plugins").iterdir():
        (repo / "plugins" / plugin.name).mkdir(parents=True)
    for name in ["install.sh", "revert.sh"]:
        text = (source / name).read_text()
        text = text.replace("SHELL_DIR=/usr/share/omarchy/shell", "SHELL_DIR=" + shlex.quote(str(shell)))
        text = text.replace("~/", str(user) + "/")
        (repo / name).write_text(text)
        (repo / name).chmod(0o755)
    commands = {
        "sudo": '''if [[ "$*" == *shell.qml ]]; then
  [[ "${CHECK_FAIL:-}" == copy ]] && exit 1
  if [[ "${CHECK_FAIL:-}" == partial ]]; then head -c -4 "${@: -2:1}" > "${@: -1}"; exit 1; fi
fi
exec "$@"''',
        "notify-send": "exit 0",
        "pgrep": "echo 1",
        "grep": 'case "$*" in *QSGRenderThread*) exit 0;; esac\nexec /usr/bin/grep "$@"',
        "jq": '[ "${CHECK_FAIL:-}" = jq ] && exit 127\nexec /usr/bin/jq "$@"',
        "mv": '[ "${CHECK_FAIL:-}" = mv ] && exit 1\nexec /usr/bin/mv "$@"',
        "omarchy": '''if [[ "$1 $2" == "hook install" ]]; then
  [[ "${CHECK_FAIL:-}" == hook ]] && exit 1
  dest="$CHECK_USER/.config/omarchy/hooks/post-update.d"
  mkdir -p "$dest"
  cp "$4" "$dest/$(basename "$4")"
  chmod +x "$dest/$(basename "$4")"
fi
exit 0''',
    }
    for name, command in commands.items():
        script = stubs / name
        script.write_text("#!/bin/bash\n" + command + "\n")
        script.chmod(0o755)
    env = dict(os.environ, PATH=str(stubs) + ":" + os.environ["PATH"], CHECK_USER=str(user))
    conf = user / ".config/omarchy/shell.json"
    hook = user / ".config/omarchy/hooks/post-update.d/centered-panels"

    def run(script="install.sh", failure=""):
        return subprocess.run([str(repo / script)], cwd=base,
                              env=dict(env, CHECK_FAIL=failure),
                              text=True, capture_output=True, timeout=15)

    result = run()
    assert result.returncode == 0, result.stderr
    verify(user, repo)
    expected = [{"id": "xpo.files"}, {"id": "xpo.wheel"}]
    assert json.loads(conf.read_text())["plugins"] == expected
    assert "plugins: xpo.files xpo.wheel" in result.stdout
    assert hook.exists()
    assert not (base / "injected").exists()
    assert (user / ".config/omarchy/plugins/xpo.files").resolve() == repo / "plugins/xpo.files"
    print("ok: fresh install from a path containing spaces, quotes, and shell syntax")

    config = {"plugins": expected + [{"id": "other", "enabled": False}], "idle": {"lock": 30}}
    conf.write_text(json.dumps(config))
    assert run().returncode == 0
    assert json.loads(conf.read_text()) == config
    assert [p.name for p in hook.parent.iterdir()] == ["centered-panels"]
    # Execute the generated trampoline too, so quoting is checked by bash itself.
    result = subprocess.run([str(hook)], cwd=base, env=env, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert not (base / "injected").exists()
    print("ok: idempotent registration and generated hook execution")

    for failure in ["malformed", "jq", "mv", "hook"]:
        original = "{bad" if failure == "malformed" else json.dumps(config)
        conf.write_text(original)
        result = run(failure=failure)
        assert result.returncode != 0, failure
        assert conf.read_text() == original or failure == "hook", failure
        if failure != "hook":
            assert "plugins: xpo.files" not in result.stdout, failure
        assert not Path(str(conf) + ".new").exists(), failure
    print("ok: malformed JSON, failed jq/mv, and hook failures return failure")

    conf.write_text(json.dumps(config))
    result = run("revert.sh")
    assert result.returncode == 0, result.stderr
    verify(user, repo, installed=False)
    assert not hook.exists()
    assert not (user / ".config/omarchy/plugins/xpo.files").is_symlink()
    assert not (user / ".local/bin/omarchy-open-path").is_symlink()
    assert json.loads(conf.read_text()) == {"plugins": [{"id": "other", "enabled": False}],
                                          "idle": {"lock": 30}}
    for original in (repo / "patches/orig").rglob("*.qml"):
        assert (shell / original.relative_to(repo / "patches/orig")).read_bytes() == original.read_bytes()
    assert run("revert.sh").returncode == 0
    print("ok: revert removes the hook and plugins, restores QML, and preserves other settings")

    # An initial merge conflict never gave the installer ownership of this file.
    relative = Path("shell.qml")
    upstream = repo / "patches/orig" / relative
    patch = repo / "patches/shell" / relative
    installed = shell / relative
    upstream.write_text("upstream\n")
    patch.write_text("wheel\n")
    installed.write_text("existing customization\n")
    assert run().returncode == 1
    assert installed.read_text() == "existing customization\n"
    result = run("revert.sh")
    assert result.returncode == 0, result.stderr
    assert installed.read_text() == "existing customization\n"
    print("ok: revert preserves an initial merge conflict while restoring successful patches")

    state = user / ".local/state/omarchy-custom"
    saved = state / "orig" / relative
    written = state / "installed" / relative
    gap = "unchanged\n" * 8
    stock = "stock\n" + gap + "end\n"
    custom = "stock\n" + gap + "custom\n"
    upstream.write_text(stock)
    patch.write_text("wheel\n" + gap + "end\n")
    installed.write_text(custom)
    assert run().returncode == 0
    assert installed.read_text() == "wheel\n" + gap + "custom\n"
    assert saved.read_text() == custom
    assert run().returncode == 0
    patch.write_text(patch.read_text().replace("wheel", "updated wheel"))
    assert run().returncode == 0
    assert saved.read_text() == custom
    # Revert must be independent of this checkout's changing merge baseline.
    upstream.write_text("different repository baseline\n")
    assert run("revert.sh").returncode == 0
    assert installed.read_text() == custom
    print("ok: custom merges, repeated installs and patch updates preserve the machine backup")

    upstream.write_text(stock)
    patch.write_text("wheel\n" + gap + "end\n")
    installed.write_text(stock)
    assert run().returncode == 0
    installed.write_text(custom)  # simulate a package update replacing our patch
    assert run().returncode == 0
    assert saved.read_text() == custom
    installed.write_text(installed.read_text() + "later edit\n")
    edited = installed.read_bytes()
    result = run("revert.sh")
    assert result.returncode == 1 and "changed since installation" in result.stderr
    assert installed.read_bytes() == edited and saved.read_text() == custom
    installed.write_bytes(written.read_bytes())  # user resolves the reported conflict
    assert run("revert.sh", "copy").returncode == 1
    assert saved.exists() and written.exists()
    assert run("revert.sh", "partial").returncode == 1
    assert run().returncode == 1  # a partial restore also requires recovery first
    installed.write_bytes(written.read_bytes())
    assert run("revert.sh").returncode == 0
    assert installed.read_text() == custom
    print("ok: upstream replacement, later edits and failed restores retain recoverable backups")

    for failure in ["copy", "partial"]:
        upstream.write_text(stock)
        patch.write_text("wheel\n" + gap + "end\n")
        installed.write_text(stock)
        assert run(failure=failure).returncode == 1
        assert saved.read_text() == stock
        result = run("revert.sh")
        if failure == "partial":
            assert result.returncode == 1 and installed.read_text() == patch.read_text()[:-4]
            assert run().returncode == 1  # retry must not rebase onto a truncated patch
            assert saved.read_text() == stock
            installed.write_bytes(saved.read_bytes())
            assert run("revert.sh").returncode == 0
        else:
            assert result.returncode == 0 and installed.read_text() == stock
    print("ok: failed and partial copies preserve originals and report unresolved files")

    # A failed backup commit must prevent the privileged write entirely.
    assert run(failure="mv").returncode == 1
    assert installed.read_text() == stock
    assert not written.exists()
    assert run().returncode == 0
    assert run("revert.sh").returncode == 0
    assert installed.read_text() == stock
    print("ok: failed backup recording prevents patching and a later retry recovers")

    installed.write_bytes(patch.read_bytes())
    assert run().returncode == 0  # old installation without a saved original
    result = run("revert.sh")
    assert result.returncode == 1 and "no complete installation backup" in result.stderr
    assert installed.read_bytes() == patch.read_bytes()
    print("ok: untracked legacy patches are never replaced with a guessed original")
