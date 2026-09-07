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
// Deliberately a browser and not a manager. Nothing here renames, copies or
// deletes -- those are the operations that cost you data when they are wrong,
// and yazi is installed and already does them properly. This answers where is
// it, what is in it, and open it, which is what a file manager is actually
// reached for.
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

  // One caret, blinking in one place: at the end of the path you are typing, or
  // in the filter chip. Hoisted here so both wear the same beat rather than
  // each running a timer of its own.
  property bool caretLit: true
  Timer {
    running: root.opened && root.filter.length > 0
    interval: 530
    repeat: true
    onTriggered: root.caretLit = !root.caretLit
    onRunningChanged: root.caretLit = true
  }

  component Caret: Rectangle {
    width: Style.space(2)
    height: Style.font.subtitle
    color: Color.accent
    opacity: root.caretLit ? 0.85 : 0.0
  }

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
  property string previewText: ""
  onPreviewPathChanged: { root.previewText = ""; root.previewHtml = "" }

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
  readonly property int dirRows: Math.max(1, Math.floor(preview.height / root.lineHeight))
  readonly property int dirPaneChars: Math.max(20, Math.floor(preview.width / codeMetrics.advanceWidth))
  readonly property var dirColumns: root.showsDir
    ? FilesIndex.columns(root.dirEntries, root.dirRows, root.dirPaneChars, 400) : []
  // A line of text sits at the top of its line box; a list row sits in the
  // middle of a taller one. Without this the first file in the preview floats
  // above the first file in the list.
  readonly property int dirTopPad: Math.max(0, Math.round((root.rowHeight - codeMetrics.height) / 2))
  readonly property string previewBody:
    root.showsMarkdown ? FilesIndex.airOut(FilesIndex.flattenLinks(root.previewText))
    : root.showsCode
      ? FilesIndex.codeHtml(root.previewHtml || FilesIndex.escapeHtml(root.previewText),
                            Style.font.menuFamily, Style.font.subtitle)
      : ""
  readonly property string previewNumbers: root.showsMarkdown
    ? "" : FilesIndex.numbers(root.previewText)
  onSelChanged: settle.restart()
  // Cleared here rather than left for the model to overwrite: the child model
  // only reports Ready, so between two folders the old folder's contents would
  // otherwise sit under the new folder's name.
  onSettledSelChanged: {
    preview.contentY = 0
    preview.contentX = 0
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
    !root.settledSel ? (root.query ? "No match" : "Empty")
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
    Qt.callLater(function () { keys.forceActiveFocus() })
  }

  // A name to land on once the directory has been read, which is how the wheel
  // hands a file over: the browser opens where the file lives with the file
  // itself selected, so the preview is showing it before you have touched a
  // key. Cleared on arrival, so it claims the selection once and never again.
  property string pending: ""
  function claimPending() {
    if (!root.pending) return
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].name === root.pending) { root.index = i; break }
    }
    root.pending = ""
    list.positionViewAtIndex(root.index, ListView.Contain)
  }

  function close() { root.opened = false }

  // Closing lets go of what the preview was holding -- the file's bytes, the
  // folder's entries, the image -- and cancels a settle that would otherwise
  // read a directory for a panel nobody is looking at. Every open starts at
  // home, so none of it would have been reused.
  onOpenedChanged: if (!root.opened) { settle.stop(); root.settledSel = null }
  function toggle() { root.opened ? root.close() : root.open("{}") }

  // Moving house: the filter belongs to the directory it was typed in, and
  // carrying it into the next one hides everything on arrival.
  function enter(next) {
    var path = String(next).replace(/\/+$/, "")
    root.dir = FilesIndex.within(path || "/", root.home)
    root.filter = ""
    root.index = 0
  }

  function up() { root.enter(FilesIndex.parentOf(root.dir)) }

  function move(step) {
    var n = root.rows.length
    if (n > 0) root.index = (root.index + step + n) % n
    list.positionViewAtIndex(root.index, ListView.Contain)
  }

  // The preview scrolls under the keyboard, because a preview you can only see
  // the top of is a thumbnail. Clamped by hand rather than left to the
  // Flickable, which would rubber-band past the end and settle back.
  function scrollBy(dy) {
    preview.contentY = Util.clamp(preview.contentY + dy, 0,
                                  Math.max(0, preview.contentHeight - preview.height))
  }

  function scrollAcross(dx) {
    preview.contentX = Util.clamp(preview.contentX + dx, 0,
                                  Math.max(0, preview.contentWidth - preview.width))
  }

  // A directory is somewhere to go; a file is something to hand off -- when the
  // desktop has an app for it. Nothing here opens an editor: a text file is
  // already open in the pane on the right. The panel steps aside only when
  // something is taking over, which is what the opener's exit code says: zero
  // means a viewer is coming, 3 that it declined and this keeps its place.
  function activate(e) {
    if (!e) return
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
    path: root.previewPath
    printErrors: false
    onLoaded: root.previewText = FilesIndex.looksBinary(text()) ? "" : FilesIndex.head(text(), root.previewLines)
    onLoadFailed: root.previewText = ""
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
          if (event.modifiers & Qt.ControlModifier) {
            switch (event.key) {
            case Qt.Key_H: root.showHidden = !root.showHidden; event.accepted = true; return
            case Qt.Key_U: root.filter = ""; event.accepted = true; return
            }
          }
          // Shift turns the arrows on the preview instead of the list. Held
          // down, it is the one modifier that reads as "the other pane".
          if (event.modifiers & Qt.ShiftModifier) {
            switch (event.key) {
            case Qt.Key_Down:  root.scrollBy(root.lineHeight * 3); event.accepted = true; return
            case Qt.Key_Up:    root.scrollBy(-root.lineHeight * 3); event.accepted = true; return
            case Qt.Key_Right: root.scrollAcross(Style.space(60)); event.accepted = true; return
            case Qt.Key_Left:  root.scrollAcross(-Style.space(60)); event.accepted = true; return
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
          case Qt.Key_PageDown: root.scrollBy(preview.height * 0.9); event.accepted = true; return
          case Qt.Key_PageUp:   root.scrollBy(-preview.height * 0.9); event.accepted = true; return
          case Qt.Key_Home:  root.enter(root.home); event.accepted = true; return
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

        // ------------------------------------------------------------ header
        //
        // Where you are, spelled as the trail you walked rather than as one
        // string: the leaf at full strength, everything behind it dimmed to
        // context. One line, because the path is the only thing that has to be
        // legible at a glance and a second row of chrome would push the list
        // down.
        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: Style.font.title + Style.spacing.controlPaddingY * 2
          // A path deep enough to reach the preview's heading is cut off at
          // the column boundary rather than allowed to run through it.
          clip: true

          // Path, query, count: one left-flowing group. Right-aligning the
          // count instead put it directly above the preview's own size and
          // date, where two dim figures in a column read as two facts about one
          // file -- and squeezing it over the narrow list column alone leaves
          // it nowhere to go the moment the path or the query grows.
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // Wide enough that the count is not read as part of the path the
            // caret is still sitting at the end of.
            spacing: Style.spacing.xxl

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Repeater {
                model: root.crumbs

                delegate: Row {
                  required property int index
                  required property string modelData
                  spacing: 0

                  Text {
                    visible: index > 0
                    text: "/"
                    color: Color.menu.text
                    opacity: 0.22
                    leftPadding: Style.spacing.sm
                    rightPadding: Style.spacing.sm
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.subtitle
                  }

                  Text {
                    text: modelData
                    color: Color.menu.text
                    // While a path is being typed the trail is all context and
                    // the tail is the live word, so nothing in the trail is lit.
                    opacity: !root.pathMode && index === root.crumbs.length - 1 ? 0.95 : 0.5
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.subtitle
                  }
                }
              }

              // The tail of a typed path, written as the next segment of the
              // trail it extends. The crumbs already ARE the path typed so far;
              // this is only the word they do not know yet.
              Row {
                visible: root.pathMode
                spacing: 0

                Text {
                  text: "/"
                  color: Color.menu.text
                  opacity: 0.22
                  leftPadding: Style.spacing.sm
                  rightPadding: Style.spacing.sm
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.subtitle
                }

                Text {
                  text: root.typedLeaf
                  color: Color.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.subtitle
                }

                Caret { anchors.verticalCenter: parent.verticalCenter }
              }
            }

            // What you have typed to narrow the list. It sits in a pill of its
            // own rather than trusting the accent to distinguish it: plenty of
            // themes set `accent` to the same colour as the foreground, and
            // then a coloured word next to the path is just another segment.
            Rectangle {
              visible: root.filter.length > 0 && !root.pathMode
              anchors.verticalCenter: parent.verticalCenter
              width: filterText.width + caret.width + Style.spacing.xs + Style.spacing.md * 2
              height: Style.font.subtitle + Style.spacing.sm * 2
              radius: root.rowRadius
              color: Util.alpha(Color.menu.text, 0.07)

              Text {
                id: filterText
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: root.filter
                color: Color.accent
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.subtitle
              }

              Caret {
                id: caret
                anchors.left: filterText.right
                anchors.leftMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: FilesIndex.countLabel(root.rows.length, root.entries.length,
                                          root.query, root.showHidden)
              color: Color.menu.text
              opacity: 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // The preview's own heading, on the same line as the path and over
          // the column it describes. It used to sit inside the preview under a
          // rule of its own, which made the card look like it had two headers
          // and drew a line across the page for no one.
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg
            visible: !!root.settledSel

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, Math.round(root.previewWidth * 0.6))
              elide: Text.ElideMiddle
              text: root.settledSel ? root.settledSel.name : ""
              color: Color.menu.text
              opacity: 0.9
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.metaLine
              color: Color.menu.text
              opacity: 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
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

          ListView {
            id: list
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: root.listWidth
            clip: true
            model: root.rows
            currentIndex: root.index
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: entry
              required property int index
              required property var modelData
              readonly property bool active: root.index === entry.index

              width: list.width
              height: root.rowHeight

              // The fill stops short of the preview so the selection never
              // touches it; the bar is what your eye actually lands on.
              Rectangle {
                anchors.fill: parent
                anchors.rightMargin: Style.spacing.md
                radius: root.rowRadius
                color: entry.active ? root.activeFill
                                    : (pointer.containsMouse ? root.hoverFill : "transparent")
              }

              Rectangle {
                visible: entry.active
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(2)
                height: Math.round(parent.height * 0.5)
                radius: width / 2
                color: Color.accent
              }

              MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                // positionChanged, not entered: retyping a query re-lays the
                // rows out under a cursor that has not moved, and `entered`
                // fires on every row that slides beneath it -- which drags the
                // selection around mid-keystroke and leaves you unsure what
                // Return will run. Real pointer motion is the only thing that
                // should claim it.
                onPositionChanged: function (mouse) {
                  if (root.hoverMoved(mapToItem(null, mouse.x, mouse.y))) root.index = entry.index
                }
                onClicked: root.activate(entry.modelData)
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.rowPaddingX + Style.spacing.md
                spacing: Style.spacing.controlGap

                // Folders carry a little of the accent even when they are not
                // selected. It is the only cue that survives a list where every
                // other row is a file with a long ordinary name.
                Text {
                  id: glyph
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.iconLarge
                  text: entry.modelData.isDir ? "󰉋" : "󰈔"
                  color: entry.active ? Color.accent
                         : entry.modelData.isDir ? Util.alpha(Color.accent, 0.55)
                         : Util.alpha(Color.menu.text, 0.35)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.iconLarge
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - glyph.width - trail.width - parent.spacing * 2
                  elide: Text.ElideRight
                  text: entry.modelData.name
                  color: entry.active ? Color.menu.selectedText : Color.menu.text
                  opacity: entry.active ? 1.0 : (entry.modelData.isDir ? 0.88 : 0.66)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }

                // A size for files. For the folder you are standing on, the
                // chevron that says Return goes in there.
                Text {
                  id: trail
                  anchors.verticalCenter: parent.verticalCenter
                  text: entry.modelData.isDir
                        ? (entry.active ? "›" : "")
                        : FilesIndex.humanSize(entry.modelData.size)
                  color: entry.active ? Color.accent : Color.menu.text
                  opacity: entry.active ? 0.75 : 0.45
                  font.family: Style.font.menuFamily
                  font.pixelSize: entry.modelData.isDir ? Style.font.body : Style.font.bodySmall
                }
              }
            }
          }

          // The same indicator the preview carries, for the same reason: a
          // directory of 977 files is otherwise a list with no bottom.
          Rectangle {
            visible: list.contentHeight > list.height + 1
            anchors.right: list.right
            anchors.rightMargin: Style.spacing.xs
            width: Style.space(2)
            radius: width / 2
            color: Util.alpha(Color.menu.text, 0.18)
            height: Math.max(Style.space(24),
                             list.height * list.height / Math.max(1, list.contentHeight))
            y: list.y + (list.contentY / Math.max(1, list.contentHeight - list.height))
               * (list.height - height)
          }

          // What the selection is, without opening it. A directory shows what
          // is inside, an image shows itself, and text shows its top; anything
          // else has only its name and size to give, and says so rather than
          // drawing a screen of mojibake.
          Item {
            anchors {
              top: parent.top; bottom: parent.bottom
              left: list.right; leftMargin: Style.spacing.huge
              right: parent.right
            }
            clip: true

            // No wrapping: a wrapped line is one the numbers beside it stop
            // agreeing with, and code read at the wrong margins is worse than
            // code read short. What runs off the edge is reachable by
            // dragging, or by Shift and an arrow.
            Flickable {
              id: preview
              // Neither the numbers nor the prose should start hard against
              // the edge the column was cut at.
              anchors {
                top: parent.top; bottom: parent.bottom
                left: parent.left; leftMargin: Style.spacing.lg
                right: parent.right; rightMargin: Style.spacing.lg
              }
              visible: root.showsDir || !!root.previewBody
              contentWidth: root.showsDir ? folderView.width : content.width
              contentHeight: root.showsDir ? folderView.height : content.height
              flickableDirection: Flickable.HorizontalAndVerticalFlick
              boundsBehavior: Flickable.StopAtBounds
              clip: true

              // The folder, in columns, starting where the pane starts. It is
              // the width of the facts that fills a pane, not the position of
              // the block: centred, the space between the two columns of the
              // card read as a channel of dead ground.
              Row {
                id: folderView
                visible: root.showsDir
                y: root.dirTopPad
                spacing: root.gutterGap * 2

                Repeater {
                  model: root.dirColumns

                  delegate: Text {
                    required property string modelData
                    text: modelData
                    color: Color.menu.text
                    opacity: 0.92
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.subtitle
                    renderType: Text.NativeRendering
                    lineHeightMode: Text.FixedHeight
                    lineHeight: root.lineHeight
                  }
                }
              }

              Row {
                id: content
                visible: !root.showsDir
                // The same nudge the folder gets, so arrowing from a folder to
                // a file does not step the preview up the page.
                y: root.dirTopPad
                spacing: root.gutterGap

                Text {
                  visible: root.previewNumbers.length > 0 && !root.showsMarkdown
                  text: root.previewNumbers
                  horizontalAlignment: Text.AlignRight
                  color: Color.menu.text
                  opacity: 0.32
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.bodySmall
                  renderType: Text.NativeRendering
                  lineHeightMode: Text.FixedHeight
                  lineHeight: root.lineHeight
                }

                Text {
                  text: root.previewBody
                  color: Color.menu.text
                  opacity: 0.92
                  // Prose wraps to the pane and flows; code keeps its own line
                  // breaks and scrolls sideways past the edge.
                  width: root.showsMarkdown ? preview.width : implicitWidth
                  wrapMode: root.showsMarkdown ? Text.Wrap : Text.NoWrap
                  textFormat: root.showsMarkdown ? Text.MarkdownText
                              : root.showsCode ? Text.RichText
                              : Text.PlainText
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.subtitle
                  // Hinted against the pixel grid rather than distance-field
                  // sampled. It is what makes small monospace look set rather
                  // than printed slightly out of focus.
                  renderType: Text.NativeRendering
                  // A rendered heading is taller than a line of body text and
                  // has to be allowed to be; only code wants a fixed rhythm.
                  lineHeightMode: root.showsMarkdown ? Text.ProportionalHeight
                                                     : Text.FixedHeight
                  lineHeight: root.showsMarkdown ? 1.0 : root.lineHeight
                }
              }
            }

            // The only thing that tells you there is more below, and where in
            // it you are standing.
            Rectangle {
              anchors.right: parent.right
              visible: preview.visible && preview.contentHeight > preview.height + 1
              width: Style.space(2)
              radius: width / 2
              color: Util.alpha(Color.menu.text, 0.22)
              height: Math.max(Style.space(24),
                               preview.height * preview.height / Math.max(1, preview.contentHeight))
              y: (preview.contentY / Math.max(1, preview.contentHeight - preview.height))
                 * (preview.height - height)
            }

            Image {
              id: previewImage
              anchors.fill: parent
              // A format Qt has no plugin for, or a corrupt file, must fall
              // through to the note rather than leaving an empty frame.
              visible: root.showsImage && status !== Image.Error
              source: root.showsImage ? "file://" + root.settledSel.path : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              sourceSize.width: width
              sourceSize.height: height
            }

            Text {
              anchors.centerIn: parent
              visible: !!root.previewNote
              text: root.previewNote
              color: Color.menu.text
              opacity: 0.45
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // Every key this panel answers to, in the order you reach for them. A
        // browser with no visible verbs is one you have to remember. Key and
        // word are told apart by weight rather than by space, so the pairs
        // group themselves instead of reading as six phrases in a row.
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

        Row {
          id: hints
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xxl

          Repeater {
            model: [["↑↓", "select"], ["→", "open"], ["←", "up"],
                    ["shift+↑↓", "scroll"], ["ctrl+h", "hidden"], ["esc", "close"]]

            delegate: Row {
              required property var modelData
              spacing: Style.spacing.xs

              Text {
                text: modelData[0]
                color: Color.menu.text
                opacity: 0.72
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                text: modelData[1]
                color: Color.menu.text
                opacity: 0.36
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
