"""S1 part regressions against lock-render.py's 1080p and 4K captures."""
from functools import cache
from pathlib import Path
import subprocess
import sys


def check_parts(output):
    @cache
    def raster(name):
        return subprocess.check_output(["magick", str(output / (name + ".png")), "-depth", "8", "RGB:-"])

    def pixel(name, x, y, scale):
        rgb = raster(name)
        start = (y * scale * 1920 * scale + x * scale) * 3
        return rgb[start:start + 3]

    def level(name, x, y, scale):
        return sum(pixel(name, x, y, scale)) / 3

    for name, bare, scale in [("parked", "wingless", 1), ("4k", "wingless-4k", 2)]:
        # The far fin stands behind this patch of the roof's corner and near C-pillar.
        # Removing the wing must leave it unchanged, including its lighting mask.
        for x in range(1332, 1342):
            for y in range(362, 370):
                a, b = pixel(name, x, y, scale), pixel(bare, x, y, scale)
                assert max(abs(i - j) for i, j in zip(a, b)) <= 1, f"wing shows through roof in {name}"
        assert abs(level(name, 1469, 339, scale) - level(bare, 1469, 339, scale)) > 10, "wing reference did not remove wing"
        # The rounded housing must shade across its curved front shoulder.
        # a broad highlight must rise and fall without turning white.
        mirror = [level(name, 1007, y, scale) for y in range(484, 511)]
        assert max(mirror) - min(mirror) > 40 and max(mirror) < 160, f"flat or washed-out mirror in {name}"
        assert 2 < mirror.index(max(mirror)) < len(mirror) - 3, f"missing curved mirror highlight in {name}"
        # Rubber falls continuously out of the arch's shade. The former three
        # flat bands produced a sudden jump halfway down this strip.
        flap = [level(name, 910, y, scale) for y in range(802, 824)]
        assert flap[-1] - flap[0] > 15, f"flat mud flap in {name}"
        assert max(abs(a - b) for a, b in zip(flap, flap[1:])) < 5, f"banded mud flap in {name}"
        # The near fin carries the body's clear-coat reflections and its carbon tip curls
        # from a dark base into a sky highlight. Flat planes shaded each one colour.
        fin = [level(name, 1611, y, scale) for y in range(384, 432)]
        assert max(fin) - min(fin) > 8, f"flat wing fin in {name}"
        assert max(abs(a - b) for a, b in zip(fin, fin[1:])) < 5, f"banded wing fin in {name}"
        tip = [level(name, 1637, y, scale) for y in range(350, 363)]
        assert min(tip) < 45 and max(tip) - min(tip) > 50, f"matte carbon tip in {name}"
    print("ok: wing stays behind roof and its fins and tips shade like paint; mirrors curve and rubber "
          "shades continuously at 1080p and 4K")


if __name__ == "__main__":
    check_parts(Path(sys.argv[1]))
