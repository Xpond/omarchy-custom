import QtQuick

// Drop-in key dispatcher for keyboard-driven panels. Wraps panel content
// and emits semantic signals so each panel keeps its own state machine
// (focusSection, selectedIndex, action rules) while the boilerplate
// key handling lives here.
//
// Usage:
//   Common.KeyboardPanel {
//     ...
//     PanelKeyCatcher {
//       anchors.fill: parent
//       onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
//       onActivateRequested: root.activateCursor()
//       onCloseRequested: root.close()
//       onDeleteRequested: root.deleteSelected()
//       onTextKey: function(t) { if (t === "r") root.refresh() }
//
//       Column { ... panel content ... }
//     }
//   }
//
// Keys.priority: Keys.BeforeItem means this handler gets keys first,
// even when a descendant has activeFocus. That's what lets Up/Down
// arrows drive the cursor instead of being consumed by an inner
// Flickable's built-in scroll handling. When a panel has an inline
// editor (wifi passphrase, gallery TextField demo) the panel must
// set `blocked: editor.activeFocus` so this handler short-circuits
// and the editor receives keys normally.
//
// blocked: when true, ALL keys are forwarded to descendants without
// triggering signals.
Item {
  id: root

  property bool blocked: false

  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)

  focus: true
  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (blocked) return

    // `q` closes too, matching the wheel and every other shell surface. Safe
    // because `blocked` is set while an inline editor holds focus, so a
    // passphrase field still gets its own letters.
    if (event.key === Qt.Key_Escape
        || (event.key === Qt.Key_Q && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))) {
      closeRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      tabRequested((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
      event.accepted = true
      return
    }
    // Ctrl+Left/Right walks between panels. Bare arrows stay with the panel
    // itself -- in the monitor panel they drive the brightness/text-size
    // sliders and the scale buttons, so taking them would cost that control.
    if ((event.modifiers & Qt.ControlModifier)
        && (event.key === Qt.Key_Right || event.key === Qt.Key_Left)) {
      tabRequested(event.key === Qt.Key_Right ? 1 : -1)
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Down || event.text === "j") {
      moveRequested(0, 1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Up || event.text === "k") {
      moveRequested(0, -1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Right || event.text === "l") {
      moveRequested(1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Left || event.text === "h") {
      moveRequested(-1, 0); event.accepted = true; return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      returnRequested()
      activateRequested(); event.accepted = true; return
    }
    if (event.key === Qt.Key_Space) {
      activateRequested(); event.accepted = true; return
    }
    if (event.text === "x" || event.text === "X") {
      deleteRequested(); event.accepted = true; return
    }
    if (event.text && event.text.length === 1) {
      textKey(event.text)
    }
  }
}
