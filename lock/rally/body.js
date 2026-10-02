.pragma library
.import "shape.js" as Shape

var across = Shape.across, along = Shape.along, arc = Shape.arc, arch = Shape.arch, crown = Shape.crown,
  disc = Shape.disc, flip = Shape.flip, level = Shape.level, lift = Shape.lift, lip = Shape.lip,
  mesh = Shape.mesh, plate = Shape.plate, ring = Shape.ring, rrect = Shape.rrect

function build(m) {
  var surface = m.surface, solid = m.solid, atZ = m.atZ, blade = m.blade, chord = m.chord, deck = m.deck,
    face = m.face, fin = m.fin, glass = m.glass, grille = m.grille, hood = m.hood, mirrorArms = m.mirrorArms,
    mirrors = m.mirrors, panes = m.panes, roof = m.roof, spots = m.spots, tail = m.tail, wheels = m.wheels,
    wing = m.wing, wingAt = m.wingAt, wipers = m.wipers, i, side
  surface(0, lift([[4, 72]].concat(tail.slice(1)), -1).concat(flip(arch(322, 202.9, -22.9, -88)), [[284.5, 16, -88]],
    flip(lift(along(24, 142, lip(322, 24, -1)), -1)), [[142, 16, -88]], flip(arch(100, 202.9, -22.9, -88)), lift(face.slice(0, 7), -1)))
  surface(7, lift(along(24, 142, 282.5), -1).concat([[284.5, 16, -88], [282.5, 16, -78], [147.5, 16, -78]]))
  // Fender tops and window pillars share the highlight tone.
  surface(3, lift([[4, 72]].concat(hood, glass.slice(1), deck.slice(1), tail.slice(0, 2),
    [[403, 72]], flip(along(72, 4, 403))), -1))
  // The side windows' opening, B-pillar included: the S1's frames and B-pillar are black.
  var windows = lift([[154, 93], [206, 126], [262, 128], [296, 128], [334, 96], [268, 93], [154, 93]], -1)
  surface(3, windows)
  surface(5, panes[0])
  surface(5, panes[1])
  surface(56, panes[2])
  // The inset seal cuts the windscreen opening out of the body surround.
  var seal = []
  for (i = 0; i <= 12; i++) seal.push(crown(149.3, 92.06, 2, 74 * (i / 6 - 1)))
  for (i = 0; i <= 12; i++) seal.push(crown(207.2, 128.25, 3, 60 * (1 - i / 6)))
  seal.push(seal[0])
  surface(3, across(146, 90, 2).concat(flip(across(210, 130, 3))))
  surface(3, seal)
  surface(27, seal)
  surface(27, panes[2])
  // Paint the C-pillar over decals to hide the far deck stripe behind it.
  surface(32, lift([[296, 128]].concat(glass.slice(20), [[334, 96]]), -1))
  // Black trim round the side windows: each frame with its glass cut out.
  ;[windows, panes[0], panes[1]].forEach(function(pts) { surface(27, pts) })
  surface(2, lift(hood, -1).concat(across(146, 90, 2), flip(lift(hood, 1)), flip(across(8, 76, 2))))
  surface(2, lift(roof.slice(8), -1).concat(across(300, 131, 3), flip(lift(roof.slice(8), 1)), flip(across(210, 130, 3))))
  // Only the deck shows behind the roof; the near C-pillar covers its far corner.
  surface(2, flip(across(403, 98, 1)).concat(flip(lift(deck.slice(0, 2), -1)), flip(lift(glass.slice(20), -1)).slice(1)))
  // Single outlines avoid GPU fill gaps at shared edges; the grille cuts out the lamp panel.
  var lip72 = across(4, 72, 0), chin18 = across(-9, 18, 0), face23 = across(-5, 23, 0)
  var nose = across(4, 53, 0).concat([[4, 69, 88], lip72[lip72.length - 1]], flip(across(8, 76, 2)), [lip72[0], [4, 69, -88]])
  surface(1, nose)
  surface(1, grille)
  // The rounded bumper shares the flank's pigment; the shader supplies its lighting.
  surface(28, across(-9, 15, 0).concat([chin18[chin18.length - 1], face23[face23.length - 1]], flip(across(-5, 49, 0)), [face23[0], chin18[0]]))
  surface(2, across(-5, 49, 0).concat(flip(across(4, 53, 0))))
  surface(3, lift(along(69, 4, 142).concat(flip(along(72, 4, 142))), -1))
  surface(3, lift(along(69, 286, 403).concat(flip(along(72, 286, 403))), -1))
  // The lips' inner walls; tyre walls round the rims, and the treads where they show.
  wheels.forEach(function(wheel) {
    surface(27, arch(wheel.x, -22.9, 202.9, -80))
    surface(4, arch(wheel.x, -22.9, wheel.wall[1], -88).concat(flip(arch(wheel.x, -22.9, wheel.wall[0], -80))))
    surface(7, ring(wheel.x, 30, 30, 72, -84), wheel.x)
    surface(7, flip(ring(wheel.x, 30, 22, 60, -86)), wheel.x)
    surface(8, ring(wheel.x, 30, 22, 60, -86), wheel.x)
    surface(22, ring(wheel.x, 30, 19.5, 60, -85), wheel.x)
    surface(29, mesh(wheel.x, 0), wheel.x)
    surface(29, mesh(wheel.x, 1), wheel.x)
    surface(30, ring(wheel.x, 30, 9, 36, -76), wheel.x)
    surface(18, ring(wheel.x, 30, 5.5, 24, -77), wheel.x)
    // Convex tyre volume stays behind the body when the suspension lifts.
    solid(61, ring(wheel.x, 30, 30, 144, -84).concat(ring(wheel.x, 30, 30, 144, -64)), wheel.x, true)
    // Mudflaps bend backward at the foot.
    var flap = wheel.x + 37
    surface(76, rrect(flap, 1, 24, -88, -64, 2).map(function(p) { return [p[0] + 2 * Math.pow(Math.max(0, 16 - p[1]) / 13, 2), p[1], p[2]] }))
  })
  // Paint the far mirror before the cabin and body hide its inner side.
  ;[[18, 34, 33], [36, 37, 38]].forEach(function(tones, k) {
    surface(tones[0], mirrorArms[k])
    solid(tones[1], mirrors[k].shell)
    surface(tones[2], mirrors[k].rim)
  })
  wipers.forEach(function(w) { surface(40, w.arm); surface(41, w.blade) })
  surface(1, plate(360, 372, 79, 89, -81, 2))
  surface(19, arc(366, 84, 3.2, 0, 360, 24, -81.2))
  // Taillamp: a dark housing, the red lens with an amber band along its top, and a glint.
  surface(7, lift([[403, 77], [386, 77], [386, 93], [403, 93]], -1))
  surface(11, lift([[403, 78], [387, 78], [387, 92], [403, 92], [403, 78]], -1))
  surface(21, lift([[403, 88.5], [387, 88.5], [387, 92], [403, 92]], -1))
  surface(20, lift([[389, 86.5], [393, 86.5], [392.3, 85.3], [388.3, 85.3]], -1))
  // Far fin sits over the deck; near fin hides the plane's end.
  surface(64, atZ(fin, 76))
  surface(65, atZ(blade, 77))
  surface(63, atZ(fin, -76))
  surface(62, wing)
  ;[[69, 46, 26], [70, 24, 17], [71, 15, 11.5]].forEach(function(band) {
    ;[-1, 1].forEach(function(side) {
      surface(band[0], chord.slice(2).map(function(c) { return wingAt(c, 1, side * band[1]) })
        .concat(flip(chord.slice(2)).map(function(c) { return wingAt(c, 1, side * band[2]) })))
    })
  })
  surface(66, atZ(blade, -77))
  // Lens glints are slanted bars on the face plane.
  function glint(x, y, z) { return [[x, y + 0.8, z], [x, y + 0.8, z - 3], [x, y - 0.8, z - 4.5], [x, y - 0.8, z - 1.5]] }
  for (side = -1; side <= 1; side += 2) {
    var lens = rrect(4, 58.5, 67.5, side * 46, side * 84, 2.5)
    surface(57, rrect(4, 57, 69, side * 44, side * 86, 1.5))
    surface(57, lens)
    surface(6, lens)
    surface(19, rrect(4, 63.5, 66.8, side * 48, side * 82, 1.5))
    surface(20, glint(4, 65.5, side < 0 ? -48.5 : 81.5))
    surface(21, rrect(-5, 38.5, 45.5, side * 70, side * 84, 1))
  }
  // Spotlight depth slices merge via winding fill.
  surface(58, [[-6, 45, -52], [-6, 45, 52], [-6, 47.5, 52], [-6, 47.5, -52], [-6, 45, -52]])
  spots.forEach(function(l) {
    ;[4, 3, 2, 1, 0].forEach(function(d) { surface(58, level(disc(l[0] + d, l[1], l[2], l[3]))) })
    surface(17, level(disc(l[0], l[1], l[2], l[3])))
    surface(17, level(disc(l[0], l[1], l[2], l[3] - 1.3)))
    surface(59, level(disc(l[0], l[1], l[2], l[3] - 1.3)))
    surface(60, level(glint(l[0], l[1] + l[3] * 0.45, l[2] + l[3] * 0.55)))
  })
  return { nose: nose }
}
