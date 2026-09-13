#!/usr/bin/env python3
"""Managed desktop setup checks; no live Hyprland configuration is loaded."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from unittest.mock import patch


def prepare(source, repo, user, stubs):
    for directory in ("scripts", "config"):
        shutil.copytree(source / directory, repo / directory)
    config = user / ".config/hypr/hyprland.lua"
    config.parent.mkdir(parents=True)
    config.write_text('-- personal config\nrequire("default.hypr.omarchy")\n')
    hyprctl = stubs / "hyprctl"
    hyprctl.write_text('''#!/bin/bash
case "$*" in
  reload) exit 0 ;;
  "-j configerrors") echo '[""]' ;;
  *) exit 1 ;;
esac
''')
    hyprctl.chmod(0o755)


def verify(user, repo, installed=True):
    config = (user / ".config/hypr/hyprland.lua").read_text()
    assert ("-- BEGIN omarchy-custom\n" in config) == installed
    for name in ("omarchy-open-path", "omarchy-wheel-close"):
        link = user / ".local/bin" / name
        assert link.is_symlink() == installed
        if installed:
            assert link.resolve() == repo / "bin" / name


def check():
    source = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location("user_config", source / "scripts/user-config.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    reload_config = module.reload
    module.reload = lambda: None
    for errors in ([], [""], ["invalid config"], {}):
        response = subprocess.CompletedProcess([], 0, stdout=json.dumps(errors))
        with patch.object(module.subprocess, "run", return_value=response):
            try:
                reload_config()
                assert errors in ([], [""])
            except ValueError:
                assert errors not in ([], [""])
    print("ok: reload accepts clean Hyprland responses and rejects config errors")
    with tempfile.TemporaryDirectory(prefix="omarchy-desktop-") as temporary:
        root = Path(temporary)
        config, state, bindir = root / "hyprland.lua", root / "state", root / "bin"
        original = '-- café, personal bindings\r\no.bind("SUPER + W", "Mine", "my-command")'
        config.write_bytes(original.encode())
        config.chmod(0o640)

        def run(mode):
            module.configure(mode, config, state, bindir)

        for _ in range(2):
            run("install")
            installed = config.read_bytes()
            run("install")
            assert config.read_bytes() == installed
            assert config.stat().st_mode & 0o777 == 0o640
            assert config.read_text().count(module.BEGIN) == 1
            for name in module.HELPERS:
                assert (bindir / name).resolve() == source / "bin" / name
            extra = "\n-- personal edit after installation\n"
            config.write_bytes(installed + extra.encode())
            run("revert")
            assert config.read_bytes() == (original + extra).encode()
            assert not any(bindir.iterdir())
            assert not (state / "user-config.json").exists()
            run("revert")
            config.write_bytes(original.encode())
        print("ok: install/revert/reinstall preserves personal edits, bytes, and permissions")

        # A symlinked main config remains a symlink; helper links into this checkout are ours,
        # including one an older installer left without a record.
        target = root / "dotfile"
        config.rename(target)
        config.symlink_to(target)
        borrowed = bindir / "omarchy-open-path"
        borrowed.symlink_to(source / "bin/omarchy-open-path")
        run("install")
        run("revert")
        assert config.is_symlink() and target.read_bytes() == original.encode()
        assert not borrowed.is_symlink()
        borrowed.symlink_to(source / "bin/omarchy-open-path")
        run("revert")
        assert not borrowed.is_symlink()
        borrowed.write_text("personal helper")
        try:
            run("install")
            raise AssertionError("overwrote a personal helper")
        except ValueError:
            pass
        assert borrowed.read_text() == "personal helper" and target.read_bytes() == original.encode()
        borrowed.unlink()
        print("ok: existing helpers and symlinked user configurations are preserved")

        run("install")
        installed = config.read_bytes()
        config.write_bytes(installed.replace(b'"Wheel"', b'"My wheel"'))
        for mode in ("install", "revert"):
            try:
                run(mode)
                raise AssertionError("overwrote an edited managed block")
            except ValueError:
                pass
        assert json.loads((state / "user-config.json").read_text())["before"] == original
        config.write_bytes(installed)
        run("revert")
        print("ok: managed-block edits are reported and the original backup survives")

        write = module.write

        def interrupted(path, text):
            if path == config:
                raise OSError("simulated interruption")
            write(path, text)

        module.write = interrupted
        try:
            run("install")
        except OSError:
            pass
        finally:
            module.write = write
        assert config.read_bytes() == original.encode()
        run("install")
        run("revert")
        assert config.read_bytes() == original.encode()
        print("ok: journal permits recovery after an interrupted configuration install")

        updated_repo = root / "updated-repo"
        for directory in ("config", "bin"):
            shutil.copytree(source / directory, updated_repo / directory)
        template = updated_repo / "config/hyprland.lua"
        template.write_text(template.read_text() + "\n-- updated setup\n")
        for existing in (False, True):
            if existing:
                run("install")
            before = config.read_bytes()
            record = state / "user-config.json"
            old_record = record.read_bytes() if record.exists() else None
            with patch.object(module, "REPO", updated_repo), \
                 patch.object(module, "reload", side_effect=ValueError("invalid config")), \
                 patch.object(module.subprocess, "run"):
                for mode in (["install", "revert"] if existing else ["install"]):
                    try:
                        run(mode)
                        raise AssertionError("validation failure was ignored")
                    except ValueError:
                        pass
                    assert config.read_bytes() == before
                    assert (record.read_bytes() if record.exists() else None) == old_record
                    assert (bindir / "omarchy-wheel-close").is_symlink() == existing
                    if existing:
                        assert (bindir / "omarchy-wheel-close").resolve() == source / "bin/omarchy-wheel-close"
            if existing:
                run("revert")
        print("ok: failed reload validation rolls back fresh setup, updates, and removals")

    subprocess.run(["lua", str(source / "tests/desktop.lua"), str(source / "config/hyprland.lua")], check=True)
    print("ok: shipped Lua installs press/release bindings, render environment and shared blur rules")


if __name__ == "__main__":
    check()
