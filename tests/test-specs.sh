#!/bin/bash
# Static checks on the COPR package set under distro/fedora/specs/ (no rpm tooling needed).
source "$(dirname "$0")/lib.sh"
D=$ROOT/distro/fedora/specs
mapfile -t order < <(grep -vE '^\s*(#|$)' "$D/build-order.txt")
assert_eq "${#order[@]}" 25 "build-order.txt lists 25 packages"
specs=("$D"/*.spec); assert_eq "${#specs[@]}" 25 "there are 25 spec files"
for s in "${specs[@]}"; do
  n=$(basename "$s" .spec)
  name=$(grep -m1 -E '^Name:' "$s" | awk '{print $2}')
  assert_eq "$name" "$n" "$n: Name matches the file name"
  printf '%s\n' "${order[@]}" | grep -qx "$n" || not_ok "$n is not in build-order.txt"
  assert_file "$s.sources" "$n: has a .sources pin file"
  grep -qE '^Release:\s+[0-9]+.*%\{\?dist\}' "$s" || not_ok "$n: Release must carry %{?dist}"
  # every remote source (not the vendor/zig-cache tarballs srpm.sh generates) has a sha256 pin:
  # names use spec macros, so compare counts, and require the pin lines to be well-formed
  urls=$(grep -E '^Source[0-9]*:' "$s" | grep -E '://|%\{[a-z_]*url\}' | grep -vcE 'vendor\.tar|zig-cache' || true)
  pins=$(grep -cvE '^\s*(#|$)' "$s.sources" || true)
  assert_eq "$pins" "$urls" "$n: one sha256 pin per remote source"
  bad=$(grep -vE '^\s*(#|$)' "$s.sources" | grep -vE '^[0-9a-f]{64}  \S+$' || true)
  [[ -z $bad ]] || not_ok "$n: malformed pin line" "$bad"
  # no dependency on the project we forked from, and no bar or launcher recommended in
  hits=$(grep -nE '^(Requires|BuildRequires|Recommends|Suggests|Provides|Obsoletes|Conflicts):.*(omedora|wofi|nwg-panel|playerctl|whiptail|newt)' "$s" || true)
  [[ -z $hits ]] || not_ok "$n: forbidden dependency line" "$hits"
done
ok "per-spec checks ran"
assert_file "$D/srpm.sh" "srpm.sh present"; assert_file "$D/macros.hyprland" "hyprland macros present"
assert_file "$D/herdr-libvt-only.patch" "herdr patch present"
if grep -q "omedora-self" "$D/srpm.sh"; then not_ok "srpm.sh still has the self-source mode"; else ok "srpm.sh has no self-source mode"; fi
finish
