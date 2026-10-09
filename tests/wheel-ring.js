const assert = require("node:assert/strict")
const { method, keymap } = require("./qml.js")
const { M, wheelSource, binding, derive } = require("./wheel-source.js")
const shift = 1 << 25, ctrl = 1 << 26

// The ring holds what search finds, by the keys picks are counted under, so a hand-written list of
// panel and menu ids still reads. A row with no key of its own (a window, a file, an answer) or a
// setting cannot join it, and a key that names nothing is dropped.
{
  const index = [...M.panelRows(M.panels({ "omarchy.audio": true, "omarchy.network": true })),
    { id: "system", node: "system", icon: "x", label: "System", kind: M.KIND.menu },
    { appId: "firefox.desktop", appIcon: "firefox", label: "Firefox", kind: M.KIND.app, keywords: "firefox" },
    { label: "Firefox", address: "0x1", kind: M.KIND.window, keywords: "firefox" },
    { label: "notes.md", path: "/home/test/notes.md" }, { label: "42", copy: "42" },
    ...M.settingRows("SUPER + A", false, [], M.SKIPPED, 0, true)]
  assert.deepEqual(index.filter(M.pinnable).map(M.keyOf),
    ["omarchy.audio", "omarchy.network", "omarchy.clipboard", "system", "app:firefox.desktop"])
  assert.deepEqual(M.ringOf(index, ["app:firefox.desktop", "omarchy.clipboard", "gone", "setting:ring",
                                    "system", "omarchy.audio"]).map(r => r.label),
    ["Firefox", "Clipboard", "System", "Audio"])
  // The editor's search lists only what a ring can hold, and a sigil opens no other source there.
  const finder = { editingRing: true, query: "/fire", term: "fire", index, resultLimit: 40, uses: {} }
  finder.mode = binding("mode", { root: finder, MenuIndex: M })
  assert.deepEqual(binding("results", { root: finder, MenuIndex: M }).map(r => r.appId || r.address), ["firefox.desktop"],
    "the ring editor offered what a ring cannot hold")
  finder.editingRing = false; finder.mode = ""
  assert.equal(binding("results", { root: finder, MenuIndex: M }).length, 2)
  // A bare `/` lists the files picked before, latest first, and nothing else.
  const bare = { listing: "", mode: "file", term: "", resultLimit: 40, home: "/home/test",
    uses: { "file:/home/test/a": 1, "system.lock": 3, "file:/home/test/b/": 1 } }
  assert.deepEqual(binding("results", { root: bare, MenuIndex: M }).map(r => r.path), ["/home/test/b/", "/home/test/a"])
  // `/` search hands the wheel's picks over: a file opened before leads a shorter name.
  const picker = { listing: "", mode: "file", term: "a", resultLimit: 40, home: "/home/test",
    files: M.parseFiles("/home/test/ab\n/home/test/abc\n"), uses: { "file:/home/test/abc": 1 } }
  assert.deepEqual(binding("results", { root: picker, MenuIndex: M }).map(r => r.label), ["abc", "ab"])

  // The editor edits the ring as drawn, saving each change; the bar's ring is where a first edit starts.
  const saved = []
  const disk = { raw: '{ "other": 1 }', text() { return this.raw }, setText(raw) { this.raw = raw; saved.push(raw) } }
  const ed = { index, ringIds: null, selected: 0, query: "fire", path: ["system"], editingRing: false, resetAsked: true,
    panels: M.panels({ "omarchy.audio": true, "omarchy.network": true }),
    get ring() { return this.ringIds ? M.ringOf(this.index, this.ringIds) : this.panels },
    get slices() { return this.ring }, get sliceCount() { return this.ring.length },
    select(i) { this.selected = i }, enter(node) { this.path = []; this.query = ""; this.selected = -1 },
    countUse() { throw new Error("adding to the ring counted a pick") },
    dismiss() { throw new Error("the ring editor closed the wheel") } }
  const scope = { root: ed, ringFile: disk, MenuIndex: M, unmap: { running: false } }
  for (const name of ["edit", "run", "pin", "unpin", "moveSlice", "resetRing", "saveRing"])
    ed[name] = method(wheelSource, name, scope)
  derive(ed, "ringKeys")
  const ring = () => ed.ring.map(M.keyOf).join(" ") + " @" + ed.selected
  const written = () => JSON.parse(saved.at(-1))

  ed.edit({ setting: "ring" })
  assert.deepEqual([ed.editingRing, ed.resetAsked, ed.path, ed.query], [true, false, [], ""])
  assert.equal(ring(), "omarchy.audio omarchy.network omarchy.clipboard @-1", "the editor did not start from the bar")
  ed.select(0); ed.query = "fire"
  ed.run(index[4])
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network omarchy.clipboard @1",
    "a pick did not land after the selected slice")
  assert.deepEqual(written(), { other: 1, slices: ["omarchy.audio", "app:firefox.desktop", "omarchy.network",
                                                 "omarchy.clipboard"] }, "the file lost what else it held")
  assert.equal(ed.query, "", "a pick left the query up")
  ed.select(3); ed.run(ed.ring[0])
  assert.equal(ring() + " " + saved.length, "omarchy.audio app:firefox.desktop omarchy.network omarchy.clipboard @0 1",
    "a slice already on the ring was added twice")
  ed.select(-1); ed.run(index[3])
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network omarchy.clipboard system @4",
    "with nothing selected a pick did not go last")
  ed.moveSlice(1)
  assert.equal(ring(), "system app:firefox.desktop omarchy.network omarchy.clipboard omarchy.audio @0",
    "past the last slice a move did not wrap to the first")
  ed.moveSlice(-1); ed.moveSlice(-1)
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network system omarchy.clipboard @3")
  ed.unpin(); ed.unpin()
  assert.equal(ring(), "omarchy.audio app:firefox.desktop omarchy.network @2", "del did not keep its place")
  assert.deepEqual(written().slices, ["omarchy.audio", "app:firefox.desktop", "omarchy.network"])

  // Ctrl+R asks once and acts on the second; an emptied ring follows the bar as well.
  const writes = saved.length
  ed.resetRing()
  assert.equal(ed.resetAsked + " " + saved.length, "true " + writes, "ctrl+r acted on the first press")
  ed.resetRing()
  assert.deepEqual([ed.ringIds, ed.resetAsked, written()], [null, false, { other: 1 }])
  ed.resetRing()
  assert.equal(ed.resetAsked + " " + saved.length, "false " + (writes + 1), "the bar's ring asked to be reset")
  ed.select(-1); ed.run(index[3]); ed.select(0)
  ed.unpin(); ed.unpin(); ed.unpin(); ed.unpin()
  assert.deepEqual([ed.ringIds, written()], [null, { other: 1 }], "an emptied ring did not follow the bar")

  // A slice hidden for now, by a condition or a row not loaded yet, keeps its place through every
  // edit; once nothing is drawn, the ring follows the bar.
  ed.ringIds = ["omarchy.audio", "hidden", "omarchy.network"]; ed.select(0)
  ed.moveSlice(1); ed.select(-1); ed.run(index[3]); ed.unpin()
  assert.deepEqual(written().slices, ["omarchy.network", "hidden", "omarchy.audio"], "an edit dropped a hidden slice")
  ed.unpin(); ed.unpin()
  assert.equal(ed.ringIds, null, "a ring that draws nothing did not follow the bar")
}

// In the ring editor Del, Shift+arrows and Esc belong to the ring until a query is typed, and then
// to the field. Ctrl+R's question is taken back by any key but a modifier on its way to Ctrl+R.
{
  const did = []
  const ringed = { editingRing: true, resetAsked: false, query: "", queryAt: 0,
    get searching() { return this.query.length > 0 },
    unpin: () => did.push("unpin"), moveSlice: step => did.push("move " + step),
    resetRing() { did.push("reset") }, rotate: step => did.push("rotate " + step),
    up: () => false, dismiss: () => did.push("dismiss") }
  const ringKey = keymap("plugins/xpo.wheel/MenuKeys.js", ringed)
  ringKey("Key_Delete"); ringKey("Key_Right", shift); ringKey("Key_Left", shift); ringKey("Key_Right")
  assert.deepEqual(did.splice(0), ["unpin", "move 1", "move -1", "rotate 1"])
  ringed.query = "fi"
  for (const [key, modifiers] of [["Key_Delete", 0], ["Key_Left", shift], ["Key_Right", shift]])
    assert.equal(ringKey(key, modifiers).accepted, false, key + " left the field while typing")
  ringKey("Key_Escape")
  assert.deepEqual([ringed.query, ringed.editingRing], ["", true], "esc on a query left the editor")
  ringKey("Key_R", ctrl); ringed.resetAsked = true
  ringKey("Key_Control", ctrl); ringKey("Key_R", ctrl)
  assert.deepEqual([did.splice(0), ringed.resetAsked], [["reset", "reset"], true], "a modifier took the question back")
  ringKey("Key_A", 0, "a")
  assert.equal(ringed.resetAsked, false, "another key left ctrl+r armed")
  ringKey("Key_Escape")
  assert.deepEqual([ringed.editingRing, did], [false, []], "esc did not leave the editor, or closed the wheel")
}
console.log("ok: the ring takes what search finds, and its editor adds, moves, removes and goes back to the bar")
