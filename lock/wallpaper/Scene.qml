import QtQuick
import QtQuick.Effects

// Wallpaper: the current background, blurred, as on Omarchy's own lock screen.
Item {
  id: root

  // The lock screen's view (LockView.qml): which wallpaper, and whether to load it.
  property Item host

  // Fades out while the lock releases, so the wait reads as unlocking.
  function play() { fade.stop(); opacity = 1 }
  function leave() { fade.start() }

  NumberAnimation { id: fade; target: root; property: "opacity"; to: 0; duration: 1100 }

  Image {
    id: wallpaper
    anchors.fill: parent
    // Each path segment encoded; the version reloads a wallpaper changed while locked.
    source: host.loadBackground && host.backgroundPath
      ? "file://" + host.backgroundPath.split("/").map(encodeURIComponent).join("/") + "?v=" + host.backgroundVersion
      : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    sourceSize.width: width
    sourceSize.height: height
  }

  MultiEffect {
    anchors.fill: wallpaper
    source: wallpaper
    autoPaddingEnabled: false
    blurEnabled: wallpaper.status === Image.Ready
    blur: 1.0
    blurMax: 128
    blurMultiplier: 1.25
    contrast: -0.08
  }
}
