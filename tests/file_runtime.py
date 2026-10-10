"""Actual file editing, file-operation process completion, and clicks in a folder's preview."""
import json
import os
from file_edits import check as check_file_edits


def check(files, ops, base, run, block):
    check_file_edits(files, base, run, block)

    # The real preview under real pointer events: a click on an entry picks its column and line, a
    # double click opens the pick, and the scroll wheel still reaches the preview beneath.
    run("preview-pointer", '''
  property var entries: Array.from({ length: 200 }, (_, i) => ({ name: "e" + i, isDir: false, size: 1, modified: null }))
  property var dirColumns: FilesIndex.columns(root.entries, 10, 120, 400, ({}))
  property var dirMarks: []
  property bool showsDir: true
  property int lineHeight: 20
  property int dirTopPad: 5
  property int gutterGap: 16
  property int shownLines: 10
  property bool dirty: false
  property bool editing: false
  property bool previewCut: false
  property bool showAll: false
  property bool showsCode: false
  property bool showsDiff: false
  property bool showsImage: false
  property bool showsMarkdown: false
  property string previewBody: ""
  property string previewNote: ""
  property string previewText: ""
  property string shownText: ""
  property var settledSel: null
  property var picks: []
  function pickPreview(column, line) { root.picks.push(column + ":" + line) }
  function openPicked() { root.picks.push("open") }
  Pointer { id: pointer }
  Window { width: 900; height: 400; visible: true; FilesPreview { id: preview; panel: root; anchors.fill: parent } }
  function find(test) { var out = [], walk = item => item.children.forEach(c => { if (test(c)) out.push(c); walk(c) }); walk(preview); return out }
  Timer { interval: 200; running: true; onTriggered: {
    var column = root.find(c => c.text === root.dirColumns[1])[0], p = column.mapToItem(preview, 10, 3 * 20 + 10)
    pointer.mouseClick(preview, p.x, p.y, Qt.LeftButton, Qt.NoModifier, -1)
    pointer.mouseDoubleClickSequence(preview, p.x, p.y + 20, Qt.LeftButton, Qt.NoModifier, -1)
    if (root.picks.join() !== "1:3,1:4,open") { console.error("FAIL clicks in the preview gave", root.picks.join()); Qt.exit(1); return }
    pointer.mouseWheel(preview, p.x, p.y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
    scrolled.start()
  } }
  Timer { id: scrolled; interval: 300; onTriggered: {
    if (!(root.find(c => c.flickableDirection !== undefined)[0].contentY > 0)) { console.error("FAIL the wheel did not scroll the preview"); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')

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
