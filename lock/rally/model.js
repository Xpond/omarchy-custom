.pragma library
.import "shape.js" as Shape
.import "outlines.js" as Outlines
.import "cabin.js" as Cabin
.import "body.js" as Body
.import "livery.js" as Livery

// The car as 3D outlines, traced in the order they're added, and painted surfaces by tone (see Car.qml's
// paint). Each part adds to the same lists and hands on what later parts build on.
function carModel() {
  var m = Shape.builder()
  ;[Outlines, Cabin, Body, Livery].forEach(function(part) { Object.assign(m, part.build(m)) })
  return { parts: m.parts, surfaces: m.surfaces, panes: [m.panes[0], m.panes[1], m.windscreen.slice(0, 13).concat(m.edge, [m.windscreen[0]])],
    dash: m.dash.concat(m.inside[0], m.inside[1]) }
}
