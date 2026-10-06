import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Calc.js" as Calc
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
  property alias queryAt: searchInput.cursorPosition
  property var defaultMenu: ({})
  property var userMenu: ({})
  // Answers re-read on every open stay raw text: a string reassigned unchanged notifies nothing.
  property string lockText: ""
  property string conditionText: ""
  property string themeText: ""
  property string fontText: ""
  property string bindText: ""
  property string currentTheme: ""
  property string currentFont: ""
  // The user's entries override the defaults by id; lock designs join as a Style submenu.
  readonly property var menuItems: MenuIndex.merge(MenuIndex.merge(root.defaultMenu,
    MenuIndex.lockItems(MenuIndex.lines(root.lockText))), root.userMenu)
  // [] is home; nested ids point at submenu rings.
  property var path: []
  readonly property string crumb: MenuIndex.crumb(root.menuItems, root.path)
  readonly property var conditions: MenuIndex.parseConditions(root.conditionText, root.menuItems)
  // Prefer the user's bar layout over the stock one.
  property var userBarIds: null
  property var stockBarIds: null
  readonly property var barIds: root.userBarIds || root.stockBarIds
  readonly property var panels: MenuIndex.panels(root.barIds)
  // A chosen ring is keys into search; otherwise it follows the bar.
  property var ringIds: null
  readonly property var ring: root.ringIds ? MenuIndex.ringOf(root.index, root.ringIds) : root.panels
  readonly property var staticRows: MenuIndex.panelRows(MenuIndex.OVERLAYS.concat(MenuIndex.EXTRAS))
    .concat(MenuIndex.menuRows(root.menuItems, root.conditions))
  readonly property var styleRows: MenuIndex.styles(MenuIndex.lines(root.themeText), root.currentTheme,
                                                    MenuIndex.lines(root.fontText), root.currentFont)
  readonly property var bindRows: MenuIndex.bindRows(root.bindText)
  property string shortcut: MenuIndex.SHORTCUT
  // The backdrop in percent as the shell draws it; while changed, the value the shell reads back next.
  property int backdropDraft: 0
  readonly property int backdrop: root.editing === "backdrop" ? root.backdropDraft
    : Math.round(Color.menu.scrim.a * 100)
  readonly property var settingRows: MenuIndex.settingRows(root.shortcut, !!root.ringIds)
  // The setting row being changed in place: the field shows the value, the row what saving would do.
  property string editing: ""
  property string editValue: ""
  property string editNote: ""
  property string pending: ""
  // The ring editor: search adds to the ring, and the ring's own keys move and remove its slices.
  property bool editingRing: false
  // Ctrl+R asks twice before the ring is reset to the bar's.
  property bool resetAsked: false
  readonly property string ringHint: root.searching ? "enter adds to the ring"
    : root.resetAsked ? "ctrl+r again resets the ring\nany other key cancels"
    : "del removes · shift+←→ reorders\n" + (root.ringIds ? "ctrl+r resets · " : "") + "esc done"
  // Hyprland's cached history goes stale; accumulate activeToplevel changes.
  property var focusOrder: []
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property var index: []
  property var uses: ({})
  // A leading sigil selects one search source; the ring editor searches only what a ring holds.
  readonly property string mode: root.editingRing ? "" : MenuIndex.modeOf(root.query)
  readonly property string term: MenuIndex.termOf(root.query)
  // Cache scanned home paths only for the current open.
  property var files: null
  readonly property int resultLimit: 40
  readonly property int resultCap: 8
  readonly property var results: root.mode === "file"
    ? MenuIndex.fileRows(root.files, root.term, root.resultLimit, root.home)
    : root.mode === "calc" ? Calc.rows(root.term)
    : MenuIndex.search(root.editingRing ? root.index.filter(MenuIndex.pinnable) : root.index,
                       root.term, root.resultLimit, root.uses)
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
  readonly property string emptyText: root.mode === "calc" ? (root.term ? "No answer" : "Type to calculate")
    : root.mode !== "file" ? "No match"
    : !root.files ? "Scanning\u2026"
    : !root.term ? "Type to find files\nctrl+y copy path\nctrl+enter terminal"
    : "No match"

  // Clockwise from north; node slices drill into submenu rings.
  readonly property var slices: MenuIndex.ringSlices(root.menuItems, root.path,
                                                     root.conditions, root.ring)
  property var previousSlices: []
  onSlicesChanged: {
    if (root.selected >= 0) root.select(MenuIndex.indexOfEntry(root.slices, root.previousSlices[root.selected]))
    root.previousSlices = root.slices
  }

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

  // Refresh live panels/apps/windows per open; panels need not be on the ring.
  function rebuildIndex() {
    var live = MenuIndex.panelRows(MenuIndex.livePanels(
      root.shell && root.shell.panels ? root.shell.panels() : []))
    root.index = MenuIndex.withBindings(root.staticRows.concat(live, MenuIndex.liveRows({
      apps: root.appLibrary ? root.appLibrary.sortedEntries("") : [],
      windows: Hyprland.toplevels.values,
      focusOrder: root.focusOrder
    }), root.styleRows, root.settingRows), root.bindRows, root.menuItems)
  }

  function closePeers() {
    return root.shell ? root.shell.closePeers() : { acted: false, clear: true }
  }

  function open() {
    // Treat a press during fade-out as a fresh open.
    var wasOpen = root.opened && !unmap.running
    unmap.stop()
    var peers = root.closePeers()
    if (!peers.clear) return
    if (root.shell) root.shell.claimPopout(root)
    root.selected = -1
    root.armed = false
    root.originX = -1
    root.query = ""
    root.path = []
    root.launched = ""
    root.launchedAt = -1
    root.editing = ""
    root.editingRing = false
    root.justOpened = !wasOpen
    root.openScreen = root.focusedScreen()
    root.opened = true
    root.rebuildIndex()
    root.reread()
    spin.stepsLeft = root.sliceCount
    spin.restart()
    Qt.callLater(function () { root.shown = true; searchInput.forceActiveFocus() })
  }

  // Fade cancellation; unmap immediately before handing keyboard focus to a panel.
  function close(immediate) {
    if (root.shell) root.shell.releasePopout(root)
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
    if (root.shell) root.shell.hide(root.pluginId)
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

  // Release fires a flick; the first tap holds and the second dismisses. Only the opening press's
  // release fires: the next press closes the wheel itself, and its release may land first.
  function commit() {
    if (!root.opened || unmap.running) return "closed"
    if (!root.justOpened) { root.dismiss(); return "dismissed" }
    root.justOpened = false
    if (!root.searching && root.armed && root.selected >= 0) {
      var label = root.slices[root.selected].label
      root.run(root.slices[root.selected])
      return "fired:" + label
    }
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
    if (root.editingRing) { root.pin(e); return }
    root.countUse(e)
    if (e.node) { root.enter(e.node); return }
    if (e.setting) { root.edit(e); return }
    root.launchedAt = root.slices.indexOf(e)
    root.dismiss(true)
    // Unmap this layer before the target requests keyboard focus.
    Qt.callLater(function () {
      if (e.plugin && root.shell) { root.shell.toggle(e.plugin, "{}"); root.launched = e.plugin }
      // Omarchy 4 requires the Lua dispatcher form for window focus.
      else if (e.address) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })")
      else if (e.dispatch) Hyprland.dispatch(e.dispatch)
      else if (e.appId) root.appLibrary.launch(e.appId, e.label)
      else if (e.path && root.shell) {
        root.shell.summon("xpo.files", MenuIndex.pathPayload(e.path))
        root.launched = "xpo.files"
      }
      else if (e.copy) root.copy(e.copy)
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

  // The ring row hands the home ring to its editor, and the backdrop row takes ←/→. The shortcut
  // row records the next combo; Hyprland's bindings pause meanwhile, so a taken one arrives too.
  function edit(e) {
    if (e.setting === "ring") { root.enter(""); root.editingRing = true; root.resetAsked = false; return }
    root.backdropDraft = root.backdrop
    root.editing = e.setting
    root.pending = ""
    root.editValue = e.setting === "backdrop" ? root.backdrop + "%" : "Press a shortcut"
    root.editNote = e.setting === "backdrop" ? "←→ adjusts" : "esc cancels"
  }

  // Plain Enter saves what was pressed, plain Esc gives up, and any other combo is the new candidate.
  function record(event) {
    var bare = !(event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier))
    if (bare && event.key === Qt.Key_Escape) { root.editing = ""; return }
    if (bare && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      if (root.pending) root.saveShortcut(root.pending)
      root.editing = ""
      return
    }
    var combo = MenuKeys.shortcutOf(event)
    if (combo === null) return
    root.pending = ""
    root.editValue = combo || "Press a shortcut"
    if (!combo) root.editNote = "pick another key"
    else if (!/^(SUPER|CTRL|ALT) \+ /.test(combo)) root.editNote = "add SUPER, CTRL or ALT"
    else if (combo === "SUPER + W") root.editNote = "closes the wheel"
    else if (combo === root.shortcut) root.editNote = "already set"
    else {
      var taken = MenuIndex.bindingAt(root.bindText, combo)
      root.editNote = taken ? "replaces " + taken : "enter saves"
      root.pending = combo
    }
  }

  // Hyprland reads the file on reload; the bindings are read again after it, for the next conflict.
  function saveShortcut(combo) {
    root.shortcut = combo
    shortcutFile.setText(combo + "\n")
  }

  // Saved at once, so the backdrop behind the wheel shows it. Blur is on above 0%, and only turning
  // it reloads Hyprland, which re-applies the layer rule to the open backdrop.
  function setBackdrop(percent) {
    if ((percent > 0) !== (root.backdrop > 0)) blurFile.setText(percent > 0 ? "on\n" : "off\n")
    root.backdropDraft = percent
    root.editValue = percent + "%"
    shellFile.setText(MenuIndex.withScrimAlpha(shellFile.text(), percent / 100))
  }

  // A row joins the ring after the selected slice, or at the end; one already there is selected.
  function pin(e) {
    var keys = root.ring.map(MenuIndex.keyOf)
    var at = keys.indexOf(MenuIndex.keyOf(e))
    if (at < 0) {
      at = root.selected >= 0 ? root.selected + 1 : keys.length
      keys.splice(at, 0, MenuIndex.keyOf(e))
      root.saveRing(keys)
    }
    root.query = ""
    root.select(at)
  }

  // The next slice takes the removed one's place, so Del can clear a run of them.
  function unpin() {
    var at = root.selected
    if (at < 0) return
    var keys = root.ring.map(MenuIndex.keyOf)
    keys.splice(at, 1)
    root.saveRing(keys)
    root.select(Math.min(at, root.sliceCount - 1))
  }

  // A slice swaps places with its neighbour, across north too, as the ring has no ends.
  function moveSlice(step) {
    var n = root.sliceCount
    if (root.selected < 0 || n < 2) return
    var keys = root.ring.map(MenuIndex.keyOf)
    var to = (root.selected + step + n) % n
    var key = keys[root.selected]
    keys[root.selected] = keys[to]
    keys[to] = key
    root.saveRing(keys)
    root.select(to)
  }

  function resetRing() {
    if (!root.ringIds) return
    if (!root.resetAsked) { root.resetAsked = true; return }
    root.resetAsked = false
    root.saveRing(null)
  }

  // An empty ring follows the bar, as an empty list in the file does.
  function saveRing(keys) {
    root.ringIds = keys && keys.length ? keys : null
    ringFile.setText(MenuIndex.withSlices(ringFile.text(), root.ringIds))
  }

  function paste() {
    var text = String(Quickshell.clipboardText || "").replace(/\s+/g, " ").trim()
    searchInput.remove(searchInput.selectionStart, searchInput.selectionEnd)
    searchInput.insert(searchInput.cursorPosition, text)
  }

  function takePath() {
    var hit = root.searching ? root.results[root.resultIndex] : null
    if (!hit || !hit.path) return false
    root.copy(hit.path)
    root.dismiss()
    return true
  }

  // A terminal in the highlighted path's folder; the wheel unmaps first, as in run().
  function terminal() {
    var hit = root.searching ? root.results[root.resultIndex] : null
    if (!hit || !hit.path) return false
    root.dismiss(true)
    Qt.callLater(function () {
      Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + MenuIndex.dirOf(hit.path)])
    })
    return true
  }

  function copy(text) {
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "wheel", text])
  }

  function moveResult(step) {
    var n = root.results.length
    if (n <= 0) return
    var from = root.resultIndex < 0 && step < 0 ? 0 : root.resultIndex
    root.resultIndex = (from + step + n) % n
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
  }

  property var previousResults: []
  property string previousQuery: ""
  onResultsChanged: {
    if (root.query !== root.previousQuery) root.resultIndex = 0
    else if (root.previousResults[root.resultIndex])
      root.resultIndex = MenuIndex.indexOfEntry(root.results, root.previousResults[root.resultIndex])
    root.previousResults = root.results
    root.previousQuery = root.query
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
  onOpenedChanged: {
    if (root.shell) root.shell.panelSurfaceVisible(root.opened)
    if (!root.opened) {
      root.scanEpoch++
      fileScan.running = false
      root.files = null
      root.daylight = 0
      root.editing = ""
    }
  }

  // Omarchy's menu re-checks its rows on every open, and so does the wheel, so a row follows
  // state that changed under it. Answers land a moment after the wheel appears.
  function reread() {
    root.checkConditions()
    themeList.running = true
    themeNow.running = true
    fontList.running = true
    fontNow.running = true
    lockList.running = true
    bindList.running = true
  }

  Process {
    id: themeList
    running: true
    command: ["omarchy", "theme", "list"]
    stdout: StdioCollector { onStreamFinished: root.themeText = text }
  }

  Process {
    id: themeNow
    running: true
    command: ["omarchy", "theme", "current"]
    stdout: StdioCollector { onStreamFinished: root.currentTheme = text.trim() }
  }

  Process {
    id: fontList
    running: true
    command: ["omarchy", "font", "list"]
    stdout: StdioCollector { onStreamFinished: root.fontText = text }
  }

  Process {
    id: fontNow
    running: true
    command: ["omarchy", "font", "current"]
    stdout: StdioCollector { onStreamFinished: root.currentFont = text.trim() }
  }

  Process {
    id: lockList
    running: true
    command: ["omarchy-lock-design", "list"]
    stdout: StdioCollector { onStreamFinished: root.lockText = text }
  }

  // Omarchy's keybindings menu caches the command behind each binding; printing refreshes the cache.
  Process {
    id: bindList
    running: true
    command: ["bash", "-c", "omarchy-menu-keybindings --print >/dev/null; cat \"${XDG_CACHE_HOME:-$HOME/.cache}\"/omarchy/keybindings-*.records 2>/dev/null"]
    stdout: StdioCollector { onStreamFinished: root.bindText = text }
  }

  // Both menu files are watched, as Omarchy's menu watches them, so an edit shows on save.
  FileView {
    path: root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.defaultMenu = MenuIndex.parse(text())
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.userMenu = MenuIndex.parse(text())
    onLoadFailed: root.userMenu = ({})
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
    id: ringFile
    printErrors: false
    path: Quickshell.env("HOME") + "/.config/omarchy/wheel.json"
    watchChanges: true
    atomicWrites: true
    onFileChanged: reload()
    onLoaded: root.ringIds = MenuIndex.ringIds(text())
    // Deleting wheel.json restores the default ring.
    onLoadFailed: root.ringIds = null
  }

  // The launch key, as data the Hyprland block reads on reload; Hyprland does not watch it.
  FileView {
    id: shortcutFile
    path: Quickshell.env("HOME") + "/.config/omarchy/wheel-shortcut"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.shortcut = MenuIndex.shortcutIn(text())
    onLoadFailed: root.shortcut = MenuIndex.SHORTCUT
    onSaved: hyprReload.running = true
  }

  // The shell watches this file and draws its [menu] scrim-alpha over the theme's. Re-read on change,
  // so a write keeps what another writer just put here.
  FileView {
    id: shellFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
  }

  // The backdrop's blur, as data the Hyprland block reads on reload.
  FileView {
    id: blurFile
    path: Quickshell.env("HOME") + "/.config/omarchy/wheel-blur"
    atomicWrites: true
    printErrors: false
    onSaved: hyprReload.running = true
  }

  Process {
    id: hyprReload
    command: ["hyprctl", "reload"]
    onExited: bindList.running = true
  }

  // Recording pauses Hyprland's bindings for this surface alone, until the row lets go.
  ShortcutInhibitor {
    window: surface
    enabled: root.editing === "shortcut"
    onCancelled: root.editing = ""
  }

  Process {
    id: conditionScan
    // The menu the command was written for: writing it costs a millisecond, too much for every open.
    property var writtenFor: null
    stdout: StdioCollector { onStreamFinished: root.conditionText = text }
  }

  // Started again mid-run, a Process runs once more when the run ends, with the newest command.
  function checkConditions() {
    if (!Object.keys(root.menuItems).length) return
    if (conditionScan.writtenFor !== root.menuItems) {
      conditionScan.writtenFor = root.menuItems
      conditionScan.command = ["bash", "-c", MenuIndex.conditionScript(root.menuItems)]
    }
    conditionScan.running = true
  }

  onMenuItemsChanged: root.checkConditions()
  onStaticRowsChanged: if (root.opened) root.rebuildIndex()
  onStyleRowsChanged: if (root.opened) root.rebuildIndex()
  onBindRowsChanged: if (root.opened) root.rebuildIndex()
  onSettingRowsChanged: if (root.opened) root.rebuildIndex()

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
        shadowEnabled: true
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
          shadowEnabled: true
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
          // A submenu's crumb, or what the ring editor's keys do.
          text: root.editingRing ? root.ringHint : "‹  " + root.crumb
          color: Color.menu.text
          opacity: root.editingRing || root.path.length && !root.searching ? 0.7 : 0
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

          // While a setting row records, the field shows what was pressed; the query waits underneath.
          Text {
            anchors.centerIn: parent
            width: parent.width - Style.spacing.rowPaddingX * 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideLeft
            visible: !!root.editing
            text: root.editValue
            color: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
          }

          Text {
            anchors.centerIn: parent
            visible: !root.searching
            text: root.editingRing ? "Add to ring" : "Search · / files · = calc"
            color: Color.menu.text
            opacity: 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
          }

          TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            clip: true
            focus: true
            // Hidden by opacity: an invisible item would lose the keyboard the recording needs.
            opacity: root.editing ? 0 : 1
            text: root.query
            color: Color.menu.text
            selectionColor: Util.alpha(Color.accent, 0.35)
            selectedTextColor: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
            cursorVisible: activeFocus && text.length > 0
            cursorDelegate: Rectangle {
              width: Style.space(2)
              color: Color.accent
              // TextInput does not hide a custom cursor delegate automatically.
              visible: searchInput.cursorVisible
            }
            onTextChanged: root.query = text
            Keys.onPressed: function (event) { MenuKeys.onKey(root, event) }
          }
        }
      }

      WheelResults { wheel: root }
    }
  }
}
