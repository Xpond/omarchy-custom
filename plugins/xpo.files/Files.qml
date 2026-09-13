import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui
import "FilesIndex.js" as FilesIndex
import "FilesKeys.js" as FilesKeys

// Keyboard-first browser rooted at $HOME. Writes never overwrite; deletes use trash.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  // Absolute, and without a trailing slash except at the root itself.
  property string dir: Quickshell.env("HOME")
  // A leading / or ~ enters path completion; both are rooted at $HOME.
  property string filter: ""
  readonly property bool pathMode: root.filter.charAt(0) === "/"
                                   || root.filter.charAt(0) === "~"
  readonly property string typedPath: root.pathMode
    ? root.home + "/" + root.filter.replace(/^[~\/]+/, "") : ""
  readonly property string typedDir: root.pathMode
    ? root.typedPath.slice(0, root.typedPath.lastIndexOf("/") + 1) : ""
  readonly property string typedLeaf: root.pathMode
    ? root.typedPath.slice(root.typedPath.lastIndexOf("/") + 1) : ""
  // The typed directory in path mode, jailed to $HOME either way.
  readonly property string listedDir: root.pathMode
    ? FilesIndex.within(root.typedDir, root.home) : root.dir
  property int index: 0
  property bool showHidden: false
  property string order: "name"
  function cycleOrder() {
    root.order = FilesIndex.nextOrder(root.order)
    root.index = 0
  }

  // Freeze the focused screen on open; pointer focus can otherwise move it.
  property var openScreen: null
  function focusedScreen() {
    var m = Hyprland.focusedMonitor
    if (!m) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === m.name) return screens[i]
    return null
  }

  // Ignore Qt's synthetic hover moves when filtered rows shift under the pointer.
  property point hoverAt: Qt.point(-1, -1)
  function hoverMoved(pt) {
    if (root.editing) return false
    if (root.hoverAt.x === pt.x && root.hoverAt.y === pt.y) return false
    root.hoverAt = pt
    return true
  }

  // FolderListModel cannot combine directory filtering with our ranking.
  property var entries: []
  readonly property string query: root.pathMode ? root.typedLeaf : root.filter
  readonly property var rows: FilesIndex.filtered(root.entries, root.query, root.order)
  readonly property var sel: root.index >= 0 && root.index < root.rows.length
    ? root.rows[root.index] : null

  // Debounce preview work while the selection is moving.
  property var settledSel: null
  Timer {
    id: settle
    interval: 60
    onTriggered: root.settledSel = root.sel
  }
  readonly property var crumbs: FilesIndex.crumbs(root.listedDir, root.home)

  // ------------------------------------------------------------- surfaces
  readonly property color edge: Util.alpha(Color.menu.text, 0.13)
  readonly property color hoverFill: Util.alpha(Color.menu.text, 0.05)
  readonly property color activeFill: Util.alpha(Color.accent, 0.14)

  // Size both columns in the characters they render.
  TextMetrics {
    id: nameMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    text: "0"
  }

  TextMetrics {
    id: codeMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.subtitle
    text: "0"
  }

  readonly property int listWidth: Math.round(nameMetrics.advanceWidth * 34)
    + Style.font.iconLarge + Style.spacing.rowPaddingX * 2 + Style.spacing.md
  readonly property int previewWidth: Math.round(codeMetrics.advanceWidth * 100)
  readonly property int gutterGap: Math.round(codeMetrics.advanceWidth * 2)

  readonly property int rowHeight: Style.spacing.popupRowHeight + Style.spacing.md
  // Shared by gutter, body, and keyboard scrolling to keep line numbers aligned.
  readonly property int lineHeight: Math.round(Style.font.subtitle * 1.75)

  readonly property int previewLimit: 262144
  readonly property int previewLines: 500
  readonly property bool showsImage: !!root.settledSel && !root.settledSel.isDir
                                     && FilesIndex.isImage(root.settledSel.name)
  property string imageDims: ""
  Process {
    id: measurer
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.imageDims = text.split("\n")[0].trim()
    }
  }
  readonly property bool showsMarkdown: !!root.settledSel && !root.settledSel.isDir
                                        && FilesIndex.isMarkdown(root.settledSel.name)
  readonly property string previewPath:
    (root.settledSel && !root.settledSel.isDir && !root.showsImage
     && root.settledSel.size <= root.previewLimit) ? root.settledSel.path : ""
  // Keep the full file for safe editing; only the preview is truncated.
  property string fullText: ""
  property bool utf8: false
  readonly property string previewText: FilesIndex.head(root.fullText, root.previewLines)
  onPreviewPathChanged: { root.fullText = ""; root.utf8 = false; root.previewHtml = ""; root.saving = null }

  // Highlight only the settled selection, in one Pygments process.
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
    + "if len(parts) - (parts[-1] == '') > " + root.previewLines + ": src += '\\n\u2026'\n"
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

  onPreviewTextChanged: {
    root.previewHtml = ""
    highlighter.running = false
    if (root.previewText && !root.showsMarkdown) highlightSoon.restart()
  }

  // Fill folder previews down the pane, then across it.
  property var dirEntries: []
  readonly property bool showsDir: !!root.settledSel && root.settledSel.isDir
                                   && root.dirEntries.length > 0
  readonly property int dirRows: Math.max(1, Math.floor(preview.paneHeight / root.lineHeight))
  readonly property int listPage: Math.max(1, Math.floor(list.view.height / root.rowHeight) - 1)
  readonly property int dirPaneChars: Math.max(20, Math.floor(preview.paneWidth / codeMetrics.advanceWidth))
  readonly property var dirColumns: root.showsDir
    ? FilesIndex.columns(root.dirEntries, root.dirRows, root.dirPaneChars, 400) : []
  // Align the first preview line with the centered text in the first list row.
  readonly property int dirTopPad: Math.max(0, Math.round((root.rowHeight - codeMetrics.height) / 2))
  readonly property string previewBody:
    root.showsMarkdown ? FilesIndex.airOut(FilesIndex.escapeTags(FilesIndex.flattenLinks(root.previewText)))
    : root.showsCode
      ? FilesIndex.codeHtml(root.previewHtml || FilesIndex.escapeHtml(root.previewText),
                            Style.font.menuFamily, Style.font.subtitle)
      : ""
  // Changing selection disarms delete.
  onSelChanged: { settle.restart(); ops.doomed = "" }
  // Clear stale folder and image data before the next preview loads.
  onSettledSelChanged: {
    preview.resetScroll()
    root.dirEntries = []
    root.imageDims = ""
    measurer.running = false
    if (root.settledSel && !root.settledSel.isDir && FilesIndex.isImage(root.settledSel.name)) {
      measurer.command = ["identify", "-format", "%w×%h\n", root.settledSel.path]
      measurer.running = true
    }
  }

  readonly property string metaLine:
    !root.settledSel ? ""
    : root.settledSel.isDir ? FilesIndex.countLabel(childFolder.count, childFolder.count, "", root.showHidden)
    : FilesIndex.humanSize(root.settledSel.size)
      + (root.imageDims ? "  ·  " + root.imageDims : "")
      + (root.settledSel.modified
         ? "  ·  " + Qt.formatDateTime(root.settledSel.modified, "d MMM yyyy") : "")

  // Empty while the preview has content of its own.
  readonly property string previewNote:
    root.editing ? ""
    : !root.settledSel ? (root.query ? "No match" : "Empty")
    : root.settledSel.isDir ? (root.showsDir ? "" : "Empty folder")
    : root.previewBody ? ""
    : (root.showsImage && preview.imageStatus !== Image.Error) ? ""
    : FilesIndex.humanSize(root.settledSel.size) + "  ·  no preview"

  // Payloads may choose a start; otherwise use the stable home directory.
  function open(payloadJson) {
    if (root.editing && (root.dirty || root.saving !== null)) {
      ops.note("save or discard the current edit first")
      preview.focusEditor()
      return
    }
    if (root.editing) root.leaveEdit()
    root.naming = ""
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    root.enter(payload.dir ? String(payload.dir) : root.home)
    root.pending = payload.select ? String(payload.select) : ""
    root.openScreen = root.focusedScreen()
    root.opened = true
    // Rows may already be loaded, so claim directly as well as onRowsChanged.
    Qt.callLater(function () { keys.forceActiveFocus(); root.claimPending() })
  }

  // A one-shot selection requested by the wheel handoff.
  property string pending: ""
  // Keep misses until asynchronous rows arrive.
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

  function close() {
    if (!root.opened) return
    if (root.editing && root.dirty) { root.leaveEdit(); return }
    root.opened = false
    if (root.shell) root.shell.hide("xpo.files")
  }

  // Drop preview state and pending work when the panel closes.
  onOpenedChanged: {
    if (root.opened) {
      // Rebuild a preview even when reopening on the same row.
      settle.restart()
    } else {
      settle.stop()
      root.settledSel = null
      root.editing = false
      root.dirty = false
      root.discarding = false
      root.naming = ""
    }
  }
  function toggle() { root.opened ? root.close() : root.open("{}") }

  function enter(next) {
    var path = String(next).replace(/\/+$/, "")
    root.dir = FilesIndex.within(path || "/", root.home)
    root.filter = ""
    root.index = 0
    root.pending = ""
  }

  function up() { root.enter(FilesIndex.parentOf(root.dir)) }

  // At home, hand Backspace navigation to the wheel.
  function toWheel() {
    if (root.shell) root.shell.callIfLoaded("xpo.wheel", "back", "")
  }

  function move(step) {
    var n = root.rows.length
    if (n > 0) root.index = (root.index + step + n) % n
    list.view.positionViewAtIndex(root.index, ListView.Contain)
  }

  function goTo(i) {
    root.move(Math.max(0, Math.min(i, root.rows.length - 1)) - root.index)
  }

  // ------------------------------------------------------------------- edit
  //
  // Editing is modal so printable keys cannot also reach the filter.
  property bool editing: false
  property bool dirty: false
  property bool saveError: false
  // Never edit a truncated or non-UTF-8 preview; saving it would lose data.
  readonly property bool editable: root.utf8 && !!root.previewPath && root.fullText === root.previewText
                                   && (!!root.fullText || root.settledSel.size === 0)

  function edit() {
    if (root.previewPath && !root.utf8) { ops.note("not UTF-8; preview only"); return }
    if (!root.editable || root.editing) return
    ops.fileNote = ""
    preview.editorText = root.fullText
    root.dirty = false
    root.saveError = false
    preview.keepPlace()
    root.editing = true
    preview.focusEditor()
  }

  // FileView does not report write failure, so verify from disk after a delay.
  // null means idle; "" is a valid save in flight.
  property var saving: null
  function save() {
    if (!root.editing || root.saving !== null) return
    root.saveError = false
    ops.fileNote = ""
    root.saving = FilesIndex.endLine(preview.editorText)
    previewFile.setText(root.saving)
    verifySave.restart()
  }

  Timer { id: verifySave; interval: 150; onTriggered: previewFile.reload() }

  // Escape asks twice before discarding a dirty edit.
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
  // ---------------------------------------------------------- rename, delete
  // Rename and create share the header's editable name field.
  property string naming: ""
  property string renameTo: ""
  property int renameAt: 0

  function beginRename() {
    if (!root.sel || root.editing) return
    root.renameTo = root.sel.name
    var dot = root.renameTo.lastIndexOf(".")
    root.renameAt = dot > 0 ? dot : root.renameTo.length
    root.naming = "rename"
  }

  function beginNew() {
    if (root.editing) return
    root.renameTo = ""
    root.renameAt = 0
    root.naming = "new"
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
      // Pasted paths become plain names.
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

  function commitName() {
    var verb = root.naming
    var name = root.renameTo.trim()
    root.naming = ""
    // `/` forces a folder and `.` forces a file; otherwise infer from extension.
    var slashed = verb === "new" && name.slice(-1) === "/"
    var dotted = verb === "new" && !slashed && name.slice(-1) === "."
    if (slashed || dotted) name = name.slice(0, -1).trim()
    if (!name) return
    if (name.indexOf("/") !== -1) { ops.note("a name cannot hold a /"); return }
    if (verb === "new") {
      var folder = slashed || (!dotted && name.indexOf(".") < 0)
      ops.run(["sh", "-c", '[ -e "$2" ] && exit 17; exec "$1" -- "$2"',
                "files", folder ? "mkdir" : "touch", ops.inHere(name)],
               { name: name, land: true, done: "made " + name, fail: "could not make " + name })
      return
    }
    var e = root.sel
    if (!e || name === e.name) return
    ops.run(ops.guarded("mv", e.path, ops.inHere(name)),
             { name: name, land: true, done: "renamed to " + name, fail: "rename failed" })
  }
  FilesOps { id: ops; panel: root }
  readonly property alias held: ops.held
  readonly property alias fileNote: ops.fileNote
  readonly property alias doomed: ops.doomed
  readonly property alias doomedName: ops.doomedName
  readonly property alias danger: ops.danger

  FolderListModel {
    id: folder
    folder: "file://" + root.listedDir
    showDirsFirst: true
    showDotAndDotDot: false
    showHidden: root.showHidden
    sortField: FolderListModel.Name
    // Ready gates both initial loads and later count changes.
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
    // Preserve the old file if a write stops partway.
    atomicWrites: true
    onLoaded: {
      root.utf8 = FilesIndex.isUtf8(data())
      root.fullText = FilesIndex.looksBinary(text()) ? "" : text()
      // Typing during save verification leaves the editor dirty.
      if (root.saving !== null) {
        root.saveError = root.fullText !== root.saving
        root.dirty = root.saveError || FilesIndex.endLine(preview.editorText) !== root.saving
        if (!root.saveError) savedFlash.restart()
        root.saving = null
      }
    }
    onLoadFailed: root.fullText = ""
  }

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

    // Share the bar scrim so panel handoffs do not flash the desktop.
    onVisibleChanged: {
      var bar = root.shell && root.shell.bar
      if (bar && typeof bar.panelSurfaceVisible === "function") bar.panelSurfaceVisible(visible)
    }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(root.listWidth + root.previewWidth + Style.spacing.huge
                      + Style.spacing.lg * 2 + Style.spacing.panelPadding * 2,
                      surface.width * 0.92)
      height: Math.min(Style.space(900), surface.height * 0.80)
      radius: Style.space(24)
      color: Util.alpha(Color.menu.background, 0.94)
      borderSpec: Border.flat(root.edge, Style.spacing.hairline)

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        anchors.bottomMargin: Style.spacing.xl
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) { FilesKeys.onKey(root, ops, preview, event) }

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
            operations: ops
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
