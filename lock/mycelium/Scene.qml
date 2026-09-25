import QtQuick
import "grow.js" as Grow

// A new colony grows each lock, lighting the ground as the camera drifts; unlocking draws it back.
Item {
  id: root

  // The lock screen's view (LockView.qml): whether the display is on.
  property Item host

  // How many of the colony's steps have grown, 45 a second while it spreads: every tip moves 3
  // units a step, the screen being 1080 high.
  property real grown: 0
  property bool spreading: false
  readonly property var colony: width > 0 && height > 0 ? Grow.grow(width / height) : null
  onColonyChanged: { web.requestPaint(); times.requestPaint(); shine.requestPaint(); deeper.requestPaint() }

  // Start growth once the scene has a size, even if play() came earlier. Pause both clocks on blank.
  property real time: 0
  FrameAnimation {
    running: !root.host.blanked
    onTriggered: {
      root.time += frameTime
      if (root.spreading && root.colony) root.grown = Math.min(root.colony.fronts.length, root.grown + 45 * frameTime)
    }
  }
  // The camera's slow drift, over a minute or so: its pan in pixels, zoom and roll, zoomed in
  // enough that the colony's edges never show.
  readonly property vector4d camera: {
    var m = Math.min(width, height)
    return Qt.vector4d(0.006 * m * Math.sin(time / 7), 0.005 * m * Math.sin(time / 9 + 1),
                       1.04 + 0.01 * Math.sin(time / 11 + 2), 0.004 * Math.sin(time / 13 + 3))
  }

  function play() { leaving.stop(); grown = 0; spreading = true }
  function hide() { leaving.stop(); spreading = false; grown = 0 }
  function leave() { spreading = false; leaving.start() }

  // Drawn back into the centre, gone by the time the lock releases.
  ParallelAnimation {
    id: leaving
    NumberAnimation { target: root; property: "grown"; to: 0; duration: 1100; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 1100; easing.type: Easing.InQuart }
  }

  // The colony's lines, anti-aliased, the runs of each width in one stroke.
  Canvas {
    id: web
    anchors.fill: parent
    visible: false
    onPaint: {
      var c = getContext("2d"), k = height / 1080
      c.clearRect(0, 0, width, height)
      if (!root.colony) return
      c.setTransform(k, 0, 0, k, width / 2, height / 2)
      c.strokeStyle = "white"
      c.lineCap = "round"
      c.lineJoin = "bevel"
      root.colony.strands.forEach(function(runs, bin) {
        c.lineWidth = bin / 4
        c.beginPath()
        runs.forEach(function(run) {
          c.moveTo(run[0], run[1])
          for (var i = 2; i < run.length; i += 2) c.lineTo(run[i], run[i + 1])
        })
        c.stroke()
      })
    }
  }

  // The step that reaches each pixel of those lines, in red and green. Drawn without antialiasing
  // to store exact steps, then sampled smoothly by the shader. A pixel and a half wider each side
  // covers their smoothed edges though Qt draws the finest a pixel wide and unsmoothed strokes sit
  // up to half a pixel off. Where lines meet, the earliest step is drawn last and wins.
  Canvas {
    id: times
    anchors.fill: parent
    visible: false
    antialiasing: false
    smooth: true
    onPaint: {
      var c = getContext("2d"), k = height / 1080
      c.clearRect(0, 0, width, height)
      if (!root.colony) return
      c.setTransform(k, 0, 0, k, width / 2, height / 2)
      c.lineCap = "square"
      var fronts = root.colony.fronts
      for (var s = fronts.length - 1; s > 0; s--) {
        if (!fronts[s]) continue
        c.strokeStyle = "rgb(" + (s >> 8) + "," + (s & 255) + ",0)"
        fronts[s].forEach(function(f, bin) {
          c.lineWidth = bin / 4 + 3 / k
          c.beginPath()
          for (var i = 0; i < f.length; i += 4) { c.moveTo(f[i], f[i + 1]); c.lineTo(f[i + 2], f[i + 3]) }
          c.stroke()
        })
      }
    }
  }

  // The colony again, for the deep hyphae: soft, at half the resolution, each line coloured with
  // the step that reaches it in eighths. Earliest last, so it wins where lines meet.
  Canvas {
    id: deeper
    width: root.width / 2
    height: root.height / 2
    visible: false
    onPaint: {
      var c = getContext("2d"), k = height / 1080
      c.clearRect(0, 0, width, height)
      if (!root.colony) return
      c.setTransform(k, 0, 0, k, width / 2, height / 2)
      c.lineCap = "square"
      c.lineWidth = 3
      var fronts = root.colony.fronts
      for (var e = fronts.length >> 3; e >= 0; e--) {
        c.strokeStyle = "rgb(" + Math.min(e, 255) + ",0,0)"
        c.beginPath()
        for (var s = 8 * e; s < 8 * e + 8; s++) if (fronts[s]) fronts[s].forEach(function(f) {
          for (var i = 0; i < f.length; i += 4) { c.moveTo(f[i], f[i + 1]); c.lineTo(f[i + 2], f[i + 3]) }
        })
        c.stroke()
      }
    }
  }

  // The light the colony casts, a pixel to about 32 units, which the shader magnifies smoothly.
  Canvas {
    id: shine
    width: root.colony ? root.colony.light.cols : 1
    height: root.colony ? root.colony.light.rows : 1
    visible: false
    onPaint: {
      if (!root.colony) return
      var c = getContext("2d"), image = c.createImageData(width, height), px = root.colony.light.px
      for (var i = 0; i < px.length; i++) image.data[i] = px[i]
      c.putImageData(image, 0, 0)
    }
  }

  // The ground, drawn once: the camera moves over it.
  ShaderEffect {
    id: earth
    anchors.fill: parent
    readonly property vector2d resolution: Qt.vector2d(width, height)
    fragmentShader: Qt.resolvedUrl("ground.frag.qsb")
  }
  ShaderEffectSource { id: soil; sourceItem: earth; live: false; hideSource: true; visible: false }

  ShaderEffect {
    anchors.fill: parent
    property var lines: web
    property var reach: times
    property var light: shine
    property var deep: deeper
    property var ground: soil
    readonly property vector2d resolution: Qt.vector2d(width, height)
    readonly property vector2d lightSize: Qt.vector2d(shine.width, shine.height)
    readonly property vector2d deepSize: Qt.vector2d(deeper.width, deeper.height)
    property real grown: root.grown
    property real time: root.time
    property vector4d camera: root.camera
    fragmentShader: Qt.resolvedUrl("mycelium.frag.qsb")
  }
}
