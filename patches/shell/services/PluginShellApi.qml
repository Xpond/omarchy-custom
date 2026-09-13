import QtQuick

// Capability-scoped shell surface for installed third-party plugins.
//
// The callbacks are closed over one plugin id by shell.qml. A plugin can call
// them directly, but it cannot widen their scope: ordinary plugins are limited
// to their own id, and menu/full-bar callbacks independently enforce their
// non-authentication UI scope. Host objects never cross this facade; visual
// plugins still share the QML scene and are not process-sandboxed.
QtObject {
  id: api

  required property string pluginId

  property var appLibrary: null
  property var bar: null
  property var barConfig: ({})
  property var idleConfig: ({})

  property var _serviceLookup: null
  property var _firstPartyServiceLookup: null
  property var _barEntryShellLookup: null
  property var _summon: null
  property var _hide: null
  property var _toggle: null
  property var _isOpen: null
  property var _closePeers: null
  property var _panels: null
  property var _claimPopout: null
  property var _releasePopout: null
  property var _panelSurfaceVisible: null
  property var _updateSettings: null
  property var _mutateBarConfig: null
  property var _claimedPopout: null
  property bool _surfaceVisible: false

  function serviceFor(id) {
    return _serviceLookup ? _serviceLookup(String(id || "")) : null
  }

  // Full-bar facades and configured Indicators clones under the trusted bar
  // receive narrow proxies for their specific non-authentication services.
  function firstPartyServiceFor(id) {
    return _firstPartyServiceLookup
      ? _firstPartyServiceLookup(String(id || "")) : null
  }

  function pluginShellForBarEntry(ownerId, moduleName) {
    return _barEntryShellLookup
      ? _barEntryShellLookup(String(ownerId || ""), String(moduleName || "")) : null
  }

  function summon(id, payloadJson) {
    return _summon ? _summon(String(id || ""), String(payloadJson || "")) : false
  }

  function hide(id) {
    return _hide ? _hide(String(id || "")) : false
  }

  function toggle(id, payloadJson) {
    return _toggle ? _toggle(String(id || ""), String(payloadJson || "")) : false
  }

  function isPluginOpen(id) {
    return _isOpen ? _isOpen(String(id || "")) : false
  }

  function closePeers() {
    return _closePeers ? _closePeers() : { acted: false, clear: true }
  }

  // Menu plugins only: the panels the live bar can open, for search.
  function panels() {
    return _panels ? _panels() : []
  }

  function claimPopout(owner) {
    if (!_claimPopout || !owner) return false
    if (_claimedPopout && _claimedPopout !== owner) releasePopout(_claimedPopout)
    if (!_claimPopout(owner)) return false
    _claimedPopout = owner
    return true
  }

  function releasePopout(owner) {
    if (!owner || _claimedPopout !== owner) return
    if (_releasePopout) _releasePopout(owner)
    _claimedPopout = null
  }

  function panelSurfaceVisible(shown) {
    var next = shown === true
    if (_surfaceVisible === next) return
    _surfaceVisible = next
    if (_panelSurfaceVisible) _panelSurfaceVisible(next)
  }

  function updateEntryInline(id, settings) {
    return _updateSettings ? _updateSettings(String(id || ""), settings) : false
  }

  function mutateShellConfig(mutator) {
    return _mutateBarConfig && typeof mutator === "function"
      ? _mutateBarConfig(mutator) : false
  }

  Component.onDestruction: {
    if (_claimedPopout && _releasePopout) _releasePopout(_claimedPopout)
    if (_surfaceVisible && _panelSurfaceVisible) _panelSurfaceVisible(false)
  }
}
