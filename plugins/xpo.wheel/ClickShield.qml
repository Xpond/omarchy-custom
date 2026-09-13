import QtQuick

// Keep left-clicks from reaching the dismiss surface; right-click still dismisses.
MouseArea {
  anchors.fill: parent
  acceptedButtons: Qt.LeftButton
}
