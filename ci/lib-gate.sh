# shellcheck shell=bash
# compare_with_allowlist FOUND_FILE ALLOW_FILE WHAT
# FOUND_FILE: sorted unique findings, one per line. ALLOW_FILE: allowed findings,
# '#' comments and blank lines ignored. Fails on findings that are not allowed
# AND on allowed entries that were not found, so the allowlist can only shrink.
# With TINKERO_GATE_WRITE=1 it rewrites ALLOW_FILE from the findings instead.
compare_with_allowlist() {
  local found=$1 allow=$2 what=$3 rc=0 tmp
  if [[ ${TINKERO_GATE_WRITE:-0} == 1 ]]; then
    { echo "# Baseline written by './dev baseline'. Entries may only be removed, never added by hand."
      echo "# Each one is work owed by a later plan; see docs/superpowers/plans/."
      cat "$found"; } > "$allow"
    echo "WROTE: $allow ($(wc -l < "$found") entries)"; return 0
  fi
  tmp=$(mktemp)
  grep -vE '^\s*(#|$)' "$allow" 2>/dev/null | sed 's/[[:space:]]*#.*$//' | sort -u > "$tmp" || true
  local extra stale
  extra=$(comm -23 "$found" "$tmp"); stale=$(comm -13 "$found" "$tmp")
  if [[ -n $extra ]]; then
    echo "FAIL: $what not on the allowlist ($allow):"; echo "  ${extra//$'\n'/$'\n'  }"; rc=1
  fi
  if [[ -n $stale ]]; then
    echo "FAIL: stale allowlist entries (no longer found; delete them from $allow):"; echo "  ${stale//$'\n'/$'\n'  }"; rc=1
  fi
  rm -f "$tmp"
  [[ $rc -eq 0 ]] && echo "PASS: $what ($(wc -l < "$found") allowed finding(s))"
  return $rc
}
