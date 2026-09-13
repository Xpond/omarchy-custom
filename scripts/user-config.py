#!/usr/bin/env python3
"""Install/remove a marked Lua block and the two helper links, preserving user edits."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
BEGIN = "-- BEGIN omarchy-custom\n"
END = "-- END omarchy-custom\n"
HELPERS = ("omarchy-open-path", "omarchy-wheel-close")


def write(path, text):
    path = path.resolve()  # preserve a user's config symlink
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".omarchy-custom-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def reload():
    subprocess.run(["hyprctl", "reload"], check=True, capture_output=True, text=True)
    result = subprocess.run(["hyprctl", "-j", "configerrors"], check=True, capture_output=True, text=True)
    errors = json.loads(result.stdout)
    if not isinstance(errors, list) or any(errors):
        raise ValueError(f"Hyprland configuration errors: {errors}")


def change_config(config, before, after):
    if before != after:
        write(config, after)
    try:
        reload()
    except (ValueError, subprocess.SubprocessError):
        if before != after:
            write(config, before)
        subprocess.run(["hyprctl", "reload"], capture_output=True)
        raise


def configure(mode, config, state, bindir):
    record = state / "user-config.json"
    if mode == "revert" and not record.exists():
        # An installer older than the record may still have linked helpers into this checkout.
        for name in HELPERS:
            link = bindir / name
            if link.is_symlink() and os.readlink(link) == str(REPO / "bin" / name):
                link.unlink()
        return
    text = config.read_bytes().decode()
    previous_record = record.read_text() if record.exists() else None
    saved = json.loads(previous_record) if previous_record else {
        "before": text, "blocks": [], "links": {}
    }
    block = next((b for b in saved["blocks"] if b in text), None)
    if BEGIN in text or END in text:
        if not block or text.count(BEGIN) != 1 or text.count(END) != 1:
            raise ValueError(f"Managed Lua block was edited; left untouched. Backup: {record}")

    # Check every helper before making any change. Existing links into this checkout are ours.
    previous_links = {}
    for name in HELPERS:
        if mode == "revert" and name not in saved["links"]:
            continue
        link = bindir / name
        target = str(REPO / "bin" / name)
        allowed = saved["links"].get(name, [target])
        previous_links[name] = os.readlink(link) if link.is_symlink() else None
        if link.is_symlink():
            if previous_links[name] not in allowed:
                raise ValueError(f"Helper link changed; left untouched: {link}")
        elif link.exists():
            raise ValueError(f"Existing helper left untouched: {link}")
        if mode == "install" and (name in saved["links"] or previous_links[name] in (None, target)):
            saved["links"][name] = list(dict.fromkeys(allowed + [target]))

    if mode == "install":
        new_block = "\n" + BEGIN + (REPO / "config/hyprland.lua").read_text() + END
        if new_block not in saved["blocks"]:
            saved["blocks"].append(new_block)
        # Journal both block/link versions before writes so interrupted updates can retry.
        write(record, json.dumps(saved, indent=2) + "\n")
        bindir.mkdir(parents=True, exist_ok=True)
        for name in saved["links"]:
            link = bindir / name
            target = str(REPO / "bin" / name)
            if link.is_symlink() and os.readlink(link) == target:
                continue
            link.unlink(missing_ok=True)
            link.symlink_to(target)
        updated = text.replace(block, new_block, 1) if block else text + new_block
        try:
            change_config(config, text, updated)
        except (ValueError, subprocess.SubprocessError):
            for name in saved["links"]:
                link = bindir / name
                link.unlink(missing_ok=True)
                if previous_links[name] is not None:
                    link.symlink_to(previous_links[name])
            if previous_record is None:
                record.unlink()
            else:
                write(record, previous_record)
            raise
        print("Installed wheel keys (SUPER+A, SUPER+W), shared blur, render loop, and helpers")
    else:
        change_config(config, text, text.replace(block, "", 1) if block else text)
        for name in saved["links"]:
            (bindir / name).unlink(missing_ok=True)
        record.unlink()
        print("Removed managed wheel configuration and helper links; personal edits preserved")


if __name__ == "__main__":
    try:
        mode, config, state, bindir = sys.argv[1:]
        if mode not in ("install", "revert"):
            raise ValueError("Expected install or revert")
        configure(mode, Path(config), Path(state), Path(bindir))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"omarchy-custom: {error}")
