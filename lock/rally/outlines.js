.pragma library
.import "shape.js" as Shape

var across = Shape.across, along = Shape.along, arc = Shape.arc, arch = Shape.arch, crown = Shape.crown,
  disc = Shape.disc, flip = Shape.flip, grow = Shape.grow, inset = Shape.inset, level = Shape.level,
  lift = Shape.lift, lip = Shape.lip, mesh = Shape.mesh, plate = Shape.plate, ring = Shape.ring,
  rrect = Shape.rrect, screen = Shape.screen, slats = Shape.slats, slope = Shape.slope,
  smooth = Shape.smooth, wallAngles = Shape.wallAngles

function build(m) {
  var add = m.add, i
  // Projection angles for visible tread and arch lips joining the z=-88 opening to the z=-80 wall.
  var wheels = [{ x: 100, tread: [224, 238.7], wall: wallAngles(100) },
    { x: 322, tread: [225, 246.6], wall: wallAngles(322) }]
  // Arch and sill silhouettes, then wheels and flare lips.
  add([[-9, 15, -88]].concat(arch(100, 202.9, -22.9, -88), [[142, 16, -88]]), 3)
  add([[284.5, 16, -88]].concat(arch(322, 202.9, -22.9, -88), [[397, 16, -88]]), 3).underPaint = true
  add(lift([[142, 16], [142, 69], [142, 72]], -1), 1)
  add([[147.5, 16, -78], [282.5, 16, -78], [284.5, 16, -88]], 3)
  for (var w = 0; w < 2; w++) {
    var x = wheels[w].x
    // Tyre, rim lip, BBS cross-spoke mesh dished in to the hub, hub, centre cap and badge.
    var wheel = [
      ring(x, 30, 30, 72, -84), ring(x, 30, 22, 60, -86), ring(x, 30, 19.5, 60, -85),
      mesh(x, 0), mesh(x, 1),
      ring(x, 30, 9, 36, -76), ring(x, 30, 5.5, 24, -77), ring(x, 30, 3, 16, -78)
    ]
    // Wheel parts carry their axle: they turn, and don't pitch with the body. Tyre outline, rim lip panel, the rest fine.
    for (var k = 0; k < wheel.length; k++) add(wheel[k].map(function(p) { return grow(p, x) }), [3, 2, 1][Math.min(k, 2)]).axle = x
    // Tread follows the wheel without turning; omit the rim barrel so it cannot read as a far tyre wall.
    var tread = wheels[w].tread
    var part = add(arc(x, 30, 30, tread[0], tread[1], 10, -64).concat([arc(x, 30, 30, tread[1], tread[1], 1, -84)[0]])
      .map(function(p) { return grow(p, x) }), 2)
    part.axle = x
    part.still = true
    // The flare rolls over into the lip (fine), whose inner edge shows in the arch.
    add(arc(x, 30, 40, 200.5, -20.5, 28, -88), 1)
    add(arch(x, -22.9, wheels[w].wall[0], -80))
  }

  // Near silhouette and visible far edges; soften hood and roof curves.
  var face = [[-9, 15], [-9, 18], [-5, 23], [-5, 49], [-3, 52], [4, 53], [4, 69], [4, 72], [8, 76]]
  var hood = smooth([[8, 76], [80, 85], [146, 90]], 8)
  var roof = smooth([[146, 90], [178, 110], [210, 130]], 4).concat(smooth([[210, 130], [255, 134], [300, 131]], 6).slice(1))
  var glass = roof.concat(smooth([[300, 131], [333, 117], [360, 97]], 8).slice(1))
  var deck = [[360, 97], [393, 98], [403, 98]]
  var tail = [[403, 90], [403, 76], [403, 72], [403, 69], [403, 50], [405, 46], [405, 22], [397, 16]]
  add(lift(face.slice(0, 6), -1), 3).underPaint = true
  add(lift(face.slice(5).concat(hood.slice(1), smooth([[146, 90], [262, 92], [360, 97]], 6).slice(1), deck.slice(1), tail), -1), 3)
  add(lift(glass, -1), 3)
  add(lift(face, 1), 3)
  // Near C-pillar hides the rear glass, far C-pillar and far deck edge.
  add(lift(hood.concat(roof.slice(1)), 1), 3)
  var cross = [across(8, 76, 2), across(146, 90, 2), across(210, 130, 3), across(300, 131, 3),
    across(403, 98, 1), across(4, 72, 0), across(4, 53, 0), across(-3, 52, 0), across(-5, 23, 0), across(-9, 18, 0), across(-9, 15, 0)]
  for (i = 0; i < cross.length; i++) add(cross[i])

  // Door glass starts behind the mirror panel.
  var doorFrame = [[154, 93], [206, 126], [262, 128], [262, 93], [154, 93]]
  var doorGlass = [[200, 93], [200, 122.2], [206, 126], [262, 128], [262, 93], [200, 93]]
  var quarterGlass = [[268, 93], [268, 128], [296, 128], [334, 96], [268, 93]]
  // The glass the interior shows through: side windows inside their frames, and the windscreen's.
  var panes = [lift(inset(doorGlass, 4), -1), lift(inset(quarterGlass, 4), -1)]
  var flank = [
    lift([[-3, 52], [lip(100, 52, -1), 52]], -1), lift([[lip(322, 50, 1), 50], [403, 50]], -1),
    lift(along(24, 142, lip(322, 24, -1)), -1),
    lift([[154, 93], [154, 28.5], [156.5, 26], [259.5, 26], [262, 28.5], [262, 93]], -1),
    lift(doorFrame, -1), panes[0], lift(quarterGlass, -1), panes[1],
    [crown(8, 76, 2, -50), crown(146, 90, 2, -50)], [crown(8, 76, 2, 50), crown(146, 90, 2, 50)]
  ]
  // The hood creases, last, are fine.
  for (i = 0; i < flank.length; i++) add(flank[i], i < flank.length - 2 ? 2 : 1)

  // Headlamps, indicators and grille, then six spotlights as [face x, height, z, radius].
  var front = [], bezels = []
  var low = -8 + slope(46.5), spots = [[-3, 67.5, -33, 9], [-3, 67.5, 33, 9], [low, 46.5, -47, 8.5], [low, 46.5, -19, 8.5], [low, 46.5, 19, 8.5], [low, 46.5, 47, 8.5]]
  for (var side = -1; side <= 1; side += 2) {
    bezels.push(rrect(4, 57, 69, side * 44, side * 86, 1.5))
    front.push(bezels[bezels.length - 1], rrect(4, 58.5, 67.5, side * 46, side * 84, 2.5), rrect(-5, 38.5, 45.5, side * 70, side * 84, 1), slats(side))
  }
  var grille = rrect(4, 56, 70, -40, 40, 1.5)
  front.push(grille, disc(4, 63, -12.75, 6), disc(4, 63, -4.25, 6), disc(4, 63, 4.25, 6), disc(4, 63, 12.75, 6))
  spots.forEach(function(l) { front.push(level(disc(l[0], l[1], l[2], l[3])), level(disc(l[0], l[1], l[2], l[3] - 1.3))) })
  // Headlamp bezels glow when the engine starts. They and the grille are panels, the rest fine.
  for (i = 0; i < front.length; i++) add(front[i], bezels.indexOf(front[i]) >= 0 || front[i] === grille ? 2 : 1).lamp = bezels.indexOf(front[i]) >= 0

  // Windscreen, mirrors, wipers, handle, fuel flap and taillamp.
  var windscreen = []
  for (i = 0; i <= 12; i++) windscreen.push(crown(150.5, 92.8, 2, 72 * (i / 6 - 1)))
  for (i = 0; i <= 12; i++) windscreen.push(crown(206, 127.5, 3, 58 * (1 - i / 6)))
  panes.push(windscreen.concat([windscreen[0]]))
  // A rounded, flattened housing with a broad rear rim.
  function mirrorRing(x, side) {
    var radius = Math.pow(Math.max(0, 1 - Math.pow(Math.abs((x - 168) / 10), 3)), 1 / 3), points = []
    function roundedAxis(v) { return Math.sign(v) * Math.pow(Math.abs(v), 2 / 3) }
    for (var j = 0; j <= 32; j++) {
      var a = j / 16 * Math.PI
      points.push([x, 103 + 5 * radius * roundedAxis(Math.sin(a)), side * (94 + 8 * radius * roundedAxis(Math.cos(a)))])
    }
    return points
  }
  var mirrors = [-1, 1].map(function(side) {
    var shell = []
    ;[158, 158.2, 158.7, 159.5, 161, 163, 166, 168, 170, 172, 174].forEach(function(x) { shell = shell.concat(mirrorRing(x, side)) })
    var rim = mirrorRing(174, side)
    return { shell: shell, rim: rim.slice(24).concat(rim.slice(1, 9)) }
  })
  var mirrorArms = [-1, 1].map(function(side) {
    return [[163, 93, 80], [170, 93, 80], [170, 99, 94], [166, 99, 94]].map(function(p) { return [p[0], p[1], side * p[2]] })
  })
  // Parked wiper arm meets a 44-unit blade.
  function wiper(z) {
    var arm = [], blade = []
    for (var i = 0; i <= 4; i++) { arm.push(screen(152.5 + i * 0.375, z + i * 10)); blade.push(screen(154, z + 18 + i * 11)) }
    return { arm: arm, blade: blade, line: blade.concat([blade[3]], flip(arm)) }
  }
  var wipers = [wiper(-50), wiper(0)]
  // Symmetric NACA wing: 2-unit thickness, 24-unit chord, 1.5-unit rise.
  // wingAt samples upper (+1) or lower (-1) surface at chord fraction c.
  function wingAt(c, s, z) {
    var f = 0.2969 * Math.sqrt(c) - 0.126 * c - 0.3516 * c * c + 0.2843 * c * c * c - 0.1036 * c * c * c * c
    return [384 + 24 * c, 120 + 1.5 * c + s * 10 * f, z]
  }
  var chord = [0, 0.004, 0.012, 0.03, 0.06, 0.1, 0.16, 0.24, 0.34, 0.46, 0.6, 0.75, 0.88, 1]
  function wingEdge(z) { return [0.06, 0.03, 0.012, 0.004].map(function(c) { return wingAt(c, -1, z) }).concat(chord.map(function(c) { return wingAt(c, 1, z) })) }
  var wing = wingEdge(-76).concat(flip(wingEdge(76)), [wingAt(0.06, -1, -76)])
  // White fins close the plane's ends; carbon tips sweep above its trailing edge.
  var fin = [[393, 98], [403, 98], [409.5, 122.1]]
    .concat(flip(chord).map(function(c) { var p = wingAt(c, 1, 0); return [p[0], p[1] + 0.3] }), [[383, 119.7], [393, 98]])
  var blade = smooth([[383, 120.4], [394, 123.6], [404, 126.6], [409, 129.6], [411.8, 129.2], [411.4, 125.6], [409.5, 122.1]], 3)
    .concat(fin.slice(3, -2), [[383, 120.4]])
  function atZ(pts, z) { return pts.map(function(p) { return [p[0], p[1], z] }) }
  // Painted edges belong to the solids; tracing behind the roof must disappear under its paint.
  add(wing, 3).underPaint = true
  add(atZ(fin, -76), 3).underPaint = true
  add(atZ(blade, -77)).underPaint = true
  var details = [
    panes[2],
    mirrors[0].rim, mirrors[1].rim,
    mirrorArms[0].concat([mirrorArms[0][0]]),
    wipers[0].line, wipers[1].line,
    plate(242, 256, 80, 84.5, -81, 2),
    plate(360, 372, 79, 89, -81, 2),
    lift([[403, 78], [387, 78], [387, 92], [403, 92]], -1)
  ]
  for (i = 0; i < details.length; i++) {
    var detail = add(details[i], i === 1 || i === 2 ? 3 : i < 4 || i > 6 ? 2 : 1)
    detail.lamp = i === details.length - 1
  }
  return { wheels: wheels, face: face, hood: hood, roof: roof, glass: glass, deck: deck, tail: tail,
    doorFrame: doorFrame, doorGlass: doorGlass, quarterGlass: quarterGlass, panes: panes, spots: spots,
    grille: grille, windscreen: windscreen, mirrors: mirrors, mirrorArms: mirrorArms, wipers: wipers,
    wingAt: wingAt, chord: chord, wing: wing, fin: fin, blade: blade, atZ: atZ }
}
