import QtQuick

// Transparent contours: the ring supplies their clock, palette and clear centre.
ShaderEffect {
  required property real phase
  required property real reveal
  required property real quietRadius
  required property color warm
  required property color cool
  // Normalized screen position in XY, visible strength in Z.
  required property vector3d sun
  required property vector3d moon
  readonly property vector2d resolution: Qt.vector2d(width, height)

  visible: reveal > 0
  z: -2
  fragmentShader: Qt.resolvedUrl("fluid.frag.qsb")
}
