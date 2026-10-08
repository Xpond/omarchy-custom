const assert = require("node:assert/strict")
const { read, method } = require("./qml.js")
const { M, wheelSource, binding } = require("./wheel-source.js")

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

{
  // History lists picks newest first in the results; Del has no list to remove from, an empty history
  // says so, and a submenu picked from it leaves the list rather than being added to one.
  const hist = { listing: "history", query: "", mode: "", index: lockRows, uses: picks, home: "/home/test" }
  assert.deepEqual(binding("results", { root: hist, MenuIndex: M }).map(r => r.label), ["Lock", "a.txt"])
  assert.deepEqual([binding("listed", { root: hist }), binding("emptyText", { root: hist })], [[], "Nothing picked yet"])
  const added = []
  const hr = { listing: "history", editingRing: false, path: [], countUse() {}, addEntry(e) { added.push(e) } }
  for (const name of ["run", "enter"]) hr[name] = method(wheelSource, name, { root: hr, spin: { restart() {} }, unmap: { running: false } })
  hr.run({ node: "system", label: "System" })
  assert.deepEqual([added.length, hr.listing, hr.path.join(".")], [0, "", "system"], "a submenu from history was added, or kept the list")

}
