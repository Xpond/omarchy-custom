import QtQuick
import qs.Commons
import "FilesIndex.js" as FilesIndex

Item {
  id: root

  property var panel: null

  height: Style.font.title + Style.spacing.controlPaddingY * 2
  clip: true

  // Path, filter and rename share one caret timer.
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

  component Separator: Text {
    text: "/"
    color: Color.menu.text
    opacity: 0.22
    leftPadding: Style.spacing.sm
    rightPadding: Style.spacing.sm
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.subtitle
  }

  // Keep the count beside the path so it cannot be mistaken for preview metadata.
  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    // Separate the count from the path's trailing caret.
    spacing: Style.spacing.xxl

    Row {
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        model: panel.crumbs

        delegate: Row {
          required property int index
          required property string modelData

          Separator {
            visible: index > 0
          }

          Text {
            text: modelData
            color: Color.menu.text
            // Only the unfinished path segment is active during completion.
            opacity: !panel.pathMode && index === panel.crumbs.length - 1 ? 0.95 : 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
          }
        }
      }

      // Completed segments are already in the breadcrumbs.
      Row {
        visible: panel.pathMode

        Separator {}

        Text {
          text: panel.typedLeaf
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
        }

        Caret { anchors.verticalCenter: parent.verticalCenter }
      }
    }

    // A pill distinguishes the filter even when accent and foreground match.
    Rectangle {
      // Rename uses a separate colour so it cannot be mistaken for filtering.
      visible: !!panel.naming || (panel.filter.length > 0 && !panel.pathMode)
      anchors.verticalCenter: parent.verticalCenter
      width: field.width + Style.spacing.md * 2
      height: Style.font.subtitle + Style.spacing.sm * 2
      radius: height / 2
      color: panel.naming ? Util.alpha(Color.accent, 0.16)
                            : Util.alpha(Color.menu.text, 0.07)

      // Rename has a movable caret; filtering appends at the end.
      Row {
        id: field
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter

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
            : panel.fileNote ? panel.fileNote
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
