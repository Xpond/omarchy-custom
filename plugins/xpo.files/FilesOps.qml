import QtQuick
import Quickshell
import Quickshell.Io
import "FilesIndex.js" as FilesIndex

// Everything in the browser that writes, in one place and behind one process.
// The panel decides what to do; this does it and says how it went. Kept apart
// because these are the verbs that can cost you data when they are wrong, and
// a file you can read end to end is the cheapest guard there is.
Item {
  id: root

  // The panel, for the selection and the directory the verbs act on. Passed
  // rather than reached for, the way FilesHints takes it.
  property var panel: null

  // One held entry and one verb, the idiom every file manager already uses:
  // ctrl+x or ctrl+c takes the selection, ctrl+v places it in the directory you
  // have walked to. A move between two directories is the thing people actually
  // open a second pane for, and not having it is what sends you to a terminal.
  //
  // Nothing is ever overwritten. The destination name is tested before the
  // command runs and a collision comes back as its own exit code, reported as
  // it is rather than resolved by inventing a "(copy)" name -- a file manager
  // that renames your file for you is one you cannot predict.
  property var held: null
  property string fileNote: ""
  Timer { id: noteFade; interval: 4000; onTriggered: root.fileNote = "" }
  function note(text) { root.fileNote = text; noteFade.restart() }

  function hold(e, move) {
    if (!e) return
    root.held = { path: e.path, name: e.name, isDir: !!e.isDir, move: !!move }
    root.note((move ? "moving " : "copying ") + e.name)
  }

  // Every write goes through one process and one contract: exit 0 is done, 17
  // is the name is taken, anything else failed. `op` is what to say about it.
  property var op: null
  function run(command, about) {
    if (filer.running) { root.note("a file operation is still running"); return }
    root.op = about
    filer.command = command
    filer.running = true
  }

  // Paths go as arguments, never spliced into the script, so a name with a
  // space or a $ in it is just a name. $2 is the destination, and 17 is nothing
  // mv or cp returns on its own.
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
      // The model watches the directory, so the row arrives on its own; this
      // is only which of them to land on once it does.
      if (o.land) panel.pending = o.name
      root.note(o.done)
      // A move has spent its source. A copy has not, so it can be placed again.
      if (o.spend) root.held = null
    }
  }
  // The one thing the panel could not do with a file it is showing you: name it
  // to something else. Path as an argument, never spliced -- `guarded`'s rule.
  function copyPath() {
    if (!panel.sel || panel.editing) return
    root.run(["sh", "-c", 'printf %s "$1" | wl-copy', "files", panel.sel.path],
             { done: "copied " + FilesIndex.display(panel.sel.path, panel.home),
               fail: "copy path failed" })
  }
  // Trashed, not removed. gio puts it in the freedesktop trash, where it can be
  // got back -- the difference between a delete you can survive and one you
  // cannot. Asked twice all the same, because it is the one verb here that
  // takes something away, and the second press is cheaper than the regret.
  // Not Color.urgent: themes set it to a muted brick that reads brown at small
  // sizes, and a question about destroying something has to be the one colour
  // on the card nobody has to look twice at. Fixed on purpose, and the only
  // place in this panel that ignores the theme.
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
  // A directory is somewhere to go; a file is something to hand off -- when the
  // desktop has an app for it. Nothing here opens an editor: a text file is
  // already open in the pane on the right. The panel steps aside only when
  // something is taking over, which is what the opener's exit code says: zero
  // means a viewer is coming, 3 that it declined and this keeps its place.
  property string opening: ""
  function activate(e) {
    if (!e || panel.editing) return
    if (e.isDir) { panel.enter(e.path); return }
    root.opening = e.name
    opener.command = ["omarchy-open-path", e.path]
    opener.running = true
  }

  Process {
    id: opener
    onExited: function (exitCode) {
      if (exitCode === 0) { panel.close(); return }
      // 3 is a terminal handler declining a file the pane is already showing, so
      // there is nothing to say. 4 is nothing owning it at all, and silence
      // there reads as a key that did nothing.
      if (exitCode === 4) root.note("nothing here opens " + root.opening)
    }
  }
}
