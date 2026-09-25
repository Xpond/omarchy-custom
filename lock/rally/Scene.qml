import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Rally: a Sport quattro S1 E2 traced by comets in front of a neon city, driving off on unlock.
Item {
  // The lock screen's view (LockView.qml), for designs that read its state.
  property Item host

  function play() { car.play() }
  function hide() { car.hide() }
  function leave() { car.driveOff() }

  // Painted scenery stays flat; the live car and its reflection render above it.
  Image {
    id: city
    anchors.fill: parent
    source: Qt.resolvedUrl("neon-city.png")
    fillMode: Image.PreserveAspectCrop
    smooth: true
    mipmap: true
  }

  // Contact shadow follows the car's shared framing and departure transforms.
  Canvas {
    anchors.fill: car
    opacity: car.painted
    transform: [carGrow, carSlide, carFraming, carLower]
    property var ground: car.ground
    onGroundChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      if (!car.view) return
      var g = getContext("2d"), a = ground[0], b = ground[1], c = car.view([211, -2, 0])
      g.reset(); g.translate(c[0], c[1])
      g.rotate(Math.atan2(b.y - a.y, b.x - a.x))
      g.scale(Math.hypot(b.x - a.x, b.y - a.y) * 0.9, height * 0.105)
      var shade = g.createRadialGradient(0, 0, 0.15, 0, 0, 1)
      shade.addColorStop(0, "#ee02040a"); shade.addColorStop(0.7, "#c902040a"); shade.addColorStop(1, "#0002040a")
      g.fillStyle = shade; g.beginPath(); g.arc(0, 0, 1, 0, Math.PI * 2); g.fill()
    }
  }

  // The wet floor mirrors the car, blurred and fading away from the tyres.
  ShaderEffectSource { id: carImage; anchors.fill: car; sourceItem: car; visible: false }

  Item {
    id: floorFade
    anchors.fill: car
    visible: false
    layer.enabled: true
    // Fades over a fifth of the height, square to the contact line.
    readonly property real reach: car.height * 0.2 / Math.hypot(car.ground[1].x - car.ground[0].x, car.ground[1].y - car.ground[0].y)
    Shape {
      anchors.fill: parent
      ShapePath {
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: (car.ground[0].x + car.ground[1].x) / 2; y1: (car.ground[0].y + car.ground[1].y) / 2
          x2: x1 + (car.ground[1].y - car.ground[0].y) * floorFade.reach; y2: y1 - (car.ground[1].x - car.ground[0].x) * floorFade.reach
          GradientStop { position: 0; color: "#ffffffff" }
          GradientStop { position: 1; color: "#00ffffff" }
        }
        PathRectangle { width: floorFade.width; height: floorFade.height }
      }
    }
  }

  MultiEffect {
    anchors.fill: car
    source: carImage
    maskEnabled: true
    maskSource: floorFade
    maskSpreadAtMin: 1
    blurEnabled: true
    blur: 0.8
    blurMax: 64
    opacity: 0.14
    transform: [carMirror, carGrow, carSlide, carFraming, carLower]
    Matrix4x4 { id: carMirror; matrix: car.mirror }
  }

  // The nose points left and toward the camera: the car slides left, dips and grows as it leaves.
  Scale { id: carGrow; origin.x: car.width * 0.3; origin.y: car.height * 0.6; xScale: 1 + 0.3 * car.launch; yScale: 1 + 0.3 * car.launch }
  Translate { id: carSlide; x: -car.width * 1.2 * car.launch; y: car.height * 0.14 * car.launch }
  // Frame the car, shadow and reflection together, including the entire drive-off.
  Scale { id: carFraming; origin.x: car.width / 2; origin.y: car.height / 2; xScale: 0.89; yScale: 0.89 }
  Translate { id: carLower; x: car.width * 0.03; y: car.height * 0.04 }

  Car {
    id: car
    anchors.fill: parent
    environment: city
    transform: [carGrow, carSlide, carFraming, carLower]
  }
}
