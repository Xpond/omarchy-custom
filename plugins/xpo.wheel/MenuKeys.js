.pragma library

// The wheel's whole key map, in one function rather than in the dial it drives.
// It decides which verb a key means; the wheel performs it. That is what lets
// `tests/check.js` press a key without a running shell.
function onKey(wheel, event) {
  // Editing the query the way any text field does. Ahead of the plain
  // Backspace below, which ignores modifiers and would take
  // Ctrl+Backspace one character at a time; these also arrive as control
  // codes under " ", which the printable test at the end drops.
  if (event.modifiers & Qt.ControlModifier) {
    switch (event.key) {
    // The readline kills, either side of the caret. With the caret at the
    // end -- where it is unless you moved it -- ctrl+u still clears.
    case Qt.Key_U:
      wheel.query = wheel.query.slice(wheel.queryAt); wheel.queryAt = 0
      event.accepted = true; return
    case Qt.Key_K:
      wheel.query = wheel.query.slice(0, wheel.queryAt); event.accepted = true; return
    case Qt.Key_W:
    case Qt.Key_Backspace:
      // The trailing space stays, so the next word does not need one.
      var kept = wheel.query.slice(0, wheel.queryAt).replace(/\S+\s*$/, "")
      wheel.query = kept + wheel.query.slice(wheel.queryAt)
      wheel.queryAt = kept.length; event.accepted = true; return
    case Qt.Key_A: wheel.queryAt = 0; event.accepted = true; return
    case Qt.Key_E: wheel.queryAt = wheel.query.length; event.accepted = true; return
    case Qt.Key_V: wheel.paste(); event.accepted = true; return
    case Qt.Key_Y:
      if (!wheel.takePath()) return
      event.accepted = true; return
    // The readline pair, on the one thing here that is a list -- the ring
    // is a compass rather than a column, so there they fall through.
    case Qt.Key_N:
      if (wheel.searching) { wheel.moveResult(1); event.accepted = true }
      return
    case Qt.Key_P:
      if (wheel.searching) { wheel.moveResult(-1); event.accepted = true }
      return
    }
  }
  // One step at a time: the query, then the menu tree, then the screen.
  if (event.key === Qt.Key_Escape) {
    if (wheel.searching) wheel.query = ""
    else if (!wheel.up()) wheel.dismiss()
    event.accepted = true; return
  }
  if (event.key === Qt.Key_Backspace) {
    if (!wheel.searching) wheel.up()
    else if (wheel.queryAt > 0) {
      var at = wheel.queryAt - 1
      wheel.query = wheel.query.slice(0, at) + wheel.query.slice(wheel.queryAt)
      wheel.queryAt = at
    }
    event.accepted = true; return
  }
  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
    wheel.run(wheel.searching ? wheel.results[wheel.resultIndex] : wheel.slices[wheel.selected])
    event.accepted = true; return
  }
  if (wheel.searching) {
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { wheel.moveResult(1); event.accepted = true; return }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { wheel.moveResult(-1); event.accepted = true; return }
    // Left and right carry the caret. Home and end stay on the list: it
    // is the thing here with two ends, and stepping only wraps cheaply
    // from the ends it is already standing on.
    if (event.key === Qt.Key_Left) { wheel.queryAt = Math.max(0, wheel.queryAt - 1); event.accepted = true; return }
    if (event.key === Qt.Key_Right) {
      wheel.queryAt = Math.min(wheel.query.length, wheel.queryAt + 1); event.accepted = true; return
    }
    if (event.key === Qt.Key_Home) { wheel.resultIndex = 0; wheel.showResult(); event.accepted = true; return }
    if (event.key === Qt.Key_End) {
      wheel.resultIndex = Math.max(0, wheel.results.length - 1)
      wheel.showResult(); event.accepted = true; return
    }
  } else {
    switch (event.key) {
    // Arrows alone reach the whole ring: up/down jump to the top and
    // bottom slice, left/right pick the side slice first and then step
    // around, so anything off a cardinal is a cardinal plus a few steps.
    // Found by bearing rather than fixed at 0/4/2/6 -- the ring is nine
    // slices by default and any count once it is configured.
    case Qt.Key_Up:       wheel.select(wheel.nearestSlice(0)); event.accepted = true; return
    case Qt.Key_Down:     wheel.select(wheel.nearestSlice(180)); event.accepted = true; return
    case Qt.Key_Right:    wheel.selected < 0 ? wheel.select(wheel.nearestSlice(90)) : wheel.rotate(1); event.accepted = true; return
    case Qt.Key_Left:     wheel.selected < 0 ? wheel.select(wheel.nearestSlice(270)) : wheel.rotate(-1); event.accepted = true; return
    case Qt.Key_Tab:      wheel.rotate(1); event.accepted = true; return
    case Qt.Key_Backtab:  wheel.rotate(-1); event.accepted = true; return
    }
  }
  // Anything else printable starts the query or lands in it at the caret.
  if (event.text && event.text.length === 1 && event.text >= " ") {
    wheel.insert(event.text)
    event.accepted = true
  }
}
