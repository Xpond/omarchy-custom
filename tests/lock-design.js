// The design command lists scenes and persists a valid choice. A folder without a scene is no design.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const { repo } = require("./qml.js")

const home = fs.mkdtempSync(path.join(os.tmpdir(), "lock-design-"))
const design = (...args) => spawnSync(path.join(repo, "bin/omarchy-lock-design"), args,
  { env: { ...process.env, HOME: home }, encoding: "utf8" })
const choice = path.join(home, ".config/wheely/lock-design")
try {
  for (const name of ["rally", "meadow", "notes"]) {
    const folder = path.join(home, ".local/share/wheely/lock", name)
    fs.mkdirSync(folder, { recursive: true })
    if (name !== "notes") fs.writeFileSync(path.join(folder, "Scene.qml"), "")
  }
  assert.equal(design("list").stdout, "meadow\nrally\n")
  assert.equal(design("current").stdout, "rally\n", "with no choice yet the lock screen shows rally")
  assert.equal(design("set", "meadow").status, 0)
  assert.deepEqual([fs.readFileSync(choice, "utf8"), design("current").stdout], ["meadow\n", "meadow\n"])
  for (const args of [["set", "missing"], []]) {
    assert.equal(design(...args).status, 1, args.join(" "))
    assert.equal(fs.readFileSync(choice, "utf8"), "meadow\n", "a refused choice replaced the design")
  }
} finally {
  fs.rmSync(home, { recursive: true, force: true })
}
console.log("ok: designs are listed and chosen by name, rally until one is, and a bad name changes nothing")
