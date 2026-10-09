import QtQuick
import Quickshell.Io

// A collector belongs to one request. Cancelled requests may still finish their streams.
Item {
  id: root
  signal finished(string output, int code)
  property var current: null

  function cancel() {
    var old = root.current
    root.current = null
    if (old) old.running = false
  }

  function start(command) {
    root.cancel()
    root.current = request.createObject(root, { command: command })
    root.current.running = true
  }

  Component {
    id: request
    Process {
      id: job
      stdout: StdioCollector { id: output }
      onExited: function (code) {
        if (root.current === job) {
          root.current = null
          root.finished(output.text, code)
        }
        job.destroy()
      }
    }
  }
}
