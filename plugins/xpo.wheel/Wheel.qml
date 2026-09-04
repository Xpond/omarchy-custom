import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
    { icon: "",  label: "System",    exec: ["omarchy-menu", "toggle", "system"] },
    { icon: "",  label: "Clipboard", plugin: "omarchy.clipboard" },
    { icon: "󰍜", label: "Menu",      exec: ["omarchy-menu", "toggle", "root"] },
    { icon: "󰃭", label: "Calendar",  plugin: "omarchy.clock" },
    { icon: "󰍹", label: "Display",   plugin: "omarchy.monitor" },
    { icon: "󰖩", label: "Network",   plugin: "omarchy.network" }
  ]

  readonly property int ringRadius: Style.space(240)
  readonly property int itemSize: Style.space(76)
  readonly property int deadzone: Style.space(54)
  // The field lives in the ring's hole, so its width is the hole's: that is
  // the room the wheel makes for it, and deriving it means the field can never
  // reach under the east and west slices when either size is retuned.
  // Sized to leave real air inside the hole rather than filling it edge to
  // edge, but still clamped to the hole so it can never reach under the east
  // and west slices if either size is retuned.
  readonly property int searchWidth: Math.min(Style.space(280),
    (root.ringRadius - root.itemSize / 2) * 2 - Style.space(48))
  // The pointer-enter that arrives when the surface maps is a synthetic move,
  // so the first sample is kept as an origin and the wheel only arms once the
  // pointer has travelled past this from it.
  readonly property int moveThreshold: Style.space(8)
  property real originX: -1
  property real originY: -1
  readonly property string pluginId: (manifest && manifest.id) || "xpo.wheel"

  // Applications come from the shell's own library rather than a .desktop scan
  // of our own: it sorts, drops hidden entries, resolves icon names, and
  // launches through uwsm so an app doesn't inherit the compositor's scope.
  function rebuildIndex() {
    root.index = MenuIndex.build(root.menuItems, root.slices,
                                 root.appLibrary ? root.appLibrary.sortedEntries("") : [])
  }

  function open(payloadJson) {
    var wasOpen = root.opened
    root.selected = -1
    root.armed = false
    root.originX = -1
    root.query = ""
    // Only a press that actually opened the wheel earns the tap-to-hold grace;
    // a press onto an already-open wheel is the second tap, which closes it.
    root.justOpened = !wasOpen
    root.opened = true
    Qt.callLater(function () { root.shown = true; keys.forceActiveFocus() })
  }

  function close() { root.opened = false; root.shown = false }

  function dismiss() {
    root.close()
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

  function select(i) { root.armed = true; root.selected = i }

  function activate(i) {
    if (i < 0 || i >= root.slices.length) return
    var s = root.slices[i]
    root.dismiss()
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
    root.dismiss()
    Qt.callLater(function () {
      if (r.appId) root.appLibrary.launch(r.appId, r.label)
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
  // The shell is injected after this component loads, so the first app list
  // has to wait for it; afterwards the library tells us when apps change.
  onAppLibraryChanged: root.rebuildIndex()

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.rebuildIndex() }
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
    onLoaded: {
      root.menuItems = MenuIndex.merge(MenuIndex.parse(text()), root.menuItems)
      root.rebuildIndex()
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    onLoaded: {
      root.menuItems = MenuIndex.merge(root.menuItems, MenuIndex.parse(text()))
      root.rebuildIndex()
    }
  }

  PanelWindow {
    id: surface
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wheel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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
      Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

      // Ring and results are the two modes, and they swap in the same place:
      // the ring while the query is empty, the list the moment anything is
      // typed. Both are positioned off the field rather than stacked with it,
      // so the swap cannot move the field.
      Item {
        id: ring
        anchors.centerIn: parent
        visible: !root.searching
        width: (root.ringRadius + root.itemSize) * 2
        height: width

        Repeater {
          model: root.slices
          delegate: CursorSurface {
            required property int index
            required property var modelData

            readonly property real angle: (index * 45 - 90) * Math.PI / 180
            x: ring.width / 2 + root.ringRadius * Math.cos(angle) - width / 2
            y: ring.height / 2 + root.ringRadius * Math.sin(angle) - height / 2
            width: root.itemSize
            height: root.itemSize
            radius: Style.cornerRadius
            hasCursor: root.selected === index
            foreground: Color.menu.text
            bordered: true

            Column {
              anchors.centerIn: parent
              spacing: Style.spacing.sm
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.icon
                color: root.selected === index ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.display
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: root.selected === index ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // Dead center, fixed size, anchored to nothing that changes: the field
      // is the one thing that must not move between the two modes.
      BorderSurface {
        id: searchBox
        anchors.centerIn: parent
        width: root.searchWidth
        height: Style.spacing.controlHeight + Style.spacing.controlPaddingY * 2
        // A pill on the same 1px control border the slices use. The panel
        // border spec is 2px and reads as heavier chrome than the ring it sits
        // inside, which made the field look bolted on rather than part of it.
        radius: height / 2
        color: "transparent"
        borderSpec: Border.controlSpec(root.searching ? "focus" : "normal", Color.menu.text, Color.accent)

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

      Column {
        anchors.top: searchBox.bottom
        anchors.topMargin: Style.spacing.panelGap
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.searching
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
          delegate: CursorSurface {
            required property int index
            required property var modelData

            width: root.searchWidth
            height: Style.spacing.popupRowHeight + Style.spacing.controlPaddingY * 2
            radius: Style.cornerRadius
            hasCursor: root.resultIndex === index
            foreground: Color.menu.text

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.resultIndex = index
              onClicked: root.runResult(index)
            }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.rowPaddingX
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.rowPaddingX
              spacing: Style.spacing.controlGap

              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !modelData.appId
                width: Style.font.iconLarge
                text: modelData.icon
                color: root.resultIndex === index ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.iconLarge
              }
              // Apps have an image icon rather than a glyph. Only one of the
              // two is ever visible, and a Row skips what isn't.
              Image {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!modelData.appId
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                source: modelData.appId ? root.appLibrary.iconSource(modelData.appIcon) : ""
                sourceSize.width: Style.font.iconLarge
                sourceSize.height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                asynchronous: true
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.resultIndex === index ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
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
