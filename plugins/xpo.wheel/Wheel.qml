import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "MenuIndex.js" as MenuIndex
import "MenuKeys.js" as MenuKeys

// Radial control center: the ring is the fast path, search is the complete one.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // FileViews bind before the shell injects this property.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  property bool shown: false
  // Ignore the pointer position synthesized when the surface maps.
  property bool armed: false
  property bool justOpened: false
  property int selected: -1
  property string launched: ""
  // Home-ring slice to restore when returning from a launched panel.
  property int launchedAt: -1

  property string query: ""
  property int queryAt: 0
  property var menuItems: ({})
  // [] is home; nested ids point at submenu rings.
  property var path: []
  readonly property string crumb: MenuIndex.crumb(root.menuItems, root.path)
  property var conditions: MenuIndex.NO_CONDITIONS
  // Prefer the user's bar layout over the stock one.
  property var userBarIds: null
  property var stockBarIds: null
  readonly property var barIds: root.userBarIds || root.stockBarIds
  readonly property var panels: MenuIndex.panels(root.barIds)
  property var ringIds: null
  readonly property var ring: root.ringIds
    ? MenuIndex.ringOf(root.menuItems, root.ringIds, root.conditions)
    : root.panels
  readonly property var staticRows: MenuIndex.panelRows(root.panels.concat(MenuIndex.EXTRAS))
    .concat(MenuIndex.menuRows(root.menuItems, root.conditions))
  property var themes: []
  property var fonts: []
  // Hyprland's cached history goes stale; accumulate activeToplevel changes.
  property var focusOrder: []
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property var index: []
  property var uses: ({})
  // A leading sigil selects one search source.
  readonly property string mode: MenuIndex.modeOf(root.query)
  readonly property string term: MenuIndex.termOf(root.query)
  // Cache scanned home paths only for the current open.
  property var files: null
  readonly property int resultLimit: 40
  readonly property int resultCap: 8
  readonly property var results: root.mode === "file"
    ? MenuIndex.fileRows(root.files, root.term, root.resultLimit, root.home)
    : MenuIndex.search(root.index, root.term, root.resultLimit, root.uses)
  property int resultIndex: 0
  property int resultTop: 0
  readonly property var beads: root.results.slice(root.resultTop,
                                                  root.resultTop + root.resultCap)
  readonly property bool searching: root.query.length > 0

  // Ignore synthetic hover moves when result rows shift under the pointer.
  property point hoverAt: Qt.point(-1, -1)
  function hoverMoved(pt) {
    if (root.hoverAt.x === pt.x && root.hoverAt.y === pt.y) return false
    root.hoverAt = pt
    return true
  }
  readonly property string emptyText: root.mode !== "file" ? "No match"
    : !root.files ? "Scanning\u2026"
    : !root.term ? "Type to find files"
    : "No match"

  // Clockwise from north; node slices drill into submenu rings.
  readonly property var slices: MenuIndex.ringSlices(root.menuItems, root.path,
                                                     root.conditions, root.ring)

  // Preserve each slice's arc by growing the ring with its item count.
  readonly property int sliceCount: root.slices.length
  readonly property real sliceStep: 360 / Math.max(1, root.sliceCount)

  // Even rings anchor east/west; odd rings anchor north.
  readonly property real sliceOrigin: root.sliceCount % 2 === 0 ? 90 % root.sliceStep : 0
  function sliceAngle(i) { return root.sliceOrigin + i * root.sliceStep }
  function nearestSlice(deg) {
    if (!root.sliceCount) return -1
    var i = Math.round((deg - root.sliceOrigin) / root.sliceStep)
    return ((i % root.sliceCount) + root.sliceCount) % root.sliceCount
  }

  readonly property int baseItem: Style.space(76)
  readonly property real slicePitch: root.baseItem * root.selectedScale + Style.space(28)
  readonly property int maxRadius: Math.max(Style.space(160),
    Math.min(surface.width, surface.height) / 2 - root.baseItem * 1.9)
  readonly property int ringRadius: Math.min(root.maxRadius,
    Math.max(Style.space(240), root.slicePitch * root.sliceCount / (2 * Math.PI)))
  // Shrink discs only after the radius reaches its screen cap.
  readonly property int itemSize: Math.max(Style.space(36),
    Math.min(root.baseItem,
             2 * root.ringRadius * Math.sin(Math.PI / Math.max(2, root.sliceCount)) - Style.space(14)))
  readonly property int deadzone: Style.space(54)
  readonly property real selectedScale: 1.08
  readonly property int labelGap: Style.space(18)
  readonly property real ringBox: (root.ringRadius + root.itemSize * 2) * 2
  readonly property int searchWidth: Math.min(Style.space(280),
    (root.ringRadius - root.itemSize / 2) * 2 - Style.space(48))
  readonly property int searchHeight: Style.spacing.controlHeight + Style.spacing.controlPaddingY * 2
  readonly property int resultWidth: root.searchWidth - Style.space(28)
  readonly property int resultHeight: Style.spacing.popupRowHeight + Style.spacing.xs * 2

  // Keep follower angles unwrapped across north.
  property real arcTarget: -90
  property real arcHead: root.arcTarget
  Behavior on arcHead { NumberAnimation { duration: 90 - 45 * root.charge; easing.type: Easing.OutCubic } }
  property real arcTail: root.arcTarget
  Behavior on arcTail { NumberAnimation { duration: 300 + 160 * root.charge; easing.type: Easing.OutCubic } }
  readonly property real arcSpread: root.sliceStep / 2 * 0.85
  // Bound illumination drag; RingTrack owns the shorter visible trail.
  readonly property real arcDrag: Math.max(-300, Math.min(300, root.arcHead - root.arcTail))
  readonly property real arcFrom: root.arcDrag >= 0 ? root.arcHead + root.arcSpread - root.arcSpan : root.arcHead - root.arcSpread
  readonly property real arcSpan: Math.min(240, Math.abs(root.arcDrag) + root.arcSpread * 2)
  // Charge separates deliberate steps from sustained key-repeat spin.
  property real charge: 0

  // Hold reveals the mark only after sustained spin.
  property real hold: 0

  property real markReveal: root.hold * 1.05
  Behavior on markReveal { NumberAnimation { duration: 40 } }

  // Pause the runner while the mark draws or drains.
  property real markPhase: 0
  NumberAnimation on markPhase {
    running: root.markReveal > 0
    paused: running && root.markReveal < 1.05
    loops: Animation.Infinite
    from: 0; to: 1
    duration: 1400
  }

  property real huePhase: 0

  // Unwrapped shared sky/fluid clock; about 7s per day at full spin.
  property real daylight: 0
  Behavior on daylight { NumberAnimation { duration: 40 } }

  Timer {
    interval: 40
    repeat: true
    running: root.charge > 0 || root.hold > 0
    onTriggered: {
      root.charge = Math.max(0, root.charge - 0.09)
      root.hold = root.charge > 0.9
        ? Math.min(1, root.hold + 0.018)
        : Math.max(0, root.hold - 0.045)
      if (root.charge <= 0) root.huePhase = 0
      root.daylight += 0.0012 + 0.0045 * root.charge
    }
  }

  // Rotate in OKLCH to keep perceived lightness and chroma stable across hues.
  function cometAt(turns, amount) {
    function cb(v) { return Math.pow(Math.max(0, v), 1 / 3) }
    function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    var c = Color.accent
    var r = lin(c.r), g = lin(c.g), b = lin(c.b)
    var la = cb(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    var ma = cb(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    var sa = cb(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    var L = 0.2104542553 * la + 0.7936177850 * ma - 0.0040720468 * sa
    var A = 1.9779984951 * la - 2.4285922050 * ma + 0.4505937099 * sa
    var B = 0.0259040371 * la + 0.7827717662 * ma - 0.8086757660 * sa

    var C = Math.sqrt(A * A + B * B)
    var h = Math.atan2(B, A) + turns * 2 * Math.PI
    // Move low-chroma accents toward a visible palette as spin builds.
    L += (0.78 - L) * amount
    C += (0.13 - C) * amount

    A = C * Math.cos(h)
    B = C * Math.sin(h)
    var lb = L + 0.3963377774 * A + 0.2158037573 * B
    var mb = L - 0.1055613458 * A - 0.0638541728 * B
    var sb = L - 0.0894841775 * A - 1.2914855480 * B
    lb = lb * lb * lb; mb = mb * mb * mb; sb = sb * sb * sb
    function enc(v) {
      v = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(Math.max(0, v), 1 / 2.4) - 0.055
      return Math.max(0, Math.min(1, v))
    }
    return Qt.rgba(enc( 4.0767416621 * lb - 3.3077115913 * mb + 0.2309699292 * sb),
                   enc(-1.2684380046 * lb + 2.6097574011 * mb - 0.3413193965 * sb),
                   enc(-0.0041960863 * lb - 0.7034186147 * mb + 1.7076147010 * sb), 1)
  }

  readonly property color cometColor: root.charge <= 0 ? Color.accent
    : root.cometAt(root.huePhase * root.charge, root.charge)

  // Disc illumination follows the input head and eases at both ends.
  function sweepAt(deg) {
    var moving = Math.min(1, Math.abs(root.arcDrag) / root.arcSpread)
    if (moving <= 0) return 0
    var span = Math.abs(root.arcDrag) + root.arcSpread
    // Wrap ahead of the leading edge so long tails cross north intact.
    var offset = (root.arcHead - deg) * (root.arcDrag >= 0 ? 1 : -1)
    var behind = ((offset + root.arcSpread) % 360 + 360) % 360 - root.arcSpread
    if (behind > span) return 0
    var rise = Math.min(1, (behind + root.arcSpread) / root.arcSpread)
    var fall = 1 - Math.max(0, behind) / span
    return moving * rise * rise * (3 - 2 * rise) * fall * fall * (3 - 2 * fall)
  }

  // Step the opening lap like key repeat so the followers produce a trail.
  Timer {
    id: spin
    interval: 25
    repeat: true
    property int stepsLeft: 0
    onTriggered: {
      root.arcTarget += root.sliceStep
      if (--spin.stepsLeft <= 0) spin.stop()
    }
  }

  readonly property color surfaceFill: Util.alpha(Color.menu.background, 0.85)
  readonly property color surfaceEdge: Util.alpha(Color.menu.text, 0.16)
  readonly property color selectedFill: Qt.tint(Util.alpha(Color.menu.background, 0.9),
                                                Util.alpha(Color.accent, 0.22))
  readonly property int moveThreshold: Style.space(8)
  readonly property int fadeDuration: 130
  property real originX: -1
  property real originY: -1
  readonly property string pluginId: (manifest && manifest.id) || "xpo.wheel"
  // Freeze the focused screen on open; pointer focus can otherwise move it.
  property var openScreen: null
  function focusedScreen() {
    var m = Hyprland.focusedMonitor
    if (!m) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === m.name) return screens[i]
    return null
  }

  // Refresh live apps/windows per open; reuse the more expensive static menu rows.
  function rebuildIndex() {
    root.index = root.staticRows.concat(MenuIndex.liveRows({
      apps: root.appLibrary ? root.appLibrary.sortedEntries("") : [],
      windows: Hyprland.toplevels.values,
      focusOrder: root.focusOrder,
      themes: root.themes,
      fonts: root.fonts
    }))
  }

  function closePeers() {
    if (!root.shell) return { acted: false, clear: true }
    var acted = false
    var bar = root.shell.bar
    var popout = bar && bar.activePopout
    if (popout && popout !== root) {
      acted = true
      if ("closeForPopoutSwitch" in popout) popout.closeForPopoutSwitch()
      else if ("close" in popout) popout.close()
    }
    var ids = []
    var candidates = {}
    var openIds = root.shell.openPanelIds || {}
    var loaders = root.shell.panelLoaders || {}
    for (var openId in openIds) candidates[openId] = true
    for (var loadedId in loaders) candidates[loadedId] = true
    for (var id in candidates)
      if (id !== root.pluginId && root.shell.isPluginOpen(id)) ids.push(id)
    var clear = !bar || !bar.activePopout || bar.activePopout === root
    for (var i = 0; i < ids.length; i++) {
      root.shell.hide(ids[i])
      acted = true
      if (root.shell.isPluginOpen(ids[i])) clear = false
    }
    return { acted: acted, clear: clear }
  }

  function open(payloadJson) {
    // Treat a press during fade-out as a fresh open.
    var wasOpen = root.opened && !unmap.running
    unmap.stop()
    var peers = root.closePeers()
    if (!peers.clear) return
    var bar = root.shell && root.shell.bar
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
    root.selected = -1
    root.armed = false
    root.originX = -1
    root.query = ""
    root.path = []
    root.launched = ""
    root.launchedAt = -1
    root.justOpened = !wasOpen
    root.openScreen = root.focusedScreen()
    root.opened = true
    root.rebuildIndex()
    spin.stepsLeft = root.sliceCount
    spin.restart()
    Qt.callLater(function () { root.shown = true; keys.forceActiveFocus() })
  }

  // Fade cancellation; unmap immediately before handing keyboard focus to a panel.
  function close(immediate) {
    var bar = root.shell && root.shell.bar
    if (bar && bar.activePopout === root) bar.releasePopout(root)
    if (immediate) { unmap.stop(); root.opened = false; root.shown = false; return }
    if (!root.opened || unmap.running) return
    root.shown = false
    unmap.start()
  }

  Timer {
    id: unmap
    interval: root.fadeDuration
    onTriggered: root.opened = false
  }

  function dismiss(immediate) {
    root.close(immediate)
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function closeForPopoutSwitch() { root.dismiss(true) }

  // Return whether anything closed so SUPER+W can decide whether to fall through.
  function closeAll() {
    var acted = root.opened
    if (root.opened) root.dismiss()
    var peers = root.closePeers()
    acted = acted || peers.acted
    return acted ? "closed" : "none"
  }

  // Release fires a flick; the first tap holds and the second dismisses.
  function commit() {
    if (!root.opened) return "closed"
    if (!root.searching && root.armed && root.selected >= 0) {
      var label = root.slices[root.selected].label
      root.run(root.slices[root.selected])
      return "fired:" + label
    }
    if (!root.justOpened) { root.dismiss(); return "dismissed" }
    root.justOpened = false
    return "held"
  }

  function select(i) {
    spin.stop()
    root.armed = true
    root.selected = i
    if (i < 0) return
    // Add the shortest turn while keeping the target unwrapped.
    var slice = root.sliceAngle(i) - 90
    root.arcTarget += ((slice - root.arcTarget) % 360 + 540) % 360 - 180
  }

  function enter(node) {
    root.path = node ? String(node).split(".") : []
    root.query = ""
    root.selected = -1
    root.armed = false
    root.justOpened = false
    spin.stepsLeft = root.sliceCount
    spin.restart()
  }

  // Return only from a panel that this wheel launched and remains open.
  function back() {
    if (!root.launched || !root.shell || !root.shell.isPluginOpen(root.launched)) return "none"
    var at = root.launchedAt
    Qt.callLater(function () {
      root.shell.summon(root.pluginId, "{}")
      if (at >= 0 && at < root.sliceCount) root.select(at)
    })
    return "wheel"
  }

  function up() {
    if (!root.path.length) return false
    root.enter(root.path.slice(0, -1).join("."))
    return true
  }

  function run(e) {
    if (!e) return
    root.countUse(e)
    if (e.node) { root.enter(e.node); return }
    root.launchedAt = root.slices.indexOf(e)
    root.dismiss(true)
    // Unmap this layer before the target requests keyboard focus.
    Qt.callLater(function () {
      if (e.plugin && root.shell) { root.shell.toggle(e.plugin, "{}"); root.launched = e.plugin }
      // Omarchy 4 requires the Lua dispatcher form for window focus.
      else if (e.address) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })")
      else if (e.appId) root.appLibrary.launch(e.appId, e.label)
      else if (e.path && root.shell) {
        root.shell.summon("xpo.files", MenuIndex.pathPayload(e.path))
        root.launched = "xpo.files"
      }
      else if (e.action) Util.execDetached(e.action)
    })
  }

  // Persist each pick; shell shutdown has no reliable flush point.
  function countUse(e) {
    var key = MenuIndex.keyOf(e)
    if (!key) return
    var bump = {}
    bump[key] = (root.uses[key] || 0) + 1
    root.uses = MenuIndex.merge(root.uses, bump)
    usesFile.setText(JSON.stringify(root.uses) + "\n")
  }

  // Compute the caret before assigning query; its change handler clamps it.
  function insert(text) {
    if (!text) return
    var at = root.queryAt + text.length
    root.query = root.query.slice(0, root.queryAt) + text + root.query.slice(root.queryAt)
    root.queryAt = at
  }

  function paste() {
    root.insert(String(Quickshell.clipboardText || "").replace(/\s+/g, " ").trim())
  }

  function takePath() {
    var hit = root.searching ? root.results[root.resultIndex] : null
    if (!hit || !hit.path) return false
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "wheel", hit.path])
    root.dismiss()
    return true
  }

  function moveResult(step) {
    var n = root.results.length
    if (n <= 0) return
    root.resultIndex = (root.resultIndex + step + n) % n
    root.showResult()
  }

  // Keep the selected result inside the visible result window.
  function showResult() {
    var top = Math.min(root.resultTop, root.resultIndex)
    top = Math.max(top, root.resultIndex - root.resultCap + 1)
    root.resultTop = Math.max(0, Math.min(top, root.results.length - root.resultCap))
  }

  // Treat the whole screen as a compass around its center.
  function sliceAt(px, py) {
    var dx = px - surface.width / 2
    var dy = py - surface.height / 2
    if (Math.sqrt(dx * dx + dy * dy) < root.deadzone) return -1
    var deg = (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 360) % 360
    return root.nearestSlice(deg)
  }

  function rotate(step) {
    var n = root.sliceCount
    if (!n) return
    root.charge = Math.min(1, root.charge + 0.16)
    root.huePhase += 0.012
    // A fresh ring steps from its north-facing resting slice.
    var from = root.selected < 0 ? root.nearestSlice(0) : root.selected
    root.select((from + step + n) % n)
  }

  onQueryChanged: {
    root.resultIndex = 0; root.resultTop = 0
    root.queryAt = Math.min(root.queryAt, root.query.length)
  }

  property bool caretLit: true
  Timer {
    running: root.opened && root.searching
    interval: 530
    repeat: true
    onTriggered: root.caretLit = !root.caretLit
    onRunningChanged: root.caretLit = true
  }
  onQueryAtChanged: root.caretLit = true
  onResultsChanged: {
    if (root.resultIndex >= root.results.length) root.resultIndex = 0
    root.showResult()
  }

  // Ignore the null focus event produced when this overlay takes the keyboard.
  onActiveWindowChanged: {
    if (!root.activeWindow) return
    var address = root.activeWindow.address
    var next = [address]
    for (var i = 0; i < root.focusOrder.length; i++)
      if (root.focusOrder[i] !== address) next.push(root.focusOrder[i])
    root.focusOrder = next
  }

  // Scan lazily per open; cap depth to avoid large cache and SDK trees.
  Process {
    id: fileScan
    command: ["fd", "--hidden", "--max-depth", "6", "--exclude", ".cache",
              "--exclude", ".git", "--exclude", "node_modules", ".", root.home]
    property int epoch: 0
    // Ignore partial output from canceled scans.
    stdout: StdioCollector {
      onStreamFinished: if (fileScan.epoch === root.scanEpoch) root.files = MenuIndex.parseFiles(text)
    }
    onExited: if (epoch !== root.scanEpoch) Qt.callLater(root.scanFiles)
  }

  property int scanEpoch: 0
  function scanFiles() {
    if (!root.opened || root.mode !== "file" || root.files || fileScan.running) return
    fileScan.epoch = root.scanEpoch
    fileScan.running = true
  }
  onModeChanged: root.scanFiles()
  onOpenedChanged: if (!root.opened) {
    root.scanEpoch++
    fileScan.running = false
    root.files = null
    root.daylight = 0
  }

  // Themes and fonts change rarely enough to list once at startup.
  Process {
    running: true
    command: ["omarchy", "theme", "list"]
    stdout: StdioCollector { onStreamFinished: root.themes = MenuIndex.lines(text) }
  }

  Process {
    running: true
    command: ["omarchy", "font", "list"]
    stdout: StdioCollector { onStreamFinished: root.fonts = MenuIndex.lines(text) }
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
    onLoaded: root.menuItems = MenuIndex.merge(MenuIndex.parse(text()), root.menuItems)
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    onLoaded: root.menuItems = MenuIndex.merge(root.menuItems, MenuIndex.parse(text()))
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.userBarIds = MenuIndex.barWidgets(text())
    onLoadFailed: root.userBarIds = null
  }

  FileView {
    path: root.omarchyPath + "/config/omarchy/shell.json"
    onLoaded: root.stockBarIds = MenuIndex.barWidgets(text())
  }

  FileView {
    id: usesFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/wheel-uses.json"
    atomicWrites: true
    printErrors: false
    onLoaded: root.uses = MenuIndex.parse(text())
    onLoadFailed: root.uses = ({})
  }

  FileView {
    printErrors: false
    path: Quickshell.env("HOME") + "/.config/omarchy/wheel.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.ringIds = MenuIndex.ringIds(text())
    // Deleting wheel.json restores the default ring.
    onLoadFailed: root.ringIds = null
  }

  // Evaluate all shell conditions once per menu load.
  Process {
    id: conditionScan
    stdout: StdioCollector { onStreamFinished: root.conditions = MenuIndex.parseConditions(text, root.menuItems) }
  }

  // Set command before running; independent bindings can race.
  onMenuItemsChanged: {
    if (!root.menuItems || !Object.keys(root.menuItems).length) return
    conditionScan.command = ["bash", "-c", MenuIndex.conditionScript(root.menuItems)]
    conditionScan.running = true
  }

  onStaticRowsChanged: if (root.opened) root.rebuildIndex()

  PanelWindow {
    id: surface
    visible: root.opened
    screen: root.openScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wheel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Share the bar scrim so panel handoffs do not flash the desktop.
    onVisibleChanged: {
      var bar = root.shell && root.shell.bar
      if (bar && typeof bar.panelSurfaceVisible === "function") bar.panelSurfaceVisible(visible)
    }

    Sky {
      id: sky
      anchors.fill: parent
      phase: root.daylight
      reveal: root.markReveal
    }

    Fluid {
      anchors.fill: parent
      phase: root.daylight
      reveal: root.markReveal
      quietRadius: root.ringRadius + root.itemSize
      warm: sky.keyColor
      cool: sky.mix(Qt.rgba(0.35, 0.32, 0.75, 1), sky.dayColor, sky.light)
      sun: Qt.vector3d(sky.sunPosition.x, sky.sunPosition.y, sky.glow)
      moon: Qt.vector3d(sky.moonPosition.x, sky.moonPosition.y, sky.moon)
    }

    QuietPoints {
      anchors.fill: parent
      progress: root.markReveal
      quietRadius: root.ringRadius + root.itemSize
      tint: root.cometColor
      daylight: sky.light
      haze: sky.dusk
    }

    // R stores path distance, GB the bevel normal, alpha the stroke mask.
    Image {
      id: logoMask
      source: Qt.resolvedUrl("mark.png")
      visible: false
    }

    ShaderEffect {
      anchors.centerIn: parent
      width: surface.height / (2 * 0.47) * 0.98
      height: width
      visible: root.hold > 0
      fragmentShader: Qt.resolvedUrl("logo.frag.qsb")
      layer.enabled: visible
      layer.effect: MultiEffect {
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: "#000000"
        shadowBlur: 1.0
        blurMax: 32
        shadowOpacity: 0.65
        shadowHorizontalOffset: 2
        shadowVerticalOffset: 5
      }
      property var source: logoMask
      readonly property real reveal: root.markReveal
      readonly property real feather: 0.02
      readonly property real head: 0.10
      readonly property real phase: root.markReveal + root.markPhase
      readonly property real pulse: 0.12
      readonly property vector2d pixel: Qt.vector2d(1 / width, 1 / height)
      readonly property vector2d key: sky.keyDirection
      readonly property color keyColor: sky.keyColor
      readonly property real keyStrength: sky.keyStrength
      readonly property color tint: root.cometColor
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onPositionChanged: function (mouse) {
        if (root.searching) return
        if (root.originX < 0) { root.originX = mouse.x; root.originY = mouse.y; return }
        if (!root.armed) {
          var dx = mouse.x - root.originX
          var dy = mouse.y - root.originY
          if (dx * dx + dy * dy < root.moveThreshold * root.moveThreshold) return
        }
        root.select(root.sliceAt(mouse.x, mouse.y))
      }
      onWheel: function (wheel) {
        var step = wheel.angleDelta.y > 0 ? -1 : 1
        root.searching ? root.moveResult(step) : root.rotate(step)
      }
      onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton || root.searching) { root.dismiss(); return }
        var i = root.sliceAt(mouse.x, mouse.y)
        i >= 0 ? root.run(root.slices[i]) : root.dismiss()
      }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) { MenuKeys.onKey(root, event) }
    }

    Item {
      anchors.fill: parent
      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.92
      Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

      // Render the dial into one layer for one shared shadow pass.
      Item {
        anchors.centerIn: parent
        width: root.ringBox
        height: width
        layer.enabled: true
        layer.effect: MultiEffect {
          autoPaddingEnabled: true
          shadowEnabled: true
          shadowColor: "#000000"
          shadowBlur: 1.0
          blurMax: 32
          shadowOpacity: 0.5
          shadowVerticalOffset: Style.space(5)
        }

        WheelRing { wheel: root }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.verticalCenter
          anchors.bottomMargin: root.searchHeight / 2 + Style.spacing.panelGap
          width: root.searchWidth
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideLeft
          text: "‹  " + root.crumb
          color: Color.menu.text
          opacity: root.path.length && !root.searching ? 0.7 : 0
          Behavior on opacity { NumberAnimation { duration: root.fadeDuration } }
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }

        BorderSurface {
          anchors.centerIn: parent
          width: root.searchWidth
          height: root.searchHeight
          radius: height / 2
          color: root.surfaceFill
          borderSpec: Border.flat(root.searching ? Color.accent : root.surfaceEdge,
                                  Style.spacing.hairline)

          ClickShield {}

          // Split around the caret so blinking does not shift text.
          Row {
            id: field
            anchors.centerIn: parent
            spacing: 0
            opacity: root.searching ? 1 : 0.45
            readonly property real budget: root.searchWidth - Style.spacing.rowPaddingX * 2

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, field.budget - caret.width - tail.width)
              elide: Text.ElideLeft
              text: root.searching ? root.query.slice(0, root.queryAt) : "Search"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.subtitle
            }

            Rectangle {
              id: caret
              anchors.verticalCenter: parent.verticalCenter
              visible: root.searching
              width: Style.space(2)
              height: Style.font.subtitle
              color: Color.accent
              opacity: root.caretLit ? 0.85 : 0.0
            }

            Text {
              id: tail
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, field.budget - caret.width)
              elide: Text.ElideRight
              text: root.searching ? root.query.slice(root.queryAt) : ""
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.subtitle
            }
          }
        }
      }

      WheelResults { wheel: root }
    }
  }
}
