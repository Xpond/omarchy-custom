pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

Item {
  id: field
  required property real progress
  required property real quietRadius
  required property color tint
  // The night is when these are worth having: full sun washes them out, and
  // the haze a low sun carries softens what is left before it takes them.
  required property real daylight
  required property real haze

  readonly property int columns: Math.max(1, Math.floor(width / 100))
  readonly property int rows: Math.max(1, Math.floor(height / 90))
  visible: progress > 0
  z: -1

  // Twilight softens the stars. Keep the layer allocated throughout the
  // reveal to avoid rebuilding its framebuffer and shader twice per day.
  layer.enabled: visible
  layer.effect: MultiEffect {
    blurEnabled: true
    blur: field.haze
    // Enough blur to turn 1.8–6px points into visible halos at twilight.
    blurMax: 16
  }

  Repeater {
    model: field.columns * field.rows

    Item {
      id: point
      required property int index
      // Cover the whole surface with jitter inside evenly distributed cells.
      readonly property real u: (index % field.columns + 0.2 + noise(index * 3 + 1) * 0.6) / field.columns
      readonly property real v: (Math.floor(index / field.columns) + 0.15 + noise(index * 3 + 2) * 0.7) / field.rows
      // Mostly distant points, with a few larger foreground lights.
      readonly property int band: index % 8
      readonly property int depth: band === 0 ? 2 : (band < 4 ? 1 : 0)
      readonly property real arrival: 0.10 + noise(index * 3 + 3) * 0.65
      readonly property real age: Math.max(0, (field.progress - arrival) / 0.22)
      readonly property real rise: Math.min(1, age)
      readonly property real warmth: Math.exp(-Math.pow((age - 0.75) / 0.55, 2))
      // The wheel sits above this field; keep its controls and labels clear.
      readonly property real distance: Math.hypot(u * (field.width - 32) + 16 - field.width / 2,
                                                v * (field.height - 32) + 16 - field.height / 2)
      readonly property real outside: Math.max(0, Math.min(1,
        (distance - field.quietRadius) / Math.max(1, field.quietRadius * 0.35)))

      function noise(n) {
        var value = Math.sin(n * 127.1) * 43758.5453
        return value - Math.floor(value)
      }

      x: 16 + u * (field.width - 32) - width / 2
      y: 16 + v * (field.height - 32) - height / 2
      width: [1.8, 3.0, 6.0][depth]
      height: width
      opacity: rise * rise * (3 - 2 * rise) * ([0.26, 0.42, 0.62][depth] + warmth * 0.18)
               * (0.30 + 0.70 * outside * outside * (3 - 2 * outside))
               * (1 - 0.85 * field.daylight)

      // A faint halo belongs only to the nearest lights.
      Repeater {
        model: point.depth === 2 ? 3 : 0
        Rectangle {
          required property int index
          anchors.centerIn: parent
          width: point.width * (3 - index * 0.6)
          height: width
          radius: width / 2
          color: field.tint
          opacity: 0.035
          antialiasing: true
        }
      }

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        // Static upper-left glints give each point depth.
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Qt.lighter(field.tint, 1.6) }
          GradientStop { position: 0.45; color: field.tint }
          GradientStop { position: 1; color: Qt.darker(field.tint, 1.6) }
        }
        rotation: 45
        antialiasing: true
      }

      Rectangle {
        x: point.width * 0.18
        y: x
        width: 1.5
        height: width
        radius: width / 2
        color: "white"
        opacity: 0.75
        visible: point.depth === 2
        antialiasing: true
      }
    }
  }
}
