// The pointer selects the slice it moves to, once it has travelled past the arming threshold; scrolling
// steps the ring or pages results; a right click, or any click while searching, dismisses, and a left
// click runs the slice under it, or dismisses off the ring.
const assert = require("node:assert/strict")
const { wheelSource } = require("./wheel-source.js")

const area = wheelSource.match(/^    MouseArea \{\n      anchors\.fill: parent\n[^]*?^    \}/m)[0]
const handler = (name, root) => new Function("root", "Qt", "return " +
  area.match(new RegExp("^      " + name + ": (function \\(\\w+\\) \\{[^]*?^      \\})", "m"))[1])(root, { RightButton: 2 })
const calls = []
const root = { searching: false, armed: false, originX: -1, originY: -1, moveThreshold: 10, slices: ["s0", "s1", "s2"],
  sliceAt: (x, y) => x < 0 ? -1 : x % 3, select: i => calls.push("select " + i), run: s => calls.push("run " + s),
  dismiss: () => calls.push("dismiss"), rotate: s => calls.push("rotate " + s), moveResult: s => calls.push("page " + s) }

const moved = handler("onPositionChanged", root)
for (const [x, y] of [[50, 50], [55, 55], [56, 58]]) moved({ x, y })
root.armed = true; moved({ x: 58, y: 58 })
root.searching = true; moved({ x: 100, y: 100 }); root.searching = false
assert.deepEqual(calls.splice(0), ["select 2", "select 1"],
  "the pointer selected before it moved past the threshold, or after search took over")

const scrolled = handler("onWheel", root)
scrolled({ angleDelta: { y: 120 } }); scrolled({ angleDelta: { y: -120 } })
root.searching = true; scrolled({ angleDelta: { y: -120 } }); root.searching = false
assert.deepEqual(calls.splice(0), ["rotate -1", "rotate 1", "page 1"])

const clicked = handler("onClicked", root)
for (const [button, x] of [[2, 1], [1, 0], [1, -5]]) clicked({ button, x, y: 0 })
root.searching = true; clicked({ button: 1, x: 1, y: 0 })
assert.deepEqual(calls, ["dismiss", "run s0", "dismiss", "dismiss"], "a click ran or dismissed the wrong thing")
console.log("ok: the pointer selects past its threshold, scrolls the ring or results, and clicks run or dismiss")
