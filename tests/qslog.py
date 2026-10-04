"""Fails a test on Quickshell warnings it did not expect, so new ones surface where they start."""
import re

LEVEL = re.compile(r"^(?:[\d-]+ [\d:.]+)?\s*(?:WARN|ERROR|FATAL)\b")
# An offscreen run inside a Wayland session gets a notice over three lines.
NOISE = ["QT_QPA_PLATFORM", "--- WARNING ---"]


def check(log, *expected):
    """Asserts the log has no line at warning level or above beyond that notice and the expected patterns."""
    lines = [line for line in log.splitlines()
             if LEVEL.match(line) and not any(re.search(p, line) for p in NOISE + list(expected))]
    assert not lines, "unexpected Quickshell warnings:\n" + "\n".join(lines)
