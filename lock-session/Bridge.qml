import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var peer: null
  property var state: ({ locked: false, requested: false, secure: false })
  property var pending: null
  property int serial: 0
  property bool passwordPamConfigured: false
  readonly property bool locked: !!state.locked || !!(pending && pending.action === "lock")
  readonly property string directory: Quickshell.env("HOME") + "/.local/share/omarchy-custom/lock-session"
  readonly property string socketPath: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-lock-" +
    Quickshell.env("WAYLAND_DISPLAY").replace(/[^a-zA-Z0-9_.-]/g, "_") + ".sock"

  function request(action) {
    if (pending && pending.action === "lock" && action !== "lock") return
    pending = { action: action, serial: Date.now() + "-" + (++serial) }
    if (peer) peer.write(JSON.stringify(pending) + "\n")
    else Qt.callLater(root.launch)
  }

  function launch() {
    if (peer || worker.running || retry.running) return
    worker.running = true
    startup.restart()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  SocketServer {
    id: server
    path: root.socketPath
    active: true
    handler: Socket {
      id: connection
      onConnectedChanged: {
        if (connected) { root.peer = connection; startup.stop() }
        else if (root.peer === connection) {
          root.peer = null
          const recover = root.locked
          root.state = Object.assign({}, root.state, { locked: recover, requested: recover,
            pending: recover, sessionLocked: false, secure: false, authenticating: false })
          retry.restart()
          if (recover) root.request("lock")
          // SocketServer owns its disconnected handlers until the server closes.
          server.active = false
          server.active = true
        }
      }
      parser: SplitParser {
        onRead: data => {
          const message = JSON.parse(data)
          root.state = message.state
          if (root.pending && message.serial === root.pending.serial) root.pending = null
          if (root.pending) connection.write(JSON.stringify(root.pending) + "\n")
        }
      }
    }
  }

  // Detached so restarting the desktop shell cannot kill an active lock.
  // -n also reconnects to an existing worker after a shell crash/restart.
  Process {
    id: worker
    command: ["quickshell", "--no-color", "-n", "-d", "-p", root.directory]
    environment: ({ OMARCHY_LOCK_SESSION: "1", OMARCHY_LOCK_SOCKET: root.socketPath,
                    QS_DISABLE_FILE_WATCHER: "1", QS_NO_RELOAD_POPUP: "1" })
    onExited: code => {
      if (code === 0) return
      root.pending = null
      console.error("Lockscreen worker failed to start: " + code)
    }
  }
  Timer {
    // Let an exiting worker release its singleton before starting a replacement.
    id: retry
    interval: 100
    onTriggered: if (root.pending) root.launch()
  }
  Timer {
    id: startup
    interval: 5000
    onTriggered: if (!root.peer) {
      root.pending = null
      console.error("Lockscreen worker did not connect; check its Quickshell log")
    }
  }
  // A short-lived initial worker performs the existing stranded-lock recovery check.
  Component.onCompleted: Qt.callLater(root.launch)

  IpcHandler {
    target: "lock"
    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      if (!root.locked || (!root.peer && !root.pending)) root.request("lock")
      return "ok"
    }
    function isLocked(): string { return root.locked ? "true" : "false" }
    function status(): string {
      const result = Object.assign({}, root.state)
      result.locked = root.locked
      result.requested = !!result.requested || !!(root.pending && root.pending.action === "lock")
      result.passwordPam = root.passwordPamConfigured
      return JSON.stringify(result)
    }
    function preview(): string { root.request("preview"); return "ok" }
    function hidePreview(): string {
      if (root.peer || root.pending) root.request("hidePreview")
      return "ok"
    }
  }
}
