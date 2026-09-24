#!/usr/bin/env python3
"""The branding tools (plan 2D) against fixtures: rebuild-font, apply-strings, rewrite-manifests."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, "branding")
REBUILD, APPLY, MANIFESTS = (os.path.join(B, n) for n in ("rebuild-font", "apply-strings", "rewrite-manifests"))

try:
    import fontTools  # noqa: F401
    HAVE_FONTTOOLS = True
except ImportError:
    HAVE_FONTTOOLS = False

MARK = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><path d="M96 128H928V320H640V896H384V320H96Z"/></svg>\n'


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def make_font(path, with_e900=True):
    """A two-mark fixture font shaped like upstream's: U+E900 fills the em, U+E901 the 64..960 box."""
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    def square(x0, y0, x1, y1):
        p = TTGlyphPen(None)
        p.moveTo((x0, y0)); p.lineTo((x0, y1)); p.lineTo((x1, y1)); p.lineTo((x1, y0)); p.closePath()
        return p.glyph()

    fb = FontBuilder(1024, isTTF=True)
    fb.setupGlyphOrder([".notdef", "omarchy", "pi"])
    fb.setupCharacterMap({0xE900: "omarchy", 0xE901: "pi"} if with_e900 else {0xE901: "pi"})
    fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "omarchy": square(0, 0, 1024, 1024), "pi": square(64, 64, 960, 960)})
    fb.setupHorizontalMetrics({".notdef": (1024, 0), "omarchy": (1024, 0), "pi": (1024, 64)})
    fb.setupHorizontalHeader(ascent=1024, descent=0)
    fb.setupNameTable({"familyName": "omarchy", "styleName": "Regular"})
    fb.setupOS2()
    fb.setupPost()
    fb.save(path)


def signed_area(points):
    return sum(points[i][0] * points[(i + 1) % len(points)][1] - points[(i + 1) % len(points)][0] * points[i][1]
               for i in range(len(points))) / 2


@unittest.skipUnless(HAVE_FONTTOOLS, "python3-fonttools is not installed")
class RebuildFont(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="tinkero-font.")
        self.src = os.path.join(self.tmp, "in.ttf")
        self.out = os.path.join(self.tmp, "out.ttf")
        self.svg = os.path.join(self.tmp, "mark.svg")
        make_font(self.src)
        write(self.svg, MARK)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_tool(self, svg=None, src=None):
        return subprocess.run([sys.executable, REBUILD, src or self.src, svg or self.svg, self.out], capture_output=True, text=True)

    def glyph(self, font, name):
        from fontTools.ttLib import TTFont
        f = TTFont(font)
        return f, f["glyf"][name]

    def test_replaces_only_e900(self):
        r = self.run_tool()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("rebuild-font: U+E900 (omarchy) is now 1 contour(s) in (148, 176, 876, 848); 1 other glyph(s) untouched", r.stdout)
        a, pa = self.glyph(self.src, "pi")
        b, pb = self.glyph(self.out, "pi")
        self.assertEqual(pa.compile(a["glyf"]), pb.compile(b["glyf"]))       # the other mark's bytes
        self.assertEqual(a.getBestCmap(), b.getBestCmap())
        self.assertEqual(b["name"].getDebugName(1), "omarchy")
        self.assertEqual(b["hmtx"]["omarchy"], (1024, 148))
        g = b["glyf"]["omarchy"]
        self.assertEqual((g.xMin, g.yMin, g.xMax, g.yMax), (148, 176, 876, 848))   # inside the 64..960 box

    def test_orientation_matches_the_other_marks(self):
        self.run_tool()
        b, g = self.glyph(self.out, "omarchy")
        coords, ends, _ = g.getCoordinates(b["glyf"])
        self.assertLess(signed_area(list(coords)[: ends[0] + 1]), 0)   # clockwise, like the fixture's squares

    def test_several_shapes(self):
        write(self.svg, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="10" y="10" width="80" height="20"/><circle cx="50" cy="65" r="20"/></svg>\n')
        r = self.run_tool()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.glyph(self.out, "omarchy")[1].numberOfContours, 2)

    def test_transform_attribute_is_refused(self):
        write(self.svg, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><g transform="scale(2)"><rect width="10" height="10"/></g></svg>\n')
        r = self.run_tool()
        self.assertEqual(r.returncode, 1)
        self.assertIn("transform", r.stderr)
        self.assertFalse(os.path.exists(self.out))

    def test_no_viewbox_is_refused(self):
        write(self.svg, '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>\n')
        r = self.run_tool()
        self.assertEqual(r.returncode, 1)
        self.assertIn("no viewBox", r.stderr)
        self.assertFalse(os.path.exists(self.out))

    def test_font_without_e900_is_refused(self):
        src = os.path.join(self.tmp, "bare.ttf")
        make_font(src, with_e900=False)
        r = self.run_tool(src=src)
        self.assertEqual(r.returncode, 1)
        self.assertIn("no glyph at U+E900", r.stderr)


# Task 3 appends class ApplyStrings here.
# Task 4 appends class RewriteManifests here.

if __name__ == "__main__":
    unittest.main()
