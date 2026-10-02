.pragma library
.import "shape.js" as Shape

var crown = Shape.crown, flip = Shape.flip, inset = Shape.inset, lift = Shape.lift, rrect = Shape.rrect,
  smooth = Shape.smooth, zAt = Shape.zAt

function build(m) {
  var add = m.add, surface = m.surface, doorFrame = m.doorFrame, doorGlass = m.doorGlass,
    quarterGlass = m.quarterGlass, i
  // Seat back leans 1:4 from y=60, with its rear surface 5 units behind.
  // Return outlines with their occlusion groups.
  function seat(x0, c, top, tones) {
    function at(z, y, back) { return [x0 + (y - 60) * 0.25 + back, y, c + z * 1.35] }
    function curve(pts, back) { return smooth(pts.map(function(p) { return at(p[0], p[1], back) }), 3) }
    var outline = [[-16, 62], [-17, top - 13], [-15, top - 2], [-10, top + 1], [10, top + 1], [15, top - 2], [17, top - 13], [16, 62]]
    var panel = curve([[-10, 64], [-11, top - 12], [-8, top - 5], [8, top - 5], [11, top - 12], [10, 64]], 0)
    var out = [[curve(outline, 0), "back"], [panel], [curve(outline.slice(0, 5).reverse(), 5), "back"], [[at(10, top + 1, 0), at(10, top + 1, 5)]]]
    surface(tones[0], curve(outline, 5))
    surface(tones[1], curve(outline, 0))
    surface(tones[2], panel)
    // The headrest's back shows its top and near side: from the far top corner round to the near bottom.
    var x = at(0, top + 4, 2)[0], front = rrect(x, top + 4, top + 12, c - 11, c + 11, 3)
    var behind = front.map(function(p) { return [p[0] + 3.5, p[1], p[2]] }), back = behind.slice(4, 11)
    surface(tones[0], behind)
    surface(tones[1], front)
    return out.concat([[front, "head"], [back, "head"], [[front[4], back[0]]], [[front[10], back[6]]],
      [[at(-4, top + 1, 4), [x, top + 4, c - 5.4]]], [[at(4, top + 1, 4), [x, top + 4, c + 5.4]]]])
  }
  // Dashboard, steering and far window frames show only through the panes.
  function wheelAt(a, r) { return [188 + r * Math.sin(a) * 0.48, 95 + r * Math.sin(a) * 0.88, -38 + r * Math.cos(a)] }
  var steering = [], hub = []
  for (i = 0; i <= 36; i++) { steering.push(wheelAt(i / 36 * 2 * Math.PI, 9)); hub.push(wheelAt(i / 36 * 2 * Math.PI, 2.5)) }
  var inside = [
    smooth([[176, 95, -76], [183, 97.5, -40], [183, 97.5, 40], [176, 95, 76]], 8),
    smooth([[181, 97, -54], [184, 103, -38], [181, 97, -22]], 6),
    steering, hub, [wheelAt(0, 2.5), wheelAt(0, 9)], [wheelAt(Math.PI, 2.5), wheelAt(Math.PI, 9)], [wheelAt(-Math.PI / 2, 2.5), wheelAt(-Math.PI / 2, 9)],
    rrect(200, 118, 124, -10, 10, 2), [[200, 124, 0], crown(206, 127.5, 3, 0)],
    lift(doorFrame, 1), lift(quarterGlass, 1)
  ]
  // The dash's own lines, the first two, belong to its solid (see Car.qml's project), so it doesn't hide them.
  for (i = 0; i < inside.length; i++) {
    var piece = add(inside[i])
    piece.inside = true
    if (i < 2) piece.group = "dash"
  }
  // Reverse the binnacle so winding merges it with the dash over the seats and lower steering rim.
  var dash = []
  for (i = 0; i <= 12; i++) dash.push(crown(152, 93.8, 2, 72 * (i / 6 - 1)))
  surface(26, steering)
  surface(31, dash.concat(flip(inside[0])))
  surface(31, flip(inside[1]))
  // Seat backs and headrests occlude other groups, never their own.
  var seats = [[238, -40, 106, [23, 24, 25]], [238, 40, 106, [42, 43, 44]]]
  // Inner shell, far window trim, parcel shelf and sloped bulkhead.
  function shell(x, y, s) { return [x, y, s * zAt(x, y)] }
  function inner(x, y, s) { return [x, y, s * (zAt(x, y) - 7)] }
  surface(55, lift(inset(doorGlass, 2.5), 1))
  surface(55, lift(inset(quarterGlass, 2.5), 1))
  surface(45, lift([[150, 50], [150, 93], [268, 93], [334, 96], [334, 50]], 1))
  surface(45, lift([[154, 93], [206, 126], [200, 122.2], [200, 93]], 1))
  surface(45, lift([[262, 93], [262, 128], [268, 128], [268, 93]], 1))
  surface(45, lift([[296, 128], [334, 96], [360, 97], [333, 117], [300, 131]], 1))
  surface(54, [shell(334, 96, -1), shell(360, 97, -1), shell(360, 97, 1), shell(334, 96, 1)])
  surface(46, [shell(270, 45, -1), shell(334, 96, -1), shell(334, 96, 1), shell(270, 45, 1)])
  // Cage follows the shell just inside the windows; roof and harness bars cross the car.
  function tubes(s) {
    var corner = inner(256, 126, s)
    return [
      [inner(152, 40, s), [156, 92, s * 67], [206, 124, s * 55], corner],
      [inner(154, 62, s), inner(256, 62, s)], [inner(154, 80, s), inner(256, 80, s)], [inner(206, 62, s), inner(206, 80, s)],
      [inner(256, 40, s), inner(256, 93, s), corner],
      [corner, [324, 88, s * 58]]
    ]
  }
  // 4.5-unit tubes use camera-facing bands, highlights and bend discs.
  // Keep winding consistent so overlapping bands merge.
  var depth = [0.49, -0.199, 0.849], up = [0.0993, 0.98, 0.172], rightward = [0.866, 0, -0.5]
  function vcross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
  function vdot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
  function move(p, v, k) { return [p[0] + v[0] * k, p[1] + v[1] * k, p[2] + v[2] * k] }
  var facing = vdot(vcross(rightward, up), depth) > 0
  function tube(pts, tones) {
    for (var i = 0; i < pts.length - 1; i++) {
      var a = pts[i], b = pts[i + 1], t = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], o = vcross(t, depth)
      var k = (vdot(o, up) < 0 ? -2.25 : 2.25) / Math.hypot(o[0], o[1], o[2])
      o = o.map(function(v) { return v * k })
      var turn = (vdot(vcross(t, o), depth) > 0) !== facing
      ;[[-1, 1], [-0.15, 1], [0.35, 0.7]].forEach(function(w, n) {
        var q = [move(a, o, w[0]), move(b, o, w[0]), move(b, o, w[1]), move(a, o, w[1])]
        surface(tones[n], turn ? flip(q) : q)
      })
      // Only at a bend: on a smooth curve discs bead the tube.
      if (i === 0) continue
      var u = [a[0] - pts[i - 1][0], a[1] - pts[i - 1][1], a[2] - pts[i - 1][2]]
      if (vdot(u, t) > 0.97 * Math.hypot(u[0], u[1], u[2]) * Math.hypot(t[0], t[1], t[2])) continue
      ;[[0, 2.25], [0.96, 1.29]].forEach(function(d, n) {
        var ring = []
        for (var j = 0; j < 16; j++) ring.push(move(move(move(a, up, d[0]), rightward, d[1] * Math.cos(j * Math.PI / 8)), up, d[1] * Math.sin(j * Math.PI / 8)))
        surface(tones[n], ring)
      })
    }
  }
  tubes(1).concat([[[206, 124, -55], [206, 126.5, 0], [206, 124, 55]],
    [inner(256, 126, -1), [256, 129.5, -46], [256, 131, 0], [256, 129.5, 46], inner(256, 126, 1)],
    [inner(256, 104, -1), inner(256, 104, 1)], [inner(256, 84, -1), inner(256, 84, 1)]]).forEach(function(pts) { tube(pts, [47, 48, 50]) })
  tubes(-1).forEach(function(pts) { tube(pts, [51, 52, 53]) })
  // The driver's harness: two red straps over the seat's top and down its front, closing in.
  ;[-8, 8].forEach(function(d) { surface(49, [[251, 108, -40 + d], [249.75, 107.5, -40 + d], [242.5, 78, -40 + d * 0.5]]) })
  seats.forEach(function(spec, n) {
    seat(spec[0], spec[1], spec[2], spec[3]).forEach(function(line) {
      var part = add(line[0])
      part.inside = true
      part.group = n
      if (line[1]) part.cover = n + line[1]
    })
  })
  return { inside: inside, dash: dash }
}
