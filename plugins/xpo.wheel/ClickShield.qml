import QtQuick

// A surface that is not scrim. Clicks land here and stop, rather than reaching
// the full-screen area underneath -- which reads a press as "clicked away" and
// closes the wheel, taking the query with it. Neither place it shields is
// clickable in any other sense -- the field always holds the keyboard -- so
// there is deliberately no hover state and no cursor: advertising an
// interaction that does not exist is worse than silence. Left button only, so
// right-click still falls through to dismiss.
MouseArea {
  anchors.fill: parent
  acceptedButtons: Qt.LeftButton
}
