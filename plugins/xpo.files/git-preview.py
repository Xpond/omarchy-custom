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
    prefix = subprocess.run(git + ["rev-parse", "--show-prefix"], capture_output=True)
    if prefix.returncode:
        sys.exit(0)
    under = "" if relative == "." else relative + "/"
    sys.stdout.buffer.write(prefix.stdout.removesuffix(b"\n") + os.fsencode(under) + b"\n")
    sys.stdout.flush()
    command = git + ["status", "--porcelain", "-z", "--no-renames", "--untracked-files=all", "--", relative]
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
