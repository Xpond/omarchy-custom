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
