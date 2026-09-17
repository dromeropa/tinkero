#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp)
cat > "$d/lock" <<'L'
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
tinkero_rev=3
L
reset_lock() {
  cat > "$d/lock" <<'L'
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
tinkero_rev=3
L
}
r() { TINKERO_LOCK=$d/lock TINKERO_BUILD_DATE='Thu Sep 17 2026' "$ROOT/build/render-spec" "$d/out.spec"; }
r >/dev/null; s=$(cat "$d/out.spec")
assert_contains "$s" "Version:        4.0.4" "version is the tag without v"
assert_contains "$s" "Release:        3%{?dist}" "release is tinkero_rev"
assert_contains "$s" "Requires:       (hyprland >= 0.56.2 with hyprland < 0.57)" "hyprland range is derived from the lock"
assert_contains "$s" "Requires:       quickshell = 0.3.0^20.git28771c7" "quickshell pin is verbatim"
assert_contains "$s" "tinkero-nerd-fonts" "the Nerd font from the COPR is a hard requirement"
assert_contains "$s" "Source0:        omarchy-c668141e9c42b13c80c9ca4ea108e11708c5e8a5.tar.gz" "source names the commit"
assert_eq "$(grep -c '@[A-Z_]*@' "$d/out.spec")" "0" "no placeholder left"
sed -i 's/^hyprland=.*/hyprland=0.56/' "$d/lock"
assert_fails "a malformed hyprland version is rejected" r

reset_lock
sed -i 's/^omarchy_commit=.*/omarchy_commit=abc/' "$d/lock"
assert_fails "a truncated omarchy_commit is rejected" r

reset_lock
sed -i 's/^quickshell=.*/quickshell=0.3|x/' "$d/lock"
assert_fails "a quickshell value with unsupported characters is rejected" r

reset_lock
sed -i 's/^hyprland=.*/hyprland=0.09.1/' "$d/lock"
r >/dev/null; s2=$(cat "$d/out.spec")
assert_contains "$s2" "hyprland < 0.10" "a zero-padded minor is not read as octal"

rm -rf "$d"; finish
