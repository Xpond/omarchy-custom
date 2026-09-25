.pragma library
.import "shape.js" as Shape

var across = Shape.across, along = Shape.along, arc = Shape.arc, crown = Shape.crown, faceAt = Shape.faceAt,
  flip = Shape.flip, grow = Shape.grow, inset = Shape.inset, lift = Shape.lift, lip = Shape.lip,
  plate = Shape.plate, unwarp = Shape.unwarp, zAt = Shape.zAt

// The livery: stripes, decals and lettering, and the side intake whose cheek it wraps.
function build(m) {
  var add = m.add, surface = m.surface, surfaces = m.surfaces, deck = m.deck, hood = m.hood, nose = m.nose,
    roof = m.roof, wheels = m.wheels, i
  // Decals are painted on the body in 3D, so they turn with it. Lettering is a chamfered racing type
  // on a 4 by 6 grid, slanted, sampled every unit along the surface so it follows the flares.
  var glyphs = {
    A: [[[0, 0], [0, 5], [1, 6], [3, 6], [4, 5], [4, 0]], [[0, 3], [4, 3]]],
    B: [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [4, 2], [4, 1], [3, 0], [0, 0]], [[0, 3], [3, 3]]],
    C: [[[4, 1], [3, 0], [1, 0], [0, 1], [0, 5], [1, 6], [3, 6], [4, 5]]],
    D: [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 1], [3, 0], [0, 0]]],
    E: [[[4, 6], [0, 6], [0, 0], [4, 0]], [[0, 3], [3, 3]]],
    F: [[[4, 6], [0, 6], [0, 0]], [[0, 3], [3, 3]]],
    G: [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0], [3, 0], [4, 1], [4, 3], [2, 3]]],
    H: [[[0, 0], [0, 6]], [[4, 0], [4, 6]], [[0, 3], [4, 3]]],
    I: [[[2, 0], [2, 6]]],
    K: [[[0, 0], [0, 6]], [[4, 6], [1, 3], [4, 0]], [[0, 3], [1, 3]]],
    L: [[[0, 6], [0, 0], [4, 0]]],
    M: [[[0, 0], [0, 6], [2, 3], [4, 6], [4, 0]]],
    N: [[[0, 0], [0, 6], [4, 0], [4, 6]]],
    O: [[[1, 0], [3, 0], [4, 1], [4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0]]],
    Q: [[[1, 0], [3, 0], [4, 1], [4, 5], [3, 6], [1, 6], [0, 5], [0, 1], [1, 0]], [[2.5, 1.5], [4, 0]]],
    R: [[[0, 0], [0, 6], [3, 6], [4, 5], [4, 4], [3, 3], [0, 3]], [[2, 3], [4, 0]]],
    S: [[[4, 5], [3, 6], [1, 6], [0, 5], [0, 4], [1, 3], [3, 3], [4, 2], [4, 1], [3, 0], [1, 0], [0, 1]]],
    T: [[[0, 6], [4, 6]], [[2, 6], [2, 0]]],
    U: [[[0, 6], [0, 1], [1, 0], [3, 0], [4, 1], [4, 6]]],
    V: [[[0, 6], [2, 0], [4, 6]]],
    W: [[[0, 6], [0, 0], [2, 3], [4, 0], [4, 6]]],
    X: [[[0, 0], [4, 6]], [[0, 6], [4, 0]]],
    Y: [[[0, 6], [2, 3], [4, 6]], [[2, 3], [2, 0]]],
    " ": [],
    "4": [[[3, 0], [3, 6], [0, 2], [4, 2]]]
  }
  // Text s tall centred on (u, v) of a surface, where place(u, v) is the 3D point u along and v up it,
  // widened by wide where the surface is seen at a slant.
  function letter(tone, text, u, v, s, place, wide) {
    var k = s / 6, kx = k * (wide || 1), u0 = u - (text.length * 5.5 - 1.5) * kx / 2
    text.split("").forEach(function(ch, n) {
      glyphs[ch].forEach(function(stroke) {
        var pts = []
        for (var i = 1; i < stroke.length; i++) {
          var a = stroke[i - 1], b = stroke[i], steps = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) * k))
          for (var j = i > 1 ? 1 : 0; j <= steps; j++) {
            var gx = a[0] + (b[0] - a[0]) * j / steps, gy = a[1] + (b[1] - a[1]) * j / steps
            pts.push(place(u0 + (n * 5.5 + gx) * kx + gy * 0.25 * k, v - s / 2 + gy * k))
          }
        }
        surface(tone, pts)
      })
    })
  }
  // The near flank, and the windscreen, u across it from the camera's left and v up it.
  function flankAt(u, v) { return [u, v, -zAt(u, v)] }
  function glassAt(u, v) {
    var a = crown(150.5, 92.8, 2, -u), b = crown(206, 127.5, 3, -u * 58 / 72)
    return a.map(function(c, k) { return c + (b[k] - c) * v / 63.7 })
  }
  // Stripes: navy, blue and red, Martini style. A band from v0 to v1 runs across the bumper's face and round
  // its near corner onto the flank, one outline (the GPU renderer leaves slivers along an edge two share),
  // cut round the front flare's lips; behind the door it sweeps up 46 over the rear flare to run under the
  // quarter glass, ending short of the fuel flap. Over the top one runs from x0 to x1 at
  // z0 to z1 across a panel whose profile is line, crowned by rise.
  function sweep(x) { var t = Math.min(1, Math.max(0, (x - 258) / 42)); return 46 * t * t * (3 - 2 * t) }
  function band(tone, v0, v1) {
    var ends = [faceAt, function(v) { return lip(100, v, -1) }, function(v) { return lip(100, v, 1) },
      function(v) { return 348 + (v - 30) * 0.5 }]
    for (var n = 0; n < 4; n += 2) {
      var pts = along(v0, ends[n](v0), ends[n + 1](v0))
      for (var v = v0; v < v1; v++) pts.push([ends[n + 1](v), v])
      pts = pts.concat(flip(along(v1, ends[n](v1), ends[n + 1](v1))))
      if (n) for (v = v1; v > v0; v--) pts.push([ends[n](v), v])
      var side = lift(pts.map(function(p) { return [p[0], p[1] + sweep(p[0])] }), -1)
      surface(tone, n ? side : flip(across(-5, v0, 0)).concat(side, across(-5, v1, 0)))
    }
  }
  function heightAt(line, x) {
    for (var i = 1; i < line.length - 1 && line[i][0] < x; i++);
    var a = line[i - 1], b = line[i]
    return a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])
  }
  function stripe(tone, line, rise, x0, x1, z0, z1) {
    var near = [], far = []
    for (var x = x0; x < x1 + 4; x += 4) {
      var at = Math.min(x, x1), y = heightAt(line, at)
      near.push(crown(at, y, rise, z0))
      far.unshift(crown(at, y, rise, z1))
    }
    surface(tone, near.concat(far))
  }
  band(9, 36, 44)
  band(10, 32, 35)
  band(11, 29.5, 31)
  ;[[hood, 2, 9, 146], [roof, 3, 210, 300], [deck, 1, 375, 401]].forEach(function(panel) {
    ;[-1, 1].forEach(function(side) {
      stripe(9, panel[0], panel[1], panel[2], panel[3], 46 * side, 26 * side)
      stripe(10, panel[0], panel[1], panel[2], panel[3], 24 * side, 17 * side)
      stripe(11, panel[0], panel[1], panel[2], panel[3], 15 * side, 11.5 * side)
    })
  })
  // Round the corners in the panel's own coordinates, before projecting onto the car.
  function rounded(poly, radius) {
    var out = []
    poly.forEach(function(p, i) {
      var a = poly[(i + poly.length - 1) % poly.length], b = poly[(i + 1) % poly.length]
      var da = Math.hypot(a[0] - p[0], a[1] - p[1]), db = Math.hypot(b[0] - p[0], b[1] - p[1])
      var r = Math.min(radius, da / 3, db / 3)
      var from = p.map(function(v, k) { return v + (a[k] - v) * r / da })
      var to = p.map(function(v, k) { return v + (b[k] - v) * r / db })
      for (var j = 0; j <= 6; j++) {
        var t = j / 6
        out.push(p.map(function(v, k) { return (1 - t) * (1 - t) * from[k] + 2 * t * (1 - t) * v + t * t * to[k] }))
      }
    })
    return out.concat([out[0]])
  }
  // The flank's decals sit on its lines, each of omarchy.org's lines used once: the race number roundel
  // mid-door between the navy band (y 44) and shoulder (y 72), level with the fender patch; a line reversed
  // out of the navy band under it, one under the door glass and one on the rocker (which slopes in 6 over
  // its 8 height), all centred on the door; and a sun strip across the top of the windscreen, which the
  // inside doesn't show through.
  function onFlank(pts) { return pts.map(function(p) { return flankAt(p[0], p[1]) }) }
  var door = 208
  surface(12, onFlank(arc(door, 59, 11.5, 0, 360, 48, 0)))
  surface(13, onFlank(arc(door, 59, 10, 0, 360, 48, 0)))
  letter(16, "4", door, 59, 12, flankAt)
  letter(15, "WE CAN FIX EVERYTHING", door, 40, 5, flankAt)
  letter(15, "BACKED BY THE OLIGARCHY", door, 20, 4.5, function(u, v) { return [u, v, -78 - (v - 16) * 0.75] })
  letter(14, "UNITE THE NERDS", door, 76, 4, flankAt)
  function fenderAt(u, v) { return flankAt(unwarp(u), v) }
  surface(9, plate(39, 66, 53, 65, 0, 1.5).map(function(p) { return fenderAt(p[0], p[1]) }))
  letter(15, "OMAKASE", 52.5, 59, 4, fenderAt)
  // The mouth is on the flare's front face (x=270), spanning its width, not the side panel.
  // Its painted cheek tapers back into the arch; zAt wraps the livery over that same surface.
  function intakeAt(p, sink) { return [270 + (sink || 0), 31 + p[1], -85 - p[0]] }
  var aperture = [[0, 0], [8, 0], [14, 36], [0, 36]]
  var mouth = rounded(aperture, 0.7), opening = inset(mouth, 0.45)
  var outer = mouth.map(function(p) { return intakeAt(p) }), hole = opening.map(function(p) { return intakeAt(p) })
  // Offset straight edges before rounding, so the throat's corners cannot fold inside out.
  var throat = inset(aperture.concat([aperture[0]]), 3.0)
  var intakeMesh = rounded(throat.slice(0, -1), 0.25).map(function(p) { return intakeAt(p, 1.5) })
  surface(73, hole)
  surface(74, hole)
  surface(74, intakeMesh)
  surface(72, outer)
  surface(72, hole)
  var cheek = along(31, 270, 286)
  for (i = 32; i <= 67; i++) cheek.push([286, i])
  cheek = cheek.concat(flip(along(67, 270, 286)))
  for (i = 66; i >= 31; i--) cheek.push([270, i])
  surface(75, lift(cheek, -1))
  add(outer).underPaint = true
  var edge = [], top = []
  for (i = 0; i <= 12; i++) { edge.push(glassAt(72 * (i / 6 - 1), 44)); top.unshift(glassAt(72 * (i / 6 - 1), 63.7)) }
  surface(9, edge.concat(top))
  letter(15, "OMARCHY", 0, 54, 14, glassAt)
  // Up front: QUATTRO, Omarchy 4's name, in navy across the bumper under the stripes, where the S1
  // carries its sponsor, widened, as the face is seen at a slant; and a red chin, running on round the near
  // corner to the arch, as the S1's lip does.
  letter(14, "QUATTRO", 0, 26, 4.5, function(u, v) { return [-5, v, -u] }, 1.8)
  surface(11, lift([[-9, 15], [-9, 18], [lip(100, 18, -1), 18], [lip(100, 15, -1), 15]], -1))
  surface(11, across(-9, 15, 0).concat(flip(across(-9, 18, 0))))
  // A black lamp panel round the grille, as the S1's, bevel and all: the white hood ends at a crisp edge.
  surface(18, nose)
  // Tyre lettering round each sidewall, top and bottom, turning with the wheel.
  wheels.forEach(function(wheel) {
    ;[[90, "HAVE SOME FUN"], [270, "BEAUTY IS TRUTH"]].forEach(function(side) {
      var n = surfaces.length, a0 = side[0]
      letter(15, side[1], 0, 0, 4, function(u, v) {
        var a = a0 * Math.PI / 180 - u / 26, r = 26 + v
        return grow([wheel.x + r * Math.cos(a), 30 + r * Math.sin(a), -84.5], wheel.x)
      })
      surfaces.slice(n).forEach(function(lettered) { lettered.axle = wheel.x })
    })
  })
  return { edge: edge }
}
