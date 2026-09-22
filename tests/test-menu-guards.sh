#!/bin/bash
# The bash prelude that the patched MenuModel.js emits for the menu's package guards,
# evaluated through node (CI installs nodejs; locally the test is skipped without it).
source "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null; then ok "skipped: node is not installed"; finish; exit; fi
d=$(mktmp); mkdir -p "$d/bin"
# extract guardHelpers() from the patched file in the assembled payload, or from the patch itself
src=$ROOT/.cache/payload/usr/share/omarchy/shell/plugins/menu/MenuModel.js
if [[ ! -f $src ]]; then
  # no payload: take the new lines straight from the patch
  sed -n '/^+  \/\/ Tinkero: one rpm/,/^+    + .__omarchy_pkg_has/p' "$ROOT/patches/0010-menu-package-guards-rpm.patch" | sed 's/^+//' > "$d/body.js"
else
  sed -n '/^function guardHelpers() {/,/^}/p' "$src" | sed '1d;$d' > "$d/body.js"
fi
{ echo "function f(){"; cat "$d/body.js"; echo "}"; echo "process.stdout.write(f())"; } > "$d/gen.js"
node "$d/gen.js" > "$d/prelude.sh" || { not_ok "prelude generates"; finish; exit; }
ok "prelude generates from the JS"
printf '#!/bin/bash\nprintf "foot\\nhtop\\n"\n' > "$d/bin/rpm"
printf '#!/bin/bash\nprintf "org.signal.Signal\\n"\n' > "$d/bin/flatpak"
chmod +x "$d/bin"/*
printf '# c\nfoot\tdnf\tfoot\nsignal-desktop\tflatpak\torg.signal.Signal\nvim\tdnf\tvim-enhanced\nopenclaw\tnone\t-\n' > "$d/map"
sed "s|/usr/share/tinkero/pkgmap.tsv|$d/map|" "$d/prelude.sh" > "$d/p.sh"
q() { PATH=$d/bin:$PATH bash -c "source '$d/p.sh'; __omarchy_pkg_has $1"; }
q foot;           assert_eq "$?" 0 "dnf-mapped installed name is present"
q signal-desktop; assert_eq "$?" 0 "flatpak-mapped installed name is present"
q vim;            assert_eq "$?" 1 "dnf-mapped but not installed is absent"
q openclaw;       assert_eq "$?" 1 "kind none is absent"
q nope;           assert_eq "$?" 1 "unmapped is absent"
assert_eq "$(grep -c pacman "$d/prelude.sh")" 0 "no pacman left in the prelude"
sed "s|/usr/share/tinkero/pkgmap.tsv|$d/no-such-map|" "$d/prelude.sh" > "$d/p2.sh"
PATH=$d/bin:$PATH bash -c "set -e; source '$d/p2.sh'; __omarchy_pkg_has foot && exit 3; exit 0" 2>/dev/null; rc=$?
assert_eq "$rc" 0 "a missing name map does not abort the guard batch under errexit, and every name is absent"
rm -rf "$d"; finish
