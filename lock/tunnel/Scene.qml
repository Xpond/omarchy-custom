import QtQuick

Item {
  id: root

  property Item host
  // Edges the password field.
  readonly property color accent: "#c99cff"

  // Distance flown and pace, in the mark's own grid units: it is 30 across.
  property real flight: 0
  property real speed: 0
  readonly property real cruise: 8
  // Recycle marks count gaps ahead, hidden by the far fade.
  readonly property int count: 40
  readonly property real gap: 4
  readonly property real near: 1.5
  readonly property real span: count * gap
  // A 90° view: a mark 14 units ahead fills the screen's height.
  readonly property real focal: height / 2

  // Follow the centreline's tangent and bank into turns in degrees.
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

  ParallelAnimation {
    id: takeoff
    NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 1200 }
    NumberAnimation { target: root; property: "speed"; from: 0; to: root.cruise; duration: 2400; easing.type: Easing.OutCubic }
  }

  ParallelAnimation {
    id: leaving
    NumberAnimation { target: root; property: "speed"; to: root.cruise * 10; duration: 1100; easing.type: Easing.InCubic }
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 1100; easing.type: Easing.InCubic }
  }

  FrameAnimation {
    running: root.speed > 0 && !root.host.blanked
    onTriggered: root.flight += root.speed * frameTime
  }

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
    anchors.fill: parent
    rotation: root.bank

    Repeater {
      model: root.count

      ShaderEffect {
        required property int index
        anchors.fill: parent
        readonly property real flight: root.flight
        // Cull once the far fade falls below a thousandth.
        readonly property real depth: root.near + ((index * root.gap - root.flight) % root.span + root.span) % root.span
        visible: depth - root.near < 0.9 * root.span
        readonly property real near: root.near
        readonly property real span: root.span
        readonly property vector2d centre: Qt.vector2d(width / 2, height / 2)
        readonly property real focal: root.focal
        // Its place along the corridor picks its size and turn; flown past, it comes back as another.
        readonly property int slot: Math.round((root.flight + depth - root.near) / root.gap)
        readonly property real turn: 2 * Math.PI * root.random(slot, 1)
        readonly property real size: 0.7 + 0.6 * root.random(slot, 2)

        // Comet pace is laps per flight unit, so its timing tracks the flight.
        readonly property color tint: Qt.hsla((185 + 135 * root.random(slot, 3)) / 360, 1, 0.72, 1)
        readonly property real start: root.random(slot, 4)
        readonly property real pace: (0.3 + 0.5 * root.random(slot, 5)) / root.cruise
        readonly property real tail: 0.12 + 0.23 * root.random(slot, 6)
        readonly property real inward: root.random(slot, 7) < 0.3 ? 1 : 0
        vertexShader: Qt.resolvedUrl("mark.vert.qsb")
        fragmentShader: Qt.resolvedUrl("mark.frag.qsb")
      }
    }
  }
}
