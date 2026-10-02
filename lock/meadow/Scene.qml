import QtQuick
import "garden.js" as Garden
import "foreground.js" as Foreground

Item {
  id: root
  property Item host
  // Edges the password field.
  readonly property color accent: "#ffd7a3"
  property var garden: null
  property var near: []
  property int drawn: 0
  property real grown: 0
  property real time: 0
  property bool playing: false

  function seed() {
    if (width <= 0 || height <= 0) return
    drawn = 0
    garden = Garden.garden(width / height)
    table.requestPaint(); nearGarden.requestPaint()
  }
  Component.onCompleted: Qt.callLater(seed)
  onWidthChanged: Qt.callLater(seed)
  onHeightChanged: Qt.callLater(seed)
  function play() { leaving.stop(); opacity = 1; grown = 0; playing = true }
  function hide() { leaving.stop(); playing = false; grown = 0 }
  function leave() { playing = false; leaving.restart() }
  NumberAnimation { id: leaving; target: root; property: "opacity"; to: 0; duration: 1000; easing.type: Easing.InOutQuad }
  FrameAnimation {
    running: !root.host.blanked && (root.playing || leaving.running)
    onTriggered: {
      root.time = (root.time + frameTime) % 3600
      if (root.playing && root.drawn >= 3 && root.grown < 4) root.grown = Math.min(4, root.grown + frameTime)
    }
  }

  // One texel per plant and field; the growth shaders read the garden from it.
  Canvas {
    id: table
    width: root.garden ? root.garden.plants.length : 1
    height: 12
    visible: false
    smooth: false
    renderStrategy: Canvas.Threaded
    onPainted: if (root.garden) root.drawn++
    onPaint: if (root.garden) Garden.encode(getContext("2d"), root.garden.plants)
  }
  // The same for the near bank's flowers, once it has painted.
  Canvas {
    id: nearTable
    width: Math.max(1, root.near.length)
    height: 12
    visible: false
    smooth: false
    renderStrategy: Canvas.Threaded
    onPainted: if (root.near.length) root.drawn++
    onPaint: Garden.encode(getContext("2d"), root.near)
  }
  component Plants: ShaderEffect {
    property real group
    property real part
    property real count: root.garden ? root.garden.plants.length : 0
    property real rows
    property var plants: table
    property var foreground: nearGarden
    property real grown: root.grown
    property real time: group > 0 ? root.time : 0
    property real unit: height / 900
    property real pixel: 900 / growth.artworkHeight
    property real wide: width / height * 900
    // The garden spans the whole scene, wherever a layer sits.
    y: -parent.y
    width: root.width
    height: root.height
    mesh: GridMesh { resolution: Qt.size(1, Math.max(1, count * rows)) }
    vertexShader: Qt.resolvedUrl("plants.vert.qsb")
    fragmentShader: Qt.resolvedUrl("plants.frag.qsb")
  }
  // Grass, then the lettering's stems and leaves, then its flower heads, drawn live while they
  // grow. Afterwards the layer stays still and the wind only bends its texture.
  Item {
    id: growth
    anchors.fill: parent
    visible: false
    layer.enabled: true
    layer.textureSize: Qt.size(artworkWidth, artworkHeight)
    readonly property int artworkWidth: Math.ceil(width * Screen.devicePixelRatio)
    readonly property int artworkHeight: Math.ceil(height * Screen.devicePixelRatio)
    Plants { part: 0; count: root.garden ? 1200 : 0; rows: 7 }
    Plants { part: 1; rows: 64 }
    Plants { part: 2; rows: 4 }
  }
  // The lower flowers sway from their roots, so the bottom 30% they grow in is redrawn every
  // frame: the meadow's behind the near bank's ground and stones, and the near bank's in front.
  component Low: Item {
    y: root.height * .7
    width: root.width
    height: root.height * .3
    visible: false
    layer.enabled: true
    layer.textureSize: Qt.size(growth.artworkWidth, Math.ceil(growth.artworkHeight * .3))
  }
  Low {
    id: meadowLayer
    Plants { group: 1; part: 1; rows: 64 }
    Plants { group: 1; part: 2; rows: 4 }
  }
  Low {
    id: nearLayer
    Plants { group: 2; part: 1; rows: 64; count: root.near.length; plants: nearTable }
    Plants { group: 2; part: 2; rows: 4; count: root.near.length; plants: nearTable }
  }
  // The near bank: still ground, grass and stones in the top half, the stones' outlines below.
  Canvas {
    id: nearGarden
    width: growth.artworkWidth
    height: Math.ceil(growth.artworkHeight * .3) * 2
    visible: false
    antialiasing: true
    renderStrategy: Canvas.Threaded
    onPainted: if (root.garden) { root.drawn++; nearTable.requestPaint() }
    onPaint: {
      var c = getContext("2d"), k = growth.artworkHeight / 900
      c.resetTransform(); c.clearRect(0,0,width,height)
      if (!root.garden) return
      c.scale(k,k); c.translate(0,-630)
      root.near = Foreground.draw(c,root.width / root.height * 900)
    }
  }
  ShaderEffect {
    anchors.fill: parent
    property var plants: growth
    property var foreground: nearGarden
    property var meadowFlowers: meadowLayer
    property var nearFlowers: nearLayer
    property real grown: root.grown
    property real time: root.time
    readonly property vector2d resolution: Qt.vector2d(width,height)
    readonly property real artworkWidth: growth.artworkWidth
    fragmentShader: Qt.resolvedUrl("meadow.frag.qsb")
  }
}
