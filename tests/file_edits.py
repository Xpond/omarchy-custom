"""Protect full file contents through the production editor and save verification."""
import json
from pathlib import Path
import re


def check(source, base, run, block):
    preview = (Path(__file__).resolve().parents[1] / "plugins/xpo.files/FilesPreview.qml").read_text()
    dirty_handler = re.search(r"^ +onTextChanged: .*", preview, re.M)[0]
    editable = re.search(r"^  readonly property bool editable:.*?root.settledSel.size === 0\)",
                         source, re.M | re.S)[0]
    production = "\n".join([editable, block(source, r"  function edit\("),
                               block(source, r"  property var saving:"),
                               block(source, r"  function leaveEdit\("),
                               block(source, r"  FileView {\n    id: previewFile")])
    common = '''
  property string previewPath: ""
  property string fullText: ""
  property bool utf8: false
  readonly property string previewText: FilesIndex.head(root.fullText, 3)
  property var settledSel: ({ size: 0 })
  property bool editing: false
  property bool dirty: false
  property bool saveError: false
  property bool discarding: false
  property int flashes: 0
  property int focusCalls: 0
  QtObject { id: ops; property string fileNote: ""; function note(text) { fileNote = text } }
  TextEdit {
    id: preview
    property var panel: root
    property alias editorText: preview.text
    function keepPlace() {}
    function focusEditor() { root.focusCalls++ }
''' + dirty_handler + '''
  }
  QtObject { id: keys; function forceActiveFocus() {} }
  Timer { id: savedFlash; interval: 1500; onRunningChanged: if (running) root.flashes++ }
  Timer { id: verifySave; interval: 150; onTriggered: previewFile.reload() }
  Timer { id: discardArmed; interval: 2000; onTriggered: root.discarding = false }
  function check(ok, message) { if (!ok) throw new Error("FAIL " + message) }
''' + production

    for name, content, note in [("truncated", b"one\ntwo\nthree\nfour\n", ""),
                                ("non-utf8", b"caf\xe9\n", "not UTF-8; preview only")]:
        target = base / (name + ".txt")
        target.write_bytes(content)
        run("edit-refuses-" + name, common + '''
  Component.onCompleted: root.previewPath = ''' + json.dumps(str(target)) + '''
  Timer { interval: 200; running: true; onTriggered: {
    try {
      root.check(root.fullText.length > 0, "fixture never loaded")
      root.edit()
      root.check(!root.editable && !root.editing && root.focusCalls === 0, "unsafe preview became editable")
      root.check(ops.fileNote === ''' + json.dumps(note) + ''', "wrong refusal note")
      console.log("PASS"); Qt.quit()
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
''')
        assert target.read_bytes() == content

    target = base / "wipe.md"
    target.write_bytes(b"line one\nline two\n")
    run("save-newer-edit-and-discard", common + '''
  Component.onCompleted: root.previewPath = ''' + json.dumps(str(target)) + '''
  Timer { interval: 200; running: true; onTriggered: {
    try {
      root.check(root.fullText === "line one\\nline two\\n", "fixture never loaded")
      root.edit()
      root.check(root.editing && preview.editorText === root.fullText && !root.dirty, "edit did not load full text")
      preview.editorText = ""
      root.check(root.dirty, "editing text did not mark the editor dirty")
      root.save()
      root.check(root.saving === "", "empty save was not tracked")
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
  Timer { interval: 500; running: true; onTriggered: {
    try {
      root.check(root.saving === null && root.fullText === "" && !root.dirty && !root.saveError,
                 "clean empty save did not settle cleanly")
      preview.editorText = "saved edit"
      root.save()
      root.check(root.saving === "saved edit\\n", "second save was not tracked")
      preview.editorText = "newer edit"
      root.save()
      root.check(root.saving === "saved edit\\n", "pending save accepted a second write")
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
  Timer { interval: 900; running: true; onTriggered: {
    try {
      root.check(root.saving === null && root.fullText === "saved edit\\n", "second save did not settle")
      root.check(!root.saveError && root.dirty && root.editing && root.flashes === 2,
                 "verification lost the newer edit or reported the wrong save status: "
                 + JSON.stringify([root.saveError, root.dirty, root.editing, root.flashes]))
      root.check(preview.editorText === "newer edit", "verification replaced newer editor text")
      root.leaveEdit()
      root.check(root.editing && root.dirty && root.discarding, "first Escape discarded dirty text")
      root.leaveEdit()
      root.check(!root.editing && !root.dirty && !root.discarding, "second Escape did not discard")
      console.log("PASS"); Qt.quit()
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
''')
    assert target.read_bytes() == b"saved edit\n", "pending newer edits must not replace the saved file"

    locked = base / "read-only-directory"
    locked.mkdir()
    target = locked / "keep.txt"
    target.write_bytes(b"original\n")
    locked.chmod(0o555)
    try:
        run("save-write-failure", common + '''
  Component.onCompleted: root.previewPath = ''' + json.dumps(str(target)) + '''
  Timer { interval: 200; running: true; onTriggered: {
    try {
      root.check(root.fullText === "original\\n", "fixture never loaded")
      root.edit(); preview.editorText = "unsaved"; root.save()
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
  Timer { interval: 700; running: true; onTriggered: {
    try {
      root.check(root.saving === null && root.saveError && root.dirty && root.editing,
                 "failed write was reported clean or left pending")
      root.check(root.fullText === "original\\n" && preview.editorText === "unsaved" && root.flashes === 0,
                 "failed write lost original bytes, unsaved edit, or showed success")
      console.log("PASS"); Qt.quit()
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
''', expected=(r"QML FileView at @save-write-failure\.qml\[\d+:\d+\]: Write of "
              + re.escape(str(target)) + r" failed: Unknown error when opening file\.$",))
        assert target.read_bytes() == b"original\n"
    finally:
        locked.chmod(0o755)
