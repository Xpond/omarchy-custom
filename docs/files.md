# The files browser

A keyboard-driven directory browser, reached by typing `files` into the wheel.

Two columns on one card: the directory on the left, what the selection *is* on
the right. It answers where is it, what is in it, and open it — which is what a
file manager actually gets reached for.

    plugins/xpo.files/
      manifest.json   kind: "overlay", keepLoaded
      Files.qml       surface, input model, list and preview
      FilesIndex.js   snapshotting, filtering, path and preview text helpers

It is deliberately a browser and **not** a manager. Nothing here renames,
copies or deletes. Those are the operations that cost you data when they go
wrong, `yazi` is installed and already does them properly, and a half-built
version of them in an overlay is worse than none.

## Keys

| | |
|---|---|
| type anything | filter the current directory by name |
| `/` or `~` | switch the field to a path — see [Path entry](#path-entry) |
| `↑` `↓` `Tab` `Shift+Tab` | move the selection, wrapping at both ends |
| `→` `Enter` | descend into a folder, or hand a file to the app that owns it |
| `←` | go up one directory |
| `Backspace` | delete a character, then go up one directory |
| `Home` | jump back to `~` |
| `Shift+↑` `Shift+↓` | scroll the preview three lines |
| `PageUp` `PageDown` | scroll the preview a page |
| `Shift+←` `Shift+→` | pan the preview sideways, for lines past the edge |
| `Ctrl+H` | show hidden files |
| `Ctrl+U` | clear the field |
| `Esc` | clear the field, then close |

Shift is the one modifier that means "the other pane": held down, the arrows
drive the preview instead of the list. The mouse works too — hover selects,
click opens, a click outside the card closes it, and the wheel scrolls whichever
pane is under the pointer.

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
then the count, all flowing left. The preview's own heading — name, size, date —
right-aligns on the same line. The count sits with the path rather than at the
far edge because right-aligned it stacked directly above the preview's size and
date, and two dim figures in a column read as two facts about one file.

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
as a `Process` and the exit code decides: `0` closes, `3` stays.

**Both `FolderListModel` handlers are gated on `Ready`.** A load raises `count`
on its way to `Ready`, so ungated the model was snapshotted twice per directory
and flashed empty in between. `onCountChanged` is still needed for a file
appearing under an open panel, which raises `count` with the model already
`Ready`.

## Wiring

Nothing below is done by `install.sh` — same gap `xpo.wheel` has.

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
  keeps its indentation but not its distinction from surrounding prose.
- The line-number gutter counts the lines of the *source*. A wrapped Markdown
  paragraph has no numbers at all, by design; a code file never wraps, so the
  two agree.
- No rename, copy, delete, or new-folder. Deliberate — use `yazi`.
- Only the first 500 lines of a file are ever shown, and only the first 400
  entries of a previewed folder.
- **Opening the browser from the wheel flashes.** The wheel unmaps before this
  surface maps, and for a frame or two the desktop shows through unblurred.
  Fixing it was attempted twice and both fixes were worse: fading the wheel out
  over the browser stacks two blurred scrims (measured: 14% darker, half the
  contrast, for the length of the fade), and handing over on a handshake moved
  the artifact rather than removing it. Reverted; the flash stands.
- `install.sh` wires none of this up.
