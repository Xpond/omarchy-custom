// Keybindings as wheel rows: Omarchy's records, the rows they join, and the rest.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/MenuIndex.js"), "utf8")
const names = [...source.matchAll(/^(?:function (\w+)|var (\w+) =)/gm)].map(m => m[1] || m[2])
const M = new Function(source.replace(/^\.pragma library/m, "") + "\nreturn {" + names.join(",") + "}")()

// Records as omarchy-menu-keybindings writes them: padded keys, an arrow, then tab-separated fields.
const record = (keys, label, kind, arg) => `${keys.padEnd(35)} → ${label}\t${kind}\t${arg}`
const raw = [
  record("SUPER + T", "Toggle window floating/tiling", "lua", 'hl.dsp.window.float({ action = "toggle" })'),
  record("SUPER CTRL + L", "Lock computer", "exec", "omarchy-system-lock"),
  record("SUPER CTRL + A", "Audio controls", "exec", "omarchy-shell shell toggle omarchy.audio"),
  record("SUPER + ESCAPE", "System menu", "exec", "omarchy-menu toggle system"),
  record("XF86PowerOff", "Power menu", "exec", "omarchy-menu toggle system"),
  record("SUPER SHIFT CTRL + SPACE", "Theme menu", "exec", "omarchy-menu toggle theme"),
  record("XF86AudioNext", "Next track", "exec", "omarchy-shell media next"),
  record("ALT + XF86AudioPlay", "Next track", "exec", "omarchy-shell media next"),
  record("SUPER + PRINT", "Color picker", "exec", "pkill hyprpicker || hyprpicker -a"),
  record("SUPER + K", "Two fields", "exec", "printf '%s\t%s' a b"),
  // None of these can run from a row.
  record("SHIFT ALT + L", "Copy URL from Web App", "sendshortcut", "SHIFT ALT,L,"),
  record("SUPER + C", "Universal copy", "", ""),
  record("SUPER + LEFT MOUSE BUTTON", "Move window", "lua", "hl.dsp.window.drag()"),
  record("SUPER + mouse_down", "Scroll active workspace forward", "lua", 'hl.dsp.focus({ workspace = "e+1" })')
].join("\n") + "\n"

const binds = M.bindRows(raw)
assert.deepEqual(binds.map(b => b.label), ["Toggle window floating/tiling", "Lock computer", "Audio controls",
  "System menu", "Power menu", "Theme menu", "Next track", "Next track", "Color picker", "Two fields"])
assert.deepEqual([binds[0].dispatch, binds[0].action, binds[0].kind],
  ['hl.dsp.window.float({ action = "toggle" })', undefined, M.KIND.bind])
assert.equal(binds[9].action, "printf '%s\t%s' a b", "a tab inside the command was cut")
assert.deepEqual(M.bindRows(""), [])

const items = {
  system: { label: "System" },
  "system.lock": { label: "Lock", action: "omarchy-system-lock" },
  trigger: { label: "Trigger" },
  "trigger.color": { label: "Color", action: "pkill hyprpicker || hyprpicker -a" },
  style: { label: "Style" },
  "style.theme": { label: "Theme", action: "omarchy-theme-switcher", aliases: "theme" },
  "style.next": { label: "Next background", action: "omarchy-theme-bg-next" }
}
const rows = M.panelRows([{ plugin: "omarchy.audio", icon: "a", label: "Audio" }])
  .concat(M.menuRows(items, M.NO_CONDITIONS))
// Searched before the fold, so a stale search cache would hide the words a binding lends.
assert.equal(M.search(rows, "picker", 40, {}).length, 0)
const before = JSON.stringify(rows)
const index = M.withBindings(rows, binds, items)
const find = label => index.filter(r => r.label === label)
const top = query => M.search(index, query, 40, {})[0].label

// A binding that runs a row's own command, toggles its panel or opens Omarchy's menu at it by id
// or alias joins that row unseen: nothing on the row changes, but its description finds it.
assert.equal(top("lock computer"), "Lock")
assert.equal(top("audio controls"), "Audio")
assert.equal(top("power menu"), "System")
assert.equal(top("theme menu"), "Theme")
assert.equal(top("picker"), "Color")
assert.ok(index.every((r, i) => r.trail === (rows[i] ? rows[i].trail : "")), "a row shows a binding's keys")
assert.equal(JSON.stringify(rows), before, "the fold changed the rows it was given")

// The rest are rows of their own, one per command.
assert.equal(find("Next track").length, 1)
assert.equal(index.length, rows.length + 3)
assert.deepEqual(M.search(index, "next", 40, {}).map(r => r.label), ["Next background", "Next track"],
  "a binding outranked a menu row matching as well")

// A binding row counts its uses by command, and no two rows share a key.
assert.equal(M.keyOf(find("Toggle window floating/tiling")[0]), 'hl.dsp.window.float({ action = "toggle" })')
const keys = index.map(M.keyOf)
assert.equal(new Set(keys).size, keys.length)
console.log("ok: keybindings are rows, one per command, joining rows that run the same thing")
