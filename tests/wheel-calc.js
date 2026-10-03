// The wheel's calculator: answers, precedence, and the input that has none.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const source = fs.readFileSync(path.join(__dirname, "../plugins/xpo.wheel/Calc.js"), "utf8")
const C = new Function(source.replace(/^\.pragma library/m, "") + "\nreturn { evaluate, rows }")()

// Each answer is one row, and Enter copies exactly what it shows.
for (const [text, want] of [
  // Issue #8's screenshots, digit for digit.
  ["11.3/43", "0.262790697674419"], ["24*60*60.33/1.003", "86615.3539381854"],
  // ^ is not JavaScript's, so it is pinned here.
  ["-2^2", "-4"], ["(-2)^2", "4"], ["2^3^2", "512"], ["2^-1", "0.5"], ["2*3^2", "18"], ["-2^-2", "-0.25"],
  ["(1+2)*3^2", "27"], ["2^0.5", "1.4142135623731"],
  // Float noise, bare decimals, signs, and magnitudes JavaScript writes in e-notation.
  ["0.1+0.2", "0.3"], [" .5 + 1. ", "1.5"], ["--2", "2"], ["+3", "3"], ["-0", "0"], ["1/3", "0.333333333333333"],
  ["2^100", "1.26765060022823e+30"], ["1/2^40", "9.09494701772928e-13"]
]) assert.deepEqual(C.rows(text), [{ icon: "󰃬", label: want, trail: "", copy: want }], text)

// Half-typed, foreign, or non-finite input has no answer.
for (const text of ["", "  ", "2+", "(1+2", "(2 3", "1+2)", "()", "2(3)", "1 2", "1.2.3", "x^0", "2**3", "1,000",
  "5 ft to cm", "1/0", "0/0", "-1/0"])
  assert.deepEqual(C.rows(text), [], JSON.stringify(text))

// Without ^ the grammar is JavaScript's, so random sums must agree bit for bit.
let seed = 8
const rand = () => (seed = seed * 16807 % 2147483647) / 2147483647
const pick = list => list[Math.floor(rand() * list.length)]
const sign = () => rand() < 0.15 ? "-" : ""
function expr(depth) {
  if (depth <= 0 || rand() < 0.3) return sign() + Math.floor(rand() * 1000) / pick([1, 10, 100])
  if (rand() < 0.2) return sign() + "(" + expr(depth - 1) + ")"
  return expr(depth - 1) + " " + pick(["+", "-", "*", "/"]) + " " + expr(depth - 1)
}
for (let n = 0; n < 2000; n++) {
  const text = expr(5)
  assert.equal(C.evaluate(text), Function("return " + text)(), text)
}
console.log("ok: calculator answers issue #8's sums, keeps PEMDAS, and leaves 2000 random sums as JavaScript does")
