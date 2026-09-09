# The files browser

A keyboard-driven directory browser, reached by typing `files` into the wheel.

Two columns on one card: the directory on the left, what the selection *is* on
the right. It answers where is it, what is in it, and open it — which is what a
file manager actually gets reached for.

    plugins/xpo.files/
      manifest.json     kind: "overlay", keepLoaded
      Files.qml         state, keys, file operations, the surface itself
      FilesHeader.qml   breadcrumb, path entry, filter and rename field
      FilesList.qml     the directory, one row per entry
      FilesPreview.qml  the scroller, and the editor inside it
      FilesHints.qml    the foot: the legend, and what a held file would do
      FilesIndex.js     snapshotting, filtering, path and text helpers

Each component takes the panel as `panel` rather than reaching for a parent, so
its one dependency is visible at the call site. `FilesPreview` owns its
scrolling and its editor and exposes verbs — `scrollBy`, `keepPlace`,
`copy` — rather than letting the panel reach into a `Flickable`.

It answers where is it, what is in it, and open it — and then the things you
reach for once you are already looking at the file: edit it
([`Ctrl+E`](#editing)), move or copy it, [rename](#moving-files) it, [make
one](#moving-files) beside it, copy its path, throw it away. Each earns its place
the same way: you are looking at the thing, and acting on it should not cost you
a terminal.

Every one that writes can cost you data when it is wrong, so none of them are
quiet. Nothing is overwritten, a delete goes to the trash and is asked twice in
red, and a save is confirmed by reading the file back. There is still no undo
beyond the trash; `yazi` is installed and does the rest properly.

## Keys

| | |
|---|---|
| type anything | filter the current directory by name |
| `/` or `~` | switch the field to a path — see [Path entry](#path-entry) |
| `↑` `↓` `Tab` `Shift+Tab` `Ctrl+N` `Ctrl+P` | move the selection, wrapping at both ends |
| `→` `Enter` | descend into a folder, or hand a file to the app that owns it |
| `←` | go up one directory |
| `Backspace` | delete a character, then go up one directory |
| `Home` `End` | the first and last row |
| `PageUp` `PageDown` | a page of rows, one kept for orientation |
| `Shift+↑` `Shift+↓` | scroll the preview three lines |
| `Shift+PageUp` `Shift+PageDown` | scroll the preview a page |
| `Shift+←` `Shift+→` | pan the preview sideways, for lines past the edge |
| `Shift+Home` `Shift+End` | the top and the bottom of the preview |
| `Ctrl+E` | edit the previewed file — see [Editing](#editing) |
| `Ctrl+X` `Ctrl+C` | take the selection to move or to copy — see [Moving files](#moving-files) |
| `Ctrl+V` | place it in the directory you are standing in |
| `F2` | rename the selection — see [Moving files](#moving-files) |
| `Ctrl+Shift+N` | make a file or a folder here — the name says which, see [Moving files](#moving-files) |
| `Del` | trash the selection, asked twice |
| `Ctrl+Y` | copy the selection's path to the clipboard |
| `Ctrl+O` | order by name, then newest, then largest — see [Ordering](#ordering) |
| `Ctrl+H` | show hidden files |
| `Ctrl+U` | clear the field |
| `Ctrl+W` `Ctrl+Backspace` | back one word of the filter, or one segment of a typed path |
| `Esc` | clear the field, then close |

Shift is the one modifier that means "the other pane", and it is the whole
rule: every bare key drives the list, every shifted one drives the preview.
`Home` is the first row rather than the home directory, because `~` already
opens path entry sitting there and is the character that says so.

The mouse works too — hover selects, click opens, a click outside the card
closes it, and the wheel scrolls whichever pane is under the pointer.

## Home is the floor

The browser opens at `$HOME` every time and cannot be navigated above it.
`FilesIndex.within()` is applied on every path change — arrow navigation, `←`,
`Backspace`, and typed paths alike — and anything resolving outside home
resolves *to* home rather than being refused. There is no state the panel can
be left holding that it cannot get out of.

It tests `home + "/"` rather than a bare prefix, because `/home/xpo2` starts
with `/home/xpo` and is not inside it.

It does not remember where you were. A remembered directory is only valid until
something moves, renames, unmounts or deletes it, and then the panel opens onto
a path that no longer exists and shows an empty list with no hint of why. Home
is the one directory that is always there. A caller passes
`{"dir": "...", "select": "..."}` instead, which is how the wheel hands a file
over: the browser opens where the file lives with the file selected, so its
preview is up before you have touched a key.

## Path entry

A leading `/` or `~` turns the field from a name filter into a path. The
directory being listed becomes whatever complete directory you have typed so
far, and the tail you are still typing filters it — so the list *completes* the
path as you write it, and `Enter` descends into what it found.

Both prefixes mean the same place, because home is the only root this panel
has: `/xpo/omarchy-custom` and `~/xpo/omarchy-custom` are the same path. A
leading slash is how you say "from the top", and the top here is `$HOME`.

This is what makes the jail liveable. The original worry about a floor was that
`Backspace` could walk you somewhere with no way back; typing a path *is* the
way back, and `Home` is the other one.

**A typed path is written into the trail, not beside it.** The breadcrumb
already *is* the directory being listed, so the tail still being typed is drawn
as the next segment of it — accent-coloured, with the caret at its end — and the
filter chip stays behind for plain name filters. Showing both put the whole path
on the header twice, once walked and once typed, and two spellings of the same
place read as two places. The count reads off the same tail (`root.query`), so
`/Projects/` says `10 items` rather than `10 of 10`.

## Ordering

Folders first and then alphabetically, until `Ctrl+O` asks for something else:
**newest** first, then **largest** first, then back to name. The listing already
prints a size and a date beside every name, and a browser that cannot order by
them is asking you to read the rows. The header says which one you are in, and
the order stays with the panel — it is a way of looking, not a place, so unlike
a remembered directory it cannot go stale.

Where the filter landed only ranks under **name**: once you have asked for
newest first, a prefix match jumping the queue is the sort lying about itself.
Folders are never ordered by size, which for a directory counts the block its
entries are listed in rather than anything inside it.

## The two columns

Both columns are sized in **characters of the font they render**, not in
fractions of the display:

    listWidth     34 characters + icon + row padding
    previewWidth  100 characters
    card width    the sum of those, plus gaps, capped at 92% of the screen

A percentage-based split gives the preview a wider box than any line of code
will fill, and the void on its right is width nobody asked for. A name is about
so many letters long and a line of code is about so many columns wide; those
are the units, so those are what the layout is written in. `TextMetrics`
measures the real advance width of the real font, so this holds under any
`[font] size` or family the theme sets.

The card carries **one ground colour**. The two columns are told apart by the
space between them and the rule under their headings — not by a second fill or
a second frame, which turn a card into two cards and make the preview look like
a window dropped inside this one.

The header is one line: the path as a breadcrumb trail with the leaf at full
strength and the trail behind it dimmed, then whatever is narrowing the list,
then the count, all flowing left. The preview's own heading — name, size, the
pixel dimensions if it is an image, date — right-aligns on the same line. The
count sits with the path rather than at the far edge because right-aligned it
stacked directly above the preview's size and date, and two dim figures in a
column read as two facts about one file.

The foot of the card carries the keys, centred, in key-and-word pairs: the key
lit, the verb whispered. Weight is what separates them, not the run of spaces
that used to — six phrases at one size and one opacity read as a list you have
to parse to find the pairs. A hairline above it makes the row a band rather than
text floating in the padding.

## The preview

Four kinds of thing, one scroller:

| selection | shown as |
|---|---|
| a folder | its contents as a listing — name, size, date — capped at 400 entries |
| an image | itself, aspect-fit, async, formats Qt actually has plugins for |
| a `.md` file | rendered Markdown — headings, bold, code blocks |
| any other text | the first 500 lines, syntax highlighted, with line numbers |
| anything else | its size and `no preview` |

The first four are read-only renderings. `Ctrl+E` replaces the fourth with the
file itself — see [Editing](#editing).

A folder previews in the same scroller a file does, rather than in a second
`ListView` with its own delegate and its own way of being navigated. Its rows
are set the way the browser's own rows are — name at the left, size and date out
at the right edge — and filled down the pane and then across it: `dirRows` is how
many lines the pane is tall, `dirPaneChars` how many characters wide, so eight
files spread their facts across the full width and forty break into two columns.
A bare column of names left seven eighths of a pane as wide as a file of code
empty, and the answer was not a narrower pane.

Both panes start at the same height. A line of text sits at the top of its line
box while a list row sits in the middle of a taller one, so without `dirTopPad`
the first file in the preview floats above the first file in the list.

The preview follows the selection only once it has **stopped moving** — 60 ms,
the same wait the highlighter takes. Held-down arrows through forty files used
to read, slice and lay out every file passed over, about half a second of CPU
spent on frames nobody saw.

Files over **256 KB** are never read. A NUL byte in the first kilobyte is what
marks a binary, rather than an extension list to maintain: `.frag` and `.qsb`
sit either side of any list you would write by hand, and the bytes do not lie.

Arriving from the wheel while an edit is unsaved does not move: the browser
stays on the file and asks you to save or discard it first.

## Moving files

`Ctrl+X` or `Ctrl+C` takes the selected entry, you walk to another directory,
`Ctrl+V` places it. `F2` renames it where it stands, `Del` puts it in the trash.
The foot names what is held and what `Ctrl+V` would do with it; the heading says
what happened. A move spends its source and the hold is released; a copy keeps
it, so it can be placed again somewhere else.

These are the operations the "browser, not a manager" rule was really about.
They earn the exception on the same grounds editing did: a move between two
directories is what people open a second pane for, and not having it is what
sends you to a terminal.

**Rename types into the filter chip**, which is already a text box with a caret
in it, sitting where the name reads — so a rename needs no second field, only a
different fill, so it cannot be mistaken for a filter narrowing the list. A name
with a `/` in it is refused: that is a move being asked for in the wrong field,
and moving is what `Ctrl+X` is for.

It is a real field, not an append-only one: renaming is mostly changing a few
characters in the middle of a name you already have. `←` `→` `Home` `End` move
the caret, `Backspace` and `Del` cut either side of it, `Ctrl+U` and `Ctrl+K`
cut to the ends, `Ctrl+V` pastes with separators stripped. It opens with the
caret on the stem, before the extension. The chip draws the name in two halves
with the caret between them, so it stands where the next character will go; a
filter is only ever typed at, so its caret is always the trailing one.

**Delete trashes, and asks twice, loudly.** `gio trash` puts the entry in the
freedesktop trash with its original path recorded, so it can be got back — the
difference between a delete you can survive and one you cannot. It is still
asked twice, because it is the one verb here that takes something away.

The question is asked where you are looking. A note in the heading was missed
entirely: the row itself now fills with the theme's urgent colour and the foot
turns urgent and reads `del  again to trash <name>`. Any key that is not the
second `Del` cancels it, and so does moving the selection — a second `Del` can
never land on a row you did not aim it at.

**One process, one contract.** Every write goes through the same `Process` and
the same exit codes: `0` done, `17` the name is taken, anything else failed.
`op` carries what to say about each outcome, so move, copy, rename and delete
share one success path and one failure path rather than three of each.

**Nothing is ever overwritten.** The destination name is tested before the
command runs:

    sh -c '[ -e "$2" ] && exit 17; exec mv -- "$1" "$2"' files <src> <dst>

Paths go as arguments, never spliced into the script, so a name with a space, a
dash or a `$` in it is just a name. `17` is this panel's word for *something is
already called that* and is nothing `mv` or `cp` returns on their own; it comes
back as `a wheel.md is already here` rather than being resolved by inventing a
`(copy)` name — a file manager that renames your file for you is one you cannot
predict. Directories go with `cp -r`, and `mv` refuses to move one into itself
without any help from here.

**`Ctrl+Shift+N` makes one**, into the same chip a rename types into. It is the
one gap the "browser, not a manager" line left that a browser trips over: you
have walked to where the thing belongs, and making it there is the last reason to
open a terminal.

**The name says which of the two it is.** A dot in it is an extension, and an
extension is what a file has — which is how the listing above reads them back
anyway, so there is nothing extra to remember. A trailing mark overrides that
either way, and neither mark can be part of a name in the first place:

    archive         a folder        v1.2/       a folder
    notes.md        a file          Makefile.   a file
    .gitignore      a file          .config/    a folder

A second binding for the second verb would have been a second thing to learn for
a difference the name already spells out. Anything *else* with a `/` in it is
still refused: a slash in the middle is a nested path being asked for in a field
that names one thing.

`mkdir` and `touch` go out through the same script with the verb as an argument,
so both cross the same collision test and come back as the same `17`.

**`Ctrl+Y` copies the selection's path**, through `wl-copy` with the path as an
argument rather than spliced into the script — the discipline the move commands
are written with. It was the one thing the panel could not do with a file it was
showing you: name it to something else.

There is no undo beyond the trash. That stays with `yazi`.

The pasted row arrives on its own: `FolderListModel` watches the directory, so
the paste only has to name what to land on — `pending`, the same mechanism the
wheel uses to hand a file over.

## Editing

`Ctrl+E` turns the preview into a `TextEdit` over the same file, `Ctrl+S`
writes it, `Esc` comes back. It is the only thing in this panel that writes.

| | |
|---|---|
| `Ctrl+E` | edit the previewed file |
| `Ctrl+S` | save |
| `Ctrl+C` `Ctrl+X` `Ctrl+V` `Ctrl+A` | copy, cut, paste, select all |
| `Esc` | back — pressed twice, within 2 s, if there are unsaved changes |

What makes it safe rather than merely possible:

**It is modal, because the keyboard is a filter.** Every printable key in this
panel lands in the search field; nothing can type into a file and into a search
box at once. While `editing`, the whole keyboard goes to the editor and only the
edit verbs are kept. `Keys.priority: Keys.BeforeItem` means the card's handler
sees every key *before* the editor, focused or not — the same thing Omarchy's
own `PanelKeyCatcher` documents — so what makes typing work is that the guard
returns without accepting. The clipboard verbs are spelled out rather than left
to `TextEdit`'s own handling: a panel this modal should not have verbs that only
work by accident. Hover, clicks and the click-outside shield stop moving the
selection for the same reason.

**It edits plain source, not the rendering.** What the preview draws is pygments
HTML or Qt's Markdown; editing a rendering saves the rendering — `<span
class="k">def</span>` into your Python file. So the colour drops away for the
length of the edit, which is also the clearest signal that you are looking at
bytes rather than at a picture of them. The heading says `editing`, `unsaved`,
`saved` or `write failed` in the accent while it lasts.

**It refuses anything it did not read whole.** `head()` cuts a file past 500
lines and marks the cut with `…`; saving that back would delete the rest of the
file. `FileView` holds `fullText` — the file as it is on disk — `previewText` is
the cut *of* it, and `editable` is the identity between them, so a file over 500
lines, over 256 KB, binary, or not valid UTF-8 is not editable -- the bytes are
what get checked, so a file that genuinely contains U+FFFD still edits. Writes
go out `atomicWrites`.
A save is then confirmed by reading the file back, because `FileView` will not
tell you (see [Traps](#traps)), and `endLine()` adds the trailing newline `vim`
would, since a file saved without one is a file `git` calls damaged.

**Your place is kept, as a fraction.** The editor sets its lines at the font's
own leading and the rendered preview does not, so a Markdown file is a wholly
different height in the two modes and the offset cannot be carried across —
`contentY` alone lands you somewhere unrelated in the document, which is what
made an edit at the foot of a file come back to the middle of it. `keepPlace()`
stores the fraction of the way down, `takePlace()` applies it when the scroller
re-measures (at the moment the mode flips, `contentHeight` is still the other
mode's), and the caret lands on the line you were reading.

Closing is refused while there are unsaved changes — `close()` routes to
`leaveEdit()` instead, so a click outside arms the discard rather than throwing
the edit away silently.

### Syntax highlighting

Colour comes from **pygments**, not from a tokeniser written here. One process
per settled selection buys every language it knows, correctly, against a
hand-rolled pass that would get shell quoting wrong on its first day.

    python3 -c <script> <path>     one interpreter, style=one-dark

One interpreter does the lexer lookup and the formatting together. Naming the
lexer with `pygmentize -N` was a second Python start and a shell to pipe them a
third: that cost 239 ms, and this costs 105 ms. A 60 ms debounce means arrowing
through a directory does not spawn a process per row.

**The uncoloured file travels through the same `<pre>` the coloured one does.**
Qt collapses runs of spaces in rich text, which would flatten every indent, so
the markup is needed either way — but the reason it goes in from the *first*
frame is that swapping a plain-text item for a rich-text one steps the whole
file down the page the instant the highlighter answers. Rendering both states
through one path makes the arrival of colour nothing but a change of colour.
`margin: 0` on the `<pre>` is part of the same fix.

The gutter is generated from `head()`, which appends an ellipsis line when it
truncates. The Python truncates the same way, from the same `previewLines`
property, for the same reason: if the two disagree the numbers stop naming the
lines beside them.

Colour is a nicety, not a dependency. If `python3` or pygments is missing the
process yields nothing and the escaped plain text stays on screen.

### Markdown

Rendered rather than dumped — line numbers and a no-wrap column are right for
code and wrong for prose. Two things have to be done to the source first:

**Links are flattened to their words.** Qt paints Markdown links in a blue of
its own that belongs to no theme on this card and is barely legible on a dark
ground, and `linkColor` does not override what the Markdown importer stamps on
them. A preview pane cannot follow a link anyway.

**Blank lines are given a paragraph to occupy.** Qt's Markdown importer gives a
paragraph *no margins*, so a rendered document arrives as one unbroken slab
whatever line height it is set at — headings included. `airOut()` replaces each
blank line with a paragraph holding a single non-breaking space, which
CommonMark counts as content rather than as more blank. Fenced blocks are left
exactly as written.

## Traps

**`FolderListModel` is snapshotted, not bound.** Qt's model does not apply
`nameFilters` to directories, so a filter typed into it narrows the files and
leaves every folder standing; and it sorts on one field, where a browser wants
folders first *and* the filter's best match first *and* then alphabetical.
`FilesIndex.snapshot()` costs one pass per directory entered and buys both.

**Hover claims the selection on `positionChanged`, never on `entered`.**
Retyping a query re-lays the rows out under a cursor that has not moved, and
`entered` fires on every row that slides beneath it — which drags the selection
around mid-keystroke and leaves you unsure what `Return` will run. Real pointer
motion is the only thing that should claim it. The same reasoning is written out
at length in `Wheel.qml`.

**A change handler can see a stale binding.** `showsCode` is a binding on
`previewText`, and `onPreviewTextChanged` can run *before* that binding
re-evaluates — so asking it there reads the value from before the file loaded,
and the highlighter never starts. Imperative code asks the two conditions
directly; only the declarative bindings use `showsCode`. This cost a debugging
round; it will cost another if the guard is ever "simplified" back.

**The monitor is resolved once, when the panel opens.** Hyprland moves focus
with the pointer, so a live binding would walk the surface onto another monitor
while you are reading it. Matched by name, because this Quickshell's
`HyprlandMonitor` carries no `screen`.

**Opening a file closes the panel only if something is opening.** Whatever
opens wants the keyboard, and the layer surface holds it exclusively until it
unmaps — but a file the desktop has no viewer for opens nothing, and closing the
browser for it would look like the panel had crashed. `omarchy-open-path` is run
as a `Process` and the exit code decides: `0` closes, `3` and `4` stay.

Only one of the two declines needs saying. `3` is a terminal handler, for a file
already open in the pane on the right, where a message would be noise. `4` is
nothing owning it at all, and there the panel says `nothing here opens <name>`:
with no pane covering for it, silence reads as a key that did nothing.

**`FileView` does not tell you whether a write worked.** Neither `saved` nor
`saveFailed` fires for `setText`; a permission failure only prints a warning.
Verified by measurement, not assumption — see [Editing](#editing). A `reload()`
in the same tick as the write is also swallowed, which is what the 150 ms is
for.

**`TextEdit` has no `lineHeight`.** It is a `Text` property, not a
`QQuickTextEdit` one, so an edited file is set at the font's own leading rather
than the preview's 1.75 rhythm, and edit mode is unavoidably denser. The gutter
has to follow it twice over: `ProportionalHeight` *and* the body's font size,
because a font's leading follows its size — under the fixed rhythm the numbers
can be smaller, since there the rhythm is what aligns them, but at natural
leading a smaller gutter drifts off its own lines down the page.

**Reopening where you already are announces nothing.** `enter()` sets the same
`dir`, `FolderListModel` reloads nothing, `rows` is the same array — so
`onRowsChanged` never fires and `claimPending()` is never reached, leaving the
selection on row 0 instead of on the file the wheel named. `sel` has not changed
either, so `settle` never restarts and `settledSel` — dropped on close — stays
null, which the preview renders as `Empty` over a file sitting right there. So
`open()` calls `claimPending()` directly and restarts the settle. The name is
cleared only once found, or by `enter()` — walking somewhere yourself abandons
it — so the direct call cannot discard it a frame before its rows arrive.

**The scroller's content height is not the content's height.** Both panes sit
`dirTopPad` down the Flickable so the first line aligns with the first list row.
Counting only `content.height` leaves that offset unreachable, so the last line
of a file is clipped by the bottom edge — on the file you scrolled to the bottom
to read. It is counted twice, which also gives the closing line the air the
opening one stands in.

**Raw HTML in a Markdown file eats the rest of the document.** Qt's importer
hands anything tag-shaped to a sub-parser, and an unclosed tag swallows every
block after it — only code spans come through, because those arrive as their own
typed spans rather than as text. One `<dir>` written inside a sentence in
`docs/wheel.md` cut the preview from 17907 rendered characters to 7477, and the
tail of the file read as a column of empty bullets. `escapeTags()` escapes every
angle bracket outside code, so a tag is shown as it was written; code spans and
fenced and indented blocks are left alone, where `&lt;` would be four literal
characters rather than one.

**Both `FolderListModel` handlers are gated on `Ready`.** A load raises `count`
on its way to `Ready`, so ungated the model was snapshotted twice per directory
and flashed empty in between. `onCountChanged` is still needed for a file
appearing under an open panel, which raises `count` with the model already
`Ready`.

## Wiring

`install.sh` does both halves — it links every `plugins/*/` into
`~/.config/omarchy/plugins/`, registers the id in `shell.json`, and puts the
opener on `PATH`:

    ln -s ~/xpo/omarchy-custom/plugins/xpo.files ~/.config/omarchy/plugins/
    ln -s ~/xpo/omarchy-custom/bin/omarchy-open-path ~/.local/bin/

`bin/omarchy-open-path` is on `PATH` because a plugin directory is private to
its owner. It routes by handler rather than calling `xdg-open` blindly:
`text/plain` resolves to `nvim.desktop` here, and `xdg-open` launches that with
no terminal attached, so nvim hangs invisibly and `Enter` looks like it did
nothing.

Nothing here opens an editor. A terminal handler, or no handler at all, is a
decline — the script exits `3`, and the browser keeps its place, because the
file it is being asked about is already open in the preview pane. An image, a
PDF, a video goes to `xdg-open`, and a zero exit is what tells the browser to
step aside for it.

The wheel no longer calls the script at all: a path picked out of `/` mode
opens this browser instead, standing in the directory the path lives in with
the path itself selected (`MenuIndex.pathPayload`).

The wheel registers it in `MenuIndex.js` as an `EXTRAS` entry — searchable
without consuming a ring slice, so the default ring keeps the even count that
fills 3 and 9 o'clock. Being a slice rather than an app is what puts it above
GNOME Files, whose entry is also called "Files". `Wheel.qml` lists `xpo.files`
among the surfaces `closeAll` sweeps, so `SUPER+W` closes it instead of falling
through to `killactive`.

Blur needs a layer rule in `~/.config/hypr/looknfeel.lua`, matching namespace
`omarchy-files`. Without it the surface gets no blur at all and the sharp
desktop reads straight through the scrim.

Editing the plugin needs `omarchy-restart-shell` — QML components are cached, so
`rescanPlugins` alone will not reload changed code.

## Known limits

- **Colour lands a beat after the text.** ~165 ms of debounce plus interpreter
  start on every selection. There is no jump any more, but there is a wait.
  Caching the last few results, or keeping one Python process alive to serve
  requests, would be the next step.
- Markdown is rendered by Qt, and Qt's importer is lossy: an indented code block
  keeps its indentation but not its distinction from surrounding prose, and a
  table's cells arrive with nothing between them, so a row reads as one run-on
  word. Tables are the worst thing this preview renders.
- The line-number gutter counts the lines of the *source*. A wrapped Markdown
  paragraph has no numbers at all, by design; a code file never wraps, so the
  two agree.
- No undo for a move, a copy, a rename or a new file — only a delete can be
  taken back, out of the trash. Use `yazi` for the rest.
- An image's pixel size comes from `identify`. Colour and dimensions are both
  niceties rather than dependencies: without ImageMagick there are no numbers,
  and the size and the date still stand.
- **Only files the preview read whole are editable** — at most 500 lines and
  256 KiB, valid UTF-8, not binary. Other encodings remain preview-only.
- Only the first 500 lines of a file are ever shown, and only the first 400
  entries of a previewed folder.
- **Opening the browser from the wheel flashes.** The wheel unmaps before this
  surface maps, and for a frame or two the desktop shows through unblurred.
  Fixing it was attempted twice and both fixes were worse: fading the wheel out
  over the browser stacks two blurred scrims (measured: 14% darker, half the
  contrast, for the length of the fade), and handing over on a handshake moved
  the artifact rather than removing it. Reverted; the flash stands.
