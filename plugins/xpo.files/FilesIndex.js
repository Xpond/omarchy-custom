.pragma library

// Snapshot because FolderListModel cannot filter directories and rank matches.
function snapshot(model, limit) {
  var out = []
  var count = limit === undefined ? model.count : Math.min(model.count, limit)
  for (var i = 0; i < count; i++) {
    out.push({
      name: String(model.get(i, "fileName")),
      path: String(model.get(i, "filePath")),
      isDir: !!model.get(i, "fileIsDir"),
      size: Number(model.get(i, "fileSize")) || 0,
      modified: model.get(i, "fileModified")
    })
  }
  return out
}

// Sort once per directory/order; typing reuses this order in matching().
function ordered(entries, order) {
  var hits = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    hits.push({ entry: e, time: order === "date" ? when(e.modified) : 0 })
  }
  hits.sort(function (a, b) {
    // Deleted rows arrive with git's status, after the rest; last, they move no selection.
    if (!a.entry.missing !== !b.entry.missing) return a.entry.missing ? 1 : -1
    if (a.entry.isDir !== b.entry.isDir) return a.entry.isDir ? -1 : 1
    var rank = 0
    if (order === "date") rank = b.time - a.time
    // Folder metadata size does not represent its contents.
    else if (order === "size" && !a.entry.isDir) rank = b.entry.size - a.entry.size
    return rank || a.entry.name.localeCompare(b.entry.name)
  })
  var out = []
  for (var j = 0; j < hits.length; j++) out.push(hits[j].entry)
  return out
}

// Entries already have their metadata/name order; typing only partitions name matches.
function matching(entries, query, order) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return entries
  var groups = [[], [], [], []]
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i], at = e.name.toLowerCase().indexOf(q)
    if (at === -1) continue
    var group = order === "date" ? 0
      : e.isDir ? (at === 0 ? 0 : 1)
      : order === "size" || at === 0 ? 2 : 3
    groups[group].push(e)
  }
  return groups[0].concat(groups[1], groups[2], groups[3])
}

var ORDERS = ["name", "date", "size"]
var ORDER_WORDS = { name: "", date: "newest", size: "largest" }

function nextOrder(order) {
  return ORDERS[(ORDERS.indexOf(order) + 1) % ORDERS.length]
}

function when(modified) {
  return (modified && new Date(modified).getTime()) || 0
}

function parentOf(dir) {
  var d = String(dir || "")
  if (d.length <= 1) return "/"
  var cut = d.lastIndexOf("/")
  return cut <= 0 ? "/" : d.slice(0, cut)
}

// Jail paths to home; the slash prevents /home/xpo2 from matching /home/xpo.
function within(dir, home) {
  var d = String(dir || "")
  return (d === home || d.indexOf(home + "/") === 0) ? d : home
}

function display(dir, home) {
  var d = String(dir || "")
  return d.indexOf(home) === 0 ? "~" + d.slice(home.length) : d
}

function crumbs(dir, home) {
  var parts = display(dir, home).split("/")
  var out = []
  for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
  if (!out.length) return ["/"]
  // Preserve both ends of long paths.
  if (out.length > 5) out = [out[0], "\u2026"].concat(out.slice(-3))
  return out
}

// Lines as an editor counts them: a final newline ends the last line, it does not start one.
function lineLabel(text) {
  var t = String(text || "")
  if (!t) return ""
  var n = t.split("\n").length - (t.slice(-1) === "\n" ? 1 : 0)
  return n + (n === 1 ? " line" : " lines")
}

function countLabel(shown, total, query, hidden, order) {
  var s = String(query || "").length
    ? shown + " of " + total
    : shown + (shown === 1 ? " item" : " items")
  if (hidden) s += "  ·  hidden"
  var word = ORDER_WORDS[order]
  return word ? s + "  ·  " + word : s
}

function humanSize(bytes) {
  var units = ["B", "K", "M", "G", "T"]
  var n = Number(bytes) || 0
  var u = 0
  while (n >= 1024 && u < units.length - 1) { n /= 1024; u++ }
  return (u === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + units[u]
}

// Only formats available through this Qt installation.
var IMAGE = { png: 1, jpg: 1, jpeg: 1, gif: 1, webp: 1, bmp: 1,
              svg: 1, ico: 1, icns: 1, tif: 1, tiff: 1, tga: 1 }

// StyledText lays code out an order of magnitude faster than the rich-text <pre>
// it replaced. Keep <pre>'s rules: drop a newline after its opening tag and one
// before its closing tag, drop \r, and keep other whitespace as written, through
// entities StyledText cannot collapse. highlight.py applies the same rules.
function styledCode(text) {
  var t = String(text || "")
  if (t.charAt(0) === "\n") t = t.slice(1)
  if (t.charAt(t.length - 1) === "\n") t = t.slice(0, -1)
  return t.replace(/\r/g, "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/[\n\u2028\u2029]/g, "<br>").replace(/ /g, "&#32;").replace(/\t/g, "&#9;")
    // Qt reads &#133; as an ellipsis; another glyphless control keeps NEL's box.
    .replace(/\x85/g, "\x80")
    .replace(/[\v\f\xa0\u1680\u2000-\u200a\u202f\u205f\u3000]/g,
             function (c) { return "&#" + c.charCodeAt(0) + ";" })
}

// Ready git's diff for reading. The file header goes once a hunk follows: the preview's
// heading already names the file. git lists a whole block of removed lines before the
// lines that replaced them; instead each old line goes straight above the most alike new
// line still unused, in order, and the new lines it passes over go first as plain additions.
// A "\ No newline at end of file" note would split a block, so it goes too.
function readableDiff(text) {
  var at = ("\n" + text).indexOf("\n@@")
  if (at < 0) return text
  var lines = text.slice(at).split("\n").filter(function (l) { return l.charAt(0) !== "\\" })
  // A fixed character-comparison budget bounds pairing work on the UI thread.
  // Once spent, keep Git's ordinary unified order without dropping any lines.
  var out = [], i = 0, budget = 50000
  while (i < lines.length) {
    if (lines[i].charAt(0) !== "-") { out.push(lines[i++]); continue }
    var old = [], now = [], j = 0, oldChars = 0, newChars = 0
    while (i < lines.length && lines[i].charAt(0) === "-") { oldChars += lines[i].length; old.push(lines[i++]) }
    while (i < lines.length && lines[i].charAt(0) === "+") { newChars += lines[i].length; now.push(lines[i++]) }
    var cost = old.length * newChars + now.length * oldChars
    if (cost > budget) {
      old.forEach(function (line) { out.push(line) })
      now.forEach(function (line) { out.push(line) })
      continue
    }
    budget -= cost
    old.forEach(function (o) {
      var best = -1, most = 0
      for (var k = j; k < now.length; k++) {
        var like = likeness(o.slice(1), now[k].slice(1))
        if (like > most) { best = k; most = like }
      }
      if (most < ALIKE) { out.push(o); return }
      while (j < best) out.push(now[j++])
      out.push(o, now[j++])
    })
    while (j < now.length) out.push(now[j++])
  }
  return out.join("\n")
}

// Lines whose shared start and end cover this much of the longer are one line, changed.
var ALIKE = 0.5

// How many characters two lines share at the start, then at the end.
function shared(a, b) {
  var p = 0, s = 0, n = Math.min(a.length, b.length)
  while (p < n && a[p] === b[p]) p++
  while (s < n - p && a[a.length - 1 - s] === b[b.length - 1 - s]) s++
  return [p, s]
}

function likeness(a, b) {
  var ends = shared(a, b)
  return (ends[0] + ends[1]) / Math.max(a.length, b.length, 1)
}

// What differs between a line and the one it pairs with, widened to whole words, in bold.
function emboldened(line, other) {
  var ends = shared(line, other), p = ends[0], s = ends[1]
  while (p > 0 && /\w/.test(line[p - 1])) p--
  while (s > 0 && /\w/.test(line[line.length - s])) s--
  return styledCode(line.slice(0, p)) + "<b>" + styledCode(line.slice(p, line.length - s)) + "</b>"
    + styledCode(line.slice(line.length - s))
}

// Colour a unified diff by how each line starts, in highlight.py's One Dark. A hunk's
// @@ line becomes a ⋯ break carrying git's context; a diff without hunks, as a binary's,
// is all header, in grey. A removed line next to an added one alike enough is a pair, and
// each shows what changed in bold.
function styledDiff(text) {
  // Nothing yet while a diff is on its way.
  if (!text) return ""
  var lines = String(text).replace(/\n$/, "").split("\n"), header = lines[0].slice(0, 2) !== "@@"
  return lines.map(function (line, i) {
    if (line.slice(0, 2) === "@@") line = ("⋯ " + line.replace(/^@@[^@]*@@ ?/, "")).trim()
    var lead = line.charAt(0)
    var colour = header ? "#7f848e" : lead === "⋯" ? "#61afef"
      : lead === "+" ? "#98c379" : lead === "-" ? "#e06c75" : ""
    var other = header ? ""
      : lead === "-" && (lines[i + 1] || "").charAt(0) === "+" ? lines[i + 1]
      : lead === "+" && (lines[i - 1] || "").charAt(0) === "-" ? lines[i - 1] : ""
    var code = other && likeness(line.slice(1), other.slice(1)) >= ALIKE
      ? lead + emboldened(line.slice(1), other.slice(1)) : styledCode(line)
    return colour ? '<font color="' + colour + '">' + code + "</font>" : code
  }).join("<br>")
}

// Each line's number in the file as it is now, the numbers its plain preview shows.
// A removed line is no longer in the file, so it has none.
function diffNumbers(text) {
  var now = 0
  return String(text || "").replace(/\n$/, "").split("\n").map(function (line) {
    var hunk = /^@@ -\d+(?:,\d+)? \+(\d+)/.exec(line)
    if (hunk) { now = +hunk[1]; return "" }
    return now && (line.charAt(0) === "+" || line.charAt(0) === " ") ? now++ : ""
  }).join("\n")
}

// The listed folder's place in its repository, then git's status of everything under it.
// Outside a repository it prints nothing.
function statusCommand(dir, script) {
  return ["python3", script, "status", dir]
}

// statusCommand's output as marks by entry name in the listed folder, or in its folder
// `under`: a file's status letter as git prints it, or ● on a folder holding changes.
function changes(text, under) {
  var cut = text.indexOf("\n"), prefix = text.slice(0, cut) + (under ? under + "/" : ""), marks = Object.create(null)
  text.slice(cut + 1).split("\0").forEach(function (entry) {
    if (entry.slice(3, 3 + prefix.length) !== prefix) return
    var path = entry.slice(3 + prefix.length).replace(/\/$/, "")
    if (!path) return
    var slash = path.indexOf("/")
    marks[slash < 0 ? path : path.slice(0, slash)] = slash < 0 ? entry.slice(0, 2).trim().charAt(0) : "●"
  })
  return marks
}

// Keep deleted files and their missing parent folders reachable in the existing list.
function withDeleted(entries, text, dir, under, hidden) {
  var out = entries.slice(), seen = Object.create(null)
  entries.forEach(function (e) { seen[e.name] = true })
  var cut = text.indexOf("\n"), prefix = text.slice(0, cut) + (under ? under + "/" : "")
  text.slice(cut + 1).split("\0").forEach(function (entry) {
    if (entry.slice(0, 2).indexOf("D") < 0 || entry.slice(3, 3 + prefix.length) !== prefix) return
    var path = entry.slice(3 + prefix.length), slash = path.indexOf("/")
    var name = slash < 0 ? path : path.slice(0, slash)
    if (!name || seen[name] || (!hidden && name.charAt(0) === ".")) return
    seen[name] = true
    out.push({ name: name, path: dir.replace(/\/$/, "") + "/" + (under ? under + "/" : "") + name,
               isDir: slash >= 0, size: 0, modified: null, missing: true })
  })
  return out
}

// How many lines a diff adds and removes.
function diffStat(text) {
  return [(text.match(/^\+/gm) || []).length, (text.match(/^-/gm) || []).length]
}

// Everything uncommitted in one file, staged or not. Literal, so a name like a*b is not a glob.
function diffCommand(dir, name, script) {
  return ["python3", script, "diff", dir, name]
}

// Links are inert here; flatten them to keep theme colors legible.
function flattenLinks(text) {
  return String(text || "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
}

// Escape raw tags outside code; Qt can swallow later blocks after an unclosed tag.
function escapeTags(md) {
  var lines = String(md || "").split("\n")
  var fenced = false
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*(```|~~~)/.test(lines[i])) { fenced = !fenced; continue }
    if (fenced || /^(\t| {4})/.test(lines[i])) continue
    // Odd split members are code spans.
    lines[i] = lines[i].split(/(`+[^`]*`+)/).map(function (part, n) {
      return n % 2 ? part : part.replace(/</g, "&lt;")
    }).join("")
  }
  return lines.join("\n")
}

// Qt drops paragraph margins; preserve blank blocks with non-breaking spaces.
function airOut(md) {
  var lines = String(md || "").split("\n")
  var out = []
  var fenced = false
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^\s*(```|~~~)/.test(line)) fenced = !fenced
    out.push(line)
    if (!fenced && line.trim() === "" && i > 0 && i < lines.length - 1) {
      out.push("\u00a0")
      out.push("")
    }
  }
  return out.join("\n")
}

function isMarkdown(name) {
  var n = String(name).toLowerCase()
  return /\.(md|markdown|mdown|mkd)$/.test(n)
}

function isImage(name) {
  var cut = String(name).lastIndexOf(".")
  return cut > 0 && IMAGE[String(name).slice(cut + 1).toLowerCase()] === 1
}

// Normalize text files to a trailing newline on save.
function endLine(t) {
  t = String(t || "")
  return t && !/\n$/.test(t) ? t + "\n" : t
}

function looksBinary(text) {
  return String(text || "").slice(0, 1024).indexOf("\u0000") !== -1
}

// Validate bytes because decoded U+FFFD may be real text or a replacement.
function isUtf8(data) {
  // Empty FileView buffers cannot be wrapped by Uint8Array.
  if (!data || !data.byteLength) return true
  var bytes = new Uint8Array(data)
  for (var i = 0; i < bytes.length; i++) {
    var c = bytes[i]
    if (c < 0x80) continue
    var n = c >= 0xc2 && c <= 0xdf ? 1
          : c >= 0xe0 && c <= 0xef ? 2
          : c >= 0xf0 && c <= 0xf4 ? 3 : 0
    if (!n || i + n >= bytes.length) return false
    var value = c & (0x7f >> (n + 1))
    for (var j = 0; j < n; j++) {
      var next = bytes[++i]
      if ((next & 0xc0) !== 0x80) return false
      value = (value << 6) | (next & 0x3f)
    }
    if (value < (n === 1 ? 0x80 : n === 2 ? 0x800 : 0x10000)
        || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return false
  }
  return true
}

// Bound Text rendering cost for large files. Highlighted markup breaks its lines with <br>.
function head(text, lines, br) {
  var t = String(text || ""), b = br || "\n"
  var end = -b.length
  for (var i = 0; i < lines; i++) {
    end = t.indexOf(b, end + b.length)
    if (end === -1) return t
  }
  return end === t.length - b.length ? t : t.slice(0, Math.max(0, end)) + b + "…"
}

var DIR_GLYPH = "\udb80\ude4b"
var FILE_GLYPH = "\udb80\ude14"

// Fill folder previews down, then across, within the pane's character budget.
var GUTTER = 4
var MIN_COL = 38
var SIZE_COL = 5
var DATE_COL = 9

// How many rows each folder-preview column holds, and how many characters wide it is.
function shape(n, rows, paneChars) {
  var wanted = Math.ceil(n / rows)
  var fits = Math.floor((paneChars + GUTTER) / (MIN_COL + GUTTER))
  var cols = Math.max(1, Math.min(wanted, fits))
  // Balance columns rather than leaving a short final column.
  return [Math.ceil(n / cols), Math.floor((paneChars - GUTTER * (cols - 1)) / cols)]
}

// Where a folder holds changes, each row keeps room after its name for markColumns() to fill.
function columns(entries, rows, paneChars, limit, marks) {
  var n = Math.min(entries.length, limit), cut = shape(n, rows, paneChars)
  var marked = !!marks && Object.keys(marks).length > 0
  var out = []
  for (var i = 0; i < n; i += cut[0]) {
    var col = []
    for (var j = i; j < Math.min(i + cut[0], n); j++) col.push(row(entries[j], cut[1], marked))
    out.push(col.join("\n"))
  }
  if (entries.length > n) out[out.length - 1] += "\n\u2026"
  return out
}

// git's letter or dot in the room each row of columns() keeps for it, counted from just past
// the row's glyph; the preview draws these over the rows in another colour.
function markColumns(entries, rows, paneChars, limit, marks) {
  var n = Math.min(entries.length, limit), cut = shape(n, rows, paneChars), out = []
  var skip = pad("", 2 + nameColumn(cut[1], true) + 1)
  for (var i = 0; i < n; i += cut[0])
    out.push(entries.slice(i, Math.min(i + cut[0], n))
             .map(function (e) { return marks[e.name] ? skip + marks[e.name] : "" }).join("\n"))
  return out
}

function nameColumn(width, marked) {
  return Math.max(8, width - 3 - SIZE_COL - 2 - DATE_COL - (marked ? 2 : 0))
}

function row(e, width, marked) {
  var nameCol = nameColumn(width, marked)
  return (e.isDir ? DIR_GLYPH : FILE_GLYPH) + "  "
       + pad(clip(e.name, nameCol), nameCol) + (marked ? "  " : "")
       + lead(e.isDir ? "" : humanSize(e.size), SIZE_COL) + "  "
       + lead(stamp(e.modified), DATE_COL)
}

function clip(name, cap) {
  var t = String(name)
  return t.length > cap ? t.slice(0, cap - 1) + "\u2026" : t
}

function pad(s, n) { var t = String(s); while (t.length < n) t += " "; return t }
function lead(s, n) { var t = String(s); while (t.length < n) t = " " + t; return t }

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function stamp(when) {
  if (!when) return ""
  var d = new Date(when)
  if (isNaN(d.getTime())) return ""
  return lead(d.getDate(), 2) + " " + MONTHS[d.getMonth()] + " "
       + String(d.getFullYear()).slice(2)
}

function numbers(text) {
  var t = String(text || "")
  if (!t.length) return ""
  var n = t.split("\n").length
  var out = []
  for (var i = 1; i <= n; i++) out.push(i)
  return out.join("\n")
}
