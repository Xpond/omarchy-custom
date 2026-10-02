"""Colour a file preview for Qt's StyledText: python3 highlight.py <path> <lines>"""
import re
import sys

from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_for_filename
from pygments.lexers.special import TextLexer

path, limit = sys.argv[1], int(sys.argv[2])
parts = open(path, errors="replace").read().split("\n")
src = "\n".join(parts[:limit])
if len(parts) - (parts[-1] == "") > limit:
    src += "\n…"
try:
    lexer = get_lexer_for_filename(path, stripnl=False)
except Exception:
    lexer = TextLexer()
html = highlight(src, lexer, HtmlFormatter(nowrap=True, noclasses=True, style="one-dark"))

# The same rules as FilesIndex.styledCode(), which shows the file until this answers.
if html.startswith("\n"):
    html = html[1:]
if html.endswith("\n"):
    html = html[:-1]
space = re.compile("[\t\x0b\x0c \xa0\u1680\u2000-\u200a\u202f\u205f\u3000]")
closers = []


def styled(piece):
    if piece == "</span>":
        return closers.pop()
    if piece.startswith("<span"):
        color = re.search(r"color: (#\w+)", piece)
        opened, closer = ('<font color="%s">' % color.group(1), "</font>") if color else ("", "")
        for word, tag in (("bold", "b"), ("italic", "i")):
            if word in piece:
                opened, closer = opened + "<%s>" % tag, "</%s>" % tag + closer
        closers.append(closer)
        return opened
    piece = re.sub("[\n\u2028\u2029]", "<br>", piece)
    # Qt reads &#133; as an ellipsis; another glyphless control keeps NEL's box.
    piece = piece.replace("\x85", "\x80")
    return space.sub(lambda m: "&#%d;" % ord(m.group()), piece)


sys.stdout.write("".join(map(styled, re.split("(<[^>]*>)", html))))
