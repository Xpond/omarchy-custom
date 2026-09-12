pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// Translucent sky over the blurred desktop. Sun and moon share one arc,
// supplying positions for the fluid and lighting for the mark.
Item {
  id: sky

  // One day per phase unit; never wrap it, so interpolation stays smooth.
  required property real phase
  // Follows the mark's sustained-spin reveal and release fade.
  required property real reveal

  // The sun rises on the left, passes overhead, and sets on the right.
  readonly property real elevation: Math.sin(phase * 2 * Math.PI)
  readonly property real azimuth: -Math.cos(phase * 2 * Math.PI)
  // Only what is above the horizon lights the sky.
  readonly property real light: Math.max(0, elevation)
  // Twilight straddles the horizon: colour lingers after sunset, and the
  // haze softens stars while they are still visible before full daylight.
  readonly property real dusk: Math.exp(-Math.pow(elevation / 0.45, 2))
  // The sun's glow persists briefly below the horizon; the moon rises after it.
  readonly property real glow: Math.max(0, Math.min(1, elevation + 0.35))
  readonly property real moon: Math.max(0, Math.min(1, (-elevation - 0.10) / 0.55))

  // Shared screen positions keep the glow and fluid deformation together.
  function bodyPosition(side) {
    return Qt.vector2d(0.5 + 0.40 * azimuth * side, 0.78 - 0.56 * elevation * side)
  }
  readonly property vector2d sunPosition: bodyPosition(1)
  readonly property vector2d moonPosition: bodyPosition(-1)

  // Hand lighting from sun (+1) to moon (-1), passing through frontal light
  // at the horizon. Negative shader X means left; negative Y means above.
  readonly property real keyFacing: Math.max(-1, Math.min(1, elevation * 3))
  readonly property vector2d keyDirection: Qt.vector2d(0.70 * keyFacing * azimuth,
                                                       -0.70 * keyFacing * elevation)

  visible: reveal > 0
  z: -2

  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  readonly property color nightColor: Qt.rgba(0.04, 0.05, 0.11, 1)
  readonly property color dayColor: Qt.rgba(0.38, 0.60, 0.92, 1)
  // Azimuth distinguishes morning from evening without a branch at midnight.
  // Below the horizon is violet; rising through it brings rose, then gold.
  readonly property real evening: (azimuth + 1) / 2
  readonly property real twilightRise: Math.max(0, Math.min(1, (elevation + 0.30) / 0.65))
  readonly property color dawnColor: sky.mix(
    sky.mix(Qt.rgba(0.30, 0.20, 0.52, 1), Qt.rgba(0.90, 0.48, 0.57, 1), Math.min(1, twilightRise * 2)),
    Qt.rgba(1, 0.84, 0.56, 1), Math.max(0, twilightRise * 2 - 1))
  // Sunset walks this backwards: gold into copper, leaving purple afterglow.
  readonly property color sunsetColor: sky.mix(
    sky.mix(Qt.rgba(0.29, 0.12, 0.42, 1), Qt.rgba(0.93, 0.36, 0.17, 1), Math.min(1, twilightRise * 2)),
    Qt.rgba(1, 0.69, 0.36, 1), Math.max(0, twilightRise * 2 - 1))
  readonly property color twilightColor: sky.mix(dawnColor, sunsetColor, evening)
  // Low light is the colour of the light it is carrying; high light burns pale.
  readonly property color glowColor: sky.mix(twilightColor, Qt.rgba(1, 0.93, 0.78, 1), light * light)

  // The bevel borrows the light's colour while the mark keeps its own pigment.
  // Moonlight is cooler and weaker, with the same smooth handover as direction.
  readonly property color keyColor: sky.mix(glowColor, Qt.rgba(0.68, 0.79, 1, 1), Math.max(0, -keyFacing))
  readonly property real keyStrength: 1 - 0.28 * Math.max(0, -keyFacing)

  // The sky itself: what colour the air is, with no light in it yet.
  readonly property color zenith: sky.mix(nightColor, dayColor, light * 0.62)
  readonly property color horizon: sky.mix(sky.mix(nightColor, dayColor, light), twilightColor, dusk)

  Rectangle {
    anchors.fill: parent
    // Hold noon's brightness down so the wheel's labels stay readable.
    opacity: (0.09 + 0.14 * sky.light + 0.23 * sky.dusk) * Math.min(1, sky.reveal)
    gradient: Gradient {
      GradientStop { position: 0; color: sky.zenith }
      GradientStop { position: 0.55; color: sky.mix(sky.zenith, sky.horizon, 0.45) }
      GradientStop { position: 1; color: sky.horizon }
    }
  }

  // Both lights use the same radial falloff and shared screen positions.
  component Body: Shape {
    id: body
    // +1 the sun's end of the arc, -1 the moon's.
    required property real side
    // How much screen it gets, already faded by how far up it is.
    required property real amount
    required property real spread
    required property color core
    // Fade to the same halo RGB at zero alpha to avoid a coloured rim.
    required property color halo
    required property real edge

    readonly property vector2d position: side > 0 ? sky.sunPosition : sky.moonPosition
    readonly property real px: sky.width * position.x
    readonly property real py: sky.height * position.y

    anchors.fill: parent
    opacity: amount * Math.min(1, sky.reveal)
    visible: opacity > 0.004
    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: body.px
        centerY: body.py
        centerRadius: sky.height * body.spread
        focalX: body.px
        focalY: body.py
        GradientStop { position: 0; color: body.core }
        GradientStop { position: body.edge; color: body.halo }
        GradientStop { position: 1; color: Qt.rgba(body.halo.r, body.halo.g, body.halo.b, 0) }
      }
      startX: 0; startY: 0
      PathLine { x: sky.width; y: 0 }
      PathLine { x: sky.width; y: sky.height }
      PathLine { x: 0; y: sky.height }
      PathLine { x: 0; y: 0 }
    }
  }

  // Broad, warm sunlight; twilight strengthens its glow.
  Body {
    side: 1
    amount: sky.glow * (0.36 + 0.24 * sky.dusk)
    spread: 0.64
    core: sky.glowColor
    halo: Qt.rgba(sky.glowColor.r, sky.glowColor.g, sky.glowColor.b, 0.40)
    edge: 0.30
  }

  // Smaller, cooler moonlight.
  Body {
    side: -1
    amount: sky.moon * 0.30
    spread: 0.30
    core: Qt.rgba(0.83, 0.88, 1, 1)
    halo: Qt.rgba(0.66, 0.74, 0.95, 0.45)
    edge: 0.22
  }
}
