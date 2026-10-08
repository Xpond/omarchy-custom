"""Reactive wheel query, history, launch and menu reload behavior."""
import json


def check(wheel, base, run, block, line):
    # The field and the query are one value both ways, and queryAt is the field's own
    # caret: typing edits from inside, Esc clears from outside, and Ctrl+W places the
    # caret after it assigns the query. The real lines are the fixture.
    run("query-field", '''
  property string query: ""
''' + line(wheel, r"^  property alias queryAt:.*$") + '''
  TextInput {
    id: searchInput
''' + line(wheel, r"^ +text: root\.query$") + line(wheel, r"^ +onTextChanged:.*$") + '''
  }
  Timer { interval: 1; running: true; onTriggered: {
    searchInput.insert(0, "firefox")
    if (root.query !== "firefox") { console.error("FAIL typing missed the query", root.query); Qt.exit(1); return }
    root.query = "fox"; root.queryAt = 1
    if (searchInput.text + "|" + searchInput.cursorPosition !== "fox|1") {
      console.error("FAIL the caret did not land", searchInput.text, searchInput.cursorPosition); Qt.exit(1); return
    }
    root.query = ""
    if (searchInput.text !== "" || root.queryAt !== 0) { console.error("FAIL caret left behind", root.queryAt); Qt.exit(1); return }
    searchInput.insert(0, "a"); root.query = "b"
    if (searchInput.text !== "b") { console.error("FAIL typing cut the field loose", searchInput.text); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')

    # History opens from its own search, so the query clears before the list shows; typing then
    # leaves history for search, while a folder list keeps its typing. The real handlers are the fixture.
    run("history-open", '''
  property string query: "history"
  property string listing: ""
  property int resultIndex: 3
  property int resultTop: 0
''' + block(wheel, r"  onQueryChanged: \{") + "\n" + block(wheel, r"  function edit\(") + '''
  Timer { interval: 1; running: true; onTriggered: {
    root.edit({ setting: "history" })
    if (root.listing + "|" + root.query !== "history|") {
      console.error("FAIL history did not open from its own search", root.listing, root.query); Qt.exit(1); return
    }
    root.query = "l"
    if (root.listing !== "") { console.error("FAIL typing stayed in history"); Qt.exit(1); return }
    root.query = ""; root.listing = "folders"; root.query = "/m"
    if (root.listing !== "folders") { console.error("FAIL typing left a folder list"); Qt.exit(1); return }
    console.log("PASS"); Qt.quit()
  } }
''')

    # A pick runs once the wheel has faded out and unmapped, and a second click during the fade
    # runs nothing. The backdrop goes as the fade starts. The real pick, close, fade and unmap are the fixture.
    run("launch-after-fade", '''
  property bool opened: true
  property bool shown: true
  property var queued: null
  property int fadeDuration: 130
  property var backdrop: []
  property QtObject shell: QtObject {
    function releasePopout(owner) {}
    function hide(id) {}
    function panelSurfaceVisible(shown) { root.backdrop.push(shown) }
  }
  property var slices: []
  property int launchedAt: -1
  property string editing: ""
  property real daylight: 0
  property var copied: []
  property int picks: 0
  function countUse(e) { root.picks++ }
  function copy(text) { root.copied.push(text) }
  function dropScan() {}
''' + "\n".join(block(wheel, pattern) for pattern in [r"  function run\(", r"  function close\(",
                                                      r"  Timer \{\n    id: unmap", r"  function dismiss\(",
                                                      r"  onOpenedChanged: \{"]) + '''
  Timer { interval: 1; running: true; onTriggered: { root.run({ copy: "first" }); root.run({ copy: "second" }) } }
  Timer { interval: 60; running: true; onTriggered: {
    if (root.copied.length || root.backdrop.join() !== "false") {
      console.error("FAIL ran before the wheel unmapped, or kept the backdrop", root.backdrop); Qt.exit(1)
    }
  } }
  Timer { interval: 400; running: true; onTriggered: {
    if (JSON.stringify(root.copied) + root.picks !== '["first"]1') {
      console.error("FAIL", JSON.stringify(root.copied), root.picks); Qt.exit(1)
    } else { console.log("PASS"); Qt.quit() }
  } }
''')

    # A check asked for while one runs has to run once that one ends, with the newer script, and
    # an answer that comes back unchanged must rebuild nothing.
    run("conditions-recheck", '''
  property var menuItems: ({ slow: { label: "Slow", action: "s", when: "sleep 0.3" } })
  property string conditionText: ""
  property int changes: 0
  property int settled: -1
  onConditionsChanged: root.changes++
''' + line(wheel, r"^  readonly property var conditions:.*$") + block(wheel, r"  Process {\n    id: conditionScan")
        + "\n" + block(wheel, r"  function checkConditions\(") + "\n" + line(wheel, r"^  onMenuItemsChanged:.*$") + '''
  Component.onCompleted: root.checkConditions()
  Timer { interval: 100; running: true; onTriggered:
    root.menuItems = MenuIndex.merge(root.menuItems, { quick: { label: "Quick", action: "q", when: "true" } }) }
  Timer { interval: 1200; running: true; onTriggered: {
    if (!root.conditions.when.quick) { console.error("FAIL the check asked mid-run was lost"); Qt.exit(1); return }
    root.settled = root.changes
    root.checkConditions()
  } }
  Timer { interval: 2200; running: true; onTriggered: {
    if (root.changes !== root.settled) { console.error("FAIL an unchanged answer rebuilt"); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
''')

    # Saving the user's menu shows at once, and an entry taken out of it is gone, not merged over.
    menus = base / "menus"
    menus.mkdir()
    (menus / "default.jsonc").write_text('{"system": {"label": "System"}, "system.lock": {"label": "Lock", "action": "l"}}')
    (menus / "user.jsonc").write_text('{"notes": {"label": "Notes", "action": "n"}}')
    default_menu = block(wheel, r'  FileView {\n    path: root\.omarchyPath \+ "/default/omarchy/omarchy-menu\.jsonc"')
    user_menu = block(wheel, r'  FileView {\n    path: Quickshell\.env\("HOME"\) \+ "/\.config/omarchy/extensions/omarchy-menu\.jsonc"')
    run("menu-reload", '''
  property var defaultMenu: ({})
  property var userMenu: ({})
  property string lockText: ""
''' + line(wheel, r"^  readonly property var menuItems:[^\n]*\n.*$")
        + default_menu.replace('root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"', json.dumps(str(menus / "default.jsonc")))
        + "\n" + user_menu.replace('Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"', json.dumps(str(menus / "user.jsonc"))) + '''
  FileView { id: editor; path: ''' + json.dumps(str(menus / "user.jsonc")) + '''; atomicWrites: true }
  Timer { interval: 400; running: true; onTriggered: {
    if (!root.menuItems.notes || !root.menuItems["system.lock"]) { console.error("FAIL menus did not load"); Qt.exit(1); return }
    editor.setText('{"todo": {"label": "Todo", "action": "t"}}')
  } }
  Timer { interval: 1400; running: true; onTriggered: {
    var ids = Object.keys(root.menuItems).sort().join(" ")
    if (ids !== "system system.lock todo") { console.error("FAIL", ids); Qt.exit(1) }
    else { console.log("PASS"); Qt.quit() }
  } }
''')
