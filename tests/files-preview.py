#!/usr/bin/env python3
"""Code previews render pixel for pixel as the rich-text <pre> they replaced."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import qslog

repo = Path(__file__).resolve().parents[1]
plugin = repo / "plugins/xpo.files"
shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
LIMIT = 120

# The highlighter as it was: pygments HTML for a rich-text <pre>.
RICH = """import sys
from pygments import highlight
from pygments.lexers import get_lexer_for_filename
from pygments.lexers.special import TextLexer
from pygments.formatters import HtmlFormatter
p = sys.argv[1]
parts = open(p, errors='replace').read().split('\\n')
src = '\\n'.join(parts[:%d])
if len(parts) - (parts[-1] == '') > %d: src += '\\n\u2026'
try:
    lx = get_lexer_for_filename(p, stripnl=False)
except Exception:
    lx = TextLexer()
sys.stdout.write(highlight(src, lx, HtmlFormatter(nowrap=True, noclasses=True, style='one-dark')))
""" % (LIMIT, LIMIT)

samples = {
    "lead.txt": "\nfoo\nbar\n", "lead2.py": "\n\nx = 1\n", "only-newlines.txt": "\n\n\n",
    "newline.txt": "\n", "one.txt": "x", "blank.py": "a = 1\n\n\n\nb = 2\n",
    "blank-lines.txt": "a\n   \n\t\nb", "trailing.txt": "a   \nb\t\n",
    "crlf.py": "one = 1\r\ntwo = 2\r\n\r\nthree = 3\r\n", "cr.txt": "a\rb\rc\n",
    "fallback.txt": "naïve → 日本語 ✓ 😀\nplain line\n  ✓ indented\n😀\n日本語だけ\n",
    "markup.js": "if (a < b && c > d) { s = \"x\" + 'y' } // &amp; &nbsp; <br> </pre> &#9;\n",
    "separators.txt": "a\u2028b\u2029c\n", "breaks.txt": "a\fb\vc\n\x85d\n",
    "spaces.txt": "nb\u00a0sp ideo\u3000graphic thin\u2009space\n", "control.txt": "bell\x07 esc\x1b[0m\n",
    "long.txt": "x" * 400 + "\ny\n", "tabs.c": "int\tmain(void)\n{\n\tif (x)\n\t\treturn 1;\t// tab\n}\n",
    "multiline.js": "/* multi\n   line */\nconst s = `a\nb`\n",
    "bold.py": "def f():\n    '''doc\n    string'''\n    return 1\n# end",
    "italic.rst": "Title\n=====\n\n*emphasis* and **strong**\n",
    "truncated.txt": "\n".join("line %d" % i for i in range(LIMIT + 30)),
}
files = [repo / "plugins/xpo.wheel/MenuIndex.js", repo / "plugins/xpo.wheel/Wheel.qml",
         repo / "install.sh", repo / "tests/install.py"]

with tempfile.TemporaryDirectory(prefix="omarchy-preview-") as temporary:
    base = Path(temporary)
    (base / "Commons").symlink_to(shell / "Commons")
    shutil.copyfile(plugin / "FilesIndex.js", base / "FilesIndex.js")
    styled = (plugin / "FilesPreview.qml").read_text().replace("Style.font.subtitle", "panel.codePx")
    handler = styled[styled.index("        onLineLaidOut:"):styled.index("      }\n    }\n  }\n\n  Rectangle")]
    rich = styled.replace("panel.showsCode ? Text.StyledText", "panel.showsCode ? Text.RichText")
    assert rich != styled and handler
    (base / "Styled.qml").write_text(styled)
    (base / "Rich.qml").write_text(rich.replace(handler, ""))

    def run(*command):
        return subprocess.run(command, capture_output=True, text=True, check=True).stdout

    cases = []
    for name, text in list(samples.items()) + [(f.name, f.read_text()) for f in files]:
        path = base / "cases" / name
        path.parent.mkdir(exist_ok=True)
        path.write_text(text, newline="")
        cases.append({"name": name, "text": text, "rich": run("python3", "-c", RICH, str(path)),
                      "styled": run("python3", str(plugin / "highlight.py"), str(path), str(LIMIT))})
    (base / "cases.json").write_text(json.dumps(cases))

    (base / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs.Commons
import "FilesIndex.js" as FilesIndex
Scope {
  component Panel: QtObject {
    property int codePx: 13
    property int lineHeight: Math.round(codePx * 1.75)
    property string previewText: ""
    property string previewBody: ""
    property bool showsCode: !!previewText
    property bool editing: false
    property bool dirty: false
    property bool showsMarkdown: false
    property bool showsDir: false
    property bool showsImage: false
    property var dirColumns: []
    property var settledSel: null
    property string previewNote: ""
    property int gutterGap: 16
    property int dirTopPad: 7
  }
  Panel { id: before }
  Panel { id: after }
  Window {
    width: 3400; height: 3600; visible: true; color: "black"
    Rich { id: rich; panel: before; width: 1650 }
    Styled { id: styled; panel: after; x: 1700; width: 1650 }
  }
  property var jobs: []
  function next() {
    if (!jobs.length) { console.log("PASS"); Qt.quit(); return }
    var j = jobs.shift()
    var text = FilesIndex.head(j.text, ''' + str(LIMIT) + ''')
    // Room for every line break either format could draw, so nothing is clipped.
    var lines = (text.match(/[\\n\\r\\v\\f\\x85\\u2028\\u2029]/g) || []).length + 2
    rich.height = styled.height = lines * Math.round(j.px * 1.75) + 30
    before.codePx = after.codePx = j.px
    before.previewText = after.previewText = text
    before.previewBody = '<pre style="margin:0; font-family:\\'' + Style.font.menuFamily + '\\'; font-size:'
      + j.px + 'px">' + (j.stage === "plain"
        ? text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") : j.rich) + '</pre>'
    after.previewBody = j.stage === "plain" ? FilesIndex.styledCode(text) : j.styled
    Qt.callLater(function () {
      rich.grabToImage(function (a) {
        a.saveToFile("out/" + j.file + "-rich.png")
        styled.grabToImage(function (b) { b.saveToFile("out/" + j.file + "-styled.png"); Qt.callLater(next) })
      })
    })
  }
  Component.onCompleted: {
    var x = new XMLHttpRequest()
    x.open("GET", Qt.resolvedUrl("cases.json"), false); x.send()
    var cases = JSON.parse(x.responseText)
    for (var c of cases) for (var px of [11, 13, 16]) for (var stage of ["plain", "coloured"])
      jobs.push({ text: c.text, rich: c.rich, styled: c.styled, px: px, stage: stage,
                  file: c.name + "-" + px + "-" + stage })
    Qt.callLater(next)
  }
}
''')
    (base / "out").mkdir()
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1",
               QML_XHR_ALLOW_FILE_READ="1", XDG_RUNTIME_DIR=str(base / "runtime"))
    result = subprocess.run(["quickshell", "--no-color", "-p", str(base / "shell.qml")], cwd=base,
                            env=env, capture_output=True, text=True, timeout=900)
    log = result.stdout + result.stderr
    assert "PASS" in log, log
    qslog.check(log)

    pairs = sorted(p.name[:-len("-rich.png")] for p in (base / "out").glob("*-rich.png"))
    assert len(pairs) == len(cases) * 6, len(pairs)
    # compare alone reports 0 for images of different sizes.
    size = lambda p: subprocess.check_output(["magick", "identify", "-format", "%wx%h", p], text=True)
    failed = []
    for name in pairs:
        a, b = (base / "out" / (name + suffix) for suffix in ("-rich.png", "-styled.png"))
        diff = subprocess.run(["magick", "compare", "-metric", "AE", a, b, "null:"],
                              capture_output=True, text=True).stderr.split()[0]
        if size(a) != size(b) or diff != "0":
            failed.append("%s: %s vs %s, %s pixels differ" % (name, size(a), size(b), diff))
    assert not failed, "\n".join(failed)
    print("ok: %d code previews, plain and coloured at three sizes, match the rich text pixel for pixel"
          % len(pairs))
