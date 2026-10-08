"""Actual FileView decoding and file-operation process completion."""
import json
import os
from file_edits import check as check_file_edits


def check(files, ops, base, run, block):
    for name, content, expected in [("empty", b"", True),
                                     ("latin1", b"caf\xe9\n", False),
                                     ("late-invalid", b"a" * 2048 + b"\xe9", False),
                                     ("unicode", "café हिन्दी 😀 �\n".encode(), True)]:
        target = base / name
        target.write_bytes(content)
        run("fileview-" + name, '''
  FileView {
    path: ''' + json.dumps(str(target)) + '''
    onLoaded: {
      if (FilesIndex.isUtf8(data()) !== ''' + str(expected).lower() + ''') {
        console.error("FAIL encoding"); Qt.exit(1)
      } else { console.log("PASS"); Qt.quit() }
    }
  }
''')

    check_file_edits(files, base, run, block)

    # Replace the external clipboard owner, preserving the actual shell pipeline
    # and QML completion handler. Nothing touches the desktop clipboard.
    (base / "wl-copy").write_text('#!/bin/sh\ncat > "$CHECK_COPY"\nexit "$CHECK_COPY_EXIT"\n')
    (base / "wl-copy").chmod(0o755)
    captured = base / "clipboard"
    selected = "/home/test/a '$file with spaces.txt"
    clipboard = '''
  // FilesOps borrows the selection from its panel; here it is its own.
  property var panel: root
  property bool editing: false
  property string home: "/home/test"
  property var sel: ({path: ''' + json.dumps(selected) + '''})
  property var op: null
  property string fileNote: ""
  function note(text) { root.fileNote = text }
''' + block(ops, r"  function run\(") + block(ops, r"  function copyPath\(") + block(ops, r"  Process {\n    id: filer") + '''
  Component.onCompleted: {
    root.copyPath()
    if (root.fileNote) { console.error("FAIL premature success"); Qt.exit(1) }
  }
  onFileNoteChanged: {
    var failed = Quickshell.env("CHECK_COPY_EXIT") !== "0"
    if (failed ? root.fileNote !== "copy path failed" : root.fileNote.indexOf("copied ") !== 0) {
      console.error("FAIL completion", root.fileNote); Qt.exit(1)
    } else { console.log("PASS"); Qt.quit() }
  }
'''
    for code in [0, 127]:
        run("clipboard-" + str(code), clipboard,
            {"PATH": str(base) + ":" + os.environ["PATH"], "CHECK_COPY": str(captured),
             "CHECK_COPY_EXIT": str(code)})
        assert captured.read_text() == selected
