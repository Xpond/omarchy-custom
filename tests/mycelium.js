const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

// The mycelium design's colony, grown outside Qt from fixed seeds (mulberry32), at 1080 units high.
const source = fs.readFileSync(path.join(__dirname, "../lock/mycelium/grow.js"), "utf8").replace(/^\.pragma .*$/m, "")
const { begin } = new Function(`${source}\nreturn { begin }`)()
let seed = 1
Math.random = () => {
  seed = (seed + 0x6D2B79F5) >>> 0
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}
const length = p => { let l = 0; for (let i = 2; i < p.length; i += 2) l += Math.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1]); return l }

for (const aspect of [4 / 3, 16 / 9, 21 / 9, 9 / 16]) for (let n = 0; n < 6; n++) {
  const { strands, fronts, light } = begin(aspect)(Infinity)
  // It takes the screen: some of it crosses nearly every 60-unit square.
  const width = 1080 * aspect, cols = Math.ceil(width / 60), seen = new Set()
  let reached = 0
  fronts.forEach(front => front.forEach(f => {
    for (let i = 0; i < f.length; i += 4) {
      reached += length(f.slice(i, i + 4))
      const x = Math.floor((f[i] + width / 2) / 60), y = Math.floor((f[i + 1] + 540) / 60)
      if (x >= 0 && x < cols && y >= 0 && y < 18) seen.add(y * cols + x)
    }
  }))
  assert.ok(seen.size / (cols * 18) > 0.95, `colony leaves ${Math.round(100 - seen.size / cols / 0.18)}% of a ${aspect.toFixed(2)} screen bare`)
  // Every line drawn has the step that reaches it, which fits the reach map's two bytes.
  const drawn = strands.reduce((sum, runs) => sum + runs.reduce((s, run) => s + length(run), 0), 0)
  assert.ok(Math.abs(drawn - reached) < 1e-6 * drawn, `lines drawn ${drawn} but reached ${reached}`)
  assert.ok(fronts.length < 65536, "more steps than the reach map holds")
  // Its light, which the shader spreads over neighbouring squares, covers nearly the whole screen
  // and reaches the corners after the centre.
  const right = light.cols - 1, bottom = light.rows - 1, arrival = (x, y) => light.px[4 * (y * light.cols + x) + 1]
  const shines = (x, y) => x >= 0 && y >= 0 && x <= right && y <= bottom && light.px[4 * (y * light.cols + x)] > 0
  let lit = 0
  for (let y = 0; y <= bottom; y++) for (let x = 0; x <= right; x++)
    if ([-1, 0, 1].some(dy => [-1, 0, 1].some(dx => shines(x + dx, y + dy)))) lit++
  assert.ok(lit / light.cols / light.rows > 0.95, `light covers only ${Math.round(100 * lit / light.cols / light.rows)}% of the screen`)
  for (const [x, y] of [[0, 0], [right, 0], [0, bottom], [right, bottom]])
    assert.ok(arrival(right >> 1, bottom >> 1) < arrival(x, y), "light reaches a corner before the centre")
}
console.log("ok: the colony and its light take the whole screen at 4:3, 16:9, 21:9 and portrait, every line with its step")

// Interrupt at every boundary, including tapering, and require the same complete colony.
const realNow = Date.now
for (const aspect of [4 / 3, 16 / 9, 21 / 9, 9 / 16]) {
  seed = 123
  const expected = begin(aspect)(Infinity)
  seed = 123
  const advance = begin(aspect)
  let now = 0, actual, slices = 0
  Date.now = () => now++
  try {
    while (!(actual = advance(2))) assert.ok(++slices < 10000, "growth never completes")
  } finally { Date.now = realNow }
  assert.ok(slices > 100, "test did not interrupt growth")
  assert.deepEqual(actual, expected, "yielding changes the colony")
}
console.log("ok: interrupted growth preserves every point, arrival step and light pixel")
