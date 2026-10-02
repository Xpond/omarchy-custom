import QtQuick
import qs.Commons
import "model.js" as Model

// GPU paths trace the car; completed outlines are cached until another lands.
Item {
  id: car

  property Item environment
  property color lineColor: Color.lock.text
  // Fixed blue keeps comets distinct from the theme's lines and accent.
  property color glowColor: "#7fd4ff"
  property real clock: duration
  // Drive-off timeline, 0..1 over driveTime.
  property real drive: 0
  // Levels: inside/far, fine, panels, outline, under paint. Body and wheel paths stay separate;
  // comets and streaks use three heat levels.
  property var lines: [[], [], [], [], []]
  property var wheelLines: [[], [], [], [], []]
  property var tracing: [[], [], [], [], []]
  property var comets: [[], [], []]
  property var streaks: [[], [], []]
  // Tones with an ink width are stroked; Paintwork.qml sets the draw order.
  readonly property var paint: [
    "#f2f2ee", "#f2f2ee", "#f6f6f3", "#e9eae8", "#f2f2ee",    // 0-4 bodywork: flank, sides and front, tops, upper sides, shadow
    "#26121a24", "#9fb3c3", "#1c1d1f", "#dcb865",               // 5-8 tinted glass, lamp lenses, rubber, polished rim lips
    "#1c2c5e", "#3aa3e0", "#d42a2a", "#141414", "#f2f2ee",    // 9-13 decals: navy, blue, red, black, white
    "#1c2c5e", "#f2f2ee", "#141414",                           // 14-16 lettering: navy, white, black
    "#d9dce0", "#1d1f23", "#d3dee7", "#ffffff", "#e8963a",    // 17-21 the spotlights' chrome rims, the black lamp panel and centre caps, lens tops, glints, indicators
    "#2e281c",                                                 // 22 the dark dish behind the mesh
    "#1d1f23", "#3a3e45", "#2c3d70", "#5b6069",               // 23-26 inside: seat backs, seats, seat panels, steering
    "#0b0c0e",                                                 // 27 window trim
    "#f2f2ee", "#caa652", "#caa652",                          // 28-30 rounded bumper (same pigment as flank 0), gold mesh spokes, hubs
    "#3a3e46",                                                 // 31 the dash's top
    "#1c2c5e",                                                 // 32 the C-pillar, over the decals
    "#080b11", "#141c29", null,                                // 33-35 near mirror rim and shell; spare slot
    "#1d1f23", "#141c29", "#080b11", null,                     // 36-39 far mirror mount, shell, rim; spare slot
    "#5b6069", "#5b6069",                                      // 40-41 the wipers' arms and blades, over their lines
    "#141518", "#2a2d33", "#212c52",                           // 42-44 inside, deeper in shadow: the far seat's back, face and panel
    "#c2c4c0", "#9c9e9a",                                      // 45-46 the cabin's shell, mid grey under the dark cage: far side (shaded, see cabin), bulkhead
    "#141518", "#2c2e33", "#c4262b", "#50535a",                // 47-50 the roll cage's far tubes, dark on the grey shell: shadow, body; harness straps; highlight
    "#141518", "#2c2e33", "#50535a",                           // 51-53 its near tubes, over the seats: shadow, body, highlight
    "#8a8c88", "#a07d8a96",                                    // 54-55 the parcel shelf; the far windows from inside, showing out
    "#38d8dee2",                                               // 56 the windscreen, catching the sky: lighter than the side glass
    "#c9cdd2", "#16171a", "#c3d0da", "#ffffff",              // 57-60 the headlamps' chrome bezels; the spotlights' cans and bar, lenses, glints
    "#161719",                                                // 61 full tyre volume behind the body and sidewall
    "#f6f6f3", "#f2f2ee", "#aeb0ad", "#141518", "#1d1f23",    // 62-66 the wing: plane, near and far fins, far and near carbon tips
    "#6a707c", null, "#1c2c5e", "#3aa3e0", "#d42a2a",         // 67-71 the tips' rims; spare slot; the wing's stripes
    "#f2f2ee", "#090c10", "#f2f2ee", "#f2f2ee",               // 72-75 intake lip, screen, inner return and painted outer cheek
    "#c79943"]                                                 // 76 mud flaps
  readonly property var ink: ({ 14: 2.2, 15: 1.6, 16: 2.2, 26: 2.6, 29: 1.4, 40: 1.8, 41: 1, 49: 5, 33: 0.6, 38: 0.6 })
  // Paint starts after the last outline lands.
  readonly property real painted: Math.min(1, Math.max(0, (clock - traced) / paintTime))
  readonly property color gapColor: "#15171a"
  // Parked body polygons move via bodyPose; wheels are reprojected as they turn.
  property var bodywork: paint.map(function() { return [] })
  property var wheels: paint.map(function() { return [] })
  // Screen x-bounds include one pixel of padding so the paint sweep starts and ends clear.
  property var span: null
  readonly property real front: span ? Math.max(0, span[0] + (span[1] - span[0]) * painted) : 0
  readonly property bool coating: painted < 1
  property var wavefront: []
  // The cabin's far side, lit from the belt down to the floor's shadow, as screen points.
  property var cabin: [Qt.point(0, 0), Qt.point(0, 1)]
  // The near tyres' contact points, as screen points: the floor mirrors the car about the line through them.
  property var ground: [Qt.point(0, 1), Qt.point(1, 1)]
  readonly property matrix4x4 mirror: {
    var a = ground[0], k = (ground[1].y - a.y) / (ground[1].x - a.x)
    return Qt.matrix4x4(1, 0, 0, 0, 2 * k, -1, 0, 2 * (a.y - k * a.x), 0, 0, 1, 0, 0, 0, 0, 1)
  }
  property int finished: -1
  // Projection and flat pose transform, rebuilt on resize.
  property var view: null
  property var stance: null
  property size projected
  property var focusHeights: Qt.point(1, 0)
  // Drive-off: milliseconds, wheel radians, launch/lamp progress, and pose [pitch, shake].
  readonly property int driveTime: 1100
  property real rolled: 0
  property real launch: 0
  property real lamps: 0
  property var glowing: []
  property var pose: [0, 0]
  property matrix4x4 bodyPose
  // Speed streaks trail from these: headlamps, taillamp, mirror, roof, chassis ends, tyres.
  readonly property var streakFrom: [[14, 63, -80], [14, 63, -59], [14, 63, 59], [14, 63, 80], [401, 85, -81], [167.4, 103, -100],
    [210, 130, -64], [300, 131, -64], [210, 130, 64], [1, 15, -88], [397, 16, -88], [100, -2, -88], [322, -2, -88]]
  readonly property var model: Model.carModel()
  readonly property var parts: model.parts
  // Trace and paint durations in milliseconds.
  readonly property int traced: Math.ceil(parts.reduce(function(end, part) { return Math.max(end, part.end) }, 0))
  readonly property int paintTime: 600
  readonly property int duration: traced + paintTime
  // Matches the wheel's 2px comet ring at 1080p.
  readonly property real base: Math.max(1, height / 540)

  Paintwork { car: parent }

  // The line color at alpha a, moved toward color to at alpha b as the paint comes in.
  function settle(a, to, b) {
    var c = lineColor, t = painted
    return Qt.rgba(c.r + (to.r - c.r) * t, c.g + (to.g - c.g) * t, c.b + (to.b - c.b) * t, a + (b - a) * t)
  }

  // Clip inside outlines to the visible glass runs.
  function pieces(part, a, b, dx, dy) {
    if (!part.runs) return [slice(part, a, b, dx, dy)]
    var out = []
    part.runs.forEach(function(run) { if (Math.min(b, run[1]) > Math.max(a, run[0])) out.push(slice(part, Math.max(a, run[0]), Math.min(b, run[1]), dx, dy)) })
    return out
  }

  // Whether a screen point is inside a closed screen outline (even-odd).
  function contains(poly, q) {
    var c = false
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++)
      if ((poly[i][1] > q[1]) !== (poly[j][1] > q[1]) && q[0] < (poly[j][0] - poly[i][0]) * (q[1] - poly[i][1]) / (poly[j][1] - poly[i][1]) + poly[i][0]) c = !c
    return c
  }

  // Screen point, with its depth, at distance d along an outline.
  function pointAt(part, d) {
    var c = part.cum, s = part.screen, j = 1
    while (j < c.length - 1 && c[j] < d) j++
    var k = (d - c[j - 1]) / Math.max(1e-6, c[j] - c[j - 1])
    return [0, 1, 2].map(function(i) { return s[j - 1][i] + (s[j][i] - s[j - 1][i]) * k })
  }

  // Reuse unchanged tone lists to avoid rebuilding their shapes.
  function shade(wheel, all) {
    var out = paint.map(function() { return [] }), changed = [], c = Math.cos(rolled), sn = Math.sin(rolled)
    // Cache Qt.point lookup in the projection loop.
    var point = Qt.point
    model.surfaces.forEach(function(s) {
      if ((s.axle !== undefined) !== wheel) return
      if (all || !s.still) {
        var pts = s.pts.map(!wheel || s.still ? view : function(p) { return view(turn(p, s.axle, c, sn)) })
        s.poly = (s.hull ? hull(pts) : pts).map(function(q) { return point(q[0], q[1]) })
        changed[s.tone] = true
      }
      out[s.tone].push(s.poly)
    })
    var was = wheel ? wheels : bodywork
    return out.map(function(tone, n) { return changed[n] || !tone.length ? tone : was[n] })
  }

  // Pair sorted crossings so the paint edge follows the car's silhouette.
  function cuts() {
    var out = []
    bodywork.concat(wheels).forEach(function(tone) { tone.forEach(function(poly) {
      var hits = []
      for (var i = 0; i < poly.length; i++) {
        var a = poly[i], b = poly[(i + 1) % poly.length]
        if ((a.x < front) !== (b.x < front)) hits.push(Qt.point(front, a.y + (b.y - a.y) * (front - a.x) / (b.x - a.x)))
      }
      hits.sort(function(a, b) { return a.y - b.y })
      for (i = 0; i + 1 < hits.length; i += 2) out.push([hits[i], hits[i + 1]])
    }) })
    return out
  }

  function turn(p, axle, c, s) {
    var dx = p[0] - axle, dy = p[1] - 30
    return [axle + dx * c - dy * s, 30 + dx * s + dy * c, p[2]]
  }

  // A point on the body, pitched nose-up about the rear axle and shaken.
  function pitched(p, pitch, shake) {
    var dx = p[0] - 322, dy = p[1] - 30, c = Math.cos(pitch), s = Math.sin(pitch)
    return [322 + dx * c + dy * s, 30 - dx * s + dy * c + shake, p[2]]
  }

  function roll() {
    var c = Math.cos(rolled), s = Math.sin(rolled)
    parts.forEach(function(part) {
      if (part.axle === undefined || part.still) return
      part.screen = part.pts.map(function(p) { return view(turn(p, part.axle, c, s)) })
      part.whole = pieces(part, 0, part.len, 0, 0)
    })
    wheelLines = landed(true)
    wheels = shade(true, false)
  }

  // The landed outlines by level, of the wheels or of the body.
  function landed(wheel) {
    var still = [[], [], [], [], []]
    parts.forEach(function(part) {
      if (clock >= part.end && (part.axle !== undefined) === wheel) still[part.level].push.apply(still[part.level], part.whole)
    })
    return still
  }

  // Convex hull of screen points (monotone chain): the silhouette of a solid.
  function hull(pts) {
    pts = pts.slice().sort(function(a, b) { return a[0] - b[0] || a[1] - b[1] })
    function half(list) {
      var h = []
      list.forEach(function(p) {
        while (h.length > 1 && (h[h.length - 1][0] - h[h.length - 2][0]) * (p[1] - h[h.length - 2][1]) - (h[h.length - 1][1] - h[h.length - 2][1]) * (p[0] - h[h.length - 2][0]) <= 0) h.pop()
        h.push(p)
      })
      return h.slice(0, -1)
    }
    return half(pts).concat(half(pts.slice().reverse()))
  }

  // Screen polyline of an outline from distance a to b along it, shifted by (dx, dy).
  function slice(part, a, b, dx, dy) {
    var c = part.cum, s = part.screen, point = Qt.point
    function at(d) { var p = pointAt(part, d); return point(p[0] + dx, p[1] + dy) }
    var out = [at(a)]
    for (var i = 1; i < c.length - 1; i++) if (c[i] > a && c[i] < b) out.push(point(s[i][0] + dx, s[i][1] + dy))
    out.push(at(b))
    return out
  }

  // Project once per size; the car stays still during tracing.
  function project() {
    if (projected.width === width && projected.height === height) return
    projected = Qt.size(width, height)
    // About 480 units wide at this angle; roof to near wheel about 200 tall.
    var S = Math.min(width * 0.88 / 480, height * 0.8 / 200), cx = width / 2, cy = height / 2 - 4 * S, D = 1400
    var cyaw = Math.cos(Math.PI / 6), syaw = Math.sin(Math.PI / 6), cp = Math.cos(0.2), sp = Math.sin(0.2)
    view = function(p) {
      var x = p[0] - 221, y = p[1] - 60
      var x1 = x * cyaw - p[2] * syaw, z1 = x * syaw + p[2] * cyaw
      var y2 = y * cp + z1 * sp, z2 = -y * sp + z1 * cp, k = D / (D + z2)
      return [cx + x1 * k * S, cy - y2 * k * S, z2]
    }
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i], z = 0
      part.screen = part.pts.map(function(p) { var q = view(p); z += q[2]; return q })
      // Depth dims outlines and lowers their weight toward the inside level.
      var bright = Math.max(0.3, Math.min(0.95, 0.95 - (z / part.pts.length + 120) / 240 * 0.65))
      part.level = part.underPaint ? 4 : part.inside ? 0 : Math.max(0, part.weight + Math.floor(bright * 4) - 3)
      part.whole = pieces(part, 0, part.len, 0, 0)
      // Half-step golden angles avoid zero components in the offscreen intersection.
      var mx = 0, my = 0, r = 0, a = (i + 0.5) * 2.39996
      part.screen.forEach(function(p) { mx += p[0] / part.screen.length; my += p[1] / part.screen.length })
      part.screen.forEach(function(p) { r = Math.max(r, Math.hypot(p[0] - mx, p[1] - my)) })
      var ux = Math.cos(a), uy = Math.sin(a)
      var out = Math.min(ux > 0 ? (width - mx) / ux : -mx / ux, uy > 0 ? (height - my) / uy : -my / uy) + r
      part.fly = [ux * out, uy * out]
    }
    // Sample visible glass runs every unit, clipping against other groups' solids at mean depth.
    var panes = model.panes.map(function(pane) { return pane.map(view) })
    var solids = { dash: { group: "dash", pts: model.dash.map(view) } }
    parts.forEach(function(part) {
      if (!part.cover) return
      var solid = solids[part.cover] = solids[part.cover] || { group: part.group, pts: [] }
      solid.pts = solid.pts.concat(part.screen)
    })
    solids = Object.keys(solids).map(function(key) {
      var solid = solids[key]
      return { group: solid.group, hull: hull(solid.pts), depth: solid.pts.reduce(function(sum, p) { return sum + p[2] }, 0) / solid.pts.length }
    })
    parts.forEach(function(part) {
      if (!part.inside) return
      var runs = [], from = -1
      for (var d = 0; d <= part.len; d++) {
        var q = pointAt(part, d)
        var seen = panes.some(function(pane) { return contains(pane, q) }) && !solids.some(function(solid) {
          return solid.group !== part.group && q[2] > solid.depth && contains(solid.hull, q)
        })
        if (seen && from < 0) from = d
        if (!seen && from >= 0) { runs.push([from, d - 1]); from = -1 }
      }
      if (from >= 0) runs.push([from, part.len])
      part.runs = runs
      part.whole = pieces(part, 0, part.len, 0, 0)
    })
    bodywork = shade(false, true)
    wheels = shade(true, true)
    focusHeights = Qt.point(view([322, 62, -84])[1], view([300, 131, 64])[1])
    glowing = parts.filter(function(part) { return part.lamp }).map(function(part) { return part.whole[0] })
    // Fit an affine drive-off pose over every eighth body point; centering separates the equations.
    // stance returns [a, b, c, d, e, f] for (ax + by + c, dx + ey + f).
    var fit = [], mx = 0, my = 0, xx = 0, xy = 0, yy = 0
    parts.forEach(function(part) { if (part.axle === undefined) part.pts.forEach(function(p, i) { if (i % 8 === 0) fit.push(p) }) })
    var at = fit.map(view)
    at.forEach(function(q) { mx += q[0] / at.length; my += q[1] / at.length })
    at.forEach(function(q) { xx += (q[0] - mx) * (q[0] - mx); xy += (q[0] - mx) * (q[1] - my); yy += (q[1] - my) * (q[1] - my) })
    var det = xx * yy - xy * xy, last = [], fitted
    stance = function(pitch, shake) {
      if (!pitch && !shake) return [1, 0, 0, 0, 1, 0]
      // The launch holds its pose.
      if (pitch === last[0] && shake === last[1]) return fitted
      last = [pitch, shake]
      var s = [0, 0, 0, 0, 0, 0]
      fit.forEach(function(p, i) {
        var q = view(pitched(p, pitch, shake)), x = at[i][0] - mx, y = at[i][1] - my
        s[0] += x * q[0]; s[1] += y * q[0]; s[2] += q[0]; s[3] += x * q[1]; s[4] += y * q[1]; s[5] += q[1]
      })
      var a = (yy * s[0] - xy * s[1]) / det, b = (xx * s[1] - xy * s[0]) / det
      var d = (yy * s[3] - xy * s[4]) / det, e = (xx * s[4] - xy * s[3]) / det
      return fitted = [a, b, s[2] / at.length - a * mx - b * my, d, e, s[5] / at.length - d * mx - e * my]
    }
    // The paint has to cross every painted point: mirrors and bumper reach past the bodywork.
    var lo = Infinity, hi = -Infinity
    bodywork.concat(wheels).forEach(function(tone) { tone.forEach(function(poly) { poly.forEach(function(q) {
      if (q.x < lo) lo = q.x
      if (q.x > hi) hi = q.x
    }) }) })
    span = [lo - 1, hi + 1]
    cabin = [[290, 96, 78], [290, 50, 78]].map(function(p) { var q = view(p); return Qt.point(q[0], q[1]) })
    ground = [[100, -2, -88], [322, -2, -88]].map(function(p) { var q = view(p); return Qt.point(q[0], q[1]) })
    finished = -1
    frame()
  }

  function frame() {
    if (!parts[0].whole) return
    var done = 0, drawn = [[], [], [], [], []], heat = [[], [], []]
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i]
      if (clock >= part.end) { done++; continue }
      if (clock <= part.start) continue
      // The comet's tail spans 12% of its outline, like the logo's, and at least 110 units.
      var k = (clock - part.start) / (part.end - part.start), d = k * part.len
      var tail = Math.min(d, Math.max(0.12 * part.len, 110))
      var f = Math.pow(1 - k, 3), dx = part.fly[0] * f, dy = part.fly[1] * f
      drawn[part.level].push.apply(drawn[part.level], pieces(part, 0, d, dx, dy))
      heat[0].push.apply(heat[0], pieces(part, d - tail, d - tail * 2 / 3, dx, dy))
      heat[1].push.apply(heat[1], pieces(part, d - tail * 2 / 3, d - tail / 3, dx, dy))
      heat[2].push.apply(heat[2], pieces(part, d - tail / 3, d, dx, dy))
    }
    if (done !== finished) {
      lines = landed(false)
      wheelLines = landed(true)
      finished = done
    }
    tracing = drawn
    comets = heat
  }

  onClockChanged: frame()
  onFrontChanged: wavefront = painted > 0 && painted < 1 ? cuts() : []
  // Engine starts at 0ms, wheels spin and body squats at 300ms, launch starts at 500ms.
  // Only wheels are reprojected; the launch translates the cached texture.
  onDriveChanged: {
    var t = drive * driveTime, u = Math.max(0, (t - 500) / (driveTime - 500))
    launch = u * u * u
    lamps = t === 0 ? 0 : t < 50 ? 0.8 : t < 110 ? 0.1 : Math.min(1, t / 250)
    // Wheels spin at 0.14rad a frame, under half the mesh's 18deg repeat, so they never seem to turn backwards.
    var was = rolled
    rolled = t === 0 ? 0 : rolled + 0.14 * Math.min(1, Math.max(0, (t - 300) / 150))
    if (rolled !== was) roll()
    var shake = t < 500 ? 1.2 * Math.sin(t * 0.16) : 0
    var pitch = 0.06 * Math.min(1, Math.max(0, (t - 300) / 200))
    pose = [pitch, shake]
    var m = stance(pitch, shake)
    bodyPose = Qt.matrix4x4(m[0], m[1], 0, m[2], m[3], m[4], 0, m[5], 0, 0, 1, 0, 0, 0, 0, 1)
    function body(p) { var q = view(p); return [m[0] * q[0] + m[1] * q[1] + m[2], m[3] * q[0] + m[4] * q[1] + m[5]] }
    focusHeights = Qt.point(focusHeights.x, body([300, 131, 64])[1])
    if (u === 0) {
      if (streaks[0].length) streaks = [[], [], []]
      return
    }
    // Each streak reaches back as far as the car went in the last 120ms, in its scaled frame.
    var back = Math.min(width * 0.5, width * 1.2 * (launch - Math.pow(Math.max(0, u - 120 / (driveTime - 500)), 3)) / (1 + 0.3 * launch))
    var ml = Math.hypot(width * 1.2, height * 0.14), bx = width * 1.2 / ml * back, by = -height * 0.14 / ml * back
    var heat = [[], [], []]
    streakFrom.forEach(function(p) {
      var q = body(p)
      function at(f) { return Qt.point(q[0] + bx * f, q[1] + by * f) }
      heat[2].push([at(0), at(1 / 3)])
      heat[1].push([at(1 / 3), at(2 / 3)])
      heat[0].push([at(2 / 3), at(1)])
    })
    streaks = heat
  }
  onWidthChanged: project()
  onHeightChanged: project()
  Component.onCompleted: project()

  NumberAnimation on clock { id: run; from: 0; to: car.duration; duration: car.duration; running: false }
  NumberAnimation on drive { id: go; from: 0; to: 1; duration: car.driveTime; running: false }

  function play() { go.stop(); drive = 0; run.restart() }
  function hide() { go.stop(); run.stop(); drive = 0; clock = 0 }
  function driveOff() { go.restart() }
}
