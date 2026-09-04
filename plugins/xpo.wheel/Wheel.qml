import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "MenuIndex.js" as MenuIndex

// Radial control center. Eight panels sit on a ring reachable by direction,
// and typing searches every menu entry the system knows about -- the ring is
// the fast path for what you use daily, search is the complete one.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Defaulted from the environment rather than left empty: the shell injects
  // this only after the component loads, and the FileViews below read on their
  // first binding evaluation.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property bool opened: false
  property bool shown: false
  // Selection stays disarmed until the pointer or a key actually moves, so a
  // bare tap never fires whichever slice the cursor happened to point at when
  // the surface mapped.
  property bool armed: false
  property bool justOpened: false
  property int selected: -1

  property string query: ""
  property var menuItems: ({})
  // Where the ring is pointed: [] is home, ["install"] the Install ring.
  property var path: []
  readonly property string crumb: MenuIndex.crumb(root.menuItems, root.path)
  // Which `when` conditions hold, in one subprocess. Flagged not-ready until
  // the first run lands, which keeps the menu whole meanwhile.
  property var conditions: MenuIndex.NO_CONDITIONS
  // The bar's widgets, the user's file winning over the one Omarchy ships.
  // Null only if neither could be read, which offers everything rather than
  // nothing.
  property var userBarIds: null
  property var stockBarIds: null
  readonly property var barIds: root.userBarIds || root.stockBarIds
  readonly property var panels: MenuIndex.panels(root.barIds)
  // Ids, not slices: what each name resolves to depends on the menu and on
  // which conditions hold.
  property var ringIds: null
  readonly property var ring: root.ringIds
    ? MenuIndex.ringOf(root.menuItems, root.ringIds, root.conditions)
    : root.panels
  readonly property var staticRows: MenuIndex.panelRows(root.panels)
    .concat(MenuIndex.menuRows(root.menuItems, root.conditions))
  property var themes: []
  property var fonts: []
  // Window addresses, most recently focused first. Hyprland has its own focus
  // history, but only inside each toplevel's cached IPC object, which is not
  // re-fetched when focus moves -- it reports whatever was true when the list
  // was last pulled. `activeToplevel` does track focus, so the order is
  // accumulated from that instead.
  property var focusOrder: []
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property var index: []
  readonly property var results: MenuIndex.search(root.index, root.query, 8)
  property int resultIndex: 0
  readonly property bool searching: root.query.length > 0

  // Clockwise from north. The ring is the panels -- the things with a widget
  // worth a disc -- and the rest of the menu is one search away instead.
  // `wheel.json` replaces the list with whatever the user wants on it. A slice
  // carrying a `node` drills into that node's children rather than firing.
  readonly property var slices: MenuIndex.ringSlices(root.menuItems, root.path,
                                                     root.conditions, root.ring)

  // The ring sizes itself to what it holds: a constant arc per slice, paid for
  // by growing the radius, so a disc and its label have the same room at
  // fourteen slices as at eight.
  readonly property int sliceCount: root.slices.length
  readonly property real sliceStep: 360 / Math.max(1, root.sliceCount)

  // Slices are evenly spaced; the only choice is where the first one goes. An
  // even count is rotated so two of them land at 3 and 9 o'clock, flanking the
  // field -- which is what eight slices did for free at 45 degrees apart. An
  // odd count cannot have both: east and west are half a turn apart, and half
  // a turn is a whole number of steps only when the count is even. Those
  // anchor north, which at least keeps the ring symmetric about the vertical.
  readonly property real sliceOrigin: root.sliceCount % 2 === 0 ? 90 % root.sliceStep : 0
  function sliceAngle(i) { return root.sliceOrigin + i * root.sliceStep }
  function nearestSlice(deg) {
    // A wheel.json naming nothing that resolves leaves an empty ring, and the
    // modulo below would hand back NaN as a selection.
    if (!root.sliceCount) return -1
    var i = Math.round((deg - root.sliceOrigin) / root.sliceStep)
    return ((i % root.sliceCount) + root.sliceCount) % root.sliceCount
  }

  readonly property int baseItem: Style.space(76)
  // The grown disc plus air: the arc each slice is entitled to.
  readonly property real slicePitch: root.baseItem * root.selectedScale + Style.space(28)
  // Growth stops before the labels would run off the short edge of the screen.
  readonly property int maxRadius: Math.max(Style.space(160),
    Math.min(surface.width, surface.height) / 2 - root.baseItem * 1.9)
  readonly property int ringRadius: Math.min(root.maxRadius,
    Math.max(Style.space(240), root.slicePitch * root.sliceCount / (2 * Math.PI)))
  // Only bites once the radius has hit its cap: the chord between neighbouring
  // centres, less a hairline of air.
  readonly property int itemSize: Math.max(Style.space(36),
    Math.min(root.baseItem,
             2 * root.ringRadius * Math.sin(Math.PI / Math.max(2, root.sliceCount)) - Style.space(14)))
  readonly property int deadzone: Style.space(54)
  // How much a disc grows when it is the selected one.
  readonly property real selectedScale: 1.08
  // Disc edge to nearest label edge, at the disc's grown size.
  readonly property int labelGap: Style.space(18)
  // The dial's layer has to hold the labels too, and they sit outside the ring
  // now -- at itemSize * 1.5 the east and west ones came within 7px of being
  // clipped by it.
  readonly property real ringBox: (root.ringRadius + root.itemSize * 2) * 2
  // The field lives in the ring's hole, so its width is the hole's: that is
  // the room the wheel makes for it, and deriving it means the field can never
  // reach under the east and west slices when either size is retuned.
  // Sized to leave real air inside the hole rather than filling it edge to
  // edge, but still clamped to the hole so it can never reach under the east
  // and west slices if either size is retuned.
  readonly property int searchWidth: Math.min(Style.space(280),
    (root.ringRadius - root.itemSize / 2) * 2 - Style.space(48))
  // Shared by the pill and by the results card, which is placed off the
  // surface's center rather than off the pill itself.
  readonly property int searchHeight: Style.spacing.controlHeight + Style.spacing.controlPaddingY * 2

  // Where the arc is headed on the dial, and the two followers chasing it. The
  // head nearly keeps up and the tail drags well behind, so the gap between
  // them reads out how fast the ring is being turned: nothing while stepping,
  // a long streak while an arrow is held down. Unwrapped rather than kept in
  // 0..360, so a lap past north keeps running forward.
  property real arcTarget: -90
  // Both durations ride the charge: the head closes on the target quicker
  // while the tail lets go slower, so a held arrow sharpens the point and
  // stretches the streak at the same time.
  property real arcHead: root.arcTarget
  Behavior on arcHead { NumberAnimation { duration: 90 - 45 * root.charge; easing.type: Easing.OutCubic } }
  property real arcTail: root.arcTarget
  Behavior on arcTail { NumberAnimation { duration: 300 + 160 * root.charge; easing.type: Easing.OutCubic } }
  // Half the arc at rest. The discs are painted over the dial, so anything no
  // wider than one hides behind it; half a slice's share of the ring, less a
  // hair, lights the dial on either side of the selected disc instead.
  readonly property real arcSpread: root.sliceStep / 2 * 0.85
  // Clamped: a held arrow drags the tail more than a lap behind, and an arc
  // past a full turn is just the circle again -- it stops reading as motion.
  // Clamping from the head keeps the point and loses the far end of the tail.
  readonly property real arcDrag: Math.max(-300, Math.min(300, root.arcHead - root.arcTail))
  readonly property real arcFrom: Math.min(root.arcHead, root.arcHead - root.arcDrag) - root.arcSpread
  readonly property real arcSpan: Math.abs(root.arcDrag) + root.arcSpread * 2
  // How hard the ring is being turned, 0 at rest and 1 saturated. Every step
  // adds a bite and the bleed takes it back out faster than a person can
  // press: stepping by hand never accumulates, while an arrow held at the
  // 40Hz key-repeat rate fills it in about a quarter second and a release
  // empties it in half of one. The comet's hue and its speed both read from
  // this one number, so the two cannot drift apart.
  property real charge: 0

  // How far round the color wheel this spin has travelled. A fixed offset per
  // charge arrives at one color and sits there, which is what a long hold
  // looked like: this keeps moving for as long as the ring is being turned,
  // about half a rotation of hue per second at the key-repeat rate.
  property real huePhase: 0

  // One tick bleeds both of those back out.
  Timer {
    interval: 40
    repeat: true
    running: root.charge > 0
    onTriggered: {
      root.charge = Math.max(0, root.charge - 0.09)
      // Back to the theme's own accent once the ring has stopped, so the next
      // spin starts from it rather than from wherever the last one ended.
      if (root.charge <= 0) root.huePhase = 0
    }
  }

  // The comet heats up as it spins: the accent's own color, turned `turns` of
  // the way round the spectrum, with `amount` saying how far from the accent
  // it is allowed to get. Swept in OKLCH rather than HSL, because rotating an
  // HSL hue at a fixed lightness walks sRGB's idea of brightness rather than
  // the eye's -- a pure yellow carries about twice the weight of a pure blue
  // at the same "lightness", so the sweep lands hard on four or five poster
  // colors and skips everything in between. OKLCH holds the perceived
  // lightness and the chroma steady, so the whole spectrum comes past at one
  // weight and no hue is a landmark.
  function cometAt(turns, amount) {
    // Cube root by hand: the linear channels below are never negative, and
    // Math.cbrt is not worth depending on for three calls.
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
    // Pulled toward a band that can actually hold color at every hue as the
    // spin builds: a near-white or near-black accent has nowhere to put
    // chroma, and a grey one has no chroma to rotate in the first place.
    // At `amount` 0 both are the accent's own, so a ring at rest is exactly
    // the theme's color and winds back to it as the spin bleeds out.
    L += (Math.min(0.78, Math.max(0.52, L)) - L) * amount
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

  // How hard the comet is sitting over a given bearing: 1 right at the head,
  // falling off to 0 at the end of the tail, 0 anywhere the streak is not.
  // What the trail crosses lights up from this, which is what stops the
  // streak looking like it passes behind the discs.
  function sweepAt(deg) {
    var span = Math.abs(root.arcDrag) + root.arcSpread
    // Degrees behind the head, measured against the way the ring is turning.
    var off = ((deg - root.arcHead) % 360 + 540) % 360 - 180
    var behind = root.arcDrag >= 0 ? -off : off
    if (behind < -root.arcSpread || behind > span) return 0
    return 1 - Math.max(0, behind) / span
  }

  // Opening spins the comet once around the ring. This has to step the target
  // in whole slices at the key-repeat rate rather than sweep it smoothly: the
  // streak is the gap the two followers open up behind a jump, so a target
  // that slides continuously is tracked almost exactly and draws no trail at
  // all. Eight jumps of 45 degrees is one lap, and 25ms apart is the 40Hz a
  // held arrow delivers -- the same input, so the same streak.
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

  // One palette for every floating piece of the wheel -- discs, pill, card --
  // so they can't drift apart. Short of opaque so the blur still reads through.
  readonly property color surfaceFill: Util.alpha(Color.menu.background, 0.85)
  readonly property color surfaceEdge: Util.alpha(Color.menu.text, 0.16)
  // The accent is the theme's one loud color, so selection spends it.
  readonly property color selectedFill: Qt.tint(Util.alpha(Color.menu.background, 0.9),
                                                Util.alpha(Color.accent, 0.22))
  // The pointer-enter that arrives when the surface maps is a synthetic move,
  // so the first sample is kept as an origin and the wheel only arms once the
  // pointer has travelled past this from it.
  readonly property int moveThreshold: Style.space(8)
  // One tempo for every transition the wheel makes as a whole: the open and
  // close fade, the timer that waits on it, and the ring-to-results swap.
  readonly property int fadeDuration: 130
  property real originX: -1
  property real originY: -1
  readonly property string pluginId: (manifest && manifest.id) || "xpo.wheel"

  // Applications come from the shell's own library rather than a .desktop scan
  // of our own: it sorts, drops hidden entries, resolves icon names, and
  // launches through uwsm so an app doesn't inherit the compositor's scope.
  // Windows come straight off the compositor. Both are read fresh on every
  // open rather than watched, which is the only moment either has to be right.
  // The menu half is flattened once per file load instead: doing that on every
  // open costs three times what everything else costs together.
  function rebuildIndex() {
    root.index = root.staticRows.concat(MenuIndex.liveRows({
      apps: root.appLibrary ? root.appLibrary.sortedEntries("") : [],
      windows: Hyprland.toplevels.values,
      focusOrder: root.focusOrder,
      themes: root.themes,
      fonts: root.fonts
    }))
  }

  function open(payloadJson) {
    // A wheel that is still fading out is logically shut, so a press during
    // the fade is a fresh open and earns the tap-to-hold grace.
    var wasOpen = root.opened && !unmap.running
    unmap.stop()
    root.selected = -1
    root.armed = false
    root.originX = -1
    root.query = ""
    // Home: where the wheel opens must not depend on what was done last time.
    root.path = []
    // Only a press that actually opened the wheel earns the tap-to-hold grace;
    // a press onto an already-open wheel is the second tap, which closes it.
    root.justOpened = !wasOpen
    root.opened = true
    root.rebuildIndex()
    spin.stepsLeft = root.sliceCount
    spin.restart()
    Qt.callLater(function () { root.shown = true; keys.forceActiveFocus() })
  }

  // `visible` follows `opened`, so dropping it unmaps the layer surface on the
  // spot -- which is why the exit half of the fade never used to play. Drop
  // `shown` to run the fade and let the surface go once it has finished.
  //
  // Firing a slice is the one case that cannot wait: the target panel grabs
  // the keyboard on the next tick, and a layer surface still holding an
  // exclusive grab hands it a window without focus. Cancelling has nobody to
  // hand off to, so that path gets the fade. The shell's own hide() reaches
  // this as close(null), which is the fade.
  function close(immediate) {
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

  // Everything the wheel can put on screen, closed in one call: the wheel
  // itself plus whatever it opened. Reports whether it actually closed
  // anything, so the SUPER+W wrapper knows whether to fall through to
  // Omarchy's own close-window.
  function closeAll() {
    var acted = root.opened
    if (root.opened) root.dismiss()
    if (!root.shell) return acted ? "closed" : "none"
    // The catalogue, not the ring: a panel reached from search still has to
    // be closable.
    var catalogue = MenuIndex.panels(null)
    for (var i = 0; i < catalogue.length; i++) {
      var id = catalogue[i].plugin
      if (id && root.shell.isPluginOpen(id)) { root.shell.hide(id); acted = true }
    }
    // The bar's own menu widget is a shell plugin too, and a wheel entry can
    // still have summoned a picker that lives inside it.
    if (root.shell.isPluginOpen("omarchy.menu")) { root.shell.hide("omarchy.menu"); acted = true }
    return acted ? "closed" : "none"
  }

  // Driven by the release half of the keybind. A flick that landed on a slice
  // fires it; a bare tap leaves the wheel up for the keyboard, and a second
  // bare tap closes it again.
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
    // The short way round from wherever the arc is already pointed, added on
    // rather than assigned, which is what keeps the target unwrapped.
    var slice = root.sliceAngle(i) - 90
    root.arcTarget += ((slice - root.arcTarget) % 360 + 540) % 360 - 180
  }

  // Point the ring at a submenu: nothing is dismissed and nothing is spawned.
  function enter(node) {
    // "" is home, and "".split(".") is [""] rather than [] -- which would
    // point the ring at a node whose id is the empty string, i.e. the menu's
    // own top level, instead of at the slices the user chose.
    root.path = node ? String(node).split(".") : []
    root.query = ""
    root.selected = -1
    root.armed = false
    // The grace is spent: releasing the keybind must not take the new ring away.
    root.justOpened = false
    spin.stepsLeft = root.sliceCount
    spin.restart()
  }

  // One level up. At home the caller decides: Escape closes, Backspace doesn't.
  function up() {
    if (!root.path.length) return false
    root.enter(root.path.slice(0, -1).join("."))
    return true
  }

  // Ring slices and search results carry the same fields, so which of the two
  // was picked stops mattering here.
  function run(e) {
    if (!e) return
    if (e.node) { root.enter(e.node); return }
    root.dismiss(true)
    // Let this layer surface unmap and hand the keyboard back before the
    // target grabs it, or the panel opens without focus.
    Qt.callLater(function () {
      if (e.plugin && root.shell) root.shell.toggle(e.plugin, "{}")
      // Omarchy 4 configures Hyprland in Lua, and its dispatcher rejects the
      // legacy string form -- which is what both Quickshell's own activate()
      // and `hyprctl dispatch focuswindow` send, silently doing nothing.
      else if (e.address) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })")
      else if (e.appId) root.appLibrary.launch(e.appId, e.label)
      else if (e.action) Util.execDetached(e.action)
    })
  }

  function moveResult(step) {
    var n = root.results.length
    if (n > 0) root.resultIndex = (root.resultIndex + step + n) % n
  }

  // Direction from screen center, read off the absolute pointer position: the
  // whole screen acts as a compass, so a flick from anywhere selects and no
  // cursor warp is needed to keep pointing coherent with a centered wheel.
  function sliceAt(px, py) {
    var dx = px - surface.width / 2
    var dy = py - surface.height / 2
    if (Math.sqrt(dx * dx + dy * dy) < root.deadzone) return -1
    var deg = (Math.atan2(dy, dx) * 180 / Math.PI + 90 + 360) % 360
    return root.nearestSlice(deg)
  }

  function rotate(step) {
    var n = root.sliceCount
    root.charge = Math.min(1, root.charge + 0.16)
    root.huePhase += 0.012
    root.select(root.selected < 0 ? (step > 0 ? 0 : n - 1) : (root.selected + step + n) % n)
  }

  onQueryChanged: root.resultIndex = 0

  // Opening the wheel takes the keyboard, which drops activeToplevel to null.
  // Ignoring that is what keeps the window you came from at the head.
  onActiveWindowChanged: {
    if (!root.activeWindow) return
    var address = root.activeWindow.address
    var next = [address]
    for (var i = 0; i < root.focusOrder.length; i++)
      if (root.focusOrder[i] !== address) next.push(root.focusOrder[i])
    root.focusOrder = next
  }

  // Listed once at startup: installing a theme or a font is a rare, deliberate
  // act, and both commands cost a subprocess that opening the wheel shouldn't.
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

  // Watched, so a widget added to the bar turns up without a shell restart.
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.userBarIds = MenuIndex.barWidgets(text())
    onLoadFailed: root.userBarIds = null
  }

  // What Omarchy ships. A machine that has never edited its bar has no user
  // config at all, and the whole catalogue would put panels on the ring that
  // this machine has no widget for.
  FileView {
    path: root.omarchyPath + "/config/omarchy/shell.json"
    onLoaded: root.stockBarIds = MenuIndex.barWidgets(text())
  }

  // The ring, if the user has said what they want on it. Absent by default.
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/wheel.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.ringIds = MenuIndex.ringIds(text())
    // Deleting the file is how you go back to the default, and only success
    // has a signal -- without this the ring keeps a since-deleted list.
    onLoadFailed: root.ringIds = null
  }

  // 144 shell conditions in one bash process rather than 144 processes, and
  // once at startup rather than per open -- installing a package is rare, and
  // pressing SUPER+A is not the moment to spend 1.2s asking about it. The
  // alternative is a menu that lies about what this machine can do.
  Process {
    id: conditionScan
    stdout: StdioCollector { onStreamFinished: root.conditions = MenuIndex.parseConditions(text, root.menuItems) }
  }

  // Started by hand rather than by binding `running`. `running` and `command`
  // would be two bindings firing off the same change, and a run that got away
  // before the command was rebuilt read an empty script -- whose empty output
  // is indistinguishable from every condition failing, which hid every
  // conditional row in the menu.
  onMenuItemsChanged: {
    if (!root.menuItems || !Object.keys(root.menuItems).length) return
    conditionScan.command = ["bash", "-c", MenuIndex.conditionScript(root.menuItems)]
    conditionScan.running = true
  }

  // The ring binds to `conditions`; the index is built by hand, so it has to
  // be told when the answers land late.
  onStaticRowsChanged: if (root.opened) root.rebuildIndex()

  // A widget's own icon component, for the two marks that have no glyph at all.
  // Loaded by URL off `omarchyPath` rather than imported: an import path has to
  // be a literal, and this one belongs to another plugin whose location is only
  // known at runtime.
  component PanelIcon: Loader {
    property string file
    property real size
    property color tint
    active: !!file
    source: file ? root.omarchyPath + "/shell/plugins/panels/" + file : ""
    onLoaded: {
      item.iconSize = Qt.binding(function () { return size })
      item.color = Qt.binding(function () { return tint })
    }
  }

  component Track: ShapePath {
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    PathAngleArc {
      centerX: root.ringBox / 2
      centerY: root.ringBox / 2
      radiusX: root.ringRadius
      radiusY: root.ringRadius
      startAngle: root.arcFrom
      sweepAngle: root.arcSpan
    }
  }

  PanelWindow {
    id: surface
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wheel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
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
      Keys.onPressed: function (event) {
        // One step at a time: the query, then the menu tree, then the screen.
        if (event.key === Qt.Key_Escape) {
          if (root.searching) root.query = ""
          else if (!root.up()) root.dismiss()
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Backspace) {
          if (root.searching) root.query = root.query.slice(0, -1)
          else root.up()
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.run(root.searching ? root.results[root.resultIndex] : root.slices[root.selected])
          event.accepted = true; return
        }
        if (root.searching) {
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.moveResult(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.moveResult(-1); event.accepted = true; return }
        } else {
          switch (event.key) {
          // Arrows alone reach the whole ring: up/down jump to the top and
          // bottom slice, left/right pick the side slice first and then step
          // around, so anything off a cardinal is a cardinal plus a few steps.
          // Found by bearing rather than fixed at 0/4/2/6 -- the ring is nine
          // slices by default and any count once it is configured.
          case Qt.Key_Up:       root.select(root.nearestSlice(0)); event.accepted = true; return
          case Qt.Key_Down:     root.select(root.nearestSlice(180)); event.accepted = true; return
          case Qt.Key_Right:    root.selected < 0 ? root.select(root.nearestSlice(90)) : root.rotate(1); event.accepted = true; return
          case Qt.Key_Left:     root.selected < 0 ? root.select(root.nearestSlice(270)) : root.rotate(-1); event.accepted = true; return
          case Qt.Key_Tab:      root.rotate(1); event.accepted = true; return
          case Qt.Key_Backtab:  root.rotate(-1); event.accepted = true; return
          }
        }
        // Anything else printable starts or extends the query.
        if (event.text && event.text.length === 1 && event.text >= " ") {
          root.query += event.text
          event.accepted = true
        }
      }
    }

    Item {
      anchors.fill: parent
      opacity: root.shown ? 1 : 0
      scale: root.shown ? 1 : 0.92
      Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

      // Ring and pill drawn once into a texture, so one effect pass shadows
      // the whole dial. Not a separate MultiEffect fed by `source`: that form
      // needs the source hidden, and a hidden layer does not reliably
      // re-render when its contents or geometry change.
      Item {
        anchors.centerIn: parent
        width: root.ringBox
        height: width
        layer.enabled: true
        layer.effect: MultiEffect {
          // The shadow reaches past the layer's bounds, and without this the
          // effect draws only inside them and clips its own falloff.
          autoPaddingEnabled: true
          shadowEnabled: true
          shadowColor: "#000000"
          shadowBlur: 1.0
          blurMax: 32
          shadowOpacity: 0.5
          shadowVerticalOffset: Style.space(5)
        }

        // Ring and results are the two modes, and they swap in the same
        // place: the ring while the query is empty, the list the moment
        // anything is typed. Both are placed off dead center, which is where
        // the field is, so the swap cannot move the field.
        Item {
          id: ring
          anchors.fill: parent
          // Traded for the card rather than switched off: the ring draws back
          // as the list comes forward. `visible` still follows the fade so a
          // ring at zero opacity stops being composited at all.
          opacity: root.searching ? 0 : 1
          scale: root.searching ? 0.94 : 1
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

          // The dial the discs sit on. Without a stroke through their centers
          // the eight read as scattered chips rather than one object.
          Rectangle {
            anchors.centerIn: parent
            width: root.ringRadius * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Style.spacing.hairline
            border.color: Util.alpha(Color.menu.text, 0.12)
          }

          // The comet. It rides the dial's own stroke rather than sitting
          // outside it, so what moves is the ring lighting up along its
          // length -- the wheel turning, not a marker sliding over it. The
          // under-glow goes down first, so the crisp arc sits in its own light.
          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // Nothing to point at until something is selected -- except during
            // the opening lap, which is the comet with nothing to point at yet.
            opacity: root.selected >= 0 || Math.abs(root.arcDrag) > 0.5 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

            Track { strokeWidth: Style.space(9); strokeColor: Util.alpha(root.cometColor, 0.16) }
            Track { strokeWidth: Style.space(3); strokeColor: root.cometColor }
          }

          Repeater {
            model: root.slices
            delegate: Item {
              id: slice
              required property int index
              required property var modelData
              readonly property bool active: root.selected === index
              // Where the streak is on this disc right now, and what that
              // does to its glyph: full accent while selected, and the
              // comet's hue washing over it as the trail crosses.
              readonly property real sweep: root.sweepAt(root.sliceAngle(index) - 90)
              readonly property color glyphColor: Qt.tint(Color.menu.text,
                Util.alpha(root.cometColor, active ? 1 : slice.sweep))
              // Tied to the disc rather than fixed: once the ring is full
              // enough that the discs have to shrink, a fixed icon would be the
              // thing that overflows them.
              readonly property real glyphSize: Style.font.displayLarge * root.itemSize / root.baseItem

              readonly property real angle: (root.sliceAngle(index) - 90) * Math.PI / 180
              x: ring.width / 2 + root.ringRadius * Math.cos(angle) - width / 2
              y: ring.height / 2 + root.ringRadius * Math.sin(angle) - height / 2
              width: root.itemSize
              height: root.itemSize

              BorderSurface {
                anchors.fill: parent
                // A dial of discs reads as one mechanism; the same eight as
                // rounded squares read as a grid arranged in a circle.
                radius: width / 2
                // A surface, not an outline: only a fill separates a slice
                // from the blurred desktop behind it.
                color: active
                  ? root.selectedFill
                  : root.surfaceFill
                // A full weight ring against everyone else's hairline, in
                // the comet's hue rather than the flat accent -- and every
                // unselected one takes that hue as the streak crosses it and
                // gives it back as the tail leaves.
                borderSpec: active
                  ? Border.flat(root.cometColor, Style.space(2))
                  : Border.flat(Qt.tint(root.surfaceEdge,
                                        Util.alpha(root.cometColor, slice.sweep * 0.9)),
                                Style.spacing.hairline)
                // Only the disc grows. Scaling the label with it would drift the
                // whole ring of text every time selection moved.
                scale: active ? root.selectedScale : 1

                Behavior on color { ColorAnimation { duration: 90 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                Text {
                  anchors.centerIn: parent
                  visible: !modelData.iconFile
                  text: modelData.icon
                  color: slice.glyphColor
                  font.family: Style.font.menuFamily
                  font.pixelSize: slice.glyphSize
                }
                // Tailscale's and Dropbox's marks are shapes Omarchy draws
                // itself, so there is no codepoint to set here.
                PanelIcon {
                  anchors.centerIn: parent
                  file: modelData.iconFile || ""
                  size: slice.glyphSize
                  tint: slice.glyphColor
                }
              }

              // Outside the disc rather than in it: a circle's usable width
              // collapses away from its center, and "Bluetooth" does not fit
              // under an icon in there. Pushed out along its own spoke rather
              // than hung straight down, because the dial's stroke runs
              // through every disc's center -- a label below the east or west
              // disc sits exactly on the arc's path and gets washed out as it
              // passes. Radially there is nothing for it to collide with, and
              // they read as one radiating set. Keeping the arc per slice
              // constant as the ring grows is what keeps neighbouring labels
              // off each other at any count.
              Text {
                // Measured to the box's nearest edge rather than its center,
                // so every label clears its disc by the same margin whatever
                // its width and whatever angle it sits at -- to the center,
                // a long label on a diagonal has its near corner back on top
                // of the disc.
                readonly property real reach: root.itemSize / 2 * root.selectedScale + root.labelGap
                  + (Math.abs(Math.cos(parent.angle)) * width
                     + Math.abs(Math.sin(parent.angle)) * height) / 2
                x: parent.width / 2 + reach * Math.cos(parent.angle) - width / 2
                y: parent.height / 2 + reach * Math.sin(parent.angle) - height / 2
                text: modelData.label
                color: active ? Color.accent : Color.menu.text
                // Labels name the icon rather than compete with it, so they sit
                // back until the slice is the one selected.
                opacity: active ? 1 : 0.6
                // The disc under it eases; without these the ring of text
                // strobes while the discs glide.
                Behavior on color { ColorAnimation { duration: 90 } }
                Behavior on opacity { NumberAnimation { duration: 90 } }
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // A drilled ring is otherwise anonymous -- twelve discs that could be
        // Install's or Remove's. The chevron points at the way out: backspace.
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

        // Dead center, fixed size, anchored to nothing that changes: the field
        // is the one thing that must not move between the two modes.
        BorderSurface {
          anchors.centerIn: parent
          width: root.searchWidth
          height: root.searchHeight
          radius: height / 2
          // Filled and edged like the discs: the hub is part of the wheel, and
          // an unfilled pill over blurred desktop reads as a gap in it.
          color: root.surfaceFill
          borderSpec: Border.flat(root.searching ? Color.accent : root.surfaceEdge,
                                  Style.spacing.hairline)

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.spacing.rowPaddingX * 2
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.searching ? root.query + "▏" : "Search"
            color: Color.menu.text
            opacity: root.searching ? 1 : 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
          }
        }
      }

      // Results get the same card the Omarchy menu gives its own list, so the
      // wheel's search mode looks like the rest of the shell rather than rows
      // laid straight onto the desktop.
      BorderSurface {
        // Off the surface's center rather than the pill's edge: the pill is
        // inside the dial's layer, and anchors don't cross between parents.
        // Dead center is where the pill sits by construction.
        anchors.top: parent.verticalCenter
        anchors.topMargin: root.searchHeight / 2 + Style.spacing.panelGap
        anchors.horizontalCenter: parent.horizontalCenter
        // Grown from its top edge, which is pinned just under the pill, so the
        // card reads as unrolling out of the field rather than swelling from
        // its own middle. Rows carry MouseAreas, so a faded card must go
        // properly invisible or it keeps catching clicks over the ring.
        transformOrigin: Item.Top
        opacity: root.searching ? 1 : 0
        scale: root.searching ? 1 : 0.96
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }
        width: resultList.width + Style.spacing.popupPadding * 2
        height: resultList.height + Style.spacing.popupPadding * 2
        radius: Style.cornerRadius
        // The same fill and hairline the discs wear. The Omarchy menu's own
        // 2px full-strength border is louder than anything on the ring, and
        // wearing it made search mode look like a different surface.
        color: root.surfaceFill
        borderSpec: Border.flat(root.surfaceEdge, Style.spacing.hairline)
        // The card resizes with every query, so its shadow has to come from
        // the card itself or it draws at a stale size. Layering does not block
        // the rows' mouse input -- it only changes how they are painted.
        layer.enabled: true
        layer.effect: MultiEffect {
          autoPaddingEnabled: true
          shadowEnabled: true
          shadowColor: "#000000"
          shadowBlur: 1.0
          // Tighter than the dial's. The discs are small enough to carry a
          // wide falloff; on a card this size the same one hangs off the
          // bottom edge as a skirt rather than reading as depth.
          blurMax: 16
          shadowOpacity: 0.4
          shadowVerticalOffset: Style.space(3)
        }

        Column {
          id: resultList
          anchors.centerIn: parent
          width: root.searchWidth
          spacing: Style.spacing.hairline

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.results.length === 0
            text: "No match"
            color: Color.menu.text
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.results
            delegate: BorderSurface {
              id: resultCard
              required property int index
              required property var modelData
              readonly property bool active: root.resultIndex === index

              width: root.searchWidth
              height: Style.spacing.popupRowHeight + Style.spacing.controlPaddingY * 2
              radius: Style.cornerRadius
              // The same accent tint and ring a selected disc wears, so the
              // two modes highlight the current thing the same way.
              color: active
                ? root.selectedFill
                : "transparent"
              borderSpec: active
                ? Border.flat(Color.accent, Style.spacing.hairline)
                : Border.none()

              Behavior on color { ColorAnimation { duration: 90 } }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.resultIndex = index
                onClicked: root.run(root.results[index])
              }

              Row {
                id: resultRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.rowPaddingX
                spacing: Style.spacing.controlGap

                // What the label and the breadcrumb share, once the icon and
                // the two gaps are paid for. A window title is arbitrary text --
                // a terminal's is a whole command line -- so without a budget
                // one row draws straight through the edge of the card.
                readonly property real textBudget:
                  Math.max(0, width - Style.font.iconLarge - spacing * 2 - chevron.width)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !modelData.appIcon && !modelData.iconFile
                  width: Style.font.iconLarge
                  text: modelData.icon
                  color: active ? Color.accent : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.iconLarge
                }
                // The same marks the ring loads, at row size.
                PanelIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.iconLarge
                  file: modelData.iconFile || ""
                  size: Style.font.iconLarge
                  tint: resultCard.active ? Color.accent : Color.menu.text
                }
                // Apps and windows name an icon file rather than carrying a
                // glyph. Only one of the two is ever visible, and a Row skips
                // what isn't.
                Image {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!modelData.appIcon
                  width: Style.font.iconLarge
                  height: Style.font.iconLarge
                  source: modelData.appIcon ? root.appLibrary.iconSource(modelData.appIcon) : ""
                  sourceSize.width: Style.font.iconLarge
                  sourceSize.height: Style.font.iconLarge
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                }
                Text {
                  id: labelText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, resultRow.textBudget - trailText.width)
                  elide: Text.ElideRight
                  text: modelData.label
                  color: active ? Color.accent : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  id: trailText
                  anchors.verticalCenter: parent.verticalCenter
                  // Whatever the label leaves, but never squeezed below a share
                  // of its own -- a breadcrumb that elides to nothing is noise.
                  width: Math.min(implicitWidth,
                                  Math.max(resultRow.textBudget * 0.4,
                                           resultRow.textBudget - labelText.implicitWidth))
                  text: modelData.trail
                  color: Color.menu.text
                  opacity: 0.45
                  elide: Text.ElideRight
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }
                // A category is not a command: picking it turns the ring into
                // its contents. The chevron is what says so before Return.
                Text {
                  id: chevron
                  anchors.verticalCenter: parent.verticalCenter
                  width: modelData.node ? implicitWidth + parent.spacing : 0
                  visible: !!modelData.node
                  text: "\u203a"
                  color: active ? Color.accent : Color.menu.text
                  opacity: 0.5
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
