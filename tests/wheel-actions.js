// Execute the wheel's queued launch branches without opening desktop targets.
const assert = require("node:assert/strict")
const { method } = require("./qml.js")
const { wheelSource } = require("./wheel-source.js")
const openedSource = wheelSource.match(/^  onOpenedChanged: \{([^]*?)^  }/m)[1]

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
  const run = method(wheelSource, "run", { root, unmap,
    Util: { execDetached: command => effects.push(["action", command]) },
    Hyprland: { dispatch: command => effects.push(["window", command]) } })
  const openedChanged = new Function("root", "Qt", openedSource).bind(null, root, Qt)

  run(null)
  assert.deepEqual([picks, dismissals, effects], [[], [], []], "an empty selection does nothing")
  run(entry)
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
}
console.log("ok: app, action, plugin and window picks execute once after unmapping with exact arguments")

// Reopening during the fade cancels the pick, so closing again without one runs nothing.
const Qt = { callLater: fn => fn() }
const root = { opened: true, queued: () => assert.fail("a cancelled pick ran on the next close"),
  closePeers: () => ({ clear: true }), focusedScreen() {}, rebuildIndex() {}, reread() {}, dropScan() {} }
method(wheelSource, "open", { root, Qt, unmap: { stop() {} }, spin: { restart() {} },
  searchInput: { forceActiveFocus() {} } })()
root.opened = false
new Function("root", "Qt", openedSource)(root, Qt)
console.log("ok: reopening during the fade cancels the queued pick")
