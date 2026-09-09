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

// What a row is across opens, for the use counter. A menu row carries both an
// id and an action, and the id is the stable half -- an action's text changes
// whenever Omarchy retunes a command. Windows deliberately answer "": their
// address is new on every launch, and they already sort on live focus order.
function keyOf(e) {
  if (e.plugin) return e.plugin
  if (e.id) return e.id
  if (e.appId) return "app:" + e.appId
  return e.action || ""
}

// The breadcrumb of an open ring, current node included.
function crumb(items, path) {
  var out = []
  for (var i = 0; i < path.length; i++) {
    var e = items[path.slice(0, i + 1).join(".")]
    out.push((e && e.label) || path[i])
  }
  return out.join(" \u203a ")
}

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

// How long ago a window was focused, smaller being more recent. The order the
// wheel observed itself wins. A window it has not seen focused -- every one of
// them, for a moment after the shell restarts -- sorts behind those, by
// Hyprland's own cached history, which is right at the instant it was fetched.
function recencyOf(order, address, cachedHistory) {
  var seen = order.indexOf(address)
  return seen >= 0 ? seen : order.length + (Number(cachedHistory) || 0)
}

// Themes and fonts are one shape: a name the CLI takes as an argument.
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

// The shell plugins the wheel opens, in ring order. Every icon here is one the
// widget itself already draws -- a glyph where it has one, otherwise its own
// `iconFile` component, which is the only honest answer for Tailscale's and
// Dropbox's marks. Nothing is chosen by eye: a plausible-looking codepoint is
// how you end up drawing a mark that is not the product's.
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

// Overlays rather than bar widgets, so nothing in the bar layout vouches for
// them. They are on the ring unconditionally.
var OVERLAYS = [
  { plugin: "omarchy.clipboard", icon: "", label: "Clipboard" }
]

// Ours: searchable without a disc. Outside panels(), so the default ring keeps
// the even count that fills 3 and 9 o'clock. Searching as a slice is what puts
// it over GNOME Files, whose entry is also called "Files": an app loses to a
// slice on `kind` before a use count is consulted.
var EXTRAS = [
  { plugin: "xpo.files", icon: "󰉋", label: "Files",
    keywords: "file manager browser folder directory explorer nautilus" }
]

// The ring the user asked for, as a list of ids. Null when there is no config
// or it names no ring, which falls the wheel back to the bar's widgets.
function ringIds(raw) {
  var cfg = parse(raw)
  return (cfg.slices && cfg.slices.length) ? cfg.slices : null
}

// Every widget id the bar carries, whichever section it sits in. Null when the
// file names no layout, which lets the caller fall back to another one.
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

// The default ring: a widget earns a slice by being in the bar, which is a
// list the user already curates, so adding a widget to the bar adds it to the
// wheel. Order comes from PANELS rather than from the bar, so a slice does not
// move when the bar is rearranged. Overridden entirely by wheel.json.
function panels(barIds) {
  var out = []
  for (var i = 0; i < PANELS.length; i++)
    if (!barIds || barIds[PANELS[i].plugin]) out.push(PANELS[i])
  return out.concat(OVERLAYS)
}

// `when` says whether a row exists on this machine. 144 of them in the stock
// menu, so they go out as one script rather than 144 subprocesses: a line
// prints its id when its condition holds, and silence is a failure. Bash, not
// sh -- they use [[ ]] and compgen.
function conditionScript(items) {
  var out = []
  for (var id in items)
    if (items[id].when)
      out.push("if " + items[id].when + " >/dev/null 2>&1; then echo " + id + "; fi")
  return out.join("\n")
}

var NO_CONDITIONS = { when: {}, full: {}, ready: false }

// No output at all means the script never ran, not that every condition failed:
// on any machine some of these are negations that hold. Answering "nothing
// passed" would hide every conditional row in the menu, so an empty read stays
// not-ready and the menu stays whole.
function parseConditions(raw, items) {
  var ls = lines(raw)
  if (!ls.length) return NO_CONDITIONS
  var cond = { when: {}, ready: true }
  for (var i = 0; i < ls.length; i++) cond.when[ls[i]] = true
  cond.full = populated(items, cond)
  return cond
}

// Before the first evaluation lands nothing is known, and hiding everything
// conditional would gut the menu -- so unknown means visible.
function passes(e, id, cond) {
  return !e.when || !cond.ready || cond.when[id] === true
}

// The submenus that still have something under them. Trigger > Hardware is six
// rows on a laptop and none on a desktop, and drilling into an empty ring is
// worse than never being offered. Walked up from each surviving leaf, stopping
// at the first ancestor that failed, so a hidden branch does not vouch for its
// parent.
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

// Survived its own `when`, and if a submenu, something survived under it.
function shows(items, id, e, cond) {
  if (!passes(e, id, cond)) return false
  return e.action || e.provider || !cond.ready || cond.full[id] === true
}

// A menu entry as a ring slice or a search row. An action runs; a submenu
// carries the id the ring drills into.
//
// Except a provider, whose rows the menu generates at runtime -- the app list,
// the installed fonts -- and which the wheel has no way to render. Those hand
// the whole route back to Omarchy's own menu rather than being dropped, so
// every menu stays one search away, including any provider a later Omarchy
// adds that this file has never heard of.
function entryOf(id, e) {
  // `id` rides along so check.js can observe what the index emitted rather
  // than re-derive it and agree with itself.
  var s = { id: id, icon: e.icon || "󰍜", label: e.label || id }
  if (e.action) s.action = e.action
  else if (e.provider) s.action = "omarchy-menu summon " + id
  else s.node = id
  return s
}

// The direct children of a node, in file order -- which is the order the
// Omarchy menu itself lists them in. `parent` is "" for the root.
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

// Ids to slices. A panel id names one of PANELS or OVERLAYS; anything else is a
// menu id. An id that names nothing is dropped, not drawn as a blank disc.
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

// What the ring shows: the chosen slices at the root, a node's children below.
function ringSlices(items, path, cond, ring) {
  return path.length ? childrenOf(items, path.join("."), cond) : ring
}

// Panels carry their target directly rather than a ring index: the ring's
// contents depend on how deep you have drilled, so an index means nothing by
// the time a result is picked.
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

// Every menu entry, leaves and submenus alike: a submenu holds nothing to run,
// but searching "install" has to find Install, not only what is filed under it.
// Kept apart from the live half because flattening 320 entries costs three
// times what everything else does, and it only changes when the menu files load
// or the conditions come back -- not on every open.
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

// Everything that can differ between one open and the next:
// { apps, windows, focusOrder, themes, fonts }.
function liveRows(sources) {
  var out = []
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
      icon: "󰖯", appIcon: appIcon, label: name, trail: "App",
      appId: String(a.id), kind: KIND.app,
      // Deliberately not Comment. It is prose about what an app does, so
      // "files" matches Neovim ("Edit text files"). GenericName and Keywords
      // are the fields an author fills in to be found BY.
      keywords: [name, a.genericName || "",
                 a.keywords && a.keywords.join ? a.keywords.join(" ") : ""]
                .join(" ").toLowerCase(),
      // The id is a filename, so its pieces are packaging: as a prefix "sys"
      // reaches Print Settings through "system-config-printer". search()
      // matches it WHOLE instead, which keeps "nvim" -> Neovim and "printer"
      // -> Print Settings. Dotted tail only; the rest is reverse-DNS.
      ident: String(a.id).split(".").pop().replace(/[_-]/g, " ").toLowerCase()
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
  // Both are buried behind pickers in the menu -- style.theme shells out to a
  // second overlay -- so flattening them here is what makes them reachable.
  styleRows(out, sources.themes, "󰸌", "Theme", "omarchy theme set ")
  styleRows(out, sources.fonts, "󰛖", "Font", "omarchy font set ")
  return out
}

// Every term must appear somewhere in the entry, so terms narrow rather than
// widen. Rows then sort on four keys in order:
//
//   rank    a label that starts with the query, then one that merely contains
//           it, then a hit that only matched a breadcrumb, alias or app id.
//   kind    KIND above. "firefox" matches the app and the menu's install,
//           remove and set-default rows identically; the app is what was meant.
//   uses    how often this row has been picked before, most-used first. Under
//           `kind` rather than over it, so habit breaks ties inside a kind --
//           which of forty themes -- and never reorders the kinds themselves:
//           that an app beats a row offering to install it is a fact about the
//           query, while a use count is only a guess.
//   recency for windows, Hyprland's focus history -- the one you were last in
//           comes first. Zero, and inert, for everything else.
//   len     shorter labels win, which floats "Screenshot" over "Stop
//           Screenrecording" among menu entries.
//
// An open window is never a weak hit: matching one at all counts as rank 0.
// A window title is written by the program, so the query lands mid-string
// ("...Omarchy Plugins - Brave") where a menu label has it at the front, and
// without this the window you are looking at sorts below seven rows offering
// to install the thing.
// A term matches a word that STARTS with it, never a substring inside one --
// otherwise "sys" reaches Files through "filesystem". Non-alphanumerics become
// spaces and the whole is padded, so "starts a word" is a plain indexOf.
// The punctuation-stripped form rides along too, because splitting alone turns
// "Wi-Fi" into "wi" and "fi" and nobody types either.
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

// For asking whether a NAME begins with the query: "wifi" and "wi-fi" squash
// alike, so either finds Wi-Fi and both count as a hit on the front.
function squash(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "")
}

function search(index, query, limit, uses) {
  var counts = uses || {}
  var q = String(query || "").trim().toLowerCase()
  if (!q) return []
  // Split on punctuation, not just spaces, so a typed "wi-fi" is the same two
  // terms the haystack was built from.
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
    // Where the query landed IN THE NAME: at its front, at the front of a
    // later word, or nowhere -- which means it only matched something the row
    // is filed under rather than what it is called.
    var rank = e.kind === KIND.window ? 0
             : squash(e.label).indexOf(squashed) === 0 ? 0
             : startsWord(words(e.label), spaced) ? 1 : 2
    // Negated so every key in the comparator below sorts ascending.
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

// A leading sigil aims the query at one source instead of at everything. With
// no sigil the query searches the whole index, which is what it has always
// done. One entry today: the point of the table is that the next source --
// emoji, clipboard, the two that have been waiting on this decision -- is a
// line here rather than a branch in three places.
var MODES = { "/": "file" }

function modeOf(query) {
  return MODES[String(query || "").charAt(0)] || ""
}

// The query with its sigil taken off, which is what the mode's source is
// actually asked for. Unchanged when there is no mode.
function termOf(query) {
  var q = String(query || "")
  return modeOf(q) ? q.slice(1) : q
}

var NO_FILES = { paths: [], lower: [] }

// fd's own output: one absolute path per line, a directory carrying a trailing
// slash -- which is how a row knows which of the two marks to wear without a
// second walk to ask.
//
// Folded to lower case once here rather than per keystroke. Matching eighty
// thousand paths case-insensitively is the only work file mode does, and doing
// the folding inside that loop is most of its cost.
function parseFiles(raw) {
  var paths = lines(raw)
  var lower = []
  for (var i = 0; i < paths.length; i++) lower.push(paths[i].toLowerCase())
  return { paths: paths, lower: lower }
}

// Where a path's own name starts and ends, ignoring a directory's trailing
// slash. Two callers, and getting the slash wrong in either one names every
// directory "".
function nameOf(path) {
  var end = path.charAt(path.length - 1) === "/" ? path.length - 1 : path.length
  return path.slice(path.lastIndexOf("/", end - 1) + 1, end)
}

// The name is what was searched for; the directory above it is what tells two
// `main.py`s apart. Shown relative to home, because everything scanned is
// under it.
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

// Where a picked path opens: the browser, standing in the directory the path
// lives in with the path itself selected. A file is not a command and the wheel
// is not an editor -- "open" for a file here means "show me it, where it
// lives", which is the one thing a browser does better than a launcher.
function pathPayload(path) {
  var p = String(path)
  if (p.charAt(p.length - 1) === "/") return JSON.stringify({ dir: p.slice(0, -1) })
  var cut = p.lastIndexOf("/")
  return JSON.stringify({ dir: p.slice(0, cut) || "/", select: p.slice(cut + 1) })
}

// Every term somewhere in the path, the same narrowing search() does. Rows are
// then ordered by where the match landed -- at the front of the name, inside
// it, or only in some directory above it -- and then by the shorter name,
// which is what floats `Wheel.qml` over `WheelSettingsDialog.qml`.
//
// Paths stay raw strings until a row wins. Building eighty thousand row objects
// to hand back eight is the whole reason this does not reuse search(), and a
// use count is not consulted at all: what you open from a launcher is whatever
// you are working on this week, which is a worse predictor than the query.
function fileRows(files, term, limit, home) {
  var src = files || NO_FILES
  var q = String(term || "").trim().toLowerCase()
  if (!q) return []
  var terms = q.split(/\s+/)
  // Rank and name length are integer keys. Keep only the first `limit` ties
  // in each bucket: later ties cannot appear in the first `limit` results.
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
