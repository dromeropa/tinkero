# shellcheck shell=bash
# Shared helpers for build/ and ci/ scripts. Source, do not execute.

# lock_get KEY [FILE]: print the value of KEY from upstream.lock.
# The lock is parsed, never sourced, so nothing in it can execute.
lock_get() {
  local key=$1 file=${2:-${TINKERO_LOCK:-upstream.lock}} line
  if ! line=$(grep -E "^${key}=" "$file" | tail -n1) || [[ -z $line ]]; then
    echo "lock: no key '$key' in $file" >&2
    return 1
  fi
  printf '%s\n' "${line#*=}"
}

die() { echo "error: $*" >&2; exit 1; }
