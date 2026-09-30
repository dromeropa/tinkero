#!/bin/bash
# install/helpers/browser-family.sh (issue #52) and the gate patches/0012 adds to
# bin/omarchy-theme-set-browser: the browser-policy write, and the privilege request
# inside it, must run only when a Chromium-family browser is actually installed. Applies
# the real patch to realistic stand-ins of the upstream files it touches or depends on,
# then runs the patched script under a stub pkexec/sudo and a fixture PATH (an
# "applications" directory holding a stub browser executable, and an empty one with none).
source "$(dirname "$0")/lib.sh"
d=$(mktmp)
tree=$d/tree; mkdir -p "$tree/bin" "$tree/install/helpers" "$d/home"

cat > "$tree/bin/omarchy-theme-set-browser" <<'S'
#!/bin/bash

# omarchy:summary=Apply the current theme color to Chromium, Chrome, Edge, and Brave
# omarchy:hidden=true

source "$OMARCHY_PATH/install/helpers/browser-policy.sh"

CHROMIUM_THEME=$HOME/.local/state/omarchy/current/theme/chromium.theme
THEME_HEX_COLOR=$BROWSER_POLICY_DEFAULT_COLOR

if [[ -f $CHROMIUM_THEME ]]; then
  THEME_HEX_COLOR=$(browser_policy_theme_hex "$(<$CHROMIUM_THEME)")
fi

refresh_running_browser() {
  local process="$1"
  local command="$2"
  local pgrep_args="${3:--x}"

  if omarchy-cmd-present "$command" && pgrep $pgrep_args "$process" >/dev/null; then
    "$command" --refresh-platform-policy --no-startup-window &>/dev/null
  fi
}

failed=0
omarchy-theme-set-browser-policy "${THEME_HEX_COLOR#\#}" || failed=1

refresh_running_browser chromium chromium
refresh_running_browser chrome google-chrome-stable || refresh_running_browser chrome google-chrome
refresh_running_browser msedge microsoft-edge-stable
refresh_running_browser brave brave
# Match on the binary path: the running process is named plain "brave", and a
# bare -f brave-origin pattern would also match the installer's own terminal.
refresh_running_browser /opt/brave-origin-bin/ brave-origin -f

exit "$failed"
S

# A faithful stand-in for the real omarchy-theme-set-browser-policy: it is not part of this
# issue's diff, so only its require_root shape (no-tty, non-root always goes through pkexec)
# matters here, not the managed-policy write that follows it. TINKERO_EUID is this suite's
# usual test seam for "not root" (tests/test-replacements.sh, distro/fedora/lib/pkg.sh), since
# the CI container runs the whole suite as root.
cat > "$tree/bin/omarchy-theme-set-browser-policy" <<'S'
#!/bin/bash
set -euo pipefail
PACKAGED_PATH=/usr/bin/omarchy-theme-set-browser-policy
require_root() {
  if (( ${TINKERO_EUID:-$EUID} == 0 )); then
    return
  elif [[ -t 0 ]]; then
    exec sudo "$PACKAGED_PATH" "$@"
  else
    exec pkexec "$PACKAGED_PATH" "$@"
  fi
}
require_root "$@"
echo "wrote policy for $*"
S

cat > "$tree/install/helpers/browser-policy.sh" <<'S'
BROWSER_POLICY_DEFAULT_COLOR="#1c2027"
browser_policy_theme_hex() { printf '%s' "$BROWSER_POLICY_DEFAULT_COLOR"; }
S

chmod +x "$tree"/bin/*

( cd "$tree" && git apply -p1 "$ROOT/patches/0012-browser-family-gate.patch" ) ||
  { echo "patch 0012-browser-family-gate.patch did not apply" >&2; exit 2; }
# shellcheck disable=SC2016  # the $OMARCHY_PATH below is the patched script's literal text, not this shell's
assert_contains "$(cat "$tree/bin/omarchy-theme-set-browser")" \
  'source "$OMARCHY_PATH/install/helpers/browser-family.sh"' "patch adds the browser-family source line"
assert_file "$tree/install/helpers/browser-family.sh" "patch creates the shared detection helper"

# 1. Direct unit test of the shared helper: each name in the family is detected on its own,
# and an empty PATH is correctly absent.
source "$tree/install/helpers/browser-family.sh"
empty_dir=$d/empty; mkdir -p "$empty_dir"
for name in chromium chromium-browser google-chrome google-chrome-stable brave brave-browser vivaldi microsoft-edge; do
  one=$d/one-$name; mkdir -p "$one"
  printf '#!/bin/bash\n' > "$one/$name"; chmod +x "$one/$name"
  PATH=$one browser_family_chromium_present
  assert_eq "$?" 0 "helper: detects $name"
done
PATH=$empty_dir browser_family_chromium_present
assert_eq "$?" 1 "helper: absent when none of the family is on PATH"

# 2. Integration: the patched omarchy-theme-set-browser, run against a tightly scoped PATH
# so the real host's installed browsers (if any) cannot leak into the result.
stub=$d/stub; mkdir -p "$stub"
cat > "$stub/pkexec" <<'S'
#!/bin/bash
echo "pkexec $*" >> "$LOG"
S
cat > "$stub/sudo" <<'S'
#!/bin/bash
echo "sudo $*" >> "$LOG"
S
cat > "$stub/omarchy-cmd-present" <<'S'
#!/bin/bash
for c in "$@"; do command -v "$c" &>/dev/null || exit 1; done
exit 0
S
chmod +x "$stub"/*
export LOG=$d/log

apps=$d/applications; mkdir -p "$apps"
printf '#!/bin/bash\n' > "$apps/chromium"; chmod +x "$apps/chromium"

run() {
  local extra_bin=$1 full_path=$stub:$tree/bin
  [[ -n $extra_bin ]] && full_path=$stub:$extra_bin:$tree/bin
  : > "$LOG"
  # Run the script directly (it is +x with a #!/bin/bash shebang) rather than as `bash
  # SCRIPT`: PATH is scoped to the fixture below, and `bash` prefixed onto that PATH as the
  # command to run would need to resolve itself through that same restricted PATH first.
  OMARCHY_PATH=$tree HOME=$d/home PATH=$full_path TINKERO_EUID=1000 \
    "$tree/bin/omarchy-theme-set-browser" </dev/null >"$d/out" 2>&1
}

# No Chromium-family browser installed: no polkit/pkexec call, the policy helper never runs.
run ""
assert_eq "$(grep -c 'pkexec\|sudo' "$LOG")" 0 "absent: no privilege requested (no polkit dialog)"
assert_eq "$(grep -c 'wrote policy' "$d/out")" 0 "absent: the policy helper never runs"

# A Chromium-family browser installed: still asks once, via pkexec (no tty in a test run).
run "$apps"
assert_contains "$(cat "$LOG")" "pkexec /usr/bin/omarchy-theme-set-browser-policy 1c2027" "present: asks once via pkexec"
assert_eq "$(grep -c '^sudo ' "$LOG")" 0 "present: no separate sudo prompt alongside pkexec"

rm -rf "$d"; finish
