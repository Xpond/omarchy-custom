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

// What a row is, and the last tie-break in search(): two rows matching equally
// well under labels of the same length come back in this order.
var KIND = { slice: 0, window: 1, app: 2, style: 3, menu: 4 }

// One name per line, blanks dropped -- the shape every `omarchy <x> list` has.
function lines(raw) {
  var out = []
  var parts = String(raw || "").split("\n")
  for (var i = 0; i < parts.length; i++) {
    var value = parts[i].trim()
    if (value) out.push(value)
  }
  return out
}

// Single-quote for the shell: theme and font names carry spaces.
function quote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// Themes and fonts are one shape: a name the CLI takes as an argument.
function styleRows(out, names, icon, trail, command) {
  for (var i = 0; i < names.length; i++) {
    var name = String(names[i])
    out.push({
      icon: icon, label: name, trail: trail, kind: KIND.style,
      action: command + quote(name), slice: -1,
      keywords: (name + " " + trail).toLowerCase()
    })
  }
}

// One flat list of everything runnable: the wheel's own slices, every menu
// entry carrying an action, every desktop application, every open window, and
// every theme and font. Menu entries without an action are submenus -- they
// hold nothing to run, and their labels already appear as breadcrumbs.
//
// `sources` is the live half: { apps, windows, themes, fonts }.
function build(items, slices, sources) {
  var out = []
  for (var i = 0; i < slices.length; i++) {
    out.push({ icon: slices[i].icon, label: slices[i].label, trail: "Wheel",
               slice: i, kind: KIND.slice,
               keywords: String(slices[i].label).toLowerCase() })
  }
  for (var id in items) {
    var e = items[id]
    if (!e || !e.action) continue
    var trail = trailOf(items, id)
    out.push({
      icon: e.icon || "", label: e.label || id, trail: trail.join(" › "),
      action: e.action, slice: -1, kind: KIND.menu,
      keywords: [e.label, trail.join(" "), String(id).replace(/[.]/g, " "),
                 (e.aliases || []).join(" "), e.description || ""]
                .join(" ").toLowerCase()
    })
  }
  // `sources.apps` is the shell app library's own row list, so each element
  // wraps the desktop entry. An app carries an icon NAME rather than a glyph
  // -- a non-empty `appIcon` is what tells the row to draw an image -- and it
  // launches by desktop id, not by command.
  var apps = sources.apps
  var iconByAppId = {}
  for (var j = 0; j < apps.length; j++) {
    var a = apps[j].entry
    if (!a.id) continue
    var name = String(a.name || a.id)
    var appIcon = String(a.icon || a.id)
    iconByAppId[String(a.id).toLowerCase()] = appIcon
    out.push({
      icon: "", appIcon: appIcon, label: name, trail: "App",
      appId: String(a.id), slice: -1, kind: KIND.app,
      keywords: [name, a.genericName || "", a.comment || "",
                 a.keywords && a.keywords.join ? a.keywords.join(" ") : "",
                 String(a.id).replace(/[._]/g, " ")]
                .join(" ").toLowerCase()
    })
  }
  // A window is carried by address, not by its toplevel object, so a row can
  // outlive the window without holding it alive. Quickshell reports that
  // address bare and Hyprland only matches it as hex. The icon comes from the
  // app's desktop entry rather than the app id -- Brave's window says
  // `brave-browser` while its entry draws `brave-desktop` -- and an app with
  // no entry at all leaves `appIcon` empty, which falls the row back to the
  // glyph instead of a grey blank.
  var windows = sources.windows
  for (var w = 0; w < windows.length; w++) {
    var t = windows[w]
    var appId = String((t.wayland && t.wayland.appId) || "")
    var title = String(t.title || appId)
    if (!title) continue
    out.push({
      icon: "󰖯", appIcon: iconByAppId[appId.toLowerCase()] || "", label: title,
      trail: appId || "Window", address: "0x" + t.address, slice: -1,
      kind: KIND.window,
      keywords: (title + " " + appId).toLowerCase()
    })
  }
  // Both are buried behind pickers in the menu -- style.theme shells out to a
  // second overlay -- so flattening them here is what makes them reachable.
  styleRows(out, sources.themes, "󰸌", "Theme", "omarchy theme set ")
  styleRows(out, sources.fonts, "󰛖", "Font", "omarchy font set ")
  return out
}

// Every term must appear somewhere in the entry, so terms narrow rather than
// widen. Ranking puts a label that starts with the query above one that merely
// contains it, above a hit that only matched a breadcrumb or alias; shorter
// labels break ties, which floats "Screenshot" over "Stop Screenrecording".
// Dead heats past that go by KIND above: "firefox" matches the app and the
// menu's install/remove/set-default rows identically, and the one the typist
// meant is the app.
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
    hits.push({ rank: at === 0 ? 0 : (at !== -1 ? 1 : 2), len: label.length, entry: e })
  }
  hits.sort(function (a, b) {
    return a.rank - b.rank || a.len - b.len || a.entry.kind - b.entry.kind
  })
  var out = []
  for (var j = 0; j < hits.length && j < limit; j++) out.push(hits[j].entry)
  return out
}
