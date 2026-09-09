import QtQuick

// The mark a first-party panel draws in the bar, loaded from the panel that
// owns it. Tailscale's and Dropbox's are QML components rather than glyphs, so
// there is no character to fall back to and no honest answer but to load them.
Loader {
  property string omarchyPath
  property string file
  property real size
  property color tint
  active: !!file
  source: file ? omarchyPath + "/shell/plugins/panels/" + file : ""
  onLoaded: {
    item.iconSize = Qt.binding(function () { return size })
    item.color = Qt.binding(function () { return tint })
  }
}
