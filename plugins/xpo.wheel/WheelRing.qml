import QtQuick
import qs.Commons
import qs.Ui

// The dial: the discs, their labels, and the stroke that runs through their
// centers. Traded for the results card rather than switched off, so the ring
// draws back as the list comes forward.
Item {
  id: root

  // The wheel, for the slices and the comet. Passed rather than reached for,
  // the way the browser's own components take their panel.
  property var wheel: null
  // Repeated passes merge into quiet illumination as sustained spin builds.
  property real spin: Math.max(0, Math.min(1, (wheel.charge - 0.35) / 0.5))
  Behavior on spin { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

  anchors.fill: parent
  // Traded for the card rather than switched off: the ring draws back
  // as the list comes forward. `visible` still follows the fade so a
  // ring at zero opacity stops being composited at all.
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
      // Tied to the disc rather than fixed: once the ring is full
      // enough that the discs have to shrink, a fixed icon would be the
      // thing that overflows them.
      readonly property real glyphSize: Style.font.displayLarge * wheel.itemSize / wheel.baseItem

      readonly property real angle: (wheel.sliceAngle(index) - 90) * Math.PI / 180
      x: root.width / 2 + wheel.ringRadius * Math.cos(angle) - width / 2
      y: root.height / 2 + wheel.ringRadius * Math.sin(angle) - height / 2
      width: wheel.itemSize
      height: wheel.itemSize

      // Cut the track out beneath the actual animated disc, independently
      // of its translucent fill. Reparent only the mask's visual geometry.
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
        // A dial of discs reads as one mechanism; the same eight as
        // rounded squares read as a grid arranged in a circle.
        radius: width / 2
        // A surface, not an outline: only a fill separates a slice
        // from the blurred desktop behind it.
        color: Qt.rgba(
          wheel.surfaceFill.r + (wheel.selectedFill.r - wheel.surfaceFill.r) * slice.emphasis,
          wheel.surfaceFill.g + (wheel.selectedFill.g - wheel.surfaceFill.g) * slice.emphasis,
          wheel.surfaceFill.b + (wheel.selectedFill.b - wheel.surfaceFill.b) * slice.emphasis,
          wheel.surfaceFill.a + (wheel.selectedFill.a - wheel.surfaceFill.a) * slice.emphasis)
        // Selection settles into a full ring at rest; at speed it barely
        // changes weight, letting the comet carry the motion.
        borderSpec: Border.flat(Qt.tint(wheel.surfaceEdge,
          Util.alpha(wheel.cometColor, Math.max(slice.emphasis, slice.sweep * 0.9))),
          Style.spacing.hairline + (Style.space(2) - Style.spacing.hairline) * slice.emphasis)
        // Only the disc grows. Scaling the label with it would drift the
        // whole ring of text every time selection moved.
        scale: 1 + (wheel.selectedScale - 1) * slice.emphasis

        Text {
          anchors.centerIn: parent
          visible: !modelData.iconFile
          text: modelData.icon
          color: slice.glyphColor
          font.family: Style.font.menuFamily
          font.pixelSize: slice.glyphSize
        }
        // Tailscale's and Dropbox's marks are shapes Omarchy draws
        // itself, so there is no codepoint to set here.
        PanelIcon {
          omarchyPath: wheel.omarchyPath
          anchors.centerIn: parent
          file: modelData.iconFile || ""
          size: slice.glyphSize
          tint: slice.glyphColor
        }
      }

      // Outside the disc rather than in it: a circle's usable width
      // collapses away from its center, and "Bluetooth" does not fit
      // under an icon in there. Pushed out along its own spoke rather
      // than hung straight down, because the dial's stroke runs
      // through every disc's center -- a label below the east or west
      // disc sits exactly on the arc's path and gets washed out as it
      // passes. Radially there is nothing for it to collide with, and
      // they read as one radiating set. Keeping the arc per slice
      // constant as the ring grows is what keeps neighbouring labels
      // off each other at any count.
      Text {
        // Measured to the box's nearest edge rather than its center,
        // so every label clears its disc by the same margin whatever
        // its width and whatever angle it sits at -- to the center,
        // a long label on a diagonal has its near corner back on top
        // of the disc.
        readonly property real reach: wheel.itemSize / 2 * wheel.selectedScale + wheel.labelGap
          + (Math.abs(Math.cos(parent.angle)) * width
             + Math.abs(Math.sin(parent.angle)) * height) / 2
        x: parent.width / 2 + reach * Math.cos(parent.angle) - width / 2
        y: parent.height / 2 + reach * Math.sin(parent.angle) - height / 2
        text: modelData.label
        color: Qt.tint(Color.menu.text, Util.alpha(Color.accent, slice.emphasis))
        // Labels name the icon rather than compete with it, so they sit
        // back until the slice is the one selected.
        opacity: 0.6 + 0.4 * slice.emphasis
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
