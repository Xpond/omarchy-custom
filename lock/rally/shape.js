.pragma library

// The car's shape, and the curves every part is drawn with. Design units are about centimetres:
// x along the car, y up, z across it, the near side negative.

// Half-width: the doors 84 up to the shoulder (y 72), leaning in to the belt (y 90) and on to the roof.
// Box flares stand 4 proud below the shoulder: the front one steps out over 2 units up to x 143;
// the rear one swells from just behind the door (x 264) and is full by its arch's lip (x 282).
function zAt(x, y) {
  var body = y <= 72 ? 84 : y <= 90 ? 84 - (y - 72) / 18 * 4 : 80 - Math.min(40, y - 90) / 40 * 18
  var k = Math.min(1, Math.max(0, (143 - x) / 2 + 0.5, (x - 264) / 18))
  var flare = body + 4 * k * k * (3 - 2 * k) * Math.min(1, Math.max(0, (72 - y) / 3))
  // The forward-facing inlet's outer cheek rejoins the arch at x=286.
  if (x >= 270 && x < 286 && y >= 26 && y <= 72) {
    var blend = Math.min(1, (y - 26) / 5, (72 - y) / 5)
    blend = blend * blend * (3 - 2 * blend)
    flare += (8 + (Math.max(31, Math.min(67, y)) - 31) / 6) * Math.pow((286 - x) / 16, 2) * blend
  }
  return flare
}
function lift(pts, s) { return pts.map(function(p) { return [p[0], p[1], s * zAt(p[0], p[1])] }) }
// The nose is drawn 10 longer than the car's: every outline and surface is warped as it's added, the
// front face (x 8 and ahead) moving back whole and the fender ahead of the front arch (x 8-58) closing
// up, so from the arch back nothing moves. unwarp places a decal there undistorted.
// Before that the bumper is shaped, after the S1's: below the lamp panel (y 53) it leans forward toward
// the bottom, 0.35 a unit down to its foot (y 23), so its ledge is a bevel and its foot and chin jut; and
// its near corner is rounded in plan, radius 8, easing out over the last 4 below the panel, so it wraps
// round into the flank, its edge leaning with the face (a radius growing downward undid the lean there).
// The far corner, seen edge-on, stays square: rounded, its bulge stood past the face's outline. The round
// moves the face back onto it and the flank's front edge back to its end, but leaves the flank behind that.
// level() stands a part upright on the lean: the spotlights.
function slope(y) { return y >= 53 ? 0 : (Math.max(23, y) - 36) * 0.35 }
function level(pts) { return pts.map(function(p) { return [p[0] - slope(p[1]), p[1], p[2]] }) }
function faceAt(y) { return y <= 18 ? -9 : y <= 23 ? -9 + (y - 18) * 0.8 : y <= 49 ? -5 : -5 + (y - 49) * 2 / 3 }
function shape(p) {
  var x = p[0], y = p[1]
  if (x >= 8 || y >= 53) return p
  var r = 8 * Math.min(1, (53 - y) / 4), d = Math.min(r, Math.max(0, -p[2] - 88 + r))
  if (d > 0) x = Math.max(x, faceAt(y) + r - Math.sqrt(r * r - d * d))
  return [x + slope(y), y, p[2]]
}
function warp(p) { p = shape(p); var x = p[0]; return [x <= 8 ? x + 10 : x < 58 ? 18 + (x - 8) * 0.8 : x, p[1], p[2]] }
function unwarp(x) { return x <= 18 ? x - 10 : x < 58 ? 8 + (x - 18) / 0.8 : x }
// Wheels are drawn at radius 30 and grown to 32 about their axle (at height 30), so the tyres fill
// their arches as the real car's do.
function grow(p, axle) { return [axle + (p[0] - axle) * 16 / 15, 30 + (p[1] - 30) * 16 / 15, p[2]] }
// A flank line at height y, every 2 units, so it follows the flares.
function along(y, x0, x1) {
  var pts = []
  for (var x = x0; x < x1; x += 2) pts.push([x, y])
  return pts.concat([[x1, y]])
}
// Catmull-Rom through the points, n steps a span, so a few points make a soft edge.
function smooth(pts, n) {
  var out = [pts[0]]
  for (var i = 0; i < pts.length - 1; i++) {
    var a = pts[Math.max(0, i - 1)], b = pts[i], c = pts[i + 1], d = pts[Math.min(pts.length - 1, i + 2)]
    for (var j = 1; j <= n; j++) {
      var t = j / n
      out.push(b.map(function(_, k) {
        return b[k] + 0.5 * t * (c[k] - a[k] + t * (2 * a[k] - 5 * b[k] + 4 * c[k] - d[k] + t * (3 * b[k] - a[k] - 3 * c[k] + d[k])))
      }))
    }
  }
  return out
}
// Arc in the side plane z, from a0 to a1 degrees.
function arc(cx, cy, r, a0, a1, n, z) {
  var pts = []
  for (var i = 0; i <= n; i++) { var a = (a0 + (a1 - a0) * i / n) * Math.PI / 180; pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a), z]) }
  return pts
}
// Both edges of a wheel opening use the same two-degree grid. Independently
// tessellated arcs left slivers where the body and its inner return meet.
function arch(x, a0, a1, z) {
  var pts = [], step = a1 > a0 ? 2 : -2
  function at(a) { a *= Math.PI / 180; return [x + 36 * Math.cos(a), 30 + 36 * Math.sin(a), z] }
  pts.push(at(a0))
  for (var a = step > 0 ? Math.floor(a0 / 2) * 2 + 2 : Math.ceil(a0 / 2) * 2 - 2; (a1 - a) * step > 0; a += step) pts.push(at(a))
  pts.push(at(a1))
  return pts
}
// Exact meeting of the projected z=-88 opening and z=-80 inner edge.
// Camera matches Car.qml's project(): yaw pi/6, pitch 0.2, distance 1400.
function wallAngles(x) {
  var camera = [221 - 700 * Math.cos(0.2), 60 + 1400 * Math.sin(0.2), -1400 * Math.cos(Math.PI / 6) * Math.cos(0.2)]
  var k = (-80 - camera[2]) / (-88 - camera[2]), lo = 0, hi = Math.PI / 2, q
  for (var i = 0; i < 40; i++) {
    var a = (lo + hi) / 2
    q = [camera[0] + k * (x + 36 * Math.cos(a) - camera[0]), camera[1] + k * (30 + 36 * Math.sin(a) - camera[1])]
    if (Math.hypot(q[0] - x, q[1] - 30) > 36) lo = a
    else hi = a
  }
  return [Math.atan2(q[1] - 30, q[0] - x) * 180 / Math.PI, a * 180 / Math.PI]
}
function ring(cx, cy, r, n, z) { return arc(cx, cy, r, 0, 360, n, z) }
// A point on a panel crowned by lift at the middle, and a line across the car along it.
function crown(x, y, lift, z) { return [x, y + lift * (1 - Math.pow(z / zAt(x, y), 2)), z] }
// A flat one (lift 0) runs denser near its ends, where the bumper's corners round off.
function across(x, y, lift) {
  var ks = []
  for (var i = 0; i <= 12; i++) ks.push(i / 6 - 1)
  if (!lift) ks = [-1, -0.99, -0.97, -0.94, -0.9].concat(ks.slice(1, 12), [0.9, 0.94, 0.97, 0.99, 1])
  return ks.map(function(k) { return crown(x, y, lift, zAt(x, y) * k) })
}
// Where the flare lip around an axle meets height y, ahead (-1) or behind (1).
function lip(axle, y, side) { return axle + side * Math.sqrt(1600 - (y - 30) * (y - 30)) }
// Ten spokes zigzag from hub to rim; a second pass, offset by one tooth, crosses them.
function mesh(x, pass) {
  var pts = []
  for (var k = 0; k <= 20; k++) {
    var a = (k + pass) / 20 * 2 * Math.PI, r = k % 2 ? 19.5 : 9
    pts.push([x + r * Math.cos(a), 30 + r * Math.sin(a), k % 2 ? -85 : -76])
  }
  return pts
}
// Rounded rectangle on a face plane x, corners of radius r.
function rrect(x, y0, y1, za, zb, r) {
  var z0 = Math.min(za, zb), z1 = Math.max(za, zb), pts = []
  var corners = [[z1 - r, y1 - r, 0], [z0 + r, y1 - r, 90], [z0 + r, y0 + r, 180], [z1 - r, y0 + r, 270]]
  corners.forEach(function(c) {
    for (var j = 0; j <= 4; j++) { var a = (c[2] + j * 22.5) * Math.PI / 180; pts.push([x, c[1] + r * Math.sin(a), c[0] + r * Math.cos(a)]) }
  })
  return pts.concat([pts[0]])
}
// Circle on a face plane x.
function disc(x, y, z, r) {
  var pts = []
  for (var j = 0; j <= 32; j++) { var a = j / 32 * 2 * Math.PI; pts.push([x, y + r * Math.sin(a), z + r * Math.cos(a)]) }
  return pts
}
// Six grille slats on one side, from the frame to the outer ring, as one serpentine that
// steps along the frame and along the ring, so no step shows.
function slats(side) {
  var pts = [], zc = side * 12.75
  function edge(y) { return [4, y, zc + side * Math.sqrt(36 - (y - 63) * (y - 63))] }
  for (var j = 0; j < 6; j++) {
    var y = 68 - j * 2
    if (j % 2) {
      for (var t = 1; t < 4; t++) pts.push(edge(y + 2 - t / 2))
      pts.push(edge(y), [4, y, side * 40])
    } else pts.push([4, y, side * 40], edge(y))
  }
  return pts
}
// Rounded rectangle on a side plane z.
function plate(x0, x1, y0, y1, z, r) {
  return rrect(0, y0, y1, x0, x1, r).map(function(p) { return [p[2], p[1], z] })
}
// A closed convex outline in the side plane, moved in by d: the glass inside its frame.
function inset(poly, d) {
  var n = poly.length - 1, area = 0, lines = [], out = []
  for (var i = 0; i < n; i++) area += poly[i][0] * poly[i + 1][1] - poly[i + 1][0] * poly[i][1]
  for (i = 0; i < n; i++) {
    var a = poly[i], b = poly[i + 1], k = (area > 0 ? d : -d) / Math.hypot(b[0] - a[0], b[1] - a[1])
    lines.push([a[0] - (b[1] - a[1]) * k, a[1] + (b[0] - a[0]) * k, b[0] - a[0], b[1] - a[1]])
  }
  for (i = 0; i < n; i++) {
    var p = lines[(i + n - 1) % n], q = lines[i], den = p[2] * q[3] - p[3] * q[2]
    var t = Math.abs(den) < 1e-9 ? 1 : ((q[0] - p[0]) * q[3] - (q[1] - p[1]) * q[2]) / den
    out.push([p[0] + p[2] * t, p[1] + p[3] * t])
  }
  return out.concat([out[0]])
}
// A point just above the windscreen, which rises 0.625 a unit from the cowl.
function screen(x, z) { var p = crown(x, 90 + (x - 146) * 0.625, 2, z); p[1] += 0.6; return p }
function flip(pts) { return pts.slice().reverse() }

// The outlines and surfaces the parts add, in order. Parts also hand on, through it, what later ones use.
function builder() {
  var list = [], surfaces = []
  // Each outline is traced at a comet's pace: 900 units a second, never quicker than 300ms,
  // and drawn at a weight: 3 the body's outline, 2 its panels (the default), 1 fine detail.
  // They set off in the order they're added, one every pace ms, so the same handful is ever in
  // flight and the car builds at an even rate: sills, wheels, body, glass, then the cabin seen
  // through it. Timing each group from its own base instead let groups overlap, which stalled
  // the trace between them and then landed half the car at once.
  var pace = 22
  function add(pts, weight) {
    pts = pts.map(warp)
    var cum = [0]
    for (var i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]))
    var len = cum[cum.length - 1], start = list.length * pace
    var part = { pts: pts, cum: cum, len: len, start: start, end: start + Math.max(300, len / 0.9), weight: weight === undefined ? 2 : weight }
    list.push(part)
    return part
  }

  // Painted surfaces by tone (see Car.qml's paint). A tone fills even-odd, so an outline inside another is a hole:
  // windows and grille; the wheel wells have dark backing. Rubber and the dash fill by winding
  // instead (the rim's hole runs backwards). Surfaces on a wheel
  // carry its axle and turn with it, but for those that are still, like the treads.
  function surface(tone, pts, axle, still) { surfaces.push({ tone: tone, pts: pts.map(function(p) { return warp(axle === undefined ? p : grow(p, axle)) }), axle: axle, still: still }) }
  function solid(tone, pts, axle, still) { surface(tone, pts, axle, still); surfaces[surfaces.length - 1].hull = true }
  return { parts: list, surfaces: surfaces, add: add, surface: surface, solid: solid }
}
