#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src")
# a private repo root so the test controls drop.list, patches and replacements
r=$d/root; mkdir -p "$r"/{build,patches,distro/fedora/{replacements,lib,skills,dconf/profile},session/uwsm-env.d,bin,config/hypr,provision,config-notes}
mkdir -p "$r"/systemd/{omarchy-fcitx5.service.d,bt-agent.service.d,omarchy-speaker-tuning.service.d}
printf '# lib\n' > "$r/distro/fedora/lib/pkg.sh"; printf 'foot\tdnf\tfoot\n' > "$r/distro/fedora/pkgmap.tsv"
cp "$ROOT/session/tinkero.desktop" "$r/session/"
echo '# fixture host guide' > "$r/distro/fedora/skills/host.md"
printf '[Unit]\nDescription=fixture inhibitor\n\n[Service]\nExecStart=/usr/bin/true\n' > "$r/systemd/tinkero-inhibit-power-key.service"
printf '[Unit]\nConditionPathExists=/usr/bin/fcitx5\n' > "$r/systemd/omarchy-fcitx5.service.d/tinkero.conf"
printf '[Unit]\nPartOf=graphical-session.target\n' > "$r/systemd/bt-agent.service.d/tinkero.conf"
printf '[Unit]\nPartOf=graphical-session.target\n' > "$r/systemd/omarchy-speaker-tuning.service.d/tinkero.conf"
printf 'export DCONF_PROFILE=tinkero\n' > "$r/session/uwsm-env.d/20-tinkero"
echo '-- fixture bindings' > "$r/config/hypr/bindings.lua"
printf 'chromium/\n' > "$r/provision/skip.list"
printf 'omarchy-keep.service\n' > "$r/provision/session-units.list"
echo 'user-db:tinkero' > "$r/distro/fedora/dconf/profile/tinkero"
echo 'note' > "$r/config-notes/v0.md"
printf 'omarchy_tag=v0\n' > "$r/upstream.lock"
printf '# comment\nmigrations\ndefault/pacman\nbin/omarchy-snapshot\nbin/omarchy-plymouth-*\ndefault/systemd/user/omarchy-migrate-notify.service\n' > "$r/build/drop.list"
cat > "$r/patches/0001-version.patch" <<'P'
--- a/bin/omarchy-version
+++ b/bin/omarchy-version
@@ -1,2 +1,2 @@
 #!/bin/bash
-pacman -Q omarchy
+rpm -q tinkero
P
echo 0001-version.patch > "$r/patches/series"
printf '#!/bin/bash\necho "dnf upgrade"\n' > "$r/distro/fedora/replacements/omarchy-update"
mkdir -p "$r/menu"; cp "$ROOT/menu/apply-overrides" "$r/menu/"
cat > "$r/menu/overrides.jsonc" <<'J'
{"delete": ["learn.arch"], "expect_rows": 2}
J
run() { TINKERO_ROOT=$r "$ROOT/build/assemble" "$tb" "$1"; }

out=$(run "$d/dest")
o=$d/dest/usr/share/omarchy
assert_file "$d/dest/usr/bin/omarchy-keep-me" "commands land in /usr/bin"
assert_symlink "$o/bin/omarchy-keep-me" /usr/bin/omarchy-keep-me "tree bin/ holds symlinks"
assert_no_path "$d/dest/usr/bin/omarchy-snapshot" "dropped script is gone"
assert_no_path "$o/bin/omarchy-plymouth-set" "dropped glob is gone"
assert_no_path "$o/migrations" "dropped directory is gone"
assert_no_path "$o/etc" "upstream etc/ is not shipped"
assert_no_path "$d/dest/etc/sudoers.d" "no sudoers reach the payload"
assert_file "$d/dest/usr/share/tinkero/fastfetch/config.jsonc" "fastfetch config is relocated"
assert_file "$d/dest/etc/mise/conf.d/omarchy.toml" "mise alias is kept"
assert_eq "$(tail -n1 "$d/dest/usr/bin/omarchy-version")" "rpm -q tinkero" "patch applied"
assert_eq "$(tail -n1 "$d/dest/usr/bin/omarchy-update")" 'echo "dnf upgrade"' "replacement installed"
assert_file "$d/dest/usr/share/wayland-sessions/tinkero.desktop" "session file installed"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-keep.service" "user units installed"
assert_no_path "$d/dest/usr/lib/systemd/user/omarchy-migrate-notify.service" "dropped unit not installed"
assert_file "$d/dest/usr/share/licenses/tinkero/LICENSE.omarchy" "upstream license shipped"
assert_file "$d/dest/usr/share/tinkero/upstream.lock" "lock shipped"
assert_file "$d/dest/usr/share/tinkero/pkg.sh" "package library shipped"
assert_file "$d/dest/usr/share/tinkero/pkgmap.tsv" "name map shipped"

# Provisioning data (plan 2E)
assert_file "$o/default/agents/skills/omarchy/host.md" "host guide joins the omarchy skill inside the tree"
assert_eq "$(cat "$d/dest/usr/share/tinkero/config/hypr/bindings.lua")" "-- fixture bindings" "config overrides shipped under /usr/share/tinkero/config"
assert_file "$d/dest/usr/share/tinkero/provision/skip.list" "skip list shipped"
assert_file "$d/dest/usr/share/tinkero/provision/session-units.list" "session unit list shipped"
assert_file "$d/dest/usr/share/tinkero/config-notes/v0.md" "config notes shipped"
assert_file "$d/dest/etc/dconf/profile/tinkero" "dconf profile shipped"
assert_file "$d/dest/usr/share/icons/hicolor/512x512/apps/disk-usage.png" "launcher icon shipped under its Icon= name"
assert_file "$d/dest/usr/share/icons/hicolor/512x512/apps/imv.png" "imv icon shipped"

# Session units (plan 2F): [Install] stripped in the tree, Tinkero's own units join it
assert_contains "$out" "stripped [Install] from 1 unit(s)" "assemble logs how many units were stripped"
for copy in "$d/dest/usr/lib/systemd/user" "$o/default/systemd/user"; do
  if grep -rq '^\[Install\]' "$copy"; then not_ok "no [Install] survives in $copy"; else ok "no [Install] survives in $copy"; fi
done
assert_eq "$(sed -n '/^\[Service\]/,$p' "$d/dest/usr/lib/systemd/user/omarchy-keep.service")" "$(printf '[Service]\nExecStart=/usr/bin/omarchy-keep-me')" \
  "a section after [Install] survives intact"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-no-install.service" "a unit with no [Install] section is untouched"
assert_file "$d/dest/usr/lib/systemd/user/tinkero-inhibit-power-key.service" "Tinkero's inhibitor unit lands beside the tree's units"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-fcitx5.service.d/tinkero.conf" "Tinkero's fcitx5 drop-in lands"
assert_file "$d/dest/usr/lib/systemd/user/bt-agent.service.d/tinkero.conf" "Tinkero's bt-agent drop-in lands"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-speaker-tuning.service.d/tinkero.conf" "Tinkero's speaker-tuning drop-in lands"
assert_eq "$(cat "$d/dest/usr/share/uwsm/env.d/20-tinkero")" "export DCONF_PROFILE=tinkero" "the DCONF_PROFILE env file lands"

# a fixture root without systemd/ still assembles (other tests' private roots have none)
r2=$d/root-nosystemd; cp -a "$r" "$r2"; rm -rf "$r2/systemd"
TINKERO_ROOT=$r2 "$ROOT/build/assemble" "$tb" "$d/dest-nosystemd" >/dev/null
assert_no_path "$d/dest-nosystemd/usr/lib/systemd/user/tinkero-inhibit-power-key.service" "no Tinkero units without a systemd/ dir in the root"
assert_file "$d/dest-nosystemd/usr/lib/systemd/user/omarchy-keep.service" "the tree's own units still land"

# a unit whose [Install] header the strip cannot recognise (leading whitespace) fails the build
mkdir -p "$d/y"
tar -xzf "$tb" -C "$d/y"
printf '[Unit]\nDescription=broken\n\n  [Install]\nWantedBy=graphical-session.target\n' \
  > "$d/y/omarchy-fixture/default/systemd/user/omarchy-broken-install.service"
tar -C "$d/y" -czf "$d/broken-install.tar.gz" omarchy-fixture
out=$(TINKERO_ROOT=$r "$ROOT/build/assemble" "$d/broken-install.tar.gz" "$d/dest-broken" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a header the strip cannot recognise fails the build"
assert_contains "$out" "still have [Install] after stripping" "and names the failure"

# PAM variants and the host-only bin/ (plan 2F). The fixture root above has neither
# distro/fedora/pam nor distro/fedora/bin, and the run at "$d/dest" above still assembled: both
# steps are guarded. Add them now and assemble again to prove the positive path too.
mkdir -p "$r/distro/fedora/pam" "$r/distro/fedora/bin"
printf 'password fixture wrapped\n' > "$r/distro/fedora/pam/omarchy-lock-password.wrapped"
printf 'password fixture plain\n' > "$r/distro/fedora/pam/omarchy-lock-password.plain"
printf '#!/bin/bash\necho pam-sync fixture\n' > "$r/distro/fedora/bin/tinkero-pam-sync"
run "$d/dest-pam" >/dev/null
assert_eq "$(cat "$d/dest-pam/usr/share/tinkero/pam/omarchy-lock-password.wrapped")" "password fixture wrapped" "PAM wrapped variant shipped under usr/share/tinkero/pam"
assert_eq "$(cat "$d/dest-pam/usr/share/tinkero/pam/omarchy-lock-password.plain")" "password fixture plain" "PAM plain variant shipped"
assert_eq "$(stat -c %a "$d/dest-pam/usr/share/tinkero/pam/omarchy-lock-password.wrapped")" "644" "PAM variant installed mode 0644"
assert_eq "$(tail -n1 "$d/dest-pam/usr/bin/tinkero-pam-sync")" "echo pam-sync fixture" "distro/fedora/bin/tinkero-* installed to usr/bin, like bin/tinkero-*"
assert_eq "$(stat -c %a "$d/dest-pam/usr/bin/tinkero-pam-sync")" "755" "distro/fedora/bin/tinkero-pam-sync installed mode 0755"

# 3b. Menu: the default menu is rewritten in place, in the tree, before relocation
menu=$d/dest/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc
assert_file "$menu" "menu: still shipped at upstream's path"
assert_eq "$(grep -c '^\s*"' "$menu")" 2 "menu: two rows survive the fixture overrides"
assert_contains "$(cat "$menu")" "// fixture menu" "menu: upstream's comment survives"
if grep -q "learn.arch\|omarchy-snapshot" "$menu"; then not_ok "menu: deleted rows are gone"; else ok "menu: deleted rows are gone"; fi
assert_contains "$out" "apply-overrides: 4 rows in, 1 deleted by prefix, 1 deleted for a dropped command, 0 replaced, 0 added, 2 rows out" "menu: assemble logs the summary"
# a wrong expect_rows fails the build
sed -i 's/"expect_rows": 2/"expect_rows": 3/' "$r/menu/overrides.jsonc"
out=$(run "$d/dest-badmenu" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "menu: expect_rows mismatch fails assemble"
assert_contains "$out" "expect_rows is 3 but the rewritten menu has 2 rows" "and names the menu step"
sed -i 's/"expect_rows": 3/"expect_rows": 2/' "$r/menu/overrides.jsonc"

# assert_fails cannot tell the guard from the pre-existing "matches nothing" failure,
# so these two pin the guard by its message.
echo '../outside' >> "$r/build/drop.list"
out=$(run "$d/dest6" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a drop line escaping the tree with .. fails the build"
assert_contains "$out" "must be a relative path inside the tree" "and names the guard, not a later failure"
sed -i '$d' "$r/build/drop.list"

echo '/etc' >> "$r/build/drop.list"
out=$(run "$d/dest7" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a drop line starting with / fails the build"
assert_contains "$out" "must be a relative path inside the tree" "and names the guard"
sed -i '$d' "$r/build/drop.list"

echo 'default/foo..bar' >> "$r/build/drop.list"
out=$(run "$d/dest10" 2>&1) && rc=0 || rc=$?
assert_contains "$out" "matches nothing" "a name that merely contains .. is not treated as an escape"
sed -i '$d' "$r/build/drop.list"

mkdir -p "$d/x"
tar -xzf "$tb" -C "$d/x"
ln -s omarchy-keep-me "$d/x/omarchy-fixture/bin/omarchy-alias"
tar -C "$d/x" -czf "$d/symlink-bin.tar.gz" omarchy-fixture
tb_symlink=$d/symlink-bin.tar.gz
run_symlink() { TINKERO_ROOT=$r "$ROOT/build/assemble" "$tb_symlink" "$1"; }
assert_fails "a symlink in upstream bin/ fails the build" run_symlink "$d/dest8"

echo 'bin/omarchy-renamed-upstream' >> "$r/build/drop.list"
assert_fails "a drop line matching nothing fails the build" run "$d/dest2"
sed -i '$d' "$r/build/drop.list"
printf '#!/bin/bash\n' > "$r/distro/fedora/replacements/omarchy-brand-new"
assert_fails "a replacement with no upstream namesake fails" run "$d/dest3"
echo omarchy-brand-new > "$r/distro/fedora/replacements.new"
run "$d/dest4" >/dev/null; assert_file "$d/dest4/usr/bin/omarchy-brand-new" "unless declared in replacements.new"
# destructive: corrupt the patch, then restore it, so a case added below still sees a working fixture
cp "$r/patches/0001-version.patch" "$d/patch.bak"
sed -i 's/pacman -Q omarchy/pacman -Q something-else/' "$r/patches/0001-version.patch"
out=$(run "$d/dest5" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a patch that no longer applies fails the build"
assert_contains "$out" "patch failed: 0001-version.patch" "and names the patch"
cp "$d/patch.bak" "$r/patches/0001-version.patch"
run "$d/dest9" >/dev/null 2>&1; assert_eq "$?" 0 "the fixture is intact again after the destructive case"
rm -rf "$d"; finish
