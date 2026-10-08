"""Selection regressions driven by the wheel's actual QML change handlers."""


def check(wheel, run, block):
    common = '''
  property bool opened: true
  property bool armed: false
  property bool justOpened: false
  property string query: ""
  readonly property bool searching: query.length > 0
  property int selected: -1
  property int resultIndex: 0
  property int resultTop: 0
  property int resultCap: 8
  property var previousSlices: []
  property var previousResults: []
  property string previousQuery: ""
  property real arcTarget: 0
  property string ran: ""
  property var failures: []
  property var menuItems: ({
    system: { label: "System" },
    "system.suspend": { label: "Suspend", when: "toggle", action: "suspend" },
    "system.logout": { label: "Logout", checked: "default", action: "logout" },
    "system.reboot": { label: "Reboot", action: "reboot" }
  })
  property string conditionText: "system.suspend:w\\n"
  readonly property var conditions: MenuIndex.parseConditions(root.conditionText, root.menuItems)
  readonly property var slices: MenuIndex.childrenOf(root.menuItems, "system", root.conditions)
  readonly property var results: MenuIndex.search(MenuIndex.menuRows(root.menuItems, root.conditions), root.query, 40, {})
  QtObject { id: spin; function stop() {} }
  QtObject { id: unmap; property bool running: false }
  function sliceAngle(i) { return i * 90 }
  function dismiss() {}
  function run(e) { if (e) root.ran = e.action || "" }
  function expect(ok, message) { if (!ok) root.failures = root.failures.concat([message]) }
  function finish() {
    if (root.failures.length) { console.error("FAIL", JSON.stringify(root.failures)); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  }
'''
    common += "\n".join(block(wheel, r"  function " + name + r"\(") for name in
                        ["commit", "select", "showResult", "moveResult"])
    common += "\n" + "\n".join(block(wheel, r"  " + name + r": \{") for name in
                                ["onSlicesChanged", "onResultsChanged", "onQueryChanged"])

    run("refresh-ring-selection", common + '''
  Timer { interval: 50; running: true; onTriggered: {
    root.select(1)
    root.conditionText = "system.logout:c\\n"
  } }
  Timer { interval: 100; running: true; onTriggered: {
    root.justOpened = true; root.commit()
    root.expect(root.ran === "logout", "refresh changed Logout into Reboot")
    root.expect(root.selected === 0 && root.armed, "selection did not follow the surviving action")
    root.ran = ""
    root.menuItems = MenuIndex.merge(root.menuItems, { "system.logout": {
      label: "Logout", action: "changed-command" } })
  } }
  Timer { interval: 150; running: true; onTriggered: {
    root.justOpened = true; root.commit()
    root.expect(!root.ran && root.selected === -1, "a replaced action stayed selected")
    root.select(root.slices.length - 1)
    root.menuItems = { system: {label: "System"} }
  } }
  Timer { interval: 200; running: true; onTriggered: {
    root.justOpened = true; root.commit()
    root.expect(!root.ran && root.selected === -1, "removed final slice remained selected")
    // A later release belongs to the press that closes the wheel, whichever lands first.
    root.select(0)
    root.expect(root.commit() === "dismissed" && !root.ran, "a later release fired the selection")
    unmap.running = true; root.justOpened = true
    root.expect(root.commit() === "closed" && !root.ran, "a release during the close fade fired")
    root.finish()
  } }
''')

    run("refresh-search-selection", common + '''
  Timer { interval: 50; running: true; onTriggered: {
    root.query = "system"
    root.resultIndex = root.results.findIndex(function(e) { return e.id === "system.logout" })
    root.conditionText = "system.logout:c\\n"
  } }
  Timer { interval: 100; running: true; onTriggered: {
    root.run(root.results[root.resultIndex])
    root.expect(root.ran === "logout", "search refresh changed its selected action")
    root.ran = ""
    root.menuItems = { system: {label: "System"}, "system.reboot": {label: "Reboot", action: "reboot"} }
  } }
  Timer { interval: 150; running: true; onTriggered: {
    root.run(root.results[root.resultIndex])
    root.expect(!root.ran && root.resultIndex === -1, "removing a result silently picked its neighbor")
    root.moveResult(1)
    root.expect(root.resultIndex === 0, "down did not pick the first row after removal")
    root.resultIndex = -1
    root.moveResult(-1)
    root.expect(root.resultIndex === root.results.length - 1, "up did not pick the last row after removal")
    root.query = "reboot"
  } }
  Timer { interval: 200; running: true; onTriggered: {
    root.expect(root.resultIndex === 0 && root.results[0].action === "reboot", "a new query did not select its first result")
    root.finish()
  } }
''')
