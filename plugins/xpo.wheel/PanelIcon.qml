import QtQuick

// Load first-party panel marks that have no glyph equivalent.
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
