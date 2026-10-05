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
  return (key, modifiers = 0, text = "") => {
    const event = { key: Qt[key], modifiers, text, accepted: false }
    onKey(...bound, event)
    return event
  }
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
  return files.paths.map((p, i) => ({ p, i, name: p.toLowerCase().replace(/\/$/, "").split("/").pop() }))
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
for (const query of ["", "a", "e", "home", "wheel", " WHEEL ", "a beta", "space name", "é", "zzz",
  "/", "beta/", "a/", "/beta", "1/a"])
  for (const limit of [0, 1, 8, 40, 5001])
    assert.deepEqual(M.fileRows(files, query, limit, "/home/test"), reference(files, query, limit))
assert.deepEqual(M.fileRows(null, "a", 40, "/home/test"), [])
const app = M.liveRows({ apps: [{ entry: { id: "broken", icon: "/missing.png" } }],
  windows: [] })[0]
assert.ok(app.icon)
console.log("ok: file search ordering, limits, ties, and app fallback glyph")

// "lock" locks first, even after the designs row is used more; the designs show only in its submenu.
const lockMenu = M.merge({ system: { label: "System" }, "system.lock": { label: "Lock", action: "omarchy-system-lock" },
  style: { label: "Style" } }, M.lockItems(["rally", "wallpaper"]))
const lockRows = M.menuRows(lockMenu, M.NO_CONDITIONS)
assert.deepEqual(M.search(lockRows, "lock", 40, { "style.lockscreen": 9 }).map(e => e.label), ["Lock", "Lockscreen Designs"])
assert.deepEqual(M.search(lockRows, "rally", 40, {}), [])
assert.deepEqual(M.childrenOf(lockMenu, "style.lockscreen", M.NO_CONDITIONS).map(e => [e.label, e.action]),
  [["Rally", "omarchy-lock-design set 'rally'"], ["Wallpaper", "omarchy-lock-design set 'wallpaper'"]])
console.log("ok: \"lock\" finds Lock, then one Lockscreen Designs row whose submenu sets a design")

// Omarchy takes `aliases` as one string or a list, and a bar widget as its bare id.
const aliased = M.menuRows({ notes: { label: "Notes", action: "notes", aliases: "memo" },
  todo: { label: "Todo", action: "todo", aliases: ["tasks"] } }, M.NO_CONDITIONS)
assert.deepEqual(M.search(aliased, "memo", 40, {}).map(r => r.label), ["Notes"])
assert.deepEqual(M.search(aliased, "tasks", 40, {}).map(r => r.label), ["Todo"])
assert.deepEqual(M.panels(M.barWidgets(JSON.stringify({ bar: { layout: {
  left: ["omarchy.audio"], right: [{ id: "omarchy.network" }, "omarchy.power"] } } }))).map(p => p.plugin),
  ["omarchy.audio", "omarchy.network", "omarchy.power", "omarchy.clipboard"])
console.log("ok: a string alias and a bare-id bar widget read as Omarchy reads them")

// A holding `checked` marks its row wherever it shows, as do the current theme and font, and an
// icon keeps the font it is drawn in.
const defaults = { setup: { label: "Setup" }, "setup.browser": { label: "Browser" },
  "setup.browser.brave": { label: "Brave", action: "b", when: "w", checked: "c" },
  "setup.browser.zen": { label: "Zen", action: "z", checked: "c", icon: "", iconFont: "omarchy" } }
const answered = M.parseConditions("setup.browser.brave:w\nsetup.browser.brave:c\n", defaults)
const browsers = M.childrenOf(defaults, "setup.browser", answered)
assert.deepEqual(browsers.map(e => e.label), ["Brave ✓", "Zen"])
assert.equal(browsers[1].iconFont, "omarchy")
const marked = M.menuRows(defaults, answered)
assert.deepEqual(M.search(marked, "brave", 40, {}).map(r => r.label), ["Brave ✓"])
for (const delegate of ["WheelResults.qml", "WheelRing.qml"])
  assert.match(read("plugins/xpo.wheel/" + delegate), /font\.family: modelData\.iconFont \|\| Style\.font\.menuFamily/,
    delegate + " draws every icon in the menu font")
assert.deepEqual(M.styles(["Catppuccin", "Osaka Jade"], "Osaka Jade", ["Geist"], "Geist")
  .map(r => r.label + "|" + r.action), ["Catppuccin|omarchy theme set 'Catppuccin'",
  "Osaka Jade ✓|omarchy theme set 'Osaka Jade'", "Geist ✓|omarchy font set 'Geist'"])
assert.deepEqual(M.lockItems([]), {}, "designs not listed yet made an empty submenu")
console.log("ok: checked rows and the current theme and font are marked; icons keep their font")

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

// Ctrl+T pops the overlay out into a window the shell no longer counts as open.
// A summon then raises the window, and moves it only when a path asks.
const popped = []
const win = { opened: true, windowed: false, editing: false, filter: "", naming: "",
  dir: "/home/test/here", shell: { hide: id => popped.push("hide " + id) },
  raise: () => popped.push("raise"), enter(d) { this.dir = d }, claimPending() {},
  focusedScreen: () => null }
const winScope = { root: win, keys: { forceActiveFocus() {} }, Qt: { callLater: fn => fn() } }
win.popOut = method(source, "popOut", winScope)
win.close = method(source, "close", winScope)
const winKey = keymap("plugins/xpo.files/FilesKeys.js", win, { doomed: "" }, {})
winKey("Key_T", 1 << 26)
assert.equal(win.windowed, true)
assert.equal(win.opened, false)
assert.deepEqual(popped, ["hide xpo.files"], "the shell forgets the overlay once")
winKey("Key_T", 1 << 26); winKey("Key_Escape")
assert.deepEqual(popped, ["hide xpo.files"], "a window neither pops out again nor closes on Escape")
const winOpen = method(source, "open", winScope)
winOpen("{}")
assert.equal(win.dir, "/home/test/here", "a bare summon keeps the window's place")
winOpen('{"dir":"/home/test/there","select":"a.txt"}')
assert.equal(win.dir, "/home/test/there")
assert.equal(win.pending, "a.txt")
assert.equal(win.opened, false, "a summon never reopens the overlay over the window")
assert.deepEqual(popped.slice(1), ["raise", "raise"])
console.log("ok: ctrl+t pops out once; the window ignores Escape, keeps its place, and is raised")

const opsSource = read("plugins/xpo.files/FilesOps.qml")
const busy = { root: { note: text => calls.push(text) }, filer: { running: true } }
method(opsSource, "run", busy)(["cp"], {})
assert.equal(busy.root.op, undefined)
assert.match(calls.at(-1), /still running/)

const listSource = read("plugins/xpo.files/FilesList.qml")
const clickHandler = listSource.match(/onClicked:\s*([^\n]+)/)[1]
const activated = []
new Function("operations", "panel", "entry", clickHandler)(
  { activate: entry => activated.push(entry) }, {}, { modelData: { name: "picked" } })
assert.deepEqual(activated, [{ name: "picked" }], "clicking a file row does not activate it")
assert.match(source, /FilesList\s*\{[^}]*operations:\s*ops/s,
  "Files.qml does not hand its operations object to the list")

const wheel = { root: { countUse() {}, dismiss() {}, slices: [], copy: text => calls.push(text), shell: {
  summon: (id, payload) => calls.push([id, JSON.parse(payload)]),
  toggle() { throw new Error("navigation must summon") }
} }, Qt: { callLater: fn => fn() }, MenuIndex: M,
  Hyprland: { dispatch: expression => calls.push(["dispatch", expression]) } }
const runRow = method(read("plugins/xpo.wheel/Wheel.qml"), "run", wheel)
runRow({ path: "/home/test/new.txt" })
assert.equal(calls.at(-1)[0], "xpo.files")
assert.equal(calls.at(-1)[1].select, "new.txt")
runRow({ copy: "42" })
assert.equal(calls.at(-1), "42")
runRow({ dispatch: "hl.dsp.window.pseudo()" })
assert.deepEqual(calls.at(-1), ["dispatch", "hl.dsp.window.pseudo()"])
console.log("ok: busy operations report refusal; wheel paths summon the browser, answers are copied, Lua binds dispatch")

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
// Ctrl+Enter is a terminal in the folder being browsed; Enter alone still opens the selection.
const browsed = []
const terminalOps = { doomed: "", activate: () => browsed.push("open"),
  terminal: method(read("plugins/xpo.files/FilesOps.qml"), "terminal", {
    panel: { dir: "/home/test/My Dir", close: () => browsed.push("closed") },
    Quickshell: { execDetached: argv => browsed.push([...argv]) } }) }
const browserKey = keymap("plugins/xpo.files/FilesKeys.js", browser, terminalOps, preview)
browserKey("Key_Return", 1 << 26); browserKey("Key_Return")
assert.deepEqual(browsed, ["closed", ["uwsm-app", "--", "xdg-terminal-exec", "--dir=/home/test/My Dir"], "open"])
console.log("ok: browser bare keys drive the list, shift drives the preview, ctrl+enter opens a terminal")

// The query field types, deletes, moves and selects, Home, End and Ctrl+A included; the rest is the wheel's.
const copied = []
const wheelSource = read("plugins/xpo.wheel/Wheel.qml")
const dial = { query: "", queryAt: 0, results: [], resultIndex: 0,
  get searching() { return this.query.length > 0 },
  dismiss: () => copied.push("dismissed"), showResult() {}, moveResult(step) { this.resultIndex += step } }
const edit = (query, at) => { dial.query = query; dial.queryAt = at }
// TextInput's remove() does nothing for an empty selection; insert() moves the caret past its text.
const field = { selectionStart: 0, selectionEnd: 0, get cursorPosition() { return dial.queryAt },
  remove(from, to) { if (from < to) edit(dial.query.slice(0, from) + dial.query.slice(to), from) },
  insert(at, text) { edit(dial.query.slice(0, at) + text + dial.query.slice(at), at + text.length) } }
dial.paste = method(wheelSource, "paste", { root: dial, searchInput: field,
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
dial.terminal = method(wheelSource, "terminal", { root: dial, Qt: { callLater: fn => fn() }, MenuIndex: M,
  Quickshell: { execDetached: argv => terminals.push([...argv]) } })
dial.results.push({ path: "/home/test/My Dir/" })
dial.resultIndex = 0; dialKey("Key_Return", ctrl)
assert.deepEqual([terminals, entered.map(e => e.appId)], [[], ["firefox"]], "ctrl+enter on an app is not enter")
dial.resultIndex = 1; dialKey("Key_Return", ctrl)
dial.resultIndex = 2; dialKey("Key_Enter", ctrl)
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
const placeholder = wheelSource.match(/visible: !root\.searching\n\s+text: "([^"]+)"/)[1]
for (const sigil of Object.keys(M.MODES)) assert.ok(placeholder.includes(sigil + " "), `the placeholder hides ${sigil}`)
console.log("ok: the search placeholder names every search sigil")

// A panel cannot tell how it was opened, so the wheel answers for it: only the
// panel the wheel put on screen, and only while it is still there.
const opened = {}
const picked = []
const ring = { pluginId: "xpo.wheel", launched: "", launchedAt: -1,
  slices: [{}, {}, {}], get sliceCount() { return this.slices.length },
  select: i => picked.push(i),
  shell: { isPluginOpen: id => opened[id] === true,
           hide: id => { opened[id] = false },
           summon: id => { opened[id] = true } } }
const back = method(read("plugins/xpo.wheel/Wheel.qml"), "back",
  { root: ring, Qt: { callLater: fn => fn() } })
assert.equal(back(), "none", "a wheel that opened nothing owes nothing")
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
assert.equal(back(), "wheel")
assert.equal(opened["omarchy.audio"], true, "the panel stays up until the wheel claims its surface")
assert.equal(opened["xpo.wheel"], true)
opened["omarchy.audio"] = false
opened["omarchy.network"] = true
ring.launched = ""
assert.equal(back(), "none", "a panel opened from the bar keeps its backspace")
ring.launched = "omarchy.audio"
assert.equal(back(), "none", "and one that has since gone is not owed a return")
console.log("ok: only the panel the wheel opened answers backspace with a return")

// Search takes every panel the live bar can open, whether or not it has a disc.
const indexed = { staticRows: M.panelRows(M.OVERLAYS.concat(M.EXTRAS)),
  styleRows: [], bindRows: [], menuItems: {}, focusOrder: [], appLibrary: null,
  shell: { panels: () => [
    { id: "omarchy.weather", name: "Weather", source: "omarchy.weather" },
    { id: "alice.audio", name: "Alice Audio", source: "omarchy.audio" },
    { id: "third.notes", name: "Notes", source: "third.notes" },
    { id: "xpo.files", name: "Files", source: "xpo.files" }] } }
const rebuildIndex = method(wheelSource, "rebuildIndex",
  { root: indexed, MenuIndex: M, Hyprland: { toplevels: { values: [] } } })
rebuildIndex()
const hits = query => M.search(indexed.index, query, 40, {}).map(r => r.plugin)
assert.ok(hits("weather").includes("omarchy.weather"), "Weather is not searchable")
assert.ok(hits("audio").includes("alice.audio"), "a clone is not searchable by its source")
assert.ok(hits("notes").includes("third.notes"), "a third-party panel is not searchable")
assert.equal(indexed.index.find(r => r.plugin === "alice.audio").icon, M.PANELS[0].icon,
  "a clone lost its source's mark")
assert.ok(indexed.index.find(r => r.plugin === "third.notes").icon, "an unknown panel has no mark")
assert.equal(indexed.index.filter(r => r.plugin === "xpo.files").length, 1,
  "a panel with a fixed search row was listed twice")
assert.ok(!M.panels(null).some(p => p.plugin === "omarchy.weather"), "Weather joined the ring")
indexed.shell = {}
rebuildIndex()
assert.equal(indexed.index.length, indexed.staticRows.length,
  "a facade without panels() fills search")
console.log("ok: every panel the bar can open is searchable, on the ring or not")

// The host closes peers without exposing its panel registries to the wheel.
const openPeers = { "xpo.wheel": true, "xpo.files": true, "omarchy.menu": true }
const popoutBar = {
  activePopout: null,
  pluginOwnsBarObject: (id, owner) => owner && owner.pluginId === id
}
const oldPanel = { closed: false, closeForPopoutSwitch() {
  this.closed = true
  popoutBar.activePopout = null
} }
popoutBar.activePopout = oldPanel
const hostShell = {
  bar: popoutBar,
  barHasPluginPopouts: () => true,
  isPluginOpen: id => openPeers[id] === true,
  hide: id => { openPeers[id] = false }
}
const shellSource = read("patches/shell/shell.qml")
const closePluginPeers = method(shellSource, "closePluginPeers", {
  shell: hostShell,
  openPanelIds: { "xpo.wheel": true, "xpo.files": true },
  panelLoaders: { "omarchy.menu": {} }
})
const peers = closePluginPeers("xpo.wheel")
assert.equal(peers.clear, true)
assert.equal(oldPanel.closed, true, "the old bar panel is switched out")
assert.equal(openPeers["xpo.files"], false, "an open overlay is closed")
assert.equal(openPeers["omarchy.menu"], false, "a directly opened overlay is closed")

// A custom full bar need not implement plugin popout ownership.
const bareBar = { activePopout: null }
bareBar.activePopout = { closeForPopoutSwitch() { bareBar.activePopout = null } }
const bareShell = { bar: bareBar, isPluginOpen: () => false, hide() {} }
bareShell.barHasPluginPopouts = method(shellSource, "barHasPluginPopouts", { shell: bareShell })
const closeBarePeers = method(shellSource, "closePluginPeers",
  { shell: bareShell, openPanelIds: {}, panelLoaders: {} })
const bare = closeBarePeers("xpo.wheel")
assert.ok(bare.acted && bare.clear, "a bar without plugin popouts still switches its panel out")
bareBar.activePopout = { close() {} }
const sticky = closeBarePeers("xpo.wheel")
assert.ok(sticky.acted && !sticky.clear, "a bar panel that stays open keeps the wheel hidden")

// Third-party panels join search; Omarchy's own are already in its menu.
const hostPanels = method(shellSource, "summonablePanels", { shell: { bar: null, panelEntries: [
  { id: "third.radar", manifest: { name: "Radar" } },
  { id: "omarchy.clipboard", manifest: { name: "Clipboard", __isFirstParty: true } }] } })
assert.equal(String(hostPanels().map(p => p.id)), "third.radar", "Omarchy's own panels were listed")

let claimedPopout = null
const opening = {
  shell: {
    closePeers: () => ({ acted: false, clear: true }),
    claimPopout: owner => { claimedPopout = owner },
    releasePopout: owner => { if (claimedPopout === owner) claimedPopout = null }
  },
  opened: false, sliceCount: 8, focusedScreen: () => null, rebuildIndex() {}, reread() {}
}
opening.closePeers = method(wheelSource, "closePeers", { root: opening })
const openingScope = { root: opening, unmap: { running: false, stop() {} },
  spin: { stepsLeft: 0, restart() {} }, searchInput: { forceActiveFocus() {} },
  Qt: { callLater: fn => fn() } }
method(wheelSource, "open", openingScope)("{}")
assert.equal(claimedPopout, opening, "the wheel owns the popout slot")
assert.equal(opening.opened, true)
method(wheelSource, "close", { root: opening, unmap: { stop() {} } })(true)
assert.equal(claimedPopout, null, "closing releases the popout slot")
openPeers["xpo.files"] = true
hostShell.hide = () => {}
opening.shell.closePeers = () => closePluginPeers("xpo.wheel")
method(wheelSource, "open", openingScope)("{}")
assert.equal(opening.opened, false, "a peer protecting unsaved work keeps the wheel hidden")
console.log("ok: the wheel replaces an open panel instead of stacking above it")

// `back` can only give back what `run` wrote down.
// Recorded off `slices`, so a slice picked with the pointer is written down the
// same as one picked with the arrows.
const ran = { countUse() {}, dismiss() {}, launchedAt: null,
  slices: [{ plugin: "a" }, { plugin: "b" }, { plugin: "c" }] }
const runPick = method(wheelSource, "run",
  { root: ran, Qt: { callLater() {} }, MenuIndex: M })
runPick(ran.slices[2])
assert.equal(ran.launchedAt, 2, "the slice that was run is written down")
runPick({ plugin: "off-ring" })
assert.equal(ran.launchedAt, -1, "a pick that is on no ring writes down nothing")
console.log("ok: running a slice records which slice it was")

// A step back hands the ring over the way it was left. Without this the wheel
// comes up with selected at -1 while the comet still rests on the slice that
// launched, so the ring looks selected and the arrows do not step from it --
// right and left jump to the east and west slices instead of to the neighbours.
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
ring.launchedAt = 2; picked.length = 0
assert.equal(back(), "wheel")
assert.deepEqual(picked, [2], "the slice that launched is selected again")
// A search result sits on no ring, so there is no slice to give back.
picked.length = 0
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
ring.launchedAt = -1
assert.equal(back(), "wheel")
assert.deepEqual(picked, [], "a search result restores no selection")
// wheel.json is watched, so the ring can be shorter than when the panel went up.
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
ring.launchedAt = 9
assert.equal(back(), "wheel")
assert.deepEqual(picked, [], "a stale index is dropped, not selected")
console.log("ok: backspace gives the ring back the slice it was left on")

// Left and right step one slice, from the first press onward. A fresh wheel has
// nothing selected and rests at the top, so that is what the first step comes
// off -- landing on the east or west slice instead skipped whatever sat between
// it and the top. Nine slices at 40 degrees, odd, so slice 0 is the top one.
function dialAt(count, selected) {
  const seen = []
  const w = { selected, sliceCount: count, searching: false,
    sliceOrigin: count % 2 === 0 ? 90 % (360 / count) : 0,
    get sliceStep() { return 360 / count },
    select(i) { seen.push(i); this.selected = i },
    rotate: null, nearestSlice: null }
  w.nearestSlice = method(wheelSource, "nearestSlice", { root: w })
  w.rotate = method(wheelSource, "rotate", { root: w })
  return { wheel: w, seen, key: keymap("plugins/xpo.wheel/MenuKeys.js", w) }
}
let ring9 = dialAt(9, -1)
ring9.key("Key_Right")
assert.deepEqual(ring9.seen, [1], "right off a fresh ring steps to the next slice")
ring9 = dialAt(9, -1)
ring9.key("Key_Left")
assert.deepEqual(ring9.seen, [8], "and left to the previous one, not to the west slice")
// Then it keeps stepping, and wraps rather than stopping at either end.
ring9 = dialAt(9, 0)
for (let i = 0; i < 3; i++) ring9.key("Key_Right")
assert.deepEqual(ring9.seen, [1, 2, 3], "every press after the first is one slice too")
// Up and down still name a place rather than stepping.
ring9 = dialAt(9, 3)
ring9.key("Key_Up"); assert.equal(ring9.wheel.selected, 0, "up is the top slice")
// An empty ring has nowhere to go, and must not select NaN on the way there.
const empty = dialAt(0, -1)
empty.key("Key_Right")
assert.deepEqual(empty.seen, [], "an empty ring selects nothing at all")
console.log("ok: the ring steps one slice a press, from the top when it is fresh")

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

// The bar owns the shared backdrop so panel handoffs preserve blur.
for (const f of ["plugins/xpo.wheel/Wheel.qml", "plugins/xpo.files/Files.qml"]) {
  assert.doesNotMatch(read(f), /color:\s*Color\.menu\.scrim/, f + " paints its own scrim")
  assert.match(read(f), /onOpenedChanged:[\s\S]*?panelSurfaceVisible\(root\.opened\)/,
    f + " does not drive the bar scrim from its open state")
}
console.log("ok: neither plugin paints a scrim; both count on the bar's")

// Every third-party plugin gets a facade. A namespace must never grant the
// host ShellRoot: another plugin can choose the same prefix or even the same id.
const scoped = []
const host = {
  createScopedPluginShell: (...args) => { const api = { args }; scoped.push(api); return api },
  pluginHasBarCapabilities: () => false
}
const shellFor = method(shellSource, "pluginShellFor", { shell: host })
for (const id of ["xpo.wheel", "xpo.files", "xpo.hostile", "third.party"])
  assert.notEqual(shellFor({ id, __isFirstParty: false }), host, id + " received ShellRoot")
assert.equal(scoped.length, 4)

const manifests = {
  "ui.panel": { kinds: ["panel"] },
  "disabled.panel": { kinds: ["panel"] },
  "auth.service": { kinds: ["panel"] },
  "plain.service": { kinds: ["service"] }
}
const permissionShell = {
  manifestHasKind: (manifest, kind) => manifest.kinds.includes(kind),
  pluginHasVisualCapabilities: manifest => manifest.kinds.some(k =>
    ["bar-widget", "panel", "overlay", "menu"].includes(k)),
  pluginRegistry: {
    resolveEnabledId: id => id,
    installedPlugins: manifests,
    isEnabled: id => id !== "disabled.panel"
  },
  isAuthenticationService: (manifest, id) => id === "auth.service"
}
const menuMayControl = method(shellSource, "menuPluginMayControl", { shell: permissionShell })
assert.equal(menuMayControl({ kinds: ["menu"] }, "ui.panel"), true)
assert.equal(menuMayControl({ kinds: ["overlay"] }, "ui.panel"), false)
assert.equal(menuMayControl({ kinds: ["menu"] }, "disabled.panel"), false)
assert.equal(menuMayControl({ kinds: ["menu"] }, "auth.service"), false)
assert.equal(menuMayControl({ kinds: ["menu"] }, "plain.service"), false)

const surfaceCalls = []
const surfaceScope = {
  _pluginSurfaceStates: ({}),
  shell: { bar: { panelSurfaceVisible: shown => surfaceCalls.push(shown) } }
}
const setSurfaceVisible = method(shellSource, "setPluginSurfaceVisible", surfaceScope)
setSurfaceVisible("xpo.wheel", false)
setSurfaceVisible("xpo.wheel", true)
setSurfaceVisible("xpo.wheel", true)
setSurfaceVisible("xpo.wheel", false)
assert.deepEqual(surfaceCalls, [true, false], "a plugin cannot inflate the scrim count")

for (const file of ["plugins/xpo.wheel/Wheel.qml", "plugins/xpo.files/Files.qml"])
  assert.doesNotMatch(read(file), /root\.shell\.(?:bar|openPanelIds|panelLoaders|callIfLoaded)\b/,
    file + " reaches through its facade")
assert.match(read("plugins/xpo.wheel/manifest.json"), /"menu"/,
  "the wheel lacks the menu capability")
for (const plugin of ["xpo.wheel", "xpo.files"])
  require("node:child_process").execFileSync("omarchy",
    ["plugin", "validate", path.join(repo, "plugins", plugin)], { stdio: "inherit" })
console.log("ok: xpo plugins use narrow facades and menus control only UI plugins")

require("./scene.js")
require("./trails.js")
