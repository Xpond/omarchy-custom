const assert = require("node:assert/strict")
const path = require("node:path")
const { repo, read, method } = require("./qml.js")
const { wheelSource } = require("./wheel-source.js")

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
const bareShell = { bar: bareBar }
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
for (const plugin of ["xpo.wheel", "xpo.files"])
  require("node:child_process").execFileSync("omarchy",
    ["plugin", "validate", path.join(repo, "plugins", plugin)], { stdio: "inherit" })
console.log("ok: xpo plugins use narrow facades and menus control only UI plugins")
