.pragma library

// Keep the key map pure enough to exercise without a running shell. The query
// field types, deletes, moves and selects for itself; this is everything else.
function onKey(wheel, event) {
  // A setting row being changed takes every key until Enter or Esc; the backdrop's ←/→ step a tenth.
  if (wheel.editing === "backdrop") {
    var step = event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Left ? -1 : 0
    if (step) wheel.setBackdrop(Math.max(0, Math.min(100, (Math.round(wheel.backdrop / 10) + step) * 10)))
    else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) wheel.editing = ""
    event.accepted = true; return
  }
  // Forgetting picks asks again: Enter forgets them, Esc keeps them.
  if (wheel.editing === "forget") {
    var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
    if (enter) wheel.forgetPicks()
    if (enter || event.key === Qt.Key_Escape) wheel.editing = ""
    event.accepted = true; return
  }
  if (wheel.editing) { wheel.record(event); event.accepted = true; return }
  // The ring editor: Del and Shift+arrows change the ring, and Esc is done. Ctrl+R resets it when
  // pressed again; any other key, a modifier on its way to a combo aside, takes the question back.
  if (wheel.editingRing) {
    var again = (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R
    if (!again && shortcutOf(event) !== null) wheel.resetAsked = false
    if (again) { wheel.resetRing(); event.accepted = true; return }
    if (!wheel.searching) {
      if (event.key === Qt.Key_Delete) { wheel.unpin(); event.accepted = true; return }
      if (event.key === Qt.Key_Escape) { wheel.editingRing = false; event.accepted = true; return }
      if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
        wheel.moveSlice(event.key === Qt.Key_Right ? 1 : -1); event.accepted = true; return
      }
    }
  }
  // A list in the results: Del removes the picked entry and Esc is done, until something is typed.
  if (wheel.listing && !wheel.query) {
    if (event.key === Qt.Key_Delete) { wheel.removeEntry(); event.accepted = true; return }
    if (event.key === Qt.Key_Escape) { wheel.listing = ""; event.accepted = true; return }
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
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { wheel.moveResult(1); event.accepted = true; return }
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { wheel.moveResult(-1); event.accepted = true; return }
    // Home and End move and select in the field; Ctrl+Home and Ctrl+End reach the ends of the list.
    if (!(event.modifiers & Qt.ControlModifier)) return
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

// The combo a press makes, in Hyprland's names: "SUPER + SHIFT + B". A modifier alone is null,
// still on its way to a combo; a key without a name here is "", as is a shifted symbol, since
// Hyprland binds the unshifted key.
function shortcutOf(event) {
  var k = event.key
  if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Meta, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Super_L, Qt.Key_Super_R,
       Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_CapsLock, Qt.Key_NumLock].indexOf(k) >= 0) return null
  var name = ""
  if (k >= Qt.Key_A && k <= Qt.Key_Z || k >= Qt.Key_0 && k <= Qt.Key_9) name = String.fromCharCode(k)
  else if (k >= Qt.Key_F1 && k <= Qt.Key_F24) name = "F" + (k - Qt.Key_F1 + 1)
  var named = [[Qt.Key_Space, "SPACE"], [Qt.Key_Return, "RETURN"], [Qt.Key_Tab, "TAB"], [Qt.Key_Backtab, "TAB"],
    [Qt.Key_Backspace, "BACKSPACE"], [Qt.Key_Escape, "ESCAPE"], [Qt.Key_Delete, "DELETE"],
    [Qt.Key_Insert, "INSERT"], [Qt.Key_Home, "HOME"], [Qt.Key_End, "END"], [Qt.Key_PageUp, "PAGE_UP"],
    [Qt.Key_PageDown, "PAGE_DOWN"], [Qt.Key_Left, "LEFT"], [Qt.Key_Right, "RIGHT"], [Qt.Key_Up, "UP"],
    [Qt.Key_Down, "DOWN"], [Qt.Key_Print, "PRINT"], [Qt.Key_Comma, "COMMA"], [Qt.Key_Period, "PERIOD"],
    [Qt.Key_Slash, "SLASH"], [Qt.Key_Semicolon, "SEMICOLON"], [Qt.Key_Apostrophe, "APOSTROPHE"],
    [Qt.Key_BracketLeft, "BRACKETLEFT"], [Qt.Key_BracketRight, "BRACKETRIGHT"], [Qt.Key_Backslash, "BACKSLASH"],
    [Qt.Key_Minus, "MINUS"], [Qt.Key_Equal, "EQUAL"], [Qt.Key_QuoteLeft, "GRAVE"]]
  for (var i = 0; i < named.length && !name; i++) if (named[i][0] === k) name = named[i][1]
  if (!name) return ""
  var mods = [[Qt.MetaModifier, "SUPER"], [Qt.ControlModifier, "CTRL"], [Qt.AltModifier, "ALT"],
              [Qt.ShiftModifier, "SHIFT"]]
  var out = []
  for (var m = 0; m < mods.length; m++) if (event.modifiers & mods[m][0]) out.push(mods[m][1])
  return out.concat([name]).join(" + ")
}
