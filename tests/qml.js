// Load production QML methods and libraries for logic tests.
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const repo = path.resolve(__dirname, "..")
const read = name => fs.readFileSync(path.join(repo, name), "utf8")
function library(name) {
  const src = read(name).replace(/^\.pragma library/m, "")
  const names = [...src.matchAll(/^(?:function (\w+)|var (\w+) =)/gm)].map(m => m[1] || m[2])
  return new Function(src + "\nreturn {" + names.join(",") + "}")()
}
// A function ends on its own line or at the next brace closing at its indent.
function method(source, name, scope) {
  const start = "^  function " + name + "\\("
  vm.createContext(scope)
  vm.runInContext(source.match(new RegExp(start + "[^\\n]*\\} *$|" + start + "[^]*?^  }", "m"))[0], scope)
  return scope[name]
}
// A key map is a library like any other. It needs only a Qt whose names compare
// distinctly; real Qt values would be a table to keep correct for no gain.
function keymap(name, ...bound) {
  const src = read(name).replace(/^\.pragma library/m, "")
  const Qt = { ShiftModifier: 1 << 25, ControlModifier: 1 << 26 }
  let n = 1
  for (const [, key] of src.matchAll(/Qt\.(Key_\w+)/g)) Qt[key] = Qt[key] || n++
  const onKey = new Function("Qt", src + "\nreturn onKey")(Qt)
  return (key, modifiers = 0, text = "") => {
    const event = { key: Qt[key], modifiers, text, accepted: false }
    onKey(...bound, event)
    return event
  }
}

module.exports = { repo, read, library, method, keymap }
