#!/usr/bin/env python3
"""Exercise install/revert with temporary system paths and no desktop changes."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="omarchy-install-") as temporary:
    base = Path(temporary)
    repo = base / "repo with ' $(touch injected)"
    user = base / "user"
    shell = base / "shell"
    stubs = base / "stubs"
    stubs.mkdir()
    shutil.copytree(source / "patches", repo / "patches")
    shutil.copytree(source / "patches/shell", shell)
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
        "sudo": 'exec "$@"',
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
    assert not hook.exists()
    assert not (user / ".config/omarchy/plugins/xpo.files").is_symlink()
    assert not (user / ".local/bin/omarchy-open-path").is_symlink()
    assert json.loads(conf.read_text()) == {"plugins": [{"id": "other", "enabled": False}],
                                          "idle": {"lock": 30}}
    for original in (repo / "patches/orig").rglob("*.qml"):
        assert (shell / original.relative_to(repo / "patches/orig")).read_bytes() == original.read_bytes()
    assert run("revert.sh").returncode == 0
    print("ok: revert removes the hook and plugins, restores QML, and preserves other settings")
