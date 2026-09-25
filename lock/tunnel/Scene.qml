import QtQuick

// Tunnel: the wheel's Omarchy mark stacked into a corridor, flown through first person. Every
// mark has its own hue and runs its own comet, as the wheel's does; dust drifts past, towards a
// glow at the far end.
Item {
  id: root

  // The lock screen's view (LockView.qml): whether the display is on.
  property Item host

  // Distance flown and pace, in the mark's own grid units: it is 30 across.
  property real flight: 0
  property real speed: 0
  readonly property real cruise: 8
  // A mark stands every gap; one flown past returns count gaps further on, where the dark hides it.
  readonly property int count: 40
  readonly property real gap: 4
  readonly property real near: 1.5
  readonly property real span: count * gap
  // A 90° view: a mark 14 units ahead fills the screen's height.
  readonly property real focal: height / 2

  // The corridor's centreline wanders. The camera flies along it, looking down its tangent,
  // and banks into the turns, in degrees.
  function bend(s) { return Qt.point(7 * Math.sin(s / 40) + 2 * Math.sin(s / 17 + 1), 4 * Math.sin(s / 53 + 2)) }
  readonly property point here: bend(flight)
  readonly property point ahead: bend(flight + 1)
  readonly property point behind: bend(flight - 1)
  readonly property point slope: Qt.point((ahead.x - behind.x) / 2, (ahead.y - behind.y) / 2)
  readonly property real bank: -700 * (ahead.x - 2 * here.x + behind.x)

  // Repeatable noise in [0, 1): a place along the corridor always holds the same mark.
  function random(slot, salt) { var x = Math.sin(slot * 12.9898 + salt * 78.233) * 43758.5453; return x - Math.floor(x) }

  function play() { leaving.stop(); takeoff.restart() }
  function hide() { takeoff.stop(); leaving.stop(); opacity = 0; speed = 0 }
  function leave() { takeoff.stop(); leaving.start() }

  // Throttle up from a standstill as the tunnel fades in.
  ParallelAnimation {
    id: takeoff
    NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 1200 }
    NumberAnimation { target: root; property: "speed"; from: 0; to: root.cruise; duration: 2400; easing.type: Easing.OutCubic }
  }

  // Punch through the tunnel, gone by the time the lock releases.
  ParallelAnimation {
    id: leaving
    NumberAnimation { target: root; property: "speed"; to: root.cruise * 10; duration: 1100; easing.type: Easing.InCubic }
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 1100; easing.type: Easing.InCubic }
  }

  // A blank display shows nothing.
  FrameAnimation {
    running: root.speed > 0 && !root.host.blanked
    onTriggered: root.flight += root.speed * frameTime
  }

  // The space around the tunnel, dark whatever the theme: a glow at the far end, and dust.
  ShaderEffect {
    anchors.fill: parent
    readonly property vector2d resolution: Qt.vector2d(width, height)
    // Where the tunnel's tangent meets the screen, turned with the bank.
    readonly property vector2d vanish: {
      var x = -root.focal * root.slope.x, y = -root.focal * root.slope.y
      return Qt.vector2d(width / 2 + x * Math.cos(roll) - y * Math.sin(roll), height / 2 + x * Math.sin(roll) + y * Math.cos(roll))
    }
    readonly property real roll: root.bank * Math.PI / 180
    // Wrapped to the dust's cycle (space.frag), so the shader's floats stay precise.
    readonly property real flight: root.flight % 160
    readonly property real focal: root.focal
    readonly property color glow: "#3b4bd6"
    fragmentShader: Qt.resolvedUrl("space.frag.qsb")
  }

  Item {
    id: tunnel
    anchors.fill: parent
    rotation: root.bank

    Repeater {
      model: root.count

      ShaderEffect {
        required property int index
        // How far ahead this mark stands.
        readonly property real depth: root.near + ((index * root.gap - root.flight) % root.span + root.span) % root.span
        readonly property point at: root.bend(root.flight + depth)
        // Its place along the corridor picks its size and turn; flown past, it comes back as another.
        readonly property int slot: Math.round((root.flight + depth - root.near) / root.gap)

        // The mark's 30 units, and 2 each side for its glow.
        width: 34
        height: 34
        x: tunnel.width / 2 - 17 + root.focal * ((at.x - root.here.x) / depth - root.slope.x)
        y: tunnel.height / 2 - 17 + root.focal * ((at.y - root.here.y) / depth - root.slope.y)
        rotation: 360 * root.random(slot, 1)
        scale: (0.7 + 0.6 * root.random(slot, 2)) * root.focal / depth
        // Fades in from the far end, and out once past the screen's edges, at 16:9 even the smallest.
        opacity: Math.min(1, (depth - root.near) / 1.5) * Math.pow(1 - (depth - root.near) / root.span, 3)

        // Its own hue between cyan and magenta, and its comet's start, pace in laps a second at
        // cruise, tail and way round. The comets keep time with the flight.
        readonly property color tint: Qt.hsla((185 + 135 * root.random(slot, 3)) / 360, 1, 0.72, 1)
        readonly property real head: (root.random(slot, 4) + (0.3 + 0.5 * root.random(slot, 5)) * root.flight / root.cruise) % 1
        readonly property real tail: 0.12 + 0.23 * root.random(slot, 6)
        readonly property real inward: root.random(slot, 7) < 0.3 ? 1 : 0
        readonly property real pixel: 1 / scale
        fragmentShader: Qt.resolvedUrl("mark.frag.qsb")
      }
    }
  }
}
