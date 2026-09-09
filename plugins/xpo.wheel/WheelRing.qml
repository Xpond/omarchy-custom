import QtQuick
import QtQuick.Shapes
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

  // Both arcs are the same sweep at two weights, and only the dial draws them.
  component Track: ShapePath {
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    PathAngleArc {
      centerX: wheel.ringBox / 2
      centerY: wheel.ringBox / 2
      radiusX: wheel.ringRadius
      radiusY: wheel.ringRadius
      startAngle: wheel.arcFrom
      sweepAngle: wheel.arcSpan
    }
  }

  anchors.fill: parent
  // Traded for the card rather than switched off: the ring draws back
  // as the list comes forward. `visible` still follows the fade so a
  // ring at zero opacity stops being composited at all.
  opacity: wheel.searching ? 0 : 1
  scale: wheel.searching ? 0.94 : 1
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }

  // The dial the discs sit on. Without a stroke through their centers
  // the eight read as scattered chips rather than one object.
  Rectangle {
    anchors.centerIn: parent
    width: wheel.ringRadius * 2
    height: width
    radius: width / 2
    color: "transparent"
    border.width: Style.spacing.hairline
    border.color: Util.alpha(Color.menu.text, 0.12)
  }

  // The comet. It rides the dial's own stroke rather than sitting
  // outside it, so what moves is the ring lighting up along its
  // length -- the wheel turning, not a marker sliding over it. The
  // under-glow goes down first, so the crisp arc sits in its own light.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    // Nothing to point at until something is selected -- except during
    // the opening lap, which is the comet with nothing to point at yet.
    opacity: wheel.selected >= 0 || Math.abs(wheel.arcDrag) > 0.5 ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    Track { strokeWidth: Style.space(9); strokeColor: Util.alpha(wheel.cometColor, 0.16) }
    Track { strokeWidth: Style.space(3); strokeColor: wheel.cometColor }
  }

  Repeater {
    model: wheel.slices
    delegate: Item {
      id: slice
      required property int index
      required property var modelData
      readonly property bool active: wheel.selected === index
      // Where the streak is on this disc right now, and what that
      // does to its glyph: full accent while selected, and the
      // comet's hue washing over it as the trail crosses.
      readonly property real sweep: wheel.sweepAt(wheel.sliceAngle(index) - 90)
      readonly property color glyphColor: Qt.tint(Color.menu.text,
        Util.alpha(wheel.cometColor, active ? 1 : slice.sweep))
      // Tied to the disc rather than fixed: once the ring is full
      // enough that the discs have to shrink, a fixed icon would be the
      // thing that overflows them.
      readonly property real glyphSize: Style.font.displayLarge * wheel.itemSize / wheel.baseItem

      readonly property real angle: (wheel.sliceAngle(index) - 90) * Math.PI / 180
      x: root.width / 2 + wheel.ringRadius * Math.cos(angle) - width / 2
      y: root.height / 2 + wheel.ringRadius * Math.sin(angle) - height / 2
      width: wheel.itemSize
      height: wheel.itemSize

      BorderSurface {
        anchors.fill: parent
        // A dial of discs reads as one mechanism; the same eight as
        // rounded squares read as a grid arranged in a circle.
        radius: width / 2
        // A surface, not an outline: only a fill separates a slice
        // from the blurred desktop behind it.
        color: active
          ? wheel.selectedFill
          : wheel.surfaceFill
        // A full weight ring against everyone else's hairline, in
        // the comet's hue rather than the flat accent -- and every
        // unselected one takes that hue as the streak crosses it and
        // gives it back as the tail leaves.
        borderSpec: active
          ? Border.flat(wheel.cometColor, Style.space(2))
          : Border.flat(Qt.tint(wheel.surfaceEdge,
                                Util.alpha(wheel.cometColor, slice.sweep * 0.9)),
                        Style.spacing.hairline)
        // Only the disc grows. Scaling the label with it would drift the
        // whole ring of text every time selection moved.
        scale: active ? wheel.selectedScale : 1

        Behavior on color { ColorAnimation { duration: 90 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

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
        color: active ? Color.accent : Color.menu.text
        // Labels name the icon rather than compete with it, so they sit
        // back until the slice is the one selected.
        opacity: active ? 1 : 0.6
        // The disc under it eases; without these the ring of text
        // strobes while the discs glide.
        Behavior on color { ColorAnimation { duration: 90 } }
        Behavior on opacity { NumberAnimation { duration: 90 } }
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
