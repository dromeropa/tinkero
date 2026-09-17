#!/bin/bash
source "$(dirname "$0")/lib.sh"; source "$ROOT/build/lib.sh"
d=$(mktmp); printf '# c\nomarchy_tag=v1.2.3\nquickshell=0.3.0^20.gitabc\n' > "$d/l"
assert_eq "$(lock_get omarchy_tag "$d/l")" "v1.2.3" "reads a plain value"
assert_eq "$(lock_get quickshell "$d/l")" "0.3.0^20.gitabc" "keeps special characters verbatim"
assert_fails "missing key is an error" lock_get nope "$d/l"
# shellcheck disable=SC2016  # single-quoted on purpose: this must stay literal, not be shell-expanded
printf 'x=$(touch %s/pwned)\n' "$d" >> "$d/l"; lock_get x "$d/l" >/dev/null
assert_no_path "$d/pwned" "lock values are never executed"
rm -rf "$d"; finish
