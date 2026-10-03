.pragma library

// Keep the key map pure enough to exercise without a running shell.
function onKey(wheel, event) {
  if (event.modifiers & Qt.ControlModifier) {
    switch (event.key) {
    // Ctrl+A remains TextInput's native select-all. Ctrl+E had only our old
    // caret shortcut, so don't give it an accidental platform-specific action.
    case Qt.Key_E:
      if (wheel.searching) { event.accepted = true; return }
      break
    case Qt.Key_Y:
      if (!wheel.takePath()) return
      event.accepted = true; return
    // A path opens a terminal in its folder; anything else runs as Enter does.
    case Qt.Key_Return:
    case Qt.Key_Enter:
      if (!wheel.terminal()) break
      event.accepted = true; return
    }
  }
  if (wheel.searching) {
    // TextInput owns editing (including printable text and Delete). Consume
    // movement combinations that would navigate or select nonexistent lines.
    if (event.modifiers & Qt.ControlModifier) {
      if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
          || event.key === Qt.Key_Home || event.key === Qt.Key_End
          || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
        event.accepted = true; return
      }
    }
    if ((event.modifiers & Qt.ShiftModifier)
        && (event.key === Qt.Key_Up || event.key === Qt.Key_Down
            || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)) {
      event.accepted = true; return
    }
  }
  if (event.key === Qt.Key_Escape) {
    if (wheel.searching) wheel.query = ""
    else if (!wheel.up()) wheel.dismiss()
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
    if (event.modifiers === 0 && event.key === Qt.Key_Down) { wheel.moveResult(1); event.accepted = true; return }
    if (event.modifiers === 0 && event.key === Qt.Key_Up) { wheel.moveResult(-1); event.accepted = true; return }
    // Home/End belong to the text caret; page keys jump to the result-list ends.
    if (event.modifiers === 0 && event.key === Qt.Key_PageUp) {
      wheel.resultIndex = 0; wheel.showResult(); event.accepted = true; return
    }
    if (event.modifiers === 0 && event.key === Qt.Key_PageDown) {
      wheel.resultIndex = Math.max(0, wheel.results.length - 1)
      wheel.showResult(); event.accepted = true; return
    }
    if (event.modifiers === 0 && event.key === Qt.Key_Tab) { wheel.moveResult(1); event.accepted = true; return }
    if (event.key === Qt.Key_Backtab) { wheel.moveResult(-1); event.accepted = true; return }
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
