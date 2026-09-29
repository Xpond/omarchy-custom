const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const rally = path.join(__dirname, "../lock/rally")
const qml = fs.readFileSync(path.join(rally, "Car.qml"), "utf8")

// A QML JavaScript library of the car's: its functions, with its .imports as arguments.
const loaded = {}
function library(file) {
  if (loaded[file]) return loaded[file]
  const source = fs.readFileSync(path.join(rally, file), "utf8")
  const imports = [...source.matchAll(/^\.import "(.+)" as (\w+)$/gm)]
  const code = source.replace(/^\.(pragma|import) .*$/gm, "")
  const names = [...code.matchAll(/^function (\w+)/gm)].map(m => m[1])
  return loaded[file] = new Function(...imports.map(i => i[2]), `${code}\nreturn { ${names} }`)(...imports.map(i => library(i[1])))
}

// Runs the car's own model, projection, tracing and drive-off outside Qt, at 1080p.
const model = library("model.js").carModel(), parts = model.parts
const code = qml.slice(qml.indexOf("  // Screen polylines of an outline from a to b"), qml.indexOf("  onClockChanged"))
const drive = qml.match(/onDriveChanged: \{([^]*?)\n  \}\n  onWidthChanged/)[1]
const streakFrom = qml.match(/readonly property var streakFrom: (\[[^]*?\]\])\n/)[1]
const paint = qml.match(/readonly property var paint: (\[[^\]]*\])/)[1]
// traced is when the last outline lands; painted is the paint's own progress over the paintTime after it,
// a binding in QML and set by hand here.
const traced = Math.ceil(Math.max(...parts.map(part => part.end)))
const paintTime = Number(qml.match(/readonly property int paintTime: (\d+)/)[1])
const car = new Function("model", "parts", "Qt", `
  var paint = ${paint}, width = 1920, height = 1080, clock = 0, lines, wheelLines, tracing, comets = [[], [], [], []], streaks = [[], [], [], []]
  var bodywork, wheels, finished, view, stance, projected = {}, focusHeights, bodyPose
  var drive = 0, driveTime = 1100, launch = 0, lamps = 0, rolled = 0, glowing = [], pose, streakFrom = ${streakFrom}
  var traced = ${traced}, paintTime = ${paintTime}, painted = 1, span = null, front = 0, wavefront = []
  ${code}
  function onDrive() { ${drive} }
  function tick(t) {
    clock = t
    painted = Math.min(1, Math.max(0, (t - traced) / paintTime))
    front = span ? span[0] + (span[1] - span[0]) * painted : 0
    frame()
    wavefront = painted > 0 && painted < 1 ? cuts() : []
  }
  // Every tone's surfaces as drawn: the body's parked, which bodyPose moves as a whole, and the wheels'.
  function fills() { return bodywork.map(function(tone, n) { return tone.concat(wheels[n]) }) }
  return {
    project: project,
    view: function(p) { return view(p) },
    pitched: pitched,
    stance: function(pitch, shake) { return stance(pitch, shake) },
    at: function(t) { tick(t); return { lines: lines, tracing: tracing, comets: comets, fills: fills(), front: front, wavefront: wavefront } },
    drive: function(v) { drive = v; onDrive(); return { lines: lines.concat(wheelLines), streaks: streaks, glowing: glowing, fills: fills() } }
  }`)(model, parts, { point: (x, y) => ({ x, y }), size: (width, height) => ({ width, height }), matrix4x4: (...m) => m })
car.project()

const finite = groups => groups.every(group => group.every(line => line.every(p => isFinite(p.x) && isFinite(p.y))))
const end = Math.max(...parts.map(part => part.end))

// Every tracing frame is drawable: a fly-in direction with a zero component once made NaN points.
for (let t = 0; t <= end; t += 7) {
  const f = car.at(t)
  assert.ok(finite([...f.lines, ...f.tracing, ...f.comets, ...f.fills]), "non-finite point while tracing at " + t + "ms")
}
// Parked is the whole draw-in done: outlines landed and the paint swept all the way to the tail.
const parked = car.at(end + paintTime)
assert.equal(parked.tracing.flat().length, 0, "outlines still tracing after the draw-in")
assert.ok(end <= 4000, "draw-in takes " + end + "ms, over 4s")
console.log("ok: every outline traces to finite points and the car parks by " + Math.round(end) + "ms")

// The trace keeps an even pace: outlines set off one after another, so it neither stalls between
// groups nor lands a heap of them at once. The first and last 300ms are its ramp in and out.
const busy = []
for (let t = 0; t <= end; t += 50) busy.push(parts.filter(part => t > part.start && t < part.end).length)
const settled = busy.slice(6, -6)
assert.ok(Math.min(...settled) >= 8, "the trace stalls to " + Math.min(...settled) + " outlines in flight")
assert.ok(Math.max(...busy) <= 18, "the trace piles up " + Math.max(...busy) + " outlines at once")
console.log("ok: the trace holds " + Math.min(...settled) + "-" + Math.max(...busy) + " outlines in flight throughout")

// Paint waits for the car and then floods on behind a wavefront, rather than appearing whole over a
// half-built wireframe: the clip starts clear of every painted point, finishes past them all, and
// crosses the car steadily in between.
const points = parked.fills.flat().flat()
const shown = x => points.filter(p => p.x < x).length / points.length
const fronts = []
for (let t = end; t <= end + paintTime; t += paintTime / 20) fronts.push(car.at(t).front)
assert.equal(shown(fronts[0]), 0, "the car is already painted when the last outline lands")
assert.equal(shown(fronts.at(-1)), 1, "the sweep leaves part of the car bare")
assert.ok(fronts.every((x, i) => i === 0 || x > fronts[i - 1]), "the wavefront doesn't advance")
const mid = shown(fronts[fronts.length >> 1])
assert.ok(mid > 0.15 && mid < 0.85, "the paint is " + Math.round(100 * mid) + "% on halfway: it isn't sweeping")

// The lit edge is the wavefront cutting the surfaces, so it follows the car's shape: it has to appear
// only mid-sweep, sit on the front, and span more than one stretch down the screen.
assert.equal(car.at(end).wavefront.length, 0, "the lit edge shows before the paint starts")
assert.equal(parked.wavefront.length, 0, "the lit edge is still lit once the paint is done")
const lit = car.at(end + paintTime / 2).wavefront
assert.ok(lit.length > 1, "the lit edge is a single stretch, not the car's outline")
assert.ok(lit.every(([a, b]) => a.x === b.x && Math.abs(a.x - fronts[fronts.length >> 1]) < 1e-6), "the lit edge isn't on the wavefront")
assert.ok(new Set(lit.map(([a, b]) => Math.round(b.y - a.y))).size > 1, "every lit stretch is the same length: it isn't following the body")
console.log("ok: paint waits for the last outline, then floods on nose to tail, " +
  Math.round(100 * mid) + "% on at half sweep, lit edge in " + lit.length + " stretches")

// Inside the car shows only through glass, so some inside outlines are cut and none spill over the body.
const inside = parts.filter(part => part.inside)
assert.ok(inside.some(part => part.whole.length > 1) && inside.every(part => part.runs), "inside outlines weren't clipped")
console.log("ok: inside outlines are clipped to the glass")

// The wheel wells have dark backing; no body paint covers the gap over a tyre.
const covers = (poly, [x, y]) => poly.reduce((c, p, i) => {
  const q = poly[(i + poly.length - 1) % poly.length]
  return (p.y > y) !== (q.y > y) && x < (q.x - p.x) * (y - p.y) / (q.y - p.y) + p.x ? !c : c
}, false)
for (const axle of [100, 322]) {
  const gap = car.view([axle, 63, -86])
  for (const side of [-1, 1])
    assert.ok(parked.fills[27].some(poly => covers(poly, car.view([axle + side * 33, 22, -80]))), "open lower wheel well at " + axle)
  parked.fills.forEach((tone, n) => {
    if (n !== 61) assert.equal(tone.filter(poly => covers(poly, gap)).length % 2, n === 27 ? 1 : 0, "unexpected backing tone " + n + " over " + axle)
  })
}
console.log("ok: the wheel wells stay dark")

// The inner return must taper to the opening, not close with a visible cap.
// Shared arc vertices prevent slivers; dense chords keep the inner edge smooth at 4K.
const flank = model.surfaces.find(s => s.tone === 0).pts
for (const wall of model.surfaces.filter(s => s.tone === 4 && s.pts.length > 3)) {
  const split = wall.pts.findIndex(p => p[2] === -80)
  const outer = wall.pts.slice(0, split), a = car.view(outer.at(-1)), b = car.view(wall.pts[split])
  assert.ok(Math.hypot(a[0] - b[0], a[1] - b[1]) < 1e-6, "inner arch ends in a visible cap")
  for (const p of outer.slice(0, -1))
    assert.ok(flank.some(q => p.every((v, i) => Math.abs(v - q[i]) < 1e-9)), "arch and body use different curves")
  const axle = outer[0][0] < 220 ? 100 : 322
  for (let i = 1; i < wall.pts.length; i++) {
    const p = wall.pts[i - 1], q = wall.pts[i]
    if (p[2] !== q[2]) continue
    const sagitta = 36 - Math.hypot((p[0] + q[0]) / 2 - axle, (p[1] + q[1]) / 2 - 30)
    assert.ok(sagitta < 0.006, "inner arch has visibly coarse segments")
  }
}
console.log("ok: inner arch edges meet exactly, share the body curve and stay smooth at 4K")

// The intake mouth faces the nose.
const intake = model.surfaces.find(s => s.tone === 72).pts
for (const p of intake) {
  assert.ok(p[1] < 69 && p[1] > 23, "intake crosses the flare shoulder or sill")
  assert.ok(p[0] > 264 && Math.hypot(p[0] - 322, p[1] - 30) > 36, "intake crosses door or wheel arch")
}
assert.ok(Math.max(...intake.map(p => p[0])) - Math.min(...intake.map(p => p[0])) < 0.01,
  "intake mouth must face forward on a constant-x plane")
assert.ok(Math.max(...intake.map(p => p[2])) - Math.min(...intake.map(p => p[2])) > 10,
  "intake mouth must span the flare width")
const cheek = model.surfaces.find(s => s.tone === 75).pts
assert.ok(cheek.every(p => p[1] >= 31 && p[1] <= 67), "painted cheek forms pointed caps above or below intake")
assert.ok(model.surfaces.find(s => s.tone === 7).pts.some(p => p[0] === 284.5 && p[1] === 16),
  "rocker stops short of the wheel opening")
// The inset screen must stay behind the mouth: an overly deep offset exposed a sliver outside it.
for (const t of [0, 350, 700, 1100]) {
  const f = car.drive(t / 1100).fills
  for (const p of f[74][1]) assert.ok(covers(f[73][0], [p.x, p.y]), "intake screen projects outside its opening")
}
// The near fin closes the tail's top corner: no bodywork rises above the deck there outside it,
// as the Quattro's lip once poked out beside the wing.
const nearFin = parked.fills[63][0]
for (const s of model.surfaces.filter(s => s.tone <= 4))
  for (const p of s.pts.filter(p => p[0] > 393 && p[1] > 98.5 && p[2] < -60))
    assert.ok(covers(nearFin, car.view(p)), "bodywork pokes out beside the wing's fin at " + p.map(Math.round))
const housing = model.surfaces.find(s => s.tone === 34).pts
assert.ok(new Set(housing.map(p => p[0])).size > 5, "mirror is a pointed cone, without a rounded shell")
console.log("ok: intake faces forward, the wing's fin closes the tail corner and mirrors have rounded shells")

// Every section across the tyre's width is solid, including the tread exposed on launch.
for (const t of [0, 350, 500, 700, 900]) {
  const posed = car.drive(t / 1100)
  for (const axle of [100, 322]) for (const z of [-83, -74, -65]) for (let a = 0; a < 360; a += 5) {
    const angle = a * Math.PI / 180
    const p = car.view([axle + 31 * Math.cos(angle), 30 + 31 * Math.sin(angle), z])
    assert.ok(posed.fills[61].some(poly => covers(poly, p)), `hollow tyre at ${axle}, ${a}deg, ${z}, ${t}ms`)
  }
}
console.log("ok: both tyres remain solid across their full width throughout drive-off")

// The drive-off poses every frame finitely, lights both headlamps and the taillamp, and trails streaks.
let off
for (let t = 0; t <= 1100; t += 7) {
  off = car.drive(t / 1100)
  assert.ok(finite([...off.lines, ...off.streaks, ...off.fills, off.glowing]), "non-finite point driving off at " + t + "ms")
}
assert.equal(off.glowing.length, 3, "lamps that glow")
assert.equal(off.streaks[2].length, new Function("return " + streakFrom)().length, "one streak per streak point")
console.log("ok: the drive-off stays finite, lights three lamps and trails every streak")

// The body takes its pose as one flat transform of its parked shapes: none while parked, the shake to
// within half a pixel, and the squat to within the parallax a flat transform can't show.
const body = parts.filter(part => part.axle === undefined).flatMap(part => part.pts)
  .concat(model.surfaces.filter(s => s.axle === undefined).flatMap(s => s.pts))
function strays(pitch, shake) {
  const m = car.stance(pitch, shake)
  return body.map(p => {
    const q = car.view(p), exact = car.view(car.pitched(p, pitch, shake))
    return Math.hypot(m[0] * q[0] + m[1] * q[1] + m[2] - exact[0], m[3] * q[0] + m[4] * q[1] + m[5] - exact[1])
  })
}
assert.deepEqual(car.stance(0, 0), [1, 0, 0, 0, 1, 0], "the parked body is transformed")
assert.ok(Math.max(...strays(0, 1.2)) < 0.5, "the shaking body strays from its true pose")
const squat = strays(0.06, 0), mean = squat.reduce((a, b) => a + b) / squat.length
assert.ok(mean < 5 && Math.max(...squat) < 21, `the squatting body strays ${mean.toFixed(1)}px on average, up to ${Math.max(...squat).toFixed(1)}px`)
console.log(`ok: the body's flat pose keeps the shake within half a pixel, and the squat within ${mean.toFixed(1)}px on average`)
