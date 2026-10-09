import QtQuick
import qs.Commons

Item {
  id: root

  property var panel: null

  implicitHeight: hints.height

  // Delete confirmation takes priority over the key legend.
  readonly property bool arming: !!panel && !!panel.doomed

  readonly property var pairs:
    !panel ? []
    : root.arming ? [["del", "again to trash " + panel.doomedName],
                     ["any other key", "cancel"]]
    : panel.editing
      ? [["ctrl+s", "save"], ["ctrl+c/x/v", "clipboard"],
         ["esc", panel.discarding ? "again to discard"
                 : panel.dirty ? "discard" : "back"]]
    : panel.naming
      ? (panel.naming === "new"
         ? [["type", "a name; a dot in it makes a file"],
            ["/ at the end", "a folder"], [". at the end", "a file"],
            ["enter", "make it"], ["esc", "cancel"]]
         : [["type", "the new name"], ["enter", "rename"], ["esc", "cancel"]])
    // A window closes like any other, so only the overlay offers esc; ctrl+t goes either way.
    : panel.held
      ? [["↑↓", "select"], ["→", "open"], ["←", "up"],
         ["ctrl+v", (panel.held.move ? "move " : "copy ") + panel.held.name + " here"],
         ["ctrl+e", "edit"]].concat(panel.host ? [["esc", "search"]] : panel.windowed ? [] : [["esc", "close"]])
    : [["↑↓", "select"], ["→", "open"], ["←", "up"],
       ["shift+↑↓", "scroll"], ["ctrl+x/c/v", "move/copy"],
       ["ctrl+e", "edit"], ["ctrl+enter", "terminal"], ["ctrl+y", "copy path"],
       ["ctrl+o", "sort"], ["f2", "rename"], ["ctrl+shift+n", "new"], ["del", "trash"]]
      .concat(panel.host ? [["ctrl+t", "unpin"], ["esc", "search"]] : panel.windowed ? [["ctrl+t", "unpin"]]
              : [["ctrl+t", "window"], ["esc", "close"]])

  Row {
    id: hints
    anchors.horizontalCenter: parent.horizontalCenter
    // Shrink rather than clip when a tiled window is narrower than the legend.
    scale: implicitWidth > root.width ? root.width / implicitWidth : 1
    spacing: Style.spacing.xxl

    Repeater {
      model: root.pairs

      delegate: Row {
        required property var modelData
        spacing: Style.spacing.xs

        Text {
          text: modelData[0]
          color: root.arming ? panel.danger : Color.menu.text
          opacity: root.arming ? 1.0 : 0.72
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          text: modelData[1]
          color: root.arming ? panel.danger : Color.menu.text
          opacity: root.arming ? 0.9 : 0.36
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
