#!/bin/bash
# bin/tinkero-update against stub sudo, mise and flatpak: order, skips, and stopping on failure.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin" "$d/bin-nomise"; export LOG=$d/log
# shellcheck disable=SC2016  # the stubs log their own $* at run time
for s in sudo mise flatpak; do
  printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n[[ ${FAIL_%s:-} == 1 ]] && exit 1\nexit 0\n' "$s" "$(tr '[:lower:]' '[:upper:]' <<<"$s")" > "$d/bin/$s"
  chmod +x "$d/bin/$s"
done
cp "$d/bin/sudo" "$d/bin-nomise/sudo"   # a PATH with sudo only: no mise, no flatpak
T=$ROOT/bin/tinkero-update
: > "$LOG"; out=$(PATH=$d/bin:/usr/bin:/bin "$T" 2>&1); rc=$?
assert_eq "$rc" 0 "all three present: exit 0"
assert_eq "$(paste -sd'|' "$LOG")" "sudo dnf upgrade --refresh|mise up|flatpak update" "runs dnf, then mise, then flatpak"
: > "$LOG"; out=$(PATH=$d/bin-nomise:/usr/bin:/bin "$T" 2>&1); rc=$?
assert_eq "$rc" 0 "mise and flatpak absent: still exit 0"
assert_eq "$(paste -sd'|' "$LOG")" "sudo dnf upgrade --refresh" "only dnf ran"
assert_contains "$out" "mise not installed, skipped" "says mise was skipped"
: > "$LOG"; FAIL_SUDO=1 PATH=$d/bin:/usr/bin:/bin "$T" >/dev/null 2>&1; rc=$?
assert_eq "$rc:$(wc -l < "$LOG")" "1:1" "dnf failing stops the script before mise"
rm -rf "$d"; finish
