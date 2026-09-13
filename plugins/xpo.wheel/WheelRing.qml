import QtQuick
import qs.Commons
import qs.Ui

// The dial, including its discs, labels, track, and comet.
Item {
  id: root

  property var wheel: null
  // Repeated passes merge into quiet illumination as sustained spin builds.
  property real spin: Math.max(0, Math.min(1, (wheel.charge - 0.35) / 0.5))
  Behavior on spin { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

  anchors.fill: parent
  // Stop compositing after the transition to search results.
  opacity: wheel.searching ? 0 : 1
  scale: wheel.searching ? 0.94 : 1
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }

  Item { id: discCutouts; anchors.fill: parent }
  ShaderEffectSource {
    id: maskTexture
    sourceItem: discCutouts
    hideSource: true
    live: true
  }

  RingTrack {
    anchors.fill: parent
    wheel: root.wheel
    discMask: maskTexture
    spin: root.spin
  }

  Repeater {
    model: wheel.slices
    delegate: Item {
      id: slice
      required property int index
      required property var modelData
      readonly property bool active: wheel.selected === index
      property real emphasis: active ? 1 - root.spin * 0.9 : 0
      Behavior on emphasis { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
      readonly property real targetLight: wheel.sweepAt(wheel.sliceAngle(index) - 90)
      property real light: targetLight
      Behavior on light {
        NumberAnimation { duration: slice.targetLight > slice.light ? 70 : 260; easing.type: Easing.OutCubic }
      }
      readonly property real sweep: root.spin * 0.24 + light * (1 - root.spin * 0.85)
      readonly property color glyphColor: Qt.tint(Color.menu.text,
        Util.alpha(wheel.cometColor, Math.max(slice.emphasis, slice.sweep)))
      readonly property real glyphSize: Style.font.displayLarge * wheel.itemSize / wheel.baseItem

      readonly property real angle: (wheel.sliceAngle(index) - 90) * Math.PI / 180
      x: root.width / 2 + wheel.ringRadius * Math.cos(angle) - width / 2
      y: root.height / 2 + wheel.ringRadius * Math.sin(angle) - height / 2
      width: wheel.itemSize
      height: wheel.itemSize

      // Cut the track beneath the animated disc, independent of its translucent fill.
      Rectangle {
        parent: discCutouts
        x: slice.x + (slice.width - width) / 2
        y: slice.y + (slice.height - height) / 2
        width: slice.width * disc.scale
        height: width
        radius: width / 2
        color: "black"
        antialiasing: true
      }

      BorderSurface {
        id: disc
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(
          wheel.surfaceFill.r + (wheel.selectedFill.r - wheel.surfaceFill.r) * slice.emphasis,
          wheel.surfaceFill.g + (wheel.selectedFill.g - wheel.surfaceFill.g) * slice.emphasis,
          wheel.surfaceFill.b + (wheel.selectedFill.b - wheel.surfaceFill.b) * slice.emphasis,
          wheel.surfaceFill.a + (wheel.selectedFill.a - wheel.surfaceFill.a) * slice.emphasis)
        borderSpec: Border.flat(Qt.tint(wheel.surfaceEdge,
          Util.alpha(wheel.cometColor, Math.max(slice.emphasis, slice.sweep * 0.9))),
          Style.spacing.hairline + (Style.space(2) - Style.spacing.hairline) * slice.emphasis)
        scale: 1 + (wheel.selectedScale - 1) * slice.emphasis

        Text {
          anchors.centerIn: parent
          visible: !modelData.iconFile
          text: modelData.icon
          color: slice.glyphColor
          font.family: Style.font.menuFamily
          font.pixelSize: slice.glyphSize
        }
        PanelIcon {
          omarchyPath: wheel.omarchyPath
          anchors.centerIn: parent
          file: modelData.iconFile || ""
          size: slice.glyphSize
          tint: slice.glyphColor
        }
      }

      // Place labels radially outside each disc to clear the track and neighbors.
      Text {
        // Measure clearance to the label's nearest edge.
        readonly property real reach: wheel.itemSize / 2 * wheel.selectedScale + wheel.labelGap
          + (Math.abs(Math.cos(parent.angle)) * width
             + Math.abs(Math.sin(parent.angle)) * height) / 2
        x: parent.width / 2 + reach * Math.cos(parent.angle) - width / 2
        y: parent.height / 2 + reach * Math.sin(parent.angle) - height / 2
        text: modelData.label
        color: Qt.tint(Color.menu.text, Util.alpha(Color.accent, slice.emphasis))
        opacity: 0.6 + 0.4 * slice.emphasis
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
