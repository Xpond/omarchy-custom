const assert = require("node:assert/strict")
const fs = require("node:fs")
const { read, method, keymap } = require("./qml.js")
const { M, wheelSource, binding, derive } = require("./wheel-source.js")

// Wheel settings are rows: `wheely settings` lists them and their own words find each. The wheel's
// own bindings mean nothing from inside it, so they are no rows, and no conflict for a new key.
{
  const records = [
    "SUPER + A                 → Wheel\texec\tomarchy-shell -q shell toggle xpo.wheel",
    "SUPER + A                 → \texec\tomarchy-shell -q shell call xpo.wheel commit ''",
    "SUPER + W                 → Close window\texec\t/home/test/wheely/bin/omarchy-wheel-close",
    "SUPER + SPACE             → Omarchy menu\texec\tomarchy-menu toggle",
    "SUPER SHIFT CTRL + SPACE  → Theme menu\texec\tomarchy-menu toggle theme",
    "SUPER + C                 → Universal copy\t\t",
    "SUPER + X                 → \t\t"].join("\n")
  assert.deepEqual(M.bindRows(records).map(r => r.label), ["Omarchy menu", "Theme menu"],
    "the wheel's own bindings are rows")
  const rows = M.withBindings(M.settingRows("SUPER + A", false, [], M.SKIPPED, 0, true), M.bindRows(records), {})
  for (const query of ["wheely settings", "wheel", "preferences"])
    assert.deepEqual(M.search(rows, query, 40, {}).map(r => r.setting).filter(s => s !== "history").sort(),
      ["backdrop", "folders", "forget", "panels", "ring", "shortcut", "skipped"], query)
  assert.deepEqual(M.search(rows, "wheely settings", 40, {}).filter(r => r.setting === "history"), [],
    "history passed for a setting")
  for (const [setting, queries] of Object.entries({ shortcut: ["wheely shortcut", "shortcut", "keybind"],
       ring: ["wheely ring", "ring", "slices", "pin"], backdrop: ["backdrop", "blur", "dim"], folders: ["searched folders"],
       skipped: ["skip"], forget: ["forget", "clear picks"], panels: ["centered panels", "panels", "center"],
       history: ["history", "wheely history", "recent"] }))
    for (const query of queries) assert.equal(M.search(rows, query, 40, {})[0]?.setting, setting, query + " misses its row")
  assert.equal(M.indexOfEntry(M.settingRows("ALT + SPACE", false, [], M.SKIPPED, 0, true), rows[0]), 0, "saving a key lost the row")
  assert.deepEqual(M.settingRows("SUPER + A", true, ["/mnt"], ["a", "b"], 57, false).map(r => r.trail),
    ["SUPER + A", "Custom", "", "Off", "Home + 1", "2", "57", "57"])

  assert.equal(M.comboOf("SUPER SHIFT CTRL + space"), "SUPER + CTRL + SHIFT + SPACE")
  assert.equal(M.bindingAt(records, "SUPER + CTRL + SHIFT + SPACE"), "Theme menu", "another spelling hid a binding")
  assert.equal(M.bindingAt(records, "SUPER + SPACE"), "Omarchy menu")
  assert.equal(M.bindingAt(records, "SUPER + C"), "Universal copy", "a binding no row runs gave up its key")
  assert.equal(M.bindingAt(records, "SUPER + X"), "another binding", "a binding without a description gave up its key")
  assert.equal(M.bindingAt(records, "SUPER + A") + M.bindingAt(records, "SUPER + B"), "")
  assert.equal(M.bindingAt("SUPER + T → Terminal\texec\tx", "SUPER + T"), "Terminal", "the first binding gave up its key")

  // The Hyprland block reads the file by the same rule, over the same cases (tests/desktop.py).
  for (const [saved, key] of [[undefined, "SUPER + A"], ["SUPER + SHIFT + B\n", "SUPER + SHIFT + B"],
       ["  ALT + SPACE \r\n", "ALT + SPACE"], ["SPACE\n", "SUPER + A"], ["", "SUPER + A"],
       ['super + b") os.execute("touch pwned\n', "SUPER + A"]])
    assert.equal(M.shortcutIn(saved), key, JSON.stringify(saved))

  // The backdrop sets one key of the user's shell.toml, as the shell's own reader reads it, and keeps the rest.
  const parseShell = method(fs.readFileSync((process.env.OMARCHY_PATH || "/usr/share/omarchy")
    + "/shell/Commons/Color.qml", "utf8"), "parseShell", {})
  for (const [raw, out] of [[undefined, "[menu]\nscrim-alpha = 0.3\n"],
       ["[font]\nbase-size = 12\n", "[font]\nbase-size = 12\n\n[menu]\nscrim-alpha = 0.3\n"],
       ["[menu] # mine\nscrim-alpha = 0.5\n[font]\nbase-size = 12", "[menu] # mine\nscrim-alpha = 0.3\n[font]\nbase-size = 12\n"],
       ['[menu]\nbackground = "#000"\n\n[polkit]\nscrim-alpha = 0.9\n',
        '[menu]\nbackground = "#000"\nscrim-alpha = 0.3\n\n[polkit]\nscrim-alpha = 0.9\n']]) {
    assert.equal(M.withShellValue(raw, "menu", "scrim-alpha", 0.3), out, JSON.stringify(raw))
    assert.deepEqual({ ...parseShell(out) }, { ...parseShell(raw), "menu.scrim-alpha": "0.3" }, "the shell reads " + out)
  }

  // Enter hands ←/→ the backdrop, snapped to a tenth; each step saves the dim, and the blur only when
  // it turns at 0%, since that reloads Hyprland. Every key stays the row's until Enter or Esc.
  const shellFile = { raw: "", text() { return this.raw }, setText(raw) { this.raw = raw } }
  const blurFile = { raw: "", setText(raw) { this.raw += raw } }
  const bd = { editing: "", drawn: 32, get backdrop() { return this.editing ? this.backdropDraft : this.drawn } }
  derive(bd, "editValue")
  for (const name of ["edit", "setBackdrop"])
    bd[name] = method(wheelSource, name, { root: bd, shellFile, blurFile, MenuIndex: M })
  const backdropKey = keymap("plugins/xpo.wheel/MenuKeys.js", bd)
  const state = () => [bd.editValue, parseShell(shellFile.raw)["menu.scrim-alpha"], blurFile.raw]
  bd.edit({ setting: "backdrop" })
  backdropKey("Key_Right")
  assert.deepEqual(state(), ["40%", "0.4", ""], "a step from 32")
  for (let i = 0; i < 5; i++) backdropKey("Key_Left")
  assert.deepEqual(state(), ["0%", "0", "off\n"], "0% is not clear")
  backdropKey("Key_Right")
  assert.deepEqual(state(), ["10%", "0.1", "off\non\n"], "10% is not blurred")
  for (let i = 0; i < 10; i++) backdropKey("Key_Right")
  assert.deepEqual(state(), ["100%", "1", "off\non\n"], "the backdrop passed opaque, or blur turned above 0%")
  assert.equal(backdropKey("Key_A").accepted && bd.editing, "backdrop", "a key escaped the backdrop row")
  backdropKey("Key_Return")
  const entered = bd.editing
  bd.edit({ setting: "backdrop" }); backdropKey("Key_Escape")
  assert.deepEqual([entered, bd.editing], ["", ""], "enter or esc left the row taking keys")

  // Forget picks asks again: Enter forgets every pick, on disk too; Esc keeps them; other keys wait.
  const usesFile = { raw: "", setText(raw) { this.raw = raw } }
  const fg = { editing: "", uses: { "system.lock": 3, "file:/a": 1 } }
  derive(fg, "editValue")
  for (const name of ["edit", "forgetPicks"]) fg[name] = method(wheelSource, name, { root: fg, usesFile })
  const forgetKey = keymap("plugins/xpo.wheel/MenuKeys.js", fg)
  fg.edit({ setting: "forget" })
  assert.deepEqual([fg.editValue, forgetKey("Key_A").accepted, fg.editing], ["Forget 2 picks", true, "forget"],
    "a key other than Enter or Esc left the question")
  forgetKey("Key_Escape")
  assert.deepEqual([fg.editing, Object.keys(fg.uses).length, usesFile.raw], ["", 2, ""], "esc forgot the picks")
  assert.equal(binding("settingRows", { root: { ...fg, folders: [], skipped: [] }, MenuIndex: M })
    .find(r => r.setting === "forget").trail, "2",
    "the forget row miscounted the picks")
  fg.edit({ setting: "forget" }); forgetKey("Key_Return")
  assert.deepEqual([fg.editing, Object.keys(fg.uses).length, usesFile.raw], ["", 0, "{}\n"], "enter kept the picks")
  // A pick lands last in the file too, which is where history reads its order.
  const cu = { uses: { a: 1, b: 1 } }
  cu.countUse = method(wheelSource, "countUse", { root: cu, usesFile, MenuIndex: M })
  cu.countUse({ id: "a" })
  cu.countUse({ setting: "history" })
  assert.equal(usesFile.raw, '{"b":1,"a":2}\n', "a pick kept its place in the file, or a setting counted")

  // Centered panels flips [wheely] panels in shell.toml, which the shell's reader hands every panel;
  // until it is flipped there is no key, and panels center as they always have.
  const panelsFile = { raw: "[menu]\nscrim-alpha = 0.5\n", text() { return this.raw }, setText(raw) { this.raw = raw } }
  const pn = { panelsCentered: true }
  pn.edit = method(wheelSource, "edit", { root: pn, shellFile: panelsFile, MenuIndex: M })
  pn.edit({ setting: "panels" })
  assert.deepEqual({ ...parseShell(panelsFile.raw) }, { "menu.scrim-alpha": "0.5", "wheely.panels": "native" })
  pn.panelsCentered = false; pn.edit({ setting: "panels" })
  assert.equal(parseShell(panelsFile.raw)["wheely.panels"], "centered")
  const panelRule = 'Color.shellValues["wheely.panels"] !== "native"'
  const keyboardPanel = read("patches/shell/Ui/KeyboardPanel.qml")
  assert.ok(wheelSource.includes(panelRule) && keyboardPanel.includes(panelRule), "the panels read another key than the wheel writes")

  // Recording: a modifier alone waits, plain Esc gives up, plain Enter saves only a candidate,
  // and any other press is judged. shortcutOf's names are checked against real Qt in runtime.py.
  const Q = { ShiftModifier: 1 << 25, ControlModifier: 1 << 26, AltModifier: 1 << 27, MetaModifier: 1 << 28,
              Key_Escape: 1, Key_Return: 2, Key_Enter: 3 }
  const saved = []
  const rec = { shortcut: "SUPER + A", bindText: records, saveShortcut: combo => saved.push(combo) }
  derive(rec, "refused", "pending", "taken", "editValue", "editNote")
  const edit = method(wheelSource, "edit", { root: rec })
  const record = method(wheelSource, "record",
    { root: rec, Qt: Q, MenuKeys: { shortcutOf: event => event.combo } })
  const press = (combo, key = 0, modifiers = Q.MetaModifier) => {
    record({ combo, key, modifiers })
    return rec.editValue + " | " + rec.editNote + " | " + rec.pending
  }
  edit({ setting: "shortcut" })
  assert.equal(press(null), "Press a shortcut | esc cancels | ", "a modifier alone was judged")
  assert.equal(press(""), "Press a shortcut | pick another key | ")
  assert.equal(press("SHIFT + B", 0, Q.ShiftModifier), "SHIFT + B | add SUPER | ")
  assert.equal(press("F13", 0, 0), "F13 | add SUPER | ")
  // CTRL or ALT alone is refused too: Hyprland would take the combo from every app.
  assert.equal(press("CTRL + C", 0, Q.ControlModifier), "CTRL + C | add SUPER | ")
  assert.equal(press("ALT + SPACE", 0, Q.AltModifier), "ALT + SPACE | add SUPER | ")
  assert.equal(press("SUPER + W"), "SUPER + W | closes the wheel | ")
  assert.equal(press("SUPER + A"), "SUPER + A | already set | ")
  assert.equal(press("SUPER + SPACE"), "SUPER + SPACE | replaces Omarchy menu | SUPER + SPACE")
  assert.equal(press("SUPER + RETURN", Q.Key_Return), "SUPER + RETURN | enter saves | SUPER + RETURN",
    "enter with a modifier was not a candidate")
  record({ key: Q.Key_Return, modifiers: 0 })
  assert.deepEqual(saved, ["SUPER + RETURN"])
  assert.equal(rec.editing, "", "saving left the row recording")
  // Enter saves only a candidate: after nothing, or after a refused combo, it saves nothing.
  for (const [presses, last] of [[[], "SUPER + RETURN"], [["SUPER + B", "SHIFT + B"], "SUPER + RETURN"],
                                 [["SUPER + B"], "SUPER + B"]]) {
    edit({ setting: "shortcut" })
    for (const combo of presses) press(combo, 0, combo.startsWith("SHIFT") ? Q.ShiftModifier : Q.MetaModifier)
    record({ key: Q.Key_Enter, modifiers: 0 })
    assert.equal(rec.editing + saved.at(-1), last, "enter after " + JSON.stringify(presses))
  }
  edit({ setting: "shortcut" }); press("SUPER + C")
  record({ key: Q.Key_Escape, modifiers: 0 })
  assert.equal(rec.editing + saved.at(-1), "SUPER + B", "esc saved the candidate")

  // While a row records, every key is the row's: none types, moves or closes.
  const recorded = []
  const editingKey = keymap("plugins/xpo.wheel/MenuKeys.js", { editing: "shortcut", record: e => recorded.push(e) })
  for (const key of ["Key_Escape", "Key_Return", "Key_Backspace", "Key_Up", "Key_A"])
    assert.equal(editingKey(key).accepted, true, key + " escaped the shortcut row")
  assert.equal(recorded.length, 5)

  // Enter on a setting row starts changing it; the wheel stays up.
  const setRow = { countUse() {}, dismiss() { throw new Error("a setting row closed the wheel") },
                   slices: [], edited: "", edit(e) { this.edited = e.setting } }
  method(wheelSource, "run", { root: setRow, unmap: { running: false }, MenuIndex: M })(rows[0])
  assert.equal(setRow.edited, "shortcut")
}
console.log("ok: settings are rows, the wheel's own bindings are not, and the shortcut row records, judges and saves")
