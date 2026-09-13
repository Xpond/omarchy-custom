import QtQuick
import Quickshell.Io
import "FilesIndex.js" as FilesIndex

// File mutations are serialized here and never overwrite existing paths.
Item {
  id: root

  property var panel: null

  // Held copy/move state survives directory navigation.
  property var held: null
  property string fileNote: ""
  Timer { id: noteFade; interval: 4000; onTriggered: root.fileNote = "" }
  function note(text) { root.fileNote = text; noteFade.restart() }

  function hold(e, move) {
    if (!e) return
    root.held = { path: e.path, name: e.name, isDir: !!e.isDir, move: !!move }
    root.note((move ? "moving " : "copying ") + e.name)
  }

  // Exit 17 is reserved for destination collisions.
  property var op: null
  function run(command, about) {
    if (filer.running) { root.note("a file operation is still running"); return }
    root.op = about
    filer.command = command
    filer.running = true
  }

  // Pass paths as arguments to preserve shell metacharacters.
  function guarded(verb, src, dst) {
    return ["sh", "-c", '[ -e "$2" ] && exit 17; exec ' + verb + ' -- "$1" "$2"',
            "files", src, dst]
  }

  function inHere(name) { return panel.listedDir.replace(/\/+$/, "") + "/" + name }

  function paste() {
    if (!root.held) return
    if (root.inHere(root.held.name) === root.held.path) { root.note("already here"); return }
    var h = root.held
    root.run(root.guarded(h.move ? "mv" : "cp -r", h.path, root.inHere(h.name)),
             { name: h.name, land: true, spend: h.move,
               done: (h.move ? "moved " : "copied ") + h.name,
               fail: (h.move ? "move" : "copy") + " failed" })
  }

  Process {
    id: filer
    onExited: function (exitCode) {
      var o = root.op
      root.op = null
      if (!o) return
      if (exitCode !== 0) {
        root.note(exitCode === 17 ? "a " + o.name + " is already here" : o.fail)
        return
      }
      if (o.land) panel.pending = o.name
      root.note(o.done)
      if (o.spend) root.held = null
    }
  }
  function copyPath() {
    if (!panel.sel || panel.editing) return
    root.run(["sh", "-c", 'printf %s "$1" | wl-copy', "files", panel.sel.path],
             { done: "copied " + FilesIndex.display(panel.sel.path, panel.home),
               fail: "copy path failed" })
  }
  // Deletion uses trash, requires two presses, and stays visibly red across themes.
  readonly property color danger: "#ff2222"
  property string doomed: ""
  readonly property string doomedName:
    root.doomed ? root.doomed.slice(root.doomed.lastIndexOf("/") + 1) : ""
  Timer { id: doomArmed; interval: 3000; onTriggered: root.doomed = "" }
  function remove() {
    var e = panel.sel
    if (!e || panel.editing) return
    if (root.doomed !== e.path) {
      root.doomed = e.path
      doomArmed.restart()
      return
    }
    root.doomed = ""
    root.run(["gio", "trash", "--", e.path],
             { name: e.name, done: "trashed " + e.name, fail: "delete failed" })
  }
  // Keep the panel open unless another application accepts the file.
  property var opening: null
  function activate(e) {
    if (!e || panel.editing) return
    if (e.isDir) { panel.enter(e.path); return }
    root.opening = e
    opener.command = ["omarchy-open-path", e.path]
    opener.running = true
  }

  Process {
    id: opener
    onExited: function (exitCode) {
      if (exitCode === 0) { panel.close(); return }
      // Exit 3 is a quiet decline; exit 4 means no application claimed the file.
      if (exitCode !== 4) return
      root.note(root.opening.size === 0
                ? root.opening.name + " is empty -- ctrl+e writes it"
                : "nothing here opens " + root.opening.name)
    }
  }
}
