// Git edge cases use real repositories; missing entries must stay safe to browse.
const assert = require("node:assert/strict")
const fs = require("node:fs"), os = require("node:os"), path = require("node:path")
const { spawnSync } = require("node:child_process")
const { library, read, method } = require("./qml.js")
const F = library("plugins/xpo.files/FilesIndex.js")
const script = path.resolve(__dirname, "../plugins/xpo.files/git-preview.py")
const repo = fs.mkdtempSync(path.join(os.tmpdir(), "files-git-edges-"))
function run(argv, codes = [0]) {
  const r = spawnSync(argv[0], argv.slice(1), { encoding: "utf8" })
  assert.ok(codes.includes(r.status), r.error || r.stderr)
  return r.stdout
}
const git = (...args) => run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t",
  "-c", "commit.gpgsign=false", ...args])
const status = dir => F.readStatus(run(F.statusCommand(dir, script)))
const diff = (dir, name) => F.readableDiff(run(F.diffCommand(dir, name, script), [0, 1]))
function put(name, text = "old\n") {
  fs.mkdirSync(path.dirname(path.join(repo, name)), { recursive: true })
  fs.writeFileSync(path.join(repo, name), text)
}
try {
  git("init", "-q")
  put("first.txt", "first\n"); git("add", ".")
  assert.equal(diff(repo, "first.txt"), "@@ -0,0 +1 @@\n+first\n", "unborn HEAD")
  put("first.txt", "edited before commit\n")
  assert.match(diff(repo, "first.txt"), /^\+edited before commit$/m)
  for (const name of ["gone.txt", "gone folder/deep/a*b", "constructor", "__proto__"]) put(name)
  git("add", "."); git("commit", "-qm", "base")
  for (const name of ["fresh.txt", "a*b", "a ' $(touch injected).txt"]) {
    put(name, "new\n")
    assert.equal(diff(repo, name), "@@ -0,0 +1 @@\n+new\n", name)
  }
  assert.equal(fs.existsSync(path.join(repo, "injected")), false)
  const clean = F.changes(status(repo), "")
  assert.equal(clean.constructor, undefined)
  assert.equal(clean.__proto__, undefined)
  put("constructor", "new\n"); put("__proto__", "new\n")
  const changed = F.changes(status(repo), "")
  assert.equal(changed.constructor, "M")
  assert.equal(changed.__proto__, "M")
  fs.unlinkSync(path.join(repo, "gone.txt"))
  fs.rmSync(path.join(repo, "gone folder"), { recursive: true })
  const gone = F.withDeleted([], status(repo), repo, "", false)
  assert.equal(gone.find(e => e.name === "gone.txt").missing, true)
  assert.equal(gone.find(e => e.name === "gone folder").isDir, true)
  const nested = repo + "/gone folder/deep"
  const row = F.withDeleted([], status(nested), nested, "", false)[0]
  assert.equal(row.name, "a*b")
  assert.equal(row.path, nested + "/a*b")
  assert.equal(row.missing, true)
  assert.equal(diff(nested, row.name), "@@ -1 +0,0 @@\n-old\n")
  assert.deepEqual(F.withDeleted([], status(repo + "/gone folder"), repo + "/gone folder", "deep", false), [row])
  const live = { name: "gone.txt", path: repo + "/gone.txt", isDir: false }
  assert.equal(F.withDeleted([live], status(repo), repo, "", true).filter(e => e.name === live.name).length, 1)
  const hidden = F.readStatus("\n D .hidden\0 D .folder/x\0")
  assert.equal(F.withDeleted([], hidden, repo, "", false).length, 0)
  assert.equal(F.withDeleted([], hidden, repo, "", true).length, 2)
  console.log("ok: new files, unborn HEAD, literal names and deleted folders have diffs")
} finally { fs.rmSync(repo, { recursive: true, force: true }) }

// Deleted rows arrive with git's status, when a selection may already rest on a live row; they must not move it.
const live = [{ name: "b.txt", isDir: false, size: 2 }, { name: "src", isDir: true, size: 0 }]
const late = F.readStatus("\n D a.txt\0 D old/x\0")
for (const order of ["name", "date", "size"]) {
  const before = F.ordered(live, order), after = F.ordered(F.withDeleted(live, late, "/r", "", false), order)
  assert.deepEqual(after.slice(0, before.length), before, order + ": a deleted row moved a live one")
  assert.deepEqual(after.slice(before.length).map(e => e.name), ["old", "a.txt"], order)
}
console.log("ok: deleted rows follow the live ones, so their arrival moves no selection")

// A status is read once; a folder selected after reads only its own part, so moving through the
// list stays instant however many changes the repository holds.
const many = Array.from({ length: 60000 }, (_, i) => " D node_modules/p" + (i % 600) + "/f" + i + ".js")
const big = F.readStatus("\n" + many.join("\0") + "\0"), start = Date.now()
for (let i = 0; i < 100; i++)
  for (const name of ["node_modules", "src"]) { F.changes(big, name); F.withDeleted([], big, "/r", name, false) }
assert.ok(Date.now() - start < 250, "selecting a folder read the whole status again")
assert.equal(F.changes(big, "").node_modules, "●")
assert.equal(F.withDeleted([], big, "/r", "node_modules", false).length, 600)
console.log("ok: one status read serves every folder selected after it")

const n = 2000, old = [], now = []
for (let i = 0; i < n; i++) { old.push("-  oldItem" + i + " = true;"); now.push("+  newItem" + i + " = true;") }
const large = "@@ -1," + n + " +1," + n + " @@\n" + old.join("\n") + "\n" + now.join("\n") + "\n"
assert.equal(F.readableDiff(large), large, "large replacement blocks retain unified order")
assert.deepEqual(F.diffStat(F.readableDiff(large)), [n, n])
assert.equal(F.diffNumbers(large).split("\n").at(-1), String(n))
console.log("ok: large diffs preserve every line without quadratic pairing")

const calls = [], e = { name: "gone", path: "/tmp/gone", missing: true, isDir: false }
const panel = { sel: e, editing: false, diffMode: false, enter: p => calls.push(p) }
const ops = { held: null, doomed: "", note() {}, run: () => calls.push("operation") }
const scope = { root: ops, panel, opener: {}, doomArmed: { restart() {} } }
for (const name of ["hold", "remove", "activate"])
  ops[name] = method(read("plugins/xpo.files/FilesOps.qml"), name, scope)
ops.hold(e, true); ops.hold(e, false); ops.remove(); ops.remove(); ops.activate(e)
assert.equal(ops.held, null)
assert.equal(ops.doomed, "")
assert.deepEqual(calls, [])
assert.equal(panel.diffMode, true, "Enter on a deleted file opens its diff")
e.isDir = true; ops.activate(e)
assert.deepEqual(calls, [e.path], "deleted folders remain navigable")
const root = { sel: e, editing: false, naming: "" }
method(read("plugins/xpo.files/Files.qml"), "beginRename", { root })()
assert.equal(root.naming, "")
console.log("ok: deleted rows cannot copy, move, rename or trash missing paths")
