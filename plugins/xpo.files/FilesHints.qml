import QtQuick
import qs.Commons

Item {
  id: root

  property var panel: null

  implicitHeight: hints.height

  // Delete confirmation takes priority over the key legend.
  readonly property bool arming: !!panel && !!panel.doomed
  readonly property var listKey: ["ctrl+b", !!panel && panel.listShown ? "hide list" : "show list"]
  // With the list hidden the bare keys scroll the preview; see FilesKeys.
  readonly property var moves: !panel || panel.listShown
    ? [["↑↓", "select"], ["enter", "open"], ["←", "up"], ["shift+↑↓", "scroll"]]
    : [["↑↓", "scroll"], ["enter", "open"], ["←", "list"]]
  // A window closes like any other, so only the overlay offers esc.
  readonly property var leave: !panel ? [] : panel.host ? [["esc", "search"]] : panel.windowed ? [] : [["esc", "close"]]

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
    : panel.held
      ? root.moves.concat([["ctrl+v", (panel.held.move ? "move " : "copy ") + panel.held.name + " here"],
         ["ctrl+e", "edit"]], root.leave)
    // The everyday keys by default; F1 swaps in every key.
    : panel.allKeys
      ? root.moves.concat([["ctrl+x/c/v", "move/copy"],
         ["ctrl+e", "edit"], ["ctrl+enter", "terminal"], ["ctrl+y", "copy path"],
         ["ctrl+o", "sort"], ["f2", "rename"], ["ctrl+shift+n", "new"], ["del", "trash"], root.listKey,
         ["ctrl+t", panel.host || panel.windowed ? "unpin" : "window"]], root.leave, [["f1", "fewer keys"]])
    : root.moves.concat([["ctrl+e", "edit"], root.listKey], root.leave, [["f1", "all keys"]])

  // A legend too long for one readable line takes two.
  readonly property var lines: root.pairs.length > 10
    ? [root.pairs.slice(0, Math.ceil(root.pairs.length / 2)), root.pairs.slice(Math.ceil(root.pairs.length / 2))]
    : [root.pairs]

  Column {
    id: hints
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.spacing.md

    Repeater {
      model: root.lines

      delegate: Row {
        required property var modelData
        anchors.horizontalCenter: parent.horizontalCenter
        // Shrink rather than clip when a tiled window is narrower than the line.
        scale: implicitWidth > root.width ? root.width / implicitWidth : 1
        spacing: Style.spacing.xxl

        Repeater {
          model: modelData

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
  }
}
