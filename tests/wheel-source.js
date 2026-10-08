const { read, library } = require("./qml.js")
const M = library("plugins/xpo.wheel/MenuIndex.js")

const wheelSource = read("plugins/xpo.wheel/Wheel.qml")
// A readonly binding of Wheel.qml, evaluated over the names given.
const binding = (name, scope) => new Function(...Object.keys(scope), "return " + wheelSource
  .match(new RegExp("readonly property \\w+ " + name + ": ([^]*?)\\n  (?:readonly )?property"))[1])(...Object.values(scope))
// Those bindings as getters on a stand-in, so it reads them as the wheel does.
const derive = (root, ...names) => names.forEach(name =>
  Object.defineProperty(root, name, { get: () => binding(name, { root, MenuIndex: M }) }))

module.exports = { M, wheelSource, binding, derive }
