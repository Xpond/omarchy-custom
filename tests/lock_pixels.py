"""Pixel regressions for captures produced by lock-render.py."""
from functools import cache
import re
import subprocess


def check(output, stages, log):
    @cache
    def raster(name):
        stage = next(s for s in stages if s["name"] == name)
        rgb = subprocess.check_output(["magick", str(output / (name + ".png")), "-depth", "8", "RGB:-"])
        return stage.get("width", 1920), rgb

    def pixels(name, crop, framed=True):
        # Decode each capture once; all material probes share the same RGB buffer.
        w, h, x, y = map(int, re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", crop).groups())
        width, rgb = raster(name)
        if framed:
            # Material coordinates precede the scene's shared framing: carFraming scales by 0.89
            # about the centre, then carLower moves the car 3% right and 4% down.
            x, y = round(x * 0.89 + width * 0.085), round(y * 0.89 + width * 9 / 16 * 0.095)
            w, h = max(1, round(w * 0.89)), max(1, round(h * 0.89))
        return b"".join(rgb[(row * width + x) * 3:(row * width + x + w) * 3] for row in range(y, y + h))

    def difference(a, b, crop):
        left, right = pixels(a, crop), pixels(b, crop)
        assert len(left) == len(right)
        return sum(abs(x - y) for x, y in zip(left, right)) / len(left)

    # Camera focus softens the distant silhouette while preserving the foreground.
    for name, sharp, scale in [("parked", "sharp", 1), ("4k", "sharp-4k", 2)]:
        roof = difference(name, sharp, f"{300*scale}x{24*scale}+{960*scale}+{217*scale}")
        assert 1 < roof < 10, f"missing or excessive far-edge softness in {name}: {roof:.2f}"
        for w, h, x, y in [(70, 70, 650, 690), (180, 40, 990, 670), (80, 80, 20, 30)]:
            change = difference(name, sharp, f"{w*scale}x{h*scale}+{x*scale}+{y*scale}")
            assert change < 0.1, f"focus blurred the foreground or backdrop in {name} at {(x, y)}"
    print("ok: far edges soften while foreground wheels, lettering and backdrop stay sharp at 1080p and 4K")

    # These regions are inside materials, away from antialiased panel boundaries.
    for name, scale in [("parked", 1), ("4k", 2)]:
        pink = pixels(name, f"{scale}x{scale}+{1080*scale}+{510*scale}")
        blue = pixels(name, f"{scale}x{scale}+{750*scale}+{550*scale}")
        white = pixels(name, f"{scale}x{scale}+{1000*scale}+{580*scale}")
        assert min(pink[0::3]) > max(pink[1::3]) + 25, f"missing neon reflection in {name}"
        assert min(blue[2::3]) > max(blue[0::3]) + 40 and max(white) < 190, f"missing cool night lighting in {name}"
        for x, y in [(337, 580), (717, 615)]:
            unlit = "unlit" if scale == 1 else "unlit-4k"
            assert max(pixels(unlit, f"{scale}x{scale}+{x*scale}+{y*scale}")) < 40, f"scenery visible through grille or arch in {unlit}"
        for x in [60, 1810]:
            backdrop = pixels(name, f"{50*scale}x{200*scale}+{x*scale}+{150*scale}", framed=False)
            assert max(backdrop) > 60 and max(backdrop) - min(backdrop) > 50, f"missing backdrop in {name} at {x}"
    assert difference("parked", "unlit", "150x80+20+30") < 0.1, "shader escaped into the background"
    assert difference("parked", "unlit", "80x50+1100+360") > 8, "cabin shading did not render"
    assert difference("parked", "unlit", "40x20+320+570") > 2, "nose plastic shading did not render"
    assert difference("parked", "unlit", "180x60+990+570") > 8, "body shader did not render"
    assert difference("parked", "unlit", "100x100+650+680") > 8, "metal rims did not render"
    assert difference("trace", "trace-unlit", "1920x1080+0+0") < 0.1, "shader changed unpainted tracing"
    # The far cabin wall once lost a large triangle through the windscreen during
    # pitch, and a smaller one beside the seat during launch. Probe their interiors.
    for suffix, scale in [("", 1), ("-4k", 2)]:
        for name, x, y, minimum in [("pitch", 758, 321, 170), ("launch", 989, 394, 115)]:
            name += suffix + "-unlit"
            patch = pixels(name, f"{3*scale}x{3*scale}+{x*scale}+{y*scale}")
            assert sum(patch) / len(patch) > minimum, f"missing cabin fill in {name}"
    probes = re.findall(r"SAIL (\S+) (\d+) (\d+)", log)
    assert {p[0] for p in probes} == {s["name"] for s in stages if 0 < s.get("drive", 0) < 0.9}, "missing drive-off probes"
    for name, x, y in [p for p in probes if p[0].endswith("-unlit")]:
        patch = pixels(name, f"3x3+{x}+{y}", framed=False)
        assert sum(patch) / len(patch) > 165, f"cabin triangle disappeared during {name}"
    for name, scale in [("parked", 1), ("4k", 2)]:
        # Rubber stays black between the letters; the shoulder above HAVE/SOME catches a neutral
        # highlight. Mirroring the city there washed the tyres grey, then smeared into streaks.
        for x, y in [(691, 638), (1362, 585)]:
            rubber = pixels(name, f"{scale}x{scale}+{x*scale}+{y*scale}")
            assert max(rubber) < 40, f"tyre no longer black at {(x, y)} in {name}"
        for x, y in [(656, 656), (1352, 591)]:
            shine = pixels(name, f"{scale}x{scale}+{x*scale}+{y*scale}")
            assert min(shine) > 60 and max(shine) - min(shine) < 15, f"missing or tinted tyre shine at {(x, y)} in {name}"
        # Inside each gold hub, light must roll off without a separate bright band.
        # Smooth edges alone still allowed the old strip reflection to look patched.
        for x, y, height in [(680, 714, 21), (1385, 621, 19)]:
            strip = pixels(name, f"1x{height*scale}+{x*scale}+{y*scale}")
            levels = [sum(strip[i:i+3]) / 3 for i in range(0, len(strip), 3)]
            jump = max(abs(a - b) for a, b in zip(levels, levels[1:])) * scale
            assert jump < 30, f"hard reflection patch on the hub at {x} in {name}: {jump:.1f}"
            assert max(levels) - levels[0] < 10, f"separate reflection band on the hub at {x} in {name}"
            assert max(levels) - min(levels) > 50, f"flat gold hub at {x} in {name}"
        # The navy pigment stays dark through the corner even where it reflects neon.
        # Different reflected colours on the two faces are expected in the city scene.
        corner = pixels(name, f"{3*scale}x{3*scale}+{479*scale}+{737*scale}")
        flank = pixels(name, f"{3*scale}x{3*scale}+{494*scale}+{734*scale}")
        assert max(sum(corner) / len(corner), sum(flank) / len(flank)) < 90, f"navy bumper washed out in {name}"
        # The rounded join crosses white paint and all three stripe colours. An
        # overlaid construction stroke left a narrow white peak through every colour.
        for x, y in [(497, 720), (492, 735), (485, 760), (457, 828)]:
            samples = [pixels(name, f"{scale}x{scale}+{(x+dx)*scale}+{y*scale}") for dx in [-3, 0, 3]]
            left, seam, right = [sum(sample) / len(sample) for sample in samples]
            assert seam - max(left, right) < 8, f"white bumper seam at {(x, y)} in {name}"
        # Reject an abrupt seam, allowing a smooth reflection gradient across the join.
        for x, y in [(500, 710), (476, 790), (466, 815), (460, 824)]:
            samples = [pixels(name, f"{scale}x{scale}+{(x+dx)*scale}+{y*scale}") for dx in range(-3, 4)]
            levels = [sum(sample) / len(sample) for sample in samples]
            steps = [b - a for a, b in zip(levels, levels[1:])]
            assert max(abs(b - a) for a, b in zip(steps, steps[1:])) < 2.5, f"bumper reflection steps at {(x, y)} in {name}"
        # Equal-height paint beside each arch must share the surrounding reflection;
        # a radial normal boost previously made these skirts 35 levels brighter.
        for skirt, body in [((600, 680), (570, 685)), ((1534, 563), (1558, 560))]:
            samples = [pixels(name, f"{3*scale}x{3*scale}+{x*scale}+{y*scale}") for x, y in [skirt, body]]
            jump = abs(sum(samples[0]) - sum(samples[1])) / len(samples[0])
            assert jump < 10, f"isolated wheel-skirt highlight at {skirt}: {jump:.1f} in {name}"
        # The triangular sill return and both arch interiors are shaded recesses.
        for x, y in [(1305, 700), (833, 735), (1515, 621)]:
            recess = pixels(name, f"{3*scale}x{3*scale}+{x*scale}+{y*scale}")
            assert 20 < sum(recess) / len(recess) < 80, f"unshaded or missing return at {(x, y)} in {name}"
        # Sample across the exact trailing strips: shadow -> bend -> painted lip.
        # Uniformly darkening them left the same separate, hard-edged crescent.
        for xs, y in [((834, 838, 842), 734), ((1517, 1523, 1527), 620)]:
            strip = [pixels(name, f"{scale}x{scale}+{x*scale}+{y*scale}") for x in xs]
            dark, middle, lip = [sum(sample) / len(sample) for sample in strip]
            assert dark + 15 < middle < lip - 15, f"flat or discontinuous inner wall at {xs} in {name}"
        # The rear return vanishes here. Full shadow on its subpixel tip previously
        # cut this antialiased body edge from 113 to 33, leaving a black protrusion.
        tip = pixels(name, f"{scale}x{scale}+{1457*scale}+{524*scale}")
        assert sum(tip) / len(tip) > 90, f"dark protrusion at the rear return tip in {name}"
        # Across the rear return's outer join at four heights, light must not dip
        # into a separate ink line between the shaded return and the body paint.
        for points in [((1529, 604), (1530, 603), (1531, 603)),
                       ((1520, 576), (1521, 575), (1522, 574)),
                       ((1504, 552), (1505, 551), (1505, 550)),
                       ((1483, 535), (1484, 534), (1485, 533))]:
            samples = [pixels(name, f"{scale}x{scale}+{x*scale}+{y*scale}") for x, y in points]
            inner, join, outer = [sum(sample) / len(sample) for sample in samples]
            assert min(inner, outer) - join < 10, f"extra rear arch outline at {points[1]} in {name}"
    print("ok: bumper paint and stripes join continuously, without a white seam, at 1080p and 4K")
    print("ok: wheel skirts and recessed returns blend without patches, protrusions or extra outlines")
    print("ok: GPU shader shades body, rims, cabin and nose, preserves the background and unpainted tracing")
    print("ok: cabin panels stay filled through pitch and launch at 1080p and 4K")
    print("ok: tyres stay black with a neutral shoulder shine and gold hubs keep a continuous highlight at 1080p and 4K")
