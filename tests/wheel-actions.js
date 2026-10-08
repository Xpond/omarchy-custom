// Execute the wheel's queued launch branches without opening desktop targets.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/Wheel.qml"), "utf8")
const runSource = source.match(/^  function run\([^]*?^  }/m)[0]
const openedSource = source.match(/^  onOpenedChanged: \{([^]*?)^  }/m)[1]

for (const [entry, expected] of [
  [{ appId: "org.example.Editor", label: "My Editor" }, ["app", "org.example.Editor", "My Editor"]],
  [{ action: "example-command --flag 'two words'" }, ["action", "example-command --flag 'two words'"]],
  [{ plugin: "third.notes" }, ["plugin", "third.notes", "{}"]],
  [{ address: "0x123" }, ["window", 'hl.dsp.focus({ window = "address:0x123" })']]
]) {
  const effects = [], picks = [], dismissals = [], later = []
  const unmap = { running: false }
  const root = {
    home: "/home/test", opened: true, launched: "", queued: null, slices: [entry],
    countUse: e => picks.push(e), dropScan() {},
    dismiss(immediate) { dismissals.push(immediate); unmap.running = !immediate },
    appLibrary: { launch: (...args) => effects.push(["app", ...args]) },
    shell: { toggle: (...args) => effects.push(["plugin", ...args]), panelSurfaceVisible() {} }
  }
  const Qt = { callLater: fn => later.push(fn) }
  const run = new Function("root", "unmap", "Util", "Hyprland", runSource + "\nreturn run")(
    root, unmap, { execDetached: command => effects.push(["action", command]) },
    { dispatch: command => effects.push(["window", command]) })
  const openedChanged = new Function("root", "Qt", openedSource).bind(null, root, Qt)

  run(null)
  assert.deepEqual([picks, dismissals, effects], [[], [], []], "an empty selection does nothing")
  run(entry)
  assert.deepEqual(picks, [entry])
  assert.equal(root.launchedAt, 0)
  assert.deepEqual(dismissals, [!!entry.plugin])
  assert.deepEqual(effects, [], "a target ran before the wheel unmapped")
  assert.equal(root.launched, "", "a plugin was recorded before it opened")
  assert.equal(typeof root.queued, "function")
  if (!entry.plugin) run({ action: "second click during fade" })
  assert.deepEqual(picks, [entry], "another pick replaced the queued action during fade")

  root.opened = false
  openedChanged()
  assert.equal(root.queued, null, "unmapping must consume the queued callback")
  assert.equal(later.length, 1)
  assert.deepEqual(effects, [], "the target ran before the deferred unmap tick")
  openedChanged()
  assert.equal(later.length, 1, "a second close queued the action twice")
  later.shift()()
  assert.deepEqual(effects, [expected], "the queued target or its arguments changed")
  assert.equal(root.launched, entry.plugin || "")
  openedChanged()
  assert.equal(later.length, 0, "closing again repeated an already launched action")
  assert.deepEqual(effects, [expected])
}
console.log("ok: app, action, plugin and window picks execute once after unmapping with exact arguments")
