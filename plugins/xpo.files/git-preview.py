#!/usr/bin/env python3
"""Read Git state for real or deleted paths: a status sorted by folder, or a diff Git writes itself."""
import os
from pathlib import Path
import signal
import subprocess
import sys

mode, folder = sys.argv[1:3]
directory = Path(folder)
while not directory.is_dir() and directory != directory.parent:
    directory = directory.parent
relative = os.path.relpath(folder, directory)
git = ["git", "--no-optional-locks", "--literal-pathspecs", "-C", str(directory)]

if mode == "status":
    where = subprocess.run(git + ["rev-parse", "--show-toplevel", "--show-prefix"], capture_output=True)
    if where.returncode:
        sys.exit(0)
    top, prefix = where.stdout.split(b"\n")[:2]
    listed = prefix + os.fsencode("" if relative == "." else relative + "/")
    # git reports an untracked folder as one entry rather than walk it, however large. A path inside
    # the listed folder opens it, so its own entries are marked, but only beside the folder's name
    # without a trailing slash; from inside, "." would carry one, hence from the top.
    path = listed.removesuffix(b"/") or b"."
    # Stopped, this script stops git too: the exit runs the kill below.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    status = subprocess.Popen(git + ["-C", top, "status", "--porcelain", "-z", "--no-renames",
                                     "--untracked-files=normal", "--", path, path + b"/-"],
                              stdout=subprocess.PIPE)
    try:
        out = status.communicate()[0]
    finally:
        status.kill()
    if status.returncode:
        sys.exit(status.returncode)
    # Each change marks the listed folder's entry it lies under, and the entry under that, for the
    # folder's preview: git's letter on the change itself, a dot on a folder holding it.
    parts = {b"": {}}
    for entry in out.split(b"\0"):
        names, code = entry[3 + len(listed):].rstrip(b"/").split(b"/", 2), entry[:2]
        if not entry.startswith(listed, 3) or not names[0]:
            continue
        for depth in range(min(len(names), 2)):
            row = parts.setdefault(names[0] if depth else b"", {}).setdefault(names[depth], [b"", b"-"])
            deeper = len(names) > depth + 1
            row[0] = "●".encode() if deeper else code.strip()[:1]
            if b"D" in code:
                row[1] = b"d" if deeper else b"f"
    # A part per folder, the listed one's always, so a status in a repository is never empty. Each
    # opens with "/", which no name holds, and the folder's name, the listed one's empty; each entry
    # is its mark, then f or d if a deleted file or folder, else -, then its name.
    sys.stdout.buffer.write(b"".join(
        b"/" + name + b"\0" + b"\0".join(mark + gone + entry for entry, (mark, gone) in part.items())
        for name, part in parts.items()))
    sys.exit(0)
else:
    name = "./" + os.path.normpath(os.path.join(relative, sys.argv[3]))
    # HEAD:./ resolves from -C, including literal punctuation in the filename.
    tracked = subprocess.run(git + ["cat-file", "-e", "HEAD:" + name],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    command = git + ["diff", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames"]
    if tracked.returncode == 0:
        command += ["HEAD", "--", name]
    elif os.path.lexists(directory / name):
        # New files and unborn repositories have the same empty baseline.
        command += ["--no-index", "--", "/dev/null", name]
    else:
        sys.exit(0)

# Cancellation now reaches Git itself, including while it is emitting a large patch.
os.execvp(command[0], command)
