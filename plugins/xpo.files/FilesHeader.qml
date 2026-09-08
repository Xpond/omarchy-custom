import QtQuick
import qs.Commons
import "FilesIndex.js" as FilesIndex

// Where you are, spelled as the trail you walked rather than as one string:
// the leaf at full strength, everything behind it dimmed to context. One line,
// because the path is the only thing that has to be legible at a glance and a
// second row of chrome would push the list down.
//
// The right end is the preview's heading, over the column it describes. It used
// to sit inside the preview under a rule of its own, which made the card look
// like it had two headers and drew a line across the page for no one.
Item {
  id: root

  property var panel: null

  height: Style.font.title + Style.spacing.controlPaddingY * 2
  // A path deep enough to reach the preview's heading is cut off at the column
  // boundary rather than allowed to run through it.
  clip: true

  // One caret, blinking in one place: at the end of the path you are typing, or
  // in the filter chip. Both wear the same beat rather than each running a
  // timer of its own.
  property bool caretLit: true
  Timer {
    running: panel.opened && (!!panel.naming || panel.filter.length > 0)
    interval: 530
    repeat: true
    onTriggered: root.caretLit = !root.caretLit
    onRunningChanged: root.caretLit = true
  }

  component Caret: Rectangle {
    width: Style.space(2)
    height: Style.font.subtitle
    color: Color.accent
    opacity: caretLit ? 0.85 : 0.0
  }

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
        model: panel.crumbs

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
            opacity: !panel.pathMode && index === panel.crumbs.length - 1 ? 0.95 : 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
          }
        }
      }

      // The tail of a typed path, written as the next segment of the
      // trail it extends. The crumbs already ARE the path typed so far;
      // this is only the word they do not know yet.
      Row {
        visible: panel.pathMode
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
          text: panel.typedLeaf
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
      // The same pill holds the new name while one is being typed -- see
      // `beginRename`. It is lit differently so that a rename in progress can
      // never be mistaken for a filter narrowing the list.
      visible: !!panel.naming || (panel.filter.length > 0 && !panel.pathMode)
      anchors.verticalCenter: parent.verticalCenter
      width: field.width + Style.spacing.md * 2
      height: Style.font.subtitle + Style.spacing.sm * 2
      radius: height / 2
      color: panel.naming ? Util.alpha(Color.accent, 0.16)
                            : Util.alpha(Color.menu.text, 0.07)

      // Written in two halves with the caret between them, so it stands where
      // the next character will go rather than always at the end. A filter is
      // only ever typed at, so its caret is always the trailing one.
      Row {
        id: field
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: panel.naming ? panel.renameTo.slice(0, panel.renameAt) : panel.filter
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
        }

        Caret { anchors.verticalCenter: parent.verticalCenter }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: panel.naming ? panel.renameTo.slice(panel.renameAt) : ""
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
        }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: FilesIndex.countLabel(panel.rows.length, panel.entries.length,
                                  panel.query, panel.showHidden, panel.order)
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
    visible: !!panel.settledSel

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: panel.editing || !!panel.fileNote
      text: !panel.editing ? panel.fileNote
            : panel.saveError ? "write failed"
            : savedFlash.running ? "saved"
            : panel.dirty ? "unsaved" : "editing"
      color: panel.saveError ? Color.menu.text : Color.accent
      opacity: 0.85
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.round(panel.previewWidth * 0.6))
      elide: Text.ElideMiddle
      text: panel.settledSel ? panel.settledSel.name : ""
      color: Color.menu.text
      opacity: 0.9
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: panel.metaLine
      color: Color.menu.text
      opacity: 0.5
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
