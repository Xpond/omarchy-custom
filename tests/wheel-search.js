// Search parity across cached queries, rebuilt sources, and changing usage/recency.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/MenuIndex.js"), "utf8")
const names = [...source.matchAll(/^(?:function (\w+)|var (\w+) =)/gm)].map(m => m[1] || m[2])
const M = new Function(source.replace(/^\.pragma library/m, "") + "\nreturn {" + names.join(",") + "}")()

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
    if (!terms.every(t => words.some(w => w.startsWith(t)) || ident.includes(t))) return null
    const labelWords = " " + entry.label.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
      + " " + label + " "
    const rank = entry.kind === M.KIND.window || label.startsWith(squashed) ? 0
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
  "---", "...", "  LOCK  ", "@#", "zzzz", "visual code", "audio - o"]
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
const root = { staticRows: [], styleRows: [], focusOrder: [],
  appLibrary: { sortedEntries: () => [{ entry: desktop }] } }
const rebuild = new Function("root", "MenuIndex", "Hyprland",
  wheel.match(/^  function rebuildIndex\([^]*?^  }/m)[0] + "\nreturn rebuildIndex")(
    root, M, { toplevels: { values: [top] } })
rebuild()
const previous = M.search(root.index, "old", 40, {})
assert.equal(previous.length, 2)
desktop.name = "New Editor"; top.title = "New Document"
root.staticRows = M.menuRows({ new: { label: "New Menu", action: "new action" } }, M.NO_CONDITIONS)
rebuild()
assert.equal(M.search(root.index, "old", 40, {}).length, 0)
assert.equal(M.search(root.index, "new", 40, {}).length, 3)
assert.deepEqual(previous.map(e => e.label), ["Old Document", "Old Editor"])
console.log(`ok: ${checked} wheel searches preserve ordering, matching, ties, and live scores; production refresh replaces cached rows`)
