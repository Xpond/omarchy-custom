# The files browser

A keyboard-driven directory browser, reached by typing `files` into the wheel.

Two columns on one card: the directory on the left, what the selection *is* on
the right.

    plugins/xpo.files/
      manifest.json     kind: "overlay", keepLoaded
      Files.qml         state, derivation, and both surfaces
      FilesOps.qml      everything that writes: one process, one contract
      FilesHeader.qml   breadcrumb, path entry, filter and rename field
      FilesList.qml     the directory, one row per entry
      FilesPreview.qml  the scroller, and the editor inside it
      FilesHints.qml    the foot: the legend, and what a held file would do
      FilesIndex.js     snapshotting, filtering, path and text helpers
      FilesKeys.js      the key map: which verb a key means

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
red, and a save is confirmed by reading the file back.

## Keys

| | |
|---|---|
| type anything | filter the current directory by name |
| `/` or `~` | switch the field to a path from here or from home — see [Path entry](#path-entry) |
| `↑` `↓` `Tab` `Shift+Tab` `Ctrl+N` `Ctrl+P` | move the selection, wrapping at both ends |
| `Enter` | descend into a folder, or hand a file to the app that owns it, text to your editor |
| `→` | descend into a folder; on a file it does nothing |
| `←` | go up one directory, landing on the folder you left |
| `Backspace` | delete a character, then go up one directory, then back to the wheel |
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
| `Ctrl+Enter` | open a terminal in the directory you are in |
| `Ctrl+O` | order by name, then newest, then largest — see [Ordering](#ordering) |
| `Ctrl+H` | show hidden files |
| `Ctrl+U` | clear the field |
| `Ctrl+W` `Ctrl+Backspace` | back one word of the filter, or one segment of a typed path |
| `Ctrl+T` | pop out into a window, and back — see [Popping out](#popping-out) |
| `Ctrl+B` | slide the list out so the preview takes its width, and back |
| `Ctrl+D` | show a changed file's diff instead of its contents, and back — see [Uncommitted changes](#uncommitted-changes) |
| `F1` | show every key in the legend, or only the everyday ones |
| `Esc` | clear the field, then close |

Shift is the one modifier that means "the other pane", and while the list is
shown it is the whole rule: every bare key drives the list, every shifted one
drives the preview.
`Home` is the first row rather than the home directory, because `~` already
opens path entry sitting there and is the character that says so.

`Ctrl+B` slides the list out to the left and the preview takes the width. With
the list hidden the preview is the view, so the bare keys act as shifted ones —
`↑` `↓`, the page keys and `Home` `End` scroll it — and `←`, or `Backspace` with
nothing left to delete, brings the list back rather than going up. The preview slides along at its old width and widens only
once the list is out: reflowing a Markdown table every frame of the slide would
stutter. The choice holds across the overlay and its windows while the shell runs.

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

`~` starts from home. `/` starts from the folder you are in: typed in
`~/xpo/omarchy-custom/docs` it writes `/xpo/omarchy-custom/docs/` into the
field, so the list stays put, `Ctrl+W` climbs a segment and typing goes deeper.
Both are rooted at `$HOME`, the only root this panel has, so
`/xpo/omarchy-custom` and `~/xpo/omarchy-custom` are the same path.

**A typed path is written into the trail, not beside it.** The breadcrumb
already *is* the directory being listed, so the tail still being typed is drawn
as the next segment of it — accent-coloured, with the caret at its end — and the
filter chip stays behind for plain name filters. Showing both put the whole path
on the header twice, once walked and once typed, and two spellings of the same
place read as two places. The count reads off the same tail (`root.query`), so
`/Projects/` says `10 items` rather than `10 of 10`.

## Ordering

Folders first and then alphabetically, until `Ctrl+O` asks for something else:
**newest** first, then **largest** first, then back to name. The header says
which one you are in, and the order stays with the panel — it is a way of looking, not a place, so unlike
a remembered directory it cannot go stale.

Where the filter landed only ranks under **name**: once you have asked for
newest first, a prefix match jumping the queue is the sort lying about itself.
Folders are never ordered by size, which for a directory counts the block its
entries are listed in rather than anything inside it.

## The two columns

Both columns are sized in **characters of the font they render**, not in
fractions of the display:

    listWidth     28 characters + icon + row padding
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
pixel dimensions if it is an image or the line count if it is text, date —
right-aligns on the same line. The
count sits with the path rather than at the far edge because right-aligned it
stacked directly above the preview's size and date, and two dim figures in a
column read as two facts about one file.

The foot of the card carries the keys, centred, in key-and-word pairs: the key
lit, the verb whispered. A hairline above it makes the row a band rather than
text floating in the padding.

## The preview

Four kinds of thing, one scroller:

| selection | shown as |
|---|---|
| a folder | its contents as a listing — name, size, date — capped at 400 entries |
| an image | itself, aspect-fit, async, formats Qt actually has plugins for |
| a `.md` file | rendered Markdown — headings, bold, code blocks |
| any other text | syntax highlighted, with line numbers |
| anything else | its size and `no preview` |

The first four are read-only renderings. `Ctrl+E` replaces the third or fourth with the
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

Only what is near the view is **laid out**. A selection lays out two screens of
lines; scrolling within a screen of their end doubles that, and `End` lays out
the rest first, so the whole file is there to scroll through. The file is still
read whole: reading costs well under a millisecond, and editing needs it.
Laying out is the cost, and a selection in `docs/` now takes 10 to 30 ms.

Files over **256 KB** are never read. A NUL byte in the first kilobyte is what
marks a binary, rather than an extension list to maintain: `.frag` and `.qsb`
sit either side of any list you would write by hand, and the bytes do not lie.

Arriving from the wheel while an edit is unsaved does not move: the browser
stays on the file and asks you to save or discard it first.

## Uncommitted changes

Inside a git repository the list marks what changed since the last commit:
git's own letter on a file — `M` modified, `A` added, `D` deleted, `?`
untracked — and a dot on a folder with changes anywhere under it, so changes
can be followed down from the root. A folder git does not track at all is `?`
as a whole and its preview is unmarked; inside it, each entry has its own mark.
A folder's preview carries the same marks
between each name and its size. The preview is one plain text per column, and
a plain text takes one colour, so the marks are a second text laid over room
the rows keep for them, placed past the row's glyph by its measured width. A
changed file's heading leads with how many lines it adds and removes,
`+11 −2  ·  name`, set off by the same dot as the facts after the name.

Deleted files remain in the list as read-only rows, below everything that
exists: they arrive with git's status, just after the folder's rows, and so
move no selection already made. Missing parent folders remain navigable too;
Enter on a deleted file shows its diff. These rows cannot be edited, renamed,
copied, moved, or trashed.

`Ctrl+D` shows a changed file's diff in place of its contents — staged and
unstaged, against `HEAD`, coloured in the highlighter's One Dark. git's header
goes, since the heading names the file, and each `@@` becomes a `⋯` break
carrying git's context. git lists a block of removed lines before the lines
that replaced them; instead each old line sits above the most alike new line,
in order, with what changed in bold. Lines sharing under half their length at
their two ends are not alike, and stay plain removals and additions. Pairing
has a fixed work budget; larger blocks keep Git's unified order with every
line intact, so selecting a heavily rewritten file cannot stall on pairing.
The gutter numbers lines as the file now has them, so a removed line has none.
Unchanged files and images keep their usual preview, so the arrows can walk
the list with the diff on. A changed file's preview waits blank for its diff
rather than flash the file, which loads first; an empty diff gives it back.
The choice holds while the shell runs, and while it is on, `ctrl+d hide diff`
is lit in the legend: the browser reopens in the diff, and an unexplained diff
looks like a broken file. `Ctrl+E` edits the file, never the diff.

Untracked files and files in repositories without a first commit compare
against an empty file. A small diff remains readable even when the current
file exceeds the normal 256 KiB content-preview limit.

Marks are read whenever the folder's rows load — which a save also triggers —
and whenever the browser opens; a short debounce combines duplicate requests,
and one status covers the folder previews too. git reports an untracked folder
as one entry instead of walking it, so an unignored `node_modules` costs one
line rather than one per file; the status also names a path inside the listed
folder, which makes git open that folder even when it is untracked. A changed
file's diff is read
when the selection settles, shown or not, so the heading can count it.
`git-preview.py` resolves missing directories through their existing parent
and chooses the comparison baseline. Each request owns its process and
collector; cancelled output cannot update a later selection. Outside a
repository the helper prints nothing.
`node tests/files-index.js` and `node tests/files-git.js` exercise real Git
repositories; `python3 tests/runtime.py` also checks cancellation, deleted
directory navigation, large-file previews, and pairing time in Quickshell.
`--no-optional-locks` keeps a status read off the index lock a commit may
want; `--literal-pathspecs` keeps `a*b` from diffing `axb` too.

## Moving files

`Ctrl+X` or `Ctrl+C` takes the selected entry, you walk to another directory,
`Ctrl+V` places it. `F2` renames it where it stands, `Del` puts it in the trash.
The foot names what is held and what `Ctrl+V` would do with it; the heading says
what happened. A move spends its source and the hold is released; a copy keeps
it, so it can be placed again somewhere else.

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

The question is asked where you are looking: the row itself fills with a fixed
red and the foot turns red and reads `del  again to trash <name>`. Any key that
is not the second `Del` cancels it, and so does moving the selection — a second
`Del` can never land on a row you did not aim it at.

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

**`Ctrl+Shift+N` makes one**, into the same chip a rename types into.

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
are written with.

The pasted row arrives on its own: `FolderListModel` watches the directory, so
the paste only has to name what to land on — `pending`, the same mechanism the
wheel uses to hand a file over.

## Editing

`Ctrl+E` turns the preview into a `TextEdit` over the same file, `Ctrl+S`
writes it, `Esc` comes back.

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
edit verbs are kept. Hover, clicks and the click-outside shield stop moving the
selection for the same reason.

**It edits plain source, not the rendering.** What the preview draws is pygments
markup or Qt's Markdown; editing a rendering saves the rendering — `<font
color="#C678DD">def</font>` into your Python file. So the colour drops away for the
length of the edit, which is also the clearest signal that you are looking at
bytes rather than at a picture of them. The heading says `editing`, `unsaved`,
`saved` or `write failed` while it lasts.

**It edits only what it can write back whole.** `FileView` holds `fullText` —
the file as it is on disk — and the editor takes all of it, never the preview's
lines, so a file of any length edits. A file over 256 KB, binary, or not valid
UTF-8 is not editable -- the bytes are what get checked, so a file that
genuinely contains U+FFFD still edits. Writes go out `atomicWrites`.
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

    python3 highlight.py <path> <lines>     one interpreter, style=one-dark

One interpreter does the lexer lookup and the formatting together. Naming the
lexer with `pygmentize -N` was a second Python start and a shell to pipe them a
third: that cost 239 ms, and this costs 105 ms. A 60 ms debounce means arrowing
through a directory does not spawn a process per row.

**The uncoloured file travels through the same markup the coloured one does.**
Swapping a plain-text item for a marked-up one steps the whole file down the
page the instant the highlighter answers; rendering both states through one
path makes the arrival of colour nothing but a change of colour.

**That markup is StyledText, drawn exactly as a rich-text `<pre>` drew it.**
The `<pre>` held the GUI thread for about 100 ms per 500-line file, twice per
selection; StyledText takes about 11. `styledCode()` and `highlight.py` keep the
`<pre>` rules: no newline straight after the opening tag or before the closing
one, no `\r`, every other whitespace character kept, as entities StyledText
cannot collapse. Rich text put each baseline 4/5 down its fixed-height line
whatever the fonts; StyledText puts it at the line's ascent, so `onLineLaidOut`
moves every line back, measuring with a hidden probe any line that leaves
printable ASCII. NEL goes in as U+0080, another glyphless control, because Qt
reads `&#133;` as an ellipsis. `tests/files-preview.py` holds all of it to the
old rendering pixel for pixel.

`highlight.py` colours the whole file once. The preview shows its first
`shownLines`: the gutter numbers `head()` of the text, and the markup is cut by
the same `head()` at its `<br>`s, appending the same `…` line, for the same
reason: if the two disagree the numbers stop naming the lines beside them.

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

**Markdown has a `Text` of its own.** When one `Text` served both, its line
height switched with the format and it carried the code's per-line handler, and
Qt then laid out Markdown tables many times slower: 100 to 780 ms a selection in
`docs/`. Fixed values and no handler bring the same documents to under 80 ms
even at 500 lines. Do not fold the two back together.

## Popping out

`Ctrl+T` moves the browser out of the overlay into a normal Hyprland window,
keeping the folder, the selection and the preview. Hyprland tiles it beside
whatever else is open, and it moves, floats and pins like any other window. The
overlay goes, and the dimmed backdrop with it; the window is nearly solid, so the
blurred backdrop barely shows through. `Ctrl+T` in the window brings the overlay
back the same way.

To the shell the browser is then closed, so opening the wheel or a panel leaves
the window alone, and `SUPER+W` closes it as it closes any window. `Esc` only
clears the field: closing is the window's business. A file picked in the wheel
sends the window there and focuses it; summoning the browser without a path only
focuses it. Once the window is gone, the next summon opens the overlay again.

A file picked in the pinned search (see `docs/wheel.md`, Pinning) opens the
browser inside the search's window rather than a window of its own. There `Esc`,
or `Backspace` at home, goes back to the search, and `Ctrl+T` moves the browser
to the overlay, leaving the search in its window.

Closing a window cannot ask twice, so an unsaved edit does not go with it: the
overlay comes back holding the edit, where `Esc` asks as usual.

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
motion is the only thing that should claim it.

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

Of the two declines, only `4` says anything. `3` is a terminal handler for a
file that is not text, and every terminal handler here is nvim, so it hardly
happens. `4` is nothing owning it at all, and there the panel says `nothing
here opens <name>`: with no pane covering for it, silence reads as a key that
did nothing.

**`FileView` does not tell you whether a write worked.** Neither `saved` nor
`saveFailed` fires for `setText`; a permission failure only prints a warning.
A `reload()` in the same tick as the write is also swallowed, which is what the
150 ms is for.

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

`bin/omarchy-open-path` is on `PATH` because a plugin directory is private to
its owner. It routes by handler rather than calling `xdg-open` blindly:
`text/plain` resolves to `nvim.desktop` here, and `xdg-open` launches that with
no terminal attached, so nvim hangs invisibly and `Enter` looks like it did
nothing.

So text that no graphical app owns — a terminal handler like that one, or no
handler at all, as for `.js`, `.sh` and `.json` here — goes to
`omarchy-launch-editor`, which opens Omarchy's default editor and gives a
terminal editor its terminal. An empty file counts as text: a new file is
written there too. Anything else with a terminal handler is a
decline: the script exits `3`, and the browser keeps its place. An image, a PDF,
a video goes to `xdg-open`, and a zero exit is what tells the browser to step
aside for it. `python3 tests/open-path.py` runs each route with the handlers and
launchers stubbed.

The wheel registers it in `MenuIndex.js` as an `EXTRAS` entry — searchable
without consuming a ring slice, so the default ring keeps the even count that
fills 3 and 9 o'clock. Being a slice rather than an app is what puts it above
GNOME Files, whose entry is also called "Files".

The backdrop is not this surface's. The wash and the blur behind the card
belong to one scrim owned by the bar, which the panels, the wheel and the
clipboard hold a count on too — so opening the browser from the wheel changes
what stands on the backdrop without the backdrop itself going anywhere. This
surface only asks for that count when it opens (`Files.qml` `onOpenedChanged`)
and lets it go when it closes; the bar holds the scrim 150 ms past the last
release, which covers the ~55 ms a replacement surface takes to map.

## Known limits

- **Colour lands a beat after the text.** Debounce plus interpreter start on
  every selection. Caching the last few results, or keeping one Python process alive to serve
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
- The key legend is one line, 1117 px wide at the stock size. Where the card
  or the window is narrower, it shrinks to fit: barely in a half-screen tile,
  to about 60% in a third of a 1080p screen, where it is hard to read.
- An image's pixel size comes from `identify`. Colour and dimensions are both
  niceties rather than dependencies: without ImageMagick there are no numbers,
  and the size and the date still stand.
