#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src")
c=0123456789abcdef0123456789abcdef01234567
printf 'omarchy_tag=v0\nomarchy_commit=%s\n' "$c" > "$d/lock"
f() { TINKERO_LOCK=$d/lock TINKERO_CACHE=$d/cache TINKERO_UPSTREAM_URL="file://$tb" "$ROOT/build/fetch-upstream" "$@"; }
assert_fails "refuses to build without a recorded checksum" f
out=$(f --record 2>/dev/null)
assert_eq "$out" "$d/cache/omarchy-$c.tar.gz" "--record fetches and prints the path"
assert_eq "$(grep -c '^omarchy_sha256=' "$d/lock")" "1" "--record writes the checksum once"
assert_eq "$(f)" "$d/cache/omarchy-$c.tar.gz" "verifies against the recorded checksum"
sed -i 's/^omarchy_sha256=.*/omarchy_sha256=deadbeef/' "$d/lock"
assert_fails "checksum mismatch fails" f
assert_no_path "$d/cache/omarchy-$c.tar.gz" "and removes the bad download"
printf 'omarchy_commit=v4.0.4\n' > "$d/lock"
assert_fails "a tag is not accepted as a commit id" f
rm -rf "$d"; finish
