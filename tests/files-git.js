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
const status = dir => run(F.statusCommand(dir, script))
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
  const clean = F.changes(status(repo))
  assert.equal(clean.constructor, undefined)
  assert.equal(clean.__proto__, undefined)
  put("constructor", "new\n"); put("__proto__", "new\n")
  const changed = F.changes(status(repo))
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
  assert.deepEqual(F.withDeleted([], status(repo), repo, "gone folder/deep", false), [row])
  const live = { name: "gone.txt", path: repo + "/gone.txt", isDir: false }
  assert.equal(F.withDeleted([live], status(repo), repo, "", true).filter(e => e.name === live.name).length, 1)
  const hidden = "\n D .hidden\0 D .folder/x\0"
  assert.equal(F.withDeleted([], hidden, repo, "", false).length, 0)
  assert.equal(F.withDeleted([], hidden, repo, "", true).length, 2)
  console.log("ok: new files, unborn HEAD, literal names and deleted folders have diffs")
} finally { fs.rmSync(repo, { recursive: true, force: true }) }

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
