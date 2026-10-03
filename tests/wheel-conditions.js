// The batched condition script: one pacman query and one run per shared reader answer the stock
// checks, and every other condition keeps the meaning Bash alone gives it.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/MenuIndex.js"), "utf8")
const M = new Function(source.replace(/^\.pragma library/m, "") + "\nreturn { conditionScript, lockItems, merge }")()
const stubs = fs.mkdtempSync(path.join(os.tmpdir(), "wheel-conditions-"))
const stub = (name, body) => fs.writeFileSync(path.join(stubs, name), "#!/bin/bash\n" + body, { mode: 0o755 })
stub("pacman", 'echo "$1" >> "$STUBS/pacman.log"; installed=" kitty vim "\n'
  + '[[ $1 == -T && $PACMAN_FAILS ]] && exit 1\n'
  + 'if [[ $1 == -T ]]; then shift 2; s=0; for p; do [[ $installed == *" $p "* ]] || { echo "$p"; s=127; }; done; exit $s; fi\n'
  + '[[ $installed == *" $2 "* ]]\n')
stub("omarchy-default-browser", 'echo browser >> "$STUBS/reads.log"; echo "${TEST_BROWSER:-brave}"\n')
stub("omarchy-lock-design", '[[ $1 == current ]] && echo meadow\n')
stub("probe-reader", 'echo probe >> "$STUBS/reads.log"; echo value\n')
// What a script printed, and which pacman queries and readers it ran.
function bash(script, fails = "") {
  for (const log of ["pacman.log", "reads.log"]) fs.writeFileSync(path.join(stubs, log), "")
  const stdout = execFileSync("bash", ["-c", script], { encoding: "utf8",
    env: { ...process.env, PATH: stubs + ":" + process.env.PATH, STUBS: stubs, PACMAN_FAILS: fails } })
  const log = name => fs.readFileSync(path.join(stubs, name), "utf8")
  return { stdout, pacman: log("pacman.log"), reads: log("reads.log") }
}
try {
  const checks = M.merge({
    kitty: { label: "Kitty", action: "k", when: "omarchy-pkg-present kitty" },
    steam: { label: "Steam", action: "s", when: "! omarchy-pkg-present steam" },
    both: { label: "Both", action: "b", when: "omarchy-pkg-missing kitty vim" },
    brave: { label: "Brave", action: "b", checked: "[[ \"$(omarchy-default-browser)\" == brave ]]" },
    zen: { label: "Zen", action: "z", checked: "[[ $(omarchy-default-browser) == zen ]]" },
    quoted: { label: "Quoted", action: "q", when: "[[ \"$(echo ')')\" == ')' ]]" }
  }, M.lockItems(["rally", "meadow"]))
  // A failed query asks pacman per name, as omarchy-pkg-present does.
  for (const fails of ["", "1"]) {
    const run = bash(M.conditionScript(checks), fails)
    assert.deepEqual(run.stdout.trim().split("\n").sort(), ["brave:c", "kitty:w", "quoted:w", "steam:w", "style.lockscreen.1:c"])
    assert.equal(run.pacman, fails ? "-T\n-Q\n-Q\n-Q\n-Q\n" : "-T\n")
    assert.equal(run.reads, "browser\n", "a shared reader ran twice")
  }
  const custom = {
    assignment: "probe=$(command -v wheel-test-no-such-command)",
    shortCircuit: "false && [[ $(probe-reader) == value ]]",
    guardedKnownReader: "false && [[ $(omarchy-default-browser) == brave ]]",
    literal: "[[ '$(probe-reader)' == '$'\"(probe-reader)\" ]]",
    localEnvironment: "export TEST_BROWSER=firefox; [[ $(omarchy-default-browser) == firefox ]]",
    nested: '[[ "$(printf x$(probe-reader))" == xvalue ]]',
    ordinary: "[[ $(probe-reader) == value ]]",
    quotedArgument: "[[ $(printf '%s' value) == value ]]"
  }
  for (const [name, expr] of Object.entries(custom)) {
    for (const [field, tag] of [["when", "w"], ["checked", "c"]]) {
      const batch = bash(M.conditionScript({ test: { [field]: expr } }))
      const alone = bash(`if { ${expr}; } >/dev/null 2>&1; then echo test:${tag}; fi`)
      assert.deepEqual([batch.stdout, batch.reads], [alone.stdout, alone.reads],
        `${name} (${field}) changed its result or executed an extra command`)
    }
  }
  console.log("ok: one pacman query and one read per shared reader; custom conditions keep their Bash meaning")
} finally {
  fs.rmSync(stubs, { recursive: true })
}
