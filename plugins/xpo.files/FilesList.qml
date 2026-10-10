import QtQuick
import qs.Commons
import "FilesIndex.js" as FilesIndex

Item {
  property var panel: null
  property var operations: null
  property alias view: list

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    model: panel.rows
    currentIndex: panel.index
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: entry
      required property int index
      required property var modelData
      readonly property bool active: panel.index === entry.index
      readonly property bool doomed: panel.doomed === entry.modelData.path

      width: list.width
      height: panel.rowHeight

      // Match the wheel's selection capsule, stopping before the preview.
      Rectangle {
        anchors.fill: parent
        anchors.rightMargin: Style.spacing.md
        radius: height / 2
        color: entry.doomed ? Util.alpha(panel.danger, 0.30)
               : entry.active ? panel.activeFill
               : (pointer.containsMouse ? panel.hoverFill : "transparent")
        border.width: entry.active ? Style.spacing.hairline : 0
        border.color: entry.doomed ? panel.danger : Color.accent
      }

      MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: function (mouse) {
          if (panel.hoverMoved(mapToItem(null, mouse.x, mouse.y))) { panel.pending = ""; panel.index = entry.index }
        }
        onClicked: operations.activate(entry.modelData)
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.rowPaddingX + Style.spacing.md
        spacing: Style.spacing.controlGap

        // Folder colour remains distinct in a list of files.
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
                 - (mark.visible ? mark.width + parent.spacing : 0)
          elide: Text.ElideRight
          text: entry.modelData.name
          color: entry.active ? Color.menu.selectedText : Color.menu.text
          opacity: entry.active ? 1.0 : (entry.modelData.isDir ? 0.88 : 0.66)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }

        // Uncommitted changes: git's letter on a file, a dot on a folder holding some.
        Text {
          id: mark
          anchors.verticalCenter: parent.verticalCenter
          visible: !!text
          text: panel.changes[entry.modelData.name] || ""
          color: Color.accent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }

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

  // Show the scroll position in long directories.
  Rectangle {
    visible: list.contentHeight > list.height + 1
    anchors.right: list.right
    anchors.rightMargin: Style.spacing.xs
    width: Style.space(2)
    radius: width / 2
    color: Util.alpha(Color.menu.text, 0.18)
    height: Math.max(Style.space(24),
                     list.height * list.height / Math.max(1, list.contentHeight))
    y: (list.contentY / Math.max(1, list.contentHeight - list.height))
       * (list.height - height)
  }
}
