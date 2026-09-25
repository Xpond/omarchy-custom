.pragma library

// A mycelium colony, grown out from the centre of a screen 1080 units high and aspect times as
// wide. Every tip steps 3 units at a time: it wanders, bends outward, steers clear of other hyphae
// and branches into open space. It dies where it meets another hypha, fusing with it, or 20 units
// past the screen's edge. Returns its lines as strands, runs of one width by width in quarter
// units, and as fronts, each stretch as a pair of points by the step that reaches it, then by
// width; and the light it casts on the ground, as a small image (see light).
function grow(aspect) {
  var halfW = 540 * aspect + 20, halfH = 560
  // Which hypha holds each 8-unit cell, and where: the first to reach it keeps it.
  var cell = 8, cols = Math.ceil(2 * halfW / cell), rows = Math.ceil(2 * halfH / cell)
  var owner = new Int32Array(cols * rows), holding = new Int32Array(cols * rows)
  function at(x, y) { return Math.floor((y + halfH) / cell) * cols + Math.floor((x + halfW) / cell) }
  function taken(x, y, h) { var c = at(x, y); return owner[c] && owner[c] !== h + 1 ? 1 : 0 }

  // Tips growing, and waiting to, by the step they first move on.
  var hyphae = [], tips = [], waking = []
  // A branch turns from its parent's heading; one sprouting at start first moves the step after.
  // For its first 5 steps a hypha neither fuses nor holds cells, so it can get clear of its parent.
  function sprout(x, y, heading, turn, start, parent) {
    hyphae.push({ points: [x, y], start: start, parent: parent, from: parent < 0 ? 0 : hyphae[parent].points.length / 2 - 1, feeds: {} });
    (waking[start + 1] = waking[start + 1] || []).push({ h: hyphae.length - 1, x: x, y: y, a: heading + turn, turn: turn, bend: 0, grace: 5 })
  }
  for (var i = 0; i < 12; i++) sprout(0, 0, (i + 0.3 + 0.4 * Math.random()) / 12 * 2 * Math.PI, 0, 0, -1)

  // Probes sense 0.6 either side of the heading.
  var C = Math.cos(0.6), S = Math.sin(0.6)
  for (var step = 1; tips.length || step < waking.length; step++) {
    var growing = waking[step] ? tips.concat(waking[step]) : tips
    tips = []
    for (var n = 0; n < growing.length; n++) {
      var tip = growing[n], h = hyphae[tip.h]
      var ca = Math.cos(tip.a), sa = Math.sin(tip.a)
      // A branch that wakes to find no room ahead turns as far the other way, and failing that
      // never grows: late branches find the gaps left.
      if (step === h.start + 1 && h.parent >= 0 && taken(tip.x + 24 * ca, tip.y + 24 * sa, tip.h)) {
        tip.a -= 2 * tip.turn
        ca = Math.cos(tip.a); sa = Math.sin(tip.a)
        if (taken(tip.x + 24 * ca, tip.y + 24 * sa, tip.h)) continue
      }
      // Wander smoothly, lean outward (by the sine of the turn to it) and turn from the nearer of
      // two hyphae sensed ahead.
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

  // A hypha tapers with the length it feeds beyond each point, its own and its branches': cords
  // near the centre carry the colony, the fine hyphae at its edge only themselves. Point j of a
  // hypha is reached at step start + j. Branches come after their parents, so go from the last.
  var strands = [], fronts = []
  // The light the colony casts, in 32-unit squares, from every third stretch.
  var down = 34, across = Math.round(down * aspect), dense = new Float32Array(down * across), late = new Float32Array(down * across)
  for (var i = hyphae.length - 1; i >= 0; i--) {
    var h = hyphae[i], p = h.points, load = 0, bin = -1, run
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

// The colony's light on the ground, as an image cols by rows over the screen, magnified smoothly
// where it's used: in red, how much of the colony lies in each square, weighing its stretches by
// width; in green, the step that reaches it on average, in eighths.
function light(dense, late, cols, rows) {
  var px = new Uint8ClampedArray(4 * cols * rows)
  for (var c = 0; c < cols * rows; c++) {
    px[4 * c] = 3 * dense[c]
    px[4 * c + 1] = dense[c] > 0 ? late[c] / dense[c] / 8 : 255
    px[4 * c + 3] = 255
  }
  return { cols: cols, rows: rows, px: px }
}
