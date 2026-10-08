"""Temporary installer tree, fake system commands and package state."""
import gzip
import hashlib
import os
import shlex
import shutil
import subprocess
from desktop import prepare


class Installer:
    def __init__(self, source, base):
        self.base = base
        self.repo = self.base / "repo with ' $(touch injected)"
        self.user = self.base / "user"
        self.shell = self.base / "shell"
        self.stubs = self.base / "stubs"
        self.package = self.base / "package"
        self.stubs.mkdir()
        prepare(source, self.repo, self.user, self.stubs)
        shutil.copytree(source / "patches", self.repo / "patches")
        shutil.copytree(source / "patches/orig", self.shell)
        shutil.copytree(source / "bin", self.repo / "bin")
        (self.repo / "lock").mkdir()
        shutil.copytree(source / "lock-session", self.repo / "lock-session")
        for plugin in (source / "plugins").iterdir():
            (self.repo / "plugins" / plugin.name).mkdir(parents=True)
        for name in ["install.sh", "revert.sh"]:
            text = (source / name).read_text()
            text = text.replace("SHELL_DIR=/usr/share/omarchy/shell", "SHELL_DIR=" + shlex.quote(str(self.shell)))
            text = text.replace("~/", str(self.user) + "/")
            (self.repo / name).write_text(text)
            (self.repo / name).chmod(0o755)
        helper = self.repo / "scripts/shell-files.sh"
        helper.write_text(helper.read_text()
                          .replace("PACKAGE_LOCAL=/var/lib/pacman/local",
                                   "PACKAGE_LOCAL=" + shlex.quote(str(self.package / "local")))
                          .replace("PACKAGE_CACHE=/var/cache/pacman/pkg",
                                   "PACKAGE_CACHE=" + shlex.quote(str(self.package / "cache"))))
        commands = {
            "sudo": '''if [[ "$*" == *shell.qml ]]; then
  if [[ "${CHECK_FAIL:-}" == partial ]]; then head -c -4 "${@: -2:1}" > "${@: -1}"; exit 1; fi
fi
exec "$@"''',
            "notify-send": "exit 0",
            # install.sh finds the shell with quickshell, never pgrep. A fallback to pgrep would find
            # this PID, so "no-shell" catches it even on a host where no Quickshell runs.
            "pgrep": "echo 1",
            "quickshell": '''[[ "$*" == "list -j -p $CHECK_SHELL" ]] || exit 1
[[ "${CHECK_FAIL:-}" == no-shell ]] && { echo '[]'; exit 0; }
echo '[{"pid": 424242}]' ''',
            "grep": '''case "$*" in
  *QSGRenderThread*)
    if [[ "$*" == *"/proc/424242/task/"* ]]; then
      [[ "${CHECK_FAIL:-}" != render ]]
    else
      [[ "${CHECK_FAIL:-}" == render || "${CHECK_FAIL:-}" == no-shell ]]
    fi ;;
  *) exec /usr/bin/grep "$@" ;;
esac''',
            "sleep": "exit 0",
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
            script = self.stubs / name
            script.write_text("#!/bin/bash\n" + command + "\n")
            script.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.stubs) + ":" + os.environ["PATH"],
                        CHECK_USER=str(self.user), CHECK_SHELL=str(self.shell))

        self.stock = {p.relative_to(source / "patches/orig").as_posix(): p.read_bytes()
                      for p in (source / "patches/orig").rglob("*.qml")}
        self.files = sorted(self.stock)
        self.publish(self.stock)
        self.git("init", "-q")
        self.git("add", "patches")
        self.git("commit", "-qm", "patches")

    # A pacman package: its mtree checksums say what stock is, and its cached archive holds it.
    def publish(self, files):
        root = self.package / "root"
        shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree(self.package / "cache", ignore_errors=True)
        (self.package / "cache").mkdir(parents=True)
        lines = ["#mtree"]
        for relative, data in files.items():
            path = root / "usr/share/omarchy/shell" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            lines.append(f"./usr/share/omarchy/shell/{relative} mode=644 "
                         f"sha256digest={hashlib.sha256(data).hexdigest()}")
        db = self.package / "local/omarchy-4.0.3-1"
        db.mkdir(parents=True, exist_ok=True)
        with gzip.open(db / "mtree", "wt") as stream:
            stream.write("\n".join(lines) + "\n")
        subprocess.run(["bsdtar", "-c", "--zstd", "-f", str(self.package / "cache/omarchy-4.0.3-1-x86_64.pkg.tar.zst"),
                        "-C", str(root), "usr"], check=True)

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=test", "-c", "user.email=test@example.com",
                        *args], check=True, capture_output=True)

    def run(self, script="install.sh", failure=""):
        return subprocess.run([str(self.repo / script)], cwd=self.base,
                              env=dict(self.env, CHECK_FAIL=failure),
                              text=True, capture_output=True, timeout=15)

    def installed(self, relative):
        return (self.shell / relative).read_bytes()

    def patched(self, relative):
        return (self.repo / "patches/shell" / relative).read_bytes()

    def all_stock(self):
        return all(self.installed(relative) == self.stock[relative] for relative in self.files)
