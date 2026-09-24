# Phase 2D: Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan runs through the issue loop** (`docs/guides/workflow.md`): dispatched only once Diego has applied `approved`, landed through a PR with green CI, tasks built serially on one branch in the order below.

**Goal:** The `tinkero` payload shows and says Tinkero everywhere a user looks (the bar's menu glyph, the About screen and its OS line, the screensaver and presentation logos, every theme's wallpaper rotation, the cheat sheet, the plugin picker, the Learn menu) while every identifier keeps upstream's name, About credits Omarchy, and a CI gate proves it on every push.

**Architecture:** Everything is data under `branding/` read by five small tools at build time: `rebuild-font` (fontTools) replaces the `U+E900` glyph in place; `apply-strings` applies a count-checked fixed-string substitution list; `rewrite-manifests` rebrands the plugin manifests' author and display strings by replacing encoded JSON values in the text and verifying by parsing; `render-wallpapers` applies a person's per-image verdicts (`images.tsv`), rendering the flat wordmark wallpapers anew from `wordmark.svg` in each theme's colours and deleting the illustrated ones; `inventory-images` and `contact-sheet` support that review. `build/assemble` step 3d runs them; `ci/gate-branding` checks the payload against `ci/allow/branding.allow`, `images.tsv` and `strings.tsv`. The artwork is a generated geometric placeholder until the real mark exists; replacing it is a data change.

**Tech Stack:** Python 3 standard library plus `python3-fonttools` (the font only), bash, ImageMagick 7 (`magick`), the existing `tests/lib.sh` harness and `unittest`, the CI gates. Two new build dependencies: `python3-fonttools` and `ImageMagick`, both in Fedora 44.

**Spec:** `docs/superpowers/specs/2026-09-23-phase-2d-branding-design.md` (the 2D design, derived from the master spec and binding for this plan; its section 11 lists the decisions D1 to D15 the operator may veto at approval) and `docs/superpowers/specs/2026-09-17-tinkero-design.md` sections 4.4, 4.13 and 8 (item 4a and Milestone B). Audit: `docs/research/arch-coupling-audit.md` section 11. Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`. Placeholder issue: #8.

## Global Constraints

- Upstream tree pinned by `upstream.lock` at `v4.0.4`; every count in this plan (20 flat wallpapers, 4 deletions, 36 authors, 11 fields, 5 rows, 6 replacements, 49 gate findings before and 8 after, 258 menu rows) was measured against that tag on 2026-09-23 and the bump checklist re-measures it.
- `build/assemble TARBALL DEST` is the whole of `%install`; branding is one numbered step (3d) inserted immediately before the `# 4. Relocate` comment and guarded on `$root/branding/strings.tsv`, so fixture roots without `branding/` skip it. `tinkero.spec.in` gets a `BuildRequires:` line, no logic.
- Data over code: what is substituted is `branding/strings.tsv`; what happens to each wallpaper is `branding/images.tsv`; the artwork is `branding/*.svg` and `branding/*.txt`. The tools never carry a file name, a string or a verdict of their own.
- Identifiers never change: `omarchy-*` commands, `/usr/share/omarchy`, `~/.config/omarchy`, plugin ids (`omarchy.*`), menu ids (`learn.omarchy` keeps its id, D5), window classes, PAM service names, the font family name `omarchy`, the glyph name `omarchy`.
- Gate allowlists only shrink. `ci/allow/branding.allow` is written once, in Task 7, from the gate's findings on the real payload (8 entries), with a comment per entry; the other two allowlists are untouched.
- Python is standard library only, except `fontTools` in `branding/rebuild-font` and the tests that exercise it; tests use `unittest`, never pytest. Bash scripts start with `#!/bin/bash` and `set -euo pipefail`, ShellCheck clean with `-x -e SC1090,SC1091`; no `A && B || C` one-liners.
- Tests never use the network. The tests that need ImageMagick or fontTools skip themselves visibly (`1..0 # skip ...` for a shell file, `unittest.skipUnless` for a Python class) when the tool is missing; CI installs both, so nothing is skipped there. `./dev gates` needs both on the developer's machine: `sudo dnf install python3-fonttools ImageMagick`.
- ImageMagick is not installed on the planning machine, so every `magick` invocation in this plan was written from the ImageMagick 7 documentation and is first executed by the implementer or by CI. The Python tools and the gate were run against the real tree while planning and their outputs are the expected values below.
- Plan 2E (issue #16) is in flight and not assumed landed. Nothing here edits a file 2E creates; the one shared file, `build/assemble`, is edited at an anchor 2E does not touch (D14). If 2E lands first, its `tests/test-assemble.sh` count moves and nothing in this plan cares.
- No em dashes in Tinkero's own prose (the one dash in `strings.tsv` is upstream's list separator, matched and kept, D13). Attribution trailers on every commit per the session's rules. Land through a PR against the approved issue; never push master.
- Each task's PR includes its Deviations line in this plan's "## Deviations" section when anything deviated.

## Issue map

To be filed as one orchestrated issue superseding placeholder #8, the tasks built serially on one branch (they share `build/assemble`, `tests/test_branding.py`, `tests/test-gates.sh` and the allowlist). Task 6 needs Diego's wallpaper pass mid-task (D4) and says so. The `approved` label is Diego's.

| Task | Size | Area | WHAT | WHERE | HOW TO VERIFY |
|---|---|---|---|---|---|
| 1 Placeholder artwork | small | branding | the block "T" mark, the block-letter wordmark, the two ASCII renderings, `branding/README.md` | `branding/{mark.svg,wordmark.svg,logo.txt,icon.txt,README.md}` | `sha256sum` of the four files equals the values in Step 4; both SVGs parse as XML and have a `viewBox`; `logo.txt` is 7 lines by 82 columns with 222 block characters, `icon.txt` 26 by 54 with 644 |
| 2 `rebuild-font` | medium | branding | the glyph replacement, with a fixture font built in the test | `branding/rebuild-font`, `tests/test_branding.py` | `python3 -m unittest discover -s tests -p 'test_*.py'` passes 20 tests; on the real font: 19 glyphs byte-identical, family `omarchy`, cmap equal, GSUB kept, `U+E900` one contour at `(148, 176, 876, 848)` |
| 3 `apply-strings` and `strings.tsv` | small | branding | the count-checked substitution list and its tool | `branding/apply-strings`, `branding/strings.tsv`, `tests/test_branding.py` | 26 Python tests pass; on a copy of the real tree: `apply-strings: 5 row(s), 6 replacement(s) in 5 file(s)`, and a second run fails naming all five rows |
| 4 `rewrite-manifests` | small | branding | the manifest transform | `branding/rewrite-manifests`, `tests/test_branding.py` | 33 Python tests pass; on a copy of the real tree: `37 manifests, 36 rewritten: 36 author(s), 11 field(s)`, no `Omarchy` left outside `author`, every `"id"` line unchanged, a second run rewrites 0 |
| 5 The Learn rows | small | menu | `learn.omarchy` becomes the "Tinkero" README row through `omarchy-launch-browser`; `learn.fedora` uses the same launcher | `menu/overrides.jsonc` | `./dev payload` reports `258 rows out`; the built menu has the two rows as written; the file carries `U+E900` twice |
| 6 Wallpapers | medium (needs Diego) | branding | `inventory-images`, `contact-sheet`, `render-wallpapers`, the reviewed `images.tsv` | `branding/{inventory-images,contact-sheet,render-wallpapers,images.tsv}`, `tests/test-branding.sh`, `tests/test-branding-render.sh` | `bash tests/test-branding.sh` at `1..14`; `bash tests/test-branding-render.sh` at `1..34` (or its skip line without the tools; the 10 assemble cases pass only after Task 7); `images.tsv` has 92 rows and **no `review` row** (Diego's pass); on the real tree: `92 wallpapers: 68 kept, 20 regenerated, 4 deleted` |
| 7 Build step, gate, packaging, CI | medium | build | assemble step 3d, `gate-branding` and its allowlist, `BuildRequires`, `dev`, the workflow | `build/assemble`, `ci/gate-branding`, `ci/allow/branding.allow`, `tinkero.spec.in`, `dev`, `.github/workflows/ci.yml`, `tests/test-gates.sh` | `bash tests/test-gates.sh` at `1..58`; `./dev gates` five `PASS`; the payload has 88 wallpapers, none named `*omarchy*`, 20 named `*tinkero*`; `grep -c Omarchy` on the payload's string-literal scan equals the 8 allowlisted files; CI green including the SRPM |
| 8 Docs | small | docs | spec 4.13 and 8 amended with the measured facts and decisions, roadmap row, audit section 11 note, README, workflow guide | `docs/superpowers/specs/2026-09-17-tinkero-design.md`, `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, `docs/research/arch-coupling-audit.md`, `README.md`, `docs/guides/workflow.md` | `./dev check` green; no em dash in the edited text; the reviewer reads each edit against the design |

## File Structure

| File | Responsibility |
|---|---|
| `branding/mark.svg`, `branding/wordmark.svg` | the glyph and the wordmark, `fill="currentColor"`, a `viewBox`; placeholders until the real mark exists |
| `branding/icon.txt`, `branding/logo.txt` | the About screen logo (54 by 26) and the screensaver and presentation logo |
| `branding/README.md` | what each input is, its constraints, how to replace the placeholders and regenerate the ASCII files |
| `branding/rebuild-font` | Python, fontTools: replace the glyph at `U+E900` in place |
| `branding/strings.tsv`, `branding/apply-strings` | the substitution list and its count-checked applier |
| `branding/rewrite-manifests` | Python: `author`, `name`, `displayName`, `description` in the plugin manifests, formatting preserved |
| `branding/images.tsv` | one reviewed row per wallpaper: path, sha256, verdict |
| `branding/inventory-images`, `branding/contact-sheet`, `branding/render-wallpapers` | bash: write the rows, render the sheet for the review, apply the verdicts |
| `build/assemble` | step 3d |
| `ci/gate-branding`, `ci/allow/branding.allow` | the payload check and its shrink-only allowlist |
| `tests/test_branding.py` | the three Python tools (font cases skipped without fontTools) |
| `tests/test-branding.sh` | `inventory-images`, hermetic |
| `tests/test-branding-render.sh` | `render-wallpapers`, `contact-sheet` and assemble step 3d against fixtures; skips itself without ImageMagick or fontTools |
| `tests/test-gates.sh` | the gate's cases, appended |
| `menu/overrides.jsonc` | the two Learn rows |
| `tinkero.spec.in`, `dev`, `.github/workflows/ci.yml` | `BuildRequires`, the gate in `./dev gates`, the tools and ShellCheck list in CI |

Interfaces later plans rely on: `branding/images.tsv` and `branding/inventory-images` (the bump checklist's wallpaper loop), `branding/strings.tsv` (the bump checklist re-counts it), `$OMARCHY_PATH/icon.txt` and `logo.txt` (2E seeds the user copies from them), `omarchy.png` renamed to `tinkero.png` per theme (2F's Milestone B checklist looks for it in the rotation).

## Review Focus

Input classes the design implies that no requirement names; each has its test in the task that owns the code.

1. A real mark exported with `transform` attributes or several elements: fontTools' SVG reader applies no element transforms, so `rebuild-font` refuses a `transform` attribute with a message and accepts several path or shape elements; Task 2 tests both.
2. A theme whose `colors.toml` writes hex in upper case (`flexoki-light` does) or lacks a key: `render-wallpapers` lowercases and refuses a missing key before writing anything; Task 6.
3. A wallpaper path with a space: the image list is tab-separated and every expansion is quoted; Task 6 inventories one, and the gate reads the list the same way.
4. A trailing comment on a code line (`x = "fine" -- Omarchy`): the gate's comment filter is line-based, so an unquoted mention after code is not a finding, and a quoted one is (and would be allowlisted); Task 7 tests the first.
5. An upstream bump that adds a wallpaper or changes one: `inventory-images` gives it a `review` row and the build refuses that row until a person has looked; Task 6 tests both transitions, Task 7 tests the gate's refusal.

---

### Task 1: Placeholder artwork and `branding/README.md`

**Files:**
- Create: `branding/mark.svg`, `branding/wordmark.svg`, `branding/logo.txt`, `branding/icon.txt`, `branding/README.md`

**Interfaces:**
- Produces: the four artwork files every later task reads (`mark.svg` for Task 2 and step 3d's `icon.png`; `wordmark.svg` for Task 6 and `logo.svg`; the two `.txt` files for step 3d). Constraints per the design, section 3: one SVG with a `viewBox`, paths and basic shapes, `fill="currentColor"`, no `transform` attributes; `icon.txt` at most 54 by 26.

- [ ] **Step 1: The mark**

`branding/mark.svg`, exactly this one line and a trailing newline (a bold "T" in a 1024 by 1024 box; the crossbar is 192 tall, the stem 256 wide):

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><path fill="currentColor" d="M96 128H928V320H640V896H384V320H96Z"/></svg>
```

- [ ] **Step 2: The wordmark and the two ASCII renderings, generated from one grid**

Run this once from the repo root (it is not checked in; the grid is the source of the three files, and the sha256s in Step 4 pin the result):

```bash
python3 - <<'EOF'
G = {
    'T': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    'I': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    'N': ["#...#", "##..#", "##..#", "#.#.#", "#..##", "#..##", "#...#"],
    'K': ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    'R': ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    'O': [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
}
rows = [".".join(G[ch][r] for ch in "TINKERO") for r in range(7)]
W, H, cell = len(rows[0]), 7, 40
rects = []
for y, row in enumerate(rows):
    x = 0
    while x < W:
        if row[x] == '#':
            x0 = x
            while x < W and row[x] == '#':
                x += 1
            rects.append((x0, y, x - x0))
        else:
            x += 1
svg = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">' % (W * cell, H * cell),
       '  <!-- Tinkero placeholder wordmark: block letters on a 5x7 grid, 40 units a cell. Replace with the real mark; keep fill="currentColor". -->',
       '  <g fill="currentColor">']
for x0, y, w in rects:
    svg.append('    <rect x="%d" y="%d" width="%d" height="%d"/>' % (x0 * cell, y * cell, w * cell, cell))
svg += ['  </g>', '</svg>']
open('branding/wordmark.svg', 'w').write("\n".join(svg) + "\n")
logo = [''.join('██' if c == '#' else '  ' for c in row).rstrip() for row in rows]
open('branding/logo.txt', 'w').write("\n".join(logo) + "\n")
icon = ['█' * 54 if y < 6 else ' ' * 19 + '█' * 16 for y in range(26)]
open('branding/icon.txt', 'w').write("\n".join(icon) + "\n")
print(len(rects), "rects")
EOF
```

Expected: `73 rects`. The wordmark is 41 cells wide (1640 units) by 7 (280); `logo.txt` is the same grid at two columns a cell; `icon.txt` is the "T" at the About screen's size.

- [ ] **Step 3: The README**

`branding/README.md`:

```markdown
# Branding inputs

Everything a user sees that used to say or show Omarchy is generated at build time from
this directory (design spec 4.13; plan 2D, `docs/superpowers/plans/2026-09-23-phase-2d-branding.md`).
Identifiers (`omarchy-*` commands, paths, plugin ids, the font family name) keep upstream's names.

| File | Used for | Constraints |
|---|---|---|
| `mark.svg` | the glyph at `U+E900` of the icon font (the bar's menu button, the "Packages" row), `icon.png` | one SVG with a `viewBox`; `<path>` and the basic shapes (`rect`, `circle`, `ellipse`, `polygon`, `line`); no `transform` attributes (flatten them first); `fill="currentColor"`; monochrome, the shell colours it |
| `wordmark.svg` | the flat wallpaper of every theme that ships one (rendered in the theme's accent on its background), `logo.svg` | same rules; `currentColor` is replaced by the accent before rendering |
| `icon.txt` | the About screen's logo (seeded to `~/.config/omarchy/branding/about.txt`) | at most 54 columns by 26 rows |
| `logo.txt` | the screensaver and the floating-terminal presentation screens | at most 26 rows; width is free |
| `strings.tsv` | exact upstream strings replaced during the build: `file`, `upstream`, `replacement`, `count`, tab-separated, file relative to the upstream tree | the build fails unless every row matches its count |
| `images.tsv` | every wallpaper in the upstream tree with a person's verdict: `keep`, `regenerate` (a flat wordmark, rendered anew), `delete`, or `review` (not looked at yet; the build refuses it) | regenerate the rows with `branding/inventory-images`, look at the images with `branding/contact-sheet` |

The tools (`rebuild-font`, `apply-strings`, `rewrite-manifests`, `render-wallpapers`) are run by
`build/assemble` step 3d and never carry a name, a string or a verdict of their own.

## The artwork is a placeholder

`mark.svg` is a block "T" and `wordmark.svg` is "TINKERO" in block letters; the two text files
are the same shapes in block characters. To replace them with the real mark:

1. Drop in `mark.svg` and `wordmark.svg` (constraints above).
2. Regenerate the text renderings with upstream's own tool from an assembled payload
   (`./dev payload`; needs ImageMagick):

   ```bash
   PATH=$PWD/.cache/payload/usr/bin:$PATH omarchy-transcode-ascii branding/mark.svg branding/icon.txt --width 54 --height 26 --mode block
   PATH=$PWD/.cache/payload/usr/bin:$PATH omarchy-transcode-ascii branding/wordmark.svg branding/logo.txt --width 82 --height 10 --mode block
   ```

3. `./dev gates`: the font, the wallpapers, `icon.png` and `logo.svg` are rendered from the
   SVGs at build time. Nothing else changes.

## Reviewing wallpapers after a bump

```bash
./dev payload
mkdir -p .cache/tree && tar -xzf .cache/omarchy-*.tar.gz -C .cache/tree --strip-components=1
branding/inventory-images .cache/tree branding/images.tsv     # new or changed images become "review"
branding/contact-sheet .cache/tree .cache/wallpapers.png       # look at them
```

Then edit the `review` rows: `keep` for an image with nothing branded, `regenerate` for a flat
wordmark on a plain background (the name must contain `omarchy`; the theme's `colors.toml`
supplies the colours), `delete` for anything else that shows upstream's marks.
```

- [ ] **Step 4: Verify**

Run: `sha256sum branding/mark.svg branding/wordmark.svg branding/logo.txt branding/icon.txt` Expected, in this order:

```
3683e506ffd4aa1e8fcfe94c2f8a47a6de44184fa4f74c0830cef0988857cf74  branding/mark.svg
5a51ad1aa0b41944afb2bda9585f11c216d9b810ea5bdae35f3a12b548f5cdcf  branding/wordmark.svg
c7e65a9565bacedff5c3129b3f53b949b44ccb52e85357594af080d5aac9f7ec  branding/logo.txt
8e420a02654c469f4a3888f7dab25ebcd4007cf29fc52ae4d0bf780c4c76a419  branding/icon.txt
```

Run: `python3 -c 'import xml.etree.ElementTree as E; [print(E.parse(f).getroot().get("viewBox")) for f in ("branding/mark.svg", "branding/wordmark.svg")]'` Expected: `0 0 1024 1024` then `0 0 1640 280`.
Run: `for f in branding/logo.txt branding/icon.txt; do echo "$f $(wc -l < "$f") $(wc -L < "$f") $(grep -o '█' "$f" | wc -l)"; done` Expected: `branding/logo.txt 7 82 222` and `branding/icon.txt 26 54 644`.
Run: `grep -c "—" branding/README.md` Expected: `0`.

- [ ] **Step 5: Commit**

```bash
git add branding/mark.svg branding/wordmark.svg branding/logo.txt branding/icon.txt branding/README.md
git commit -m "branding: placeholder mark, wordmark and ASCII renderings, generated from one grid"
```

**Verification for the issue:** Step 4's commands. The sha256s pin the placeholder; a different value means the generator or the mark line was not copied exactly.

---

### Task 2: `rebuild-font`

**Files:**
- Create: `branding/rebuild-font`, `tests/test_branding.py`

**Interfaces:**
- Consumes: `branding/mark.svg` (Task 1).
- Produces: `rebuild-font IN.ttf MARK.svg OUT.ttf`, exit 0 and a one-line report on success, exit 1 with `rebuild-font: <reason>` otherwise, nothing written on failure. Step 3d (Task 7) calls it with `OUT` as `IN` plus `.tinkero` and moves the result over the original. `tests/test_branding.py` is created here with the shared helpers; Tasks 3 and 4 append their classes.

- [ ] **Step 1: The failing tests**

`tests/test_branding.py`:

```python
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
```

Run: `python3 -m unittest discover -s tests -p 'test_*.py' -v 2>&1 | tail -n 3` (from the repo root; the start directory must be `tests`, not `.`) Expected: the six `RebuildFont` tests fail (`branding/rebuild-font` does not exist), the 14 menu tests pass; without fontTools the six are reported as skipped.

- [ ] **Step 2: The tool**

`branding/rebuild-font` (mode 0755):

```python
#!/usr/bin/env python3
"""rebuild-font IN.ttf MARK.svg OUT.ttf: put the Tinkero mark at U+E900 (design spec 4.13).

The glyph upstream draws its logo with is replaced in place, so every other glyph, the
cmap, the family name ("omarchy": BarWidget.qml and the menu's "iconFont" ask for it) and
the GSUB ligature that maps the letters o-m-a-r-c-h-y to that glyph are untouched. The mark
is scaled into the 64..960 box upstream's own omarchy-dev-font uses for the agent marks.
MARK.svg needs a viewBox; paths and basic shapes are read by fontTools' svgLib, which
applies no transform attributes, so those are refused. Requires python3-fonttools.
"""
import sys
import xml.etree.ElementTree as ET

try:
    from fontTools.pens.cu2quPen import Cu2QuPen
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    from fontTools.svgLib.path import SVGPath
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("rebuild-font: python3-fonttools is required")

CODEPOINT = 0xE900
ART_BOX = (64, 64, 960, 960)   # the box every mark in the font is drawn in (omarchy-dev-font)


def fail(msg):
    sys.exit(f"rebuild-font: {msg}")


def viewbox(svg):
    root = ET.parse(svg).getroot()
    for el in root.iter():
        if el.get("transform"):
            fail(f"{svg}: a transform attribute on <{el.tag.split('}')[-1]}> would be ignored; flatten the mark first")
    vb = root.get("viewBox")
    if not vb:
        fail(f"{svg}: no viewBox")
    x, y, w, h = (float(v) for v in vb.replace(",", " ").split())
    if w <= 0 or h <= 0:
        fail(f"{svg}: empty viewBox")
    return x, y, w, h


def main(argv):
    if len(argv) != 4:
        fail("usage: rebuild-font IN.ttf MARK.svg OUT.ttf")
    src, svg, out = argv[1:]
    font = TTFont(src)
    cmap = font.getBestCmap()
    if CODEPOINT not in cmap:
        fail(f"{src}: no glyph at U+{CODEPOINT:04X}")
    name = cmap[CODEPOINT]
    x0, y0, w, h = viewbox(svg)
    ax0, ay0, ax1, ay1 = ART_BOX
    scale = min((ax1 - ax0) / w, (ay1 - ay0) / h)
    # centre the mark in the art box; SVG y grows down and font y grows up, so flip y
    ox = ax0 + ((ax1 - ax0) - w * scale) / 2 - x0 * scale
    oy = ay0 + ((ay1 - ay0) - h * scale) / 2 + (y0 + h) * scale
    pen = TTGlyphPen(None)
    # no reverse_direction: with the y flip this yields clockwise outer contours, upstream's convention
    SVGPath(svg, transform=(scale, 0, 0, -scale, ox, oy)).draw(Cu2QuPen(pen, max_err=1.0))
    glyph = pen.glyph()
    if not glyph.numberOfContours:
        fail(f"{svg}: no contours found (paths and basic shapes only)")
    glyf = font["glyf"]
    glyf[name] = glyph
    glyph.recalcBounds(glyf)
    font["hmtx"][name] = (font["head"].unitsPerEm, glyph.xMin)
    font.save(out)
    print(f"rebuild-font: U+{CODEPOINT:04X} ({name}) is now {glyph.numberOfContours} contour(s) "
          f"in ({glyph.xMin}, {glyph.yMin}, {glyph.xMax}, {glyph.yMax}); {len(cmap) - 1} other glyph(s) untouched")


if __name__ == "__main__":
    main(sys.argv)
```

- [ ] **Step 3: Verify**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' 2>&1 | tail -n 3` Expected: `Ran 20 tests`, `OK` (or `OK (skipped=6)` without fontTools; CI has it).

Real font (`./dev payload` first; the raw tree is needed, not the payload, because Task 7 rebuilds the payload's font):

```bash
mkdir -p .cache/tree && tar -xzf .cache/omarchy-*.tar.gz -C .cache/tree --strip-components=1
h=$(mktemp -d)
python3 branding/rebuild-font .cache/tree/default/fonts/omarchy/omarchy.ttf branding/mark.svg "$h/out.ttf"
python3 - "$h/out.ttf" <<'EOF'
import sys
from fontTools.ttLib import TTFont
a, b = TTFont('.cache/tree/default/fonts/omarchy/omarchy.ttf'), TTFont(sys.argv[1])
same = [cp for cp, n in a.getBestCmap().items() if cp != 0xE900 and a['glyf'][n].compile(a['glyf']) == b['glyf'][n].compile(b['glyf'])]
g = b['glyf']['omarchy']
print(len(same), 'untouched;', b['name'].getDebugName(1), a.getBestCmap() == b.getBestCmap(), 'GSUB' in b, g.numberOfContours, (g.xMin, g.yMin, g.xMax, g.yMax))
EOF
rm -rf "$h"
```

Expected: `rebuild-font: U+E900 (omarchy) is now 1 contour(s) in (148, 176, 876, 848); 19 other glyph(s) untouched` then `19 untouched; omarchy True True 1 (148, 176, 876, 848)`.

- [ ] **Step 4: Commit**

```bash
git add branding/rebuild-font tests/test_branding.py
git commit -m "branding: rebuild-font replaces the U+E900 glyph in place with the mark"
```

**Verification for the issue:** Step 3's commands and their expected output, plus CI green.

---

### Task 3: `apply-strings` and `strings.tsv`

**Files:**
- Create: `branding/apply-strings`, `branding/strings.tsv`
- Modify: `tests/test_branding.py` (append the class at the `# Task 3 appends` marker)

**Interfaces:**
- Produces: `apply-strings TREE STRINGS.tsv`, exit 0 and `apply-strings: N row(s), M replacement(s) in K file(s)` on success; exit 1, `apply-strings: nothing written:` followed by one `line N: ...` per problem, and no file written otherwise. `strings.tsv` rows are `file<TAB>upstream<TAB>replacement<TAB>count`, `file` relative to the tree before relocation (D9). Step 3d (Task 7) and the gate's check 4 (Task 7) read the list.

- [ ] **Step 1: The failing tests**

Replace the line `# Task 3 appends class ApplyStrings here.` in `tests/test_branding.py` with:

```python
class ApplyStrings(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="tinkero-strings.")
        self.tree = os.path.join(self.tmp, "tree")
        write(os.path.join(self.tree, "a", "one.lua"), 'x = "Omarchy menu"\ny = "Omarchy menu"\n')
        write(os.path.join(self.tree, "two.qml"), 'text: "Pending Omarchy Updates"\n')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def tsv(self, *rows):
        path = os.path.join(self.tmp, "strings.tsv")
        write(path, "# comment line\n" + "".join("\t".join(r) + "\n" for r in rows))
        return path

    def run_tool(self, tsv):
        return subprocess.run([sys.executable, APPLY, self.tree, tsv], capture_output=True, text=True)

    def test_replaces_and_reports(self):
        r = self.run_tool(self.tsv(("a/one.lua", '"Omarchy menu"', '"Tinkero menu"', "2"), ("two.qml", "Omarchy", "Tinkero", "1")))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("apply-strings: 2 row(s), 3 replacement(s) in 2 file(s)", r.stdout)
        self.assertEqual(read(os.path.join(self.tree, "a", "one.lua")), 'x = "Tinkero menu"\ny = "Tinkero menu"\n')
        self.assertEqual(read(os.path.join(self.tree, "two.qml")), 'text: "Pending Tinkero Updates"\n')

    def test_count_mismatch_writes_nothing(self):
        r = self.run_tool(self.tsv(("a/one.lua", '"Omarchy menu"', '"Tinkero menu"', "2"), ("two.qml", "Omarchy", "Tinkero", "3")))
        self.assertEqual(r.returncode, 1)
        self.assertIn("nothing written", r.stderr)
        self.assertIn("line 3: two.qml contains 'Omarchy' 1 time(s), expected 3", r.stderr)
        self.assertEqual(read(os.path.join(self.tree, "a", "one.lua")), 'x = "Omarchy menu"\ny = "Omarchy menu"\n')

    def test_missing_file_is_reported(self):
        r = self.run_tool(self.tsv(("nope.lua", "Omarchy", "Tinkero", "1")))
        self.assertEqual(r.returncode, 1)
        self.assertIn("line 2: cannot read nope.lua", r.stderr)

    def test_second_run_fails(self):
        tsv = self.tsv(("two.qml", "Omarchy", "Tinkero", "1"))
        self.assertEqual(self.run_tool(tsv).returncode, 0)
        r = self.run_tool(tsv)
        self.assertEqual(r.returncode, 1)
        self.assertIn("0 time(s), expected 1", r.stderr)

    def test_malformed_row(self):
        r = self.run_tool(self.tsv(("two.qml", "Omarchy", "Tinkero")))
        self.assertEqual(r.returncode, 1)
        self.assertIn("line 2: expected 4 tab-separated fields, got 3", r.stderr)

    def test_shipped_list_is_well_formed(self):
        rows = [line.rstrip("\n").split("\t") for line in open(os.path.join(B, "strings.tsv"), encoding="utf-8")
                if line.strip() and not line.startswith("#")]
        self.assertEqual(len(rows), 5)
        for row in rows:
            self.assertEqual(len(row), 4, row)
            self.assertTrue(row[3].isdigit() and int(row[3]) >= 1, row)
            self.assertNotIn("Omarchy", row[2].replace("built on Omarchy", ""), row)
```

Run: `python3 -m unittest discover -s tests -p 'test_*.py' 2>&1 | tail -n 3` Expected: the six `ApplyStrings` tests fail.

- [ ] **Step 2: The list**

`branding/strings.tsv`. **Fields are separated by one tab character**; write it with the `printf` below rather than by hand, then check it with `cat -A` (each field boundary shows as `^I`). The fifth row's dash is upstream's list separator, matched as is (D13).

```bash
printf '%s\n' \
  '# branding/strings.tsv: exact upstream strings replaced during the build (design spec 4.13).' \
  '# file<TAB>upstream<TAB>replacement<TAB>count, file relative to the upstream tree before' \
  '# assemble step 4 relocates etc/. The build fails unless every row matches its count exactly,' \
  '# so an upstream rewording is caught at the bump. Fixed strings, no escapes, no tabs inside.' \
  $'default/hypr/bindings/utilities.lua\t"Omarchy menu"\t"Tinkero menu"\t2' \
  $'etc/fastfetch/config.jsonc\techo \\"Omarchy $version\\"\techo \\"Tinkero $version, built on Omarchy\\"\t1' \
  $'shell/plugins/bar/widgets/SystemUpdate.qml\t"Pending Omarchy Updates"\t"Pending Tinkero Updates"\t1' \
  $'shell/services/PluginRegistry.qml\treserved for first-party Omarchy plugins\treserved for first-party Tinkero plugins\t1' \
  $'default/fonts/omarchy/README.md\t`U+E900` — Omarchy\t`U+E900` — Tinkero, from branding/mark.svg (the build replaces the upstream mark)\t1' \
  > branding/strings.tsv
```

Run: `cat -A branding/strings.tsv | sed -n 6p` Expected: `etc/fastfetch/config.jsonc^Iecho \"Omarchy $version\"^Iecho \"Tinkero $version, built on Omarchy\"^I1$` (the backslashes are literal: that is how the JSON file spells its quotes).

- [ ] **Step 3: The tool**

`branding/apply-strings` (mode 0755):

```python
#!/usr/bin/env python3
"""apply-strings TREE STRINGS.tsv: the must-match substitution list (design spec 4.13).

Each row of STRINGS.tsv is  file<TAB>upstream<TAB>replacement<TAB>count  with file relative
to TREE. Every row is checked before anything is written: the file must exist and must
contain the upstream string exactly count times, else nothing is written and every
problem is listed. Matching is fixed-string, so an upstream rewording fails the build
at the bump instead of shipping the old name.
"""
import sys


def fail(msg):
    sys.exit(f"apply-strings: {msg}")


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 4:
                fail(f"{path} line {n}: expected 4 tab-separated fields, got {len(parts)}")
            file, old, new, count = parts
            if not file or not old:
                fail(f"{path} line {n}: file and upstream string must not be empty")
            if not count.isdigit() or int(count) < 1:
                fail(f"{path} line {n}: count must be a positive integer, got {count!r}")
            rows.append((n, file, old, new, int(count)))
    return rows


def main(argv):
    if len(argv) != 3:
        fail("usage: apply-strings TREE STRINGS.tsv")
    tree, tsv = argv[1], argv[2]
    rows = read_rows(tsv)
    if not rows:
        fail(f"no rows in {tsv}")
    texts, problems = {}, []
    for n, file, old, new, count in rows:
        if file not in texts:
            try:
                with open(f"{tree}/{file}", encoding="utf-8") as f:
                    texts[file] = f.read()
            except OSError as e:
                problems.append(f"line {n}: cannot read {file}: {e.strerror}")
                continue
        found = texts[file].count(old)
        if found != count:
            problems.append(f"line {n}: {file} contains {old!r} {found} time(s), expected {count}")
    if problems:
        fail("nothing written:\n  " + "\n  ".join(problems))
    for n, file, old, new, count in rows:
        texts[file] = texts[file].replace(old, new)
    for file, text in texts.items():
        with open(f"{tree}/{file}", "w", encoding="utf-8") as f:
            f.write(text)
    print(f"apply-strings: {len(rows)} row(s), {sum(r[4] for r in rows)} replacement(s) in {len(texts)} file(s)")


if __name__ == "__main__":
    main(sys.argv)
```

Note: `test_malformed_row` expects the message with the tsv's line number; `read_rows` fails on the first malformed row, before any file is read, which is the intended shape (a broken list is a list problem, not a tree problem).

- [ ] **Step 4: Verify**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' 2>&1 | tail -n 3` Expected: `Ran 26 tests`, `OK` (or `skipped=6`).

Real tree, on a copy (the raw tree from Task 2's Step 3):

```bash
h=$(mktemp -d); cp -a .cache/tree "$h/tree"
python3 branding/apply-strings "$h/tree" branding/strings.tsv
grep -c 'Tinkero menu' "$h/tree/default/hypr/bindings/utilities.lua"
grep -c 'Tinkero $version, built on Omarchy' "$h/tree/etc/fastfetch/config.jsonc"
python3 branding/apply-strings "$h/tree" branding/strings.tsv 2>&1 | grep -c 'expected'
rm -rf "$h"
```

Expected, in order: `apply-strings: 5 row(s), 6 replacement(s) in 5 file(s)`, `2`, `1`, `5` (the second run fails on all five rows, which is what makes the list a guard).

- [ ] **Step 5: Commit**

```bash
git add branding/apply-strings branding/strings.tsv tests/test_branding.py
git commit -m "branding: apply-strings and the must-match substitution list (five rows at v4.0.4)"
```

**Verification for the issue:** Step 4's commands and outputs, plus CI green.

---

### Task 4: `rewrite-manifests`

**Files:**
- Create: `branding/rewrite-manifests`
- Modify: `tests/test_branding.py` (append the class at the `# Task 4 appends` marker)

**Interfaces:**
- Produces: `rewrite-manifests TREE`, exit 0 and `rewrite-manifests: N manifests, K rewritten: A author(s), F field(s)`; exit 1 with `rewrite-manifests: <path>: <reason>` and that file untouched when a value cannot be replaced safely. Step 3d (Task 7) calls it after the font and before the substitution list.

- [ ] **Step 1: The failing tests**

Replace the line `# Task 4 appends class RewriteManifests here.` in `tests/test_branding.py` with:

```python
class RewriteManifests(unittest.TestCase):
    MENU = ('{\n  "schemaVersion": 1,\n  "id": "omarchy.menu",\n  "name": "Omarchy menu",\n  "author": "Omarchy",\n'
            '  "description": "Quickshell-powered Omarchy command menu",\n  "kinds": ["menu", "bar-widget"],\n'
            '  "barWidget": {\n    "displayName": "Omarchy menu",\n    "description": "Launches the Omarchy menu"\n  }\n}\n')
    OTHER = '{\n  "id": "someone.widget",\n  "name": "Weather",\n  "author": "Someone"\n}\n'

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="tinkero-manifests.")
        self.plugins = os.path.join(self.tmp, "shell", "plugins")
        self.menu = os.path.join(self.plugins, "menu", "manifest.json")
        self.other = os.path.join(self.plugins, "other", "manifest.json")
        write(self.menu, self.MENU)
        write(self.other, self.OTHER)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_tool(self, tree=None):
        return subprocess.run([sys.executable, MANIFESTS, tree or self.tmp], capture_output=True, text=True)

    def test_author_and_fields(self):
        r = self.run_tool()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("rewrite-manifests: 2 manifests, 1 rewritten: 1 author(s), 4 field(s)", r.stdout)
        expected = (self.MENU.replace('"author": "Omarchy"', '"author": "Tinkero (from Omarchy)"')
                    .replace("Omarchy menu", "Tinkero menu").replace("Omarchy command", "Tinkero command"))
        self.assertEqual(read(self.menu), expected)          # ids, key order and the one-line array survive

    def test_untouched_manifest_keeps_its_bytes(self):
        self.run_tool()
        self.assertEqual(read(self.other), self.OTHER)

    def test_widget_manifest_with_a_repeated_value(self):
        widget = os.path.join(self.plugins, "bar", "widgets", "SystemUpdate.manifest.json")
        write(widget, '{\n  "id": "omarchy.system-update",\n  "name": "Omarchy update",\n  "author": "Omarchy",\n'
                      '  "barWidget": {\n    "displayName": "Omarchy update"\n  }\n}\n')
        r = self.run_tool()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(read(widget).count('"Tinkero update"'), 2)
        self.assertIn('"id": "omarchy.system-update"', read(widget))

    def test_value_that_also_names_the_plugin_is_refused(self):
        bad = os.path.join(self.plugins, "bad", "manifest.json")
        write(bad, '{\n  "id": "omarchy.bad",\n  "name": "Omarchy",\n  "author": "Omarchy"\n}\n')
        r = self.run_tool()
        self.assertEqual(r.returncode, 1)
        self.assertIn("bad/manifest.json", r.stderr)
        self.assertEqual(read(bad), '{\n  "id": "omarchy.bad",\n  "name": "Omarchy",\n  "author": "Omarchy"\n}\n')

    def test_unlisted_fields_are_left_alone(self):
        extra = os.path.join(self.plugins, "extra", "manifest.json")
        write(extra, '{\n  "id": "omarchy.extra",\n  "homepage": "https://omarchy.org/Omarchy",\n  "author": "Omarchy"\n}\n')
        self.run_tool()
        self.assertIn('"homepage": "https://omarchy.org/Omarchy"', read(extra))
        self.assertIn('"author": "Tinkero (from Omarchy)"', read(extra))

    def test_second_run_is_a_noop(self):
        self.run_tool()
        after = read(self.menu)
        r = self.run_tool()
        self.assertIn("2 manifests, 0 rewritten: 0 author(s), 0 field(s)", r.stdout)
        self.assertEqual(read(self.menu), after)

    def test_tree_without_manifests_fails(self):
        r = self.run_tool(os.path.join(self.tmp, "nowhere"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("no plugin manifests", r.stderr)
```

Run: `python3 -m unittest discover -s tests -p 'test_*.py' 2>&1 | tail -n 3` Expected: the seven `RewriteManifests` tests fail.

- [ ] **Step 2: The tool**

`branding/rewrite-manifests` (mode 0755):

```python
#!/usr/bin/env python3
"""rewrite-manifests TREE: rebrand the plugin manifests without touching plugin ids (spec 4.13).

For every shell/plugins/**/manifest.json and shell/plugins/**/*.manifest.json under TREE:
  * "author": "Omarchy" becomes "Tinkero (from Omarchy)";
  * the word Omarchy becomes Tinkero in name, displayName and description, at the top
    level and under barWidget.
Nothing else changes: each new value replaces the JSON encoding of the old value in the
file's text (exactly as often as fields carry that value), so upstream's formatting survives
byte for byte, and the result is parsed again and compared with the intended object before
it is written. Ids are never read.
"""
import glob
import json
import os
import re
import sys
from collections import Counter

AUTHOR_OLD, AUTHOR_NEW = "Omarchy", "Tinkero (from Omarchy)"
WORD = re.compile(r"\bOmarchy\b")
FIELDS = ("name", "displayName", "description")


def fail(msg):
    sys.exit(f"rewrite-manifests: {msg}")


def new_value(old):
    """The text-level replacement for an encoded value: the author's wording for the author's
    value, the word swap for everything else. A field whose intended value differs (a name
    that is exactly "Omarchy", say) is caught by the parse check in rewrite()."""
    return AUTHOR_NEW if old == AUTHOR_OLD else WORD.sub("Tinkero", old)


def changes(obj):
    """[(container, key, old, new)] for the fields this transform owns."""
    out = []
    if obj.get("author") == AUTHOR_OLD:
        out.append((obj, "author", AUTHOR_OLD, AUTHOR_NEW))
    widget = obj.get("barWidget") if isinstance(obj.get("barWidget"), dict) else {}
    for container in (obj, widget):
        for key in FIELDS:
            old = container.get(key)
            if isinstance(old, str) and WORD.search(old):
                out.append((container, key, old, WORD.sub("Tinkero", old)))
    return out


def rewrite(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    obj = json.loads(raw)
    todo = changes(obj)
    if not todo:
        return 0, 0
    text = raw
    # The same value may sit in two fields (a widget's name and displayName, say): the encoded
    # old value must occur exactly as often as the fields that carry it, then all are replaced.
    for old, n in Counter(old for _, _, old, _ in todo).items():
        enc = json.dumps(old, ensure_ascii=False)
        if text.count(enc) != n:
            fail(f"{path}: {enc} occurs {text.count(enc)} time(s) in the text, expected {n}; cannot replace it safely")
        text = text.replace(enc, json.dumps(new_value(old), ensure_ascii=False))
    for container, key, old, new in todo:
        container[key] = new
    if json.loads(text) != obj:
        fail(f"{path}: the rewritten text does not parse to the intended manifest")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    authors = sum(1 for c in todo if c[1] == "author")
    return authors, len(todo) - authors


def main(argv):
    if len(argv) != 2:
        fail("usage: rewrite-manifests TREE")
    root = os.path.join(argv[1], "shell", "plugins")
    files = sorted(set(glob.glob(os.path.join(root, "**", "manifest.json"), recursive=True))
                   | set(glob.glob(os.path.join(root, "**", "*.manifest.json"), recursive=True)))
    if not files:
        fail(f"no plugin manifests under {root}")
    authors = fields = touched = 0
    for path in files:
        a, f = rewrite(path)
        authors += a
        fields += f
        touched += bool(a or f)
    print(f"rewrite-manifests: {len(files)} manifests, {touched} rewritten: {authors} author(s), {fields} field(s)")


if __name__ == "__main__":
    main(sys.argv)
```

Why `test_value_that_also_names_the_plugin_is_refused` fails the way it does: `"Omarchy"` is both the author and the name, so the encoded value occurs twice for two fields and both are replaced in the text with the author's wording, while the intended object has `name` as `"Tinkero"`; the parse check sees the difference and refuses. No manifest at `v4.0.4` has that shape; the check exists so that one never gets half-rewritten.

- [ ] **Step 3: Verify**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' 2>&1 | tail -n 3` Expected: `Ran 33 tests`, `OK` (or `skipped=6`).

Real tree, on a copy:

```bash
h=$(mktemp -d); cp -a .cache/tree "$h/tree"
python3 branding/rewrite-manifests "$h/tree"
grep -rh '"author"' "$h/tree/shell/plugins" --include='*.json' | sort | uniq -c
grep -rn 'Omarchy' "$h/tree/shell/plugins" --include='*.json' | grep -vc '"author"'
diff <(grep -rh '"id"' .cache/tree/shell/plugins --include='*.json' | sort) <(grep -rh '"id"' "$h/tree/shell/plugins" --include='*.json' | sort) && echo ids-same
python3 branding/rewrite-manifests "$h/tree"
rm -rf "$h"
```

Expected, in order: `rewrite-manifests: 37 manifests, 36 rewritten: 36 author(s), 11 field(s)`; `     36   "author": "Tinkero (from Omarchy)",`; `0`; `ids-same`; `rewrite-manifests: 37 manifests, 0 rewritten: 0 author(s), 0 field(s)`.

- [ ] **Step 4: Commit**

```bash
git add branding/rewrite-manifests tests/test_branding.py
git commit -m "branding: rewrite-manifests rebrands author and display strings, ids and formatting untouched"
```

**Verification for the issue:** Step 3's commands and outputs, plus CI green.

---

### Task 5: The Learn rows

**Files:**
- Modify: `menu/overrides.jsonc` (one `replace` row added, one `add` row's action changed)

**Interfaces:**
- Consumes: 2C's `replace` and `add` keys and `expect_rows`.
- Produces: the built menu's `learn.omarchy` row with label "Tinkero" and the `U+E900` glyph; `learn.fedora` through `omarchy-launch-browser` (D5).

- [ ] **Step 1: Edit the file with a script, not by hand**

The `U+E900` glyph is a private-use character that editing tools have silently dropped before (2C's Deviations). Write the rows with Python so the glyph is spelled as an escape:

```bash
python3 - <<'EOF'
p = "menu/overrides.jsonc"
s = open(p, encoding="utf-8").read()
old_replace = '''  "replace": {
    // update.omarchy ran omarchy-update; Tinkero updates through dnf, mise and flatpak (spec 4.7)
'''
new_replace = '''  "replace": {
    // learn.omarchy opened the Omarchy manual; the id stays (identifiers keep upstream's names, spec 4.13),
    // the label and the target are Tinkero's, the glyph is the rebranded U+E900 (plan 2D)
    "learn.omarchy": {"icon":"\ue900","iconFont":"omarchy","label":"Tinkero","action":"omarchy-launch-browser https://github.com/dromeropa/tinkero#readme"},
    // update.omarchy ran omarchy-update; Tinkero updates through dnf, mise and flatpak (spec 4.7)
'''
assert old_replace in s, "replace block anchor not found"
s = s.replace(old_replace, new_replace)
old_fedora = '''"action":"omarchy-launch-webapp 'https://docs.fedoraproject.org/'"}'''
new_fedora = '''"action":"omarchy-launch-browser https://docs.fedoraproject.org/"}'''
assert s.count(old_fedora) == 1, "learn.fedora row not found"
# omarchy-launch-webapp falls back to chromium.desktop unless the default browser is Chrome-like;
# omarchy-launch-browser opens the default browser (design 2D, D5)
s = s.replace(old_fedora, new_fedora)
open(p, "w", encoding="utf-8").write(s)
EOF
```

- [ ] **Step 2: Verify**

Run: `python3 -c "s=open('menu/overrides.jsonc',encoding='utf-8').read(); print(s.count(''), s.count('omarchy-launch-browser'), s.count('omarchy-launch-webapp'))"` Expected: `2 2 0`.
Run: `./dev check` Expected: green (the fixture menu tests do not read the real overrides).
Run: `./dev payload 2>&1 | grep 'rows out'` Expected: `apply-overrides: 333 rows in, 75 deleted by prefix, 1 deleted for a dropped command, 2 replaced, 1 added, 258 rows out`.
Run: `grep -c '"learn.omarchy": {"icon":"","iconFont":"omarchy","label":"Tinkero","action":"omarchy-launch-browser https://github.com/dromeropa/tinkero#readme"}' .cache/payload/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc` (the glyph between the first pair of quotes is `U+E900`; paste it from the `update.omarchy` row if the terminal shows it as blank) Expected: `1`.
Run: `grep -c 'omarchy-launch-browser https://docs.fedoraproject.org/' .cache/payload/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc` Expected: `1`.
Run: `node -e 'const fs=require("fs");const raw=fs.readFileSync(".cache/payload/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc","utf8");const j=raw.replace(/^\s*\/\/[^\n]*(\n|$)/gm,"").replace(/,(\s*[}\]])/g,"$1");console.log(Object.keys(JSON.parse(j)).length)'` Expected: `258` (upstream's own JSONC parse rule).

- [ ] **Step 3: Commit**

```bash
git add menu/overrides.jsonc
git commit -m "menu: learn.omarchy opens Tinkero's README as \"Tinkero\"; the two Learn rows use the default browser"
```

**Verification for the issue:** Step 2's commands and outputs, plus CI green.

---

### Task 6: Wallpapers (needs Diego's pass)

**Files:**
- Create: `branding/inventory-images`, `branding/contact-sheet`, `branding/render-wallpapers`, `branding/images.tsv`, `tests/test-branding.sh`, `tests/test-branding-render.sh`

**Interfaces:**
- Consumes: `branding/wordmark.svg` (Task 1); the tools of Tasks 2 to 4 (the assemble cases in `tests/test-branding-render.sh` copy them; those ten cases pass once Task 7 adds step 3d and fail until then, which is expected and stated below).
- Produces: `inventory-images TREE IMAGES.tsv` (writes the list; verdicts kept for unchanged files), `contact-sheet TREE OUT.png`, `render-wallpapers TREE IMAGES.tsv WORDMARK.svg` (exit 0 and `render-wallpapers: N wallpapers: K kept, R regenerated, D deleted`; exit 1 and `render-wallpapers: nothing written:` plus one line per problem otherwise). `images.tsv` rows: `path<TAB>sha256<TAB>verdict`, verdict `keep`, `regenerate`, `delete` or `review`. Step 3d and the gate (Task 7) read the list.

- [ ] **Step 1: The failing tests for the inventory (hermetic)**

`tests/test-branding.sh`:

```bash
#!/bin/bash
# branding/inventory-images against a fixture theme tree. Hermetic: no image tool is needed,
# the wallpapers are arbitrary bytes (the inventory reads only names and checksums).
source "$(dirname "$0")/lib.sh"
d=$(mktmp); t=$d/tree; inv=$ROOT/branding/inventory-images; tsv=$d/images.tsv
mkdir -p "$t/themes/alpha/backgrounds" "$t/themes/beta/backgrounds"
echo one > "$t/themes/alpha/backgrounds/1-one.png"
echo two > "$t/themes/alpha/backgrounds/2 two.jpg"
echo omarchy > "$t/themes/beta/backgrounds/omarchy.png"
rows() { grep -v '^#' "$tsv"; }

out=$("$inv" "$t" "$tsv")
assert_eq "$(rows | wc -l)" 3 "inventory: one row per wallpaper"
assert_eq "$(rows | cut -f3 | sort -u)" review "inventory: new rows are 'review'"
assert_eq "$(rows | cut -f1 | head -n1)" "themes/alpha/backgrounds/1-one.png" "inventory: rows are sorted by path"
assert_eq "$(rows | sed -n 2p | cut -f1)" "themes/alpha/backgrounds/2 two.jpg" "inventory: a space in the name is one field"
assert_eq "$(rows | sed -n 3p | cut -f2)" "$(sha256sum "$t/themes/beta/backgrounds/omarchy.png" | cut -d' ' -f1)" "inventory: the sha256 column"
assert_contains "$out" "3 wallpapers, 3 new, 0 changed, 0 gone; 3 to review" "inventory: the summary"
assert_eq "$(head -n1 "$tsv")" "# branding/images.tsv: every wallpaper in the upstream tree, reviewed by a person (design spec 4.13)." "inventory: the header comment"

sed -i 's/\treview$/\tkeep/; s|^\(themes/beta/backgrounds/omarchy.png\t[0-9a-f]*\t\)keep$|\1regenerate|' "$tsv"
echo changed > "$t/themes/alpha/backgrounds/1-one.png"
rm "$t/themes/alpha/backgrounds/2 two.jpg"
echo new > "$t/themes/beta/backgrounds/new.png"
out=$("$inv" "$t" "$tsv")
assert_eq "$(rows | grep -c .)" 3 "re-run: the gone row is dropped and the new row added"
assert_eq "$(rows | grep '^themes/beta/backgrounds/omarchy.png' | cut -f3)" regenerate "re-run: an unchanged file keeps its verdict"
assert_eq "$(rows | grep '^themes/alpha/backgrounds/1-one.png' | cut -f3)" review "re-run: a changed file goes back to review"
assert_eq "$(rows | grep '^themes/beta/backgrounds/new.png' | cut -f3)" review "re-run: a new file is review"
assert_eq "$(rows | grep -c '2 two.jpg')" 0 "re-run: a removed file loses its row"
assert_contains "$out" "3 wallpapers, 1 new, 1 changed, 1 gone; 2 to review" "re-run: the summary"

"$inv" "$d/nothing" "$tsv" >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" 1 "inventory: a tree without themes/ fails"
rm -rf "$d"; finish
```

Run: `bash tests/test-branding.sh` Expected: every case fails (the tool does not exist).

- [ ] **Step 2: `inventory-images`**

`branding/inventory-images` (mode 0755):

```bash
#!/bin/bash
# inventory-images TREE IMAGES.tsv: rewrite IMAGES.tsv from the wallpapers under TREE/themes.
# A row whose path and sha256 are unchanged keeps its verdict; a new or changed image gets
# 'review'; a row whose file is gone is dropped. Sorted, so the diff shows exactly what a bump
# changed. The verdicts themselves are a person's (branding/contact-sheet shows the images).
set -euo pipefail
export LC_ALL=C
[[ $# -eq 2 ]] || { echo "usage: inventory-images TREE IMAGES.tsv" >&2; exit 2; }
tree=$1; images=$2
[[ -d $tree/themes ]] || { echo "inventory-images: no themes/ under $tree" >&2; exit 1; }
declare -A old=()   # "=()" matters: bash 5.3 treats a never-assigned array as unbound under set -u
if [[ -f $images ]]; then
  while IFS=$'\t' read -r p h v; do
    [[ -z $p || $p == \#* ]] && continue
    old[$p]="$h"$'\t'"$v"
  done < "$images"
fi
new=0; changed=0; total=0
tmp=$(mktemp)
{
  echo "# branding/images.tsv: every wallpaper in the upstream tree, reviewed by a person (design spec 4.13)."
  echo "# path<TAB>sha256<TAB>verdict; verdict is keep, regenerate (a flat wordmark: rendered anew in the"
  echo "# theme's colours), delete, or review (not looked at yet: the build refuses it). Rewrite the rows"
  echo "# with branding/inventory-images after a bump; branding/contact-sheet renders the images."
  while IFS= read -r f; do
    rel=${f#"$tree"/}; h=$(sha256sum "$f" | cut -d' ' -f1); total=$((total + 1))
    if [[ -z ${old[$rel]:-} ]]; then v=review; new=$((new + 1))
    elif [[ ${old[$rel]%%$'\t'*} != "$h" ]]; then v=review; changed=$((changed + 1))
    else v=${old[$rel]#*$'\t'}; fi
    printf '%s\t%s\t%s\n' "$rel" "$h" "$v"
    # shellcheck disable=SC2016  # bash expands the subscript itself; single quotes keep a space in the key intact
    unset 'old[$rel]'
  done < <(find "$tree/themes" -path '*/backgrounds/*' -type f | sort)
} > "$tmp"
gone=${#old[@]}
mv "$tmp" "$images"
echo "inventory-images: $total wallpapers, $new new, $changed changed, $gone gone; $(grep -c $'\treview$' "$images" || true) to review"
```

Run: `bash tests/test-branding.sh` Expected: `1..14`, no `not ok`. Run: `shellcheck -x -e SC1090,SC1091 branding/inventory-images tests/test-branding.sh` Expected: clean.

- [ ] **Step 3: The failing tests for rendering and the sheet**

`tests/test-branding-render.sh`. The first three sections are this task's; section 4 (the assemble step) fails until Task 7 and is written here so that the file is complete.

```bash
#!/bin/bash
# branding/render-wallpapers, branding/contact-sheet and assemble step 3d against fixtures.
# Needs ImageMagick and python3-fonttools; without them the file skips itself (CI has both).
source "$(dirname "$0")/lib.sh"
if ! command -v magick >/dev/null || ! python3 -c 'import fontTools' 2>/dev/null; then
  echo "1..0 # skip ImageMagick and python3-fonttools are needed (sudo dnf install ImageMagick python3-fonttools)"; exit 0
fi
d=$(mktmp); B=$ROOT/branding
# one theme: a flat wordmark wallpaper, a numbered one, a keeper and one to delete
t=$d/tree; th=$t/themes/tokyo; mkdir -p "$th/backgrounds"
printf 'accent = "#7AA2F7"\nbackground = "#1a1b26"\n' > "$th/colors.toml"
magick -size 64x36 xc:'#1a1b26' "$th/backgrounds/omarchy.png"
magick -size 32x18 xc:'#1a1b26' "$th/backgrounds/3-omarchy.png"
magick -size 16x9 xc:red "$th/backgrounds/1-keep.png"
magick -size 16x9 xc:blue "$th/backgrounds/2-gone.jpg"
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 10"><rect fill="currentColor" width="40" height="10"/></svg>\n' > "$d/wordmark.svg"
tsv=$d/images.tsv; "$B/inventory-images" "$t" "$tsv" >/dev/null
verdict() { sed -i "s|^\(themes/tokyo/backgrounds/$1\t[0-9a-f]*\t\)[a-z]*$|\1$2|" "$tsv"; }
snapshot() { find "$t/themes" -type f | sort | tr '\n' ' '; }
render() { "$B/render-wallpapers" "$t" "$tsv" "$d/wordmark.svg" 2>&1; }
before=$(snapshot)

# 1. refusals leave the tree untouched
out=$(render) && rc=0 || rc=$?
assert_eq "$rc" 1 "render: unreviewed rows are refused"
assert_contains "$out" "not reviewed yet: themes/tokyo/backgrounds/1-keep.png" "render: and named"
assert_eq "$(snapshot)" "$before" "render: nothing written on refusal"
verdict omarchy.png regenerate; verdict 3-omarchy.png regenerate; verdict 1-keep.png keep; verdict 2-gone.jpg delete
magick -size 16x9 xc:green "$th/backgrounds/4-extra.png"
out=$(render) && rc=0 || rc=$?
assert_eq "$rc" 1 "render: a wallpaper without a row is refused"
assert_contains "$out" "no row" "render: and named"
rm "$th/backgrounds/4-extra.png"
magick -size 16x9 xc:yellow "$th/backgrounds/1-keep.png"
out=$(render) && rc=0 || rc=$?
assert_eq "$rc" 1 "render: a changed keeper is refused"
assert_contains "$out" "changed since it was reviewed" "render: and named"
magick -size 16x9 xc:red "$th/backgrounds/1-keep.png"
printf 'themes/tokyo/backgrounds/ghost.png\t0000\tkeep\n' >> "$tsv"
out=$(render) && rc=0 || rc=$?
assert_eq "$rc" 1 "render: a row without a file is refused"
assert_contains "$out" "row without a file" "render: and named"
sed -i '/ghost.png/d' "$tsv"
cp "$th/colors.toml" "$d/colors.bak"; printf 'background = "#1a1b26"\n' > "$th/colors.toml"
out=$(render) && rc=0 || rc=$?
assert_eq "$rc" 1 "render: a theme without an accent is refused before anything is written"
assert_contains "$out" "no 6-digit hex 'accent'" "render: and says which key"
cp "$d/colors.bak" "$th/colors.toml"
assert_eq "$(snapshot)" "$before" "render: still nothing written after the refusals"

# 2. success
out=$(render) && rc=0 || rc=$?
assert_eq "$rc" 0 "render: exit 0 once every row is decided"
assert_contains "$out" "4 wallpapers: 1 kept, 2 regenerated, 1 deleted" "render: the summary"
assert_no_path "$th/backgrounds/omarchy.png" "render: the flat source is gone"
assert_no_path "$th/backgrounds/2-gone.jpg" "render: the delete row is gone"
assert_file "$th/backgrounds/1-keep.png" "render: the keeper stays"
assert_file "$th/backgrounds/3-tinkero.png" "render: a numbered source keeps its number"
assert_eq "$(magick identify -format '%w %h' "$th/backgrounds/tinkero.png")" "64 36" "render: the source's pixel size"
assert_eq "$(magick "$th/backgrounds/tinkero.png" -format '%[hex:p{1,1}]' info: | cut -c1-6 | tr '[:upper:]' '[:lower:]')" "1a1b26" "render: the corner is the theme background"
top=$(magick "$th/backgrounds/tinkero.png" -format %c histogram:info:- | sort -rn | head -n2 | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:upper:]' '[:lower:]' | sort | tr '\n' ' ')
assert_eq "$top" "1a1b26 7aa2f7 " "render: the two most frequent colours are the background and the accent"

# 3. the contact sheet
out=$("$B/contact-sheet" "$t" "$d/sheet.png" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "sheet: renders"
assert_eq "$(magick identify -format '%m' "$d/sheet.png")" PNG "sheet: a PNG"
assert_contains "$out" "3 wallpapers on $d/sheet.png" "sheet: counts the wallpapers"

# 4. assemble step 3d on the fixture tree, with a private root that has branding/ (Task 7)
tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src"); src=$d/src/omarchy-fixture
python3 - "$src/default/fonts/omarchy/omarchy.ttf" <<'PY'
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
def square(x0, y0, x1, y1):
    p = TTGlyphPen(None); p.moveTo((x0, y0)); p.lineTo((x0, y1)); p.lineTo((x1, y1)); p.lineTo((x1, y0)); p.closePath(); return p.glyph()
fb = FontBuilder(1024, isTTF=True)
fb.setupGlyphOrder([".notdef", "omarchy", "pi"]); fb.setupCharacterMap({0xE900: "omarchy", 0xE901: "pi"})
fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "omarchy": square(0, 0, 1024, 1024), "pi": square(64, 64, 960, 960)})
fb.setupHorizontalMetrics({".notdef": (1024, 0), "omarchy": (1024, 0), "pi": (1024, 64)}); fb.setupHorizontalHeader(ascent=1024, descent=0)
fb.setupNameTable({"familyName": "omarchy", "styleName": "Regular"}); fb.setupOS2(); fb.setupPost(); fb.save(sys.argv[1])
PY
mkdir -p "$src/shell/plugins/menu" "$src/themes/tokyo/backgrounds" "$src/default/hypr/bindings"
printf '{\n  "id": "omarchy.menu",\n  "name": "Omarchy menu",\n  "author": "Omarchy"\n}\n' > "$src/shell/plugins/menu/manifest.json"
cp "$th/colors.toml" "$src/themes/tokyo/colors.toml"
magick -size 64x36 xc:'#1a1b26' "$src/themes/tokyo/backgrounds/omarchy.png"; magick -size 16x9 xc:red "$src/themes/tokyo/backgrounds/1-keep.png"
printf 'o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle")\n' > "$src/default/hypr/bindings/utilities.lua"
for f in logo.txt icon.txt logo.svg icon.png; do echo upstream > "$src/$f"; done
tar -C "$d/src" -czf "$tb" omarchy-fixture
r=$d/root; mkdir -p "$r"/{build,session,distro/fedora/lib,branding}
printf 'migrations\n' > "$r/build/drop.list"; cp "$ROOT/session/tinkero.desktop" "$r/session/"
printf '# lib\n' > "$r/distro/fedora/lib/pkg.sh"; printf 'foot\tdnf\tfoot\n' > "$r/distro/fedora/pkgmap.tsv"; printf 'omarchy_tag=v0\n' > "$r/upstream.lock"
cp "$B"/rebuild-font "$B"/rewrite-manifests "$B"/apply-strings "$B"/render-wallpapers "$B"/inventory-images "$B"/mark.svg "$r/branding/"
cp "$d/wordmark.svg" "$r/branding/wordmark.svg"; echo 'T logo' > "$r/branding/logo.txt"; echo 'T icon' > "$r/branding/icon.txt"
printf 'default/hypr/bindings/utilities.lua\t"Omarchy menu"\t"Tinkero menu"\t1\netc/fastfetch/config.jsonc\tOmarchy\tTinkero\t1\n' > "$r/branding/strings.tsv"
"$B/inventory-images" "$src" "$r/branding/images.tsv" >/dev/null
sed -i 's|^\(themes/tokyo/backgrounds/omarchy.png\t[0-9a-f]*\t\)review$|\1regenerate|; s/\treview$/\tkeep/' "$r/branding/images.tsv"
out=$(TINKERO_ROOT=$r "$ROOT/build/assemble" "$tb" "$d/dest" 2>&1) && rc=0 || rc=$?
o=$d/dest/usr/share/omarchy
assert_eq "$rc" 0 "assemble: step 3d runs on a root with branding/"
assert_eq "$(python3 -c 'from fontTools.ttLib import TTFont; import sys; g=TTFont(sys.argv[1])["glyf"]["omarchy"]; print(g.numberOfContours, g.xMin)' "$d/dest/usr/share/fonts/omarchy/omarchy.ttf" 2>/dev/null)" "1 148" "assemble: the shipped font carries the mark at U+E900"
assert_eq "$(grep -c '"author": "Tinkero (from Omarchy)"' "$o/shell/plugins/menu/manifest.json" 2>/dev/null)" 1 "assemble: manifests rewritten"
assert_eq "$(grep -c 'Tinkero menu' "$o/default/hypr/bindings/utilities.lua" 2>/dev/null)" 1 "assemble: substitution list applied"
assert_eq "$(cat "$d/dest/usr/share/tinkero/fastfetch/config.jsonc" 2>/dev/null)" '{"text":"Tinkero"}' "assemble: the fastfetch row is applied before the relocation"
assert_file "$o/themes/tokyo/backgrounds/tinkero.png" "assemble: the wallpaper is rendered"
assert_no_path "$o/themes/tokyo/backgrounds/omarchy.png" "assemble: and the source is gone"
assert_eq "$(cat "$o/logo.txt" 2>/dev/null)" "T logo" "assemble: logo.txt replaced"
assert_eq "$(magick identify -format '%w %h %m' "$o/icon.png" 2>/dev/null)" "300 300 PNG" "assemble: icon.png rendered from the mark"
assert_contains "$out" "apply-strings: 2 row(s), 2 replacement(s) in 2 file(s)" "assemble: the build log reports the substitutions"
rm -rf "$d"; finish
```

Run: `bash tests/test-branding-render.sh` Expected: sections 1 to 3 fail (`not ok`) because the tools do not exist; section 4's ten cases fail too and keep failing until Task 7. Without the tools the file prints its skip line and exits 0.

- [ ] **Step 4: `render-wallpapers` and `contact-sheet`**

`branding/render-wallpapers` (mode 0755). Every check runs before any write, including resolving the colours, so a refusal never leaves a half-applied tree:

```bash
#!/bin/bash
# render-wallpapers TREE IMAGES.tsv WORDMARK.svg: apply the reviewed wallpaper verdicts (design
# spec 4.13). Verdicts in IMAGES.tsv (path<TAB>sha256<TAB>verdict, path relative to TREE):
#   keep        the file stays; its sha256 must still match (a changed image is looked at again)
#   regenerate  a flat wordmark wallpaper: WORDMARK is rendered in the theme's accent on its
#               background (colors.toml), at the source's pixel size, under the source's name
#               with omarchy replaced by tinkero; then the source is deleted
#   delete      the file is removed
#   review      nobody has looked at it yet: the build stops (branding/contact-sheet helps)
# Every file under themes/*/backgrounds/ needs a row and every row needs a file. Every problem
# is listed before anything is written. Needs ImageMagick (magick).
set -euo pipefail
export LC_ALL=C
[[ $# -eq 3 ]] || { echo "usage: render-wallpapers TREE IMAGES.tsv WORDMARK.svg" >&2; exit 2; }
tree=$1; images=$2; wordmark=$3
die() { echo "render-wallpapers: $*" >&2; exit 1; }
[[ -d $tree/themes ]] || die "no themes/ under $tree"
[[ -r $images ]] || die "cannot read $images"
[[ -r $wordmark ]] || die "cannot read $wordmark"
command -v magick >/dev/null || die "ImageMagick (magick) is required"
fraction=${TINKERO_MARK_FRACTION:-41}   # wordmark width as a percentage of the canvas width; upstream's flat wallpapers measure 41

declare -A verdict=() sha=() accent=() bg=() present=()
n=0
while IFS=$'\t' read -r p h v; do
  n=$((n + 1))
  [[ -z $p || $p == \#* ]] && continue
  [[ -n $h && -n $v ]] || die "$images line $n is not 'path<TAB>sha256<TAB>verdict'"
  case $v in keep|regenerate|delete|review) ;; *) die "$images line $n: unknown verdict '$v'" ;; esac
  [[ -z ${verdict[$p]:-} ]] || die "$images line $n: duplicate row for $p"
  verdict[$p]=$v; sha[$p]=$h
done < "$images"

# color FILE KEY: the six-digit hex value of KEY in a colors.toml, lowercased; empty when absent
color() { sed -nE "s/^$2[[:space:]]*=[[:space:]]*\"(#[0-9A-Fa-f]{6})\".*/\1/p" "$1" | head -n1 | tr '[:upper:]' '[:lower:]'; }

problems=""
while IFS= read -r f; do
  rel=${f#"$tree"/}; present[$rel]=1
  if [[ -z ${verdict[$rel]:-} ]]; then problems+="  no row (run branding/inventory-images, then look at it): $rel"$'\n'; continue; fi
  [[ $(sha256sum "$f" | cut -d' ' -f1) == "${sha[$rel]}" ]] || problems+="  changed since it was reviewed (run branding/inventory-images, then look at it): $rel"$'\n'
  [[ ${verdict[$rel]} == review ]] && problems+="  not reviewed yet: $rel"$'\n'
  if [[ ${verdict[$rel]} == regenerate ]]; then
    [[ $rel == *omarchy* ]] || problems+="  regenerate needs 'omarchy' in the name to derive the output name: $rel"$'\n'
    theme=${rel#themes/}; theme=${theme%%/*}; toml=$tree/themes/$theme/colors.toml
    if [[ -f $toml ]]; then
      accent[$rel]=$(color "$toml" accent); bg[$rel]=$(color "$toml" background)
      [[ -n ${accent[$rel]} ]] || problems+="  themes/$theme/colors.toml: no 6-digit hex 'accent' (needed for $rel)"$'\n'
      [[ -n ${bg[$rel]} ]] || problems+="  themes/$theme/colors.toml: no 6-digit hex 'background' (needed for $rel)"$'\n'
    else
      problems+="  no colors.toml for the theme of $rel"$'\n'
    fi
  fi
done < <(find "$tree/themes" -path '*/backgrounds/*' -type f | sort)
for p in "${!verdict[@]}"; do [[ -n ${present[$p]:-} ]] || problems+="  row without a file (remove the row): $p"$'\n'; done
[[ -z $problems ]] || { echo "render-wallpapers: nothing written:" >&2; printf '%s' "$problems" >&2; exit 1; }

kept=0; rendered=0; deleted=0
while IFS= read -r p; do
  f=$tree/$p
  case ${verdict[$p]} in
    keep) kept=$((kept + 1)) ;;
    delete) rm -f -- "$f"; deleted=$((deleted + 1)) ;;
    regenerate)
      out=$tree/${p//omarchy/tinkero}
      read -r w h < <(magick identify -format '%w %h\n' "$f")
      tmp=$(mktemp --suffix=.svg)
      sed "s/currentColor/${accent[$p]}/g" "$wordmark" > "$tmp"
      # -background fills the SVG's transparent canvas and the -extent padding; PNG24 drops alpha
      magick -background "${bg[$p]}" -density 300 "$tmp" -resize "$((w * fraction / 100))x" \
        -gravity center -extent "${w}x${h}" -strip "PNG24:$out"
      rm -f -- "$tmp" "$f"
      rendered=$((rendered + 1)) ;;
  esac
done < <(printf '%s\n' "${!verdict[@]}" | sort)
echo "render-wallpapers: $((kept + rendered + deleted)) wallpapers: $kept kept, $rendered regenerated, $deleted deleted"
```

`branding/contact-sheet` (mode 0755):

```bash
#!/bin/bash
# contact-sheet TREE OUT.png: every wallpaper under TREE/themes on one labelled sheet, for the
# review that fills in branding/images.tsv. Needs ImageMagick (magick).
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: contact-sheet TREE OUT.png" >&2; exit 2; }
tree=$1; out=$2
command -v magick >/dev/null || { echo "contact-sheet: ImageMagick (magick) is required" >&2; exit 1; }
mapfile -d '' -t files < <(find "$tree/themes" -path '*/backgrounds/*' -type f -print0 | sort -z)
(( ${#files[@]} )) || { echo "contact-sheet: no wallpapers under $tree/themes" >&2; exit 1; }
args=()
for f in "${files[@]}"; do
  rel=${f#"$tree"/themes/}
  args+=( -label "${rel%%/*}: ${rel##*/}" "$f" )
done
# settings first, then the labelled images, then the layout: the montage idiom
magick montage -pointsize 16 -background '#808080' "${args[@]}" -tile 4x -geometry 480x270+6+6 "$out"
echo "contact-sheet: ${#files[@]} wallpapers on $out"
```

Run: `bash tests/test-branding-render.sh` Expected: sections 1 to 3 green (24 `ok`), section 4's ten cases still `not ok` (Task 7). Run: `shellcheck -x -e SC1090,SC1091 branding/render-wallpapers branding/contact-sheet tests/test-branding-render.sh` Expected: clean.

If a `magick` flag misbehaves (the invocations were written without running them; see Global Constraints), fix the script, not the assertions: the assertions state what the design requires (source size, background in the corner, the theme's two colours dominant).

- [ ] **Step 5: The list, then Diego's pass**

Generate the rows from the raw tree and set the 25 verdicts the design already knows (section 2 and D3):

```bash
branding/inventory-images .cache/tree branding/images.tsv
python3 - <<'EOF'
p = "branding/images.tsv"
regen = {"themes/flexoki-light/backgrounds/2-omarchy.png", "themes/lupine/backgrounds/06-omarchy.png"}
delete = {"themes/rose-pine/backgrounds/3-omarchy-plants.png", "themes/tokyo-night/backgrounds/1-quattro.jpg",
          "themes/tokyo-night/backgrounds/5-oma-cityscape.jpg", "themes/tokyo-night/backgrounds/6-oma.jpg"}
keep = {"themes/tokyo-night/backgrounds/4-omakub.jpg"}
out = []
for line in open(p, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        out.append(line); continue
    path, sha, verdict = line.rstrip("\n").split("\t")
    if path.endswith("/backgrounds/omarchy.png") or path in regen: verdict = "regenerate"
    elif path in delete: verdict = "delete"
    elif path in keep: verdict = "keep"
    out.append(f"{path}\t{sha}\t{verdict}\n")
open(p, "w", encoding="utf-8").write("".join(out))
EOF
cut -f3 branding/images.tsv | grep -v '^#' | sort | uniq -c
```

Expected: `4 delete`, `1 keep`, `20 regenerate`, `67 review`.

Then the sheet for Diego:

```bash
branding/contact-sheet .cache/tree .cache/wallpapers.png
```

**Diego replaces the 67 `review` verdicts** (`keep` for an image with nothing branded, `regenerate` for a flat wordmark whose name contains `omarchy`, `delete` for anything showing upstream's marks or third-party marks), on the task branch or as a comment on the issue that the implementer applies. Nothing else in this task can finish before that: `render-wallpapers` refuses `review` rows by design (D4). The sheet command needs ImageMagick; without a local install, the same montage runs in a `fedora:44` container with `dnf install ImageMagick` and the tree copied in.

- [ ] **Step 6: Verify on the real tree**

```bash
grep -c $'\treview$' branding/images.tsv
h=$(mktemp -d); cp -a .cache/tree "$h/tree"
branding/render-wallpapers "$h/tree" branding/images.tsv branding/wordmark.svg
find "$h/tree/themes" -path '*/backgrounds/*' -type f | wc -l
find "$h/tree/themes" -path '*/backgrounds/*omarchy*' | wc -l
find "$h/tree/themes" -path '*/backgrounds/*tinkero*' | wc -l
for f in "$h"/tree/themes/*/backgrounds/*tinkero*; do magick identify -format '%w %h\n' "$f"; done | sort -u
magick "$h/tree/themes/tokyo-night/backgrounds/tinkero.png" -format %c histogram:info:- | sort -rn | head -n2 | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:upper:]' '[:lower:]' | sort | tr '\n' ' '; echo
rm -rf "$h"
```

Expected, in order: `0`; `render-wallpapers: 92 wallpapers: 68 kept, 20 regenerated, 4 deleted` (68 assumes the review keeps all 67; each `delete` Diego adds lowers the first number and raises the third, and the issue records the final line); `88` (less any added deletions); `0`; `20`; `3840 2160`; `1a1b26 7aa2f7 ` (tokyo-night's `background` and `accent`).

Also: `bash tests/test-branding.sh` at `1..14` and `bash tests/test-branding-render.sh` with sections 1 to 3 green.

- [ ] **Step 7: Commit**

```bash
git add branding/inventory-images branding/contact-sheet branding/render-wallpapers branding/images.tsv tests/test-branding.sh tests/test-branding-render.sh
git commit -m "branding: wallpaper inventory, contact sheet and rendering from a reviewed image list (92 rows at v4.0.4)"
```

**Verification for the issue:** Step 6's commands and outputs; `images.tsv` has 92 rows and no `review`; the two test files as stated. The task is not done while a `review` row exists.

---

### Task 7: Build step, gate, packaging, CI

**Files:**
- Create: `ci/gate-branding`, `ci/allow/branding.allow`
- Modify: `build/assemble` (header comment; step 3d before `# 4. Relocate`), `tinkero.spec.in` (`BuildRequires`), `dev` (`gates()`), `.github/workflows/ci.yml` (tools, ShellCheck list), `tests/test-gates.sh` (append before `rm -rf "$d"; finish`)

**Interfaces:**
- Consumes: every `branding/` tool and data file (Tasks 1 to 6).
- Produces: `gate-branding DEST IMAGES STRINGS ALLOW` (exit 0 `PASS: branding (...)`, exit 1 with `FAIL:` lines, exit 2 on a missing input), run by `./dev gates` and CI; the rebranded payload under `.cache/payload`; `ci/allow/branding.allow` with its 8 entries.

- [ ] **Step 1: The failing gate tests**

Append to `tests/test-gates.sh`, before the final `rm -rf "$d"; finish` line:

```bash
# branding (plan 2D)
b=$d/brand; mkdir -p "$b/usr/bin" "$b/usr/share/omarchy/themes/t/backgrounds" "$b/usr/share/tinkero/fastfetch"
printf 'title: "Omarchy shell"\n' > "$b/usr/share/omarchy/gallery.qml"
printf -- '-- the "Omarchy" comment\nx = "fine" -- Omarchy trailing\n' > "$b/usr/share/omarchy/comment.lua"
printf '{"author": "Tinkero (from Omarchy)", "id": "omarchy.x", "n": "OmarchyFoo"}\n' > "$b/usr/share/omarchy/attrib.json"
printf '{"text": "Tinkero 1, built on Omarchy"}\n' > "$b/usr/share/tinkero/fastfetch/config.jsonc"
printf "y = 'org.omarchy.app'\n" > "$b/usr/share/omarchy/ids.js"
echo keep > "$b/usr/share/omarchy/themes/t/backgrounds/1-keep.png"
echo rendered > "$b/usr/share/omarchy/themes/t/backgrounds/tinkero.png"
keepsha=$(sha256sum "$b/usr/share/omarchy/themes/t/backgrounds/1-keep.png" | cut -d' ' -f1)
printf 'themes/t/backgrounds/1-keep.png\t%s\tkeep\nthemes/t/backgrounds/omarchy.png\t0\tregenerate\nthemes/t/backgrounds/old.jpg\t0\tdelete\n' "$keepsha" > "$d/images.tsv"
printf 'etc/fastfetch/config.jsonc\tOmarchy 1\tTinkero 1, built on Omarchy\t1\n' > "$d/strings.tsv"
G=$ROOT/ci/gate-branding
: > "$d/allow-b"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "branding: fails on a string literal"
assert_contains "$out" "usr/share/omarchy/gallery.qml" "branding: names the file"
for f in comment.lua attrib.json ids.js tinkero/fastfetch; do
  if [[ $out == *"$f"* ]]; then not_ok "branding: no finding for $f" "$out"; else ok "branding: no finding for $f"; fi
done
echo 'usr/share/omarchy/gallery.qml   # dev tool' > "$d/allow-b"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "branding: passes with the allowlist, a keep row and a rendered file"
assert_contains "$out" "PASS: branding" "branding: and says so"
echo 'usr/share/omarchy/stale.qml' >> "$d/allow-b"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "branding: a stale allowlist entry fails"
sed -i '/stale/d' "$d/allow-b"
echo x > "$b/usr/share/omarchy/themes/t/backgrounds/omarchy.png"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "branding: a wallpaper named for upstream fails"
assert_contains "$out" "still named for upstream" "branding: the name check"
assert_contains "$out" "present but marked regenerate" "branding: and the list check"
rm "$b/usr/share/omarchy/themes/t/backgrounds/omarchy.png"
echo extra > "$b/usr/share/omarchy/themes/t/backgrounds/9-extra.png"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_contains "$out" "no row in $d/images.tsv: themes/t/backgrounds/9-extra.png" "branding: a wallpaper without a row fails"
rm "$b/usr/share/omarchy/themes/t/backgrounds/9-extra.png"
echo changed > "$b/usr/share/omarchy/themes/t/backgrounds/1-keep.png"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_contains "$out" "changed since it was reviewed: themes/t/backgrounds/1-keep.png" "branding: a changed keeper fails"
echo keep > "$b/usr/share/omarchy/themes/t/backgrounds/1-keep.png"
printf 'themes/t/backgrounds/2-new.png\t0\treview\n' >> "$d/images.tsv"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_contains "$out" "not reviewed yet: themes/t/backgrounds/2-new.png" "branding: a review row fails"
sed -i '/2-new/d' "$d/images.tsv"
printf '{"text": "Omarchy 1"}\n' > "$b/usr/share/tinkero/fastfetch/config.jsonc"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_contains "$out" "still contains the upstream string" "branding: an unapplied etc/ row is looked up under usr/share/tinkero"
out=$("$G" "$d/no-payload" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "branding: fails loudly without a payload"
```

Run: `bash tests/test-gates.sh 2>&1 | tail -n 1` Expected: `1..58` with the 17 new cases `not ok`.

- [ ] **Step 2: The gate**

`ci/gate-branding` (mode 0755):

```bash
#!/bin/bash
# gate-branding DEST IMAGES STRINGS ALLOW: nothing a user sees in the payload says or
# shows Omarchy (design spec 4.13, section 8 item 4a). Four checks:
#   1. no capitalised "Omarchy" inside a string literal of a QML, JS, Lua, JSON, JSONC or
#      .desktop file, comment lines skipped, outside ALLOW (findings are file paths, and the
#      allowlist may only shrink, like the other gates);
#   2. no file named *omarchy* under a theme's backgrounds/;
#   3. every wallpaper in the payload is a `keep` row of IMAGES with the recorded sha256, or
#      a file rendered for a `regenerate` row; no `delete` or `regenerate` source is present;
#      no row is `review`;
#   4. no upstream string of STRINGS remains in its file, and its replacement is there.
set -euo pipefail
export LC_ALL=C
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); # shellcheck source=ci/lib-gate.sh
source "$here/lib-gate.sh"
[[ $# -eq 4 ]] || { echo "usage: gate-branding DEST IMAGES STRINGS ALLOW" >&2; exit 2; }
dest=$1; images=$2; strings=$3; allow=$4
[[ -d $dest/usr/bin ]] || { echo "FAIL: no payload at DEST (run ./dev payload first)"; exit 2; }
[[ -r $images ]] || { echo "FAIL: cannot read the image list: $images"; exit 2; }
[[ -r $strings ]] || { echo "FAIL: cannot read the substitution list: $strings"; exit 2; }
tree=$dest/usr/share/omarchy
rc=0

# 1. String literals. Comment lines (//, --, #) are dropped before matching, so a comment that
#    mentions upstream needs no allowlist entry; a string literal does. The two attribution
#    phrases the design keeps on purpose ("built on Omarchy", "from Omarchy") are not findings.
found=$(mktemp); trap 'rm -f "$found"' EXIT
lit='"[^"]*\bOmarchy\b[^"]*"|'"'"'[^'"'"']*\bOmarchy\b[^'"'"']*'"'"''
( cd "$dest" && find . -type f \( -name '*.qml' -o -name '*.js' -o -name '*.lua' -o -name '*.json' -o -name '*.jsonc' -o -name '*.desktop' \) | sort \
    | while IFS= read -r f; do
        # not grep -q: under pipefail an early exit turns the upstream grep's SIGPIPE into a failure
        hits=$(grep -vE '^\s*(//|--|#)' "$f" | sed -E 's/(built on|from) Omarchy//g' | grep -cE "$lit" || true)
        (( hits > 0 )) && echo "${f#./}"
      done ) > "$found" || true
compare_with_allowlist "$found" "$allow" "files with Omarchy in a string literal" || rc=1

# 2. Branded wallpaper names.
named=$(find "$tree/themes" -path '*/backgrounds/*' -iname '*omarchy*' 2>/dev/null | sed "s|^$dest/||" || true)
if [[ -n $named ]]; then echo "FAIL: wallpapers still named for upstream:"; printf '  %s\n' "${named//$'\n'/$'\n'  }"; rc=1; fi

# 3. The image list against the payload.
declare -A verdict=() sha=()
while IFS=$'\t' read -r p h v; do
  [[ -z $p || $p == \#* ]] && continue
  verdict[$p]=$v; sha[$p]=$h
done < "$images"
bad=""
while IFS= read -r f; do
  rel=${f#"$tree"/}
  if [[ -n ${verdict[$rel]:-} ]]; then
    case ${verdict[$rel]} in
      keep) [[ $(sha256sum "$f" | cut -d' ' -f1) == "${sha[$rel]}" ]] || bad+="  changed since it was reviewed: $rel"$'\n' ;;
      *) bad+="  present but marked ${verdict[$rel]}: $rel"$'\n' ;;
    esac
  else
    src=${rel//tinkero/omarchy}
    [[ $src != "$rel" && ${verdict[$src]:-} == regenerate ]] || bad+="  no row in $images: $rel"$'\n'
  fi
done < <(find "$tree/themes" -path '*/backgrounds/*' -type f 2>/dev/null | sort)
for p in "${!verdict[@]}"; do
  [[ ${verdict[$p]} == review ]] && bad+="  not reviewed yet: $p"$'\n'
done
if [[ -n $bad ]]; then echo "FAIL: wallpapers:"; printf '%s' "$bad"; rc=1; fi

# 4. The substitution list took effect (the build already failed if a count was off). Rows
#    under etc/ are looked up where assemble step 4 relocated the file.
while IFS=$'\t' read -r file old new _; do
  [[ -z $file || $file == \#* ]] && continue
  case $file in etc/*) target=$dest/usr/share/tinkero/${file#etc/} ;; *) target=$tree/$file ;; esac
  if [[ ! -f $target ]]; then echo "FAIL: strings.tsv names a file the payload lacks: $file"; rc=1; continue; fi
  n=$(grep -cF -- "$old" "$target" || true)
  if (( n > 0 )); then echo "FAIL: $file still contains the upstream string ($n line(s)): $old"; rc=1; fi
  n=$(grep -cF -- "$new" "$target" || true)
  if (( n == 0 )); then echo "FAIL: $file lacks the replacement: $new"; rc=1; fi
done < "$strings"

[[ $rc -eq 0 ]] && echo "PASS: branding (string literals, wallpaper names, $(grep -vc '^#' "$images") reviewed wallpapers, $(grep -vc '^#' "$strings") substitutions)"
exit $rc
```

Run: `bash tests/test-gates.sh 2>&1 | tail -n 1` Expected: `1..58`, no `not ok`. Run: `shellcheck -x -e SC1090,SC1091 ci/gate-branding tests/test-gates.sh` Expected: clean.

- [ ] **Step 3: Assemble step 3d**

In `build/assemble`, add to the header comment block after the `session/tinkero.desktop` line:

```bash
#   branding/{mark.svg,wordmark.svg,logo.txt,icon.txt,strings.tsv,images.tsv} + the branding/ tools
#                                        the mark into the font, the logo files, the plugin manifests,
#                                        the substitution list and the wallpapers (step 3d)
```

Immediately before the line `# 4. Relocate the two etc/ files Tinkero keeps, then drop the rest of etc/.` insert:

```bash
# 3d. Branding (design spec 4.13, plan 2D): the mark into the font, the logo files, the plugin
# manifests, the substitution list, the wallpapers. Data under branding/; every step fails when
# upstream moved something. Skipped when the root has no branding/strings.tsv (fixture roots).
if [[ -f $root/branding/strings.tsv ]]; then
  command -v magick >/dev/null || die "branding needs ImageMagick (magick)"
  python3 -c 'import fontTools' 2>/dev/null || die "branding needs python3-fonttools"
  for f in default/fonts/omarchy/omarchy.ttf logo.txt icon.txt logo.svg icon.png; do
    [[ -f $tree/$f ]] || die "upstream has no $f; decide where the branding goes before building"
  done
  font=$tree/default/fonts/omarchy/omarchy.ttf
  python3 "$root/branding/rebuild-font" "$font" "$root/branding/mark.svg" "$font.tinkero" || die "font rebuild failed"
  mv "$font.tinkero" "$font"
  install -m 0644 "$root/branding/logo.txt" "$tree/logo.txt"
  install -m 0644 "$root/branding/icon.txt" "$tree/icon.txt"
  install -m 0644 "$root/branding/wordmark.svg" "$tree/logo.svg"
  magick -background none -density 300 "$root/branding/mark.svg" -resize 300x300 -strip "$tree/icon.png" || die "icon.png render failed"
  python3 "$root/branding/rewrite-manifests" "$tree" || die "manifest rewrite failed"
  python3 "$root/branding/apply-strings" "$tree" "$root/branding/strings.tsv" || die "substitution list failed (see apply-strings output above)"
  "$root/branding/render-wallpapers" "$tree" "$root/branding/images.tsv" "$root/branding/wordmark.svg" || die "wallpaper rendering failed"
fi
```

Run: `bash tests/test-assemble.sh 2>&1 | tail -n 1` Expected: `1..37` unchanged (or 2E's count if 2E landed first): the fixture root has no `branding/`.
Run: `bash tests/test-branding-render.sh 2>&1 | tail -n 1` Expected: `1..34`, no `not ok` (section 4 now passes).

- [ ] **Step 4: Packaging, `dev`, CI**

`tinkero.spec.in`: change `BuildRequires:  git-core python3` to:

```
BuildRequires:  git-core python3 python3-fonttools ImageMagick
```

`dev`, in `gates()`, after the `gate-name-map` line:

```bash
  ci/gate-branding "$payload" branding/images.tsv branding/strings.tsv "$allow/branding.allow" || rc=1
```

`.github/workflows/ci.yml`: the Tools step becomes

```yaml
        run: dnf -y install git-core curl diffutils findutils ShellCheck rpmlint rpm-build rpmdevtools make nodejs python3 python3-fonttools ImageMagick
```

and in the ShellCheck step's folded `run: >` block, the line `ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/lib-gate.sh` becomes these two lines (the folded scalar joins them into the one command, so position only affects readability)

```yaml
          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/lib-gate.sh
          branding/render-wallpapers branding/inventory-images branding/contact-sheet
```

- [ ] **Step 5: The allowlist, from the real payload**

```bash
./dev payload
: > ci/allow/branding.allow
ci/gate-branding .cache/payload branding/images.tsv branding/strings.tsv ci/allow/branding.allow
```

Expected: the string-literal check fails naming exactly these eight files, and the other three checks pass:

```
usr/share/omarchy/default/chromium/extensions/copy-url/manifest.json
usr/share/omarchy/default/chromium/extensions/whatsapp-slim/manifest.json
usr/share/omarchy/default/chromium/extensions/yt-dlp/manifest.json
usr/share/omarchy/default/chromium/native-messaging-hosts/com.omarchy.copy_url.json
usr/share/omarchy/default/chromium/native-messaging-hosts/com.omarchy.ytdlp.json
usr/share/omarchy/default/hypr/apps/omarchy-shell.lua
usr/share/omarchy/default/hypr/apps/system.lua
usr/share/omarchy/shell/plugins/dev-gallery/GalleryPanel.qml
```

A ninth file means a step of 3d did not run or upstream has a string the design's table missed: read it before touching the list. Then write `ci/allow/branding.allow` by hand (not with `./dev baseline`, which would strip the comments of the other two allowlists):

```
# Baseline written by hand from the gate's findings on 2026-09-XX. Entries may only be removed, never added by hand.
# Each is a string a user does not see: design 2D, D7 (Chromium) and D8 (window rules, the dev gallery).
usr/share/omarchy/default/chromium/extensions/copy-url/manifest.json   # Chromium is a non-goal; not a Tinkero surface
usr/share/omarchy/default/chromium/extensions/whatsapp-slim/manifest.json   # same
usr/share/omarchy/default/chromium/extensions/yt-dlp/manifest.json   # same
usr/share/omarchy/default/chromium/native-messaging-hosts/com.omarchy.copy_url.json   # same
usr/share/omarchy/default/chromium/native-messaging-hosts/com.omarchy.ytdlp.json   # same
usr/share/omarchy/default/hypr/apps/omarchy-shell.lua   # window rule matching the dev gallery's title
usr/share/omarchy/default/hypr/apps/system.lua   # window rule matching a title, displays nothing
usr/share/omarchy/shell/plugins/dev-gallery/GalleryPanel.qml   # developer tool, permanent
```

- [ ] **Step 6: Verify**

Run: `./dev gates` Expected: five `PASS` lines, the last `PASS: branding (string literals, wallpaper names, 92 reviewed wallpapers, 5 substitutions)`, and in the assembly log `rebuild-font: U+E900 (omarchy) is now 1 contour(s) ...; 19 other glyph(s) untouched`, `rewrite-manifests: 37 manifests, 36 rewritten: 36 author(s), 11 field(s)`, `apply-strings: 5 row(s), 6 replacement(s) in 5 file(s)`, `render-wallpapers: 92 wallpapers: 68 kept, 20 regenerated, 4 deleted` (the last two numbers as Task 6 recorded them).
Run: `find .cache/payload/usr/share/omarchy/themes -path '*/backgrounds/*' -type f | wc -l; find .cache/payload/usr/share/omarchy/themes -path '*/backgrounds/*omarchy*' | wc -l; find .cache/payload/usr/share/omarchy/themes -path '*/backgrounds/*tinkero*' | wc -l` Expected: `88`, `0`, `20` (88 as Task 6 recorded).
Run: `ci/gate-branding .cache/payload branding/images.tsv branding/strings.tsv /dev/null 2>&1 | grep -c '^  usr/'` Expected: `8` (the gate's own filtered scan: the allowlisted files and nothing else; a raw `grep` for the word counts the attribution phrases too and is not the check).
Run: `grep -c 'Tinkero $version, built on Omarchy' .cache/payload/usr/share/tinkero/fastfetch/config.jsonc` Expected: `1`.
Run: `magick identify -format '%w %h\n' .cache/payload/usr/share/omarchy/icon.png; cmp branding/wordmark.svg .cache/payload/usr/share/omarchy/logo.svg && echo logo-svg-replaced; cmp branding/logo.txt .cache/payload/usr/share/omarchy/logo.txt && echo logo-txt-replaced` Expected: `300 300`, `logo-svg-replaced`, `logo-txt-replaced`.
Run: `./dev check` Expected: green, with `tests/test-gates.sh` at `1..58`, `tests/test-branding.sh` at `1..14`, `tests/test-branding-render.sh` at `1..34`, the Python suite at `Ran 33 tests`.
Run: `./dev spec && grep -c 'BuildRequires:  git-core python3 python3-fonttools ImageMagick' tinkero.spec` Expected: `1`. `rpmspec -P tinkero.spec >/dev/null && rpmlint tinkero.spec` in CI if not installed locally.
Run: `shellcheck -x -e SC1090,SC1091 dev build/assemble ci/gate-branding branding/render-wallpapers branding/inventory-images branding/contact-sheet tests/test-*.sh` Expected: clean.
CI: green, including the `tinkero` SRPM build step (it renders the spec with the new `BuildRequires`; the RPM build itself is COPR's, post-merge, as for every plan so far).

- [ ] **Step 7: Commit**

```bash
git add build/assemble ci/gate-branding ci/allow/branding.allow tinkero.spec.in dev .github/workflows/ci.yml tests/test-gates.sh
git commit -m "build: assemble step 3d applies the branding; gate-branding proves it on the payload (8 allowlisted files)"
```

**Verification for the issue:** Step 6's commands and outputs, plus CI green.

---

### Task 8: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` (status line; 4.13; 8 item 4a), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (2D row; a "What executing 2D added to the queue" section), `docs/research/arch-coupling-audit.md` (section 11, a measured note), `README.md` (a Branding paragraph), `docs/guides/workflow.md` ("Where the build is")

**Interfaces:**
- Consumes: the measured facts of Tasks 2 to 7 and the design's decisions.

- [ ] **Step 1: The spec**

Status line (line 4): append `; 2D (branding) done 2026-09-XX.` before `Fedora 44 x86_64 is the first target.`

Section 4.13, the table: in the "Theme wallpapers" row, replace `18 of the 22 themes ship backgrounds/omarchy.png` with `20 of the 92 wallpapers are flat wordmarks (18 named backgrounds/omarchy.png, plus flexoki-light's 2-omarchy.png and lupine's 06-omarchy.png)` and `the 18 flat ones are regenerated at build time as backgrounds/tinkero.png` with `the 20 flat ones are regenerated at build time under the source's name with omarchy replaced by tinkero`; add after `Illustrated ones cannot be regenerated and are deleted.` the sentence `A wallpaper nobody has looked at carries the verdict review, which the build refuses.` In the "Plugin metadata" row, replace `28 shell/plugins/**/manifest.json` with `36 of the 37 plugin and bar-widget manifests` and `not by 28 rows` with `not by 36 rows`; append `the transform replaces encoded values in the file text and verifies by parsing, so formatting is untouched`. In the "Menu" row, replace `the first is replaced by a learn.tinkero row that opens Tinkero's README in the default browser` with `the first keeps its id (an identifier) and becomes the "Tinkero" row that opens Tinkero's README through omarchy-launch-browser`. In the "About screen's OS line" row, append `and reads "Tinkero <version>, built on Omarchy", which is the About screen's attribution`.

After the paragraph that begins `The substitution list is branding/strings.tsv`, replace `The branding gate in section 8 covers what a substitution list cannot know about: it greps ... allowlist (the dev gallery and its window rule, and a title-matching window rule in default/hypr/apps/system.lua)` with `The branding gate in section 8 covers what a substitution list cannot know about: it scans the payload's QML, JS, Lua, JSON, JSONC and .desktop files for the capitalised word inside string literals, skipping comment lines and the two attribution phrases ("built on Omarchy", "from Omarchy"), and fails on anything outside an allowlist of eight files at v4.0.4 (the dev gallery and its window rule, a title-matching window rule in default/hypr/apps/system.lua, and five Chromium extension files that are a non-goal)`. Keep the rest of that paragraph.

Replace the last paragraph of 4.13 (`Prerequisite that does not exist yet: ...`) with: `The Tinkero mark (a monochrome glyph, an SVG wordmark and the two ASCII renderings) still does not exist; branding/ carries a generated placeholder (a block "T" and block-letter "TINKERO") and branding/README.md says what replacing it takes: two SVG files and two commands, no code. Design and decisions: docs/superpowers/specs/2026-09-23-phase-2d-branding-design.md.`

Section 8, item 4a: replace it with `4a. **Branding gate.** No capitalised "Omarchy" inside a string literal in the payload's QML, JS, Lua, JSON, JSONC or .desktop files, comment lines and the two attribution phrases excepted, outside the allowlist (ci/allow/branding.allow, eight files at v4.0.4); no *omarchy* file under a theme's backgrounds/; every wallpaper in the payload is a keep row of branding/images.tsv with its recorded sha256 or a file rendered for a regenerate row, and no row is review; every row of branding/strings.tsv is gone from its file and its replacement present (the count itself failed the build if it was off) (4.13).`

- [ ] **Step 2: The roadmap**

In the table, the 2D row becomes:

```
| **2D** branding | font rebuild, wallpaper rendering, manifest rewrite, `branding/strings.tsv` and `images.tsv`, the branding gate | 2A, 2C (menu labels) | no | **done** 2026-09-XX: `2026-09-23-phase-2d-branding.md`; design `2026-09-23-phase-2d-branding-design.md`; the placeholder mark ships until the real one exists |
```

After the "What executing 2C added to the queue" section, add:

```markdown
## What executing 2D added to the queue (2026-09-XX)

- **The mark:** `branding/mark.svg` and `wordmark.svg` are a generated placeholder; the real artwork replaces them per `branding/README.md` (two files, two commands). The two ASCII renderings are regenerated with upstream's `omarchy-transcode-ascii`.
- **Milestone B (2F):** the on-screen lines this plan could not check: the mark in the bar's menu button and beside the Packages row, the About screen with the 54 by 26 logo and its "built on Omarchy" line, the screensaver, each theme's rotation showing `tinkero.png` where `omarchy.png` was.
- **2F or bare metal:** upstream's `learn.hyprland`, `learn.neovim` and `learn.bash` rows use `omarchy-launch-webapp`, which runs `chromium.desktop` unless the default browser is Chrome-like; on a stock Fedora with Firefox those rows do nothing. Decide between a patch to the launcher's fallback and a name-map row for Chromium. 2D switched Tinkero's two Learn rows to `omarchy-launch-browser`.
- **Bump checklist (Phase 3):** `branding/inventory-images` on the new tree, then review every `review` row on `branding/contact-sheet`'s output; read `apply-strings`' report and fix `strings.tsv`; read `rewrite-manifests`' counts against the plugin diff; run the gate and read new string-literal findings before touching `ci/allow/branding.allow`; check that `U+E900` is still the logo glyph.
- **Developer machines:** `./dev gates` needs `python3-fonttools` and `ImageMagick`; `./dev check` prints a skip line for the two test files that need them.
- **Measured, not as the audit said:** 20 flat wordmark wallpapers, not 18; 36 branded manifests in 37 files, not 28; 11 branded display fields, not 4; five Chromium files and five comment-only mentions the audit did not list.
```

Replace the `2026-09-XX` placeholders with the landing date.

- [ ] **Step 3: The audit, the README, the workflow guide**

`docs/research/arch-coupling-audit.md`, end of section 11, add a paragraph: `Measured on the real tree by plan 2D (2026-09-XX): 20 of the 92 wallpapers are flat wordmarks (the 18 omarchy.png plus flexoki-light/2-omarchy.png and lupine/06-omarchy.png, all 3840 by 2160, two colours, the theme's accent on its background), four are illustrated marks (rose-pine/3-omarchy-plants.png, tokyo-night/1-quattro.jpg, 5-oma-cityscape.jpg, 6-oma.jpg); 37 manifests, 36 with the author and 11 branded display fields in 5 files; five Chromium extension files and five comment-only mentions that need no handling. The reviewed verdict of every wallpaper is branding/images.tsv.`

`README.md`, after the Principles list, add:

```markdown
## Branding

Nothing on screen says or shows Omarchy: the mark, the wallpapers, the About screen and the menu are Tinkero's, generated at build time from `branding/` (a placeholder mark until the real one exists). Every command, path and plugin id keeps upstream's name, because they are identifiers, not branding. Tinkero is built on [Omarchy](https://omarchy.org) and says so in the About screen, in every plugin's author line and in this README; Omarchy's license ships in `/usr/share/licenses/tinkero/`.
```

`docs/guides/workflow.md`, "Where the build is": replace the `Next:` and `Then` bullets with the current state (2C landed 2026-09-23; 2E planned, issue #16; 2D landed 2026-09-XX; then 2F and Phase 3).

- [ ] **Step 4: Verify and commit**

Run: `./dev check` Expected: green. Run: `git diff -U0 -- docs README.md | grep '^+' | grep -c "—"` Expected: `0`.

```bash
git add docs README.md
git commit -m "docs: 2D done, the seen surface is Tinkero's and the gate proves it"
```

**Verification for the issue:** `./dev check` green; the PR reviewer reads each edit against the design. There is no mechanical verification of prose beyond that; the issue says so.

---

## What executing 2D added to the queue (2026-09-24)

- **The mark:** `branding/mark.svg` and `wordmark.svg` are a generated placeholder; the real artwork replaces them per `branding/README.md` (two files, two commands). The two ASCII renderings are regenerated with upstream's `omarchy-transcode-ascii`.
- **Milestone B (2F):** the on-screen lines this plan could not check: the mark in the bar's menu button and beside the Packages row, the About screen with the 54 by 26 logo and its "built on Omarchy" line, the screensaver, each theme's rotation showing `tinkero.png` where `omarchy.png` was.
- **2F or bare metal:** upstream's `learn.hyprland`, `learn.neovim` and `learn.bash` rows use `omarchy-launch-webapp`, which runs `chromium.desktop` unless the default browser is Chrome-like; on a stock Fedora with Firefox those rows do nothing. Decide between a patch to the launcher's fallback and a name-map row for Chromium. 2D switched Tinkero's two Learn rows to `omarchy-launch-browser`.
- **Bump checklist (Phase 3):** `branding/inventory-images` on the new tree, then review every `review` row on `branding/contact-sheet`'s output; read `apply-strings`' report and fix `strings.tsv`; read `rewrite-manifests`' counts against the plugin diff; run the gate and read new string-literal findings before touching `ci/allow/branding.allow`; check that `U+E900` is still the logo glyph.
- **Developer machines:** `./dev gates` needs `python3-fonttools` and `ImageMagick`; `./dev check` prints a skip line for the two test files that need them.
- **Measured, not as the audit said:** 20 flat wordmark wallpapers, not 18; 36 branded manifests in 37 files, not 28; 11 branded display fields, not 4; five Chromium files and five comment-only mentions the audit did not list.
- **Diego's wallpaper pass:** the 67 `review` rows in `branding/images.tsv`, from `.cache/wallpapers.png` (`branding/contact-sheet`); the branch lands only when none is left.
- **Memory for the contact sheet:** about 3.3 GiB and seven minutes for the 92-image montage even with the script's limits; a smaller sheet (thumbnails first) is worth doing if the bump loop makes it routine.

## Deviations

The deviations below were recorded by the implementing branch on 2026-09-24.

- **Environment:** the implementing machine had neither ImageMagick nor python3-fonttools and the host was left untouched; every tool-dependent step ran in a `fedora:44` container carrying CI's package line plus the two tools. On the host `./dev check` prints the two skip lines (D12).
- **Task 6, fixture:** plan 2E landed first and `build/assemble` now installs `distro/fedora/dconf/profile/tinkero` unconditionally, so the assemble fixture root in `tests/test-branding-render.sh` section 4 gained that file (as `tests/test-assemble.sh` has it).
- **Task 6, `render-wallpapers`:** `-alpha remove` was added before `-strip` on the render line as a guard that keeps the PNG24 output independent of how the SVG delegate fills the canvas; the implementer's report of black pixels without it did not reproduce under review (output byte-identical with and without), so it is a guard, not a fix.
- **Task 6, the render test:** the plan's histogram pipeline kept the `#` of each hex colour, so its expected value `1a1b26 7aa2f7 ` could never match; the pipeline now strips the `#` (`tr -d '#'`) and the expected value is unchanged.
- **Task 6, `contact-sheet`:** the montage over the real tree (originals up to 10456 by 3455) was killed for memory on an 11 GiB machine at ImageMagick's default limits; the script now passes `-limit memory 1GiB -limit map 2GiB -limit thread 1`. `render-wallpapers` needs no limits (one image at a time, about 30 seconds for the tree).
- **Task 6, the review:** the 67 `review` rows are Diego's to replace; the branch carries them as `review`, and every real-tree figure above that depends on the verdicts was measured on a scratch copy of the list with review turned to keep. Task 6 is not done and the CI gates step is red until the review lands (D4).
- **Task 7:** the plan's RED expectation for the gate tests (17 `not ok`) was imprecise: four of the new cases pass trivially before the gate exists (13 `not ok`); the GREEN tally 1..58 is as planned.
- **Task 5:** the plan's verify command carried the U+E900 character literally, which renders blank; it was run with the Python escape for that code point instead. No file differs from the plan.
- **Final review:** the omarchy to tinkero name mapping in render-wallpapers and the gate acts on the file name only: a theme directory named for upstream would have sent the render into a directory that does not exist, and one named for Tinkero would have made the gate look up the wrong row; one hermetic gate case added for the latter, tests/test-gates.sh at 1..59.
- **Deferred:** `rebuild-font` reports malformed XML or an unsupported SVG feature as a raw traceback rather than `rebuild-font: <reason>`; `render-wallpapers` and `contact-sheet` have no fixture case with a space in a wallpaper path (`inventory-images` has one).

## What this plan deliberately leaves out

- The real Tinkero mark: a person's, any time; `branding/README.md` says what it takes.
- CLI `--help` text and the `# omarchy:summary=` lines (terminal-only, tied to the command names, out of scope in v1 per the master spec); header comments in the seeded config files (the user's files, pointing at upstream's documentation).
- The five Chromium extension files (allowlisted, D7) and the dev gallery.
- Upstream's three `learn.*` web-app rows that fall back to `chromium.desktop` (queued for 2F or bare metal).
- Running `omarchy-transcode-ascii` at build time to derive the ASCII logos from the SVGs (D2: the files are data; the build never runs an upstream script).
- The on-screen check (Milestone B): needs the installable package from 2E and 2F.
- A `--dry-run` for `render-wallpapers`: its pre-check already writes nothing until every row is decided, and `inventory-images` plus `contact-sheet` are the review tools.
