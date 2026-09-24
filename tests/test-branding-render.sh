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
top=$(magick "$th/backgrounds/tinkero.png" -format %c histogram:info:- | sort -rn | head -n2 | grep -oE '#[0-9A-Fa-f]{6}' | tr -d '#' | tr '[:upper:]' '[:lower:]' | sort | tr '\n' ' ')
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
mkdir -p "$r/distro/fedora/dconf/profile"; echo 'user-db:tinkero' > "$r/distro/fedora/dconf/profile/tinkero"
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
