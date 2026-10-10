#!/usr/bin/env python3
"""Read Git state for real or deleted paths, then hand the process over to Git."""
import os
from pathlib import Path
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
    sys.stdout.buffer.write(listed + b"\n")
    sys.stdout.flush()
    # git reports an untracked folder as one entry rather than walk it, however large. A path inside
    # the listed folder opens it, so its own entries are marked, but only beside the folder's name
    # without a trailing slash; from inside, "." would carry one, hence from the top.
    path = listed.removesuffix(b"/") or b"."
    command = git + ["-C", top, "status", "--porcelain", "-z", "--no-renames",
                     "--untracked-files=normal", "--", path, path + b"/-"]
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
