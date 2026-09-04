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

// Anything Wheel.qml reaches for has to exist here. A stale call site is
// invisible until the wheel is opened with the right config.
// Imports stripped first: `import "MenuIndex.js" as MenuIndex` otherwise reads
// as a call to a symbol named `js`.
const wheel = fs.readFileSync(path.join(here, "Wheel.qml"), "utf8").replace(/^import .*$/gm, "")
const missing = [...new Set([...wheel.matchAll(/MenuIndex\.(\w+)/g)].map(m => m[1]))]
  .filter(n => M[n] === undefined)
check(missing.length === 0, "Wheel.qml calls only what MenuIndex.js defines", missing.join(", "))

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
