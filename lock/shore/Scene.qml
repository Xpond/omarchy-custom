import QtQuick

// Shore: where the wash meets the sand, seen from high above. The water's edge surges up across
// the middle of the screen under a rope of foam and slides back; unlocking brings the tide in.
Item {
  id: root

  // The lock screen's view (LockView.qml): whether the display is on.
  property Item host

  // Seconds of surf, from a random point in its hour so each lock shows other waves, and the
  // tide's rise on unlock, in screen heights.
  property real time: 3600 * Math.random()
  property real tide: 0

  function play() { leaving.stop(); tide = 0; arriving.restart() }
  function hide() { arriving.stop(); leaving.stop(); opacity = 0 }
  function leave() { arriving.stop(); leaving.start() }

  NumberAnimation { id: arriving; target: root; property: "opacity"; from: 0; to: 1; duration: 1200 }

  // The tide floods up the beach, gone by the time the lock releases.
  ParallelAnimation {
    id: leaving
    NumberAnimation { target: root; property: "tide"; to: 1.2; duration: 1100; easing.type: Easing.InCubic }
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 1100; easing.type: Easing.InQuart }
  }

  // A blank display shows nothing.
  FrameAnimation {
    running: !root.host.blanked
    onTriggered: root.time += frameTime
  }

  ShaderEffect {
    anchors.fill: parent
    readonly property vector2d resolution: Qt.vector2d(width, height)
    // Wrapped to the surf's hour (shore.frag), so the shader's floats stay precise.
    readonly property real time: root.time % 3600
    readonly property real tide: root.tide
    fragmentShader: Qt.resolvedUrl("shore.frag.qsb")
  }
}
