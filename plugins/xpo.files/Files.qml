import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "FilesIndex.js" as FilesIndex

// A directory browser that lives where the rest of the shell lives: one
// overlay card, keyboard first, wearing the same [menu] tokens the wheel and
// the clipboard do.
//
// It answers where is it, what is in it, and open it -- and then the four
// things you reach for once you are already looking at the file: edit it
// (ctrl+e), move or copy it (ctrl+x, ctrl+c, ctrl+v), rename it (f2), throw it
// away (del). Each earns its place the same way: you are looking at the thing,
// and acting on it should not cost you a terminal.
//
// Every one of them can cost you data when it is wrong, so none of them are
// quiet. Nothing is overwritten -- a taken name comes back as exit 17 and is
// reported, never resolved by inventing one. A delete goes to the trash and is
// asked twice in red. An edit only ever saves a file that was read whole, and
// the save is confirmed by reading it back.
//
// There is still no new-folder and no undo beyond the trash; yazi is installed
// and does the rest properly.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  // Absolute, and without a trailing slash except at the root itself.
  property string dir: Quickshell.env("HOME")
  // A leading / or ~ turns the field from a name filter into a path. The
  // directory being listed becomes whatever complete directory you have typed
  // so far, and the tail you are still typing filters it -- so the list is a
  // completion of the path as you write it.
  //
  // Both prefixes mean the same place, because home is the only root this
  // panel has: `/xpo/omarchy` and `~/xpo/omarchy` are the same path. A leading
  // slash is how you say "from the top" and the top here is $HOME.
  property string filter: ""
  readonly property bool pathMode: root.filter.charAt(0) === "/"
                                   || root.filter.charAt(0) === "~"
  readonly property string typedPath: root.pathMode
    ? root.home + "/" + root.filter.replace(/^[~\/]+/, "") : ""
  readonly property string typedDir: root.pathMode
    ? root.typedPath.slice(0, root.typedPath.lastIndexOf("/") + 1) : ""
  readonly property string typedLeaf: root.pathMode
    ? root.typedPath.slice(root.typedPath.lastIndexOf("/") + 1) : ""
  // What the list is actually showing, which is the typed directory while a
  // path is being written and `dir` the rest of the time. Jailed either way.
  readonly property string listedDir: root.pathMode
    ? FilesIndex.within(root.typedDir, root.home) : root.dir
  property int index: 0
  property bool showHidden: false

  // Resolved when the panel opens and held while it is up, the way the wheel
  // does it. Hyprland moves focus with the pointer, so a live binding would
  // walk the surface onto another monitor while you are reading it. Matched by
  // name, because this Quickshell's HyprlandMonitor carries no `screen`.
  property var openScreen: null
  function focusedScreen() {
    var m = Hyprland.focusedMonitor
    if (!m) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === m.name) return screens[i]
    return null
  }

  // Hover claims the selection only on real cursor movement, for the reason
  // Wheel.qml sets out at length: Qt synthesises a hover move whenever a row
  // shifts under a stationary pointer, and a filtered list shifts constantly.
  property point hoverAt: Qt.point(-1, -1)
  function hoverMoved(pt) {
    if (root.editing) return false
    if (root.hoverAt.x === pt.x && root.hoverAt.y === pt.y) return false
    root.hoverAt = pt
    return true
  }

  // Snapshotted rather than bound -- FolderListModel does not filter
  // directories and sorts on one field. See FilesIndex.snapshot.
  property var entries: []
  // What is actually narrowing the list: the tail of a path while one is being
  // typed, the whole field when it is a plain name filter. The count reads off
  // the same property, so "/Projects/" says 10 items rather than 10 of 10.
  readonly property string query: root.pathMode ? root.typedLeaf : root.filter
  readonly property var rows: FilesIndex.filtered(root.entries, root.query)
  readonly property var sel: root.index >= 0 && root.index < root.rows.length
    ? root.rows[root.index] : null

  // What the preview is looking at: the selection once it has stopped moving.
  // The list answers the arrow key on the frame it arrives; the preview does
  // not, and following every row passed over meant reading a file, slicing five
  // hundred lines out of it and laying them out for nothing. The same 60ms the
  // highlighter already waits.
  property var settledSel: null
  Timer {
    id: settle
    interval: 60
    onTriggered: root.settledSel = root.sel
  }
  readonly property var crumbs: FilesIndex.crumbs(root.listedDir, root.home)

  // ------------------------------------------------------------- surfaces
  //
  // One ground for the whole card. The two columns are told apart by the space
  // between them and by the rules that run under their headings -- not by a
  // second fill or a second frame, which turn a card into two cards and make
  // the preview look like a window that got dropped inside this one.
  readonly property color edge: Util.alpha(Color.menu.text, 0.13)
  readonly property color hoverFill: Util.alpha(Color.menu.text, 0.05)
  readonly property color activeFill: Util.alpha(Color.accent, 0.14)

  // Both columns are sized in characters of the font they render, because that
  // is the unit their contents actually come in: a name is about so many
  // letters long, a line of code is about so many columns wide. A percentage of
  // the display instead gives the preview a wider box than any line will fill,
  // and the void on its right is the width nobody asked for.
  TextMetrics {
    id: nameMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    text: "0"
  }

  // The preview reads a step larger than the file names beside it. It is the
  // only thing on this card you read rather than scan, and 12px of monospace
  // set solid is what "smooshed" means.
  TextMetrics {
    id: codeMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.subtitle
    text: "0"
  }

  readonly property int listWidth: Math.round(nameMetrics.advanceWidth * 34)
    + Style.font.iconLarge + Style.spacing.rowPaddingX * 2 + Style.spacing.md
  readonly property int previewWidth: Math.round(codeMetrics.advanceWidth * 100)
  // Two characters of air between the numbers and the code, so the gutter is a
  // margin rather than a column of digits crowding the first token of a line.
  readonly property int gutterGap: Math.round(codeMetrics.advanceWidth * 2)

  readonly property int rowHeight: Style.spacing.popupRowHeight + Style.spacing.md
  readonly property int rowRadius: Math.min(Style.cornerRadius, Style.space(6))
  // Fixed, and shared by the gutter and the body, so line 240 in the numbers
  // sits on line 240 of the file. It is also the unit a keypress scrolls by.
  // 1.75 is the leading a long block of code is comfortable at; below about
  // 1.5 the descenders of one line start crowding the caps of the next.
  readonly property int lineHeight: Math.round(Style.font.subtitle * 1.75)

  // Anything bigger is not a preview, it is a download. Read as text only
  // after the size says it is worth opening at all.
  readonly property int previewLimit: 262144
  // How much of a long file is worth colouring to show the top of.
  readonly property int previewLines: 500
  readonly property bool showsImage: !!root.settledSel && !root.settledSel.isDir
                                     && FilesIndex.isImage(root.settledSel.name)
  // Rendered rather than dumped: Qt draws Markdown itself, so headings are
  // headings and `**bold**` is bold. Line numbers and a no-wrap column are
  // right for code and wrong for prose, so both go away for these.
  readonly property bool showsMarkdown: !!root.settledSel && !root.settledSel.isDir
                                        && FilesIndex.isMarkdown(root.settledSel.name)
  readonly property string previewPath:
    (root.settledSel && !root.settledSel.isDir && !root.showsImage
     && root.settledSel.size <= root.previewLimit) ? root.settledSel.path : ""
  // The file as it is on disk, held whole so editing has something truthful to
  // save. `previewText` is the cut of it that gets drawn.
  property string fullText: ""
  readonly property string previewText: FilesIndex.head(root.fullText, root.previewLines)
  onPreviewPathChanged: { root.fullText = ""; root.previewHtml = ""; root.saving = "" }

  // Colour comes from pygments rather than from a tokeniser written here. One
  // process per settled selection buys every language it knows, correctly,
  // against a hand-rolled pass that would get shell quoting wrong on its first
  // day. One interpreter does the lexer lookup and the formatting together --
  // naming the lexer with `pygmentize -N` was a second Python start, and a
  // shell to pipe them a third.
  property string previewHtml: ""
  readonly property string highlightScript:
    "import sys\n"
    + "from pygments import highlight\n"
    + "from pygments.lexers import get_lexer_for_filename\n"
    + "from pygments.lexers.special import TextLexer\n"
    + "from pygments.formatters import HtmlFormatter\n"
    + "p = sys.argv[1]\n"
    + "parts = open(p, errors='replace').read().split('\\n')\n"
    + "src = '\\n'.join(parts[:" + root.previewLines + "])\n"
    + "if len(parts) > " + root.previewLines + ": src += '\\n\u2026'\n"
    + "try:\n"
    + "    lx = get_lexer_for_filename(p, stripnl=False)\n"
    + "except Exception:\n"
    + "    lx = TextLexer()\n"
    + "sys.stdout.write(highlight(src, lx,\n"
    + "    HtmlFormatter(nowrap=True, noclasses=True, style='one-dark')))\n"
  readonly property bool showsCode: !!root.previewText && !root.showsMarkdown

  Timer {
    id: highlightSoon
    interval: 60
    onTriggered: {
      if (!root.previewText || root.showsMarkdown) return
      highlighter.command = ["python3", "-c", root.highlightScript, root.previewPath]
      highlighter.running = true
    }
  }

  Process {
    id: highlighter
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.previewHtml = text
    }
  }

  // Arrowing through a directory should not spawn a process per row.
  onPreviewTextChanged: {
    root.previewHtml = ""
    highlighter.running = false
    if (root.previewText && !root.showsMarkdown) highlightSoon.restart()
  }

  // A folder's contents rendered in the same scroller a file's are. A second
  // ListView would only be a second set of scrolling rules to keep in step
  // with the first -- but where a file is one column of lines, a folder is a
  // set of columns, filled down the pane and then across it.
  property var dirEntries: []
  readonly property bool showsDir: !!root.settledSel && root.settledSel.isDir
                                   && root.dirEntries.length > 0
  // As many lines as the pane is tall, as many characters as it is wide: the
  // listing is cut to the pane it is going into.
  readonly property int dirRows: Math.max(1, Math.floor(preview.paneHeight / root.lineHeight))
  readonly property int dirPaneChars: Math.max(20, Math.floor(preview.paneWidth / codeMetrics.advanceWidth))
  readonly property var dirColumns: root.showsDir
    ? FilesIndex.columns(root.dirEntries, root.dirRows, root.dirPaneChars, 400) : []
  // A line of text sits at the top of its line box; a list row sits in the
  // middle of a taller one. Without this the first file in the preview floats
  // above the first file in the list.
  readonly property int dirTopPad: Math.max(0, Math.round((root.rowHeight - codeMetrics.height) / 2))
  readonly property string previewBody:
    root.showsMarkdown ? FilesIndex.airOut(FilesIndex.escapeTags(FilesIndex.flattenLinks(root.previewText)))
    : root.showsCode
      ? FilesIndex.codeHtml(root.previewHtml || FilesIndex.escapeHtml(root.previewText),
                            Style.font.menuFamily, Style.font.subtitle)
      : ""
  // Arming a delete follows the selection: arrow away and it is disarmed, so a
  // second Del can never land on a row you did not aim it at.
  onSelChanged: { settle.restart(); root.doomed = "" }
  // Cleared here rather than left for the model to overwrite: the child model
  // only reports Ready, so between two folders the old folder's contents would
  // otherwise sit under the new folder's name.
  onSettledSelChanged: {
    preview.resetScroll()
    root.dirEntries = []
  }

  // Name on the left, facts on the right. What a preview pane owes you before
  // you have read a byte of it is which file this is and how old.
  readonly property string metaLine:
    !root.settledSel ? ""
    : root.settledSel.isDir ? FilesIndex.countLabel(childFolder.count, childFolder.count, "", root.showHidden)
    : FilesIndex.humanSize(root.settledSel.size)
      + (root.settledSel.modified
         ? "  ·  " + Qt.formatDateTime(root.settledSel.modified, "d MMM yyyy") : "")

  // The preview's fallback line, for everything that cannot draw itself: an
  // empty directory, a filtered-out one, or a file whose bytes are no use on
  // screen. Empty when something IS being shown.
  readonly property string previewNote:
    root.editing ? ""
    : !root.settledSel ? (root.query ? "No match" : "Empty")
    : root.settledSel.isDir ? (root.showsDir ? "" : "Empty folder")
    : root.previewBody ? ""
    : (root.showsImage && previewImage.status !== Image.Error) ? ""
    : FilesIndex.humanSize(root.settledSel.size) + "  ·  no preview"

  // A payload may name where to start; everything else opens at home.
  //
  // Deliberately not "where you last were": a remembered directory is only
  // valid until something moves, renames, unmounts or deletes it, and then the
  // panel opens onto a path that no longer exists and shows an empty list with
  // no hint of why. Home is the one directory that is always there.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    root.enter(payload.dir ? String(payload.dir) : root.home)
    root.pending = payload.select ? String(payload.select) : ""
    root.openScreen = root.focusedScreen()
    root.opened = true
    // Reopening where you last were reloads nothing, so nothing announces the
    // rows and only this call claims the name.
    Qt.callLater(function () { keys.forceActiveFocus(); root.claimPending() })
  }

  // A name to land on once the directory has been read, which is how the wheel
  // hands a file over: the browser opens where the file lives with the file
  // itself selected, so the preview is showing it before you have touched a
  // key. Cleared on arrival, so it claims the selection once and never again.
  property string pending: ""
  // Cleared only once the name is found. Reopening at the directory already
  // shown changes nothing -- same `dir`, same rows -- so `onRowsChanged` never
  // fires and only `open`'s direct call gets here; clearing on a miss would
  // throw the name away a frame before its rows arrive.
  function claimPending() {
    if (!root.pending) return
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].name === root.pending) {
        root.index = i
        root.pending = ""
        list.view.positionViewAtIndex(root.index, ListView.Contain)
        return
      }
    }
  }

  // Refused while an edit is unsaved, the click-outside shield included.
  function close() {
    if (root.editing && root.dirty) { root.leaveEdit(); return }
    root.opened = false
  }

  // Closing lets go of what the preview was holding -- the file's bytes, the
  // folder's entries, the image -- and cancels a settle that would otherwise
  // read a directory for a panel nobody is looking at. Every open starts at
  // home, so none of it would have been reused.
  onOpenedChanged: {
    if (root.opened) {
      // Closing drops the settled selection, so an open landing on the row it
      // left on has no change to react to and would sit at "Empty" over a file
      // that is right there.
      settle.restart()
    } else {
      settle.stop()
      root.settledSel = null
      root.editing = false
      root.dirty = false
      root.discarding = false
    }
  }
  function toggle() { root.opened ? root.close() : root.open("{}") }

  // Moving house: the filter belongs to the directory it was typed in, and
  // carrying it into the next one hides everything on arrival.
  function enter(next) {
    var path = String(next).replace(/\/+$/, "")
    root.dir = FilesIndex.within(path || "/", root.home)
    root.filter = ""
    root.index = 0
    // Walking somewhere yourself abandons a name that never turned up. `open`
    // sets its own after calling this.
    root.pending = ""
  }

  function up() { root.enter(FilesIndex.parentOf(root.dir)) }

  function move(step) {
    var n = root.rows.length
    if (n > 0) root.index = (root.index + step + n) % n
    list.view.positionViewAtIndex(root.index, ListView.Contain)
  }

  // ------------------------------------------------------------------- edit
  //
  // The one thing here that writes. Modal, because every printable key in this
  // panel lands in the filter and nothing can type into a file and into a
  // search box at once: while `editing` the whole keyboard goes to the editor
  // and only escape and ctrl+s are kept.
  //
  // Plain source, because what the preview draws is a rendering -- pygments
  // HTML, or Qt's markdown -- and editing a rendering saves the rendering.
  property bool editing: false
  property bool dirty: false
  property bool saveError: false
  // Only a file read whole: `head` cuts past 500 lines and marks the cut with
  // an ellipsis, and saving that back would delete the rest of the file. The
  // size test is what tells an empty file from a binary one, both of which
  // arrive here as no text at all.
  readonly property bool editable: !!root.previewPath && root.fullText === root.previewText
                                   && (!!root.fullText || root.settledSel.size === 0)

  function edit() {
    if (!root.editable || root.editing) return
    preview.editorText = root.fullText
    root.dirty = false
    root.saveError = false
    preview.keepPlace()
    root.editing = true
    preview.focusEditor()
  }

  // Written and then read back: `FileView` emits neither `saved` nor
  // `saveFailed` for a `setText`, and a write that fails on permissions only
  // logs a warning nothing in QML hears. The disk is the only thing that can
  // say. A reload in the same tick as the write is swallowed, hence the wait.
  property string saving: ""
  function save() {
    if (!root.editing || root.saving) return
    root.saveError = false
    root.saving = FilesIndex.endLine(preview.editorText)
    previewFile.setText(root.saving)
    verifySave.restart()
  }

  Timer { id: verifySave; interval: 150; onTriggered: previewFile.reload() }

  // Escape leaves a clean editor at once and asks twice for a dirty one, the
  // shape the filter already has.
  property bool discarding: false
  function leaveEdit() {
    if (root.dirty && !root.discarding) { root.discarding = true; discardArmed.restart(); return }
    preview.keepPlace()
    root.editing = false
    root.dirty = false
    root.discarding = false
    keys.forceActiveFocus()
  }

  Timer { id: discardArmed; interval: 2000; onTriggered: root.discarding = false }
  Timer { id: savedFlash; interval: 1500 }

  // -------------------------------------------------------------- file moves
  //
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
    if (filer.running) return
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

  function inHere(name) { return root.listedDir.replace(/\/+$/, "") + "/" + name }

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
      if (o.land) root.pending = o.name
      root.note(o.done)
      // A move has spent its source. A copy has not, so it can be placed again.
      if (o.spend) root.held = null
    }
  }

  // ---------------------------------------------------------- rename, delete
  //
  // The filter chip becomes the name field: it is already a text box with a
  // caret in it, sitting where the name reads, and a second one would be a
  // second thing to learn. With a real caret, because renaming is mostly
  // changing a few characters in the middle of a name you already have and a
  // field you can only type at the end of makes you retype all of it.
  property bool renaming: false
  property string renameTo: ""
  property int renameAt: 0

  function beginRename() {
    if (!root.sel || root.editing) return
    root.renameTo = root.sel.name
    // On the stem, before the extension, because that is the part being
    // changed nine times out of ten.
    var dot = root.renameTo.lastIndexOf(".")
    root.renameAt = dot > 0 ? dot : root.renameTo.length
    root.renaming = true
  }

  function renameKey(event) {
    var at = root.renameAt
    var t = root.renameTo
    switch (event.key) {
    case Qt.Key_Left:  root.renameAt = Math.max(0, at - 1); return
    case Qt.Key_Right: root.renameAt = Math.min(t.length, at + 1); return
    case Qt.Key_Home:  root.renameAt = 0; return
    case Qt.Key_End:   root.renameAt = t.length; return
    case Qt.Key_Backspace:
      if (!at) return
      root.renameTo = t.slice(0, at - 1) + t.slice(at)
      root.renameAt = at - 1
      return
    case Qt.Key_Delete:
      root.renameTo = t.slice(0, at) + t.slice(at + 1)
      return
    }
    if (event.modifiers & Qt.ControlModifier) {
      switch (event.key) {
      case Qt.Key_U: root.renameTo = t.slice(at); root.renameAt = 0; return
      case Qt.Key_K: root.renameTo = t.slice(0, at); return
      case Qt.Key_A: root.renameAt = 0; return
      case Qt.Key_E: root.renameAt = t.length; return
      // A name is text like any other, and a path is the likeliest thing to be
      // on the clipboard while you are renaming. Separators come out: what
      // goes in this field is a name.
      case Qt.Key_V:
        var clip = String(Quickshell.clipboardText || "").replace(/[\s\/]+/g, " ").trim()
        root.renameTo = t.slice(0, at) + clip + t.slice(at)
        root.renameAt = at + clip.length
        return
      }
      return
    }
    if (event.text && event.text.length === 1 && event.text >= " ") {
      root.renameTo = t.slice(0, at) + event.text + t.slice(at)
      root.renameAt = at + event.text.length
    }
  }

  function commitRename() {
    var e = root.sel
    var name = root.renameTo.trim()
    root.renaming = false
    if (!e || !name || name === e.name) return
    // A name is a name. Anything with a separator in it is a move being asked
    // for in the wrong field, and moving is what ctrl+x is for.
    if (name.indexOf("/") !== -1) { root.note("a name cannot hold a /"); return }
    root.run(root.guarded("mv", e.path, root.inHere(name)),
             { name: name, land: true, done: "renamed to " + name, fail: "rename failed" })
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
    var e = root.sel
    if (!e || root.editing) return
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
  function activate(e) {
    if (!e || root.editing) return
    if (e.isDir) { root.enter(e.path); return }
    opener.command = ["omarchy-open-path", e.path]
    opener.running = true
  }

  Process {
    id: opener
    onExited: function (exitCode) { if (exitCode === 0) root.close() }
  }

  // The list is rebuilt when the directory changes, when it finishes reading,
  // and when hidden files are toggled -- all three arrive as one of these two.
  FolderListModel {
    id: folder
    folder: "file://" + root.listedDir
    showDirsFirst: true
    showDotAndDotDot: false
    showHidden: root.showHidden
    sortField: FolderListModel.Name
    // Both, and both gated: a load raises count on its way to Ready, and a
    // file appearing under an open panel raises it after. Ungated, every
    // directory was snapshotted twice and flashed empty in between.
    onStatusChanged: if (status === FolderListModel.Ready) root.entries = FilesIndex.snapshot(folder)
    onCountChanged: if (status === FolderListModel.Ready) root.entries = FilesIndex.snapshot(folder)
  }

  FolderListModel {
    id: childFolder
    folder: (root.settledSel && root.settledSel.isDir) ? "file://" + root.settledSel.path : ""
    showDirsFirst: true
    showDotAndDotDot: false
    showHidden: root.showHidden
    sortField: FolderListModel.Name
    onStatusChanged: if (status === FolderListModel.Ready) root.dirEntries = root.childEntries()
    onCountChanged: if (status === FolderListModel.Ready) root.dirEntries = root.childEntries()
  }

  function childEntries() {
    if (!root.settledSel || !root.settledSel.isDir) return []
    return FilesIndex.snapshot(childFolder)
  }

  FileView {
    id: previewFile
    path: root.previewPath
    printErrors: false
    // Through a temporary and renamed into place, so a write that dies half way
    // leaves the old file rather than half of a new one.
    atomicWrites: true
    onLoaded: {
      root.fullText = FilesIndex.looksBinary(text()) ? "" : text()
      // The read-back half of a save. Typing during the wait leaves it dirty.
      if (root.saving) {
        root.saveError = root.fullText !== root.saving
        root.dirty = root.saveError || FilesIndex.endLine(preview.editorText) !== root.saving
        if (!root.saveError) savedFlash.restart()
        root.saving = ""
      }
    }
    onLoadFailed: root.fullText = ""
  }

  // Clamped rather than left pointing past the end: typing narrows the list
  // under a standing selection without the selection having moved.
  onRowsChanged: {
    if (root.index >= root.rows.length) root.index = 0
    root.claimPending()
  }

  PanelWindow {
    id: surface
    visible: root.opened
    screen: root.openScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-files"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      anchors.centerIn: parent
      // As wide as its two columns need and no wider; as tall as the screen
      // will comfortably give, because a directory listing always wants more
      // rows and a preview always wants more lines.
      width: Math.min(root.listWidth + root.previewWidth + Style.spacing.huge
                      + Style.spacing.lg * 2 + Style.spacing.panelPadding * 2,
                      surface.width * 0.92)
      height: Math.min(Style.space(900), surface.height * 0.80)
      radius: Style.cornerRadius
      // Opaque, unlike the wheel's. The wheel is a thin ring where the blurred
      // desktop showing through is the effect; this is a page of file names and
      // a preview, and text over a moving desktop is what reads as unsharp.
      color: Color.menu.background
      borderSpec: Border.flat(root.edge, Style.spacing.hairline)

      // Ahead of the rows so their own areas still take what lands on them,
      // and only the padding around them reaches the dismiss handler.
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        // Even padding, except at the foot: the hints are chrome rather than
        // content, and a full column of air under one line of 10px type is the
        // space that reads as a mistake.
        anchors.margins: Style.spacing.panelPadding
        anchors.bottomMargin: Style.spacing.xl
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          // `Keys.priority: Keys.BeforeItem` means this handler sees every key
          // before the editor does, focused or not -- the same thing Omarchy's
          // own PanelKeyCatcher documents. Anything not accepted here goes on
          // to the editor, which is what makes typing work; the clipboard is
          // spelled out rather than left to TextEdit's own handling, because a
          // panel this modal should not have verbs that only work by accident.
          if (root.editing) {
            if (event.modifiers & Qt.ControlModifier) {
              switch (event.key) {
              case Qt.Key_S: root.save(); event.accepted = true; return
              case Qt.Key_C: preview.copy(); event.accepted = true; return
              case Qt.Key_X: preview.cut(); event.accepted = true; return
              case Qt.Key_V: preview.paste(); event.accepted = true; return
              case Qt.Key_A: preview.selectAll(); event.accepted = true; return
              }
            }
            if (event.key === Qt.Key_Escape) { root.leaveEdit(); event.accepted = true }
            return
          }
          // Renaming takes the keyboard the way editing does, and for the same
          // reason: the field it is typing into is the one the filter uses.
          // Any key that is not the second Del calls the delete off. The foot
          // is showing a question; a keystroke that is not the answer is a no.
          if (root.doomed && event.key !== Qt.Key_Delete) root.doomed = ""

          if (root.renaming) {
            switch (event.key) {
            case Qt.Key_Escape: root.renaming = false; break
            case Qt.Key_Return:
            case Qt.Key_Enter:  root.commitRename(); break
            default: root.renameKey(event)
            }
            // Everything, so an arrow cannot move the selection out from under
            // the name being typed.
            event.accepted = true
            return
          }
          if (event.modifiers & Qt.ControlModifier) {
            switch (event.key) {
            case Qt.Key_E: root.edit(); event.accepted = true; return
            case Qt.Key_C: root.hold(root.sel, false); event.accepted = true; return
            case Qt.Key_X: root.hold(root.sel, true); event.accepted = true; return
            case Qt.Key_V: root.paste(); event.accepted = true; return
            case Qt.Key_H: root.showHidden = !root.showHidden; event.accepted = true; return
            case Qt.Key_U: root.filter = ""; event.accepted = true; return
            }
          }
          // Shift turns the arrows on the preview instead of the list. Held
          // down, it is the one modifier that reads as "the other pane".
          if (event.modifiers & Qt.ShiftModifier) {
            switch (event.key) {
            case Qt.Key_Down:  preview.scrollBy(root.lineHeight * 3); event.accepted = true; return
            case Qt.Key_Up:    preview.scrollBy(-root.lineHeight * 3); event.accepted = true; return
            case Qt.Key_Right: preview.scrollAcross(Style.space(60)); event.accepted = true; return
            case Qt.Key_Left:  preview.scrollAcross(-Style.space(60)); event.accepted = true; return
            }
          }
          switch (event.key) {
          // One step at a time: the filter, then the panel.
          case Qt.Key_Escape:
            if (root.filter) root.filter = ""
            else root.close()
            event.accepted = true; return
          // Backspace edits the filter while there is one, because that is
          // what it does in every field. Left is the way up that always works.
          case Qt.Key_Backspace:
            if (root.filter) root.filter = root.filter.slice(0, -1)
            else root.up()
            event.accepted = true; return
          case Qt.Key_Left:  root.up(); event.accepted = true; return
          case Qt.Key_Down:  root.move(1); event.accepted = true; return
          case Qt.Key_Up:    root.move(-1); event.accepted = true; return
          case Qt.Key_Tab:   root.move(1); event.accepted = true; return
          case Qt.Key_Backtab: root.move(-1); event.accepted = true; return
          case Qt.Key_PageDown: preview.scrollBy(preview.pageStep); event.accepted = true; return
          case Qt.Key_PageUp:   preview.scrollBy(-preview.pageStep); event.accepted = true; return
          case Qt.Key_Home:  root.enter(root.home); event.accepted = true; return
          case Qt.Key_F2:    root.beginRename(); event.accepted = true; return
          case Qt.Key_Delete: root.remove(); event.accepted = true; return
          case Qt.Key_Right:
          case Qt.Key_Return:
          case Qt.Key_Enter:
            root.activate(root.sel); event.accepted = true; return
          }
          if (event.text && event.text.length === 1 && event.text >= " ") {
            root.filter += event.text
            root.index = 0
            event.accepted = true
          }
        }

        FilesHeader {
          id: header
          panel: root
          anchors { top: parent.top; left: parent.left; right: parent.right }
        }

        Rectangle {
          id: rule
          anchors { top: header.bottom; left: parent.left; right: parent.right }
          height: Style.spacing.hairline
          color: root.edge
        }

        // -------------------------------------------------------------- body
        Item {
          id: body
          anchors {
            top: rule.bottom; topMargin: Style.spacing.panelGap
            left: parent.left; right: parent.right
            bottom: footRule.top; bottomMargin: Style.spacing.panelGap
          }

          FilesList {
            id: list
            panel: root
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: root.listWidth
          }

          FilesPreview {
            id: preview
            panel: root
            anchors {
              top: parent.top; bottom: parent.bottom
              left: list.right; leftMargin: Style.spacing.huge
              right: parent.right
            }
          }
        }

        Rectangle {
          id: footRule
          // The same air above the words as below them.
          anchors {
            bottom: hints.top; bottomMargin: Style.spacing.xl
            left: parent.left; right: parent.right
          }
          height: Style.spacing.hairline
          color: root.edge
        }

        FilesHints {
          id: hints
          panel: root
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        }
      }
    }
  }
}
