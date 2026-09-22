#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); p=$d/dest
mkdir -p "$p/usr/bin" "$p/usr/share/omarchy/bin" "$p/usr/share/omarchy/default"
printf '#!/bin/bash\nsudo pacman -Syu\n' > "$p/usr/bin/omarchy-leaky"
printf '#!/bin/bash\necho fine\n'        > "$p/usr/bin/omarchy-clean"
printf '#!/bin/bash\nomarchy-snapshot create\nomarchy-snapshot-helper\n' > "$p/usr/bin/omarchy-caller"
printf '{"action":"omarchy-plymouth-set x"}\n' > "$p/usr/share/omarchy/default/menu.jsonc"
for n in omarchy-leaky omarchy-clean omarchy-caller; do ln -s "/usr/bin/$n" "$p/usr/share/omarchy/bin/$n"; done
printf 'bin/omarchy-snapshot\nbin/omarchy-plymouth-*\nmigrations\n' > "$d/drop.list"

# arch-leak
: > "$d/allow"
out=$("$ROOT/ci/gate-arch-leak" "$p" "$d/allow" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "arch-leak fails on an unlisted file"
assert_contains "$out" "usr/bin/omarchy-leaky" "arch-leak names the file"
printf 'usr/bin/omarchy-leaky   # replaced in plan 2B\n' > "$d/allow"
"$ROOT/ci/gate-arch-leak" "$p" "$d/allow" >/dev/null 2>&1; assert_eq "$?" "0" "arch-leak passes when allowlisted (trailing comment ok)"
echo 'usr/bin/omarchy-gone' >> "$d/allow"
out=$("$ROOT/ci/gate-arch-leak" "$p" "$d/allow" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "arch-leak fails on a stale allowlist entry"
assert_contains "$out" "stale" "and says so"

# fail loudly on a missing payload instead of silently passing
out=$("$ROOT/ci/gate-arch-leak" "$d/no-payload" "$d/allow-nopayload" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "2" "arch-leak fails loudly when there is no payload at DEST"
assert_contains "$out" "no payload at DEST" "and says so"

# dropped-refs
: > "$d/allow2"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop.list" "$d/allow2" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs fails on a call to a dropped command"
assert_contains "$out" "usr/bin/omarchy-caller:omarchy-snapshot" "reports path:command"
assert_contains "$out" "usr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set" "expands drop-list globs"
if [[ $out != *omarchy-snapshot-helper* ]]; then ok "does not match a longer command name"; else not_ok "does not match a longer command name" "$out"; fi
printf 'usr/bin/omarchy-caller:omarchy-snapshot\nusr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set\n' > "$d/allow2"
"$ROOT/ci/gate-dropped-refs" "$p" "$d/drop.list" "$d/allow2" >/dev/null 2>&1; assert_eq "$?" "0" "dropped-refs passes when allowlisted"

# dropped-refs edge cases: all-glob drop list
printf 'bin/omarchy-plymouth-*\n' > "$d/drop-glob.list"
: > "$d/allow3"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-glob.list" "$d/allow3" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs with all-glob drop list fails on a match"
assert_contains "$out" "usr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set" "reports the finding"

# dropped-refs edge cases: no bin/ lines
printf 'migrations\n' > "$d/drop-nobin.list"
: > "$d/allow4"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-nobin.list" "$d/allow4" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "0" "dropped-refs with no bin/ lines passes"
assert_contains "$out" "PASS" "and reports PASS"

# dropped-refs edge case: drop list cannot be read
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/no-such-droplist" "$d/allow6" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "2" "dropped-refs fails loudly when the drop list cannot be read"
assert_contains "$out" "cannot read drop list" "and says so"

# dropped-refs edge case: unsupported glob character
printf 'bin/omarchy-fo?o\n' > "$d/drop-badglob.list"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-badglob.list" "$d/allow7" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "2" "dropped-refs rejects an unsupported glob character"
assert_contains "$out" "unsupported glob" "and says so"

# single-copy
"$ROOT/ci/gate-single-copy" "$p" >/dev/null 2>&1; assert_eq "$?" "0" "single-copy passes on a correct layout"
rm "$p/usr/share/omarchy/bin/omarchy-clean"; cp "$p/usr/bin/omarchy-clean" "$p/usr/share/omarchy/bin/omarchy-clean"
"$ROOT/ci/gate-single-copy" "$p" >/dev/null 2>&1; assert_eq "$?" "1" "single-copy fails on a regular file in the tree bin/"

# single-copy edge case: no commands at all
mkdir -p "$d/empty-dest/usr/bin" "$d/empty-dest/usr/share/omarchy/bin"
out=$("$ROOT/ci/gate-single-copy" "$d/empty-dest" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "single-copy fails when there are no commands"
assert_contains "$out" "no commands in usr/share/omarchy/bin" "and says so"

# name-map
mkdir -p "$p/usr/share/omarchy/default"
printf '#!/bin/bash\nomarchy-pkg-add foot vim 2>/dev/null\n# omarchy-pkg-add commented out\n' > "$p/usr/bin/omarchy-installer"
printf 'foot\tdnf\tfoot\nvim\tdnf\tvim-enhanced\n' > "$d/map"
"$ROOT/ci/gate-name-map" "$p" "$d/map" >/dev/null 2>&1; assert_eq "$?" 0 "name-map passes when every used name has a row"
printf 'foot\tdnf\tfoot\n' > "$d/map2"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map2" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on a used name with no row"
assert_contains "$out" "  vim" "and names it"
[[ $out != *commented* ]] && ok "name-map ignores comment lines in scripts" || not_ok "name-map ignores comment lines in scripts" "$out"
printf 'vim\tdnf\tvim-enhanced\nfoot\tdnf\tfoot\n' > "$d/map3"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map3" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails when the map is not sorted"; assert_contains "$out" "not sorted" "and says so"
printf 'foot\tdnf\tfoot\nvim\tapt\tvim\n' > "$d/map4"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map4" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on an unknown kind"; assert_contains "$out" "malformed" "and says so"
"$ROOT/ci/gate-name-map" "$p" "$d/nope" >/dev/null 2>&1; assert_eq "$?" 2 "name-map exits 2 on an unreadable map"
printf '#!/bin/bash\nomarchy-pkg-present "brave-bin" && omarchy-install-and-launch '"'"'Grok Bot'"'"' grok-bot grok-bot\nomarchy-install-font '"'"'Fira Code'"'"' ttf-firacode-nerd '"'"'FiraCode Nerd Font'"'"'\nomarchy-install-app Ollama "$ollama_pkg"\n' > "$p/usr/bin/omarchy-installer2"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map sees quoted literals and the installers' package argument"
for n in brave-bin grok-bot ttf-firacode-nerd; do assert_contains "$out" "  $n" "  reports $n"; done
[[ $out != *ollama_pkg* && $out != *Ollama* ]] && ok "name-map ignores a variable argument and the display name" || not_ok "name-map ignores a variable argument and the display name" "$out"
printf '# empty\n' > "$d/map5"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map5" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on a map with no rows"; assert_contains "$out" "has no rows" "and says so"
rm -rf "$d"; finish
