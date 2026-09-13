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

// Shell-quote theme and font names.
function quote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

// Prefer observed focus order, then Hyprland's cached history.
function recencyOf(order, address, cachedHistory) {
  var seen = order.indexOf(address)
  return seen >= 0 ? seen : order.length + (Number(cachedHistory) || 0)
}

function styleRows(out, names, icon, trail, command) {
  for (var i = 0; i < names.length; i++) {
    var name = String(names[i])
    out.push({
      icon: icon, label: name, trail: trail, kind: KIND.style,
      action: command + quote(name),
      keywords: (name + " " + trail).toLowerCase()
    })
  }
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

// Clones keep their source's mark; unknown panels get a generic one.
function livePanels(live) {
  var marks = {}
  var known = PANELS.concat(SEARCH_PANELS)
  for (var i = 0; i < known.length; i++) marks[known[i].plugin] = known[i]
  var out = []
  for (var j = 0; j < live.length; j++) {
    var p = live[j]
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
    if (!row || !row.length) continue
    for (var i = 0; i < row.length; i++) if (row[i] && row[i].id) ids[row[i].id] = true
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

// Evaluate all Bash-only `when` expressions in one process.
function conditionScript(items) {
  var out = []
  for (var id in items)
    if (items[id].when)
      out.push("if " + items[id].when + " >/dev/null 2>&1; then echo " + id + "; fi")
  return out.join("\n")
}

var NO_CONDITIONS = { when: {}, full: {}, ready: false }

// Empty output signals evaluation failure; keep conditional rows visible.
function parseConditions(raw, items) {
  var ls = lines(raw)
  if (!ls.length) return NO_CONDITIONS
  var cond = { when: {}, ready: true }
  for (var i = 0; i < ls.length; i++) cond.when[ls[i]] = true
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

function shows(items, id, e, cond) {
  if (!passes(e, id, cond)) return false
  return e.action || e.provider || !cond.ready || cond.full[id] === true
}

// Providers hand off to Omarchy; nodes carry the id the ring drills into.
function entryOf(id, e) {
  var s = { id: id, icon: e.icon || "󰍜", label: e.label || id }
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
    if (!shows(items, id, e, cond)) continue
    out.push(entryOf(id, e))
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
    if (e && shows(items, id, e, cond)) out.push(entryOf(id, e))
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
    if (!e || !shows(items, id, e, cond)) continue
    var trail = trailOf(items, id)
    var row = entryOf(id, e)
    row.trail = trail.join(" › ")
    row.kind = KIND.menu
    row.keywords = [e.label, trail.join(" "), String(id).replace(/[.]/g, " "),
                    (e.aliases || []).join(" "), e.description || ""]
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
      trail: appId || "Window", address: "0x" + t.address,
      kind: KIND.window,
      recency: recencyOf(sources.focusOrder, t.address, ipc.focusHistoryID),
      keywords: (title + " " + appId).toLowerCase()
    })
  }
  styleRows(out, sources.themes, "󰸌", "Theme", "omarchy theme set ")
  styleRows(out, sources.fonts, "󰛖", "Font", "omarchy font set ")
  return out
}

// Every term must start a word. Sort by label rank, kind, use, recency, then length.
// Windows always rank as direct hits; squashed text keeps "wifi" matching "Wi-Fi".
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
  var counts = uses || {}
  var q = String(query || "").trim().toLowerCase()
  if (!q) return []
  var terms = q.split(/[^a-z0-9]+/)
  var spaced = q.replace(/[^a-z0-9]+/g, " ").trim()
  var squashed = squash(q)
  var hits = []
  for (var i = 0; i < index.length; i++) {
    var e = index[i]
    var haystack = words(e.keywords)
    var ident = e.ident ? words(e.ident) : ""
    var matched = true
    for (var t = 0; t < terms.length; t++) {
      if (!terms[t]) continue
      if (startsWord(haystack, terms[t])) continue
      if (ident && wholeWord(ident, terms[t])) continue
      matched = false; break
    }
    if (!matched) continue
    var rank = e.kind === KIND.window ? 0
             : squash(e.label).indexOf(squashed) === 0 ? 0
             : startsWord(words(e.label), spaced) ? 1 : 2
    hits.push({ rank: rank, uses: -(counts[keyOf(e)] || 0), len: e.label.length, entry: e })
  }
  hits.sort(function (a, b) {
    return a.rank - b.rank
        || a.entry.kind - b.entry.kind
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

// fd marks directories with trailing slashes; fold case once per scan.
function parseFiles(raw) {
  var paths = lines(raw)
  var lower = []
  for (var i = 0; i < paths.length; i++) lower.push(paths[i].toLowerCase())
  return { paths: paths, lower: lower }
}

function nameOf(path) {
  var end = path.charAt(path.length - 1) === "/" ? path.length - 1 : path.length
  return path.slice(path.lastIndexOf("/", end - 1) + 1, end)
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
    var name = nameOf(low)
    var at = name.indexOf(q)
    var rank = at === 0 ? 0 : (at !== -1 ? 1 : 2)
    var lengths = buckets[rank]
    var ties = lengths[name.length]
    if (!ties) ties = lengths[name.length] = []
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
