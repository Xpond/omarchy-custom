import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// Ranked search results using the ring's visual language.
Item {
  property var wheel: null

  anchors.top: parent.verticalCenter
  anchors.topMargin: wheel.searchHeight / 2 + Style.spacing.panelGap
  anchors.horizontalCenter: parent.horizontalCenter
  // Disable hit testing after the transition back to the ring.
  transformOrigin: Item.Top
  opacity: wheel.searching ? 1 : 0
  scale: wheel.searching ? 1 : 0.96
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: wheel.fadeDuration; easing.type: Easing.OutCubic } }
  width: wheel.searchWidth
  height: resultList.height
  layer.enabled: true
  layer.effect: MultiEffect {
    autoPaddingEnabled: true
    shadowEnabled: true
    shadowColor: "#000000"
    shadowBlur: 1.0
    blurMax: 16
    shadowOpacity: 0.4
    shadowVerticalOffset: Style.space(3)
  }

  ClickShield {}

  Column {
    id: resultList
    anchors.horizontalCenter: parent.horizontalCenter
    width: wheel.resultWidth
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
      model: wheel.beads
      delegate: BorderSurface {
        id: resultCard
        required property int index
        required property var modelData
        readonly property int row: wheel.resultTop + index
        readonly property bool active: wheel.resultIndex === resultCard.row

        width: wheel.resultWidth
        height: wheel.resultHeight
        radius: height / 2
        color: active ? wheel.selectedFill : wheel.surfaceFill
        borderSpec: Border.flat(active ? wheel.cometColor : wheel.surfaceEdge,
                                Style.spacing.hairline)

        Behavior on color { ColorAnimation { duration: 90 } }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          // Ignore synthetic hover moves caused by rows shifting under the cursor.
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
          PanelIcon {
            omarchyPath: wheel.omarchyPath
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.iconLarge
            file: modelData.iconFile || ""
            size: Style.font.iconLarge
            tint: resultCard.active ? Color.accent : Color.menu.text
          }
          // Fall back to the glyph when a themed icon fails to load.
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
            width: Math.min(implicitWidth,
                            Math.max(resultRow.textBudget * 0.4,
                                     resultRow.textBudget - labelText.implicitWidth))
            text: modelData.trail
            color: Color.menu.text
            opacity: 0.45
            // Preserve the filename end of paths and the root of breadcrumbs.
            elide: modelData.path ? Text.ElideLeft : Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
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
