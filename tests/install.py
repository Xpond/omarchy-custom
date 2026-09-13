#!/usr/bin/env python3
"""Exercise install/revert with temporary system paths and no desktop changes."""
import gzip
import hashlib
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
    package = base / "package"
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
    helper = repo / "scripts/shell-files.sh"
    helper.write_text(helper.read_text()
                      .replace("PACKAGE_LOCAL=/var/lib/pacman/local",
                               "PACKAGE_LOCAL=" + shlex.quote(str(package / "local")))
                      .replace("PACKAGE_CACHE=/var/cache/pacman/pkg",
                               "PACKAGE_CACHE=" + shlex.quote(str(package / "cache"))))
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

    # A pacman package: its mtree checksums say what stock is, and its cached archive holds it.
    def publish(files):
        root = package / "root"
        shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree(package / "cache", ignore_errors=True)
        (package / "cache").mkdir(parents=True)
        lines = ["#mtree"]
        for relative, data in files.items():
            path = root / "usr/share/omarchy/shell" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            lines.append(f"./usr/share/omarchy/shell/{relative} mode=644 "
                         f"sha256digest={hashlib.sha256(data).hexdigest()}")
        db = package / "local/omarchy-4.0.3-1"
        db.mkdir(parents=True, exist_ok=True)
        with gzip.open(db / "mtree", "wt") as stream:
            stream.write("\n".join(lines) + "\n")
        subprocess.run(["bsdtar", "-c", "--zstd", "-f", str(package / "cache/omarchy-4.0.3-1-x86_64.pkg.tar.zst"),
                        "-C", str(root), "usr"], check=True)

    def git(*args):
        subprocess.run(["git", "-C", str(repo), "-c", "user.name=test", "-c", "user.email=test@example.com",
                        *args], check=True, capture_output=True)

    stock = {p.relative_to(source / "patches/orig").as_posix(): p.read_bytes()
             for p in (source / "patches/orig").rglob("*.qml")}
    files = sorted(stock)
    publish(stock)
    git("init", "-q")
    git("add", "patches")
    git("commit", "-qm", "patches")

    def run(script="install.sh", failure=""):
        return subprocess.run([str(repo / script)], cwd=base,
                              env=dict(env, CHECK_FAIL=failure),
                              text=True, capture_output=True, timeout=15)

    def installed(relative):
        return (shell / relative).read_bytes()

    def patched(relative):
        return (repo / "patches/shell" / relative).read_bytes()

    def all_stock():
        return all(installed(relative) == stock[relative] for relative in files)

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
    assert all_stock()
    assert run("revert.sh").returncode == 0
    print("ok: revert removes the hook and plugins, restores QML, and preserves other settings")

    # The state revert broke on: patches an older installer left without records, two of
    # them an older committed version of the patch.
    assert run().returncode == 0
    shutil.rmtree(user / ".local/state/omarchy-custom/installed")
    older = {}
    for relative in ["shell.qml", "services/PluginShellApi.qml"]:
        current = patched(relative)
        older[relative] = current + b"// older patch\n"
        (repo / "patches/shell" / relative).write_bytes(older[relative])
        git("commit", "-qam", "older patch")
        (repo / "patches/shell" / relative).write_bytes(current)
        git("commit", "-qam", "current patch")
        (shell / relative).write_bytes(older[relative])
    result = run("revert.sh")
    assert result.returncode == 0 and all_stock(), result.stdout + result.stderr
    print("ok: revert restores Omarchy's files from unrecorded and older versions of the patch")

    for relative, content in older.items():
        (shell / relative).write_bytes(content)
    result = run()
    assert result.returncode == 0 and "rebased" not in result.stdout, result.stdout + result.stderr
    assert all(installed(relative) == patched(relative) for relative in files)
    assert all((repo / "patches/orig" / relative).read_bytes() == stock[relative] for relative in files)
    assert run("revert.sh").returncode == 0 and all_stock()
    print("ok: an older committed patch is replaced on install and restored to stock on revert")

    relative = "shell.qml"
    update = stock[relative] + b"// upstream addition\n"
    assert run().returncode == 0
    publish({**stock, relative: update})
    (shell / relative).write_bytes(update)  # the package update replaced our patch
    result = run()
    assert result.returncode == 0 and "rebased onto new upstream: shell.qml" in result.stdout, result.stderr
    assert (repo / "patches/orig" / relative).read_bytes() == update
    assert installed(relative) != update and installed(relative).endswith(b"// upstream addition\n")
    assert run("revert.sh").returncode == 0 and installed(relative) == update
    publish(stock)
    for directory in ("orig", "shell"):
        (repo / "patches" / directory / relative).write_bytes((source / "patches" / directory / relative).read_bytes())
    (shell / relative).write_bytes(stock[relative])
    print("ok: a package update is rebased onto, and revert restores the updated stock file")

    relative = "plugins/bar/Bar.qml"
    edited = stock[relative] + b"// personal edit\n"
    (shell / relative).write_bytes(edited)
    result = run()
    assert result.returncode == 1 and installed(relative) == edited, result.stderr
    assert "changed outside" in result.stderr
    result = run("revert.sh")
    assert result.returncode == 1 and installed(relative) == edited and "changed outside" in result.stderr
    (shell / relative).write_bytes(stock[relative])
    assert all_stock()
    print("ok: files edited outside this project are neither patched over nor restored over")

    relative = "shell.qml"
    assert run(failure="partial").returncode == 1
    assert run("revert.sh").returncode == 0 and all_stock()
    assert run(failure="copy").returncode == 1 and installed(relative) == stock[relative]
    assert run().returncode == 0 and installed(relative) == patched(relative)
    assert run("revert.sh", "copy").returncode == 1 and installed(relative) == patched(relative)
    assert run("revert.sh", "partial").returncode == 1 and installed(relative) != stock[relative]
    assert run("revert.sh").returncode == 0 and all_stock()
    print("ok: interrupted installs and restores are recognised as ours and recover on retry")

    assert run().returncode == 0
    (repo / "patches/orig" / relative).write_bytes(b"a different repository baseline\n")
    assert run("revert.sh").returncode == 0 and all_stock()
    (repo / "patches/orig" / relative).write_bytes(stock[relative])
    assert run().returncode == 0
    (package / "local").rename(package / "hidden")
    result = run("revert.sh")
    assert result.returncode == 1 and "no package checksum" in result.stderr
    assert installed(relative) == patched(relative)
    (package / "hidden").rename(package / "local")
    assert run("revert.sh").returncode == 0 and all_stock()
    print("ok: stock comes from the cached package when needed, and is never guessed")
