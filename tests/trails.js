const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const read = name => fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel", name), "utf8")
const wheel = read("Wheel.qml")

// Disc illumination is continuous in both directions and clears at rest.
const sweepRoot = { arcSpread: 17, arcHead: -90, arcDrag: 0 }
const sweepAt = new Function("root", "deg", wheel.match(/function sweepAt\(deg\) \{([^]*?)\n  }/)[1])
const sweep = (deg, drag) => { sweepRoot.arcDrag = drag; return sweepAt(sweepRoot, deg) }
// -90 is the head itself: the slice a parked comet used to hold at full.
for (const deg of [-90, -50, 0, 90, 180])
  assert.equal(sweep(deg, 0), 0, "a ring at rest lights " + deg)
assert.ok(sweep(-90, 40) > 0.9, "a moving head still lights what it is on")
assert.ok(sweep(-90, 8) < sweep(-90, 40), "and a slower ring lights it less")
assert.equal(sweep(90, 40), 0, "nothing lights where the streak is not")
// Crossing either edge or the back of a long trail must not flash a disc.
for (const drag of [40, -40, 300, -300]) {
  let previous = sweep(-270, drag)
  for (let deg = -269.9; deg <= 90; deg += 0.1) {
    const light = sweep(deg, drag)
    assert.ok(light >= 0 && light <= 1, "trail brightness stays bounded")
    assert.ok(Math.abs(light - previous) < 0.02,
      `trail jumps at ${deg.toFixed(1)} degrees with drag ${drag}`)
    assert.ok(Math.abs(light - sweep(deg + 360, drag)) < 1e-10,
      "trail stays continuous across laps")
    assert.ok(Math.abs(light - sweep(-180 - deg, -drag)) < 1e-10,
      "both spin directions share the same lighting")
    previous = light
  }
}
console.log("ok: the comet lights what it crosses and gives it back at rest")

// Even at full speed, the visible comet leaves at least a third of the ring quiet
// and keeps its leading edge beside the head in either direction.
{
  const expr = name => new Function("root", "return " + wheel.match(
    new RegExp("readonly property real " + name + ": (.+)"))[1])
  const span = expr("arcSpan"), from = expr("arcFrom")
  for (const count of [8, 9, 12, 24]) {
    for (const drag of [-300, -40, 0, 40, 300]) {
      const state = { arcSpread: 360 / count / 2 * 0.85, arcDrag: drag, arcHead: 1440 }
      state.arcSpan = span(state)
      assert.ok(state.arcSpan <= 240, "fast comet closes into a circle")
      assert.ok(state.arcSpan >= state.arcSpread * 2, "selection bracket shrank")
      const tip = drag >= 0 ? from(state) + state.arcSpan : from(state)
      assert.ok(Math.abs(tip - (state.arcHead + (drag >= 0 ? 1 : -1) * state.arcSpread)) < 1e-9,
        "shortening the trail moved its head")
    }
  }
}
console.log("ok: the comet retains a third-ring gap and follows its head")

// The visible lap takes two seconds regardless of key repeat or frame rate.
{
  const source = read("RingTrack.qml")
  const body = source.match(/function advance\(dt\) \{([^]*?)\n  }/)[1]
  const advance = new Function("root", "dt", body)
  for (const direction of [-1, 1]) {
    for (const fps of [30, 60, 144]) {
      const state = { visualHead: -90, wheel: { arcDrag: direction * 300, arcHead: -90 } }
      for (let frame = 0; frame < fps * 2; frame++) {
        state.wheel.arcHead += direction * 1800 / fps
        advance(state, 1 / fps)
      }
      assert.ok(Math.abs(state.visualHead - (-90 + direction * 360)) < 1e-8,
        "visible trail raced with input at " + fps + "fps")
    }
  }
}
console.log("ok: sustained trail makes one visible lap every two seconds")

// Release discards accumulated input laps; resuming preserves the visible tip.
{
  const body = read("RingTrack.qml").match(/onRunningChanged: \{([^]*?)\n    }/)[1]
  const change = new Function("root", "settle", "running", body)
  for (const offset of [-1440, -181, -179, 0, 179, 181, 1440]) {
    const state = { wheel: { arcHead: 34567 }, visualHead: 34567 + offset, settleOffset: 0 }
    const calls = []
    const settle = { restart: () => calls.push("restart"), stop: () => calls.push("stop") }
    change(state, settle, false)
    assert.ok(Math.abs(state.settleOffset) <= 180, "release chases completed input laps")
    assert.equal((state.settleOffset - offset) % 360 || 0, 0, "release moved the visible tip")
    state.wheel.arcHead += 45
    const expected = state.wheel.arcHead + state.settleOffset
    change(state, settle, true)
    assert.equal(state.visualHead, expected, "resuming spin jumped away from the settling tip")
    assert.equal(state.settleOffset, 0)
    assert.deepEqual(calls, ["restart", "stop"])
  }
}
console.log("ok: release takes the shortest arc and resumed spin keeps its position")
