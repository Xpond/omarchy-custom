// Ranking and preview equivalence. Run: node tests/files-performance.js
const assert = require("node:assert/strict")
const { library } = require("./qml.js")
const F = library("plugins/xpo.files/FilesIndex.js")

// Independent stable-sort reference, including missing dates and tied metadata.
const entries = Array.from({ length: 2000 }, (_, i) => ({
  name: ["alpha", "zAlpha", "éclair", "हिन्दी", "Alpha", "same"][i % 6] + (i % 31),
  isDir: i % 5 === 0, size: i % 17,
  modified: [null, "invalid", "2026-01-01", new Date("2025-02-03"), 0][Math.floor(i / 5) % 5]
}))
const time = value => (value && new Date(value).getTime()) || 0
for (const order of ["name", "date", "size"])
  for (const query of ["", "  ALPHA ", "a", "é", "हिन्दी", "absent"]) {
    const q = query.trim().toLowerCase()
    const expected = entries.filter(e => e.name.toLowerCase().includes(q)).sort((a, b) => {
      if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
      const rank = e => e.name.toLowerCase().startsWith(q) ? 0 : 1
      const primary = order === "date" ? time(b.modified) - time(a.modified)
        : order === "size" && !a.isDir ? b.size - a.size : rank(a) - rank(b)
      return primary || a.name.localeCompare(b.name)
    })
    assert.deepEqual(F.matching(F.ordered(entries, order), query, order), expected)
  }
const original = entries.slice()
F.ordered(entries, "date")
assert.deepEqual(entries, original, "sorting does not reorder the snapshot")

for (const count of [0, 1, 2, 499, 500, 501, 1000, 100000])
  for (const separator of ["\n", "\r\n"])
    for (const suffix of ["", separator, separator + separator]) {
      const text = Array(count).fill("a").join(separator) + suffix
      for (const limit of [0, 1, 2, 500]) {
        const parts = text.split("\n")
        const lines = parts.length - (parts.at(-1) === "" ? 1 : 0)
        const expected = lines <= limit ? text : parts.slice(0, limit).join("\n") + "\n…"
        assert.equal(F.head(text, limit), expected)
      }
    }
// The gutter numbers every line the preview shows, blank ones included, and nothing for no text.
assert.deepEqual(["", "a", "a\n\nb"].map(F.numbers), ["", "1", "1\n2\n3"])
console.log("ok: all file sort orders, stable ties, Unicode and bounded preview parity")

// Pin the mapped fields independently of preview equivalence.
const mapped = [
  { fileName: "notes.txt", filePath: "/tmp/notes.txt", fileIsDir: false, fileSize: "1024", fileModified: null },
  { fileName: "Folder", filePath: "/tmp/Folder", fileIsDir: 1, fileSize: undefined, fileModified: "invalid" }
]
const model = { count: mapped.length, get: (i, field) => mapped[i][field] }
assert.deepEqual(F.snapshot(model), [
  { name: "notes.txt", path: "/tmp/notes.txt", isDir: false, size: 1024, modified: null },
  { name: "Folder", path: "/tmp/Folder", isDir: true, size: 0, modified: "invalid" }
])
assert.deepEqual(F.snapshot(model, 1), [
  { name: "notes.txt", path: "/tmp/notes.txt", isDir: false, size: 1024, modified: null }
])

// At 80 characters two 38-character columns fit, filled down before across.
const preview = [
  { name: "Folder", isDir: true, size: 999, modified: new Date(2026, 0, 2) },
  { name: "notes.txt", isDir: false, size: 1024, modified: null },
  { name: "another-very-long-name.txt", isDir: false, size: 12, modified: "invalid" },
  { name: "last", isDir: false, size: 0, modified: null }
]
const folder = "󰉋  " + "Folder".padEnd(19) + "     " + "  " + " 2 Jan 26"
const notes = "󰈔  " + "notes.txt".padEnd(19) + " 1.0K" + "  " + "         "
const clipped = "󰈔  another-very-long-…" + "  12B" + "  " + "         "
const last = "󰈔  " + "last".padEnd(19) + "   0B" + "  " + "         "
assert.deepEqual(F.columns([], 2, 80, 4), [])
assert.deepEqual(F.columns(preview, 2, 80, 4), [folder + "\n" + notes, clipped + "\n" + last])
assert.deepEqual(F.columns(preview, 2, 80, 3), [folder + "\n" + notes, clipped + "\n…"])
assert.deepEqual(F.columns(preview, 1, 38, 4), [[folder, notes, clipped, last].join("\n")])
// A long name is cut short of an emoji rather than between its two halves.
assert.equal(F.clip("a".repeat(16) + "😀😀", 18), "a".repeat(16) + "…")
assert.equal(F.clip("a".repeat(15) + "😀😀", 18), "a".repeat(15) + "😀…")
// Where a folder holds changes every row keeps room after its name for git's mark, drawn over it
// from a column of its own, so sizes and dates still line up.
const marks = { Folder: "●", "notes.txt": "M" }
assert.deepEqual(F.columns(preview, 1, 38, 4, marks)[0].split("\n"),
  ["󰉋  " + "Folder".padEnd(17) + "  " + "     " + "  " + " 2 Jan 26",
   "󰈔  " + "notes.txt".padEnd(17) + "  " + " 1.0K" + "  " + "         ",
   "󰈔  another-very-lon…" + "  " + "  12B" + "  " + "         ",
   "󰈔  " + "last".padEnd(17) + "  " + "   0B" + "  " + "         "])
const room = " ".repeat(2 + 17 + 1)
assert.deepEqual(F.markColumns(preview, 1, 38, 4, marks), [room + "●\n" + room + "M\n\n"])
assert.deepEqual(F.markColumns(preview, 2, 80, 3, marks).map(c => c.split("\n").length), [2, 1], "marks split as the rows do")
assert.deepEqual(F.columns(preview, 1, 38, 4, {}), F.columns(preview, 1, 38, 4), "no marks, no room kept")
// A click finds the entry drawn at its column and line, and nothing on the overflow mark or past it.
for (const [rows, chars, limit] of [[2, 80, 4], [2, 80, 3], [1, 38, 4], [3, 80, 4]]) {
  const drawn = F.columns(preview, rows, chars, limit).map(c => c.split("\n"))
  drawn.forEach((lines, column) => lines.concat([""]).forEach((text, line) => {
    const e = F.columnEntry(preview, rows, chars, limit, column, line)
    assert.equal(e ? F.row(e, F.shape(Math.min(4, limit), rows, chars)[1], false) : "", text === "…" ? "" : text,
      "column " + column + " line " + line + " of " + rows + " rows, limit " + limit)
  }))
  assert.equal(F.columnEntry(preview, rows, chars, limit, -1, 0), null)
  assert.equal(F.columnEntry(preview, rows, chars, limit, 0, -1), null)
}

for (const count of [0, 1, 399, 400, 401, 2000]) {
  let reads = 0
  const model = { count, get(i, field) {
    reads++
    const e = entries[i]
    return ({ fileName: e.name, filePath: "/tmp/" + e.name, fileIsDir: e.isDir,
      fileSize: e.size, fileModified: e.modified })[field]
  } }
  const capped = F.snapshot(model, 401)
  assert.equal(reads, Math.min(count, 401) * 5)
  const full = F.snapshot(model)
  assert.equal(full.length, count, "main listing remains complete")
  for (const rows of [1, 12, 40])
    for (const width of [20, 80, 150])
      assert.deepEqual(F.columns(capped, rows, width, 400), F.columns(full, rows, width, 400))
}
console.log("ok: capped folder preview preserves every column and overflow marker")
