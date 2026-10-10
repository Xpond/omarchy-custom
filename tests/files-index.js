const assert = require("node:assert/strict")
const { library } = require("./qml.js")
const M = library("plugins/xpo.wheel/MenuIndex.js")
const F = library("plugins/xpo.files/FilesIndex.js")

const buffer = bytes => Uint8Array.from(bytes).buffer
const valid = [[], [0], [0x7f], [0xc2, 0x80], [0xdf, 0xbf], [0xe0, 0xa0, 0x80],
  [0xed, 0x9f, 0xbf], [0xef, 0xbb, 0xbf], [0xef, 0xbf, 0xbd], [0xf0, 0x90, 0x80, 0x80],
  [0xf4, 0x8f, 0xbf, 0xbf], [...Buffer.from("café हिन्दी 😀")]]
const invalid = [[0x80], [0xc0, 0xaf], [0xc1, 0xbf], [0xc2], [0xe9, 10],
  [0xe0, 0x9f, 0xbf], [0xed, 0xa0, 0x80], [0xe2, 0x28, 0xa1], [0xe2, 0x82],
  [0xf0, 0x8f, 0xbf, 0xbf], [0xf4, 0x90, 0x80, 0x80], [0xf5, 0x80, 0x80, 0x80], [0xff],
  [...Array(2048).fill(65), 0xe9]]
for (const bytes of valid) assert.equal(F.isUtf8(buffer(bytes)), true, bytes.toString())
for (const bytes of invalid) assert.equal(F.isUtf8(buffer(bytes)), false, bytes.toString())
let seed = 42
function random() { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed }
const decoder = new TextDecoder("utf-8", { fatal: true })
for (let i = 0; i < 2000; i++) {
  const bytes = buffer(Array.from({ length: random() % 16 }, () => random() >>> 24))
  let expected = true
  try { decoder.decode(bytes) } catch { expected = false }
  assert.equal(F.isUtf8(bytes), expected)
}
console.log("ok: complete UTF-8 validation")

// Lines count as wc -l does, plus an unterminated last line.
assert.equal(F.lineLabel(""), "")
assert.equal(F.lineLabel("one"), "1 line")
assert.equal(F.lineLabel("one\ntwo"), "2 lines")
assert.equal(F.lineLabel("one\ntwo\n"), "2 lines")
console.log("ok: line counts")

// git's header goes once a hunk follows; a "\ No newline" note marks its line. Each old line sits above the most
// alike new line, in order: new lines it passes over come first, lines alike to nothing stay alone. The gutter
// numbers lines as the file now has them, and the heading counts what was added and removed.
const diff = F.readableDiff("diff --git a/x b/x\nindex 1..2 100644\n--- a/x\n+++ b/x\n@@ -8,4 +8,5 @@ def f():\n a <b>\n-if (isDir) go()\n-x = head(root.fullText)\n-gone\n\\ No newline at end of file\n+// note\n+if (isFile) go()\n+x = head(root.shownText)\n@@ -98,2 +99,2 @@\n z\n-old\n+new\n")
assert.equal(diff, "@@ -8,4 +8,5 @@ def f():\n a <b>\n+// note\n-if (isDir) go()\n+if (isFile) go()\n-x = head(root.fullText)\n+x = head(root.shownText)\n-gone \uf468\n@@ -98,2 +99,2 @@\n z\n-old\n+new\n")
assert.deepEqual(F.diffNumbers(diff).split("\n"), ["", "8", "9", "", "10", "", "11", "", "", "99", "", "100"])
assert.deepEqual(F.diffStat(diff), [4, 4])
// Hunks become ⋯ breaks carrying git's context; a pair shows what changed in bold, widened to whole words.
const red = t => '<font color="#e06c75">' + t + "</font>", green = t => '<font color="#98c379">' + t + "</font>"
assert.equal(F.styledDiff(diff), ['<font color="#61afef">⋯&#32;def&#32;f():</font>', "&#32;a&#32;&lt;b&gt;",
  green("+//&#32;note"), red("-if&#32;(<b>isDir</b>)&#32;go()"), green("+if&#32;(<b>isFile</b>)&#32;go()"),
  red("-x&#32;=&#32;head(root.<b>fullText</b>)"), green("+x&#32;=&#32;head(root.<b>shownText</b>)"), red("-gone&#32;\uf468"),
  '<font color="#61afef">⋯</font>', "&#32;z", red("-old"), green("+new")].join("<br>"))
const pair = (a, b) => F.styledDiff(F.readableDiff("@@ -1 +1 @@\n" + a + "\n" + b + "\n")).split("<br>").slice(1)
// A save that only adds the last newline: the old line's mark is what changed, not two identical lines.
assert.deepEqual(pair("-end\n\\ No newline at end of file", "+end"), [red("-end<b>&#32;\uf468</b>"), green("+end<b></b>")])
// A change at a word's edge bolds only itself; one inside a word takes the word, on either side.
assert.deepEqual(pair("-  foo,", "+  foo"), [red("-&#32;&#32;foo<b>,</b>"), green("+&#32;&#32;foo<b></b>")])
assert.deepEqual(pair("-x = 1;", "+x = 10;"), [red("-x&#32;=&#32;<b>1</b>;"), green("+x&#32;=&#32;<b>10</b>;")])
// Beyond ASCII everything counts as a word character, so bold never splits an emoji, its skin tone or an accent.
assert.deepEqual(pair("-a 😀", "+a 😃"), [red("-a&#32;<b>😀</b>"), green("+a&#32;<b>😃</b>")])
assert.deepEqual(pair("-👍🏻 ok", "+👍🏽 ok"), [red("-<b>👍🏻</b>&#32;ok"), green("+<b>👍🏽</b>&#32;ok")])
assert.deepEqual(pair("-cafe\u0301", "+cafe"), [red("-<b>cafe\u0301</b>"), green("+<b>cafe</b>")])
// Without a hunk the header is the whole story: grey, unnumbered, uncounted.
const binary = "diff --git a/p b/p\nBinary files a/p and b/p differ\n"
const grey = t => '<font color="#7f848e">' + t + "</font>"
assert.equal(F.readableDiff(binary), binary)
assert.equal(F.styledDiff(binary), grey("diff&#32;--git&#32;a/p&#32;b/p") + "<br>" + grey("Binary&#32;files&#32;a/p&#32;and&#32;b/p&#32;differ"))
assert.equal(F.diffNumbers(binary), "\n")
assert.deepEqual(F.diffStat(binary), [0, 0])
console.log("ok: diffs read old above new, changes in bold, numbered and counted")

// The real git commands on a scratch repository: marks by entry name, folders holding changes, literal names.
const { execFileSync, spawnSync } = require("node:child_process")
const fs = require("node:fs"), os = require("node:os"), path = require("node:path")
const script = path.resolve(__dirname, "../plugins/xpo.files/git-preview.py")
const repo = fs.mkdtempSync(path.join(os.tmpdir(), "files-git-"))
const put = (name, text) => { fs.mkdirSync(path.dirname(path.join(repo, name)), { recursive: true }); fs.writeFileSync(path.join(repo, name), text) }
const git = (...args) => execFileSync("git", ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t",
  "-c", "commit.gpgsign=false", ...args], { stdio: "ignore" })
const run = argv => spawnSync(argv[0], argv.slice(1), { encoding: "utf8" }).stdout
const read = dir => F.readStatus(run(F.statusCommand(dir, script)))
for (const name of ["top.txt", "src/a.js", "src/a*b", "src/axb", "src/deep/b.txt", "src/same.txt", "src/gone.txt"]) put(name, "old\n")
git("init", "-q"); git("add", "."); git("commit", "-qm", "base")
put("src/a.js", "new\n"); put("src/a*b", "new\n"); put("src/axb", "new\n"); put("src/deep/b.txt", "new\n")
put("src/new dir/x", "x"); put("src/fresh.md", "x"); put("src/staged.txt", "x"); git("add", "src/staged.txt")
fs.rmSync(path.join(repo, "src/gone.txt"))
assert.deepEqual({ ...F.changes(read(repo), "") }, { src: "●" })
assert.deepEqual({ ...F.changes(read(repo + "/src"), "") }, { "a.js": "M", "a*b": "M", axb: "M", deep: "●",
  "new dir": "?", "fresh.md": "?", "staged.txt": "A", "gone.txt": "D" })
// One status of a folder also marks inside each of its folders, for their previews.
const text = run(F.statusCommand(repo, script)), status = F.readStatus(text)
assert.deepEqual(F.changes(status, "src"), F.changes(read(repo + "/src"), ""))
assert.deepEqual({ ...F.changes(read(repo + "/src"), "deep") }, { "b.txt": "M" })
assert.deepEqual({ ...F.changes(status, "sr") }, {}, "a folder is not a prefix of its neighbour's name")
// An untracked folder is one entry however large, and its preview unmarked; inside, each entry is marked.
fs.writeFileSync(path.join(repo, ".git/info/exclude"), "*.log\n")
put("src/new dir/skip.log", "x")
for (let i = 0; i < 500; i++) put("src/new dir/tree/" + i + "/f", "x")
assert.equal(run(F.statusCommand(repo, script)), text, "git walked the untracked tree")
assert.deepEqual({ ...F.changes(read(repo + "/src"), "new dir") }, {})
assert.deepEqual({ ...F.changes(read(repo + "/src/new dir"), "") }, { x: "?", tree: "?" })
assert.equal(F.changes(read(repo + "/src/new dir/tree"), "")["499"], "?")
assert.deepEqual({ ...F.changes(read(os.tmpdir()), "") }, {}, "outside a repository")
assert.equal(F.readableDiff(run(F.diffCommand(repo + "/src", "a*b", script))), "@@ -1 +1 @@\n-old\n+new\n", "a*b was read as a glob")
assert.equal(run(F.diffCommand(repo + "/src", "same.txt", script)), "")
assert.match(run(F.diffCommand(repo + "/src", "staged.txt", script)), /^\+x$/m, "staged changes count")
fs.rmSync(repo, { recursive: true })
console.log("ok: git marks and diffs")

// A full-sort reference checks ordering, picks, stable ties, and multi-term matching.
function reference(files, query, limit, uses = {}) {
  const q = query.trim().toLowerCase()
  if (!q) return []
  return files.paths.map((p, i) => ({ p, i, name: p.toLowerCase().replace(/\/$/, "").split("/").pop() }))
    .filter(e => q.split(/\s+/).every(t => e.p.toLowerCase().includes(t)))
    .map(e => ({ ...e, rank: e.name.startsWith(q) ? 0 : e.name.includes(q) ? 1 : 2, used: uses["file:" + e.p] || 0 }))
    .sort((a, b) => a.rank - b.rank || b.used - a.used || (!a.used && a.name.length - b.name.length) || a.i - b.i)
    .slice(0, limit).map(e => M.fileRow(e.p, "/home/test"))
}
const words = ["a", "alpha", "beta", "Wheel.qml", "space name", "éclair", "longer-file"]
const paths = Array.from({ length: 5000 }, (_, i) =>
  "/home/test/" + words[random() % words.length] + "/" + i + "/" + words[random() % words.length]
  + (i % 4 ? "" : "/"))
const files = M.parseFiles(paths.join("\n"))
for (const query of ["", "a", "e", "home", "wheel", " WHEEL ", "a beta", "space name", "é", "zzz",
  "/", "beta/", "a/", "/beta", "1/a"])
  for (const limit of [0, 1, 8, 40, 5001])
    assert.deepEqual(M.fileRows(files, query, limit, "/home/test"), reference(files, query, limit))
// Every ninth path picked, up to three times: a pick leads its rank and never leaves it.
const fileUses = {}
paths.forEach((p, i) => { if (i % 9 === 0) fileUses["file:" + p] = 1 + (i / 9) % 3 })
for (const query of ["a", "e", "wheel", "a beta"])
  for (const limit of [1, 8, 40, 5001])
    assert.deepEqual(M.fileRows(files, query, limit, "/home/test", false, fileUses), reference(files, query, limit, fileUses))
assert.deepEqual(M.fileRows(null, "a", 40, "/home/test"), [])
// Scans parsed apart and joined are the scans parsed together, so a late folder parses only itself.
assert.deepEqual(M.joinFiles(M.parseFiles(paths.slice(0, 3000).join("\n")), M.parseFiles(paths.slice(3000).join("\n"))), files)
assert.equal(M.joinFiles(files, null), files)
console.log("ok: file search ordering, limits and ties")
