// A garden in a 900-unit-high frame. Flowers follow rounded, lowercase letter strokes.
function garden(aspect) {
  var seed = 71, plants = [], w = 900 * aspect
  function random() { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 4294967296 }
  function plant(x, y, radius, letter) {
    plants.push({ x: x, y: y, root: letter ? 724 + random() * 100 : Math.max(740, y + 20) + random() * 55,
      bend: (random() - .5) * (letter ? 36 : 85), waves: 6 + random() * 8,
      radius: radius, kind: Math.floor(random() * (letter ? 4 : 5)), phase: random() * 6.28,
      tilt: letter ? .85 + random() * .15 : .58 + random() * .42,
      leaves: 1 + Math.floor(random() * 3),
      start: random() * .35 + (letter ? x / w * .4 : 0), letter: letter })
  }
  var span = Math.min(w * .82, 1300), unit = span / 7.4, left = (w - span) / 2
  // The o's centre, .45 units down, sits at the frame's middle, so the word is vertically centred.
  function stroke(offset, points) {
    var next = 0
    for (var i = 1; i < points.length; i++) {
      var a = points[i - 1], b = points[i], length = Math.hypot(b[0] - a[0], b[1] - a[1]) * unit
      while (next < length) {
        var t = next / length, radius = 8.5 + random() * 6
        plant(left + (offset + a[0] + (b[0] - a[0]) * t) * unit + (random() - .5) * 8,
          450 + (a[1] + (b[1] - a[1]) * t - .45) * unit + (random() - .5) * 8, radius, true)
        next += radius * .9 + random() * 2
      }
      next -= length
    }
  }
  function arc(cx, cy, rx, ry, start, end) {
    var p = []
    for (var n = 0; n <= 32; n++) {
      var t = start + (end - start) * n / 32
      p.push([cx + rx * Math.cos(t), cy + ry * Math.sin(t)])
    }
    return p
  }
  stroke(0, arc(.42, .45, .38, .48, 0, Math.PI * 2))
  stroke(1.06, [[0,.93],[0,0]])
  stroke(1.06, arc(.3,.38,.3,.38,Math.PI,Math.PI * 2).concat([[.6,.93]]))
  stroke(1.06, arc(.9,.38,.3,.38,Math.PI,Math.PI * 2).concat([[1.2,.93]]))
  stroke(2.55, arc(.38,.45,.37,.48,0,Math.PI * 2))
  stroke(2.55, [[.76,0],[.76,.93]])
  stroke(3.65, [[0,.93],[0,0]])
  stroke(3.65, arc(.36,.4,.36,.4,Math.PI,Math.PI * 1.86))
  stroke(4.5, arc(.43,.45,.4,.48,.24 * Math.PI,1.76 * Math.PI))
  stroke(5.5, [[0,-.64],[0,.93]])
  stroke(5.5, arc(.38,.38,.38,.38,Math.PI,Math.PI * 2).concat([[.76,.93]]))
  stroke(6.55, [[0,0],[.4,.85],[.82,0]])
  stroke(6.55, [[.4,.85],[.25,1.22],[.05,1.4],[-.15,1.36]])
  for (var f = 0; f < 90; f++) {
    var y = 680 + random() * 180
    plant(random() * w, y, 4 + Math.pow((y - 650) / 230, 2) * (4 + random() * 10), false)
  }
  return plants.sort(function(a, b) { return a.root - b.root })
}

// One texel per plant and field for plants.vert, as 24-bit fixed point: value = n / 2048 - 4096.
var fields = ["x", "y", "root", "bend", "waves", "radius", "kind", "phase", "tilt", "leaves", "start", "letter"]
function encode(c, plants) {
  if (!plants.length) return
  var width = plants.length, image = c.createImageData(width, fields.length), data = image.data
  for (var row = 0; row < fields.length; row++) for (var i = 0; i < width; i++) {
    var n = Math.round((+plants[i][fields[row]] + 4096) * 2048), at = (row * width + i) * 4
    data[at] = n >> 16; data[at + 1] = n >> 8 & 255; data[at + 2] = n & 255; data[at + 3] = 255
  }
  // Qt's Canvas needs explicit dirty bounds here or the texture stays transparent.
  c.putImageData(image, 0, 0, 0, 0, width, fields.length)
}
