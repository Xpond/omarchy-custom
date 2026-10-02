// Painted underneath the foliage, with its own seed so adding soil detail does not
// rearrange the plants. Texture gets coarser and stronger towards the viewer.
function groundTexture(c, width, bank) {
  var seed = 947
  function random() { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 4294967296 }
  c.save(); c.clip()
  for (var patch = 0; patch < 110; patch++) {
    var x = random() * width, y = 760 + random() * 170
    var depth = Math.max(0,Math.min(1,(y - bank(x)) / 120)), r = 8 + depth * (12 + random() * 28)
    c.save(); c.translate(x,y); c.scale(1,.42)
    var moss = c.createRadialGradient(0,0,0,0,0,r)
    moss.addColorStop(0,patch % 3 ? "rgba(77,87,48,.5)" : "rgba(95,71,46,.4)")
    moss.addColorStop(.55,"rgba(48,57,33,.25)"); moss.addColorStop(1,"rgba(32,43,29,0)")
    c.globalAlpha = depth; c.fillStyle = moss
    c.fillRect(-r,-r,r * 2,r * 2); c.restore()
  }
  for (var grain = 0; grain < Math.round(width * 5); grain++) {
    var x = random() * width, y = 745 + random() * 180
    var depth = Math.max(0,Math.min(1,(y - bank(x)) / 100))
    if (!depth) continue
    var r = .25 + random() * (.45 + depth * 1.9)
    var mossy = Math.sin(x / 27 + Math.sin(y / 17)) * Math.cos(y / 14 + x / 51) > .15
    c.globalAlpha = depth * (.16 + random() * .4)
    c.fillStyle = mossy ? (grain % 2 ? "#758055" : "#3e5637") : (grain % 3 ? "#655c43" : "#080f0d")
    c.beginPath(); c.ellipse(x,y,r * (1.2 + random()),r * .65); c.fill()
  }
  // Tiny pebbles and fallen stems break up the moss with warm mineral detail.
  for (var bit = 0; bit < 360; bit++) {
    var x = random() * width, y = 758 + random() * 170
    var depth = Math.max(0,Math.min(1,(y - bank(x)) / 115)), r = .6 + depth * random() * 3.5
    c.globalAlpha = depth * .65
    if (bit % 4) {
      c.strokeStyle = bit % 2 ? "#625b40" : "#293123"; c.lineWidth = .3 + depth * .45
      c.beginPath(); c.moveTo(x,y)
      c.quadraticCurveTo(x + r * 2,y - r * .3,x + r * 4,y + (random() - .5) * r * 2); c.stroke()
    } else {
      c.fillStyle = "#080e0d"
      c.beginPath(); c.ellipse(x - r,y,r * 2.5,r * 1.1); c.fill()
      var pebble = c.createLinearGradient(x,y - r,x,y + r)
      pebble.addColorStop(0,"#777969"); pebble.addColorStop(.45,"#444d40"); pebble.addColorStop(1,"#202a23")
      c.fillStyle = pebble
      c.beginPath(); c.ellipse(x - r,y - r * .6,r * 2,r); c.fill()
    }
  }
  c.restore()
}

// The near bank fills only the lower frame: small distant growth, then overlapping
// leaves, stones and flowers whose size increases towards the viewer. It returns the flowers,
// which the growth shaders draw so they can sway.
function draw(c, width) {
  var seed = 193
  function random() { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 4294967296 }
  function bank(x) { return 751 + 58 * Math.exp(-Math.pow((x / width - .5) * 3.6,2)) + 6 * Math.sin(x / 71) }
  var soil = c.createLinearGradient(0,738,0,930)
  soil.addColorStop(0,"rgba(24,39,30,0)"); soil.addColorStop(.3,"rgba(24,39,30,.4)")
  soil.addColorStop(.65,"#14211b"); soil.addColorStop(1,"#080f10")
  c.fillStyle = soil
  c.beginPath(); c.moveTo(-10,900)
  for (var x = -10; x <= width + 10; x += 8) c.lineTo(x,bank(x) + random() * 5)
  c.lineTo(width + 10,920); c.closePath(); c.fill()
  groundTexture(c,width,bank)
  // Ground cover has visible depth: broad, shaded leaves overlap the tiny far tufts.
  for (var i = 0; i < 850; i++) {
    var x = random() * width, depth = random(), y = bank(x) + 12 + depth * 160
    var size = 3 + depth * depth * 15, angle = random() * 6.28
    c.save(); c.translate(x,y); c.rotate(angle)
    var leaf = c.createLinearGradient(-size,0,size,0)
    leaf.addColorStop(0,"#16261b"); leaf.addColorStop(.55,i % 3 ? "#3f5e37" : "#5e6e3a")
    leaf.addColorStop(1,"#1e3624"); c.fillStyle = leaf
    c.beginPath(); c.moveTo(0,size * .4)
    c.bezierCurveTo(-size,size * .1,-size * .5,-size * 1.6,0,-size * 2)
    c.bezierCurveTo(size * .8,-size * .9,size,size * .2,0,size * .4); c.fill()
    c.strokeStyle = "#607052"; c.lineWidth = .3
    c.beginPath(); c.moveTo(0,size * .2); c.quadraticCurveTo(-size * .12,-size * .9,0,-size * 1.65); c.stroke()
    c.restore()
  }
  // A rounded stone, lit from the sky and darkening towards its sides and base. Fine specks,
  // unlike the ground's streaks, keep it from reading as a window onto the soil.
  function rock(x, y, w, h, front) {
    c.save(); c.translate(x,y)
    var points = [[-.52,.18],[-.47,-.32],[-.3,-.7],[-.08,-.89],[.27,-.54],[.49,-.22],[.54,.24]]
    // Each corner becomes a curve between the midpoints of its two edges.
    function mid(a, b) { return [(a[0] + b[0]) / 2 * w,(a[1] + b[1]) / 2 * h] }
    var start = mid(points[points.length - 1],points[0])
    c.beginPath(); c.moveTo(start[0],start[1])
    points.forEach(function(p, i) {
      var end = mid(p,points[(i + 1) % points.length])
      c.quadraticCurveTo(p[0] * w,p[1] * h,end[0],end[1])
    })
    // As a mask, it holds its front edge between 800 and 1000, for the flowers behind it.
    if (front) {
      c.fillStyle = "rgb(" + Math.round((front - 800) / 200 * 255) + ",0,0)"; c.fill(); c.restore(); return
    }
    var stone = c.createRadialGradient(w * .05,-h * .8,0,w * .05,-h * .8,w * .62)
    stone.addColorStop(0,"#5f6a65"); stone.addColorStop(.5,"#36423f"); stone.addColorStop(1,"#141c1b")
    c.fillStyle = stone; c.fill(); c.save(); c.clip()
    // Fine light and dark mineral specks.
    for (var s = 0; s < 650; s++) {
      var px = (random() - .5) * w, py = (random() - .85) * h, r = .3 + random() * 1.1
      c.fillStyle = s % 3 ? "#141c1b" : "#9aa197"
      c.globalAlpha = .15 + random() * .3
      c.fillRect(px,py,r,r)
    }
    c.globalAlpha = 1
    // Small moss patches grow on the top.
    for (var moss = 0; moss < 70; moss++) {
      var mx = (random() - .5) * w * .8, my = -h * .65 + random() * h * .2
      c.fillStyle = moss % 3 ? "#3e5034" : "#68714a"
      c.beginPath(); c.ellipse(mx,my,2 + random() * 6,1 + random() * 3); c.fill()
    }
    c.restore(); c.restore()
  }
  var plants = [], grass = []
  // Frame the clearing with close flowers. Their roots and some petals fall outside the frame.
  for (var f = 0; f < 40; f++) {
    var side = f % 2, depth = random(), x = width * (side ? .72 + random() * .3 : random() * .28)
    var root = 831 + depth * 130, y = root - 38 - random() * 70
    plants.push({x: x, y: y, root: root, bend: (random() - .5) * 65,
      radius: 6 + depth * depth * 23, kind: Math.floor(random() * 5), phase: random() * 6.28,
      tilt: .55 + random() * .4, waves: 6 + random() * 8, leaves: 2, start: 0, letter: false})
  }
  for (var g = 0; g < 180; g++) {
    var x = random() * width, y = bank(x) + 15 + random() * 170
    grass.push([x,y,9 + (y - 740) * random() * .45,(random() - .5) * 45,random()])
  }
  plants.sort(function(a,b) { return a.root - b.root })
  // Paint back to front: each stone hides what is rooted behind its front edge, at y + .24h.
  function band(near, far) {
    grass.forEach(function(g) {
      if (g[1] < near || g[1] >= far) return
      c.strokeStyle = g[4] > .5 ? "#3a6340" : "#24452f"
      c.lineWidth = .4 + g[4] * .8
      c.beginPath(); c.moveTo(g[0],g[1])
      c.quadraticCurveTo(g[0] + g[3] * .2,g[1] - g[2] * .6,g[0] + g[3],g[1] - g[2]); c.stroke()
    })
  }
  function left(front) { rock(width * .13,856,Math.min(230,width * .25),84,front) }
  function right(front) { rock(width * .86,929,Math.min(330,width * .32),94,front) }
  c.lineCap = "round"
  band(0,876); left(); band(876,952); right(); band(952,Infinity)
  // 270 below, clear of ground reaching past the frame's lower edge, the stones' outlines mask
  // the flowers rooted behind them.
  c.clearRect(-10,900,width + 20,270); c.translate(0,270)
  left(876); right(952)
  return plants
}
