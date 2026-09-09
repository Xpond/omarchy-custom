.pragma library

// One plain row per directory entry, snapshotted out of FolderListModel rather
// than bound to it. Two reasons, both of which a browser lives or dies on:
// Qt's model does not apply `nameFilters` to directories, so a filter typed
// into it narrows the files and leaves every folder standing; and it sorts on
// one field, where a browser wants folders first AND the filter's best match
// first AND then alphabetical. Snapshotting costs one pass per directory
// entered, and buys both.
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

// Directories first, then where the filter landed -- the front of a name beats
// its middle -- then alphabetically. The same instincts the wheel's own search
// has, for the same reason: what you typed the start of is what you meant.
//
// `order` asks for something else: newest or biggest at the top. Where the
// filter landed only ranks under "name" -- once you have asked for newest
// first, a prefix match jumping the queue is the sort lying about itself.
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
    // A directory's size is the block its entries are listed in, not what is
    // inside it, so ordering folders by it sorts on nothing at all.
    if (order === "size" && !a.entry.isDir) return b.entry.size - a.entry.size || byName
    return a.rank - b.rank || byName
  })
  var out = []
  for (var j = 0; j < hits.length; j++) out.push(hits[j].entry)
  return out
}

// The three the listing already prints, cycled in that order. Name is the
// default and goes unnamed in the header: a label for "as it has always been"
// is a word to read every time.
var ORDERS = ["name", "date", "size"]
var ORDER_WORDS = { name: "", date: "newest", size: "largest" }

function nextOrder(order) {
  return ORDERS[(ORDERS.indexOf(order) + 1) % ORDERS.length]
}

function when(modified) {
  return (modified && new Date(modified).getTime()) || 0
}

// The directory above, stopping at the root rather than walking off it.
function parentOf(dir) {
  var d = String(dir || "")
  if (d.length <= 1) return "/"
  var cut = d.lastIndexOf("/")
  return cut <= 0 ? "/" : d.slice(0, cut)
}

// Home is the floor, for navigating and for typing alike. Everything this shell
// does with files is rooted there -- the wheel's own `/` mode scans $HOME and
// nothing above it. A path outside home resolves TO home rather than being
// refused, so there is no state the panel can be left pointing at that it
// cannot get out of.
//
// The `home + "/"` test rather than a bare prefix: "/home/xpo2" starts with
// "/home/xpo" and is not inside it.
function within(dir, home) {
  var d = String(dir || "")
  return (d === home || d.indexOf(home + "/") === 0) ? d : home
}

// Shown the way you would type it.
function display(dir, home) {
  var d = String(dir || "")
  return d.indexOf(home) === 0 ? "~" + d.slice(home.length) : d
}

// The path as separate words, so the header can light the directory you are in
// and leave the trail behind it at a whisper. One line of text all at the same
// weight is a string; a trail with its leaf lit is a place.
function crumbs(dir, home) {
  var parts = display(dir, home).split("/")
  var out = []
  for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
  if (!out.length) return ["/"]
  // A trail long enough to push the count off the header is no longer a trail.
  // The root and the last three are the two ends anyone reads.
  if (out.length > 5) out = [out[0], "\u2026"].concat(out.slice(-3))
  return out
}

// "3 of 41" while a filter is narrowing, plain counts otherwise. A bare number
// in the corner is a riddle; the noun is what makes it a fact.
function countLabel(shown, total, query, hidden, order) {
  var s = String(query || "").length
    ? shown + " of " + total
    : shown + (shown === 1 ? " item" : " items")
  if (hidden) s += "  ·  hidden"
  var word = ORDER_WORDS[order || "name"]
  return word ? s + "  ·  " + word : s
}

// Sizes read at a glance, not to the byte: a browser is answering "which of
// these two", and 1.2M answers that where 1258291 does not.
function humanSize(bytes) {
  var units = ["B", "K", "M", "G", "T"]
  var n = Number(bytes) || 0
  var u = 0
  while (n >= 1024 && u < units.length - 1) { n /= 1024; u++ }
  return (u === 0 ? n : n.toFixed(n < 10 ? 1 : 0)) + units[u]
}

// What Qt can actually decode here. png and bmp are built into QtGui; the rest
// come from plugins in qt6/plugins/imageformats. avif is deliberately absent --
// there is no libqavif.so on this machine, and claiming a format Qt cannot read
// buys a blank pane instead of a preview.
var IMAGE = { png: 1, jpg: 1, jpeg: 1, gif: 1, webp: 1, bmp: 1,
              svg: 1, ico: 1, icns: 1, tif: 1, tiff: 1, tga: 1 }

// pygments hands back coloured spans and nothing else. Qt collapses runs of
// spaces in rich text, which would flatten every indent in the file, so the
// whole thing goes inside a <pre> carrying the font the plain path would have
// used -- rich text does not inherit the item's font.
function codeHtml(html, family, px) {
  // margin:0 matters: <pre> carries one by default, and the plain text shown
  // while the highlighter runs has none -- so without this the whole file
  // steps down the page the instant the colour arrives.
  return '<pre style="margin:0; font-family:\'' + family + '\'; font-size:' + px + 'px">'
       + String(html || "") + '</pre>'
}

// The uncoloured file has to travel through the same <pre> the coloured one
// does. Swapping a plain-text item for a rich-text one steps the whole file
// down the page when the highlighter answers, however carefully the margins
// are matched; going in as markup from the start makes the arrival of colour
// nothing but a change of colour.
function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// A preview pane cannot follow a link, so a link is only its words here. Qt
// paints Markdown links in a blue of its own that belongs to no theme on this
// card and is barely legible on a dark ground, and `linkColor` does not
// override what the Markdown importer stamps on them.
function flattenLinks(text) {
  return String(text || "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
}

// Qt's Markdown importer hands raw HTML to a sub-parser, and an unclosed tag
// swallows every block after it -- one `<dir>` written inside a sentence in
// docs/wheel.md rendered 7477 characters of 17907. Only code spans survived,
// arriving as their own typed spans rather than as text. So every angle bracket
// outside code is escaped and shown as written; inside code it is left alone,
// where `&lt;` would be four literal characters.
function escapeTags(md) {
  var lines = String(md || "").split("\n")
  var fenced = false
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*(```|~~~)/.test(lines[i])) { fenced = !fenced; continue }
    if (fenced || /^(\t| {4})/.test(lines[i])) continue
    // Odd members of the split are the code spans that produced it.
    lines[i] = lines[i].split(/(`+[^`]*`+)/).map(function (part, n) {
      return n % 2 ? part : part.replace(/</g, "&lt;")
    }).join("")
  }
  return lines.join("\n")
}

// Qt's Markdown importer gives a paragraph no margins, so a rendered document
// arrives as one unbroken slab whatever line height it is set at -- headings
// included. The blank lines that separated the blocks in the source are the
// separation, so each one is given a paragraph of its own to occupy: a line
// holding a single non-breaking space, which CommonMark counts as content
// rather than as more blank. Fenced blocks are left exactly as written.
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

// Qt renders these itself; everything else text-shaped is shown as it is.
function isMarkdown(name) {
  var n = String(name).toLowerCase()
  return /\.(md|markdown|mdown|mkd)$/.test(n)
}

function isImage(name) {
  var cut = String(name).lastIndexOf(".")
  return cut > 0 && IMAGE[String(name).slice(cut + 1).toLowerCase()] === 1
}

// A NUL byte in the first kilobyte is what separates a binary from a text file
// without an extension list to maintain. `.frag` and `.qsb` sit either side of
// any list you would write by hand, and the bytes do not lie about which.
// A text file ends with a newline. vim fixes this silently on write and so
// does the editor; git calls a file without one damaged.
function endLine(t) {
  t = String(t || "")
  return t && !/\n$/.test(t) ? t + "\n" : t
}

function looksBinary(text) {
  return String(text || "").slice(0, 1024).indexOf("\u0000") !== -1
}

// Validate the bytes, not decoded U+FFFD: a replacement character can be real
// text, while Qt also inserts it for invalid UTF-8 anywhere in the file.
function isUtf8(data) {
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

// A preview is a glance -- but a scrollable one now, so it can afford rather
// more than the screenful it used to be cut to. Rendering a 40,000-line file
// into a Text item to show the top of it still costs the frame it is drawn on.
function head(text, lines) {
  var parts = String(text || "").split("\n")
  var count = parts.length - (parts[parts.length - 1] === "" ? 1 : 0)
  if (count <= lines) return String(text || "")
  return parts.slice(0, lines).join("\n") + "\n…"
}

// A folder previews in the same scroller a file does, rather than as a second
// list carrying its own delegate and its own way of being navigated.
var DIR_GLYPH = "\udb80\ude4b"
var FILE_GLYPH = "\udb80\ude14"

// A directory listing set the way the browser's own rows are set: name at the
// left, size and date out at the right edge. A bare column of names left seven
// eighths of a pane as wide as a file of code empty, and the answer is not a
// narrower pane but a listing that says as much about what is inside as the
// list on the left says about where you are.
//
// Filled down the pane and then across it, cut to the pane rather than to a
// number picked here: `rows` is how many lines it is tall, `paneChars` how many
// characters wide. Eight files spread their facts across the whole width; forty
// break into two columns and spread across half of it each.
var GUTTER = 4
var MIN_COL = 38
var SIZE_COL = 5
var DATE_COL = 9

function columns(entries, rows, paneChars, limit) {
  var n = Math.min(entries.length, limit)
  var wanted = Math.ceil(n / Math.max(1, rows))
  var fits = Math.floor((paneChars + GUTTER) / (MIN_COL + GUTTER))
  var cols = Math.max(1, Math.min(wanted, Math.max(1, fits)))
  // Balanced rather than filled to the brim: two columns of twenty read as one
  // listing, where twenty-seven and thirteen read as a listing and a remainder.
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

// Long names are cut rather than allowed to set the width of the column they
// are in: one 90-character name would otherwise push the size and the date of
// every other entry out of line with it.
function clip(name, cap) {
  var t = String(name)
  return t.length > cap ? t.slice(0, cap - 1) + "\u2026" : t
}

function pad(s, n) { var t = String(s); while (t.length < n) t += " "; return t }
function lead(s, n) { var t = String(s); while (t.length < n) t = " " + t; return t }

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Short enough to sit in a column: the year in two digits, because a file
// browser is answering "which of these is the recent one".
function stamp(when) {
  if (!when) return ""
  var d = new Date(when)
  if (isNaN(d.getTime())) return ""
  return lead(d.getDate(), 2) + " " + MONTHS[d.getMonth()] + " "
       + String(d.getFullYear()).slice(2)
}

// The gutter beside a text preview. Line numbers are what turn a wall of
// characters into a file you can point at.
function numbers(text) {
  var t = String(text || "")
  if (!t.length) return ""
  var n = t.split("\n").length
  var out = []
  for (var i = 1; i <= n; i++) out.push(i)
  return out.join("\n")
}
