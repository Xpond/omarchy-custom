.pragma library

// PEMDAS over + - * / ^ and parentheses. A stray, missing or foreign token means no
// answer yet, so a half-typed sum shows nothing rather than a wrong number.
function evaluate(text) {
  var tokens = String(text).match(/\d+\.?\d*|\.\d+|\S/g) || []
  var i = 0, ok = true
  function sum() {
    var v = product()
    while (tokens[i] === "+" || tokens[i] === "-")
      v = tokens[i++] === "+" ? v + product() : v - product()
    return v
  }
  function product() {
    var v = power()
    while (tokens[i] === "*" || tokens[i] === "/")
      v = tokens[i++] === "*" ? v * power() : v / power()
    return v
  }
  // As on paper: -2^2 is -4, and 2^3^2 is 2^9.
  function power() {
    if (tokens[i] === "-" || tokens[i] === "+") return tokens[i++] === "-" ? -power() : power()
    var v = atom()
    if (tokens[i] !== "^") return v
    i++
    return Math.pow(v, power())
  }
  // A flag rather than NaN: Math.pow(NaN, 0) is 1.
  function atom() {
    var t = tokens[i++]
    if (t !== "(") {
      ok = ok && /\d/.test(t)
      return parseFloat(t)
    }
    var v = sum()
    ok = ok && tokens[i++] === ")"
    return v
  }
  var v = sum()
  return ok && i === tokens.length ? v : NaN
}

// Fifteen significant digits also drop float noise: 0.1+0.2 is 0.3.
function rows(text) {
  var v = evaluate(text)
  if (!isFinite(v)) return []
  var answer = String(Number(v.toPrecision(15)))
  return [{ icon: "󰃬", label: answer, trail: "", copy: answer }]
}
