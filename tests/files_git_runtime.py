"""Git request ownership, deleted-directory navigation, and bounded diff preparation."""
import json
import shutil
import subprocess


def check(repo, files, base, run, block, line):
    shutil.copyfile(repo / "plugins/xpo.files/FilesGitProcess.qml", base / "FilesGitProcess.qml")
    # A real pipe has bytes buffered before cancellation. Wait for the producer's marker.
    helper = base / "slow-diff.py"
    helper.write_text("""import pathlib, sys, time
name = sys.argv[3]
if name == 'empty.txt':
    sys.exit()
print('@@ -1 +1 @@' + chr(10) + '-old' + chr(10) + '+' + name, flush=True)
if name == 'old.txt':
    pathlib.Path(sys.argv[2], 'ready').touch()
    time.sleep(1)
""")
    for replacement in [False, True]:
        ready = base / "ready"
        ready.unlink(missing_ok=True)
        run("git-cancel-" + str(replacement), '''
  property string listedDir: ''' + json.dumps(str(base)) + '''
  property string gitScript: ''' + json.dumps(str(helper)) + '''
  property var settledSel: ({name: 'old.txt', isDir: false})
  property var changes: ({'old.txt': 'M', 'next.txt': 'M'})
  property bool showsImage: false
  property string diffText: ""
  property bool diffLoading: false
  property bool switched: false
''' + block(files, r"^  FilesGitProcess \{\n    id: differ") + block(files, r"^  function readDiff\(") + '''
  FileView {
    path: root.listedDir + '/ready'
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (root.switched) return
      root.switched = true
      root.settledSel = ({name: ''' + ("'next.txt'" if replacement else "'clean.txt'") + ''', isDir: false})
      root.diffText = ''
      root.readDiff()
      finish.start()
    }
  }
  Timer { id: finish; interval: 1200; onTriggered: {
    var expected = ''' + ("'@@ -1 +1 @@\\n-old\\n+next.txt\\n'" if replacement else "''") + '''
    if (root.diffText !== expected) { console.error('FAIL stale diff', root.diffText); Qt.exit(1); return }
    console.log('PASS'); Qt.quit()
  } }
  Component.onCompleted: root.readDiff()
''')

    run("git-pairing-budget", '''
  Timer { interval: 0; running: true; onTriggered: {
    var n = 2000, old = [], now = []
    for (var i = 0; i < n; i++) { old.push('-  oldItem'+i+' = true;'); now.push('+  newItem'+i+' = true;') }
    var diff = '@@ -1,'+n+' +1,'+n+' @@\\n'+old.join('\\n')+'\\n'+now.join('\\n')+'\\n'
    var start = Date.now(), actual = FilesIndex.readableDiff(diff), elapsed = Date.now()-start
    if (actual !== diff || elapsed > 500) { console.error('FAIL pairing', elapsed); Qt.exit(1); return }
    console.log('PASS pairing milliseconds', elapsed); Qt.quit()
  } }
''')

    preview = files[files.index("  readonly property string previewPath:"):files.index("  // Highlight the whole settled")]
    run("git-large-preview", '''
  property var settledSel: null
  property int previewLimit: 262144
  property bool showsImage: false
  property bool diffMode: true
  property bool editing: false
  property string diffText: '@@ -1 +1 @@\\n-old\\n+new\\n'
  property bool diffLoading: false
  property string settledPath: ''
  property string imageDims: ''
  property var dirEntries: []
  property var saving: null
  property string previewHtml: ''
  function readDiff() { diffText = '@@ -1 +1 @@\\n-old\\n+new\\n' }
  QtObject { id: preview; property int paneHeight: 600; function resetScroll() {} }
  QtObject { id: measurer; property bool running: false; property var command: [] }
''' + preview.replace("Style.font.subtitle", "14") + line(files, r"^  readonly property bool showsDiff: .*")
        + block(files, r"^  onSettledSelChanged: \{").replace("Style.font.subtitle", "14") + '''
  Timer { interval: 0; running: true; onTriggered: {
    root.settledSel = ({name: 'large.txt', path: '/tmp/large.txt', size: 280000, isDir: false})
    if (root.previewPath || root.previewText !== root.diffText || root.shownLines < 2) {
      console.error('FAIL large preview', root.shownLines, root.previewText); Qt.exit(1); return
    }
    root.settledSel = ({name: 'gone.txt', path: '/tmp/gone.txt', size: 0, isDir: false, missing: true})
    if (root.previewPath || root.previewText !== root.diffText) { console.error('FAIL deleted preview'); Qt.exit(1); return }
    console.log('PASS'); Qt.quit()
  } }
''')

    # With the diff on, a changed file waits blank for its diff rather than show its contents or a note
    # first, sampled between events as a frame would be; a diff that comes back empty gives the file back.
    for name in ["wait.txt", "empty.txt"]:
        (base / name).write_text("contents\n")
    segment = lambda first, last: files[files.index(first):files.index(last)]
    run("git-diff-waits", '''
  property string listedDir: ''' + json.dumps(str(base)) + '''
  property string gitScript: ''' + json.dumps(str(helper)) + '''
  property var changes: ({'wait.txt': 'M', 'empty.txt': 'M'})
  property var settledSel: null
  property int previewLimit: 262144
  property bool showsImage: false
  property bool diffMode: true
  property bool editing: false
  property string settledPath: ''
  property string imageDims: ''
  property var dirEntries: []
  property var saving: null
  property string previewHtml: ''
  property var seen: []
  QtObject { id: preview; property int paneHeight: 600; function resetScroll() {} }
  QtObject { id: measurer; property bool running: false; property var command: [] }
''' + preview.replace("Style.font.subtitle", "14")
        + segment("  readonly property bool showsMarkdown:", "  readonly property string previewPath:")
        + line(files, r"^  readonly property bool showsCode: .*")
        + segment("  property string diffText:", "  onDiffModeChanged:")
        + segment("  readonly property string previewBody:", "  onSelChanged:")
        + block(files, r"^  onSettledSelChanged: \{").replace("Style.font.subtitle", "14")
        + segment("  readonly property string previewNote:", "  // Payloads may choose")
        + block(files, r"^  FileView \{\n    id: previewFile") + '''
  function shown() {
    return root.previewNote ? 'note' : root.previewText && root.previewText === root.fullText ? 'file'
      : root.previewText ? 'diff' : root.previewBody ? 'markup' : 'blank'
  }
  Timer { interval: 1; repeat: true; running: !!root.settledSel; onTriggered: {
    if (root.seen[root.seen.length - 1] !== root.shown()) root.seen.push(root.shown())
  } }
  function pick(name) { root.seen = []; root.settledSel = ({name: name, path: root.listedDir + '/' + name, size: 9, isDir: false}) }
  Timer { interval: 50; running: true; onTriggered: { root.pick('wait.txt'); next.start() } }
  Timer { id: next; interval: 700; onTriggered: {
    if (root.seen.join() !== 'blank,diff') { console.error('FAIL before the diff', root.seen.join()); Qt.exit(1); return }
    root.pick('empty.txt'); done.start()
  } }
  Timer { id: done; interval: 700; onTriggered: {
    if (root.seen.join() !== 'blank,file') { console.error('FAIL empty diff', root.seen.join()); Qt.exit(1); return }
    console.log('PASS'); Qt.quit()
  } }
''')

    directory = base / "git-tree"
    (directory / "gone/deep").mkdir(parents=True)
    (directory / "gone/deep/a.txt").write_text("removed\n")
    def commit(where):
        for args in [["init", "-q"], ["add", "."], ["commit", "-qm", "base"]]:
            subprocess.run(["git", "-C", str(where), "-c", "user.name=t", "-c", "user.email=t@t",
                            "-c", "commit.gpgsign=false", *args], check=True, capture_output=True)
    commit(directory)
    shutil.rmtree(directory / "gone")
    start = files.index('  property string status:')
    end = files.index('  // Fill folder previews', start)
    run("git-deleted-navigation", '''
  property bool shown: true
  property string listedDir: ''' + json.dumps(str(directory)) + '''
  property bool showHidden: false
  property var entries: []
  property string query: ''
  property string order: 'name'
  property var settledSel: null
  property bool showsImage: false
  property bool diffMode: true
  property bool editing: false
  property int stage: 0
  QtObject { id: preview; function resetScroll() {} }
''' + files[start:end].replace('Qt.resolvedUrl("git-preview.py")', json.dumps(str(repo / "plugins/xpo.files/git-preview.py")))
        + "".join(line(files, p) for p in [r"^  readonly property var listedEntries: .*", r"^  readonly property var orderedEntries: .*",
                                           r"^  readonly property var rows: .*"])
        + block(files, r"^  FolderListModel \{\n    id: folder") + '''
  Component.onCompleted: root.readChanges()
  Timer { interval: 50; running: true; repeat: true; onTriggered: {
    if (root.stage < 2) {
      if (!root.rows.length) return
      var name = root.stage === 0 ? 'gone' : 'deep'
      var e = root.rows[0]
      if (e.name !== name || !e.isDir || !e.missing) { console.error('FAIL folder', JSON.stringify(e)); Qt.exit(1); return }
      root.stage++; root.listedDir = e.path
    } else if (root.stage === 2) {
      if (!root.rows.length) return
      root.settledSel = root.rows[0]
      root.readDiff(); root.stage++
    } else if (root.diffText) {
      if (root.settledSel.name !== 'a.txt' || root.diffText !== '@@ -1 +0,0 @@\\n-removed\\n') {
        console.error('FAIL deletion', root.diffText); Qt.exit(1); return
      }
      console.log('PASS'); Qt.quit()
    }
  } }
''')

    # Backing out lands straight on the folder just left, sampled between events as a frame would be.
    # A deleted folder arrives only with git's status, after the parent's rows: nothing is selected until
    # then, rather than the top row first. A key pressed meanwhile wins; a folder that never arrives, as a
    # hidden one, gives the top row back once the status is in. A folder slow to list, its status quick
    # (ignored, and asked for at once), still gets the status after its rows.
    tree = base / "up-tree"
    for name in ["a/f", "b/f", "gone/f", ".hid/f", "wide/aaa/f", "wide/sub/f"]:
        (tree / name).parent.mkdir(parents=True)
        (tree / name).write_text("x\n")
    for i in range(20000):
        (tree / "wide" / str(i)).touch()
    (tree / ".gitignore").write_text("wide/\n")
    commit(tree)
    shutil.rmtree(tree / "gone")
    run("git-up-lands", '''
  property bool shown: true
  property string home: ''' + json.dumps(str(base)) + '''
  readonly property string tree: ''' + json.dumps(str(tree)) + '''
  property string dir: root.tree
  property bool showHidden: false
  property string order: 'name'
  property var entries: []
  property var settledSel: null
  property bool showsImage: false
  property bool diffMode: false
  property bool editing: false
  QtObject { id: preview; function resetScroll() {} }
  QtObject { id: list; property QtObject view: QtObject { function positionViewAtIndex(i, mode) {} } }
''' + files[files.index("  // A leading / or ~ enters"):files.index("  property bool showHidden:")]
        + files[start:end].replace('Qt.resolvedUrl("git-preview.py")', json.dumps(str(repo / "plugins/xpo.files/git-preview.py")))
                          .replace("interval: 60", "interval: 1")
        + "".join(line(files, p) for p in [r"^  readonly property var listedEntries: .*", r"^  readonly property string query: .*",
                                           r"^  readonly property var orderedEntries: .*", r"^  readonly property var rows: .*"])
        + files[files.index("  readonly property var sel:"):files.index("  // Debounce preview work")]
        + files[files.index("  // A one-shot selection"):files.index("  function close()")]
        + files[files.index("  // Empty while the preview"):files.index("  // Payloads may choose")]
        + "".join(block(files, p) + "\n" for p in [r"^  FolderListModel \{\n    id: folder", r"^  function enter\(",
                                                   r"^  function up\(", r"^  function move\(", r"^  onRowsChanged: \{"]) + '''
  property var cases: [{ from: 'gone', want: 'gone' }, { from: 'a', want: 'a' }, { from: '.hid', want: 'a' },
                       { from: 'gone', key: 1, want: 'a' }, { from: 'gone', key: -1, want: 'wide' },
                       { from: 'wide/sub', want: 'sub' }]
  property int at: 0
  property bool left: false
  property bool pressed: false
  property real arrived: 0
  property var seen: []
  Timer { interval: 1; running: true; repeat: true; onTriggered: {
    var c = root.cases[root.at], name = root.sel ? root.sel.name : '', from = root.tree + '/' + c.from
    if (!root.left) {
      if (root.dir !== from) { root.dir = from; return }
      if (!root.rows.length) return
      root.left = true; root.pressed = false; root.arrived = 0; root.seen = []
      root.up(); return
    }
    if (name && name !== root.seen[root.seen.length - 1]) root.seen.push(name)
    if (root.pending && root.previewNote) { console.error('FAIL the preview said ' + root.previewNote + ' while landing'); Qt.exit(1); return }
    if (c.key && !root.pressed && root.rows.length) { root.pressed = true; root.move(c.key) }
    if (!root.arrived && root.status) root.arrived = Date.now()
    if (!root.arrived || Date.now() - root.arrived < 30) return
    if (root.seen.join() !== c.want) {
      console.error('FAIL backing out of ' + c.from + (c.key ? ' with a key' : '') + ' selected ' + root.seen.join())
      Qt.exit(1); return
    }
    root.left = false
    if (++root.at === root.cases.length) { console.log('PASS'); Qt.quit() }
  } }
''')
