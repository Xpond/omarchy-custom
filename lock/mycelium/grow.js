.pragma library

// Grow a colony in a 1080-unit-high frame, 3 units per step.
// Return strands by quarter-unit width, fronts by arrival step/width, and ground light.

// Resume between whole growth steps and hyphae, keeping randomness and point order unchanged.
function begin(aspect) {
  var halfW = 540 * aspect + 20, halfH = 560
  // Which hypha holds each 8-unit cell, and where: the first to reach it keeps it.
  var cell = 8, cols = Math.ceil(2 * halfW / cell), rows = Math.ceil(2 * halfH / cell)
  var owner = new Int32Array(cols * rows), holding = new Int32Array(cols * rows)
  function at(x, y) { return Math.floor((y + halfH) / cell) * cols + Math.floor((x + halfW) / cell) }
  function taken(x, y, h) { var c = at(x, y); return owner[c] && owner[c] !== h + 1 ? 1 : 0 }

  var hyphae = [], tips = [], waking = []
  // Give branches five fusion-free steps to clear their parent.
  function sprout(x, y, heading, turn, start, parent) {
    hyphae.push({ points: [x, y], start: start, parent: parent, from: parent < 0 ? 0 : hyphae[parent].points.length / 2 - 1, feeds: {} });
    (waking[start + 1] = waking[start + 1] || []).push({ h: hyphae.length - 1, x: x, y: y, a: heading + turn, turn: turn, bend: 0, grace: 5 })
  }
  for (var i = 0; i < 12; i++) sprout(0, 0, (i + 0.3 + 0.4 * Math.random()) / 12 * 2 * Math.PI, 0, 0, -1)

  // Probes sense 0.6 either side of the heading.
  var C = Math.cos(0.6), S = Math.sin(0.6)
  var step = 1, remaining, strands = [], fronts = []
  var down = 34, across = Math.round(down * aspect), dense = new Float32Array(down * across), late = new Float32Array(down * across)
  return function advance(budget) {
    var until = Date.now() + budget
    for (; tips.length || step < waking.length; step++) {
      if (Date.now() >= until) return null
      var growing = waking[step] ? tips.concat(waking[step]) : tips
      tips = []
      for (var n = 0; n < growing.length; n++) {
        var tip = growing[n], h = hyphae[tip.h]
        var ca = Math.cos(tip.a), sa = Math.sin(tip.a)
        // Try the opposite turn if a late branch starts blocked.
        if (step === h.start + 1 && h.parent >= 0 && taken(tip.x + 24 * ca, tip.y + 24 * sa, tip.h)) {
          tip.a -= 2 * tip.turn
          ca = Math.cos(tip.a); sa = Math.sin(tip.a)
          if (taken(tip.x + 24 * ca, tip.y + 24 * sa, tip.h)) continue
        }
        // Wander, lean outward, and steer away from nearby hyphae.
        tip.bend = 0.8 * tip.bend + 0.04 * (Math.random() - 0.5)
        tip.a += tip.bend + 0.02 * (tip.y * ca - tip.x * sa) / (Math.sqrt(tip.x * tip.x + tip.y * tip.y) || 1)
          + 0.12 * (taken(tip.x + 20 * (ca * C + sa * S), tip.y + 20 * (sa * C - ca * S), tip.h)
                  - taken(tip.x + 20 * (ca * C - sa * S), tip.y + 20 * (sa * C + ca * S), tip.h))
        var x = tip.x + 3 * Math.cos(tip.a), y = tip.y + 3 * Math.sin(tip.a), c = at(x, y)
        if (Math.abs(x) > halfW || Math.abs(y) > halfH) { h.points.push(x, y); continue }
        if (tip.grace-- <= 0 && taken(x, y, tip.h)) {
          var other = hyphae[owner[c] - 1].points
          h.points.push(other[2 * holding[c]], other[2 * holding[c] + 1])
          continue
        }
        h.points.push(x, y)
        if (!owner[c] && tip.grace < 0) { owner[c] = tip.h + 1; holding[c] = h.points.length / 2 - 1 }
        tip.x = x; tip.y = y
        tips.push(tip)
        // Branch into open space, at once or a while later, behind the front.
        if (Math.random() < 0.045)
          sprout(x, y, tip.a, (Math.random() < 0.5 ? -1 : 1) * (0.5 + 0.8 * Math.random()), step + Math.floor(-40 * Math.log(1 - Math.random())), tip.h)
      }
    }

    // Reverse parent order so branch feed load contributes to each hypha's taper.
    if (remaining === undefined) remaining = hyphae.length - 1
    for (; remaining >= 0; remaining--) {
      if (Date.now() >= until) return null
      var h = hyphae[remaining], p = h.points, load = 0, bin = -1, run
      for (var j = p.length / 2 - 1; j > 0; j--) {
        load += 3 + (h.feeds[j] || 0)
        var b = Math.round(4 * Math.min(3, 0.5 + 0.35 * Math.log(1 + load / 30)))
        if (b !== bin) { bin = b; run = [p[2 * j], p[2 * j + 1]]; (strands[b] = strands[b] || []).push(run) }
        run.push(p[2 * j - 2], p[2 * j - 1])
        var front = fronts[h.start + j] = fronts[h.start + j] || [];
        (front[b] = front[b] || []).push(p[2 * j - 2], p[2 * j - 1], p[2 * j], p[2 * j + 1])
        if (j % 3) continue
        var x = Math.floor((p[2 * j] / 1080 / aspect + 0.5) * across), y = Math.floor((p[2 * j + 1] / 1080 + 0.5) * down)
        if (x >= 0 && x < across && y >= 0 && y < down) { dense[y * across + x] += b; late[y * across + x] += b * (h.start + j) }
      }
      if (h.parent >= 0) hyphae[h.parent].feeds[h.from] = (hyphae[h.parent].feeds[h.from] || 0) + load
    }
    return { strands: strands, fronts: fronts, light: light(dense, late, across, down) }
  }
}

// Ground light R: density weighted by width; G: mean arrival step / 8.
function light(dense, late, cols, rows) {
  var px = new Uint8ClampedArray(4 * cols * rows)
  for (var c = 0; c < cols * rows; c++) {
    px[4 * c] = 3 * dense[c]
    px[4 * c + 1] = dense[c] > 0 ? late[c] / dense[c] / 8 : 255
    px[4 * c + 3] = 255
  }
  return { cols: cols, rows: rows, px: px }
}
