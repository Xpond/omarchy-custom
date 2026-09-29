// Every design shares five idle seconds, with recovery time after waking a powered-off monitor.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const read = file => fs.readFileSync(path.join(__dirname, "../patches/shell/plugins/lock", file), "utf8")
const source = read("Service.qml"), view = read("LockView.qml")
const delay = Number(source.match(/id: idleBlankTimer[^]*?interval: (\d+)/)[1])
const trigger = "(function() {" + source.match(/id: idleBlankTimer[^]*?onTriggered: \{([^]*?)^    }/m)[1] + "})()"
const selected = source.match(/^        onDesignChanged: (.+)$/m)[1]
const unlockDelay = Number(source.match(/id: unlockTimer[^]*?interval: (\d+)/)[1])
const wakeExit = source.match(/id: wakeProcess[^]*?onExited: (.+)/)[1]
const blankExit = source.match(/id: blankProcess[^]*?onExited: (.+)/)[1]
let now = 100000, blankAt = 0, hidden = false, plays = 0
const scope = { Date: { now: () => now }, lockRequested: true, waking: false, unlocking: false,
  authenticatingPassword: false, lastInput: 0, wakeUntil: 0, logEvent() {},
  wakeProcess: { running: false }, blankProcess: { running: false },
  unlockTimer: { interval: unlockDelay, starts: 0, restart() { this.starts++ } },
  idleBlankTimer: { interval: delay, armedAt: 0, restart() { blankAt = now + this.interval }, stop() { blankAt = 0 } } }
const display = { loadBackground: true, driving: false, tell(name) { if (name === "play") plays++ } }
Object.defineProperty(display, "blanked", { get: () => hidden })
vm.createContext(display)
Object.defineProperty(scope, "blanked", { get: () => hidden, set: value => {
  if (value === hidden) return
  hidden = value
  vm.runInContext(view.match(/^  onBlankedChanged: (.+)$/m)[1], display)
} })
scope.root = scope
for (const key of ["interval", "armedAt"])
  Object.defineProperty(scope, key, { get: () => scope.idleBlankTimer[key] })
vm.createContext(scope)
for (const name of ["armBlankTimer", "runWake", "finishWake", "runBlank", "wakeOnInput", "driveOffThenUnlock"])
  vm.runInContext(source.match(new RegExp("^  function " + name + "\\([^]*?^  }", "m"))[0], scope)
function exit(process, handler) { process.running = false; vm.runInContext(handler, scope) }

assert.equal(unlockDelay, 1100, "missing views lost their unlock deadline")
for (const design of ["mycelium", "rally", "shore", "tunnel", "wallpaper", "missing", "future-design"]) {
  scope.design = design
  vm.runInContext(selected, scope)
  assert.equal(scope.unlockTimer.interval, design === "mycelium" ? 550 : 1100, design + ": unlock deadline")
  scope.armBlankTimer()
  assert.equal(blankAt - now, 5000, design + ": initial timeout")
  scope.runBlank()
  // A key arriving while the display-off command runs must queue the wake behind it.
  now += 100
  scope.wakeOnInput()
  assert.equal(scope.wakeProcess.running, false, "wake raced an unfinished blank command")
  assert.equal(blankAt, 0, "blank countdown runs while waking")
  exit(scope.blankProcess, blankExit)
  assert.equal(scope.wakeProcess.running, true, "queued wake was lost")
  const before = plays
  now += 4000 // A slow wake must not consume the five seconds available for typing.
  exit(scope.wakeProcess, wakeExit)
  assert.equal(scope.blanked, false)
  assert.equal(plays, before + 1, "wake required another key to start the animation")
  assert.equal(blankAt - now, 10000, design + ": monitor wake allowance")
  const recoveryEnds = blankAt
  now += 4200 // Measured monitor delay AFTER the wake command returns.
  assert.ok(blankAt - now >= 5000, "monitor has less than five visible seconds before blanking")
  scope.wakeOnInput()
  exit(scope.wakeProcess, wakeExit)
  assert.equal(blankAt, recoveryEnds, "typing extended or discarded the monitor recovery allowance")
  now += 300 // Typing within the wake allowance must not shorten it.
  scope.wakeOnInput()
  assert.equal(blankAt, recoveryEnds, "a second key shortened monitor recovery")
  now += 1000
  scope.wakeOnInput()
  assert.equal(blankAt - now, 5000, design + ": password input timeout")
  assert.equal(plays, before + 1, "ordinary typing restarted the animation")
  now = blankAt
  vm.runInContext(trigger, scope)
  assert.equal(scope.blanked, true, design + ": idle did not blank")
  exit(scope.blankProcess, blankExit)
  scope.blanked = false
}
scope.armBlankTimer()
now = blankAt + 10000
vm.runInContext(trigger, scope)
assert.equal(scope.blanked, false, "resuming from suspend blanked immediately")
assert.equal(blankAt - now, 5000, "resume did not restart the shared timeout")
scope.authenticatingPassword = true
now = blankAt
vm.runInContext(trigger, scope)
assert.equal(scope.blanked, false, "an in-flight password check was blanked")
scope.lockRequested = false
scope.driveOffThenUnlock()
assert.equal(scope.unlockTimer.starts, 0, "an unlocked session started an unlock")
scope.lockRequested = true
scope.driveOffThenUnlock()
scope.driveOffThenUnlock()
assert.equal(scope.unlockTimer.starts, 1, "authentication started the exit more than once")
assert.match(source, /id: unlockTimer[^]*?onTriggered: root\.finishUnlock\(\)/)
console.log("ok: one wake replays every design; monitor recovery, overlapping commands and password keys preserve usable typing time")

// Ready outputs lock immediately; a missing output still follows the stabilization path.
let ready = true
Object.assign(scope, {
  hasRealScreen: () => ready,
  sessionLock: { locked: false, secure: false },
  sessionLockStabilizeTimer: { running: false, restart() { this.running = true } },
  pendingSessionLockTimer: { running: false, start() { this.running = true }, stop() { this.running = false } }
})
for (const name of ["queueSessionLock", "requestSessionLock"])
  vm.runInContext(source.match(new RegExp("^  function " + name + "\\([^]*?^  }", "m"))[0], scope)
scope.queueSessionLock()
assert.equal(scope.sessionLock.locked, true, "a ready screen still waits before locking")
assert.equal(scope.sessionLockStabilizeTimer.running, false)
scope.sessionLock.locked = false
ready = false
scope.queueSessionLock()
assert.equal(scope.sessionLock.locked, false, "locked without a real output")
assert.equal(scope.sessionLockStabilizeTimer.running, true)
ready = true
scope.requestSessionLock()
assert.equal(scope.sessionLock.locked, false, "bypassed an ongoing output stabilization")
scope.sessionLockStabilizeTimer.running = false
scope.requestSessionLock()
assert.equal(scope.sessionLock.locked, true, "never locked after the output settled")
console.log("ok: ready outputs lock immediately; missing outputs retain stabilization")
