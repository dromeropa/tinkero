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
