const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const plugin = path.resolve(__dirname, "../plugins/xpo.wheel")
const read = name => fs.readFileSync(path.join(plugin, name), "utf8")
const wheel = read("Wheel.qml")

// Both ShaderEffects bind uniforms by name, including required QML properties.
for (const name of ["logo", "fluid"]) {
  const frag = read(name + ".frag")
  const block = frag.match(/uniform buf \{([^]*?)\}/)[1]
  const declared = new Set([
    ...[...block.matchAll(/^\s*(?:float|vec[234]|mat[234])\s+(\w+)\s*;/gm)].map(m => m[1]),
    ...[...frag.matchAll(/uniform sampler2D\s+(\w+)\s*;/g)].map(m => m[1]),
  ].filter(n => !n.startsWith("qt_")))
  const effect = name === "logo"
    ? wheel.slice(wheel.indexOf("ShaderEffect {")).match(/^[^]*?\n    \}/)[0]
    : read("Fluid.qml")
  assert.ok(effect.includes(name + ".frag.qsb"), "found the wrong ShaderEffect")
  const bound = new Set([...effect.matchAll(/property\s+\w+\s+(\w+)\b/g)].map(m => m[1]))
  assert.deepEqual([...bound].sort(), [...declared].sort(), name + " shader and QML disagree on uniforms")
  assert.ok(fs.existsSync(path.join(plugin, name + ".frag.qsb")), name + " compiled shader is missing")
  console.log("ok: " + name + " shader and QML agree on every uniform")
}
assert.ok(fs.existsSync(path.join(plugin, "mark.png")), "mark.png is missing")

// Evaluate production curves: the arc, twilight, moon and lighting must agree.
{
  const src = read("Sky.qml")
  const expr = name => src.match(new RegExp("readonly property real " + name + ": (.+)"))[1]
  // Each curve is read out with the property it names as its argument, which
  // is exactly how QML resolves them.
  const elevation = new Function("phase", "return " + expr("elevation"))
  const azimuth = new Function("phase", "return " + expr("azimuth"))
  const lit = new Function("elevation", "return " + expr("light"))
  const dusk = new Function("elevation", "return " + expr("dusk"))
  const light = p => lit(elevation(p))
  // sin() lands a few parts in 1e16 either side of the horizon, so these are
  // compared the way the eye does.
  const near = (a, b, why) => assert.ok(Math.abs(a - b) < 1e-9, why)
  // Half the cycle is night, and the light peaks once, at noon.
  near(light(0), 0, "the cycle does not start at the horizon")
  near(light(0.25), 1, "noon is not the top of the arc")
  for (const p of [0.5, 0.6, 0.75, 0.9, 1]) near(light(p), 0, "night is not dark at " + p)
  // Twilight straddles the horizon and is gone at both noon and midnight.
  near(dusk(0), 1, "twilight does not peak at the horizon")
  for (const e of [1, -1]) assert.ok(dusk(e) < 0.01, "twilight lingers at elevation " + e)
  assert.ok(Math.abs(dusk(0.4) - dusk(-0.4)) < 1e-9, "twilight is lopsided about the horizon")
  // Haze peaks while stars are still visible, on both sides of the horizon.
  for (const p of [0.5, 1]) {
    assert.ok(dusk(elevation(p)) > 0.9, "no haze at the hour it is meant to be thickest")
    near(light(p), 0, "the sun is still up where the haze peaks")
  }
  // The arc runs left to right across the day, not straight up the middle.
  near(azimuth(0), -1, "the light does not come up out of the left")
  near(azimuth(0.25), 0, "noon is not overhead")
  near(azimuth(0.5), 1, "the light does not go down into the right")
  // Elevation and azimuth are one ellipse, so they must stay a quarter turn
  // apart -- drifting into phase would walk the light up a diagonal instead.
  for (const p of [0, 0.12, 0.3, 0.62, 0.88]) {
    near(elevation(p) ** 2 + azimuth(p) ** 2, 1, "the arc is not an ellipse at " + p)
  }
  // Night is spent travelling back the other way, underneath.
  assert.ok(azimuth(0.75) < azimuth(0.6), "the light does not return during the night")
  // The moon is up exactly when the sun is not, so the night half of the cycle
  // has a moving part rather than a held dark frame.
  const moon = new Function("elevation", "return " + expr("moon"))
  for (const p of [0, 0.12, 0.25, 0.4]) assert.equal(moon(elevation(p)), 0, "a moon in daylight at " + p)
  near(moon(elevation(0.75)), 1, "no moon at midnight")
  // The mark is lit by whichever body is up. `keyFacing` is the handover: the
  // sun's direction while it is up, the moon's -- its exact opposite -- after.
  const facing = new Function("elevation", "return " + expr("keyFacing"))
  near(facing(elevation(0.25)), 1, "noon does not light from the sun")
  near(facing(elevation(0.75)), -1, "midnight does not light from the moon")
  near(facing(elevation(0.5)), 0, "the handover does not cross zero at the horizon")
  // Which makes the light travel left, overhead, right across the day, and come
  // from overhead again at midnight -- never from below, where nothing is.
  // Read out of the QML rather than restated here, so changing the direction
  // the mark is lit from has to come past these assertions.
  const vector = src.match(/keyDirection: (Qt\.vector2d\([^)]*\))/)[1]
  const direction = new Function("Qt", "keyFacing", "azimuth", "elevation", "return " + vector)
  const keyOf = p => direction({ vector2d: (x, y) => ({ x, y }) },
                               facing(elevation(p)), azimuth(p), elevation(p))
  assert.ok(keyOf(0.08).x < -0.1, "morning does not light from the left")
  near(keyOf(0.25).x, 0, "noon does not light from overhead")
  assert.ok(keyOf(0.42).x > 0.1, "evening does not light from the right")
  for (const p of [0.25, 0.75]) assert.ok(keyOf(p).y < 0, "the light comes from below at " + p)
  // Glow and fluid positions share the same ellipse, half a day apart.
  const positionExpr = src.match(/function bodyPosition\(side\) \{\s*return (.+)/)[1]
  const position = new Function("Qt", "azimuth", "elevation", "side", "return " + positionExpr)
  const bodyAt = (p, side) => position({ vector2d: (x, y) => ({ x, y }) }, azimuth(p), elevation(p), side)
  near(bodyAt(0, 1).x, 0.1, "sunrise is not on the left")
  near(bodyAt(0.5, 1).x, 0.9, "sunset is not on the right")
  near(bodyAt(0.25, 1).y, 0.22, "the sun does not reach overhead")
  near(bodyAt(0.75, -1).y, 0.22, "the moon does not reach overhead")
  for (const p of [0, 0.08, 0.25, 0.42, 0.75]) {
    const sun = bodyAt(p, 1), moonPos = bodyAt(p, -1)
    near(sun.x + moonPos.x, 1, "bodies lost horizontal symmetry")
    near(sun.y + moonPos.y, 1.56, "bodies lost vertical symmetry")
  }
  // Counting up past 1 must land back where it started, or the second day
  // would not match the first -- this is what pays for never wrapping `phase`.
  for (const p of [0, 0.17, 0.43, 0.81]) {
    for (const day of [1, 2, 37]) {
      near(light(p), light(p + day), "day " + day + " differs at " + p)
      near(azimuth(p), azimuth(p + day), "the arc differs on day " + day + " at " + p)
    }
  }
}
console.log("ok: the sky reaches night, peaks once, and repeats every day")
