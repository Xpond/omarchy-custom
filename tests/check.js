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

// A full-sort reference checks ordering, picks, stable ties, and multi-term matching.
function reference(files, query, limit, uses = {}) {
  const q = query.trim().toLowerCase()
  if (!q) return []
  return files.paths.map((p, i) => ({ p, i, name: p.toLowerCase().replace(/\/$/, "").split("/").pop() }))
    .filter(e => q.split(/\s+/).every(t => e.p.toLowerCase().includes(t)))
    .map(e => ({ ...e, rank: e.name.startsWith(q) ? 0 : e.name.includes(q) ? 1 : 2, used: uses["file:" + e.p] || 0 }))
    .sort((a, b) => a.rank - b.rank || b.used - a.used || (!a.used && a.name.length - b.name.length) || a.i - b.i)
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
// Every ninth path picked, up to three times: a pick leads its rank and never leaves it.
const fileUses = {}
paths.forEach((p, i) => { if (i % 9 === 0) fileUses["file:" + p] = 1 + (i / 9) % 3 })
for (const query of ["a", "e", "wheel", "a beta"])
  for (const limit of [1, 8, 40, 5001])
    assert.deepEqual(M.fileRows(files, query, limit, "/home/test", false, fileUses), reference(files, query, limit, fileUses))
assert.deepEqual(M.fileRows(null, "a", 40, "/home/test"), [])
const app = M.liveRows({ apps: [{ entry: { id: "broken", icon: "/missing.png" } }],
  windows: [] })[0]
assert.ok(app.icon)
console.log("ok: file search ordering, limits, ties, and app fallback glyph")

// "lock" locks first until the designs row is picked more; the designs show only in its submenu.
const lockMenu = M.merge({ system: { label: "System" }, "system.lock": { label: "Lock", action: "omarchy-system-lock" },
  style: { label: "Style" } }, M.lockItems(["rally", "wallpaper"]))
const lockRows = M.menuRows(lockMenu, M.NO_CONDITIONS)
assert.deepEqual(M.search(lockRows, "lock", 40, {}).map(e => e.label), ["Lock", "Lockscreen Designs"])
assert.deepEqual(M.search(lockRows, "lock", 40, { "style.lockscreen": 9 }).map(e => e.label), ["Lockscreen Designs", "Lock"])
// A picked row beats an unpicked one of an earlier kind: "loc" finds Lock before LocalSend.
const localSend = { label: "LocalSend", appId: "localsend", kind: M.KIND.app, keywords: "LocalSend" }
assert.equal(M.search(lockRows.concat([localSend]), "loc", 40, { "system.lock": 1 })[0].label, "Lock")
// Picks never lift a weaker match: "br" finds Brave before Files, whose keywords say browser.
const brave = { label: "Brave", appId: "brave", kind: M.KIND.app, keywords: "Brave" }
const filesPanel = { label: "Files", plugin: "xpo.files", kind: M.KIND.slice, keywords: "Files browser" }
assert.deepEqual(M.search([filesPanel, brave], "br", 40, { "xpo.files": 105 }).map(e => e.label), ["Brave", "Files"])
// A pick moves its key last, through the file too; history lists picks newest first, a file by its
// path, and leaves out settings and keys that name nothing today.
let picks = {}
for (const k of ["system.lock", "file:/home/test/a.txt", "setting:ring", "gone", "system.lock"]) picks = M.withPick(picks, k)
assert.deepEqual(Object.entries(JSON.parse(JSON.stringify(picks))),
  [["file:/home/test/a.txt", 1], ["setting:ring", 1], ["gone", 1], ["system.lock", 2]])
assert.deepEqual(M.historyRows(lockRows, picks, "/home/test").map(r => r.label), ["Lock", "a.txt"])
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

const wheel = { root: { home: "/home/test", countUse() {}, dismiss() {}, slices: [], copy: text => calls.push(text), shell: {
  summon: (id, payload) => calls.push([id, JSON.parse(payload)]),
  toggle() { throw new Error("navigation must summon") }
} }, Qt: { callLater: fn => fn() }, MenuIndex: M, Quickshell: { execDetached: argv => calls.push([...argv]) },
  Hyprland: { dispatch: expression => calls.push(["dispatch", expression]) } }
const runRow = method(read("plugins/xpo.wheel/Wheel.qml"), "run", wheel)
runRow({ path: "/home/test/new.txt" })
assert.equal(calls.at(-1)[0], "xpo.files")
assert.equal(calls.at(-1)[1].select, "new.txt")
runRow({ path: "/mnt/share/movie.mkv" })
assert.deepEqual(calls.at(-1), ["omarchy-open-path", "/mnt/share/movie.mkv"], "a path outside home went to the browser")
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
// A readonly binding of Wheel.qml, evaluated over the names given.
const binding = (name, scope) => new Function(...Object.keys(scope), "return " + wheelSource
  .match(new RegExp("readonly property \\w+ " + name + ": ([^]*?)\\n  (?:readonly )?property"))[1])(...Object.values(scope))
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
const placeholder = wheelSource.match(/visible: !root\.query\n\s+text: ([^]*?)\n\s+color:/)[1].match(/"([^"]+)"$/)[1]
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
  styleRows: [], bindRows: [], settingRows: M.settingRows(M.SHORTCUT, false, [], M.SKIPPED), menuItems: {},
  focusOrder: [], appLibrary: null,
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
assert.equal(indexed.index.length, indexed.staticRows.length + indexed.settingRows.length,
  "a facade without panels() fills search")
console.log("ok: every panel the bar can open is searchable, on the ring or not")

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
  for (const query of ["wheely shortcut", "shortcut", "keybind"])
    assert.equal(M.search(rows, query, 40, {})[0]?.setting, "shortcut", query + " misses the shortcut row")
  for (const query of ["wheely ring", "ring", "slices", "pin"])
    assert.equal(M.search(rows, query, 40, {})[0]?.setting, "ring", query + " misses the ring row")
  for (const query of ["backdrop", "blur", "dim"])
    assert.equal(M.search(rows, query, 40, {})[0]?.setting, "backdrop", query + " misses the backdrop row")
  assert.equal(M.search(rows, "searched folders", 40, {})[0]?.setting, "folders")
  assert.equal(M.search(rows, "skip", 40, {})[0]?.setting, "skipped")
  for (const query of ["forget", "clear picks"])
    assert.equal(M.search(rows, query, 40, {})[0]?.setting, "forget", query + " misses the forget row")
  for (const query of ["centered panels", "panels", "center"])
    assert.equal(M.search(rows, query, 40, {})[0]?.setting, "panels", query + " misses the panels row")
  for (const query of ["history", "wheely history", "recent"])
    assert.equal(M.search(rows, query, 40, {})[0]?.setting, "history", query + " misses the history row")
  assert.equal(M.indexOfEntry(M.settingRows("ALT + SPACE", false, [], M.SKIPPED, 0, true), rows[0]), 0, "saving a key lost the row")
  assert.deepEqual(M.settingRows("SUPER + A", true, ["/mnt"], ["a", "b"], 57, false).map(r => r.trail),
    ["SUPER + A", "Custom", "", "Off", "Home + 1", "2", "57", "57"])
  assert.equal(rows[1].trail, "Bar")
  assert.deepEqual(rows.filter(r => r.icon === M.SETTING_ICON).map(r => r.setting),
    ["shortcut", "ring", "backdrop", "panels", "folders", "skipped", "forget"], "a setting row lost its icon, or history wore it")

  assert.equal(M.comboOf("SUPER SHIFT CTRL + space"), "SUPER + CTRL + SHIFT + SPACE")
  assert.equal(M.bindingAt(records, "SUPER + CTRL + SHIFT + SPACE"), "Theme menu", "another spelling hid a binding")
  assert.equal(M.bindingAt(records, "SUPER + SPACE"), "Omarchy menu")
  assert.equal(M.bindingAt(records, "SUPER + C"), "Universal copy", "a binding no row runs gave up its key")
  assert.equal(M.bindingAt(records, "SUPER + X"), "another binding", "a binding without a description gave up its key")
  assert.equal(M.bindingAt(records, "SUPER + A") + M.bindingAt(records, "SUPER + B"), "")

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
  for (const name of ["edit", "forgetPicks"]) fg[name] = method(wheelSource, name, { root: fg, usesFile })
  const forgetKey = keymap("plugins/xpo.wheel/MenuKeys.js", fg)
  fg.edit({ setting: "forget", trail: "2" })
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
  assert.ok(keyboardPanel.includes("if (centered && screenW > 0") && keyboardPanel.includes("backingWindowVisible && open && centered"),
    "a panel centers or takes the backdrop with the setting off")

  // Recording: a modifier alone waits, plain Esc gives up, plain Enter saves only a candidate,
  // and any other press is judged. shortcutOf's names are checked against real Qt in runtime.py.
  const Q = { ShiftModifier: 1 << 25, ControlModifier: 1 << 26, AltModifier: 1 << 27, MetaModifier: 1 << 28,
              Key_Escape: 1, Key_Return: 2, Key_Enter: 3 }
  const saved = []
  const rec = { shortcut: "SUPER + A", bindText: records, saveShortcut: combo => saved.push(combo) }
  const edit = method(wheelSource, "edit", { root: rec })
  const record = method(wheelSource, "record",
    { root: rec, Qt: Q, MenuIndex: M, MenuKeys: { shortcutOf: event => event.combo } })
  const press = (combo, key = 0, modifiers = Q.MetaModifier) => {
    record({ combo, key, modifiers })
    return rec.editValue + " | " + rec.editNote + " | " + rec.pending
  }
  edit({ setting: "shortcut" })
  assert.equal(press(null), "Press a shortcut | esc cancels | ", "a modifier alone was judged")
  assert.equal(press(""), "Press a shortcut | pick another key | ")
  assert.equal(press("SHIFT + B", 0, Q.ShiftModifier), "SHIFT + B | add SUPER, CTRL or ALT | ")
  assert.equal(press("F13", 0, 0), "F13 | add SUPER, CTRL or ALT | ")
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
  method(wheelSource, "run", { root: setRow, Qt: {}, MenuIndex: M })(rows[0])
  assert.equal(setRow.edited, "shortcut")
}
console.log("ok: settings are rows, the wheel's own bindings are not, and the shortcut row records, judges and saves")

// The ring holds what search finds, by the keys picks are counted under, so a hand-written list of
// panel and menu ids still reads. A row with no key of its own (a window, a file, an answer) or a
// setting cannot join it, and a key that names nothing is dropped.
{
  const index = [...M.panelRows(M.panels({ "omarchy.audio": true, "omarchy.network": true })),
    { id: "system", node: "system", icon: "x", label: "System", kind: M.KIND.menu },
    { appId: "firefox.desktop", appIcon: "firefox", label: "Firefox", kind: M.KIND.app, keywords: "firefox" },
    { label: "Firefox", address: "0x1", kind: M.KIND.window, keywords: "firefox" },
    { label: "notes.md", path: "/home/test/notes.md" }, { label: "42", copy: "42" },
    ...M.settingRows("SUPER + A", false, [], M.SKIPPED, 0, true)]
  assert.deepEqual(index.map(r => M.pinnable(r)),
    [true, true, true, true, true, false, false, false, false, false, false, false, false, false, false, false])
  assert.deepEqual(M.ringOf(index, ["app:firefox.desktop", "omarchy.clipboard", "gone", "setting:ring",
                                    "system", "omarchy.audio"]).map(r => r.label),
    ["Firefox", "Clipboard", "System", "Audio"])
  // The editor's search lists only what a ring can hold, and a sigil opens no other source there.
  const finder = { editingRing: true, query: "/fire", term: "fire", index, resultLimit: 40, uses: {} }
  finder.mode = binding("mode", { root: finder, MenuIndex: M })
  assert.deepEqual(binding("results", { root: finder, MenuIndex: M }).map(r => r.appId || r.address), ["firefox.desktop"],
    "the ring editor offered what a ring cannot hold")
  finder.editingRing = false; finder.mode = ""
  assert.equal(binding("results", { root: finder, MenuIndex: M }).length, 2)
  // A bare `/` lists the files picked before, latest first, and nothing else.
  const bare = { listing: "", mode: "file", term: "", resultLimit: 40, home: "/home/test",
    uses: { "file:/home/test/a": 1, "system.lock": 3, "file:/home/test/b/": 1 } }
  assert.deepEqual(binding("results", { root: bare, MenuIndex: M }).map(r => r.path), ["/home/test/b/", "/home/test/a"])
  // `/` search hands the wheel's picks over: a file opened before leads a shorter name.
  const picker = { listing: "", mode: "file", term: "a", resultLimit: 40, home: "/home/test",
    files: M.parseFiles("/home/test/ab\n/home/test/abc\n"), uses: { "file:/home/test/abc": 1 } }
  assert.deepEqual(binding("results", { root: picker, MenuIndex: M }).map(r => r.label), ["abc", "ab"])

  // The editor edits the ring as drawn, saving each change; the bar's ring is where a first edit starts.
  const saved = []
  const disk = { raw: '{ "other": 1 }', text() { return this.raw }, setText(raw) { this.raw = raw; saved.push(raw) } }
  const ed = { index, ringIds: null, selected: 0, query: "fire", path: ["system"], editingRing: false, resetAsked: true,
    panels: M.panels({ "omarchy.audio": true, "omarchy.network": true }),
    get ring() { return this.ringIds ? M.ringOf(this.index, this.ringIds) : this.panels },
    get slices() { return this.ring }, get sliceCount() { return this.ring.length },
    select(i) { this.selected = i }, enter(node) { this.path = []; this.query = ""; this.selected = -1 },
    countUse() { throw new Error("adding to the ring counted a pick") },
    dismiss() { throw new Error("the ring editor closed the wheel") } }
  const scope = { root: ed, ringFile: disk, MenuIndex: M, Qt: {} }
  for (const name of ["edit", "run", "pin", "unpin", "moveSlice", "resetRing", "saveRing"])
    ed[name] = method(wheelSource, name, scope)
  const ring = () => ed.ring.map(M.keyOf).join(" ") + " @" + ed.selected
  const written = () => JSON.parse(saved.at(-1))

  ed.edit({ setting: "ring" })
  assert.deepEqual([ed.editingRing, ed.resetAsked, ed.path, ed.query], [true, false, [], ""])
  assert.equal(ring(), "omarchy.audio omarchy.network omarchy.clipboard @-1", "the editor did not start from the bar")
  ed.select(0); ed.query = "fire"
  ed.run(index[4])
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network omarchy.clipboard @1",
    "a pick did not land after the selected slice")
  assert.deepEqual(written(), { other: 1, slices: ["omarchy.audio", "app:firefox.desktop", "omarchy.network",
                                                 "omarchy.clipboard"] }, "the file lost what else it held")
  assert.equal(ed.query, "", "a pick left the query up")
  ed.select(3); ed.run(index[4])
  assert.equal(ring() + " " + saved.length, "omarchy.audio app:firefox.desktop omarchy.network omarchy.clipboard @1 1",
    "a slice already on the ring was added twice")
  ed.select(-1); ed.run(index[3])
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network omarchy.clipboard system @4",
    "with nothing selected a pick did not go last")
  ed.moveSlice(1)
  assert.equal(ring(), "system app:firefox.desktop omarchy.network omarchy.clipboard omarchy.audio @0",
    "past the last slice a move did not wrap to the first")
  ed.moveSlice(-1); ed.moveSlice(-1)
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network system omarchy.clipboard @3")
  ed.unpin(); ed.unpin()
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network @2", "del did not keep its place")
  assert.deepEqual(written().slices, ["omarchy.audio", "app:firefox.desktop", "omarchy.network"])

  // Ctrl+R asks once and acts on the second; an emptied ring follows the bar as well.
  const writes = saved.length
  ed.resetRing()
  assert.equal(ed.resetAsked + " " + saved.length, "true " + writes, "ctrl+r acted on the first press")
  ed.resetRing()
  assert.deepEqual([ed.ringIds, ed.resetAsked, written()], [null, false, { other: 1 }])
  ed.resetRing()
  assert.equal(ed.resetAsked + " " + saved.length, "false " + (writes + 1), "the bar's ring asked to be reset")
  ed.select(-1); ed.run(index[3]); ed.select(0)
  ed.unpin(); ed.unpin(); ed.unpin(); ed.unpin()
  assert.deepEqual([ed.ringIds, written()], [null, { other: 1 }], "an emptied ring did not follow the bar")
}

// In the ring editor Del, Shift+arrows and Esc belong to the ring until a query is typed, and then
// to the field. Ctrl+R's question is taken back by any key but a modifier on its way to Ctrl+R.
{
  const did = []
  const ringed = { editingRing: true, resetAsked: false, query: "", queryAt: 0,
    get searching() { return this.query.length > 0 },
    unpin: () => did.push("unpin"), moveSlice: step => did.push("move " + step),
    resetRing() { did.push("reset") }, rotate: step => did.push("rotate " + step),
    up: () => false, dismiss: () => did.push("dismiss") }
  const ringKey = keymap("plugins/xpo.wheel/MenuKeys.js", ringed)
  ringKey("Key_Delete"); ringKey("Key_Right", shift); ringKey("Key_Left", shift); ringKey("Key_Right")
  assert.deepEqual(did.splice(0), ["unpin", "move 1", "move -1", "rotate 1"])
  ringed.query = "fi"
  for (const [key, modifiers] of [["Key_Delete", 0], ["Key_Left", shift], ["Key_Right", shift]])
    assert.equal(ringKey(key, modifiers).accepted, false, key + " left the field while typing")
  ringKey("Key_Escape")
  assert.deepEqual([ringed.query, ringed.editingRing], ["", true], "esc on a query left the editor")
  ringKey("Key_R", ctrl); ringed.resetAsked = true
  ringKey("Key_Control", ctrl); ringKey("Key_R", ctrl)
  assert.deepEqual([did.splice(0), ringed.resetAsked], [["reset", "reset"], true], "a modifier took the question back")
  ringKey("Key_A", 0, "a")
  assert.equal(ringed.resetAsked, false, "another key left ctrl+r armed")
  ringKey("Key_Escape")
  assert.deepEqual([ringed.editingRing, did], [false, []], "esc did not leave the editor, or closed the wheel")
}
console.log("ok: the ring takes what search finds, and its editor adds, moves, removes and goes back to the bar")

// Until a list changes, `/` scans home as it always has; folders outside home get a scan of their own,
// and a skip with a slash anchors under home, so only home's scan takes it. Run against fd itself.
{
  const home = "/home/test"
  assert.equal(M.scanCommand([home], M.SKIPPED, home).join(" "),
    "fd --hidden --max-depth 6 --exclude .cache --exclude .git --exclude node_modules . /home/test")
  assert.equal(M.scanCommand([home], ["~/Android"], home).join(" "), "fd --hidden --max-depth 6 --exclude /Android/ . /home/test")
  assert.equal(M.scanCommand(["/mnt"], ["~/Android", ".git"], home).join(" "), "fd --hidden --max-depth 6 --exclude .git . /mnt")
  const tree = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "wheel-scan-"))
  for (const name of ["home/.claude/CLAUDE.md", "home/Android/x", "home/p/node_modules/m", "home/1/2/3/4/5/6/deep", "mnt/a"])
    fs.mkdirSync(path.dirname(path.join(tree, name)), { recursive: true }), fs.writeFileSync(path.join(tree, name), "")
  const found = [[tree + "/home"], [tree + "/mnt"]].map(roots => M.scanCommand(roots, ["node_modules", "~/Android"], tree + "/home"))
    .map(command => require("node:child_process").execFileSync(command[0], command.slice(1),
      { encoding: "utf8", env: { ...process.env, XDG_CONFIG_HOME: tree } })).join("")
  assert.deepEqual(found.split("\n").filter(Boolean).map(p => p.slice(tree.length)).sort(),
    ["/home/.claude/", "/home/.claude/CLAUDE.md", "/home/1/", "/home/1/2/", "/home/1/2/3/", "/home/1/2/3/4/",
     "/home/1/2/3/4/5/", "/home/1/2/3/4/5/6/", "/home/p/", "/mnt/a"])
  fs.rmSync(tree, { recursive: true })

  // Typing suggests: folders under home to skip, from the scan, and subfolders outside home to search.
  const files = M.parseFiles("/home/test/Android/\n/home/test/Android/README\n/mnt/android/\n")
  assert.deepEqual(M.fileRows(files, "andr", 40, home, true).map(r => r.path), ["/home/test/Android/"])
  assert.deepEqual(M.subfolderRows(["/home", "/media", "/mnt", "/home/test/x"], "/m", home).map(r => r.path), ["/media/", "/mnt/"])
  assert.deepEqual(M.subfolderRows(["/home"], "/", home).concat(M.subfolderRows(["/home/test/x"], "/home/test/", home)), [],
    "home, or a folder in or around it, was offered")
  assert.deepEqual([M.listEntry("/home/test/Android/", home), M.listEntry("/mnt/share/", home)], ["~/Android", "/mnt/share"])

  // Enter adds the suggestion picked, once; Del removes and the next entry takes the place; an emptied
  // list is its default again. Each change is saved, and the rest of wheel.json stays.
  const saved = []
  const disk = { raw: '{ "slices": ["system"] }', text() { return this.raw }, setText(raw) { this.raw = raw; saved.push(JSON.parse(raw)) } }
  const ls = { query: "", listing: "", savedFolders: null, savedSkipped: null, resultIndex: 0, resultLimit: 40, home, files,
    subfolderPaths: ["/mnt"], get folders() { return this.savedFolders || [] }, get skipped() { return this.savedSkipped || M.SKIPPED },
    get listed() { return this.listing === "skipped" ? this.skipped : this.folders },
    get results() { return binding("results", { root: this, MenuIndex: M }) }, drops: 0, dropScan() { this.drops++ }, scanFiles() {} }
  for (const name of ["edit", "addEntry", "removeEntry", "saveList"]) ls[name] = method(wheelSource, name, { root: ls, ringFile: disk, MenuIndex: M })
  ls.query = "wheely"; ls.edit({ setting: "skipped" })
  assert.deepEqual([ls.query, ls.results.map(r => r.label + r.trail)], ["", [".cacheanywhere", ".gitanywhere", "node_modulesanywhere"]])
  ls.query = "andr"
  assert.deepEqual(ls.results.map(r => r.path), ["/home/test/Android/"], "a skip was offered that is no folder under home")
  ls.addEntry(ls.results[0])
  ls.resultIndex = 1; ls.removeEntry()
  assert.deepEqual([ls.results.map(r => r.label), ls.resultIndex, saved.at(-1)],
    [[".cache", "node_modules", "~/Android"], 1, { slices: ["system"], skipped: [".cache", "node_modules", "~/Android"] }])
  assert.equal(ls.drops, 2, "a saved list kept the old scan")
  ls.edit({ setting: "folders" })
  ls.query = "/m"; ls.addEntry(ls.results[0]); ls.query = "/m"; ls.addEntry(ls.results[0])
  assert.deepEqual(saved.at(-1).folders, ["/mnt"], "a folder was added twice")
  ls.resultIndex = 0; ls.removeEntry()
  assert.equal("folders" in saved.at(-1), false, "an emptied list did not go back to its default")
  // Typed into a list, `/` is a path, not file search; an untyped list still shows, and the empty folders list says why.
  assert.equal(binding("mode", { root: { listing: "folders", query: "/mnt" }, MenuIndex: M }), "")
  assert.equal(binding("searching", { root: { listing: "skipped", query: "" } }), true, "an empty list editor hid its list")
  assert.equal(binding("emptyText", { root: { listing: "folders", query: "" } }), "Home is always searched")
  // History lists picks newest first in the results; Del has no list to remove from, an empty history
  // says so, and a submenu picked from it leaves the list rather than being added to one.
  const hist = { listing: "history", query: "", mode: "", index: lockRows, uses: picks, home: "/home/test" }
  assert.deepEqual(binding("results", { root: hist, MenuIndex: M }).map(r => r.label), ["Lock", "a.txt"])
  assert.deepEqual([binding("listed", { root: hist }), binding("emptyText", { root: hist })], [[], "Nothing picked yet"])
  const added = []
  const hr = { listing: "history", editingRing: false, path: [], countUse() {}, addEntry(e) { added.push(e) } }
  for (const name of ["run", "enter"]) hr[name] = method(wheelSource, name, { root: hr, spin: { restart() {} } })
  hr.run({ node: "system", label: "System" })
  assert.deepEqual([added.length, hr.listing, hr.path.join(".")], [0, "", "system"], "a submenu from history was added, or kept the list")

  // Del and Esc are the list's until something is typed.
  const did = []
  const listed = { listing: "folders", query: "/mn", queryAt: 0, results: [], resultIndex: 0, removeEntry: () => did.push("remove"),
    get searching() { return binding("searching", { root: this }) } }
  const listKey = keymap("plugins/xpo.wheel/MenuKeys.js", listed)
  assert.equal(listKey("Key_Delete").accepted, false, "del left the field while typing")
  listKey("Key_Escape")
  listKey("Key_Delete"); listKey("Key_Escape")
  assert.deepEqual([did, listed.listing], [["remove"], ""], "del or esc missed the list")
}
console.log("ok: file search scans as before until its lists change, and its lists suggest, add and remove")

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
