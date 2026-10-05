// Search parity across cached queries, rebuilt sources, and changing usage/recency.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/MenuIndex.js"), "utf8")
const names = [...source.matchAll(/^(?:function (\w+)|var (\w+) =)/gm)].map(m => m[1] || m[2])
const M = new Function(source.replace(/^\.pragma library/m, "") + "\nreturn {" + names.join(",") + "}")()

// Issue #1: a launcher without calculator keywords must still match "calc" inside its name.
const calculatorApps = [
  { entry: { id: "libreoffice-calc", name: "LibreOffice Calc" } },
  { entry: { id: "omacalc", name: "Omacalc", keywords: ["calculator"] } },
  { entry: { id: "omacalc-dev", name: "Omacalc (Development)" } }
]
const calculatorRows = M.liveRows({ apps: calculatorApps, windows: [
  { title: "Omacalc", address: "123", wayland: { appId: "omacalc-dev" } }
], focusOrder: [] })
for (const query of ["calc", "omacalc"]) {
  const hits = M.search(calculatorRows, query, 40, {})
  assert.ok(hits.some(r => r.appId === "omacalc-dev"), `${query} missed the development launcher`)
  assert.equal(hits.filter(r => r.address).length, 1)
  assert.equal(hits.find(r => r.address).trail, "Window · omacalc-dev")
  assert.equal(hits.find(r => r.appId === "omacalc-dev").trail, "App")
}
assert.equal(M.search(calculatorRows, "calc development", 40, {})[0].appId, "omacalc-dev")
assert.equal(M.search(calculatorRows.filter(r => !r.address), "omacalc", 40, {}).length, 2)

// A window that only contains a term mid-word does not outrank a label that starts with it.
assert.deepEqual(M.search(M.menuRows({ arch: { label: "Arch", action: "a" } }, M.NO_CONDITIONS).concat(
  M.liveRows({ apps: [], windows: [{ title: "~/x/omarchy-custom", address: "1", wayland: { appId: "kitty" } }],
  focusOrder: [] })), "ar", 40, {}).map(r => r.label), ["Arch", "~/x/omarchy-custom"])

// Window rows name their live workspace, so "workspace" lists every window, most recent first,
// above the bindings that mention one, and "workspace 2" only the windows on 2.
const spread = M.liveRows({ apps: [], focusOrder: ["1", "2", "3"], windows: [
  { title: "Server", address: "1", wayland: { appId: "kitty" }, workspace: { name: "2" } },
  { title: "Docs", address: "2", wayland: { appId: "brave-browser" }, workspace: { name: "1" } },
  { title: "Notes", address: "3", wayland: { appId: "kitty" }, workspace: { name: "special:scratchpad" } }
] }).concat(M.bindRows("SUPER + 2 → Switch to workspace 2\tlua\thl.dsp.focus({ workspace = \"2\" })\n"))
assert.deepEqual(spread.filter(r => r.address).map(r => r.trail),
  ["Workspace 2 · kitty", "Workspace 1 · brave-browser", "Workspace scratchpad · kitty"])
assert.deepEqual(M.search(spread, "workspace", 40, {}).map(r => r.label),
  ["Server", "Docs", "Notes", "Switch to workspace 2"])
assert.deepEqual(M.search(spread, "workspace 2", 40, {}).map(r => r.label), ["Server", "Switch to workspace 2"])

// An independent scorer keeps stable ties in input order and returns original rows.
function reference(rows, query, limit, uses) {
  const q = query.trim().toLowerCase()
  if (!q) return []
  const terms = q.split(/[^a-z0-9]+/).filter(Boolean)
  const squashed = q.replace(/[^a-z0-9]+/g, "")
  const spaced = q.replace(/[^a-z0-9]+/g, " ").trim()
  const tokens = text => {
    const low = String(text || "").toLowerCase()
    return low.split(/[^a-z0-9]+/).filter(Boolean).concat(low.replace(/[^a-z0-9]+/g, ""))
  }
  return rows.map((entry, i) => {
    const label = entry.label.toLowerCase().replace(/[^a-z0-9]+/g, "")
    const words = tokens(entry.keywords), ident = tokens(entry.ident)
    const partial = entry.kind === M.KIND.app || entry.kind === M.KIND.window
    if (!terms.every(t => words.some(w => partial ? w.includes(t) : w.startsWith(t)) || ident.includes(t))) return null
    const labelWords = " " + entry.label.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
      + " " + label + " "
    const inside = terms.some(t => !words.some(w => w.startsWith(t)))
    const rank = entry.kind === M.KIND.window && !inside || label.startsWith(squashed) ? 0
      : labelWords.includes(" " + spaced) ? 1 : 2
    return { entry, order: [rank, entry.kind, label === squashed ? 0 : 1,
      -(uses[M.keyOf(entry)] || 0), entry.recency || 0, entry.label.length, i] }
  }).filter(Boolean).sort((a, b) => {
    for (let i = 0; i < a.order.length; i++) if (a.order[i] !== b.order[i]) return a.order[i] - b.order[i]
    return 0
  }).slice(0, limit).map(hit => hit.entry)
}

const labels = ["Wi-Fi", "Wifi Settings", "Lock", "Lockscreen Designs", "Alacritty", "Visual Studio Code",
  "System Monitor", "Open Files", "Files", "éclair", "हिन्दी", "Audio Output", "Music", "---"]
function fixture(renamed = false) {
  const menu = {}
  for (let i = 0; i < 200; i++) menu["test.item" + i] = {
    label: labels[i % labels.length], aliases: ["utility", "screen", "system"],
    description: "Menu " + i, action: "action " + i
  }
  const apps = labels.map((label, i) => ({ entry: { id: "org.example.App-" + i,
    name: renamed ? "Renamed " + label : label, genericName: "App " + i, keywords: ["utility"] } }))
  const windows = labels.map((title, i) => ({ title, address: String(i), wayland: { appId: "App-" + i },
    lastIpcObject: { focusHistoryID: i % 3 } }))
  return M.panelRows(M.PANELS.concat(M.EXTRAS)).concat(M.menuRows(menu, M.NO_CONDITIONS),
    M.liveRows({ apps, windows, focusOrder: [] }), M.styles(labels, "", labels, ""))
}
const queries = ["", "  ", "a", "app", "ap", "0", "wifi", "wi fi", "wi-fi", "lock", "lockscreen",
  "files", "open f", "system", "sys m", "audio output", "screen", "utility", "renamed", "é", "हिन्दी",
  "---", "...", "  LOCK  ", "@#", "zzzz", "visual code", "audio - o", "acrit", "itor"]
let checked = 0
for (const renamed of [false, true]) {
  const rows = fixture(renamed)
  for (let round = 0; round < 3; round++) {
    const uses = {}
    rows.forEach((e, i) => { uses[M.keyOf(e)] = (i * 17 + round * 13) % 23; e.recency = (i + round) % 7 })
    for (const query of round % 2 ? [...queries].reverse() : queries) {
      for (const limit of [0, 1, 8, 40, 1000]) {
        const expected = reference(rows, query, limit, uses)
        const actual = M.search(rows, query, limit, uses)
        assert.deepEqual(actual, expected, `${query}, ${limit}, round ${round}`)
        actual.forEach((entry, i) => assert.equal(entry, expected[i]))
        checked++
      }
    }
  }
}

// Exercise the production refresh path after its live inputs change in place.
const wheel = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/Wheel.qml"), "utf8")
const desktop = { id: "org.example.editor", name: "Old Editor" }
const top = { title: "Old Document", address: "123", wayland: { appId: desktop.id } }
const root = { staticRows: [], styleRows: [], settingRows: [], focusOrder: [], menuItems: {},
  bindRows: M.bindRows("SUPER + N → New thing\texec\tnew action\n"),
  appLibrary: { sortedEntries: () => [{ entry: desktop }] } }
const rebuild = new Function("root", "MenuIndex", "Hyprland",
  wheel.match(/^  function rebuildIndex\([^]*?^  }/m)[0] + "\nreturn rebuildIndex")(
    root, M, { toplevels: { values: [top] } })
rebuild()
const previous = M.search(root.index, "old", 40, {})
assert.equal(previous.length, 2)
assert.equal(M.search(root.index, "thing", 40, {})[0].label, "New thing", "the binding is not a row")
desktop.name = "New Editor"; top.title = "New Document"
root.menuItems = { new: { label: "New Menu", action: "new action" } }
root.staticRows = M.menuRows(root.menuItems, M.NO_CONDITIONS)
rebuild()
assert.equal(M.search(root.index, "old", 40, {}).length, 0)
assert.equal(M.search(root.index, "new", 40, {}).length, 3)
assert.equal(M.search(root.index, "thing", 40, {})[0].label, "New Menu",
  "the binding did not join the menu row that runs its command")
assert.deepEqual(previous.map(e => e.label), ["Old Document", "Old Editor"])
console.log(`ok: ${checked} wheel searches preserve ordering, matching, ties, and live scores; production refresh replaces cached rows`)
