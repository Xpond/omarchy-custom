.pragma library

// Snapshot because FolderListModel cannot filter directories and rank matches.
function snapshot(model) {
  var out = []
  for (var i = 0; i < model.count; i++) {
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

// Keep directories first; prefix rank applies only to name ordering.
function filtered(entries, query, order) {
  var q = String(query || "").trim().toLowerCase()
  var hits = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    var at = q ? e.name.toLowerCase().indexOf(q) : 0
    if (at === -1) continue
    hits.push({ entry: e, rank: at === 0 ? 0 : 1 })
  }
  hits.sort(function (a, b) {
    if (a.entry.isDir !== b.entry.isDir) return a.entry.isDir ? -1 : 1
    var byName = a.entry.name.localeCompare(b.entry.name)
    if (order === "date") return when(b.entry.modified) - when(a.entry.modified) || byName
    // Folder metadata size does not represent its contents.
    if (order === "size" && !a.entry.isDir) return b.entry.size - a.entry.size || byName
    return a.rank - b.rank || byName
  })
  var out = []
  for (var j = 0; j < hits.length; j++) out.push(hits[j].entry)
  return out
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

function countLabel(shown, total, query, hidden, order) {
  var s = String(query || "").length
    ? shown + " of " + total
    : shown + (shown === 1 ? " item" : " items")
  if (hidden) s += "  ·  hidden"
  var word = ORDER_WORDS[order || "name"]
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

// <pre> preserves indentation; rich text does not inherit the item's font.
function codeHtml(html, family, px) {
  // Remove the default margin so highlighting does not shift the preview.
  return '<pre style="margin:0; font-family:\'' + family + '\'; font-size:' + px + 'px">'
       + String(html || "") + '</pre>'
}

// Keep unhighlighted text in the same rich-text layout.
function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
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

// Bound Text rendering cost for large files.
function head(text, lines) {
  var parts = String(text || "").split("\n")
  var count = parts.length - (parts[parts.length - 1] === "" ? 1 : 0)
  if (count <= lines) return String(text || "")
  return parts.slice(0, lines).join("\n") + "\n…"
}

var DIR_GLYPH = "\udb80\ude4b"
var FILE_GLYPH = "\udb80\ude14"

// Fill folder previews down, then across, within the pane's character budget.
var GUTTER = 4
var MIN_COL = 38
var SIZE_COL = 5
var DATE_COL = 9

function columns(entries, rows, paneChars, limit) {
  var n = Math.min(entries.length, limit)
  var wanted = Math.ceil(n / Math.max(1, rows))
  var fits = Math.floor((paneChars + GUTTER) / (MIN_COL + GUTTER))
  var cols = Math.max(1, Math.min(wanted, Math.max(1, fits)))
  // Balance columns rather than leaving a short final column.
  var per = Math.ceil(n / cols)
  var width = Math.floor((paneChars - GUTTER * (cols - 1)) / cols)
  var out = []
  for (var i = 0; i < n; i += per) {
    var col = []
    for (var j = i; j < Math.min(i + per, n); j++) col.push(row(entries[j], width))
    out.push(col.join("\n"))
  }
  if (entries.length > n && out.length) out[out.length - 1] += "\n\u2026"
  return out
}

function row(e, width) {
  var nameCol = Math.max(8, width - 3 - SIZE_COL - 2 - DATE_COL)
  return (e.isDir ? DIR_GLYPH : FILE_GLYPH) + "  "
       + pad(clip(e.name, nameCol), nameCol)
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
