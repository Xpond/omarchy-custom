.pragma library

// The browser's whole key map, in one function rather than in the panel it
// drives. It decides which verb a key means; the panel performs it. That is
// what lets `tests/check.js` press a key without a running shell.
function onKey(panel, ops, preview, event) {
  // `Keys.priority: Keys.BeforeItem` means this handler sees every key
  // before the editor does, focused or not -- the same thing Omarchy's
  // own PanelKeyCatcher documents. Anything not accepted here goes on
  // to the editor, which is what makes typing work; the clipboard is
  // spelled out rather than left to TextEdit's own handling, because a
  // panel this modal should not have verbs that only work by accident.
  if (panel.editing) {
    if (event.modifiers & Qt.ControlModifier) {
      switch (event.key) {
      case Qt.Key_S: panel.save(); event.accepted = true; return
      case Qt.Key_C: preview.copy(); event.accepted = true; return
      case Qt.Key_X: preview.cut(); event.accepted = true; return
      case Qt.Key_V: preview.paste(); event.accepted = true; return
      case Qt.Key_A: preview.selectAll(); event.accepted = true; return
      }
    }
    if (event.key === Qt.Key_Escape) { panel.leaveEdit(); event.accepted = true }
    return
  }
  // Renaming takes the keyboard the way editing does, and for the same
  // reason: the field it is typing into is the one the filter uses.
  // Any key that is not the second Del calls the delete off. The foot
  // is showing a question; a keystroke that is not the answer is a no.
  if (ops.doomed && event.key !== Qt.Key_Delete) ops.doomed = ""

  if (panel.naming) {
    switch (event.key) {
    case Qt.Key_Escape: panel.naming = ""; break
    case Qt.Key_Return:
    case Qt.Key_Enter:  panel.commitName(); break
    default: panel.renameKey(event)
    }
    // Everything, so an arrow cannot move the selection out from under
    // the name being typed.
    event.accepted = true
    return
  }
  if (event.modifiers & Qt.ControlModifier) {
    switch (event.key) {
    case Qt.Key_E: panel.edit(); event.accepted = true; return
    case Qt.Key_C: ops.hold(panel.sel, false); event.accepted = true; return
    case Qt.Key_X: ops.hold(panel.sel, true); event.accepted = true; return
    case Qt.Key_V: ops.paste(); event.accepted = true; return
    case Qt.Key_H: panel.showHidden = !panel.showHidden; event.accepted = true; return
    case Qt.Key_U: panel.filter = ""; event.accepted = true; return
    case Qt.Key_Y: ops.copyPath(); event.accepted = true; return
    case Qt.Key_O: panel.cycleOrder(); event.accepted = true; return
    // The readline pair the rest of this field already speaks, and the
    // same letter under shift for the other naming verb.
    case Qt.Key_N:
      if (event.modifiers & Qt.ShiftModifier) panel.beginNew()
      else panel.move(1)
      event.accepted = true; return
    case Qt.Key_P: panel.move(-1); event.accepted = true; return
    // A word of a name, a segment of a path -- one step back through
    // whichever is being written, never past the sigil that says which.
    case Qt.Key_W:
    case Qt.Key_Backspace:
      panel.filter = panel.pathMode
        ? (panel.filter.replace(/\/+$/, "").replace(/[^\/]*$/, "") || panel.filter.charAt(0))
        : panel.filter.replace(/\S+\s*$/, "")
      event.accepted = true; return
    }
  }
  // Shift turns the arrows on the preview instead of the list. Held
  // down, it is the one modifier that reads as "the other pane".
  if (event.modifiers & Qt.ShiftModifier) {
    switch (event.key) {
    case Qt.Key_Down:  preview.scrollBy(panel.lineHeight * 3); event.accepted = true; return
    case Qt.Key_Up:    preview.scrollBy(-panel.lineHeight * 3); event.accepted = true; return
    case Qt.Key_Right: preview.scrollAcross(preview.panStep); event.accepted = true; return
    case Qt.Key_Left:  preview.scrollAcross(-preview.panStep); event.accepted = true; return
    case Qt.Key_PageDown: preview.scrollBy(preview.pageStep); event.accepted = true; return
    case Qt.Key_PageUp:   preview.scrollBy(-preview.pageStep); event.accepted = true; return
    case Qt.Key_Home:  preview.scrollTo(0); event.accepted = true; return
    case Qt.Key_End:   preview.scrollTo(1); event.accepted = true; return
    }
  }
  switch (event.key) {
  // One step at a time: the filter, then the panel.
  case Qt.Key_Escape:
    if (panel.filter) panel.filter = ""
    else panel.close()
    event.accepted = true; return
  // Backspace edits the filter while there is one, because that is
  // what it does in every field. Left is the way up that always works.
  case Qt.Key_Backspace:
    if (panel.filter) panel.filter = panel.filter.slice(0, -1)
    else panel.up()
    event.accepted = true; return
  case Qt.Key_Left:  panel.up(); event.accepted = true; return
  case Qt.Key_Down:  panel.move(1); event.accepted = true; return
  case Qt.Key_Up:    panel.move(-1); event.accepted = true; return
  case Qt.Key_Tab:   panel.move(1); event.accepted = true; return
  case Qt.Key_Backtab: panel.move(-1); event.accepted = true; return
  case Qt.Key_PageDown: panel.goTo(panel.index + panel.listPage); event.accepted = true; return
  case Qt.Key_PageUp:   panel.goTo(panel.index - panel.listPage); event.accepted = true; return
  // Home is the first row, not the home directory: every bare key here
  // drives the list. `~` still opens path entry sitting at home, which
  // is the character that says so anyway.
  case Qt.Key_Home:  panel.goTo(0); event.accepted = true; return
  case Qt.Key_End:   panel.goTo(panel.rows.length - 1); event.accepted = true; return
  case Qt.Key_F2:    panel.beginRename(); event.accepted = true; return
  case Qt.Key_Delete: ops.remove(); event.accepted = true; return
  case Qt.Key_Right:
  case Qt.Key_Return:
  case Qt.Key_Enter:
    ops.activate(panel.sel); event.accepted = true; return
  }
  if (event.text && event.text.length === 1 && event.text >= " ") {
    panel.filter += event.text
    panel.index = 0
    event.accepted = true
  }
}
