const assert = require("node:assert/strict")
const { method, keymap } = require("./qml.js")
const { M, wheelSource } = require("./wheel-source.js")
const shift = 1 << 25

// The query field types, deletes, moves and selects, Home, End and Ctrl+A included; the rest is the wheel's.
const copied = []

const dial = { query: "", queryAt: 0, results: [], resultIndex: 0,
  get searching() { return this.query.length > 0 },
  dismiss: () => copied.push("dismissed"), showResult() {}, moveResult(step) { this.resultIndex += step } }
const edit = (query, at) => { dial.query = query; dial.queryAt = at }
// TextInput's remove() does nothing for an empty selection; insert() moves the caret past its text.
const field = { selectionStart: 0, selectionEnd: 0, get cursorPosition() { return dial.queryAt },
  remove(from, to) { if (from < to) edit(dial.query.slice(0, from) + dial.query.slice(to), from) },
  insert(at, text) { edit(dial.query.slice(0, at) + text + dial.query.slice(at), at + text.length) } }
dial.paste = method(wheelSource, "paste", { searchInput: field,
  Quickshell: { clipboardText: "pasted  text" } })
dial.copy = method(wheelSource, "copy", { Quickshell: { execDetached: c => copied.push(c.at(-1)) } })
dial.takePath = method(wheelSource, "takePath", { root: dial })
const dialKey = keymap("plugins/xpo.wheel/MenuKeys.js", dial)
const ctrl = 1 << 26
// Del on the bare ring did nothing to see, yet its DEL character landed in the query.
assert.equal(dialKey("Key_Delete", 0, "\x7f").accepted + "|" + dial.query, "false|", "del on the ring adds nothing")
edit("firefox", 3)
// A printable key is only its text here.
for (const [key, modifiers, text] of [["", 0, "x"], ["Key_Delete", 0, "\x7f"], ["Key_Backspace"], ["Key_Left"],
     ["Key_Right", ctrl], ["Key_Left", shift], ["Key_Home"], ["Key_End"], ["Key_A", ctrl],
     ["Key_Home", shift], ["Key_End", shift]])
  assert.equal(dialKey(key, modifiers, text).accepted, false, `${key || text} belongs to the field`)
assert.equal(dial.query + "|" + dial.queryAt, "firefox|3", "the wheel edits nothing the field does")
dialKey("Key_K", ctrl)
assert.equal(dial.query, "fir", "ctrl+k kills to the end")
dial.queryAt = 0; dialKey("Key_E", ctrl); assert.equal(dial.queryAt, 3)
dialKey("Key_V", ctrl)
assert.equal(dial.query, "firpasted text", "a pasted run of whitespace collapses")
field.selectionEnd = dial.query.length
dialKey("Key_V", ctrl); field.selectionEnd = 0
assert.equal(dial.query + "|" + dial.queryAt, "pasted text|11", "a paste replaces the selection")
dialKey("Key_U", ctrl)
assert.equal(dial.query + "|" + dial.queryAt, "|0", "ctrl+u from the end still clears")
edit("a b c", 3)
dialKey("Key_W", ctrl)
assert.equal(dial.query + "|" + dial.queryAt, "a  c|2", "ctrl+w takes the word before the caret")
dial.results = Array.from({ length: 40 }, (_, i) => ({ label: "result" + i }))
dialKey("Key_Down"); dialKey("Key_N", ctrl); assert.equal(dial.resultIndex, 2)
dialKey("Key_P", ctrl); dialKey("Key_Up"); assert.equal(dial.resultIndex, 0)
dialKey("Key_End", ctrl); assert.equal(dial.resultIndex, 39, "ctrl+end is the last of the forty results")
dialKey("Key_Home", ctrl); assert.equal(dial.resultIndex, 0, "ctrl+home is the first")

// Ctrl+Y takes a path away; anything else on the ring is not a path.
dial.results = [{ label: "Firefox", appId: "firefox" }, { path: "/home/test/notes.md" }]
dial.resultIndex = 0
dialKey("Key_Y", ctrl); assert.deepEqual(copied, [], "an app row has no path to copy")
dial.resultIndex = 1
dialKey("Key_Y", ctrl)
assert.deepEqual(copied, ["/home/test/notes.md", "dismissed"])

// Ctrl+Enter opens a terminal in a path's folder, and on any other row is Enter.
const terminals = [], entered = []
dial.run = e => entered.push(e)
dial.terminal = method(wheelSource, "terminal", { root: dial, MenuIndex: M,
  Quickshell: { execDetached: argv => terminals.push([...argv]) } })
dial.results.push({ path: "/home/test/My Dir/" })
dial.resultIndex = 0; dialKey("Key_Return", ctrl)
assert.deepEqual([terminals, entered.map(e => e.appId)], [[], ["firefox"]], "ctrl+enter on an app is not enter")
dial.resultIndex = 1; copied.length = 0; dialKey("Key_Return", ctrl)
assert.deepEqual(terminals, [], "the terminal opened before the wheel unmapped")
assert.deepEqual(copied, ["dismissed"], "ctrl+enter on a path left the wheel up")
dial.queued()
dial.resultIndex = 2; dialKey("Key_Enter", ctrl); dial.queued()
assert.deepEqual(terminals, [["uwsm-app", "--", "xdg-terminal-exec", "--dir=/home/test"],
                             ["uwsm-app", "--", "xdg-terminal-exec", "--dir=/home/test/My Dir"]])
assert.equal(entered.length, 1, "a path row also ran as enter")

// Esc clears the query, then goes up a level, then closes; Backspace on no query goes up.
const levels = []
copied.length = 0
dial.up = () => levels.push("up") < 3
dialKey("Key_Escape"); assert.equal(dial.query, "", "esc clears the query first")
dialKey("Key_Backspace"); dialKey("Key_Escape"); dialKey("Key_Escape")
assert.deepEqual([levels, copied], [["up", "up", "up"], ["dismissed"]])
console.log("ok: the field edits the query, the wheel keeps its shortcuts, and a path can be taken away or opened in a terminal")

// The placeholder names every search sigil, so a new mode cannot hide.
const placeholder = wheelSource.match(/visible: !root\.query\n\s+text: ([^]*?)\n\s+color:/)[1].match(/"([^"]+)"$/)[1]
for (const sigil of Object.keys(M.MODES)) assert.ok(placeholder.includes(sigil + " "), `the placeholder hides ${sigil}`)
console.log("ok: the search placeholder names every search sigil")
