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

# dropped-refs edge cases: sourced files
mkdir -p "$p/usr/share/omarchy/install/helpers"
printf 'echo present\n' > "$p/usr/share/omarchy/install/helpers/present.sh"
# shellcheck disable=SC2016  # the $OMARCHY_PATH literals below belong to the stub scripts being written, not to this shell
printf '#!/bin/bash\nsource "$OMARCHY_PATH/install/helpers/present.sh"\n' > "$p/usr/bin/omarchy-sources-present"
# shellcheck disable=SC2016
printf '#!/bin/bash\nsource "$OMARCHY_PATH/install/helpers/browser-policy.sh"\n' > "$p/usr/bin/omarchy-sources-dropped"
# shellcheck disable=SC2016
printf '#!/bin/bash\ntheme=t\n. "$OMARCHY_PATH/themes/$theme/init.sh"\n' > "$p/usr/bin/omarchy-sources-variable"
: > "$d/allow8"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-nobin.list" "$d/allow8" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs fails on a sourced file the drop list removed"
assert_contains "$out" "usr/bin/omarchy-sources-dropped:usr/share/omarchy/install/helpers/browser-policy.sh" "reports path:target"
if [[ $out == *omarchy-sources-present* ]]; then not_ok "dropped-refs does not flag a sourced file that is present" "$out"; else ok "dropped-refs does not flag a sourced file that is present"; fi
if [[ $out == *omarchy-sources-variable* ]]; then not_ok "dropped-refs ignores a sourced path that is not fully literal" "$out"; else ok "dropped-refs ignores a sourced path that is not fully literal"; fi
printf 'usr/bin/omarchy-sources-dropped:usr/share/omarchy/install/helpers/browser-policy.sh\n' > "$d/allow8"
"$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-nobin.list" "$d/allow8" >/dev/null 2>&1; assert_eq "$?" "0" "dropped-refs passes on a sourced-file finding once allowlisted"

# dropped-refs edge cases: quoting and trailing-punctuation variants around a dropped target
mkdir -p "$p/usr/share/omarchy/ok"
printf 'ok\n' > "$p/usr/share/omarchy/ok/a.sh"
printf 'ok\n' > "$p/usr/share/omarchy/x.sh"
# shellcheck disable=SC2016
printf '#!/bin/bash\nsource "$OMARCHY_PATH"/install/helpers/browser-policy.sh\n' > "$p/usr/bin/omarchy-split-quote"
printf "#!/bin/bash\nsource '/usr/share/omarchy/install/helpers/browser-policy.sh'\n" > "$p/usr/bin/omarchy-single-quote"
# shellcheck disable=SC2016
printf '#!/bin/bash\nsource "${OMARCHY_PATH}/install/helpers/browser-policy.sh"\n' > "$p/usr/bin/omarchy-brace-form"
# shellcheck disable=SC2016
printf '#!/bin/bash\nx=$(source $OMARCHY_PATH/ok/a.sh)\n' > "$p/usr/bin/omarchy-cmdsub-present"
printf '#!/bin/bash\n. /usr/share/omarchy/x.sh|| true\n' > "$p/usr/bin/omarchy-pipe-tail-present"
: > "$d/allow9"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-nobin.list" "$d/allow9" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs fails on a dropped target reached through split/single/braced quoting"
assert_contains "$out" "usr/bin/omarchy-split-quote:usr/share/omarchy/install/helpers/browser-policy.sh" "catches the variable quoted, rest bare idiom (quote closed right after the variable)"
assert_contains "$out" "usr/bin/omarchy-single-quote:usr/share/omarchy/install/helpers/browser-policy.sh" "catches a single-quoted literal path"
assert_contains "$out" "usr/bin/omarchy-brace-form:usr/share/omarchy/install/helpers/browser-policy.sh" "catches the braced variable form"
for f in omarchy-cmdsub-present omarchy-pipe-tail-present; do
  if [[ $out == *"$f"* ]]; then not_ok "dropped-refs does not misread trailing shell punctuation as part of the target ($f)" "$out"
  else ok "dropped-refs does not misread trailing shell punctuation as part of the target ($f)"; fi
done

# dropped-refs edge case: a name that merely starts with the same letters is a different variable
# shellcheck disable=SC2016
printf '#!/bin/bash\nOMARCHY_PATHX=/opt/x\nsource "$OMARCHY_PATHX/gone.sh"\n' > "$p/usr/bin/omarchy-lookalike-var"
: > "$d/allow10"
"$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-nobin.list" "$d/allow10" >/dev/null 2>&1
assert_eq "$?" "0" "dropped-refs does not read \$OMARCHY_PATHX as a continuation of \$OMARCHY_PATH"
rm -rf "$p/usr/share/omarchy/install" "$p/usr/share/omarchy/ok" "$p/usr/share/omarchy/x.sh" \
  "$p/usr/bin/omarchy-sources-present" "$p/usr/bin/omarchy-sources-dropped" "$p/usr/bin/omarchy-sources-variable" \
  "$p/usr/bin/omarchy-split-quote" "$p/usr/bin/omarchy-single-quote" "$p/usr/bin/omarchy-brace-form" \
  "$p/usr/bin/omarchy-cmdsub-present" "$p/usr/bin/omarchy-pipe-tail-present" "$p/usr/bin/omarchy-lookalike-var"

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
if [[ $out != *commented* ]]; then ok "name-map ignores comment lines in scripts"; else not_ok "name-map ignores comment lines in scripts" "$out"; fi
printf 'vim\tdnf\tvim-enhanced\nfoot\tdnf\tfoot\n' > "$d/map3"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map3" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails when the map is not sorted"; assert_contains "$out" "not sorted" "and says so"
printf 'foot\tdnf\tfoot\nvim\tapt\tvim\n' > "$d/map4"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map4" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on an unknown kind"; assert_contains "$out" "malformed" "and says so"
"$ROOT/ci/gate-name-map" "$p" "$d/nope" >/dev/null 2>&1; assert_eq "$?" 2 "name-map exits 2 on an unreadable map"
# shellcheck disable=SC2016  # the single-quoted literals and $ollama_pkg below belong to the stub script being written, not to this shell
printf '#!/bin/bash\nomarchy-pkg-present "brave-bin" && omarchy-install-and-launch '"'"'Grok Bot'"'"' grok-bot grok-bot\nomarchy-install-font '"'"'Fira Code'"'"' ttf-firacode-nerd '"'"'FiraCode Nerd Font'"'"'\nomarchy-install-app Ollama "$ollama_pkg"\n' > "$p/usr/bin/omarchy-installer2"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map sees quoted literals and the installers' package argument"
for n in brave-bin grok-bot ttf-firacode-nerd; do assert_contains "$out" "  $n" "  reports $n"; done
if [[ $out != *ollama_pkg* && $out != *Ollama* ]]; then ok "name-map ignores a variable argument and the display name"; else not_ok "name-map ignores a variable argument and the display name" "$out"; fi
printf '# empty\n' > "$d/map5"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map5" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on a map with no rows"; assert_contains "$out" "has no rows" "and says so"
printf 'foot\tdnf\tfoot\r\n' > "$d/map6"
"$ROOT/ci/gate-name-map" "$p" "$d/map6" >/dev/null 2>&1; assert_eq "$?" 2 "name-map exits 2 on a CRLF map"
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
printf '{"text": "Tinkero 1, built on Omarchy"}\n' > "$b/usr/share/tinkero/fastfetch/config.jsonc"
mkdir -p "$b/usr/share/omarchy/themes/tinkero-t/backgrounds"
echo x > "$b/usr/share/omarchy/themes/tinkero-t/backgrounds/tinkero.png"
printf 'themes/tinkero-t/backgrounds/omarchy.png\t0\tregenerate\n' >> "$d/images.tsv"
out=$("$G" "$b" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "branding: a theme directory named for Tinkero does not confuse the rendered-file lookup"
rm "$b/usr/share/omarchy/themes/tinkero-t/backgrounds/tinkero.png"
sed -i '/tinkero-t/d' "$d/images.tsv"

out=$("$G" "$d/no-payload" "$d/images.tsv" "$d/strings.tsv" "$d/allow-b" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "branding: fails loudly without a payload"

# session-units (plan 2F): unit-a is bound directly, unit-b only through a drop-in, unit-c is a
# plain oneshot; all three pass, so this fixture is also the "bound through a drop-in" and
# "oneshot passes" case, restored between the mutations below.
su=$d/su
mkdir -p "$su/usr/bin" "$su/usr/lib/systemd/user/unit-b.service.d" "$su/usr/share/omarchy/default/systemd/user"
reset_su() {
  printf '[Unit]\nPartOf=graphical-session.target\n\n[Service]\nExecStart=/usr/bin/true\n' > "$su/usr/lib/systemd/user/unit-a.service"
  printf '[Unit]\nDescription=b\n\n[Service]\nExecStart=/usr/bin/true\n' > "$su/usr/lib/systemd/user/unit-b.service"
  printf '[Unit]\nPartOf=graphical-session.target\n' > "$su/usr/lib/systemd/user/unit-b.service.d/tinkero.conf"
  printf '[Unit]\nDescription=c\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n' > "$su/usr/lib/systemd/user/unit-c.service"
  cp "$su/usr/lib/systemd/user/unit-a.service" "$su/usr/share/omarchy/default/systemd/user/unit-a.service"
  cp "$su/usr/lib/systemd/user/unit-b.service" "$su/usr/share/omarchy/default/systemd/user/unit-b.service"
  cp "$su/usr/lib/systemd/user/unit-c.service" "$su/usr/share/omarchy/default/systemd/user/unit-c.service"
}
reset_su
printf '# comment\nunit-a.service\nunit-b.service\nunit-c.service\n' > "$d/session-units.list"
GS=$ROOT/ci/gate-session-units

out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "session-units: pass case (a bound directly, b through a drop-in, c a plain oneshot)"
assert_eq "$out" "PASS: session units (3 listed, 3 unit files, no [Install])" "session-units: exact PASS line, comment line not counted"

printf '\n[Install]\nWantedBy=graphical-session.target\n' >> "$su/usr/lib/systemd/user/unit-a.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: [Install] in the usr/lib copy fails"
assert_contains "$out" "usr/lib/systemd/user/unit-a.service" "session-units: names the usr/lib copy"
reset_su

printf '\n[Install]\nWantedBy=graphical-session.target\n' >> "$su/usr/share/omarchy/default/systemd/user/unit-a.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: [Install] in the tree copy fails"
assert_contains "$out" "usr/share/omarchy/default/systemd/user/unit-a.service" "session-units: names the tree copy"
reset_su

printf 'unit-a.service\nunit-missing.service\n' > "$d/session-units-missing.list"
out=$("$GS" "$su" "$d/session-units-missing.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: a listed unit with no file fails"
assert_contains "$out" "listed unit has no file: unit-missing.service" "session-units: names it"

rm -f "$su/usr/lib/systemd/user/unit-b.service.d/tinkero.conf"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: a listed unit bound neither directly nor by a drop-in fails"
assert_contains "$out" "neither bound to the session nor a plain oneshot: unit-b.service" "session-units: names it"
reset_su

printf 'RemainAfterExit=yes\n' >> "$su/usr/lib/systemd/user/unit-c.service"
cp "$su/usr/lib/systemd/user/unit-c.service" "$su/usr/share/omarchy/default/systemd/user/unit-c.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: a oneshot with RemainAfterExit=yes is no longer exempt"
assert_contains "$out" "neither bound to the session nor a plain oneshot: unit-c.service" "session-units: names it"
reset_su

printf 'RemainAfterExit=true\n' >> "$su/usr/lib/systemd/user/unit-c.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: RemainAfterExit=true is a remaining oneshot too"
reset_su

printf '[Unit]\nPartOf=pipewire.service graphical-session.target\n' > "$su/usr/lib/systemd/user/unit-b.service.d/tinkero.conf"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "session-units: a PartOf= line naming several units binds the unit"
reset_su

out=$("$GS" "$su" "does-not-exist" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "session-units: exits 2 on an unreadable list"
assert_contains "$out" "cannot read session unit list" "session-units: and says so"

out=$("$GS" "$d/no-such-payload" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "session-units: exits 2 on a missing payload"
assert_contains "$out" "no payload at DEST" "session-units: and says so"

out=$("$GS" "$su" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "session-units: exits 2 on the wrong number of arguments"
assert_contains "$out" "usage: gate-session-units" "session-units: and prints usage"

rm -rf "$d"; finish
