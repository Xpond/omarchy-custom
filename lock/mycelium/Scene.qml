import QtQuick
import "grow.js" as Grow

Item {
  id: root

  property Item host
  // Edges the password field.
  readonly property color accent: "#8ee8e0"

  // Growth steps at 45/s; each tip moves 3 units in a 1080-unit-high frame.
  property real grown: 0
  property bool spreading: false
  property var colony: null
  property var growing: null
  function seed() {
    colony = null
    growing = width > 0 && height > 0 ? Grow.begin(width / height) : null
  }
  onWidthChanged: Qt.callLater(seed)
  onHeightChanged: Qt.callLater(seed)
  // Build in small slices so loading and input stay responsive; release the builder when done.
  Timer {
    interval: 1
    running: root.growing !== null && !root.host.blanked
    repeat: true
    onTriggered: {
      var ready = root.growing(3)
      if (ready) { root.growing = null; root.colony = ready }
    }
  }
  // Growth waits for all four threaded canvases to finish their initial paint.
  property int drawn: 0
  onColonyChanged: { drawn = 0; web.requestPaint(); times.requestPaint(); shine.requestPaint(); deeper.requestPaint() }

  property real time: 0
  FrameAnimation {
    running: !root.host.blanked && (root.spreading || leaving.running)
    onTriggered: {
      root.time += frameTime
      if (root.spreading && root.colony && root.drawn >= 4) root.grown = Math.min(root.colony.fronts.length, root.grown + 45 * frameTime)
    }
  }
  // Camera [pan x/y in pixels, zoom, roll]; zoom hides the colony's edges during drift.
  readonly property vector4d camera: {
    var m = Math.min(width, height)
    return Qt.vector4d(0.006 * m * Math.sin(time / 7), 0.005 * m * Math.sin(time / 9 + 1),
                       1.04 + 0.01 * Math.sin(time / 11 + 2), 0.004 * Math.sin(time / 13 + 3))
  }

  function play() { leaving.stop(); grown = 0; spreading = true }
  function hide() { leaving.stop(); spreading = false; grown = 0 }
  function leave() { spreading = false; leaving.start() }

  ParallelAnimation {
    id: leaving
    NumberAnimation { target: root; property: "grown"; to: 0; duration: 550; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "opacity"; to: 0; duration: 550; easing.type: Easing.InQuart }
  }

  // Batch strands of each width into one antialiased stroke.
  Canvas {
    id: web
    anchors.fill: parent
    visible: false
    renderStrategy: Canvas.Threaded
    onPainted: if (root.colony) root.drawn++
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

  // RG encodes arrival steps without antialiasing; 1.5px padding covers smoothed strand edges.
  // Draw earliest steps last so intersections reveal at their first arrival.
  Canvas {
    id: times
    anchors.fill: parent
    visible: false
    antialiasing: false
    renderStrategy: Canvas.Threaded
    onPainted: if (root.colony) root.drawn++
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

  // Deep hyphae encode arrival step / 8 at half resolution, earliest drawn last.
  Canvas {
    id: deeper
    width: root.width / 2
    height: root.height / 2
    visible: false
    renderStrategy: Canvas.Threaded
    onPainted: if (root.colony) root.drawn++
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

  // One light-map pixel covers about 32 design units.
  Canvas {
    id: shine
    width: root.colony ? root.colony.light.cols : 1
    height: root.colony ? root.colony.light.rows : 1
    visible: false
    renderStrategy: Canvas.Threaded
    onPainted: if (root.colony) root.drawn++
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
