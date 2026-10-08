const assert = require("node:assert/strict")
const { read, method, keymap } = require("./qml.js")
const { M, wheelSource } = require("./wheel-source.js")

// A panel cannot tell how it was opened, so the wheel answers for it: only the
// panel the wheel put on screen, and only while it is still there.
const opened = {}
const picked = []
const ring = { pluginId: "xpo.wheel", launched: "", launchedAt: -1,
  slices: [{}, {}, {}], get sliceCount() { return this.slices.length },
  select: i => picked.push(i),
  shell: { isPluginOpen: id => opened[id] === true,
           hide: id => { opened[id] = false },
           summon: id => { opened[id] = true } } }
const back = method(read("plugins/xpo.wheel/Wheel.qml"), "back",
  { root: ring, Qt: { callLater: fn => fn() } })
assert.equal(back(), "none", "a wheel that opened nothing owes nothing")
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
assert.equal(back(), "wheel")
assert.equal(opened["omarchy.audio"], true, "the panel stays up until the wheel claims its surface")
assert.equal(opened["xpo.wheel"], true)
opened["omarchy.audio"] = false
opened["omarchy.network"] = true
ring.launched = ""
assert.equal(back(), "none", "a panel opened from the bar keeps its backspace")
ring.launched = "omarchy.audio"
assert.equal(back(), "none", "and one that has since gone is not owed a return")
console.log("ok: only the panel the wheel opened answers backspace with a return")

// `back` can only give back what `run` wrote down.
// Recorded off `slices`, so a slice picked with the pointer is written down the
// same as one picked with the arrows.
const ran = { countUse() {}, dismiss() {}, launchedAt: null,
  slices: [{ plugin: "a" }, { plugin: "b" }, { plugin: "c" }] }
const runPick = method(wheelSource, "run",
  { root: ran, unmap: { running: false }, MenuIndex: M })
runPick(ran.slices[2])
assert.equal(ran.launchedAt, 2, "the slice that was run is written down")
runPick({ plugin: "off-ring" })
assert.equal(ran.launchedAt, -1, "a pick that is on no ring writes down nothing")
console.log("ok: running a slice records which slice it was")

// A pick waits for the unmap, as its target gets no keyboard while the wheel holds it. A panel or
// the browser takes the backdrop over, so only they skip the fade.
const left = []
ran.dismiss = now => left.push(now)
ran.home = "/home/test"
for (const e of [{ plugin: "a" }, { path: "/home/test/a.md" }, { appId: "firefox" }, { address: "0x1" },
                 { path: "/mnt/a.pdf" }, { action: "true" }]) {
  ran.queued = null; runPick(e)
  assert.equal(typeof ran.queued, "function", "a pick ran before the wheel unmapped")
}
assert.deepEqual(left, [true, true, false, false, false, false])
console.log("ok: a pick waits for the unmap, and only a panel or the browser skips the fade")

// A step back hands the ring over the way it was left. Without this the wheel
// comes up with selected at -1 while the comet still rests on the slice that
// launched, so the ring looks selected and the arrows do not step from it --
// right and left jump to the east and west slices instead of to the neighbours.
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
ring.launchedAt = 2; picked.length = 0
assert.equal(back(), "wheel")
assert.deepEqual(picked, [2], "the slice that launched is selected again")
// A search result sits on no ring, so there is no slice to give back.
picked.length = 0
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
ring.launchedAt = -1
assert.equal(back(), "wheel")
assert.deepEqual(picked, [], "a search result restores no selection")
// wheel.json is watched, so the ring can be shorter than when the panel went up.
ring.launched = "omarchy.audio"; opened["omarchy.audio"] = true
ring.launchedAt = 9
assert.equal(back(), "wheel")
assert.deepEqual(picked, [], "a stale index is dropped, not selected")
console.log("ok: backspace gives the ring back the slice it was left on")

// Left and right step one slice, from the first press onward. A fresh wheel has
// nothing selected and rests at the top, so that is what the first step comes
// off -- landing on the east or west slice instead skipped whatever sat between
// it and the top. Nine slices at 40 degrees, odd, so slice 0 is the top one.
function dialAt(count, selected) {
  const seen = []
  const w = { selected, sliceCount: count, searching: false,
    sliceOrigin: count % 2 === 0 ? 90 % (360 / count) : 0,
    get sliceStep() { return 360 / count },
    select(i) { seen.push(i); this.selected = i },
    rotate: null, nearestSlice: null }
  w.nearestSlice = method(wheelSource, "nearestSlice", { root: w })
  w.rotate = method(wheelSource, "rotate", { root: w })
  return { wheel: w, seen, key: keymap("plugins/xpo.wheel/MenuKeys.js", w) }
}
let ring9 = dialAt(9, -1)
ring9.key("Key_Right")
assert.deepEqual(ring9.seen, [1], "right off a fresh ring steps to the next slice")
ring9 = dialAt(9, -1)
ring9.key("Key_Left")
assert.deepEqual(ring9.seen, [8], "and left to the previous one, not to the west slice")
// Then it keeps stepping, and wraps rather than stopping at either end.
ring9 = dialAt(9, 0)
for (let i = 0; i < 3; i++) ring9.key("Key_Right")
assert.deepEqual(ring9.seen, [1, 2, 3], "every press after the first is one slice too")
// Up and down still name a place rather than stepping.
ring9 = dialAt(9, 3)
ring9.key("Key_Up"); assert.equal(ring9.wheel.selected, 0, "up is the top slice")
// An empty ring has nowhere to go, and must not select NaN on the way there.
const empty = dialAt(0, -1)
empty.key("Key_Right")
assert.deepEqual(empty.seen, [], "an empty ring selects nothing at all")
console.log("ok: the ring steps one slice a press, from the top when it is fresh")
