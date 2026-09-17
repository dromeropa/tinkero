# Minimal test helpers. Source from a test file; call `finish` last.
set -u
T_FAILS=0; T_COUNT=0
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ok()      { T_COUNT=$((T_COUNT+1)); echo "ok $T_COUNT - $1"; }
not_ok()  { T_COUNT=$((T_COUNT+1)); T_FAILS=$((T_FAILS+1)); echo "not ok $T_COUNT - $1"; [[ -n ${2:-} ]] && echo "#   $2"; return 0; }
assert_eq()      { [[ "$1" == "$2" ]] && ok "$3" || not_ok "$3" "expected '$2', got '$1'"; }
assert_file()    { [[ -f "$1" ]] && ok "${2:-file exists: $1}" || not_ok "${2:-file exists: $1}" "missing $1"; }
assert_no_path() { [[ ! -e "$1" && ! -L "$1" ]] && ok "${2:-path absent: $1}" || not_ok "${2:-path absent: $1}" "present $1"; }
assert_symlink() { [[ -L "$1" && "$(readlink "$1")" == "$2" ]] && ok "${3:-symlink $1}" || not_ok "${3:-symlink $1}" "want -> $2, got $(readlink "$1" 2>/dev/null || echo none)"; }
assert_contains(){ grep -qF -- "$2" <<<"$1" && ok "$3" || not_ok "$3" "output lacks '$2': $1"; }
# The description variable is deliberately odd: the command under test is often a shell
# function of the caller that reads the caller's own variables (a plain `local d` would shadow them).
assert_fails()   { local _t_desc=$1; shift; if "$@" >/dev/null 2>&1; then not_ok "$_t_desc" "command succeeded"; else ok "$_t_desc"; fi; }
mktmp()   { mktemp -d "${TMPDIR:-/tmp}/tinkero-test.XXXXXX"; }
finish()  { echo "1..$T_COUNT"; [[ $T_FAILS -eq 0 ]]; }
