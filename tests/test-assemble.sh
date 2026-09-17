#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src")
# a private repo root so the test controls drop.list, patches and replacements
r=$d/root; mkdir -p "$r"/{build,patches,distro/fedora/replacements,session,bin}
cp "$ROOT/session/tinkero.desktop" "$r/session/"
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
run() { TINKERO_ROOT=$r "$ROOT/build/assemble" "$tb" "$1"; }

run "$d/dest" >/dev/null
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

echo '../outside' >> "$r/build/drop.list"
assert_fails "a drop line escaping the tree with .. fails the build" run "$d/dest6"
sed -i '$d' "$r/build/drop.list"

echo '/etc' >> "$r/build/drop.list"
assert_fails "a drop line starting with / fails the build" run "$d/dest7"
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
sed -i 's/pacman -Q omarchy/pacman -Q something-else/' "$r/patches/0001-version.patch"
assert_fails "a patch that no longer applies fails the build" run "$d/dest5"
rm -rf "$d"; finish
