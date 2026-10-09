// SUPER+W closes what is ours, else the window: the wheel answers whether anything closed, and the
// command closes the window on any other answer, an unreachable shell included.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const { repo, method } = require("./qml.js")
const { wheelSource } = require("./wheel-source.js")

for (const [opened, peersActed, answer] of [[true, false, "closed"], [false, true, "closed"], [false, false, "none"]]) {
  const calls = []
  const root = { opened, dismiss: () => calls.push("dismiss"),
                 closePeers: () => { calls.push("peers"); return { acted: peersActed, clear: true } } }
  assert.equal(method(wheelSource, "closeAll", { root })(), answer, "the wheel misreported what it closed")
  assert.deepEqual(calls, opened ? ["dismiss", "peers"] : ["peers"], "the wheel or its panels stayed up")
}

// The shell's answer comes from $ANSWER; each call is logged after the timeout it was given.
const stubs = fs.mkdtempSync(path.join(os.tmpdir(), "wheel-close-"))
const stub = (name, body) => fs.writeFileSync(path.join(stubs, name), "#!/bin/bash\n" + body, { mode: 0o755 })
stub("omarchy-shell", 'echo "$OMARCHY_SHELL_IPC_TIMEOUT $(printf "[%s]" "$@")" >> "$STUBS/calls"; [[ $ANSWER == fail ]] && exit 1; echo "$ANSWER"\n')
stub("hyprctl", 'echo "hyprctl $(printf "[%s]" "$@")" >> "$STUBS/calls"\n')
try {
  for (const answer of ["closed", "none", "fail"]) {
    fs.rmSync(path.join(stubs, "calls"), { force: true })
    const result = spawnSync(path.join(repo, "bin/omarchy-wheel-close"), [],
      { env: { ...process.env, PATH: stubs + ":" + process.env.PATH, STUBS: stubs, ANSWER: answer } })
    assert.equal(result.status, 0, answer)
    const [asked, ...rest] = fs.readFileSync(path.join(stubs, "calls"), "utf8").trim().split("\n")
    assert.equal(asked, "0.5s [shell][call][xpo.wheel][closeAll][]", "the wheel was not asked first, briefly and for its answer")
    assert.deepEqual(rest, answer === "closed" ? [] : ["hyprctl [dispatch][hl.dsp.window.close()]"],
      "SUPER+W closed a window behind the wheel, or left the window open with nothing of ours up")
  }
} finally {
  fs.rmSync(stubs, { recursive: true, force: true })
}
console.log("ok: SUPER+W closes the wheel or its panels when up, and otherwise the window, even with no shell")
