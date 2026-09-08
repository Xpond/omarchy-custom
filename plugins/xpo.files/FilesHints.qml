import QtQuick
import qs.Commons

// Every key the panel answers to, in the order you reach for them: a browser
// with no visible verbs is one you have to remember. Key and word are told
// apart by weight rather than by space, so the pairs group themselves instead
// of reading as eight phrases in a row.
//
// The row is the panel's status line as much as its legend -- it is where a
// held file says what ctrl+v would do with it.
Item {
  id: root

  // The panel, for the state the legend reads. Passed rather than reached for,
  // so this file has one dependency and it is visible at the call site.
  property var panel: null

  implicitHeight: hints.height

  // A delete waiting for its second press owns the whole row and says so in
  // the urgent colour: the note in the heading was too far from where you are
  // looking, and being asked a destructive question quietly is worse than not
  // being asked.
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
    : panel.held
      ? [["↑↓", "select"], ["→", "open"], ["←", "up"],
         ["ctrl+v", (panel.held.move ? "move " : "copy ") + panel.held.name + " here"],
         ["ctrl+e", "edit"], ["esc", "close"]]
    : [["↑↓", "select"], ["→", "open"], ["←", "up"],
       ["shift+↑↓", "scroll"], ["ctrl+x/c/v", "move/copy"],
       ["ctrl+e", "edit"], ["ctrl+y", "copy path"], ["ctrl+o", "sort"],
       ["f2", "rename"], ["ctrl+shift+n", "new"], ["del", "trash"],
       ["esc", "close"]]

  Row {
    id: hints
    anchors.horizontalCenter: parent.horizontalCenter
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
