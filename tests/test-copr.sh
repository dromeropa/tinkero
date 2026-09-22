#!/bin/bash
# bin/tinkero-copr against a stub copr-cli that logs its argv and fails "add" for
# packages already registered.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
cat > "$d/bin/copr-cli" <<'S'
#!/bin/bash
echo "copr-cli $*" >> "$LOG"
# fail all commands if FAIL_ALL is set
[[ ${FAIL_ALL:-} == 1 ]] && { echo "auth failed" >&2; exit 1; }
# add-package-scm fails for a package listed in $EXISTING, edit succeeds for it
if [[ $1 == add-package-scm ]]; then
  for a in "$@"; do [[ $a == --name ]] && next=1 && continue; [[ ${next:-} == 1 ]] && { name=$a; break; }; done
  grep -qx "$name" "$EXISTING" 2>/dev/null && exit 1
fi
exit 0
S
chmod +x "$d/bin/copr-cli"; export PATH=$d/bin:$PATH EXISTING=$d/existing; : > "$EXISTING"
T=$ROOT/bin/tinkero-copr
assert_eq "$("$T" order | head -n1)" tinkero-nerd-fonts "order: first package"
assert_eq "$("$T" order | wc -l)" 25 "order: all 25"
assert_eq "$("$T" order hyprutils glaze | paste -sd' ')" "glaze hyprutils" "order: subset keeps canonical order"
"$T" build nope >/dev/null 2>&1; assert_eq "$?" 1 "unknown package is an error"
: > "$LOG"; TINKERO_COPR_PROJECT=me/proj "$T" register glaze >/dev/null
assert_contains "$(cat "$LOG")" "add-package-scm me/proj --name glaze --clone-url https://github.com/dromeropa/tinkero.git --commit master --subdir distro/fedora/specs --spec glaze.spec --type git --method make_srpm" "register: add with the SCM settings"
echo glaze > "$EXISTING"; : > "$LOG"; out=$("$T" register glaze)
assert_contains "$(cat "$LOG")" "edit-package-scm dromero/tinkero --name glaze" "register: falls back to edit when the package exists"
assert_contains "$out" "updated:    glaze" "and says so"
: > "$LOG"; TINKERO_COPR_COMMIT=task/x "$T" build glaze hyprutils >/dev/null
assert_eq "$(grep -c build-package "$LOG")" 2 "build: one build-package call per package"
assert_eq "$(grep build-package "$LOG" | head -n1)" "copr-cli build-package dromero/tinkero --name glaze" "build: in order, waiting (no --nowait)"
: > "$LOG"; out=$(TINKERO_COPR_DRY_RUN=1 "$T" build glaze 2>&1)
assert_eq "$(wc -l < "$LOG")" 0 "dry run calls nothing"; assert_contains "$out" "copr-cli build-package dromero/tinkero --name glaze" "dry run prints the command"
out=$(FAIL_ALL=1 "$T" register glaze 2>&1); rc=$?
assert_eq "$rc" 1 "register: both calls failing is an error"
assert_contains "$out" "add-package-scm said: auth failed" "register: shows add's own error when both calls fail"
"$T" >/dev/null 2>&1; assert_eq "$?" 2 "no command prints usage and exits 2"
rm -rf "$d"; finish
