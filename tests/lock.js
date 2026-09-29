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
console.log("ok: every outline traces to finite points")

// Parked is the whole draw-in done: outlines landed and the paint swept all the way to the tail.
const parked = car.at(end + paintTime)

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

// Inside the car shows only through glass, so some inside outlines are cut.
const inside = parts.filter(part => part.inside)
assert.ok(inside.some(part => part.whole.length > 1) && inside.every(part => part.runs), "inside outlines weren't clipped")
console.log("ok: inside outlines are clipped to the glass")

// The drive-off poses every frame finitely.
for (let t = 0; t <= 1100; t += 7) {
  const off = car.drive(t / 1100)
  assert.ok(finite([...off.lines, ...off.streaks, ...off.fills, off.glowing]), "non-finite point driving off at " + t + "ms")
}
console.log("ok: the drive-off stays finite")

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
