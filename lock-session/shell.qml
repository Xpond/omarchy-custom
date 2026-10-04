import QtQuick
import Quickshell
import Quickshell.Io
import "Lock" as Lock

ShellRoot {
  id: root
  readonly property var service: host.item
  property var pending: null
  property var channel: null
  property string serial: ""
  readonly property string snapshot: service ? JSON.stringify({
    state: JSON.parse(service.statusText), serial: serial
  }) : ""
  readonly property bool idle: service && service.strandedLockResolved && !service.locked &&
    !service.previewVisible && !service.waking && !pending

  function publish() {
    if (channel && channel.connected && snapshot) { channel.write(snapshot + "\n"); channel.flush() }
  }
  function connect() {
    if (channel) channel.destroy()
    channel = connection.createObject(root)
    publish()
  }
  function dispatch() {
    if (!service || !pending) return
    if (pending.action === "lock" && !service.passwordPamConfigured) return
    if (pending.action === "lock") {
      if (!service.locked) service.beginLock()
      service.previewVisible = false
    } else if (pending.action === "preview") {
      if (!service.locked) {
        service.refreshBackground()
        service.refreshFingerprintStatus()
        service.previewVisible = true
      }
    } else if (pending.action === "hidePreview") service.previewVisible = false
    serial = pending.serial
    pending = null
  }
  onSnapshotChanged: publish()
  onServiceChanged: dispatch()
  onIdleChanged: { if (idle) retire.restart(); else retire.stop() }

  Lock.Service { id: host }
  Connections {
    target: root.service
    function onPasswordPamConfiguredChanged() { root.dispatch() }
  }
  Component {
    id: connection
    Socket {
      path: Quickshell.env("OMARCHY_LOCK_SOCKET")
      connected: true
      onConnectedChanged: if (connected) root.publish()
      parser: SplitParser {
        onRead: data => {
          const message = JSON.parse(data)
          if (message.serial === root.serial) return
          root.pending = message
          root.dispatch()
        }
      }
    }
  }
  Component.onCompleted: connect()
  Timer {
    interval: 250
    repeat: true
    running: !root.channel || !root.channel.connected
    onTriggered: root.connect()
  }
  // Let the final wake command finish and flush the unlocked state before exit. Saying goodbye
  // first lets the bridge hang up on reading it, so only a crash logs the close as an error.
  Timer {
    id: retire
    interval: 250
    onTriggered: {
      if (!root.idle) return
      if (root.channel && root.channel.connected) {
        root.channel.write('{"bye":true}\n'); root.channel.flush(); root.channel.connected = false
      }
      Qt.quit()
    }
  }
}
