import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// The ring unrolled: the ranked list the wheel shows the moment anything is
// typed. Beads rather than a card of rows -- the same disc fill, hairline and
// capsule the slices wear, so the two modes are one surface language and the
// swap between them is not a jump to a second kind of thing.
Item {
  id: root

  // The wheel, for the results and the selection. Passed rather than reached
  // for, the way the browser's own components take their panel.
  property var wheel: null

  // Off the surface's center rather than the pill's edge: the pill is
  // inside the dial's layer, and anchors don't cross between parents.
  // Dead center is where the pill sits by construction.
  anchors.top: parent.verticalCenter
  anchors.topMargin: wheel.searchHeight / 2 + Style.spacing.panelGap
  anchors.horizontalCenter: parent.horizontalCenter
  // Grown from its top edge, which is pinned just under the pill, so the
  // beads read as falling out of the field rather than swelling from
  // their own middle. Rows carry MouseAreas, so a faded stack must go
  // properly invisible or it keeps catching clicks over the ring.
  transformOrigin: Item.Top
  opacity: wheel.searching ? 1 : 0
  scale: wheel.searching ? 1 : 0.96
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }
  // The field's width, not the beads'. The margin they gave up when they
  // stepped down a size is exactly where the rail goes.
  width: wheel.searchWidth
  height: resultList.height
  // One pass over the whole stack, the way the dial shadows its discs in
  // one: each bead lands with its own falloff, and the layer re-renders
  // at the new size every time the query changes the row count. Layering
  // does not block the rows' mouse input -- only how they are painted.
  layer.enabled: true
  layer.effect: MultiEffect {
    autoPaddingEnabled: true
    shadowEnabled: true
    shadowColor: "#000000"
    shadowBlur: 1.0
    // Tighter than the dial's, which is cast by discs small enough to
    // carry a wide falloff. On a bead this wide the same one reads as a
    // skirt hanging off the bottom edge rather than as depth.
    blurMax: 16
    shadowOpacity: 0.4
    shadowVerticalOffset: Style.space(3)
  }

  // Ahead of the rows, so their own areas still take the clicks that
  // land on them and this catches only the gaps between the beads.
  ClickShield {}

  Column {
    id: resultList
    anchors.horizontalCenter: parent.horizontalCenter
    width: wheel.resultWidth
    // Wide enough that the beads read as separate objects on the scrim.
    // At a hairline they fuse into one slab with lines ruled across it.
    spacing: Style.spacing.md

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: wheel.results.length === 0
      text: wheel.emptyText
      color: Color.menu.text
      opacity: 0.5
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
    }

    Repeater {
      // The window, not the list: eight delegates exist however deep the
      // ranked list runs behind them.
      model: wheel.beads
      delegate: BorderSurface {
        id: resultCard
        required property int index
        required property var modelData
        // `index` counts beads on screen; the selection counts rows in
        // the list. Everything a row does has to cross that offset.
        readonly property int row: wheel.resultTop + index
        readonly property bool active: wheel.resultIndex === resultCard.row

        width: wheel.resultWidth
        height: wheel.resultHeight
        radius: height / 2
        // The disc's two fills, on a hairline either way. A full-weight
        // ring works around a disc because a disc is small; drawn this
        // wide it is a stroke long enough to outweigh the word inside
        // it. Selection is carried by the accent, not by line weight.
        color: active ? wheel.selectedFill : wheel.surfaceFill
        borderSpec: Border.flat(active ? wheel.cometColor : wheel.surfaceEdge,
                                Style.spacing.hairline)

        Behavior on color { ColorAnimation { duration: 90 } }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          // positionChanged, not entered: retyping a query re-lays the rows
          // out under a cursor that has not moved, and `entered` fires on
          // every row that slides beneath it -- which drags the selection
          // around mid-keystroke and leaves you unsure what Return will run.
          // Real pointer motion is the only thing that should claim it.
          onPositionChanged: function (mouse) {
            if (wheel.hoverMoved(mapToItem(null, mouse.x, mouse.y))) wheel.resultIndex = resultCard.row
          }
          onClicked: wheel.run(wheel.results[resultCard.row])
        }

        Row {
          id: resultRow
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.rowPaddingX
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.rowPaddingX
          spacing: Style.spacing.controlGap

          // What the label and the breadcrumb share, once the icon and
          // the two gaps are paid for. A window title is arbitrary text --
          // a terminal's is a whole command line -- so without a budget
          // one row draws straight through the edge of the card.
          readonly property real textBudget:
            Math.max(0, width - Style.font.iconLarge - spacing * 2 - chevron.width)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: (!modelData.appIcon || appImage.status === Image.Error) && !modelData.iconFile
            width: Style.font.iconLarge
            text: modelData.icon
            color: active ? Color.accent : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.iconLarge
          }
          // The same marks the ring loads, at row size.
          PanelIcon {
            omarchyPath: wheel.omarchyPath
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.iconLarge
            file: modelData.iconFile || ""
            size: Style.font.iconLarge
            tint: resultCard.active ? Color.accent : Color.menu.text
          }
          // Apps and windows name an icon file and keep a glyph behind
          // it: a themed icon that fails to load used to leave a hole the
          // size of itself. One of the three draws, and a Row skips the rest.
          Image {
            id: appImage
            anchors.verticalCenter: parent.verticalCenter
            visible: !!modelData.appIcon && status !== Image.Error
            width: Style.font.iconLarge
            height: Style.font.iconLarge
            source: modelData.appIcon ? wheel.appLibrary.iconSource(modelData.appIcon) : ""
            sourceSize.width: Style.font.iconLarge
            sourceSize.height: Style.font.iconLarge
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
          Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, resultRow.textBudget - trailText.width)
            elide: Text.ElideRight
            text: modelData.label
            color: active ? Color.accent : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
          Text {
            id: trailText
            anchors.verticalCenter: parent.verticalCenter
            // Whatever the label leaves, but never squeezed below a share
            // of its own -- a breadcrumb that elides to nothing is noise.
            width: Math.min(implicitWidth,
                            Math.max(resultRow.textBudget * 0.4,
                                     resultRow.textBudget - labelText.implicitWidth))
            text: modelData.trail
            color: Color.menu.text
            opacity: 0.45
            // A breadcrumb reads from the left -- Install › Package --
            // so it loses its tail. A path reads from the right: which
            // of four `src` directories this is, is the part nearest the
            // name, and eliding that end says nothing at all.
            elide: modelData.path ? Text.ElideLeft : Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
          // A category is not a command: picking it turns the ring into
          // its contents. The chevron is what says so before Return.
          Text {
            id: chevron
            anchors.verticalCenter: parent.verticalCenter
            width: modelData.node ? implicitWidth + parent.spacing : 0
            visible: !!modelData.node
            text: "\u203a"
            color: active ? Color.accent : Color.menu.text
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  // The same rail the files panel runs beside its own list, for the same
  // reason: eight beads under a query that matched forty is otherwise a
  // list with no bottom, and nothing on screen says the ninth exists. It
  // rides in the width the beads gave up, so nothing moves to make room.
  Rectangle {
    readonly property int span: Math.max(1, wheel.results.length - wheel.resultCap)
    visible: wheel.results.length > wheel.resultCap
    anchors.right: parent.right
    width: Style.space(2)
    radius: width / 2
    color: Util.alpha(Color.menu.text, 0.18)
    height: resultList.height * wheel.resultCap / wheel.results.length
    y: wheel.resultTop / span * (resultList.height - height)
  }
}
