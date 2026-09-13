"""Exercise the production loader and capability factory across QML model conversion."""
import json
import shutil


def check(repo, base, run, block):
    shutil.copyfile(repo / "patches/shell/services/PluginShellApi.qml",
                    base / "PluginShellApi.qml")
    run("plugin-shell-facade", '''
  property int claims: 0
  property int releases: 0
  property var surfaces: []
  QtObject { id: owner }
  PluginShellApi {
    id: api
    pluginId: "xpo.wheel"
    _claimPopout: function(value) { root.claims++; return value === owner }
    _releasePopout: function(value) { if (value === owner) root.releases++ }
    _panelSurfaceVisible: function(shown) { root.surfaces = root.surfaces.concat([shown]) }
  }
  Timer { interval: 1; running: true; onTriggered: {
    api.panelSurfaceVisible(true); api.panelSurfaceVisible(true)
    api.panelSurfaceVisible(false); api.panelSurfaceVisible(false)
    if (!api.claimPopout(owner)) { console.error("FAIL claim"); Qt.exit(1); return }
    api.releasePopout({}); api.releasePopout(owner)
    if (root.claims !== 1 || root.releases !== 1
        || JSON.stringify(root.surfaces) !== "[true,false]") {
      console.error("FAIL callbacks", root.claims, root.releases,
                    JSON.stringify(root.surfaces)); Qt.exit(1)
    } else { console.log("PASS"); Qt.quit() }
  } }
''')

    source = (repo / "patches/shell/shell.qml").read_text()
    methods = ["manifestHasKind", "pluginHasVisualCapabilities", "pluginHasBarCapabilities",
               "pluginShellCapabilityProfile", "createScopedPluginShell", "pluginShellFor",
               "publicPluginManifest", "setPluginSurfaceVisible"]
    production = "\n".join(block(source, "  function " + name + r"\(") for name in methods)
    production += "\n" + block(source, r"  Instantiator {")
    manifests = {name: json.loads((repo / "plugins" / name / "manifest.json").read_text())
                 for name in ["xpo.wheel", "xpo.files"]}
    (base / "Panel.qml").write_text('''import QtQuick
Item {
  property var shell: null
  property var manifest: null
  property bool opened: false
  onOpenedChanged: shell.panelSurfaceVisible(opened)
}
''')

    run("plugin-loader-capabilities", '''
  property var shell: root
  property string omarchyPath: ""
  property var _pluginShellApis: ({})
  property var _pluginShellApiDescriptors: ({})
  property var _pluginSurfaceStates: ({})
  property var openPanelIds: ({})
  property var panelLoaders: ({})
  property var panelEntries: Object.keys(pluginRegistry.installedPlugins).map(function(id) {
    return {id: id, manifest: pluginRegistry.installedPlugins[id], kind: "overlay", keepLoaded: true}
  })
  property var pluginRegistry: QtObject {
    property var installedPlugins: ''' + json.dumps(manifests) + '''
    function entryPointUrl(manifest, kind) { return Qt.resolvedUrl("Panel.qml") }
  }
  property var bar: QtObject {
    property int visiblePanelSurfaces: 0
    function panelSurfaceVisible(shown) { visiblePanelSurfaces += shown ? 1 : -1 }
  }
  Component { id: pluginShellApiComponent; PluginShellApi {} }
  function pluginIsIndicatorsClone(manifest) { return false }
  function pluginAppLibraryFor(cacheKey, key) { return {detached: true} }
  function pluginBarStateFor(cacheKey, key) { return null }
  function publicBarConfig() { return ({}) }
  function publicIdleConfigFor(manifest) { return ({}) }
  function registerPanelLoader(id, loader) { panelLoaders[id] = loader }
  function unregisterPanelLoader(id) { delete panelLoaders[id] }
''' + production + '''
  Timer { interval: 100; running: true; onTriggered: {
    function check(condition, message) {
      if (!condition) throw new Error("FAIL " + message)
    }
    try {
      var wheel = root.panelLoaders["xpo.wheel"].item
      var files = root.panelLoaders["xpo.files"].item
      check(wheel.shell !== root && files.shell !== root, "plugin received ShellRoot")
      check(wheel.shell.bar !== root.bar && files.shell.bar !== root.bar, "plugin received live bar")
      wheel.opened = true
      check(root.bar.visiblePanelSurfaces === 1, "wheel backdrop missing")
      check(wheel.shell.appLibrary && !files.shell.appLibrary, "menu capability lost or broadened")
      wheel.shell.panelSurfaceVisible(true)
      check(root.bar.visiblePanelSurfaces === 1, "duplicate report inflated count")
      files.opened = true
      wheel.opened = false
      check(root.bar.visiblePanelSurfaces === 1, "handoff dropped Files backdrop")
      files.opened = false
      check(root.bar.visiblePanelSurfaces === 0, "backdrop retained after close")
      console.log("PASS"); Qt.quit()
    } catch (error) { console.error(String(error)); Qt.exit(1) }
  } }
''')
