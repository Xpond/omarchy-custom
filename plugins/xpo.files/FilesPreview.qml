import QtQuick
import qs.Commons
import "FilesIndex.js" as FilesIndex

// Preview and edit the selected entry through one shared scroller.
Item {
  id: root

  property var panel: null
  clip: true

  readonly property real pageStep: scroller.height * 0.9
  readonly property real panStep: Style.space(60)
  readonly property real paneWidth: scroller.width
  readonly property real paneHeight: scroller.height
  readonly property int imageStatus: scrollerImage.status
  property alias editorText: editor.text
  readonly property string lineNumbers:
    panel.editing ? FilesIndex.numbers(editor.text)
    : panel.showsMarkdown ? "" : FilesIndex.numbers(panel.previewText)

  // StyledText sets each line's baseline at its ascent. The rich text it replaced
  // set it 4/5 down a fixed-height line whatever the fonts; keep that placement.
  // Measured as each layout starts: a binding could still hold the previous font.
  property real codeBaseline: 0
  property real codeAscent: 0
  property var codeLines: []
  // Text lays out only once its implicit size is wanted, and baselineOffset needs the layout.
  Text {
    id: probe
    visible: false
    width: implicitWidth
    textFormat: Text.StyledText
    renderType: Text.NativeRendering
  }

  function measure(markup) {
    root.codeLines = markup.split("<br>")
    root.codeBaseline = Math.floor(rendered.lineHeight * 256 / 5) / 64
    probe.font = rendered.font
    probe.text = "x"
    root.codeAscent = probe.baselineOffset
  }

  // Printable ASCII is drawn in the code font; anything else may fall back to another.
  // Every line but the last also ends in a line separator drawn in the code font.
  function ascentOf(n) {
    var markup = root.codeLines[n]
    if (!/[^\x20-\x7e]|&#(?!(?:32|9|39);)/.test(markup)) return root.codeAscent
    probe.text = markup
    return n < root.codeLines.length - 1 ? Math.max(root.codeAscent, probe.baselineOffset)
                                         : probe.baselineOffset
  }

  function scrollBy(dy) {
    scroller.contentY = Util.clamp(scroller.contentY + dy, 0,
                                   Math.max(0, scroller.contentHeight - scroller.height))
  }

  function scrollAcross(dx) {
    scroller.contentX = Util.clamp(scroller.contentX + dx, 0,
                                   Math.max(0, scroller.contentWidth - scroller.width))
  }

  function resetScroll() { scroller.contentY = 0; scroller.contentX = 0 }

  function scrollTo(fraction) {
    // The end of a partly laid out file waits for the rest.
    if (fraction === 1 && panel.previewCut) {
      root.pendingAt = 1
      panel.showAll()
      return
    }
    scroller.contentY = fraction * Math.max(0, scroller.contentHeight - scroller.height)
    scroller.contentX = 0
  }

  // Preserve relative scroll position while rendered and editable heights change.
  property real pendingAt: -1
  function keepPlace() {
    var at = Util.clamp(scroller.contentY / Math.max(1, scroller.contentHeight - scroller.height), 0, 1)
    // A partly laid out file is only its share of the text.
    root.pendingAt = panel.previewCut ? at * panel.previewText.length / panel.fullText.length : at
  }
  function takePlace() {
    if (root.pendingAt < 0) return
    scroller.contentY = root.pendingAt * Math.max(0, scroller.contentHeight - scroller.height)
    scroller.contentX = 0
    root.pendingAt = -1
    if (panel.editing)
      editor.cursorPosition = editor.positionAt(0, Math.max(0, scroller.contentY - panel.dirTopPad + 2))
  }

  function focusEditor() { editor.forceActiveFocus() }

  // Lay out more of a long file once the view comes within a screen of its end.
  function fill() {
    if (panel.previewCut && !panel.editing && scroller.contentY + scroller.height * 2 > scroller.contentHeight)
      panel.shownLines *= 2
  }

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
  // Keep code unwrapped so line numbers stay aligned.
  Flickable {
    id: scroller
    anchors {
      top: parent.top; bottom: parent.bottom
      left: parent.left; leftMargin: Style.spacing.lg
      right: parent.right; rightMargin: Style.spacing.lg
    }
    visible: panel.showsDir || panel.showsCode || !!panel.previewBody || panel.editing
    contentWidth: panel.showsDir ? folderView.width : content.width
    // Include both vertical insets so the last line remains reachable.
    contentHeight: (panel.showsDir ? folderView.height : content.height)
                   + panel.dirTopPad * 2
    onContentHeightChanged: { root.takePlace(); root.fill() }
    onContentYChanged: root.fill()
    flickableDirection: Flickable.HorizontalAndVerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true

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
      y: panel.dirTopPad
      spacing: panel.gutterGap

      Text {
        visible: root.lineNumbers.length > 0
        text: root.lineNumbers
        horizontalAlignment: Text.AlignRight
        color: Color.menu.text
        opacity: 0.32
        font.family: Style.font.menuFamily
        // Match the gutter rhythm to editable text or fixed-height preview code.
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
        persistentSelection: true
        textFormat: TextEdit.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        renderType: Text.NativeRendering
        onTextChanged: if (panel.editing) panel.dirty = true
        onCursorRectangleChanged: root.revealCursor()
      }

      // Markdown has its own Text: a line height that switched with the format, or a handler
      // per line, made Qt lay out its tables many times slower.
      Text {
        visible: !panel.editing && panel.showsMarkdown
        width: scroller.width
        text: panel.showsMarkdown ? panel.previewBody : ""
        wrapMode: Text.Wrap
        textFormat: Text.MarkdownText
        color: Color.menu.text
        opacity: 0.92
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        renderType: Text.NativeRendering
      }

      Text {
        id: rendered
        visible: !panel.editing && !panel.showsMarkdown
        text: panel.showsMarkdown ? "" : panel.previewBody
        color: Color.menu.text
        opacity: 0.92
        textFormat: panel.showsCode ? Text.StyledText : Text.PlainText
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        renderType: Text.NativeRendering
        lineHeightMode: Text.FixedHeight
        lineHeight: panel.lineHeight
        onLineLaidOut: function (line) {
          if (!panel.showsCode) return
          if (line.number === 0) root.measure(text)
          // Absolute: Text has already lowered the line to the foot of its fixed height.
          line.y = line.number * lineHeight + root.codeBaseline - root.ascentOf(line.number)
        }
      }
    }
  }

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
    // Unsupported or corrupt images fall through to the preview note.
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
