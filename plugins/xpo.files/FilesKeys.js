.pragma library

// Keep the key map pure enough to exercise without a running shell.
function onKey(panel, ops, preview, event) {
  // Unaccepted keys continue to the focused editor.
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
  // Any key except the confirming Delete disarms deletion.
  if (ops.doomed && event.key !== Qt.Key_Delete) ops.doomed = ""

  if (panel.naming) {
    switch (event.key) {
    case Qt.Key_Escape: panel.naming = ""; break
    case Qt.Key_Return:
    case Qt.Key_Enter:  panel.commitName(); break
    default: panel.renameKey(event)
    }
    // Keep every key from moving the selection during naming.
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
    case Qt.Key_N:
      if (event.modifiers & Qt.ShiftModifier) panel.beginNew()
      else panel.move(1)
      event.accepted = true; return
    case Qt.Key_P: panel.move(-1); event.accepted = true; return
    case Qt.Key_W:
    case Qt.Key_Backspace:
      panel.filter = panel.pathMode
        ? (panel.filter.replace(/\/+$/, "").replace(/[^\/]*$/, "") || panel.filter.charAt(0))
        : panel.filter.replace(/\S+\s*$/, "")
      event.accepted = true; return
    }
  }
  // Shift directs navigation to the preview pane.
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
  case Qt.Key_Escape:
    if (panel.filter) panel.filter = ""
    else panel.close()
    event.accepted = true; return
  case Qt.Key_Backspace:
    if (panel.filter) panel.filter = panel.filter.slice(0, -1)
    else if (panel.dir !== panel.home) panel.up()
    else panel.toWheel()
    event.accepted = true; return
  case Qt.Key_Left:  panel.up(); event.accepted = true; return
  case Qt.Key_Down:  panel.move(1); event.accepted = true; return
  case Qt.Key_Up:    panel.move(-1); event.accepted = true; return
  case Qt.Key_Tab:   panel.move(1); event.accepted = true; return
  case Qt.Key_Backtab: panel.move(-1); event.accepted = true; return
  case Qt.Key_PageDown: panel.goTo(panel.index + panel.listPage); event.accepted = true; return
  case Qt.Key_PageUp:   panel.goTo(panel.index - panel.listPage); event.accepted = true; return
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
