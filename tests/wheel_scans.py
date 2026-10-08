"""Scan cancellation, epochs and incremental joins in the wheel."""
import json


def check(wheel, run, block):
    # A wheel's scan state around the real walks, with `fd` swapped for scans that say which
    # epoch asked for them. Everything else -- the epoch, the guards, the join -- is production code.
    handlers = wheel[wheel.index("  property int scanEpoch:"):wheel.index(
        "  // Omarchy's menu re-checks its rows on every open")]

    def scan(seconds, folder_seconds="0.05", folders="[]"):
        out = """
  property bool opened: true
  property string mode: ""
  property string listing: ""
  property var files: null
  property var folders: """ + folders + """
  property real daylight: 0
  property string editing: ""
  function paths() { return root.files ? JSON.stringify(root.files.paths) : "null" }
""" + block(wheel, r"  component FileScan: Process \{") + "\n"
        for name, wait in [("home", seconds), ("folder", folder_seconds)]:
            command = ["sh", "-c", "sleep " + wait + '; printf "/epoch-%s/' + name + '\\n" "$1"', "scan"]
            out += "  FileScan { id: " + name + "Scan; command: " + json.dumps(command)[:-1] + ", String(epoch)] }\n"
        return out + handlers

    run("scan-close-reopen", scan("0.15") + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 30; running: true; onTriggered: {
    root.opened = false; root.opened = true; root.scanFiles()
  } }
  Timer { interval: 600; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-1/home"]') { console.error("FAIL stale scan", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")
    run("scan-close", scan("5") + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 30; running: true; onTriggered: root.opened = false }
  Timer { interval: 500; running: true; onTriggered: {
    if (root.files !== null || homeScan.running) { console.error("FAIL retained scan"); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # The skip list's suggestions are home's scanned folders, so showing it scans home as `/` does,
    # and leaves the added folders unscanned.
    run("scan-skip-list", scan("0.05", "0.05", '["/x"]') + """
  Component.onCompleted: root.listing = "skipped"
  Timer { interval: 400; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-0/home"]') { console.error("FAIL the skip list scanned", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # Subfolders are listed only while a path is typed into the folders list: a model with no
    # folder lists the working directory and watches it.
    run("subfolders-on-demand", """
  property string listing: ""
  property string query: ""
""" + block(wheel, r"  readonly property var subfolderPaths:") + "\n"
        + block(wheel, r"  Loader \{\n    id: subfolders") + """
  Timer { interval: 300; running: true; onTriggered: {
    if (subfolders.item || root.subfolderPaths.length) { console.error("FAIL listed", root.subfolderPaths); Qt.exit(1) }
    root.listing = "folders"; root.query = "/us"
  } }
  Timer { interval: 900; running: true; onTriggered: {
    if (root.subfolderPaths.indexOf("/usr") < 0) { console.error("FAIL /", root.subfolderPaths); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # A folder that lands first waits for home rather than showing alone, and joins it when home lands.
    run("scan-folder-first", scan("0.6", "0.05", '["/x"]') + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 400; running: true; onTriggered: {
    if (root.paths() !== 'null') { console.error("FAIL early", root.paths()); Qt.exit(1) }
  } }
  Timer { interval: 1600; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-0/home","/epoch-0/folder"]') { console.error("FAIL late", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")

    # A finished scan is the open's own: reopening scans again, and home's new paths never show
    # beside the last open's folder paths.
    run("scan-done-reopen", scan("0.05", "0.3", '["/x"]') + """
  Component.onCompleted: root.mode = "file"
  Timer { interval: 600; running: true; onTriggered: { root.opened = false; root.opened = true; root.scanFiles() } }
  Timer { interval: 800; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-1/home"]') { console.error("FAIL reopened", root.paths()); Qt.exit(1) }
  } }
  Timer { interval: 1400; running: true; onTriggered: {
    if (root.paths() !== '["/epoch-1/home","/epoch-1/folder"]') { console.error("FAIL rescanned", root.paths()); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
""")
