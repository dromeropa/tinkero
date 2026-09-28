#!/bin/bash
# tinkero-pam-sync against a fixture PAM directory and a fixture TINKERO_SHARE/pam (design spec
# 4.8; plan 2F design, section 4.2). No sudo, no real /etc: TINKERO_PAM_DIR, TINKERO_SHARE and
# TINKERO_EUID are the seams.
source "$(dirname "$0")/lib.sh"
S=$ROOT/distro/fedora/bin/tinkero-pam-sync
d=$(mktmp)
mkdir -p "$d/pam" "$d/share/pam"
cp "$ROOT/distro/fedora/pam/omarchy-lock-password.wrapped" "$d/share/pam/"
cp "$ROOT/distro/fedora/pam/omarchy-lock-password.plain" "$d/share/pam/"
export TINKERO_PAM_DIR=$d/pam TINKERO_SHARE=$d/share
target=$d/pam/omarchy-lock-password
pa=$d/pam/password-auth

run() { out=$(TINKERO_EUID="${euid:-1000}" "$S" "$@" 2>&1) && rc=0 || rc=$?; }
no_faillock() { printf 'auth        required      pam_unix.so try_first_pass nullok\naccount     required      pam_unix.so\n' > "$pa"; }
active_faillock() { printf 'auth        required      pam_faillock.so preauth silent\nauth        required      pam_unix.so try_first_pass nullok\nauth        required      pam_faillock.so authfail\naccount     required      pam_faillock.so\naccount     required      pam_unix.so\n' > "$pa"; }
commented_faillock() { printf '#auth       required      pam_faillock.so preauth silent\nauth        required      pam_unix.so try_first_pass nullok\naccount     required      pam_unix.so\n' > "$pa"; }
dash_faillock() { printf -- '-auth       required      pam_faillock.so preauth silent\nauth        required      pam_unix.so try_first_pass nullok\naccount     required      pam_unix.so\n' > "$pa"; }
no_temp_files() { [[ -z $(find "$d/pam" -maxdepth 1 -name '.omarchy-lock-password.*') ]]; }

# --- --variant: which variant the host calls for, D6's regex against password-auth -----------
no_faillock
run --variant
assert_eq "$rc" 0 "variant: exit 0"
assert_eq "$out" "wrapped" "variant: no pam_faillock.so in password-auth -> wrapped"

active_faillock
run --variant
assert_eq "$out" "plain" "variant: an active auth line naming pam_faillock.so -> plain"

commented_faillock
run --variant
assert_eq "$out" "wrapped" "variant: a commented #auth pam_faillock.so line does not count -> wrapped"

dash_faillock
run --variant
assert_eq "$out" "plain" "variant: a -auth prefixed (ignore-failure) line still counts -> plain"

# --- writing, as root (TINKERO_EUID seam) -----------------------------------------------------
no_faillock
rm -f "$target"
euid=0 run
assert_eq "$rc" 0 "write: exit 0"
assert_eq "$out" "wrote wrapped" "write: names the variant it wrote"
assert_eq "$(cmp "$target" "$d/share/pam/omarchy-lock-password.wrapped" && echo same)" "same" "write: the file is byte-equal to the wrapped variant"
assert_eq "$(stat -c %a "$target")" "644" "write: mode 0644"
if no_temp_files; then ok "write: no temp file left in the PAM dir"; else not_ok "write: no temp file left in the PAM dir"; fi

mt1=$(stat -c %Y "$target"); sleep 1
euid=0 run
assert_eq "$rc" 0 "write again: exit 0"
assert_eq "$out" "current: wrapped" "write again: already current, says so"
mt2=$(stat -c %Y "$target")
assert_eq "$mt2" "$mt1" "write again: mtime is unchanged (no rewrite)"
if no_temp_files; then ok "write again: no temp file left"; else not_ok "write again: no temp file left"; fi

active_faillock
euid=0 run
assert_eq "$out" "wrote plain" "write: switching the host config to faillock rewrites to plain"
assert_eq "$(cmp "$target" "$d/share/pam/omarchy-lock-password.plain" && echo same)" "same" "write: now byte-equal to the plain variant"

no_faillock
euid=0 run
assert_eq "$out" "wrote wrapped" "write: switching back rewrites to wrapped"

# --- --check ------------------------------------------------------------------------------
no_faillock
euid=0 run   # get back to a known-current state (wrapped)
euid=1000 run --check
assert_eq "$rc" 0 "check: exit 0 when current"
assert_eq "$out" "current: wrapped" "check: names the current variant"

rm -f "$target"
run --check
assert_eq "$rc" 1 "check: exit 1 when the file is missing"
assert_eq "$out" "missing" "check: says missing"

euid=0 run   # wrapped installed
active_faillock   # host now wants plain
run --check
assert_eq "$rc" 1 "check: exit 1 when the wrong variant is installed"
assert_eq "$out" "wrapped installed, plain needed" "check: names both the installed and the wanted variant"

no_faillock   # back to wanting wrapped; put plain on disk to get the reverse message
euid=0 run
active_faillock; euid=0 run; no_faillock
run --check
assert_eq "$out" "plain installed, wrapped needed" "check: the reverse mismatch message"

echo "hand-edited, not either variant" > "$target"
run --check
assert_eq "$rc" 1 "check: exit 1 for a modified file"
assert_eq "$out" "modified" "check: a file that is neither variant is 'modified'"

# --- non-root: write refuses, --check and --variant still work --------------------------------
no_faillock
rm -f "$target"
euid=1000 run
assert_eq "$rc" 2 "non-root write: refuses (exit 2)"
assert_contains "$out" "sudo" "non-root write: names sudo"
assert_no_path "$target" "non-root write: nothing was written"
if no_temp_files; then ok "non-root write: no temp file left"; else not_ok "non-root write: no temp file left"; fi

euid=0 run   # now write it for real, as a base for the read-only checks below
euid=1000 run --check
assert_eq "$rc" 0 "non-root --check: works without root"
euid=1000 run --variant
assert_eq "$rc" 0 "non-root --variant: works without root"
assert_eq "$out" "wrapped" "non-root --variant: correct answer"

# --- errors: missing password-auth, missing variant file, unknown option ----------------------
rm -f "$pa"
run --variant
assert_eq "$rc" 2 "missing password-auth: exit 2"
assert_contains "$out" "password-auth" "missing password-auth: names the file"
no_faillock

f=$d/share/pam/omarchy-lock-password.wrapped
mv "$f" "$f.bak"
euid=0 run
assert_eq "$rc" 2 "missing variant file: exit 2"
assert_contains "$out" "omarchy-lock-password.wrapped" "missing variant file: names the missing file"
if no_temp_files; then ok "missing variant file: no temp file left"; else not_ok "missing variant file: no temp file left"; fi
mv "$f.bak" "$f"

run --nope
assert_eq "$rc" 2 "unknown option: exit 2"
assert_contains "$out" "unknown option" "unknown option: says so"

# --- the packaged variants (issue #46) --------------------------------------------------------
# tests/test_pam_real.py runs these files through real libpam; the text checks below only pin
# their shape. The tally reset is the account phase's `pam_faillock.so`, which the lock runs
# through Tinkero's patched quickshell (pam_acct_mgmt), so neither file needs authsucc.
w=$ROOT/distro/fedora/pam/omarchy-lock-password.wrapped
p=$ROOT/distro/fedora/pam/omarchy-lock-password.plain
active() { grep -vE '^[[:space:]]*(#|$)' "$1"; }
assert_contains "$(active "$w")" "pam_faillock.so preauth silent deny=10 unlock_time=120" "wrapped: preauth with upstream's deny=10 unlock_time=120"
assert_contains "$(active "$w")" "include        password-auth" "wrapped: the host stack comes in with include"
assert_contains "$(active "$w")" "[default=die]  pam_faillock.so authfail deny=10 unlock_time=120" "wrapped: a wrong password is recorded once and dies at authfail"
assert_contains "$(active "$w")" "account  required       pam_faillock.so" "wrapped: the account phase clears the tally"
assert_eq "$(active "$w" | grep -c 'authsucc' || true)" "0" "wrapped: no authsucc (the reset is the account phase's)"
assert_eq "$(active "$w" | grep -E '^account' | awk '{print $2}' | tr '\n' ' ')" "required include " "wrapped: account pam_faillock comes before account include password-auth"
assert_eq "$(active "$p")" "$(printf 'auth     include  password-auth\naccount  include  password-auth')" "plain: exactly the two include lines"
# the #46 class of bug: a bracketed control on include/substack is invalid PAM, and substack is
# not used at all any more
for f in "$ROOT"/distro/fedora/pam/*; do
  n=$(basename "$f")
  assert_eq "$(active "$f" | grep -cE '^[[:space:]]*-?[a-z]+[[:space:]]+\[[^]]*\][[:space:]]+(include|substack)\b' || true)" "0" "$n: no bracketed control on include/substack"
  assert_eq "$(active "$f" | grep -c 'substack' || true)" "0" "$n: no substack line"
done

# --- --tally: the per-boot tmpfiles.d entry for /run/faillock/<user> (issue #29) --------------
tf=$d/tmpfiles; mkdir -p "$tf"
# TINKERO_TALLY_CHECK_USER=0: the fixture users below need not exist on the test host.
export TINKERO_TMPFILES_DIR=$tf TINKERO_TMPFILES_APPLY=0 TINKERO_TALLY_CHECK_USER=0
tally_file=$tf/tinkero-lockout-alice.conf
no_tally_temp() { [[ -z $(find "$tf" -maxdepth 1 -name '.tinkero-lockout.*') ]]; }

euid=1000 run --tally alice
assert_eq "$rc" 2 "tally: non-root refuses (exit 2)"
assert_contains "$out" "sudo" "tally: names sudo"
assert_no_path "$tally_file" "tally: non-root wrote nothing"
if no_tally_temp; then ok "tally: non-root left no temp file"; else not_ok "tally: non-root left no temp file"; fi

euid=0 run --tally alice
assert_eq "$rc" 0 "tally: root writes the entry (exit 0)"
assert_eq "$out" "wrote tally alice" "tally: names what it wrote"
assert_file "$tally_file" "tally: the tmpfiles.d entry exists"
assert_contains "$(cat "$tally_file")" "f /run/faillock/alice 0660 alice root -" "tally: seeds /run/faillock/alice 0660 owned user:root, as faillock does"
assert_eq "$(stat -c %a "$tally_file")" "644" "tally: the entry file is mode 0644"
if no_tally_temp; then ok "tally: no temp file left"; else not_ok "tally: no temp file left"; fi

mt1=$(stat -c %Y "$tally_file"); sleep 1
euid=0 run --tally alice
assert_eq "$rc" 0 "tally again: exit 0"
assert_eq "$out" "current: tally alice" "tally again: already current, says so"
assert_eq "$(stat -c %Y "$tally_file")" "$mt1" "tally again: the file is not rewritten"

euid=0 run --tally bob
assert_file "$tf/tinkero-lockout-bob.conf" "tally: a second user gets its own entry"
assert_contains "$(cat "$tf/tinkero-lockout-bob.conf")" "f /run/faillock/bob 0660 bob root -" "tally: the second user's entry names that user"

euid=0 run --tally
assert_eq "$rc" 2 "tally: a missing user name is an error (exit 2)"
assert_contains "$out" "user name" "tally: says a user name is needed"

# a name that would escape /run/faillock or corrupt the tmpfiles.d line is refused (charset check
# is always on, even with the existence check seamed off)
euid=0 run --tally "../evil"
assert_eq "$rc" 2 "tally: a path-traversal user name is refused (exit 2)"
assert_contains "$out" "invalid user name" "tally: says the name is invalid"
assert_no_path "$tf/tinkero-lockout-../evil.conf" "tally: nothing was written for a bad name"

# the existence check (seamed on) refuses a user with no account
out=$(TINKERO_EUID=0 TINKERO_TALLY_CHECK_USER=1 "$S" --tally tinkero_nosuchuser_zzz 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "tally: a nonexistent account is refused (exit 2)"
assert_contains "$out" "no such user" "tally: says there is no such user"

unset TINKERO_TMPFILES_DIR TINKERO_TMPFILES_APPLY TINKERO_TALLY_CHECK_USER

# -h/--help
out=$("$S" -h); assert_contains "$out" "tinkero-pam-sync --check" "help: usage lists --check"
out=$("$S" --help); rc=$?
assert_eq "$rc" 0 "--help: exit 0"

rm -rf "$d"; finish
