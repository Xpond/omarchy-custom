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
  readonly property var menuRows: MenuIndex.menuRows(root.menuItems, root.slices)
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

  // Clockwise from north. `plugin` routes through the shell and lands in the
  // centered panels; `exec` covers the targets that aren't shell plugins.
  readonly property var slices: [
    { icon: "󰕾", label: "Audio",     plugin: "omarchy.audio" },
    { icon: "󰂯", label: "Bluetooth", plugin: "omarchy.bluetooth" },
    { icon: "", label: "System",    exec: ["omarchy-menu", "toggle", "system"] },
    { icon: "", label: "Clipboard", plugin: "omarchy.clipboard" },
    { icon: "󰍜", label: "Menu",      exec: ["omarchy-menu", "toggle", "root"] },
    { icon: "󰃭", label: "Calendar",  plugin: "omarchy.clock" },
    { icon: "󰍹", label: "Display",   plugin: "omarchy.monitor" },
    { icon: "󰖩", label: "Network",   plugin: "omarchy.network" }
  ]

  readonly property int ringRadius: Style.space(240)
  readonly property int itemSize: Style.space(76)
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
  property real arcHead: root.arcTarget
  Behavior on arcHead { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
  property real arcTail: root.arcTarget
  Behavior on arcTail { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
  // Half the arc at rest. The discs are painted over the dial, so anything no
  // wider than one hides behind it; half a slice's share of the ring, less a
  // hair, lights the dial on either side of the selected disc instead.
  readonly property real arcSpread: 360 / root.slices.length / 2 * 0.85
  // Clamped: a held arrow drags the tail more than a lap behind, and an arc
  // past a full turn is just the circle again -- it stops reading as motion.
  // Clamping from the head keeps the point and loses the far end of the tail.
  readonly property real arcDrag: Math.max(-300, Math.min(300, root.arcHead - root.arcTail))
  readonly property real arcFrom: Math.min(root.arcHead, root.arcHead - root.arcDrag) - root.arcSpread
  readonly property real arcSpan: Math.abs(root.arcDrag) + root.arcSpread * 2
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
      root.arcTarget += 45
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
    root.index = root.menuRows.concat(MenuIndex.liveRows({
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
    // Only a press that actually opened the wheel earns the tap-to-hold grace;
    // a press onto an already-open wheel is the second tap, which closes it.
    root.justOpened = !wasOpen
    root.opened = true
    root.rebuildIndex()
    spin.stepsLeft = root.slices.length
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
    for (var i = 0; i < root.slices.length; i++) {
      var id = root.slices[i].plugin
      if (id && root.shell.isPluginOpen(id)) { root.shell.hide(id); acted = true }
    }
    // The exec slices route through omarchy-menu, which is a shell plugin of
    // its own -- closing the wheel's menu means closing that too.
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
      root.activate(root.selected)
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
    var slice = i * 45 - 90
    root.arcTarget += ((slice - root.arcTarget) % 360 + 540) % 360 - 180
  }

  function activate(i) {
    if (i < 0 || i >= root.slices.length) return
    var s = root.slices[i]
    root.dismiss(true)
    // Let this layer surface unmap and hand the keyboard back before the
    // target grabs it, or the panel opens without focus.
    Qt.callLater(function () {
      if (s.plugin && root.shell) root.shell.toggle(s.plugin, "{}")
      else if (s.exec) Quickshell.execDetached(s.exec)
    })
  }

  function runResult(i) {
    var r = root.results[i]
    if (!r) return
    if (r.slice >= 0) { root.activate(r.slice); return }
    root.dismiss(true)
    Qt.callLater(function () {
      // Omarchy 4 configures Hyprland in Lua, and its dispatcher rejects the
      // legacy string form -- which is what both Quickshell's own activate()
      // and `hyprctl dispatch focuswindow` send, silently doing nothing.
      if (r.address) Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + r.address + "\" })")
      else if (r.appId) root.appLibrary.launch(r.appId, r.label)
      else Util.execDetached(r.action)
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
    return Math.floor(((deg + 22.5) % 360) / 45)
  }

  function rotate(step) {
    var n = root.slices.length
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
        i >= 0 ? root.activate(i) : root.dismiss()
      }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) {
          root.searching ? root.query = "" : root.dismiss()
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Backspace) {
          root.query = root.query.slice(0, -1)
          event.accepted = true; return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.searching ? root.runResult(root.resultIndex) : root.activate(root.selected)
          event.accepted = true; return
        }
        if (root.searching) {
          if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.moveResult(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.moveResult(-1); event.accepted = true; return }
        } else {
          switch (event.key) {
          // Arrows alone reach all eight: up/down jump to the top and bottom
          // slice, left/right pick the side slice first and then step around
          // the ring, so a diagonal is a cardinal plus one step.
          case Qt.Key_Up:       root.select(0); event.accepted = true; return
          case Qt.Key_Down:     root.select(4); event.accepted = true; return
          case Qt.Key_Right:    root.selected < 0 ? root.select(2) : root.rotate(1); event.accepted = true; return
          case Qt.Key_Left:     root.selected < 0 ? root.select(6) : root.rotate(-1); event.accepted = true; return
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

            Track { strokeWidth: Style.space(9); strokeColor: Util.alpha(Color.accent, 0.16) }
            Track { strokeWidth: Style.space(3); strokeColor: Color.accent }
          }

          Repeater {
            model: root.slices
            delegate: Item {
              required property int index
              required property var modelData
              readonly property bool active: root.selected === index

              readonly property real angle: (index * 45 - 90) * Math.PI / 180
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
                // A full-weight accent ring against everyone else's hairline.
                borderSpec: active
                  ? Border.flat(Color.accent, Style.space(2))
                  : Border.flat(root.surfaceEdge, Style.spacing.hairline)
                // Only the disc grows. Scaling the label with it would drift the
                // whole ring of text every time selection moved.
                scale: active ? root.selectedScale : 1

                Behavior on color { ColorAnimation { duration: 90 } }
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                Text {
                  anchors.centerIn: parent
                  text: modelData.icon
                  color: active ? Color.accent : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.displayLarge
                }
              }

              // Outside the disc rather than in it: a circle's usable width
              // collapses away from its center, and "Bluetooth" does not fit
              // under an icon in there. Pushed out along its own spoke rather
              // than hung straight down, because the dial's stroke runs
              // through every disc's center -- a label below the east or west
              // disc sits exactly on the arc's path and gets washed out as it
              // passes. Radially there is nothing for it to collide with, and
              // the eight read as one radiating set. At 45 degrees apart
              // neighbouring labels are nowhere near each other.
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
                onClicked: root.runResult(index)
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
                  Math.max(0, width - Style.font.iconLarge - spacing * 2)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !modelData.appIcon
                  width: Style.font.iconLarge
                  text: modelData.icon
                  color: active ? Color.accent : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.iconLarge
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
              }
            }
          }
        }
      }
    }
  }
}
