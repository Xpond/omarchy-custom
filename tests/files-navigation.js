const assert = require("node:assert/strict")
const { read, library, method, keymap } = require("./qml.js")
const F = library("plugins/xpo.files/FilesIndex.js")
const M = library("plugins/xpo.wheel/MenuIndex.js")

const source = read("plugins/xpo.files/Files.qml")
const calls = []
const root = { editing: true, dirty: true, saving: null, opened: true, enter: d => calls.push(d),
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

// Ctrl+T pops the overlay out into a window the shell no longer counts as open, and
// back again. A summon raises the window, and moves it only when a path asks.
const popped = []
const win = { opened: true, windowed: false, editing: false, filter: "", naming: "",
  get shown() { return this.opened || this.windowed }, focusedScreen: () => null,
  dir: "/home/test/here", shell: { hide: id => popped.push("hide " + id) },
  raise: () => popped.push("raise"), enter(d) { this.dir = d }, claimPending() {} }
const winScope = { root: win, keys: { forceActiveFocus() {} }, Qt: { callLater: fn => fn() } }
win.popOut = method(source, "popOut", winScope)
win.close = method(source, "close", winScope)
const winKey = keymap("plugins/xpo.files/FilesKeys.js", win, { doomed: "" }, {})
winKey("Key_T", 1 << 26)
assert.equal(win.windowed, true)
assert.equal(win.opened, false)
assert.deepEqual(popped, ["hide xpo.files"], "the shell forgets the overlay once")
winKey("Key_Escape")
assert.deepEqual(popped, ["hide xpo.files"], "a window does not close on Escape")
winKey("Key_T", 1 << 26)
assert.equal(win.opened, true, "ctrl+t again brings the overlay back")
assert.equal(win.windowed, false)
winKey("Key_T", 1 << 26)
const winOpen = method(source, "open", winScope)
winOpen("{}")
assert.equal(win.dir, "/home/test/here", "a bare summon keeps the window's place")
winOpen('{"dir":"/home/test/there","select":"a.txt"}')
assert.equal(win.dir, "/home/test/there")
assert.equal(win.pending, "a.txt")
assert.equal(win.opened, false, "a summon never reopens the overlay over the window")
assert.deepEqual(popped.slice(2), ["raise", "raise"])
console.log("ok: ctrl+t pops out and back; the window ignores Escape, keeps its place, and is raised")

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

const wheel = { root: { home: "/home/test", countUse() {}, dismiss() { this.queued() }, slices: [], copy: text => calls.push(text), shell: {
  summon: (id, payload) => calls.push([id, JSON.parse(payload)]),
  toggle() { throw new Error("navigation must summon") }
} }, unmap: { running: false }, MenuIndex: M,
  Quickshell: { execDetached: argv => calls.push([...argv]) },
  Hyprland: { dispatch: expression => calls.push(["dispatch", expression]) } }
const runRow = method(read("plugins/xpo.wheel/Wheel.qml"), "run", wheel)
runRow({ path: "/home/test/new.txt" })
assert.equal(calls.at(-1)[0], "xpo.files")
assert.equal(calls.at(-1)[1].select, "new.txt")
assert.equal(wheel.root.launched, "xpo.files", "a browser opened from a path has no wheel to return to")
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
  index: 40, listPage: 10, editing: false, naming: "", listShown: true,
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

// With the list hidden, bare keys scroll the preview and ← brings the list back.
scrolls.length = 0
browser.index = 5; browser.listShown = false; browser.lineHeight = 3; browser.up = () => scrolls.push("went up")
key("Key_Down"); key("Key_Home")
assert.deepEqual(scrolls, [9, "to0"], "a bare key missed the preview")
assert.equal(browser.index, 5, "a bare key moved the hidden list")
key("Key_Left")
assert.equal(browser.listShown, true, "← did not bring the list back")
assert.deepEqual(scrolls, [9, "to0"], "← went up instead of showing the list")
key("Key_Down")
assert.equal(browser.index, 6, "the list did not take the keys back")
console.log("ok: a hidden list leaves the keys to the preview; ← brings it back")

// → steps into folders but never opens a file.
const opened = []
const stepper = { editing: false, naming: "", listShown: true, sel: { name: "notes.md", isDir: false } }
const stepKey = keymap("plugins/xpo.files/FilesKeys.js", stepper,
  { doomed: "", activate: e => opened.push(e.name) }, {})
stepKey("Key_Right")
assert.deepEqual(opened, [], "→ opened a file")
stepper.sel = { name: "docs", isDir: true }
stepKey("Key_Right")
assert.deepEqual(opened, ["docs"], "→ did not enter a folder")
console.log("ok: → enters folders but opens no file")

// Backspace is one key with three jobs, taken in order: shorten the filter,
// walk up a directory, leave for the wheel. Home is the floor, so the press
// that cannot go up is the one that goes back.
const walk = { home: "/home/test", dir: "/home/test/a/b", filter: "ab",
  editing: false, naming: "", listShown: true, left: 0,
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

// Going up lands on the folder just left, not on whichever row sorts first.
const climber = { home: "/home/test", dir: "/home/test/a/docs",
  enter(d) { this.dir = F.within(d, this.home); this.pending = "" } }
const climb = method(source, "up", { root: climber, FilesIndex: F })
climb()
assert.equal(climber.dir, "/home/test/a")
assert.equal(climber.pending, "docs", "going up forgot the folder it came from")
climber.dir = "/home/test"
climb()
assert.equal(climber.pending, "", "home has nothing above it to land on")
console.log("ok: going up selects the folder it came from")

// A leading / starts the path from the folder being browsed.
const typist = { home: "/home/test", dir: "/home/test/xpo/docs", filter: "", index: 3,
  editing: false, naming: "", listShown: true }
const typeKey = keymap("plugins/xpo.files/FilesKeys.js", typist, { doomed: "" }, {})
typeKey("Key_Slash", 0, "/")
assert.equal(typist.filter, "/xpo/docs/", "/ reset the path to home")
typeKey("Key_Slash", 0, "/")
assert.equal(typist.filter, "/xpo/docs//", "a later / is just a character")
typist.filter = ""; typist.dir = typist.home
typeKey("Key_Slash", 0, "/")
assert.equal(typist.filter, "/", "at home / is home")
console.log("ok: / starts the path where you are")
