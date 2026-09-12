import QtQuick
import qs.Commons

Item {
  id: root
  required property var wheel
  required property var discMask
  required property real spin

  property real visualHead: 0
  property real settleOffset: 0
  readonly property real headOffset: spinClock.running ? visualHead - wheel.arcHead : settleOffset

  // Key repeat can make five laps a second. Give sustained spin its own
  // readable clock while leaving selection and the background clock alone.
  function advance(dt) {
    root.visualHead += (root.wheel.arcDrag < 0 ? -1 : 1) * 180 * Math.min(dt, 0.05)
  }
  FrameAnimation {
    id: spinClock
    running: root.wheel.opened && !root.wheel.searching && root.wheel.charge > 0.35
    onTriggered: root.advance(frameTime)
    onRunningChanged: {
      if (running) {
        root.visualHead = root.wheel.arcHead + root.settleOffset
        settle.stop()
        root.settleOffset = 0
      } else {
        // Rejoin the selection along the shortest arc, without chasing laps
        // accumulated by the much faster input clock.
        root.settleOffset = ((root.visualHead - root.wheel.arcHead + 180) % 360 + 360) % 360 - 180
        settle.restart()
      }
    }
  }
  NumberAnimation {
    id: settle
    target: root; property: "settleOffset"
    to: 0; duration: 300; easing.type: Easing.OutCubic
  }

  ShaderEffect {
    anchors.fill: parent
    readonly property vector2d resolution: Qt.vector2d(width, height)
    readonly property real ringRadius: root.wheel.ringRadius
    readonly property real bandWidth: Style.space(2)
    readonly property real arcFrom: (root.wheel.arcFrom + root.headOffset) * Math.PI / 180
    readonly property real arcSpan: root.wheel.arcSpan * Math.PI / 180
    readonly property real direction: root.wheel.arcDrag < 0 ? -1 : 1
    readonly property real motion: Math.min(1, Math.abs(root.wheel.arcDrag) / root.wheel.arcSpread)
    readonly property real spin: root.spin
    readonly property color baseColor: Color.menu.text
    readonly property color tint: root.wheel.cometColor
    readonly property var discMask: root.discMask
    property real presence: root.wheel.selected >= 0 || Math.abs(root.wheel.arcDrag) > 0.5 ? 1 : 0
    Behavior on presence { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    fragmentShader: Qt.resolvedUrl("ring.frag.qsb")
  }
}
