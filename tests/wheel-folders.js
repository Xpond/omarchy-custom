const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { method, keymap } = require("./qml.js")
const { M, wheelSource, binding } = require("./wheel-source.js")

// Until a list changes, `/` scans home as it always has; folders outside home get a scan of their own,
// and a skip with a slash anchors under home, so only home's scan takes it. Run against fd itself.
{
  const home = "/home/test"
  assert.equal(M.scanCommand([home], M.SKIPPED, home).join(" "),
    "fd --hidden --max-depth 6 --exclude .cache --exclude .git --exclude node_modules . /home/test")
  const tree = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "wheel-scan-"))
  for (const name of ["home/.claude/CLAUDE.md", "home/Android/x", "home/Music [old]/x", "home/p/node_modules/m",
                      "home/1/2/3/4/5/6/deep", "mnt/Android/x"])
    fs.mkdirSync(path.dirname(path.join(tree, name)), { recursive: true }), fs.writeFileSync(path.join(tree, name), "")
  const found = [[tree + "/home"], [tree + "/mnt"]].map(roots => M.scanCommand(roots, ["node_modules", "~/Android", "~/Music [old]"], tree + "/home"))
    .map(command => require("node:child_process").execFileSync(command[0], command.slice(1),
      { encoding: "utf8", env: { ...process.env, XDG_CONFIG_HOME: tree } })).join("")
  assert.deepEqual(found.split("\n").filter(Boolean).map(p => p.slice(tree.length)).sort(),
    ["/home/.claude/", "/home/.claude/CLAUDE.md", "/home/1/", "/home/1/2/", "/home/1/2/3/", "/home/1/2/3/4/",
     "/home/1/2/3/4/5/", "/home/1/2/3/4/5/6/", "/home/p/", "/mnt/Android/", "/mnt/Android/x"])
  fs.rmSync(tree, { recursive: true })

  // Typing suggests: names and folders under home to skip, from the scan, and subfolders outside home to
  // search. A name starts with what is typed, and is offered once however many folders share it.
  const files = M.parseFiles(["/home/test/Android/", "/home/test/Android/README", "/mnt/android/", "/home/test/p/target/",
    "/home/test/q/target/", "/home/test/targets/", "/home/test/star/", "/home/test/target.txt", "/mnt/target/"].join("\n"))
  assert.deepEqual(M.fileRows(files, "andr", 40, home, true).map(r => r.path), ["/home/test/Android/"])
  assert.deepEqual(M.nameRows(files, "tar", 40, home).map(r => r.label + " " + r.trail), ["target anywhere", "targets anywhere"])
  assert.deepEqual(M.nameRows(files, "andr", 40, home).map(r => r.label), ["Android"], "a name from outside home was offered")
  assert.deepEqual(M.subfolderRows(["/home", "/media", "/mnt", "/home/test/x"], "/m", home).map(r => r.path), ["/media/", "/mnt/"])
  assert.deepEqual(M.subfolderRows(["/home"], "/", home).concat(M.subfolderRows(["/home/test/x"], "/home/test/", home)), [],
    "home, or a folder in or around it, was offered")
  assert.deepEqual([M.listEntry("/home/test/Android/", home), M.listEntry("/mnt/share/", home)], ["~/Android", "/mnt/share"])

  // Enter adds the suggestion picked, once; Del removes and the next entry takes the place; an emptied
  // list is its default again. Each change is saved, and the rest of wheel.json stays.
  const saved = []
  const disk = { raw: '{ "slices": ["system"] }', text() { return this.raw }, setText(raw) { this.raw = raw; saved.push(JSON.parse(raw)) } }
  const ls = { query: "", listing: "", savedFolders: null, savedSkipped: null, resultIndex: 0, resultLimit: 40, home, files,
    subfolderPaths: ["/mnt"], get folders() { return this.savedFolders || [] }, get skipped() { return this.savedSkipped || M.SKIPPED },
    get listed() { return this.listing === "skipped" ? this.skipped : this.folders },
    get results() { return binding("results", { root: this, MenuIndex: M }) }, drops: 0, dropScan() { this.drops++ }, scanFiles() {} }
  for (const name of ["edit", "addEntry", "removeEntry", "saveList"]) ls[name] = method(wheelSource, name, { root: ls, ringFile: disk, MenuIndex: M })
  ls.query = "wheely"; ls.edit({ setting: "skipped" })
  assert.deepEqual([ls.query, ls.results.map(r => r.label + r.trail)], ["", [".cacheanywhere", ".gitanywhere", "node_modulesanywhere"]])
  ls.query = "andr"
  assert.deepEqual(ls.results.map(r => r.label + " " + (r.path || r.trail)), ["Android anywhere", "Android /home/test/Android/"],
    "a skip was offered that is no folder under home")
  ls.addEntry(ls.results[1]); ls.query = "tar"; ls.addEntry(ls.results[0])
  ls.resultIndex = 1; ls.removeEntry()
  assert.deepEqual([ls.results.map(r => r.label), ls.resultIndex, saved.at(-1)],
    [[".cache", "node_modules", "~/Android", "target"], 1,
     { slices: ["system"], skipped: [".cache", "node_modules", "~/Android", "target"] }])
  assert.equal(ls.drops, 3, "a saved list kept the old scan")
  ls.edit({ setting: "folders" })
  ls.query = "/m"; ls.addEntry(ls.results[0]); ls.query = "/m"; ls.addEntry(ls.results[0])
  assert.deepEqual(saved.at(-1).folders, ["/mnt"], "a folder was added twice")
  ls.resultIndex = 0; ls.removeEntry()
  assert.equal("folders" in saved.at(-1), false, "an emptied list did not go back to its default")
  // Typed into a list, `/` is a path, not file search; an untyped list still shows, and the empty folders list says why.
  assert.equal(binding("mode", { root: { listing: "folders", query: "/mnt" }, MenuIndex: M }), "")
  assert.equal(binding("searching", { root: { listing: "skipped", query: "" } }), true, "an empty list editor hid its list")
  assert.equal(binding("emptyText", { root: { listing: "folders", query: "" } }), "Home is always searched")

  // Del and Esc are the list's until something is typed.
  const did = []
  const listed = { listing: "folders", query: "/mn", queryAt: 0, results: [], resultIndex: 0, removeEntry: () => did.push("remove"),
    get searching() { return binding("searching", { root: this }) } }
  const listKey = keymap("plugins/xpo.wheel/MenuKeys.js", listed)
  assert.equal(listKey("Key_Delete").accepted, false, "del left the field while typing")
  listKey("Key_Escape")
  listKey("Key_Delete"); listKey("Key_Escape")
  assert.deepEqual([did, listed.listing], [["remove"], ""], "del or esc missed the list")
}
console.log("ok: file search scans as before until its lists change, and its lists suggest, add and remove")
