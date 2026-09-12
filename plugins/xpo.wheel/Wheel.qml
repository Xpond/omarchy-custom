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
import "MenuKeys.js" as MenuKeys

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
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  property bool shown: false
  // Selection stays disarmed until the pointer or a key actually moves, so a
  // bare tap never fires whichever slice the cursor happened to point at when
  // the surface mapped.
  property bool armed: false
  property bool justOpened: false
  property int selected: -1
  // The panel the last pick put on screen, and so the one whose backspace is a
  // step back to here rather than a key the panel keeps.
  property string launched: ""
  // Which slice made that pick. `open()` clears the selection, which is right
  // for a fresh summon and wrong for a step back -- backspace should hand the
  // ring back the way it was left, close enough to carry on with the arrows.
  // A home-ring index: `plugin` lives only on the ring catalogue, so the home
  // ring is the only one a panel can be launched from, and the only one
  // `open()` can come back to.
  property int launchedAt: -1

  property string query: ""
  // Where the next character goes. Clamped on every query change, so clearing
  // the query anywhere carries the caret home without saying so.
  property int queryAt: 0
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
  // EXTRAS is searchable but off the ring, so the search index is the ring's
  // panels plus ours -- see MenuIndex.EXTRAS for why the two lists differ.
  readonly property var staticRows: MenuIndex.panelRows(root.panels.concat(MenuIndex.EXTRAS))
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
  // How often each row has been picked, by MenuIndex.keyOf. A plain count with
  // no decay: what you reach for through a wheel is stable for months, and a
  // half-life is a second tuning knob to be wrong about.
  property var uses: ({})
  // A leading sigil aims the query at one source instead of at the whole
  // index. Everything downstream reads `term` rather than `query`, so a mode's
  // sigil is stripped in exactly one place.
  readonly property string mode: MenuIndex.modeOf(root.query)
  readonly property string term: MenuIndex.termOf(root.query)
  // Paths under $HOME for file mode. Null until something asks for them, and
  // null again the moment the wheel is down: six megabytes of strings is worth
  // holding while a query is being typed against them and not a second longer,
  // and what is on disk is exactly the thing that changes between two presses
  // of the keybind.
  property var files: null
  // How deep the ranked list goes, and how many of it stands under the field at
  // once. Both searches scan the whole index and sort every hit before they
  // truncate, so a deeper list costs only the rows themselves -- what the cap
  // buys is a stack that still fits in the hole.
  readonly property int resultLimit: 40
  readonly property int resultCap: 8
  readonly property var results: root.mode === "file"
    ? MenuIndex.fileRows(root.files, root.term, root.resultLimit, root.home)
    : MenuIndex.search(root.index, root.term, root.resultLimit, root.uses)
  property int resultIndex: 0
  // The first row standing under the field. The stack is a window onto the
  // list rather than the list itself, so arrowing past the eighth row scrolls
  // by one instead of stopping there.
  property int resultTop: 0
  readonly property var beads: root.results.slice(root.resultTop,
                                                  root.resultTop + root.resultCap)
  readonly property bool searching: root.query.length > 0

  // Hover may only claim the selection when the cursor has genuinely moved.
  // Qt synthesises a hover move whenever an item's geometry changes beneath a
  // stationary pointer, so `entered` and `positionChanged` both fire as a list
  // re-lays out while you type -- handing the selection to whichever row
  // happened to slide under the cursor, mid-keystroke, with the keyboard
  // fighting it for the rest of the query. Scene coordinates, not the row's
  // own: a row moving under a still pointer must read as no movement at all.
  property point hoverAt: Qt.point(-1, -1)
  function hoverMoved(pt) {
    if (root.hoverAt.x === pt.x && root.hoverAt.y === pt.y) return false
    root.hoverAt = pt
    return true
  }
  // File mode has two more ways to be empty than the index does: the walk has
  // not landed yet, or nothing has been typed after the sigil.
  readonly property string emptyText: root.mode !== "file" ? "No match"
    : !root.files ? "Scanning\u2026"
    : !root.term ? "Type to find files"
    : "No match"

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
  readonly property int searchHeight: Style.spacing.controlHeight + Style.spacing.controlPaddingY * 2
  // A size down from the field, in both directions. Beads cut to the pill's
  // own measurements read as a stack of identical fields, and nothing in the
  // picture says which of them you are typing into -- the field has to stay
  // the largest thing in the hole.
  readonly property int resultWidth: root.searchWidth - Style.space(28)
  readonly property int resultHeight: Style.spacing.popupRowHeight + Style.spacing.xs * 2

  // Input followers determine selection, trail length and disc illumination.
  // Keep angles unwrapped so crossing north continues in the same direction.
  // RingTrack gives the visible head a slower clock during sustained spin.
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
  // Bound follower separation for disc illumination. The visible trail has
  // its own shorter limit and follows RingTrack's clock during sustained spin.
  readonly property real arcDrag: Math.max(-300, Math.min(300, root.arcHead - root.arcTail))
  // Keep a third of the ring clear at speed, trimming the tail rather than the head.
  readonly property real arcFrom: root.arcDrag >= 0 ? root.arcHead + root.arcSpread - root.arcSpan : root.arcHead - root.arcSpread
  readonly property real arcSpan: Math.min(240, Math.abs(root.arcDrag) + root.arcSpread * 2)
  // How hard the ring is being turned, 0 at rest and 1 saturated. Every step
  // adds a bite and the bleed takes it back out faster than a person can
  // press: stepping by hand never accumulates, while an arrow held at the
  // 40Hz key-repeat rate fills it in about a quarter second and a release
  // empties it in half of one. Charge drives hue, trail length and the
  // transition from individual selection highlights to sustained spin.
  property real charge: 0

  // How long the ring has been held at speed. The comet has to answer the
  // first keypress, but the mark being drawn is a reward for a real spin
  // rather than a flick, so this runs on its own much slower clock: a couple
  // of seconds of spinning to fill, under one to drain.
  property real hold: 0

  // Interpolate the visible tip without changing the timer's accumulation.
  property real markReveal: root.hold * 1.05
  Behavior on markReveal { NumberAnimation { duration: 40 } }

  // Continue from the drawing tip once it reaches the end. Pause the runner
  // during drawing and draining, retaining its position if spinning resumes.
  property real markPhase: 0
  NumberAnimation on markPhase {
    running: root.markReveal > 0
    paused: running && root.markReveal < 1.05
    loops: Animation.Infinite
    from: 0; to: 1
    duration: 1400
  }

  // How far round the color wheel this spin has travelled. A fixed offset per
  // charge arrives at one color and sits there, which is what a long hold
  // looked like: this keeps moving for as long as the ring is being turned,
  // about half a rotation of hue per second at the key-repeat rate.
  property real huePhase: 0

  // Shared sky/fluid clock: about 7s per day at full spin. It runs through
  // the release fade, pauses once hold drains, and resets on close.
  // Never wrap it: interpolation across midnight must keep moving forward.
  property real daylight: 0
  // Smooth the timer's 40ms steps, as with markReveal.
  Behavior on daylight { NumberAnimation { duration: 40 } }

  // Charge and hold decay together; the hue resets when charge runs out. Also
  // the clock the sky keeps, which is why an idle wheel has no day running.
  Timer {
    interval: 40
    repeat: true
    running: root.charge > 0 || root.hold > 0
    onTriggered: {
      root.charge = Math.max(0, root.charge - 0.09)
      // Only a ring already at speed fills the hold.
      root.hold = root.charge > 0.9
        ? Math.min(1, root.hold + 0.018)
        : Math.max(0, root.hold - 0.045)
      // Back to the theme's own accent once the ring has stopped, so the next
      // spin starts from it rather than from wherever the last one ended.
      if (root.charge <= 0) root.huePhase = 0
      root.daylight += 0.0012 + 0.0045 * root.charge
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
    // Pulled toward a bright, coloured palette as the spin builds: a near-white
    // or near-black accent has nowhere to put chroma, and a grey one has none
    // to rotate in the first place.
    // At `amount` 0 both are the accent's own, so a ring at rest is exactly
    // the theme's color and winds back to it as the spin bleeds out.
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

  // Disc illumination follows the input head, easing to zero at both ends.
  // WheelRing smooths these passes into a shared glow at sustained speed.
  function sweepAt(deg) {
    // Clear the sweep at rest: the opening lap must not leave a disc looking
    // selected when Enter would do nothing. Selection has its own emphasis.
    var moving = Math.min(1, Math.abs(root.arcDrag) / root.arcSpread)
    if (moving <= 0) return 0
    var span = Math.abs(root.arcDrag) + root.arcSpread
    // Wrap ahead of the leading edge, where light is zero: wrapping at 180
    // cuts a long tail off halfway around the ring.
    var offset = (root.arcHead - deg) * (root.arcDrag >= 0 ? 1 : -1)
    var behind = ((offset + root.arcSpread) % 360 + 360) % 360 - root.arcSpread
    if (behind > span) return 0
    var rise = Math.min(1, (behind + root.arcSpread) / root.arcSpread)
    var fall = 1 - Math.max(0, behind) / span
    return moving * rise * rise * (3 - 2 * rise) * fall * fall * (3 - 2 * fall)
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
  // Resolved once per open and held while the wheel is up: Hyprland moves
  // focus with the pointer, and the compass reads the whole screen, so a live
  // binding would re-map the surface onto another monitor mid-flick. By name,
  // because this Quickshell's HyprlandMonitor carries no `screen` of its own.
  property var openScreen: null
  function focusedScreen() {
    var m = Hyprland.focusedMonitor
    if (!m) return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === m.name) return screens[i]
    return null
  }

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
    root.launched = ""
    root.launchedAt = -1
    // Only a press that actually opened the wheel earns the tap-to-hold grace;
    // a press onto an already-open wheel is the second tap, which closes it.
    root.justOpened = !wasOpen
    root.openScreen = root.focusedScreen()
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
    // Overlays no slice points at, so the loop above never sees them: the bar's
    // own menu widget, and the four reached through a menu action, which the
    // wheel dismisses itself to open. Nothing else knows they are up, so
    // without this SUPER+W answers "none" and the wrapper falls through to
    // killactive -- closing the window behind the overlay.
    var summoned = ["omarchy.menu", "omarchy.emojis", "omarchy.speedtest",
                    "omarchy.disk-speedtest", "omarchy.wifiqr", "xpo.files"]
    for (var j = 0; j < summoned.length; j++)
      if (root.shell.isPluginOpen(summoned[j])) { root.shell.hide(summoned[j]); acted = true }
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

  // Backspace in a panel, answered for the panel: a panel is reached by the same
  // call from the bar's own button and from a slice, so it cannot tell which
  // one opened it. Only a panel this wheel opened, and that is still on screen,
  // earns a return -- anything else keeps the key and it does what it always
  // did there, which is nothing.
  function back() {
    if (!root.launched || !root.shell || !root.shell.isPluginOpen(root.launched)) return "none"
    // Read before the summon: `open()` clears it on its way through.
    var at = root.launchedAt
    root.shell.hide(root.launched)
    // The same handoff run() makes, the other way round: the panel's layer
    // surface has to let the keyboard go before this one asks for it.
    Qt.callLater(function () {
      root.shell.summon(root.pluginId, "{}")
      // Bounded rather than trusted: wheel.json is watched, so the ring can be
      // shorter than it was when the panel went up.
      if (at >= 0 && at < root.sliceCount) root.select(at)
    })
    return "wheel"
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
    root.countUse(e)
    if (e.node) { root.enter(e.node); return }
    // Taken before the dismiss, and off `slices` rather than off `selected`,
    // so a picked-by-pointer slice is recorded the same as a picked-by-arrow
    // one. A search result is on no ring and gets -1, which asks for nothing.
    root.launchedAt = root.slices.indexOf(e)
    root.dismiss(true)
    // Let this layer surface unmap and hand the keyboard back before the
    // target grabs it, or the panel opens without focus.
    Qt.callLater(function () {
      if (e.plugin && root.shell) { root.shell.toggle(e.plugin, "{}"); root.launched = e.plugin }
      // Omarchy 4 configures Hyprland in Lua, and its dispatcher rejects the
      // legacy string form -- which is what both Quickshell's own activate()
      // and `hyprctl dispatch focuswindow` send, silently doing nothing.
      else if (e.address) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + e.address + "\" })")
      else if (e.appId) root.appLibrary.launch(e.appId, e.label)
      // A path opens the browser where the path lives rather than launching
      // anything: picking `main.py` out of the wheel used to drop an editor on
      // the screen, and what you wanted was to see the file and where it sits.
      else if (e.path && root.shell) {
        root.shell.summon("xpo.files", MenuIndex.pathPayload(e.path))
        root.launched = "xpo.files"
      }
      else if (e.action) Util.execDetached(e.action)
    })
  }

  // Written through on every pick rather than batched at close: the wheel is
  // never shut down in an orderly way -- it is a plugin in a shell that gets
  // restarted -- so there is no later moment guaranteed to arrive. A new
  // object rather than a mutation, because QML re-evaluates `results` off the
  // property changing, not off what it points at changing.
  function countUse(e) {
    var key = MenuIndex.keyOf(e)
    if (!key) return
    var bump = {}
    bump[key] = (root.uses[key] || 0) + 1
    root.uses = MenuIndex.merge(root.uses, bump)
    usesFile.setText(JSON.stringify(root.uses) + "\n")
  }

  // Typing and pasting are the same act at two lengths. The caret's landing
  // place is worked out before the query moves: assigning it first fires the
  // clamp in onQueryChanged, which would eat the step.
  function insert(text) {
    if (!text) return
    var at = root.queryAt + text.length
    root.query = root.query.slice(0, root.queryAt) + text + root.query.slice(root.queryAt)
    root.queryAt = at
  }

  // The field is one line and a clipboard is not: a pasted path or error
  // message arrives with newlines and runs, which would draw straight through
  // the pill.
  function paste() {
    root.insert(String(Quickshell.clipboardText || "").replace(/\s+/g, " ").trim())
  }

  // A path is worth taking away as well as opening. Nothing here can report a
  // clipboard failure once the wheel is down, so it goes the way every other
  // verb does: pick, act, leave. False when the highlighted row is not a path.
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

  // Scrolls by the single row that just went past an edge, and jumps outright
  // when the selection wraps around an end. Clamped last so a list shorter
  // than the window -- or one that shrank under a standing selection -- can
  // never leave the stack showing blank rows below its final bead.
  function showResult() {
    var top = Math.min(root.resultTop, root.resultIndex)
    top = Math.max(top, root.resultIndex - root.resultCap + 1)
    root.resultTop = Math.max(0, Math.min(top, root.results.length - root.resultCap))
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
    // An empty ring has nowhere to step to, and the modulo below would make
    // the selection NaN rather than leave it alone.
    if (!n) return
    root.charge = Math.min(1, root.charge + 0.16)
    root.huePhase += 0.012
    // Nothing selected yet is not nowhere: the ring opens resting at the top,
    // which is the slice the first step comes off. Landing on a cardinal
    // instead skipped whatever sat between it and the top -- one press of
    // right off a fresh wheel arrived two slices along. Asked by bearing so it
    // names the same slice Up does; that is index 0 for every count the origin
    // formula produces today, and stays right if the origin ever moves.
    var from = root.selected < 0 ? root.nearestSlice(0) : root.selected
    root.select((from + step + n) % n)
  }

  onQueryChanged: {
    root.resultIndex = 0; root.resultTop = 0
    root.queryAt = Math.min(root.queryAt, root.query.length)
  }

  // The browser's carets blink at 530ms and say in a comment that the point is
  // one beat everywhere. Relit on every move so a keystroke is never swallowed
  // by the dark half of it.
  property bool caretLit: true
  Timer {
    running: root.opened && root.searching
    interval: 530
    repeat: true
    onTriggered: root.caretLit = !root.caretLit
    onRunningChanged: root.caretLit = true
  }
  onQueryAtChanged: root.caretLit = true
  // The index is rebuilt when the late condition scan lands, which can shorten
  // the list under a standing selection without the query having changed.
  onResultsChanged: {
    if (root.resultIndex >= root.results.length) root.resultIndex = 0
    root.showResult()
  }

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

  // Walked only by someone who asks for it -- nothing scans until a query is
  // aimed at files -- and the answer is held for that one open. Unlike themes
  // and fonts, what is on disk is not a rare deliberate act, so the scan
  // cannot be done once at startup.
  //
  // Depth 6 rather than the whole tree. Below it lie 200,000 entries of
  // .gradle, Android SDK and browser caches, which is not what anyone reaches
  // a launcher for, and walking down to them takes the scan from 99ms to 1.2s.
  Process {
    id: fileScan
    command: ["fd", "--hidden", "--max-depth", "6", "--exclude", ".cache",
              "--exclude", ".git", "--exclude", "node_modules", ".", root.home]
    property int epoch: 0
    // A killed scan still finishes its stream, with a partial walk that would
    // read as the whole of $HOME. Only the scan this epoch asked for counts.
    stdout: StdioCollector {
      onStreamFinished: if (fileScan.epoch === root.scanEpoch) root.files = MenuIndex.parseFiles(text)
    }
    onExited: if (epoch !== root.scanEpoch) Qt.callLater(root.scanFiles)
  }

  // Started by hand for the same reason conditionScan is: `running` bound to
  // the mode would restart the walk on every keystroke that keeps it.
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
    // Reset on close, after the scene has faded; charge can end before hold.
    root.daylight = 0
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

  // Beside the shell's own state rather than in the config: this is something
  // the wheel learns, not something the user writes.
  FileView {
    id: usesFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/wheel-uses.json"
    atomicWrites: true
    printErrors: false
    onLoaded: root.uses = MenuIndex.parse(text())
    onLoadFailed: root.uses = ({})
  }

  // The ring, if the user has said what they want on it. Absent by default.
  FileView {
    printErrors: false
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

    // The wash and the blur behind this surface belong to the bar's scrim, not
    // to this surface. A scrim drawn here unmaps when the surface does and
    // takes Hyprland's blur with it, so for the frames between this going and
    // whatever replaces it arriving, the desktop snaps sharp. The bar owns one
    // wash for exactly that reason; this just holds a count on it, and the next
    // surface takes its own before this one is let go.
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

    // The stock mark's centrelines surround the wheel without changing its
    // design. R stores path distance, GB the bevel normal, alpha the stroke mask.
    Image {
      id: logoMask
      // Rebuild with scripts/generate-mark.py; see docs/wheel.md.
      source: Qt.resolvedUrl("mark.png")
      // Used only as a shader texture, with the comet supplying its colour.
      visible: false
    }

    ShaderEffect {
      anchors.centerIn: parent
      // The outer stroke is 0.47 from centre; leave 2% of the height clear.
      width: surface.height / (2 * 0.47) * 0.98
      height: width
      visible: root.hold > 0
      fragmentShader: Qt.resolvedUrl("logo.frag.qsb")
      // Match the wheel's diffuse shadow.
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
      // Interpolated progress followed by a runner continuing along the path.
      readonly property real reveal: root.markReveal
      readonly property real feather: 0.02
      // Drawing and looping use slightly different tail lengths.
      readonly property real head: 0.10
      readonly property real phase: root.markReveal + root.markPhase
      readonly property real pulse: 0.12
      readonly property vector2d pixel: Qt.vector2d(1 / width, 1 / height)
      // Lit by the day it is standing in, rather than by a fixed corner.
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
      // A wheel you cannot turn with the wheel. One notch is one step, the
      // same as one arrow press, so it feeds `charge` at the rate a hand can
      // scroll and never accumulates into the held-arrow streak.
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
        WheelRing { wheel: root }

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

          ClickShield {}

          // Two halves with the caret between them, the shape FilesHeader's
          // chip already has. A glyph inside one Text could not blink without
          // the line jumping as it went.
          Row {
            id: field
            anchors.centerIn: parent
            spacing: 0
            opacity: root.searching ? 1 : 0.45
            readonly property real budget: root.searchWidth - Style.spacing.rowPaddingX * 2

            Text {
              anchors.verticalCenter: parent.verticalCenter
              // The end being typed is the end worth keeping, so a query past
              // the pill loses its start.
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

      // Search mode is the ring unrolled. The results wear the disc's own
      // fill, hairline and capsule, and stand on the scrim the same way -- no
      // card behind them, because a box under a dial of discs is a second
      // surface language, and the jump between the two is exactly what the
      // wheel's geometry was there to avoid.
      WheelResults { wheel: root }
    }
  }
}
