.pragma library

// Menu definitions ship as JSONC. Strip line comments and trailing commas --
// the same two transforms the shell's own parser makes -- then parse. A broken
// or missing file yields an empty map rather than taking the wheel down.
function parse(raw) {
  try {
    return JSON.parse(String(raw || "")
      .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
      .replace(/,(\s*[}\]])/g, "$1")) || {}
  } catch (e) {
    return {}
  }
}

// User entries extend and override defaults by id, which is the same contract
// the extensions file documents for itself.
function merge(defaults, user) {
  var out = {}
  for (var a in defaults) out[a] = defaults[a]
  for (var b in user) out[b] = user[b]
  return out
}

// Dotted ids carry the hierarchy, so an entry's breadcrumb is just the labels
// of its ancestor ids: "trigger.capture.qr" -> ["Trigger", "Capture"].
function trailOf(items, id) {
  var parts = String(id).split(".")
  var trail = []
  for (var i = 1; i < parts.length; i++) {
    var parent = items[parts.slice(0, i).join(".")]
    if (parent && parent.label) trail.push(parent.label)
  }
  return trail
}

// One flat list of everything runnable: the wheel's own slices, every menu
// entry carrying an action, and every desktop application. Menu entries
// without an action are submenus -- they hold nothing to run, and their
// labels already appear as breadcrumbs.
function build(items, slices, apps) {
  var out = []
  for (var i = 0; i < slices.length; i++) {
    out.push({ icon: slices[i].icon, label: slices[i].label, trail: "Wheel",
               slice: i, keywords: String(slices[i].label).toLowerCase() })
  }
  for (var id in items) {
    var e = items[id]
    if (!e || !e.action) continue
    var trail = trailOf(items, id)
    out.push({
      icon: e.icon || "", label: e.label || id, trail: trail.join(" › "),
      action: e.action, slice: -1,
      keywords: [e.label, trail.join(" "), String(id).replace(/[.]/g, " "),
                 (e.aliases || []).join(" "), e.description || ""]
                .join(" ").toLowerCase()
    })
  }
  // `apps` is the shell app library's own row list, so each element wraps the
  // desktop entry. An app carries an icon NAME rather than a glyph -- the row
  // resolves it to a file -- and launches by desktop id, not by command.
  for (var j = 0; j < apps.length; j++) {
    var a = apps[j].entry
    if (!a.id) continue
    var name = String(a.name || a.id)
    out.push({
      icon: "", appIcon: String(a.icon || ""), label: name, trail: "App",
      appId: String(a.id), slice: -1,
      keywords: [name, a.genericName || "", a.comment || "",
                 a.keywords && a.keywords.join ? a.keywords.join(" ") : "",
                 String(a.id).replace(/[._]/g, " ")]
                .join(" ").toLowerCase()
    })
  }
  return out
}

// Every term must appear somewhere in the entry, so terms narrow rather than
// widen. Ranking puts a label that starts with the query above one that merely
// contains it, above a hit that only matched a breadcrumb or alias; shorter
// labels break ties, which floats "Screenshot" over "Stop Screenrecording".
// Dead heats past that go slice, then app, then menu entry: "firefox" matches
// the app and the menu's install/remove/set-default rows identically, and the
// one the typist meant is the app.
function search(index, query, limit) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return []
  var terms = q.split(/\s+/)
  var hits = []
  for (var i = 0; i < index.length; i++) {
    var e = index[i]
    var matched = true
    for (var t = 0; t < terms.length; t++) {
      if (e.keywords.indexOf(terms[t]) === -1) { matched = false; break }
    }
    if (!matched) continue
    var label = e.label.toLowerCase()
    var at = label.indexOf(q)
    hits.push({ rank: at === 0 ? 0 : (at !== -1 ? 1 : 2), len: label.length,
                kind: e.slice >= 0 ? 0 : (e.appId ? 1 : 2), entry: e })
  }
  hits.sort(function (a, b) { return a.rank - b.rank || a.len - b.len || a.kind - b.kind })
  var out = []
  for (var j = 0; j < hits.length && j < limit; j++) out.push(hits[j].entry)
  return out
}
