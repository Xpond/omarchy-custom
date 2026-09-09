// Pure logic and lifecycle regressions. Run: node tests/check.js
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const repo = path.resolve(__dirname, "..")
const read = name => fs.readFileSync(path.join(repo, name), "utf8")
function library(name) {
  const src = read(name).replace(/^\.pragma library/m, "")
  const names = [...src.matchAll(/^(?:function (\w+)|var (\w+) =)/gm)].map(m => m[1] || m[2])
  return new Function(src + "\nreturn {" + names.join(",") + "}")()
}
function method(source, name, scope) {
  vm.createContext(scope)
  vm.runInContext(source.match(new RegExp("^  function " + name + "\\([^]*?^  }", "m"))[0], scope)
  return scope[name]
}
// A key map is a library like any other. It needs only a Qt whose names compare
// distinctly; real Qt values would be a table to keep correct for no gain.
function keymap(name, ...bound) {
  const src = read(name).replace(/^\.pragma library/m, "")
  const Qt = { ShiftModifier: 1 << 25, ControlModifier: 1 << 26 }
  let n = 1
  for (const [, key] of src.matchAll(/Qt\.(Key_\w+)/g)) Qt[key] = Qt[key] || n++
  const onKey = new Function("Qt", src + "\nreturn onKey")(Qt)
  return (key, modifiers = 0, text = "") =>
    onKey(...bound, { key: Qt[key], modifiers, text, accepted: false })
}
const F = library("plugins/xpo.files/FilesIndex.js")
const M = library("plugins/xpo.wheel/MenuIndex.js")

for (const n of [0, 1, 499, 500, 501]) {
  for (const ending of ["", "\n", "\r\n"]) {
    const text = Array(n).fill("content").join(ending === "\r\n" ? ending : "\n") + ending
    assert.equal(F.head(text, 500) === text, n <= 500)
    if (n > 500) assert.ok(F.head(text, 500).endsWith("\n…"))
  }
}
const buffer = bytes => Uint8Array.from(bytes).buffer
const valid = [[], [0], [0x7f], [0xc2, 0x80], [0xdf, 0xbf], [0xe0, 0xa0, 0x80],
  [0xed, 0x9f, 0xbf], [0xef, 0xbb, 0xbf], [0xef, 0xbf, 0xbd], [0xf0, 0x90, 0x80, 0x80],
  [0xf4, 0x8f, 0xbf, 0xbf], [...Buffer.from("café हिन्दी 😀")]]
const invalid = [[0x80], [0xc0, 0xaf], [0xc1, 0xbf], [0xc2], [0xe9, 10],
  [0xe0, 0x9f, 0xbf], [0xed, 0xa0, 0x80], [0xe2, 0x28, 0xa1], [0xe2, 0x82],
  [0xf0, 0x8f, 0xbf, 0xbf], [0xf4, 0x90, 0x80, 0x80], [0xf5, 0x80, 0x80, 0x80], [0xff],
  [...Array(2048).fill(65), 0xe9]]
for (const bytes of valid) assert.equal(F.isUtf8(buffer(bytes)), true, bytes.toString())
for (const bytes of invalid) assert.equal(F.isUtf8(buffer(bytes)), false, bytes.toString())
let seed = 42
function random() { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed }
const decoder = new TextDecoder("utf-8", { fatal: true })
for (let i = 0; i < 2000; i++) {
  const bytes = buffer(Array.from({ length: random() % 16 }, () => random() >>> 24))
  let expected = true
  try { decoder.decode(bytes) } catch { expected = false }
  assert.equal(F.isUtf8(bytes), expected)
}
console.log("ok: complete UTF-8 validation and 500-line boundaries")

// A full-sort reference checks ordering, stable ties, and multi-term matching.
function reference(files, query, limit) {
  const q = query.trim().toLowerCase()
  if (!q) return []
  return files.paths.map((p, i) => ({ p, i, name: M.nameOf(p.toLowerCase()) }))
    .filter(e => q.split(/\s+/).every(t => e.p.toLowerCase().includes(t)))
    .map(e => ({ ...e, rank: e.name.startsWith(q) ? 0 : e.name.includes(q) ? 1 : 2 }))
    .sort((a, b) => a.rank - b.rank || a.name.length - b.name.length || a.i - b.i)
    .slice(0, limit).map(e => M.fileRow(e.p, "/home/test"))
}
const words = ["a", "alpha", "beta", "Wheel.qml", "space name", "éclair", "longer-file"]
const paths = Array.from({ length: 5000 }, (_, i) =>
  "/home/test/" + words[random() % words.length] + "/" + i + "/" + words[random() % words.length]
  + (i % 4 ? "" : "/"))
const files = M.parseFiles(paths.join("\n"))
for (const query of ["", "a", "e", "home", "wheel", " WHEEL ", "a beta", "space name", "é", "zzz"])
  for (const limit of [0, 1, 8, 40, 5001])
    assert.deepEqual(M.fileRows(files, query, limit, "/home/test"), reference(files, query, limit))
assert.deepEqual(M.fileRows(null, "a", 40, "/home/test"), [])
const app = M.liveRows({ apps: [{ entry: { id: "broken", icon: "/missing.png" } }],
  windows: [], themes: [], fonts: [] })[0]
assert.ok(app.icon)
console.log("ok: file search ordering, limits, ties, and app fallback glyph")

const source = read("plugins/xpo.files/Files.qml")
const calls = []
const root = { editing: true, dirty: true, saving: null, opened: true,
  note: t => calls.push(t), enter: d => calls.push(d), home: "/home/test",
  focusedScreen: () => null, claimPending() {}, leaveEdit() { this.editing = false } }
const scope = { root, ops: { note: t => calls.push(t) },
  preview: { focusEditor: () => calls.push("editor focus") },
  keys: { forceActiveFocus() {} }, Qt: { callLater: fn => fn() } }
const open = method(source, "open", scope)
open('{"dir":"/home/test/other","select":"new.txt"}')
assert.equal(root.pending, undefined)
assert.equal(root.editing, true)
assert.equal(calls.length, 2)
root.dirty = false; root.saving = "pending write"
open('{"dir":"/home/test/other"}')
assert.equal(root.pending, undefined)
root.saving = null
open('{"dir":"/home/test/other","select":"new.txt"}')
assert.equal(root.editing, false)
assert.equal(root.pending, "new.txt")
assert.ok(calls.includes("/home/test/other"))
let hides = 0
const close = method(source, "close", scope)
root.shell = { hide: () => { hides++; close() } }
close()
assert.equal(root.opened, false)
assert.equal(hides, 1)
console.log("ok: navigation preserves dirty/pending edits; self-close does not recurse")

const opsSource = read("plugins/xpo.files/FilesOps.qml")
const busy = { root: { note: text => calls.push(text) }, filer: { running: true } }
method(opsSource, "run", busy)(["cp"], {})
assert.equal(busy.root.op, undefined)
assert.match(calls.at(-1), /still running/)
const wheel = { root: { countUse() {}, dismiss() {}, shell: {
  summon: (id, payload) => calls.push([id, JSON.parse(payload)]),
  toggle() { throw new Error("navigation must summon") }
} }, Qt: { callLater: fn => fn() }, MenuIndex: M }
method(read("plugins/xpo.wheel/Wheel.qml"), "run", wheel)({ path: "/home/test/new.txt" })
assert.equal(calls.at(-1)[0], "xpo.files")
assert.equal(calls.at(-1)[1].select, "new.txt")
console.log("ok: busy operations report refusal; wheel paths summon the browser")

// The browser's whole rule: bare keys drive the list, shift drives the preview.
const scrolls = []
const browser = {
  rows: Array.from({ length: 100 }, (_, i) => ({ name: "row" + i })),
  index: 40, listPage: 10, editing: false, naming: "",
  move(step) { this.index = (this.index + step + this.rows.length) % this.rows.length }
}
const preview = { pageStep: 7, panStep: 3, scrollBy: d => scrolls.push(d),
  scrollTo: f => scrolls.push("to" + f), scrollAcross: d => scrolls.push("x" + d) }
browser.goTo = method(source, "goTo", { root: browser })
const key = keymap("plugins/xpo.files/FilesKeys.js", browser, { doomed: "" }, preview)
key("Key_End");      assert.equal(browser.index, 99)
key("Key_Home");     assert.equal(browser.index, 0)
key("Key_PageUp");   assert.equal(browser.index, 0, "a page off the top clamps")
key("Key_PageDown"); assert.equal(browser.index, 10)
browser.index = 95
key("Key_PageDown"); assert.equal(browser.index, 99, "a page off the end clamps")
assert.deepEqual(scrolls, [], "no bare key reaches the preview")
const shift = 1 << 25
key("Key_PageDown", shift); key("Key_PageUp", shift)
key("Key_Home", shift);     key("Key_End", shift)
key("Key_Right", shift);    key("Key_Left", shift)
assert.deepEqual(scrolls, [7, -7, "to0", "to1", "x3", "x-3"])
assert.equal(browser.index, 99, "no shifted key reaches the list")
console.log("ok: browser bare keys drive the list, shift drives the preview")

// The wheel's query edits at the caret, not at the end.
const copied = []
const wheelSource = read("plugins/xpo.wheel/Wheel.qml")
const dial = { query: "", queryAt: 0, results: [], resultIndex: 0,
  get searching() { return this.query.length > 0 },
  dismiss: () => copied.push("dismissed") }
dial.insert = method(wheelSource, "insert", { root: dial })
dial.paste = method(wheelSource, "paste", { root: dial,
  Quickshell: { clipboardText: "pasted  text" } })
dial.takePath = method(wheelSource, "takePath", { root: dial,
  Quickshell: { execDetached: c => copied.push(c.at(-1)) } })
const dialKey = keymap("plugins/xpo.wheel/MenuKeys.js", dial)
const ctrl = 1 << 26
// A printable key is only its text here: the handler falls through to event.text.
const type = text => [...text].forEach(c => dialKey("", 0, c))
type("firefox")
assert.equal(dial.query + "|" + dial.queryAt, "firefox|7")
for (let i = 0; i < 4; i++) dialKey("Key_Left")
assert.equal(dial.queryAt, 3)
type("XY")
assert.equal(dial.query + "|" + dial.queryAt, "firXYefox|5", "typing lands at the caret")
dialKey("Key_Backspace"); dialKey("Key_Backspace")
assert.equal(dial.query + "|" + dial.queryAt, "firefox|3", "backspace eats before the caret")
dialKey("Key_K", ctrl)
assert.equal(dial.query, "fir", "ctrl+k kills to the end")
dialKey("Key_A", ctrl); assert.equal(dial.queryAt, 0)
dialKey("Key_Left");    assert.equal(dial.queryAt, 0, "the caret stops at the start")
dialKey("Key_E", ctrl); assert.equal(dial.queryAt, 3)
dialKey("Key_Right");   assert.equal(dial.queryAt, 3, "the caret stops at the end")
dialKey("Key_V", ctrl)
assert.equal(dial.query, "firpasted text", "a pasted run of whitespace collapses")
dialKey("Key_U", ctrl)
assert.equal(dial.query + "|" + dial.queryAt, "|0", "ctrl+u from the end still clears")
type("a b c")
dialKey("Key_Left"); dialKey("Key_Left")
dialKey("Key_W", ctrl)
assert.equal(dial.query + "|" + dial.queryAt, "a  c|2", "ctrl+w takes the word before the caret")

// Ctrl+Y takes a path away; anything else on the ring is not a path.
dial.results = [{ label: "Firefox", appId: "firefox" }, { path: "/home/test/notes.md" }]
dial.resultIndex = 0
dialKey("Key_Y", ctrl); assert.deepEqual(copied, [], "an app row has no path to copy")
dial.resultIndex = 1
dialKey("Key_Y", ctrl)
assert.deepEqual(copied, ["/home/test/notes.md", "dismissed"])
console.log("ok: wheel query edits at the caret, and a path can be taken away")

// A panel cannot tell how it was opened, so the wheel answers for it: only the
// panel the wheel put on screen, and only while it is still there.
const opened = {}
const ring = { pluginId: "xpo.wheel", launched: "",
  shell: { isPluginOpen: id => opened[id] === true,
           hide: id => { opened[id] = false },
           summon: id => { opened[id] = true } } }
const back = method(read("plugins/xpo.wheel/Wheel.qml"), "back",
  { root: ring, Qt: { callLater: fn => fn() } })
assert.equal(back(), "none", "a wheel that opened nothing owes nothing")
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
assert.equal(back(), "wheel")
assert.equal(opened["omarchy.audio"], false, "the wheel takes the panel away itself")
assert.equal(opened["xpo.wheel"], true)
opened["omarchy.network"] = true
ring.launched = ""
assert.equal(back(), "none", "a panel opened from the bar keeps its backspace")
ring.launched = "omarchy.audio"
assert.equal(back(), "none", "and one that has since gone is not owed a return")
console.log("ok: only the panel the wheel opened answers backspace with a return")

// Backspace is one key with three jobs, taken in order: shorten the filter,
// walk up a directory, leave for the wheel. Home is the floor, so the press
// that cannot go up is the one that goes back.
const walk = { home: "/home/test", dir: "/home/test/a/b", filter: "ab",
  editing: false, naming: "", left: 0,
  up() { this.dir = F.parentOf(this.dir) }, toWheel() { this.left++ } }
const walkKey = keymap("plugins/xpo.files/FilesKeys.js", walk, { doomed: "" }, {})
walkKey("Key_Backspace"); assert.equal(walk.filter, "a", "the filter goes first")
walkKey("Key_Backspace"); assert.equal(walk.filter, "")
walkKey("Key_Backspace"); assert.equal(walk.dir, "/home/test/a")
walkKey("Key_Backspace"); assert.equal(walk.dir, "/home/test")
assert.equal(walk.left, 0, "nothing leaves while there is somewhere to go")
walkKey("Key_Backspace"); assert.equal(walk.left, 1, "home has nowhere left but out")
assert.equal(walk.dir, "/home/test", "and it does not climb past home on the way")
console.log("ok: backspace shortens, then climbs, then leaves for the wheel")

// One wash, owned by the bar, behind every shell surface. A plugin that paints
// its own takes Hyprland's blur down with it when it unmaps -- which is the
// flash that stood for eight sessions and survived two timing fixes, because
// timing was never what was wrong. So neither may paint one, and both must hand
// the bar their open state instead.
for (const f of ["plugins/xpo.wheel/Wheel.qml", "plugins/xpo.files/Files.qml"]) {
  assert.doesNotMatch(read(f), /color:\s*Color\.menu\.scrim/, f + " paints its own scrim")
  assert.match(read(f), /panelSurfaceVisible\(/, f + " never counts on the bar's")
}
console.log("ok: neither plugin paints a scrim; both count on the bar's")

// 4.0.3 hands a plugin a facade scoped to its own id instead of the host
// shell, which is nothing to an overlay built to launch other plugins.
// centered-panels.md has the full symptom list. Run the patched function
// rather than grep for it: a comment naming the namespace satisfies a regex
// and restores nothing, and an upstream rebase can leave the line in a
// function no longer on the injection path.
const scoped = { sandboxed: true }
const host = { createScopedPluginShell: () => scoped, pluginHasBarCapabilities: () => false }
const shellFor = method(read("patches/shell/shell.qml"), "pluginShellFor", { shell: host })
for (const id of ["xpo.wheel", "xpo.files"])
  assert.equal(shellFor({ id, __isFirstParty: false }), host, id + " is sandboxed")
// The grant is ours alone, and it is a prefix, not a substring: `notxpo.thing`
// is somebody else's plugin.
for (const id of ["third.party", "notxpo.thing"])
  assert.equal(shellFor({ id, __isFirstParty: false }), scoped, id + " was handed the host shell")
console.log("ok: xpo. plugins get the host shell, nobody else does")

// revert.sh needs no assertion here: install.py walks every patches/orig/*.qml
// and checks revert put it back, so shell.qml joined that the moment it existed.
assert.match(read("install.sh"), /\bshell\.qml\b/, "install.sh does not carry shell.qml")
console.log("ok: install.sh carries shell.qml")
