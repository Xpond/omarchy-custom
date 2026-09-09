import QtQuick
import qs.Commons
import "FilesIndex.js" as FilesIndex

// What the selection is, without opening it. A directory shows what is inside,
// an image shows itself, and text shows its top; anything else has only its
// name and size to give, and says so rather than drawing a screen of mojibake.
//
// This owns the scroller and the editor inside it, so the panel asks for
// movement rather than reaching into a Flickable: scrollBy, keepPlace, and the
// editor verbs are the whole of the surface between them.
Item {
  id: root

  property var panel: null
  clip: true

  readonly property real pageStep: scroller.height * 0.9
  readonly property real panStep: Style.space(60)
  // The scroller's own box, not this Item's: the two differ by the margins the
  // text is inset by, and the directory listing lays its columns out in
  // characters that have to fit the narrower one.
  readonly property real paneWidth: scroller.width
  readonly property real paneHeight: scroller.height
  // An id belongs to the document it is written in, so the panel's fallback
  // note cannot reach `scrollerImage` and is handed what it asks of it.
  readonly property int imageStatus: scrollerImage.status
  property alias editorText: editor.text
  readonly property string lineNumbers:
    panel.editing ? FilesIndex.numbers(editor.text)
    : panel.showsMarkdown ? "" : FilesIndex.numbers(panel.previewText)

  function scrollBy(dy) {
    scroller.contentY = Util.clamp(scroller.contentY + dy, 0,
                                   Math.max(0, scroller.contentHeight - scroller.height))
  }

  function scrollAcross(dx) {
    scroller.contentX = Util.clamp(scroller.contentX + dx, 0,
                                   Math.max(0, scroller.contentWidth - scroller.width))
  }

  function resetScroll() { scroller.contentY = 0; scroller.contentX = 0 }

  // The two ends, as the fraction `keepPlace` already thinks in.
  function scrollTo(fraction) {
    scroller.contentY = fraction * Math.max(0, scroller.contentHeight - scroller.height)
    scroller.contentX = 0
  }

  // Where you were reading, kept across the switch between the rendering and
  // the source. The two have nothing like the same height, so the offset cannot
  // be carried but the fraction of the way down can. Applied when the scroller
  // re-measures: at the moment the mode flips, contentHeight is still the
  // other mode's.
  property real pendingAt: -1
  function keepPlace() {
    root.pendingAt = Util.clamp(scroller.contentY
                                / Math.max(1, scroller.contentHeight - scroller.height), 0, 1)
  }
  function takePlace() {
    if (root.pendingAt < 0) return
    scroller.contentY = root.pendingAt * Math.max(0, scroller.contentHeight - scroller.height)
    scroller.contentX = 0
    root.pendingAt = -1
    // The caret lands on the line you were reading, so the first thing you
    // type goes where you were looking.
    if (panel.editing)
      editor.cursorPosition = editor.positionAt(0, Math.max(0, scroller.contentY - panel.dirTopPad + 2))
  }

  function focusEditor() { editor.forceActiveFocus() }
  function copy() { editor.copy() }
  function cut() { editor.cut() }
  function paste() { editor.paste() }
  function selectAll() { editor.selectAll() }

  function revealCursor() {
    if (!panel.editing) return
    var r = editor.cursorRectangle
    var top = content.y + editor.y + r.y
    if (top < scroller.contentY) root.scrollBy(top - scroller.contentY)
    else if (top + r.height > scroller.contentY + scroller.height)
      root.scrollBy(top + r.height - scroller.contentY - scroller.height)
    var left = editor.x + r.x
    if (left < scroller.contentX) root.scrollAcross(left - scroller.contentX - Style.space(40))
    else if (left + r.width > scroller.contentX + scroller.width)
      root.scrollAcross(left + r.width - scroller.contentX - scroller.width + Style.space(40))
  }


  // No wrapping: a wrapped line is one the numbers beside it stop
  // agreeing with, and code read at the wrong margins is worse than
  // code read short. What runs off the edge is reachable by
  // dragging, or by Shift and an arrow.
  Flickable {
    id: scroller
    // Neither the numbers nor the prose should start hard against
    // the edge the column was cut at.
    anchors {
      top: parent.top; bottom: parent.bottom
      left: parent.left; leftMargin: Style.spacing.lg
      right: parent.right; rightMargin: Style.spacing.lg
    }
    visible: panel.showsDir || !!panel.previewBody || panel.editing
    contentWidth: panel.showsDir ? folderView.width : content.width
    // The content sits `dirTopPad` down the scroller, so its height
    // is not the height of what is being scrolled: uncounted, the
    // last line of the file cannot be reached. Counted twice, so the
    // closing line gets the air the opening one stands in.
    contentHeight: (panel.showsDir ? folderView.height : content.height)
                   + panel.dirTopPad * 2
    onContentHeightChanged: root.takePlace()
    flickableDirection: Flickable.HorizontalAndVerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    // The folder, in columns, starting where the pane starts. It is
    // the width of the facts that fills a pane, not the position of
    // the block: centred, the space between the two columns of the
    // card read as a channel of dead ground.
    Row {
      id: folderView
      visible: panel.showsDir
      y: panel.dirTopPad
      spacing: panel.gutterGap * 2

      Repeater {
        model: panel.dirColumns

        delegate: Text {
          required property string modelData
          text: modelData
          color: Color.menu.text
          opacity: 0.92
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          renderType: Text.NativeRendering
          lineHeightMode: Text.FixedHeight
          lineHeight: panel.lineHeight
        }
      }
    }

    Row {
      id: content
      visible: !panel.showsDir
      // The same nudge the folder gets, so arrowing from a folder to
      // a file does not step the preview up the page.
      y: panel.dirTopPad
      spacing: panel.gutterGap

      Text {
        visible: root.lineNumbers.length > 0
                 && (!panel.showsMarkdown || panel.editing)
        text: root.lineNumbers
        horizontalAlignment: Text.AlignRight
        color: Color.menu.text
        opacity: 0.32
        font.family: Style.font.menuFamily
        // TextEdit carries no lineHeight, so an edited file is set at
        // the font's own leading -- which follows its size, so the
        // gutter has to be set at the size it is numbering or the two
        // drift apart down the page. The preview's fixed rhythm does
        // that job itself, and lets the numbers be smaller there.
        font.pixelSize: panel.editing ? Style.font.subtitle : Style.font.bodySmall
        renderType: Text.NativeRendering
        lineHeightMode: panel.editing ? Text.ProportionalHeight : Text.FixedHeight
        lineHeight: panel.editing ? 1.0 : panel.lineHeight
      }

      TextEdit {
        id: editor
        visible: panel.editing
        color: Color.menu.text
        opacity: 0.92
        selectionColor: Util.alpha(Color.accent, 0.35)
        selectedTextColor: Color.menu.text
        selectByMouse: true
        persistentSelection: true
        wrapMode: Text.NoWrap
        textFormat: TextEdit.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        renderType: Text.NativeRendering
        onTextChanged: if (panel.editing) panel.dirty = true
        onCursorRectangleChanged: root.revealCursor()
      }

      Text {
        visible: !panel.editing
        text: panel.previewBody
        color: Color.menu.text
        opacity: 0.92
        // Prose wraps to the pane and flows; code keeps its own line
        // breaks and scrolls sideways past the edge.
        width: panel.showsMarkdown ? scroller.width : implicitWidth
        wrapMode: panel.showsMarkdown ? Text.Wrap : Text.NoWrap
        textFormat: panel.showsMarkdown ? Text.MarkdownText
                    : panel.showsCode ? Text.RichText
                    : Text.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        // Hinted against the pixel grid rather than distance-field
        // sampled. It is what makes small monospace look set rather
        // than printed slightly out of focus.
        renderType: Text.NativeRendering
        // A rendered heading is taller than a line of body text and
        // has to be allowed to be; only code wants a fixed rhythm.
        lineHeightMode: panel.showsMarkdown ? Text.ProportionalHeight
                                           : Text.FixedHeight
        lineHeight: panel.showsMarkdown ? 1.0 : panel.lineHeight
      }
    }
  }

  // The only thing that tells you there is more below, and where in
  // it you are standing.
  Rectangle {
    anchors.right: parent.right
    visible: scroller.visible && scroller.contentHeight > scroller.height + 1
    width: Style.space(2)
    radius: width / 2
    color: Util.alpha(Color.menu.text, 0.22)
    height: Math.max(Style.space(24),
                     scroller.height * scroller.height / Math.max(1, scroller.contentHeight))
    y: (scroller.contentY / Math.max(1, scroller.contentHeight - scroller.height))
       * (scroller.height - height)
  }

  Image {
    id: scrollerImage
    anchors.fill: parent
    // A format Qt has no plugin for, or a corrupt file, must fall
    // through to the note rather than leaving an empty frame.
    visible: panel.showsImage && status !== Image.Error
    source: panel.showsImage ? "file://" + panel.settledSel.path : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    sourceSize.width: width
    sourceSize.height: height
  }

  Text {
    anchors.centerIn: parent
    visible: !!panel.previewNote
    text: panel.previewNote
    color: Color.menu.text
    opacity: 0.45
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }
}
