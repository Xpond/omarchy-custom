.pragma library

// Keep the key map pure enough to exercise without a running shell. The query
// field types, deletes, moves and selects for itself; this is everything else.
function onKey(wheel, event) {
  if (event.key === Qt.Key_CapsLock || event.key === Qt.Key_F12) {
    wheel.toggleBackdropPeek()
    event.accepted = true
    return
  }
  if (event.modifiers & Qt.ControlModifier) {
    switch (event.key) {
    case Qt.Key_U:
      wheel.query = wheel.query.slice(wheel.queryAt); wheel.queryAt = 0
      event.accepted = true; return
    case Qt.Key_K:
      wheel.query = wheel.query.slice(0, wheel.queryAt); event.accepted = true; return
    case Qt.Key_W:
    case Qt.Key_Backspace:
      var kept = wheel.query.slice(0, wheel.queryAt).replace(/\S+\s*$/, "")
      wheel.query = kept + wheel.query.slice(wheel.queryAt)
      wheel.queryAt = kept.length; event.accepted = true; return
    case Qt.Key_A: wheel.queryAt = 0; event.accepted = true; return
    case Qt.Key_E: wheel.queryAt = wheel.query.length; event.accepted = true; return
    case Qt.Key_V: wheel.paste(); event.accepted = true; return
    case Qt.Key_Y:
      if (!wheel.takePath()) return
      event.accepted = true; return
    // A path opens a terminal in its folder; anything else runs as Enter does.
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (!wheel.terminal()) break
      event.accepted = true; return
    case Qt.Key_N:
      if (wheel.searching) { wheel.moveResult(1); event.accepted = true }
      return
    case Qt.Key_P:
      if (wheel.searching) { wheel.moveResult(-1); event.accepted = true }
      return
    }
  }
  if (event.key === Qt.Key_Escape) {
    wheel.dismissByEscape()
    event.accepted = true; return
  }
  if (event.key === Qt.Key_Backspace && !wheel.searching) {
    wheel.up(); event.accepted = true; return
  }
  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
    wheel.run(wheel.searching ? wheel.results[wheel.resultIndex] : wheel.slices[wheel.selected])
    event.accepted = true; return
  }
  if (wheel.searching) {
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { wheel.moveResult(1); event.accepted = true; return }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { wheel.moveResult(-1); event.accepted = true; return }
    // Shift+Home and Shift+End select in the field.
    if (event.modifiers & Qt.ShiftModifier) return
    if (event.key === Qt.Key_Home) { wheel.resultIndex = 0; wheel.showResult(); event.accepted = true; return }
    if (event.key === Qt.Key_End) {
      wheel.resultIndex = Math.max(0, wheel.results.length - 1)
      wheel.showResult(); event.accepted = true; return
    }
  } else {
    switch (event.key) {
    // Up/down choose by bearing; left/right step around any ring size.
    case Qt.Key_Up:       wheel.select(wheel.nearestSlice(0)); event.accepted = true; return
    case Qt.Key_Down:     wheel.select(wheel.nearestSlice(180)); event.accepted = true; return
    case Qt.Key_Right:    wheel.rotate(1); event.accepted = true; return
    case Qt.Key_Left:     wheel.rotate(-1); event.accepted = true; return
    case Qt.Key_Tab:      wheel.rotate(1); event.accepted = true; return
    case Qt.Key_Backtab:  wheel.rotate(-1); event.accepted = true; return
    }
  }
}
