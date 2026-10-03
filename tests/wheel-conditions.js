// Custom Bash conditions must retain their meaning alongside the cached stock readers.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/MenuIndex.js"), "utf8")
const script = new Function(source.replace(/^\.pragma library/m, "") + "\nreturn conditionScript")()
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wheel-conditions-"))
const log = path.join(dir, "reads")
const stub = (name, body) => fs.writeFileSync(path.join(dir, name), "#!/bin/bash\n" + body, { mode: 0o755 })
stub("pacman", "exit 0\n")
stub("probe-reader", 'echo probe >> "$READ_LOG"; echo value\n')
stub("omarchy-default-browser", 'echo browser >> "$READ_LOG"; echo "${TEST_BROWSER:-brave}"\n')
const env = { ...process.env, PATH: dir + ":" + process.env.PATH, READ_LOG: log }
const cases = {
  assignment: "probe=$(command -v wheel-test-no-such-command)",
  shortCircuit: "false && [[ $(probe-reader) == value ]]",
  guardedKnownReader: "false && [[ $(omarchy-default-browser) == brave ]]",
  literal: "[[ '$(probe-reader)' == '$'\"(probe-reader)\" ]]",
  localEnvironment: "export TEST_BROWSER=firefox; [[ $(omarchy-default-browser) == firefox ]]",
  nested: '[[ "$(printf x$(probe-reader))" == xvalue ]]',
  ordinary: "[[ $(probe-reader) == value ]]",
  quotedArgument: "[[ $(printf '%s' value) == value ]]"
}
function evaluate(command) {
  fs.writeFileSync(log, "")
  const stdout = execFileSync("bash", ["-c", command], { encoding: "utf8", env })
  return { stdout, reads: fs.readFileSync(log, "utf8") }
}
try {
  for (const [name, expr] of Object.entries(cases)) {
    for (const [field, tag] of [["when", "w"], ["checked", "c"]]) {
      const direct = evaluate(`if { ${expr}; } >/dev/null 2>&1; then echo test:${tag}; fi`)
      const batch = evaluate(script({ test: { [field]: expr } }))
      assert.deepEqual(batch, direct, `${name} (${field}) changed its result or executed an extra command`)
    }
  }
  const batch = evaluate(script({
    brave: { checked: '[[ "$(omarchy-default-browser)" == "brave" ]]' },
    zen: { checked: "[[ $(omarchy-default-browser) == 'zen' ]]" }
  }))
  assert.deepEqual(batch, { stdout: "brave:c\n", reads: "browser\n" })
  console.log("ok: custom conditions preserve exit status, quoting and guards; stock comparisons share one read")
} finally {
  fs.rmSync(dir, { recursive: true })
}
