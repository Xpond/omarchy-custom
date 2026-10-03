.pragma library

// Match the shell's JSONC parsing; malformed input leaves the wheel usable.
function parse(raw) {
  try {
    return JSON.parse(String(raw || "")
      .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
      .replace(/,(\s*[}\]])/g, "$1")) || {}
  } catch (e) {
    return {}
  }
}

function merge(defaults, user) {
  var out = {}
  for (var a in defaults) out[a] = defaults[a]
  for (var b in user) out[b] = user[b]
  return out
}

// Dotted ids encode the menu hierarchy.
function trailOf(items, id) {
  var parts = String(id).split(".")
  var trail = []
  for (var i = 1; i < parts.length; i++) {
    var parent = items[parts.slice(0, i).join(".")]
    if (parent && parent.label) trail.push(parent.label)
  }
  return trail
}

// Search kind precedence.
var KIND = { slice: 0, window: 1, app: 2, style: 3, menu: 4 }

// Prefer stable ids for use counts; windows already sort by live focus.
function keyOf(e) {
  if (e.plugin) return e.plugin
  if (e.id) return e.id
  if (e.appId) return "app:" + e.appId
  return e.action || ""
}

// Keep the selected action through a refresh; a reused menu id with a new command is a new action.
function indexOfEntry(rows, previous) {
  if (!previous) return -1
  var key = keyOf(previous)
  for (var i = 0; i < rows.length; i++) {
    var e = rows[i]
    if (keyOf(e) === key && e.action === previous.action && e.node === previous.node
        && e.address === previous.address && e.path === previous.path) return i
  }
  return -1
}

function crumb(items, path) {
  var out = []
  for (var i = 0; i < path.length; i++) {
    var e = items[path.slice(0, i + 1).join(".")]
    out.push((e && e.label) || path[i])
  }
  return out.join(" \u203a ")
}

function lines(raw) {
  var out = []
  var parts = String(raw || "").split("\n")
  for (var i = 0; i < parts.length; i++) {
    var value = parts[i].trim()
    if (value) out.push(value)
  }
  return out
}

// Shell-quote names.
function quote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// Prefer observed focus order, then Hyprland's cached history.
function recencyOf(order, address, cachedHistory) {
  var seen = order.indexOf(address)
  return seen >= 0 ? seen : order.length + (Number(cachedHistory) || 0)
}

function styleRows(out, names, current, icon, trail, command) {
  for (var i = 0; i < names.length; i++) {
    var name = String(names[i])
    out.push({
      icon: icon, label: name + (name === current ? " ✓" : ""), trail: trail, kind: KIND.style,
      action: command + quote(name),
      keywords: (name + " " + trail).toLowerCase()
    })
  }
}

// Themes and fonts fire `omarchy theme|font set`; the current one is marked.
function styles(themes, theme, fonts, font) {
  var out = []
  styleRows(out, themes, theme, "󰸌", "Theme", "omarchy theme set ")
  styleRows(out, fonts, font, "󰛖", "Font", "omarchy font set ")
  return out
}

// Lock-screen designs as one Style submenu: search finds it, and each design shows only inside it.
function lockItems(names) {
  if (!names.length) return {}
  var out = { "style.lockscreen": { icon: "󰌾", label: "Lockscreen Designs" } }
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    out["style.lockscreen." + i] = { icon: "󰋩", label: name.charAt(0).toUpperCase() + name.slice(1),
                                     action: "omarchy-lock-design set " + quote(name), search: false,
                                     checked: "[[ $(omarchy-lock-design current) == " + quote(name) + " ]]" }
  }
  return out
}

// Shell panels in ring order; branded marks use their own QML components.
var PANELS = [
  { plugin: "omarchy.audio", icon: "󰕾", label: "Audio" },
  { plugin: "omarchy.network", icon: "󰖩", label: "Network" },
  { plugin: "omarchy.bluetooth", icon: "󰂯", label: "Bluetooth" },
  { plugin: "omarchy.monitor", icon: "󰍹", label: "Display" },
  { plugin: "omarchy.clock", icon: "󰃭", label: "Calendar" },
  { plugin: "omarchy.tailscale", icon: "", iconFile: "tailscale/TailscaleIcon.qml", label: "Tailscale" },
  { plugin: "omarchy.agents", icon: "󱚣", label: "Agents" },
  { plugin: "omarchy.dropbox", icon: "", iconFile: "dropbox/DropboxIcon.qml", label: "Dropbox" },
  { plugin: "omarchy.power", icon: "󰂄", label: "Power" }
]

// Overlays are available independently of the bar layout.
var OVERLAYS = [
  { plugin: "omarchy.clipboard", icon: "", label: "Clipboard" }
]

// Searchable without adding another default ring slice.
var EXTRAS = [
  { plugin: "xpo.files", icon: "󰉋", label: "Files",
    keywords: "file manager browser folder directory explorer nautilus" }
]

// Searchable panels kept off the default ring so its count stays even.
var SEARCH_PANELS = [
  { plugin: "omarchy.weather", icon: "", label: "Weather" }
]

// Clones keep their source's mark; unknown panels get a generic one. Panels
// that already have a fixed search row are not repeated.
function livePanels(live) {
  var marks = {}, fixed = {}
  var known = PANELS.concat(SEARCH_PANELS)
  for (var i = 0; i < known.length; i++) marks[known[i].plugin] = known[i]
  var rows = OVERLAYS.concat(EXTRAS)
  for (var k = 0; k < rows.length; k++) fixed[rows[k].plugin] = true
  var out = []
  for (var j = 0; j < live.length; j++) {
    var p = live[j]
    if (fixed[p.id]) continue
    var mark = marks[p.source] || { icon: "󰕮" }
    out.push({ plugin: p.id, icon: mark.icon, iconFile: mark.iconFile,
               label: p.id === mark.plugin ? mark.label : p.name,
               keywords: p.name + " " + (mark.label || "") })
  }
  return out
}

function ringIds(raw) {
  var cfg = parse(raw)
  return (cfg.slices && cfg.slices.length) ? cfg.slices : null
}

function barWidgets(raw) {
  var cfg = parse(raw)
  var layout = (cfg.bar && cfg.bar.layout) || null
  if (!layout) return null
  var ids = {}
  for (var section in layout) {
    var row = layout[section]
    if (!row) continue
    // Omarchy takes a widget as its id alone or as an object carrying one.
    for (var i = 0; i < row.length; i++) {
      var id = typeof row[i] === "string" ? row[i] : row[i] && row[i].id
      if (id) ids[id] = true
    }
  }
  return ids
}

// Bar membership chooses default slices; PANELS keeps their order stable.
function panels(barIds) {
  var out = []
  for (var i = 0; i < PANELS.length; i++)
    if (!barIds || barIds[PANELS[i].plugin]) out.push(PANELS[i])
  return out.concat(OVERLAYS)
}

var CONDITION_READERS = [
  "omarchy-default-agent", "omarchy-default-browser", "omarchy-default-terminal", "omarchy-default-editor",
  "omarchy-dns", "omarchy-network-status", "omarchy-channel-current", "omarchy-lock-design current",
  "dell-xps-touchpad-haptics get", "findmnt -no FSTYPE /"
]

// Every `when` and `checked` in one bash script, echoing `<id>:w` or `<id>:c` for each that holds.
// Asked one at a time the package checks alone take over a second, so one `pacman -T` answers
// every name they ask about, and known readers in simple comparisons run once.
function conditionScript(items) {
  var checks = [], names = {}, reads = []
  for (var id in items) {
    var tags = { w: items[id].when, c: items[id].checked }
    for (var tag in tags) {
      if (!tags[tag]) continue
      var expr = String(tags[tag])
      var asked = /omarchy-pkg-(?:present|missing)((?:[ \t]+[\w@.+-]+)+)/g, m
      while ((m = asked.exec(expr))) m[1].trim().split(/\s+/).forEach(function (n) { names[n] = true })
      // Only a whole comparison of a known reader and literal/pattern can share its output.
      // Assignments, guards, quoted shell text and arbitrary commands keep their Bash semantics.
      var comparison = /^\[\[ ("?)\$\(([\w .\/=-]+)\)\1 == ("[\w .\/-]*"|'[\w .\/-]*'|[\w.*\/-]+) \]\]$/.exec(expr)
      if (comparison && CONDITION_READERS.indexOf(comparison[2]) >= 0) {
        var read = comparison[2]
        if (reads.indexOf(read) < 0) reads.push(read)
        expr = "[[ " + comparison[1] + "${__read" + reads.indexOf(read) + "}" + comparison[1]
             + " == " + comparison[3] + " ]]"
      }
      checks.push("if { " + expr + "; } >/dev/null 2>&1; then echo " + id + ":" + tag + "; fi")
    }
  }
  var pkgs = Object.keys(names)
  // Asked names start installed and pacman -T prints those that are not; any other name, or a
  // query that failed, asks pacman itself, as omarchy-pkg-present does.
  var head = [
    "declare -A __pkg=(" + pkgs.map(function (n) { return "[" + n + "]=1" }).join(" ") + ")",
    "__missing=$(pacman -T -- " + pkgs.join(" ") + " 2>/dev/null)",
    "case $? in 0|127) for __p in $__missing; do __pkg[$__p]=0; done ;; *) __pkg=() ;; esac",
    "__has() { case ${__pkg[$1]-} in 1) return 0 ;; 0) return 1 ;; esac; pacman -Q \"$1\" &>/dev/null; }",
    "omarchy-pkg-present() { local p; for p; do __has \"$p\" || return 1; done; }",
    "omarchy-pkg-missing() { local p; for p; do __has \"$p\" || return 0; done; return 1; }"
  ]
  for (var r = 0; r < reads.length; r++) head.push("__read" + r + "=$(" + reads[r] + " 2>/dev/null)")
  return head.concat(checks).join("\n")
}

var NO_CONDITIONS = { when: {}, checked: {}, full: {}, ready: false }

// Empty output signals evaluation failure; keep conditional rows visible.
function parseConditions(raw, items) {
  var ls = lines(raw)
  if (!ls.length) return NO_CONDITIONS
  var cond = { when: {}, checked: {}, ready: true }
  for (var i = 0; i < ls.length; i++) {
    var at = ls[i].lastIndexOf(":")
    var holds = ls[i].slice(at + 1) === "c" ? cond.checked : cond.when
    holds[ls[i].slice(0, at)] = true
  }
  cond.full = populated(items, cond)
  return cond
}

function passes(e, id, cond) {
  return !e.when || !cond.ready || cond.when[id] === true
}

// Mark ancestors of surviving actions so empty submenus stay hidden.
function populated(items, cond) {
  var out = {}
  for (var id in items) {
    var e = items[id]
    if (!e || (!e.action && !e.provider) || !passes(e, id, cond)) continue
    var parts = id.split(".")
    for (var i = parts.length - 1; i >= 1; i--) {
      var pid = parts.slice(0, i).join(".")
      var parent = items[pid]
      if (parent && !passes(parent, pid, cond)) break
      out[pid] = true
    }
  }
  return out
}

function shows(id, e, cond) {
  if (!passes(e, id, cond)) return false
  return e.action || e.provider || !cond.ready || cond.full[id] === true
}

// Providers hand off to Omarchy; nodes carry the id the ring drills into. Omarchy's own marks
// sit in a font of their own, at codepoints a Nerd Font fills with other glyphs.
function entryOf(id, e, cond) {
  var s = { id: id, icon: e.icon || "󰍜", label: (e.label || id) + (cond.checked[id] ? " ✓" : "") }
  if (e.iconFont) s.iconFont = e.iconFont
  if (e.action) s.action = e.action
  else if (e.provider) s.action = "omarchy-menu summon " + id
  else s.node = id
  return s
}

function childrenOf(items, parent, cond) {
  var prefix = parent ? parent + "." : ""
  var depth = parent ? parent.split(".").length + 1 : 1
  var out = []
  for (var id in items) {
    if (id.indexOf(prefix) !== 0 || id.split(".").length !== depth) continue
    var e = items[id]
    if (!shows(id, e, cond)) continue
    out.push(entryOf(id, e, cond))
  }
  return out
}

function ringOf(items, ids, cond) {
  var byPlugin = {}
  var catalogue = panels(null).concat(EXTRAS)
  for (var i = 0; i < catalogue.length; i++) byPlugin[catalogue[i].plugin] = catalogue[i]
  var out = []
  for (var j = 0; j < ids.length; j++) {
    var id = String(ids[j])
    if (byPlugin[id]) { out.push(byPlugin[id]); continue }
    var e = items[id]
    if (e && shows(id, e, cond)) out.push(entryOf(id, e, cond))
  }
  return out
}

function ringSlices(items, path, cond, ring) {
  return path.length ? childrenOf(items, path.join("."), cond) : ring
}

function panelRows(panels) {
  var out = []
  for (var i = 0; i < panels.length; i++) {
    var p = panels[i]
    out.push({ icon: p.icon, iconFile: p.iconFile, label: p.label, trail: "Panel",
               kind: KIND.slice, plugin: p.plugin,
               keywords: (p.label + " " + (p.keywords || "")).toLowerCase() })
  }
  return out
}

// Cache flattened menu rows separately from sources that change on every open.
function menuRows(items, cond) {
  var out = []
  for (var id in items) {
    var e = items[id]
    if (!e || e.search === false || !shows(id, e, cond)) continue
    var trail = trailOf(items, id)
    var row = entryOf(id, e, cond)
    row.trail = trail.join(" › ")
    row.kind = KIND.menu
    row.keywords = [e.label, trail.join(" "), String(id).replace(/[.]/g, " "),
                    [].concat(e.aliases || []).join(" "), e.description || ""]
                   .join(" ").toLowerCase()
    out.push(row)
  }
  return out
}

function liveRows(sources) {
  var out = []
  // App rows launch by desktop id and carry icon names.
  var apps = sources.apps
  var iconByAppId = {}
  for (var j = 0; j < apps.length; j++) {
    var a = apps[j].entry
    if (!a.id) continue
    var name = String(a.name || a.id)
    var appIcon = String(a.icon || a.id)
    iconByAppId[String(a.id).toLowerCase()] = appIcon
    out.push({
      icon: "󰖯", appIcon: appIcon, label: name, trail: "App",
      appId: String(a.id), kind: KIND.app,
      keywords: [name, a.genericName || "",
                 a.keywords && a.keywords.join ? a.keywords.join(" ") : ""]
                .join(" ").toLowerCase(),
      // Search only the dotted id tail as whole words.
      ident: String(a.id).split(".").pop().replace(/[_-]/g, " ").toLowerCase()
    })
  }
  // Store window addresses, and resolve icons through matching desktop entries.
  var windows = sources.windows
  for (var w = 0; w < windows.length; w++) {
    var t = windows[w]
    var ipc = t.lastIpcObject || {}
    var appId = String((t.wayland && t.wayland.appId) || "")
    var title = String(t.title || appId)
    if (!title) continue
    out.push({
      icon: "󰖯", appIcon: iconByAppId[appId.toLowerCase()] || "", label: title,
      trail: "Window" + (appId ? " · " + appId : ""), address: "0x" + t.address,
      kind: KIND.window,
      recency: recencyOf(sources.focusOrder, t.address, ipc.focusHistoryID),
      keywords: (title + " " + appId).toLowerCase()
    })
  }
  return out
}

// Menu terms start words; app and window text also accepts substrings.
// Windows rank as direct hits unless a term only matched inside a word; squashed text keeps
// "wifi" matching "Wi-Fi".
function words(text) {
  var low = String(text || "").toLowerCase()
  return " " + low.replace(/[^a-z0-9]+/g, " ").trim()
       + " " + low.replace(/[^a-z0-9]+/g, "") + " "
}

function startsWord(padded, term) {
  return padded.indexOf(" " + term) !== -1
}

function wholeWord(padded, term) {
  return padded.indexOf(" " + term + " ") !== -1
}

function squash(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
}

function search(index, query, limit, uses) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return []
  var terms = q.split(/[^a-z0-9]+/)
  var spaced = q.replace(/[^a-z0-9]+/g, " ").trim()
  var squashed = squash(q)
  var hits = []
  for (var i = 0; i < index.length; i++) {
    var e = index[i]
    // Rows are replaced when their sources refresh; normalize once on first search.
    var text = e._search || (e._search = {
      keywords: words(e.keywords), ident: e.ident ? words(e.ident) : ""
    })
    var partial = e.kind === KIND.app || e.kind === KIND.window
    var matched = true, inside = false
    for (var t = 0; t < terms.length; t++) {
      if (!terms[t]) continue
      if (startsWord(text.keywords, terms[t])) continue
      if (partial && text.keywords.indexOf(terms[t]) !== -1) { inside = true; continue }
      if (text.ident && wholeWord(text.ident, terms[t])) continue
      matched = false; break
    }
    if (!matched) continue
    if (text.squashed === undefined) text.squashed = squash(e.label)
    var rank = e.kind === KIND.window && !inside ? 0
             : text.squashed.indexOf(squashed) === 0 ? 0
             : startsWord(text.label || (text.label = words(e.label)), spaced) ? 1 : 2
    hits.push({ rank: rank, exact: text.squashed === squashed ? 0 : 1,
                uses: -(uses[keyOf(e)] || 0), len: e.label.length, entry: e })
  }
  // An exact label beats a more-used one it prefixes: "lock" locks before it lists designs.
  hits.sort(function (a, b) {
    return a.rank - b.rank
        || a.entry.kind - b.entry.kind
        || a.exact - b.exact
        || a.uses - b.uses
        || (a.entry.recency || 0) - (b.entry.recency || 0)
        || a.len - b.len
  })
  var out = []
  for (var j = 0; j < hits.length && j < limit; j++) out.push(hits[j].entry)
  return out
}

// Leading sigils select a search source.
var MODES = { "/": "file" }

function modeOf(query) {
  return MODES[String(query || "").charAt(0)] || ""
}

function termOf(query) {
  var q = String(query || "")
  return modeOf(q) ? q.slice(1) : q
}

var NO_FILES = { paths: [], lower: [] }

// fd marks directories with trailing slashes; fold case and find names once per scan.
function parseFiles(raw) {
  var paths = lines(raw)
  var lower = [], starts = []
  for (var i = 0; i < paths.length; i++) {
    var low = paths[i].toLowerCase()
    lower.push(low)
    // The name follows the last slash, skipping a directory's trailing one.
    starts.push(low.lastIndexOf("/", low.length - 2) + 1)
  }
  return { paths: paths, lower: lower, starts: starts }
}

function fileRow(path, home) {
  var isDir = path.charAt(path.length - 1) === "/"
  var bare = isDir ? path.slice(0, -1) : path
  var cut = bare.lastIndexOf("/")
  var dir = bare.slice(0, cut) || "/"
  return {
    icon: isDir ? "󰉋" : "󰈔",
    label: bare.slice(cut + 1),
    trail: dir.indexOf(home) === 0 ? "~" + dir.slice(home.length) : dir,
    path: path
  }
}

function pathPayload(path) {
  var p = String(path)
  if (p.charAt(p.length - 1) === "/") return JSON.stringify({ dir: p.slice(0, -1) })
  var cut = p.lastIndexOf("/")
  return JSON.stringify({ dir: p.slice(0, cut) || "/", select: p.slice(cut + 1) })
}

// Rank paths by name position and length; materialize rows only for winners.
function fileRows(files, term, limit, home) {
  var src = files || NO_FILES
  var q = String(term || "").trim().toLowerCase()
  if (!q) return []
  var terms = q.split(/\s+/)
  // Later ties cannot enter the first `limit` results.
  var buckets = [[], [], []]
  for (var i = 0; i < src.lower.length; i++) {
    var low = src.lower[i]
    var matched = true
    for (var t = 0; t < terms.length; t++) {
      if (low.indexOf(terms[t]) === -1) { matched = false; break }
    }
    if (!matched) continue
    // Search the name in place; a match running into a directory's slash is outside it.
    var start = src.starts[i]
    // 47 is "/"; charAt would allocate a string per path.
    var end = low.charCodeAt(low.length - 1) === 47 ? low.length - 1 : low.length
    var at = low.indexOf(q, start)
    if (at + q.length > end) at = -1
    var rank = at === start ? 0 : (at !== -1 ? 1 : 2)
    var lengths = buckets[rank]
    var ties = lengths[end - start]
    if (!ties) ties = lengths[end - start] = []
    if (ties.length < limit) ties.push(i)
  }
  var out = []
  for (var r = 0; r < buckets.length; r++) {
    for (var len = 0; len < buckets[r].length; len++) {
      var entries = buckets[r][len] || []
      for (var j = 0; j < entries.length; j++) {
        if (out.length >= limit) return out
        out.push(fileRow(src.paths[entries[j]], home))
      }
    }
  }
  return out
}
