// Execute production file-operation commands against disposable paths.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const vm = require("node:vm")
const { spawnSync } = require("node:child_process")
const repo = path.resolve(__dirname, "..")
const opsSource = fs.readFileSync(path.join(repo, "plugins/xpo.files/FilesOps.qml"), "utf8")
const panelSource = fs.readFileSync(path.join(repo, "plugins/xpo.files/Files.qml"), "utf8")
function method(source, name, scope) {
  const code = source.match(new RegExp("^  function " + name + "\\([^\\n]*\\} *$|^  function "
                                     + name + "\\([^]*?^  }", "m"))[0]
  return vm.runInNewContext("(" + code.trim() + ")", scope)
}
const base = fs.mkdtempSync(path.join(os.tmpdir(), "files-ops-"))
try {
  const incoming = path.join(base, "incoming")
  const destination = path.join(base, "destination")
  fs.mkdirSync(incoming); fs.mkdirSync(destination)
  const panel = { listedDir: destination, editing: false, pending: "", sel: null }
  const calls = []
  const ops = { held: null, doomed: "", note() {} }
  ops.run = command => {
    // Never invoke the desktop's trash service.
    const result = command[0] === "gio" ? null : spawnSync(command[0], command.slice(1), { cwd: base })
    calls.push({ command: [...command], status: result && result.status })
  }
  const scope = { root: ops, panel, doomArmed: { restart() {} } }
  for (const name of ["guarded", "inHere", "hold", "paste", "remove"])
    ops[name] = method(opsSource, name, scope)
  const commitName = method(panelSource, "commitName", { root: panel, ops })
  for (const move of [false, true]) {
    const name = (move ? "move" : "copy") + " ' $(touch injected).txt"
    const src = path.join(incoming, name), dst = path.join(destination, name)
    fs.writeFileSync(src, "source bytes"); fs.writeFileSync(dst, "destination bytes")
    ops.hold({ path: src, name }, move)
    ops.paste()
    assert.equal(calls.at(-1).status, 17, "existing paste destination must be refused")
    assert.equal(fs.readFileSync(src, "utf8"), "source bytes")
    assert.equal(fs.readFileSync(dst, "utf8"), "destination bytes")
    fs.unlinkSync(dst)
    ops.paste()
    assert.equal(calls.at(-1).status, 0)
    assert.equal(fs.readFileSync(dst, "utf8"), "source bytes")
    assert.equal(fs.existsSync(src), !move)
  }
  const original = path.join(destination, "original.txt")
  const occupied = path.join(destination, "occupied.txt")
  fs.writeFileSync(original, "original"); fs.writeFileSync(occupied, "occupied")
  panel.sel = { path: original, name: "original.txt" }
  panel.naming = "rename"; panel.renameTo = "occupied.txt"
  commitName()
  assert.equal(calls.at(-1).status, 17)
  assert.equal(fs.readFileSync(original, "utf8"), "original")
  assert.equal(fs.readFileSync(occupied, "utf8"), "occupied")
  panel.naming = "rename"; panel.renameTo = "renamed.txt"
  commitName()
  assert.equal(calls.at(-1).status, 0)
  assert.equal(fs.existsSync(original), false)
  assert.equal(fs.readFileSync(path.join(destination, "renamed.txt"), "utf8"), "original")
  for (const name of ["occupied.txt", "existing-folder/"]) {
    const target = path.join(destination, name)
    if (name.endsWith("/")) { fs.mkdirSync(target); fs.writeFileSync(path.join(target, "child"), "keep") }
    panel.naming = "new"; panel.renameTo = name
    commitName()
    assert.equal(calls.at(-1).status, 17, "create must refuse an existing destination")
    assert.equal(fs.readFileSync(name.endsWith("/") ? path.join(target, "child") : target, "utf8"),
                 name.endsWith("/") ? "keep" : "occupied")
  }
  for (const name of ["new.txt", "new-folder/"]) {
    panel.naming = "new"; panel.renameTo = name
    commitName()
    assert.equal(calls.at(-1).status, 0)
    assert.equal(fs.statSync(path.join(destination, name)).isDirectory(), name.endsWith("/"))
  }
  for (const operation of ["move", "create"]) {
    const name = operation + "-dangling.txt"
    const dst = path.join(destination, name), missing = path.join(base, operation + "-missing")
    fs.symlinkSync(missing, dst)
    if (operation === "move") {
      const src = path.join(incoming, name)
      fs.writeFileSync(src, "keep source")
      ops.hold({ path: src, name }, true); ops.paste()
      assert.equal(calls.at(-1).status, 17, "move must refuse a dangling destination symlink")
      assert.equal(fs.readFileSync(src, "utf8"), "keep source")
    } else {
      panel.naming = "new"; panel.renameTo = name; commitName()
      assert.equal(calls.at(-1).status, 17, "create must refuse a dangling destination symlink")
    }
    assert.equal(fs.readlinkSync(dst), missing)
    assert.equal(fs.existsSync(missing), false)
  }
  const selected = { path: occupied, name: "occupied.txt" }
  panel.sel = selected
  const before = calls.length
  ops.remove()
  assert.equal(calls.length, before, "first Delete must only arm confirmation")
  assert.equal(ops.doomed, occupied)
  panel.sel = { path: path.join(destination, "new.txt"), name: "new.txt" }
  ops.remove()
  assert.equal(calls.length, before, "changing selection requires its own confirmation")
  ops.remove()
  assert.deepEqual(calls.at(-1).command, ["gio", "trash", "--", panel.sel.path])
  assert.equal(ops.doomed, "")
  assert.equal(fs.readFileSync(occupied, "utf8"), "occupied")
  assert.equal(fs.existsSync(panel.sel.path), true, "trash must stay stubbed")
  panel.editing = true
  const after = calls.length
  ops.remove(); ops.remove()
  assert.equal(calls.length, after, "Delete must not trash while editing")
  assert.equal(fs.existsSync(path.join(base, "injected")), false)
} finally {
  fs.rmSync(base, { recursive: true, force: true })
}
console.log("ok: paste, rename and create preserve collisions; trash requires confirmation")
