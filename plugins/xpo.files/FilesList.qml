import QtQuick
import qs.Commons
import "FilesIndex.js" as FilesIndex

// The directory, one row per entry, and the bar that says which one you are
// standing on. Rows are the panel's only pointer target: the preview beside
// them is a reading surface, not a second list.
Item {
  id: root

  property var panel: null
  // The scroller, so the panel can keep the selection in view after a jump.
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
      // Waiting on a second Del. The row is where you are looking, so the row
      // is what has to say so.
      readonly property bool doomed: panel.doomed === entry.modelData.path

      width: list.width
      height: panel.rowHeight

      // The wheel's selection signature, unchanged: a capsule, the accent
      // tint, and the accent hairline a selected search bead wears. One shape
      // for "this is the thing Return runs", whichever of the three surfaces
      // you are standing on. The fill stops short of the preview so the
      // selection never touches it.
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
        // Real pointer motion only, for the reason panel.hoverMoved gives.
        onPositionChanged: function (mouse) {
          if (panel.hoverMoved(mapToItem(null, mouse.x, mouse.y))) panel.index = entry.index
        }
        onClicked: panel.ops.activate(entry.modelData)
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
    y: (list.contentY / Math.max(1, list.contentHeight - list.height))
       * (list.height - height)
  }
}
