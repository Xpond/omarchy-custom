#!/usr/bin/env node
// Invariants the wheel must hold, checked against this machine's real menu.
// Run after touching MenuIndex.js, and against a new Omarchy release:
//
//   node plugins/xpo.wheel/check.js
//
// Node or Deno; it is a maintainer's check, not a runtime dependency.

const fs = require("fs")
const path = require("path")
const { execSync } = require("child_process")

const here = __dirname
const omarchy = process.env.OMARCHY_PATH || "/usr/share/omarchy"
const home = process.env.HOME

// MenuIndex.js is a QML library rather than a module, so its declarations are
// collected by name instead of being imported.
const src = fs.readFileSync(path.join(here, "MenuIndex.js"), "utf8").replace(/^\.pragma library/m, "")
const names = [...src.matchAll(/^(?:function (\w+)|var (\w+) =)/gm)].map(m => m[1] || m[2])
const M = new Function(src + "\nreturn {" + names.join(",") + "}")()

const read = p => { try { return fs.readFileSync(p, "utf8") } catch { return "" } }
let failed = 0
const check = (ok, label, detail) => {
  console.log(`${ok ? "ok  " : "FAIL"}  ${label}`)
  if (!ok) { failed++; if (detail) console.log("        " + detail) }
}

// Both files the shell's own menu reads, merged the way it merges them.
const items = M.merge(
  M.parse(read(`${omarchy}/default/omarchy/omarchy-menu.jsonc`)),
  M.parse(read(`${home}/.config/omarchy/extensions/omarchy-menu.jsonc`)))
check(Object.keys(items).length > 0, "menu definitions load",
      `nothing parsed from ${omarchy}/default/omarchy/omarchy-menu.jsonc`)

const cond = M.parseConditions(
  execSync("bash", { input: M.conditionScript(items), encoding: "utf8", maxBuffer: 1 << 22 }), items)

// Anything the plugin reaches for has to exist here. A stale call site is
// invisible until the wheel is opened with the right config. Every file rather
// than Wheel.qml alone: the ring, the results and the key map are their own
// files now, and a check that names one of them would go stale the next time
// something moves.
// Imports stripped first: `import "MenuIndex.js" as MenuIndex` otherwise reads
// as a call to a symbol named `js`.
const callers = fs.readdirSync(here)
  .filter(f => /\.(qml|js)$/.test(f) && f !== "MenuIndex.js" && f !== "check.js")
  .map(f => fs.readFileSync(path.join(here, f), "utf8").replace(/^import .*$/gm, "")).join("\n")
const missing = [...new Set([...callers.matchAll(/MenuIndex\.(\w+)/g)].map(m => m[1]))]
  .filter(n => M[n] === undefined)
check(missing.length === 0, "every call site names something MenuIndex.js defines", missing.join(", "))

// An unreadable or never-run scan must not read as "every condition failed" --
// that silently hides every conditional row, which is how it broke once.
check(M.parseConditions("", items).ready === false, "an empty condition scan fails open")

// The non-negotiable: every menu this machine actually has is one search away.
const rows = M.menuRows(items, cond)
const emitted = new Set(rows.map(r => r.id))
const unreachable = Object.keys(items).filter(id => {
  const e = items[id]
  if (!M.passes(e, id, cond)) return false              // its `when` failed: not available here
  if (!e.action && !e.provider && !cond.full[id]) return false  // submenu its children emptied
  return !emitted.has(id)
})
check(unreachable.length === 0,
      `every available menu is searchable (${Object.keys(items).length} entries -> ${rows.length} rows)`,
      unreachable.join(", "))

const dead = rows.filter(r => !r.action && !r.node)
check(dead.length === 0, "every row has something to do", dead.map(r => r.label).join(", "))

// A row that opens onto nothing is a dead end that coverage alone cannot see.
const empty = rows.filter(r => r.node && M.ringSlices(items, r.node.split("."), cond, []).length === 0)
check(empty.length === 0, "no row drills into an empty ring", empty.map(r => r.id).join(", "))

// The use counter keys rows through keyOf, and a key that is empty or shared
// makes the count quietly wrong: a row that never learns, or two rows keeping
// one tally between them. Windows are the deliberate exception -- their address
// is new every launch, so counting them would grow the file without bound.
const counted = [...M.panelRows([...M.panels(null), ...M.EXTRAS]), ...rows]
const keyless = counted.filter(r => !M.keyOf(r))
check(keyless.length === 0, "every counted row has a use key", keyless.map(r => r.label).join(", "))

const keys = counted.map(r => M.keyOf(r))
const collided = keys.filter((k, i) => keys.indexOf(k) !== i)
check(collided.length === 0, `use keys are unique (${keys.length} keys)`, collided.join(", "))

check(M.keyOf({ label: "a window", address: "0x1" }) === "", "windows are not counted")

// A sigil that a menu label also starts with would shadow every row under it.
// Nothing does today; this is what says so after the next Omarchy release, and
// after the next mode is added to the table.
const shadowed = rows.filter(r => M.modeOf(r.label))
check(shadowed.length === 0, `no menu label starts with a mode sigil (${Object.keys(M.MODES).join(" ")})`,
      shadowed.map(r => r.label).join(", "))
check(M.termOf("/wheel") === "wheel" && M.termOf("wheel") === "wheel",
      "a sigil is stripped exactly once, and only when it leads")

// fd marks a directory with a trailing slash, and that mark is the only thing
// telling a folder row from a file row. Reading it wrong names every directory
// "" -- which is a row you cannot see, pointing at a path that still opens.
const scanned = M.parseFiles(`${home}/Downloads/\n${home}/.config/hypr/hyprland.conf\n`)
const dir = M.fileRows(scanned, "downloads", 1, home)[0]
const file = M.fileRows(scanned, "hyprland", 1, home)[0]
check(!!dir && dir.label === "Downloads" && dir.trail === "~",
      "a directory row is named without its trailing slash", JSON.stringify(dir))
check(!!file && file.label === "hyprland.conf" && file.trail === "~/.config/hypr",
      "a file row carries the directory above it, relative to home", JSON.stringify(file))
check(!!dir && dir.icon !== file.icon, "files and directories wear different marks")

// The payload the browser is handed: a file opens its directory with itself
// selected, a directory opens itself. Getting the trailing slash wrong here
// opens the parent of what was picked.
check(M.pathPayload(`${home}/a/b.txt`) === JSON.stringify({ dir: `${home}/a`, select: "b.txt" }),
      "a file payload names its directory and itself", M.pathPayload(`${home}/a/b.txt`))
check(M.pathPayload(`${home}/a/`) === JSON.stringify({ dir: `${home}/a` }),
      "a directory payload names itself and selects nothing", M.pathPayload(`${home}/a/`))

// File rows are deliberately uncounted, for the reason windows are: a launcher
// opens whatever this week's work is, and every path picked would be a line in
// the state file forever.
check(M.keyOf(M.fileRow(`${home}/a.txt`, home)) === "", "files are not counted")

// Odd rings put nothing at 3 and 9 o'clock, so every default has to be even.
for (const [label, cfg] of [["shipped", `${omarchy}/config/omarchy/shell.json`],
                            ["this machine", `${home}/.config/omarchy/shell.json`]]) {
  const raw = read(cfg)
  if (!raw) continue
  const n = M.panels(M.barWidgets(raw)).length
  check(n % 2 === 0, `${label} bar gives an even ring (${n} slices)`,
        "an odd ring has no slice at 3 or 9 o'clock")
}

console.log(failed ? `\n${failed} failed` : "\nall good")
process.exit(failed ? 1 : 0)
