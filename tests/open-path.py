#!/usr/bin/env python3
"""Where omarchy-open-path sends a file, with the desktop's handlers and launchers stubbed."""
import os
from pathlib import Path
import subprocess
import tempfile
import time

script = Path(__file__).resolve().parents[1] / "bin/omarchy-open-path"
TERM, GUI = "open-path-test-term.desktop", "open-path-test-gui.desktop"
# name, content, mime type, its default application, exit code, what launches
cases = [
    ("my notes.md", b"# title\n", "text/plain", TERM, 0, "editor"),
    ("data.json", b'{"a": 1}\n', "application/json", "", 0, "editor"),
    ("page.html", b"<p>hi</p>\n", "text/html", GUI, 0, "viewer"),
    ("song.ogg", b"OggS\x00\x02\x00\x00", "audio/ogg", TERM, 3, None),
    ("blob.bin", b"\x00\x01\x02\x03", "application/octet-stream", "", 4, None),
    # A new file has nothing in it yet but is still written in the editor.
    ("empty.txt", b"", "text/plain", TERM, 0, "editor"),
    ("blank.txt", b"\n\n", "text/plain", TERM, 0, "editor"),
]

with tempfile.TemporaryDirectory(prefix="open-path-") as temporary:
    base = Path(temporary)
    home, stubs, files = base / "home", base / "bin", base / "files"
    for d in (home / ".local/share/applications", stubs, files):
        d.mkdir(parents=True)
    (home / ".local/share/applications" / TERM).write_text("[Desktop Entry]\nTerminal=true\n")
    (home / ".local/share/applications" / GUI).write_text("[Desktop Entry]\nTerminal=false\n")
    table = base / "mime.tsv"
    table.write_text("".join(f"filetype\t{n}\t{t}\ndefault\t{t}\t{d}\n" for n, _, t, d, _, _ in cases))
    stub = {
        "xdg-mime": '#!/bin/bash\nkey=$3; [[ $2 == filetype ]] && key=${3##*/}\n'
                    'awk -F "\\t" -v k="$2" -v v="$key" \'$1 == k && $2 == v { print $3; exit }\' "$MIME_TABLE"\n',
        "xdg-open": '#!/bin/sh\nprintf "viewer %s\\n" "$1" >> "$LAUNCHED"\n',
        "omarchy-launch-editor": '#!/bin/sh\nprintf "editor %s\\n" "$1" >> "$LAUNCHED"\n',
    }
    for name, body in stub.items():
        (stubs / name).write_text(body)
        (stubs / name).chmod(0o755)

    for name, content, _, _, code, opener in cases:
        path, launched = files / name, base / (name + ".launched")
        path.write_bytes(content)
        env = dict(os.environ, HOME=str(home), PATH=f"{stubs}:{os.environ['PATH']}",
                   MIME_TABLE=str(table), LAUNCHED=str(launched))
        result = subprocess.run([str(script), str(path)], env=env, timeout=10)
        assert result.returncode == code, (name, result.returncode)
        # Launches are detached; give one time to land, and one that should not, time to show.
        deadline = time.time() + (2 if opener else 0.3)
        while time.time() < deadline and not launched.exists():
            time.sleep(0.02)
        got = launched.read_text() if launched.exists() else ""
        assert got == (f"{opener} {path}\n" if opener else ""), (name, got)
print(f"ok: {len(cases)} files open in their viewer, text without one in the editor, and the rest decline")
