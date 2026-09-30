# Issue #51: omarchy-launch-webapp browser fallback, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `omarchy-launch-webapp` never runs the literal `--app=URL` as a program: it opens the URL as a Chromium `--app` window when any Chromium-family browser is installed (the xdg default first, then a priority list), and as a normal tab through `xdg-open` when none is.

**Architecture:** One new upstream patch, `patches/0013-launch-webapp-browser-fallback.patch`, in the series after 0012. It extends issue #52's shared helper `install/helpers/browser-family.sh` with two functions that reuse its one list and one loop (`browser_family_chromium_is CMD`, `browser_family_chromium_first`), and rewrites `bin/omarchy-launch-webapp` to call them in the issue's order. A new test file applies the real patches to upstream-identical fixtures and drives the patched script through stubs on a closed PATH, in the style of `tests/test-theme-set-browser.sh`. `tinkero.spec.in` gains `xdg-utils`, which owns `xdg-open` and `xdg-settings` and is not installed by Fedora Workstation on its own.

**Tech Stack:** bash (`set -euo pipefail` where the file is Tinkero's own; the patched upstream script keeps upstream's shape), `git apply -p1` patches (strict, no fuzz), the `tests/lib.sh` TAP helpers, ShellCheck.

**Spec:** GitHub issue #51 (body; the thread has no comments). Related: issue #52, landed as commit 49bee54 (patch 0012, the helper this plan reuses).

## Global Constraints

- Never push `master`; commit on the current task branch only; `Closes #51` in the main commit message (`docs/guides/workflow.md`).
- Reuse `install/helpers/browser-family.sh` from patch 0012. The family list appears exactly once in the whole tree (`BROWSER_FAMILY_CHROMIUM_CMDS`); the launcher carries no browser list of its own.
- Family list, verbatim and in this priority order: `chromium`, `chromium-browser`, `google-chrome`, `google-chrome-stable`, `brave`, `brave-browser`, `vivaldi`, `microsoft-edge`.
- Detection order: (1) xdg default browser when its `Exec=` binary is Chromium-family, with `--app=URL`; (2) first installed name from the family list, with `--app=URL`; (3) `xdg-open URL`.
- Patches apply with `git apply -p1`, no fuzz; `patches/series` lists 0013 after 0012.
- Tests never touch the network or run a real package manager; the fixture PATH is closed so the host's browsers cannot leak in.
- Bash is ShellCheck clean (`shellcheck -x -e SC1090,SC1091`). No em dashes in Tinkero's own prose (patch headers, comments, docs, tests).
- Allowlists under `ci/allow/` only shrink; nothing in this plan touches them.
- Verification before completion: `./dev check` and `./dev gates` both pass inside the `tinkero-ci:44` container. GitHub Actions is not a signal for this branch (billing wall).

## Review Focus

Inputs the issue implies but does not spell out, each pinned by a test in Task 1:

1. The xdg default is a Chromium-family browser but a different family member sits earlier in the list and is also installed (Vivaldi default, Chromium on PATH): the default must win, not the list order. Test "vivaldi default: the default wins over chromium on PATH".
2. `xdg-settings` names a desktop file that does not exist under `~/.local`, `~/.nix-profile` or `/usr` (stale default after an uninstall): the launcher must fall through to the scan, not run an empty command. Test "missing default desktop file: scan still finds brave".
3. The default browser is a Flatpak or other wrapper whose `Exec=` is not a family binary (`/usr/bin/flatpak run ...`): treated as not Chromium-family, scan then `xdg-open`. Helper test "a flatpak wrapper is not (basename is flatpak)".
4. Callers pass extra Chromium flags after the URL (`omarchy-install-service-sunshine` passes `--ignore-certificate-errors`): they must follow `--app=URL` on the app path and be dropped, not handed to `xdg-open`, on the fallback path. Tests "extra flags follow --app" and "xdg-open gets the URL only".
5. Neither a browser nor `xdg-open` is installed: a desktop notification and a stderr line, exit 1, nothing executed. Tests under "no browser, no xdg-open".

---

### Task 1: Patch 0013, the launcher rewrite and helper extension, with tests

**Files:**
- Create: `patches/0013-launch-webapp-browser-fallback.patch`
- Modify: `patches/series` (append one line)
- Create: `tests/test-launch-webapp.sh`
- Reference (read only): `patches/0012-browser-family-gate.patch`, `tests/test-theme-set-browser.sh`, `tests/lib.sh`

**Interfaces:**
- Consumes: from patch 0012, `install/helpers/browser-family.sh` with the array `BROWSER_FAMILY_CHROMIUM_CMDS` and the function `browser_family_chromium_present` (no arguments, exit status only).
- Produces: in the same helper, `browser_family_chromium_is CMD` (CMD is a bare name or a path; true when its basename is in the list) and `browser_family_chromium_first` (prints the first list member found on PATH as `command -v` prints it, exit 0; prints nothing and exits 1 when none). `browser_family_chromium_present` keeps its contract and now delegates to `browser_family_chromium_first`. Task 3's docs name these functions.

The upstream file at `v4.0.4` (this is the fixture the test writes, byte for byte):

```bash
#!/bin/bash

# omarchy:summary=Launch a URL as a web app in the default supported browser
# omarchy:args=<url>

browser=$(xdg-settings get default-web-browser)

case $browser in
google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium*) ;;
*) browser="chromium.desktop" ;;
esac

exec setsid uwsm-app -- $(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/$browser 2>/dev/null | head -1) --app="$1" "${@:2}"
```

The bug: with no `chromium.desktop`, the `sed` prints nothing and the command becomes `uwsm-app -- --app=URL`, so `--app=URL` is run as a program.

- [ ] **Step 1: Write the failing test**

Create `tests/test-launch-webapp.sh` with exactly this content:

```bash
#!/bin/bash
# bin/omarchy-launch-webapp after patches/0013 (issue #51): never run "--app=URL" as a
# program. Detection order: the xdg default browser when it is Chromium-family, else the
# first Chromium-family executable on PATH (install/helpers/browser-family.sh, issue #52),
# else xdg-open for a plain tab. Applies the real patches to an upstream-identical fixture
# of the launcher, then runs the patched script under stub xdg-settings, setsid, uwsm-app,
# xdg-open and omarchy-notification-send on a PATH scoped to the fixture, so the host's own
# browsers (if any) cannot leak into the result.
source "$(dirname "$0")/lib.sh"
d=$(mktmp)
tree=$d/tree; mkdir -p "$tree/bin" "$tree/install/helpers" "$d/home/.local/share/applications"

cat > "$tree/bin/omarchy-launch-webapp" <<'S'
#!/bin/bash

# omarchy:summary=Launch a URL as a web app in the default supported browser
# omarchy:args=<url>

browser=$(xdg-settings get default-web-browser)

case $browser in
google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium*) ;;
*) browser="chromium.desktop" ;;
esac

exec setsid uwsm-app -- $(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/$browser 2>/dev/null | head -1) --app="$1" "${@:2}"
S
chmod +x "$tree/bin/omarchy-launch-webapp"

# Patch 0012 creates the shared helper; its other hunk (bin/omarchy-theme-set-browser) is
# tests/test-theme-set-browser.sh's business and is left out here. Patch 0013 then extends
# the helper and rewrites the launcher on top of it, exactly as build/assemble orders them.
( cd "$tree" && git apply -p1 --include='install/helpers/browser-family.sh' "$ROOT/patches/0012-browser-family-gate.patch" ) ||
  { echo "patch 0012-browser-family-gate.patch (helper hunk) did not apply" >&2; exit 2; }
( cd "$tree" && git apply -p1 "$ROOT/patches/0013-launch-webapp-browser-fallback.patch" ) ||
  { echo "patch 0013-launch-webapp-browser-fallback.patch did not apply" >&2; exit 2; }
# shellcheck disable=SC2016  # the $OMARCHY_PATH below is the patched script's literal text, not this shell's
assert_contains "$(cat "$tree/bin/omarchy-launch-webapp")" \
  'source "$OMARCHY_PATH/install/helpers/browser-family.sh"' "patch makes the launcher source the shared helper"
assert_eq "$(grep -c 'chromium-browser\|google-chrome\|microsoft-edge' "$tree/bin/omarchy-launch-webapp")" 0 \
  "the launcher carries no browser list of its own (the helper's is the only one)"
assert_eq "$(grep -c 'BROWSER_FAMILY_CHROMIUM_CMDS=(' "$tree/install/helpers/browser-family.sh")" 1 \
  "the helper still declares the family list exactly once"

# 1. The helper's new functions, and the old one after its refactor.
source "$tree/install/helpers/browser-family.sh"
for name in chromium chromium-browser google-chrome google-chrome-stable brave brave-browser vivaldi microsoft-edge; do
  browser_family_chromium_is "/usr/bin/$name"
  assert_eq "$?" 0 "helper: $name is Chromium-family when given as a path"
done
browser_family_chromium_is brave
assert_eq "$?" 0 "helper: a bare name is accepted too"
browser_family_chromium_is /usr/lib64/firefox/firefox
assert_eq "$?" 1 "helper: firefox is not Chromium-family"
browser_family_chromium_is /usr/bin/flatpak
assert_eq "$?" 1 "helper: a flatpak wrapper is not (basename is flatpak)"
browser_family_chromium_is ""
assert_eq "$?" 1 "helper: the empty string is not"

make_bin() { printf '#!/bin/bash\n' > "$1"; chmod +x "$1"; }
two=$d/two; mkdir -p "$two"; make_bin "$two/brave"; make_bin "$two/chromium"
empty=$d/empty; mkdir -p "$empty"
assert_eq "$(PATH=$two browser_family_chromium_first)" "$two/chromium" "helper: first follows the list's priority, not PATH order"
assert_eq "$(PATH=$empty browser_family_chromium_first; echo "rc=$?")" "rc=1" "helper: first prints nothing and fails when none is installed"
PATH=$two browser_family_chromium_present
assert_eq "$?" 0 "helper: present is still true after the refactor"
PATH=$empty browser_family_chromium_present
assert_eq "$?" 1 "helper: present is still false with none installed"

# 2. The patched launcher, end to end, on a closed PATH. Every external the script uses is
# either a stub that logs what it was asked to run or the host's real sed/head linked in.
stub=$d/stub; xs=$d/xdg-settings; xo=$d/xdg-open; mkdir -p "$stub" "$xs" "$xo"
export LOG=$d/log
cat > "$xs/xdg-settings" <<'S'
#!/bin/bash
[[ $1 == get && $2 == default-web-browser ]] || exit 1
printf '%s\n' "${XDG_DEFAULT-}"
S
cat > "$stub/setsid" <<'S'
#!/bin/bash
exec "$@"
S
cat > "$stub/uwsm-app" <<'S'
#!/bin/bash
[[ $1 == -- ]] && shift
echo "uwsm-app $*" >> "$LOG"
S
cat > "$xo/xdg-open" <<'S'
#!/bin/bash
echo "xdg-open $*" >> "$LOG"
S
cat > "$stub/omarchy-notification-send" <<'S'
#!/bin/bash
echo "notify $*" >> "$LOG"
S
chmod +x "$xs"/* "$xo"/* "$stub"/*
for t in sed head; do ln -s "$(command -v "$t")" "$stub/$t"; done

apps_ff=$d/apps-firefox; apps_brave=$d/apps-brave; apps_both=$d/apps-both
mkdir -p "$apps_ff" "$apps_brave" "$apps_both"
make_bin "$apps_ff/firefox"
make_bin "$apps_brave/brave"
make_bin "$apps_both/firefox"; make_bin "$apps_both/chromium"; make_bin "$apps_both/vivaldi"

# Desktop files under the fixture HOME, with names no real /usr/share/applications carries.
desk=$d/home/.local/share/applications
printf '[Desktop Entry]\nName=Firefox\nExec=%s %%u\n' "$apps_ff/firefox" > "$desk/tinkero-test-firefox.desktop"
printf '[Desktop Entry]\nName=Vivaldi\nExec=%s %%U\n' "$apps_both/vivaldi" > "$desk/tinkero-test-vivaldi.desktop"
printf '[Desktop Entry]\nName=Chromium\nExec=%s %%U\n' "$apps_both/chromium" > "$desk/tinkero-test-chromium.desktop"
printf '[Desktop Entry]\nName=Brave\nExec=/usr/bin/flatpak run com.brave.Browser %%U\n' > "$desk/tinkero-test-flatpak.desktop"

# run APPS_PATH XDG_DEFAULT WITH_XDG_SETTINGS WITH_XDG_OPEN ARGS...: prints the exit status.
# The script is run directly (it is +x with a #!/bin/bash shebang) rather than as `bash
# SCRIPT`, so the closed PATH does not have to resolve bash itself.
run() {
  local apps=$1 default=$2 with_settings=$3 with_open=$4 p=$stub; shift 4
  (( with_settings )) && p=$p:$xs
  (( with_open )) && p=$p:$xo
  [[ -n $apps ]] && p=$p:$apps
  : > "$LOG"
  OMARCHY_PATH=$tree HOME=$d/home PATH=$p XDG_DEFAULT=$default \
    "$tree/bin/omarchy-launch-webapp" "$@" </dev/null >"$d/out" 2>"$d/err"
  echo $?
}
U=https://wiki.hypr.land/

# Only Firefox installed and it is the default (a stock Tinkero): a plain tab via xdg-open.
rc=$(run "$apps_ff" tinkero-test-firefox.desktop 1 1 "$U")
assert_eq "$rc" 0 "firefox only: exits 0"
assert_eq "$(cat "$LOG")" "uwsm-app xdg-open $U" "firefox only: opens the URL with xdg-open through uwsm-app"
assert_eq "$(grep -c -- '--app=' "$LOG")" 0 "firefox only: --app never appears"

# Brave installed but Firefox is the default: Brave gets the borderless --app window.
rc=$(run "$apps_ff:$apps_brave" tinkero-test-firefox.desktop 1 1 "$U")
assert_eq "$rc" 0 "brave present, not default: exits 0"
assert_eq "$(cat "$LOG")" "uwsm-app $apps_brave/brave --app=$U" "brave present, not default: brave --app window"

# Chromium is the xdg default: Chromium with --app.
run "$apps_both" tinkero-test-chromium.desktop 1 1 "$U" >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_both/chromium --app=$U" "chromium default: chromium --app"

# A Chromium-family default wins over an earlier list entry that is also installed.
run "$apps_both" tinkero-test-vivaldi.desktop 1 1 "$U" >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_both/vivaldi --app=$U" "vivaldi default: the default wins over chromium on PATH"

# A Flatpak default is not a family binary: the scan finds the native one instead.
run "$apps_both" tinkero-test-flatpak.desktop 1 1 "$U" >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_both/chromium --app=$U" "flatpak default: not family, the scan picks chromium"

# The default names a desktop file that no longer exists: fall through to the scan.
run "$apps_brave" tinkero-test-missing.desktop 1 1 "$U" >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_brave/brave --app=$U" "missing default desktop file: scan still finds brave"

# xdg-settings reports no default at all, and xdg-settings missing outright (no xdg-utils).
run "$apps_brave" "" 1 1 "$U" >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_brave/brave --app=$U" "empty default: scan finds brave"
run "$apps_brave" "" 0 1 "$U" >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_brave/brave --app=$U" "no xdg-settings on PATH: scan finds brave"

# Extra Chromium flags after the URL ride along on the --app path and are dropped on the
# xdg-open path (omarchy-install-service-sunshine passes --ignore-certificate-errors).
run "$apps_brave" "" 1 1 "$U" --ignore-certificate-errors >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app $apps_brave/brave --app=$U --ignore-certificate-errors" "extra flags follow --app"
run "$apps_ff" "" 1 1 "$U" --ignore-certificate-errors >/dev/null
assert_eq "$(cat "$LOG")" "uwsm-app xdg-open $U" "xdg-open gets the URL only"

# No browser at all, xdg-open present: xdg-open is handed the URL and reports the outcome itself.
rc=$(run "" "" 1 1 "$U")
assert_eq "$rc" 0 "no browser: hands off to xdg-open"
assert_eq "$(cat "$LOG")" "uwsm-app xdg-open $U" "no browser: xdg-open is still asked"

# No browser and no xdg-open: a user-facing notification, a stderr line, exit 1, nothing run.
rc=$(run "" "" 1 0 "$U")
assert_eq "$rc" 1 "no browser, no xdg-open: exit 1"
assert_eq "$(grep -c '^uwsm-app' "$LOG")" 0 "no browser, no xdg-open: nothing launched"
assert_contains "$(cat "$LOG")" "notify -u critical No web browser found" "no browser, no xdg-open: desktop notification"
assert_contains "$(cat "$d/err")" "no web browser" "no browser, no xdg-open: stderr says why"

# No URL: usage on stderr, exit 1, nothing run.
rc=$(run "$apps_brave" "" 1 1)
assert_eq "$rc" 1 "no url: exit 1"
assert_eq "$(grep -c '^uwsm-app' "$LOG")" 0 "no url: nothing launched"
assert_contains "$(cat "$d/err")" "Usage: omarchy-launch-webapp" "no url: usage on stderr"

rm -rf "$d"; finish
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-launch-webapp.sh; echo "rc=$?"`
Expected: `patch 0013-launch-webapp-browser-fallback.patch did not apply` on stderr and `rc=2` (the patch file does not exist yet).

- [ ] **Step 3: Write the patch**

Build it from real files so the hunk headers are exact. In a scratch directory (not in the worktree):

```bash
W=/home/diego/worktrees/tinkero/c3b13efe
scratch=$(mktemp -d); cd "$scratch"
git init -q .
mkdir -p bin install/helpers
# The upstream launcher, byte for byte: lift the heredoc body out of the test fixture.
sed -n "/^cat > \"\$tree\/bin\/omarchy-launch-webapp\" <<'S'\$/,/^S\$/p" "$W/tests/test-launch-webapp.sh" | sed '1d;$d' > bin/omarchy-launch-webapp
# The helper as patch 0012 creates it.
git apply -p1 --include='install/helpers/browser-family.sh' "$W/patches/0012-browser-family-gate.patch"
git add -A && git commit -qm base
```

Check: `bin/omarchy-launch-webapp` starts with `#!/bin/bash` and ends with the `exec setsid uwsm-app` line (13 lines), and `install/helpers/browser-family.sh` is 23 lines.

Now replace `install/helpers/browser-family.sh` with exactly this content (the list and its comment are unchanged from 0012; one loop, three entry points):

```bash
# Chromium-family browser detection, shared by anything that must behave differently
# depending on whether a Chromium-engine browser is installed (issues #51, #52). Probed
# by executable name rather than by package or desktop file, since Chrome, Chromium,
# Brave, Vivaldi and Edge all land a plain binary on PATH however they were installed.
BROWSER_FAMILY_CHROMIUM_CMDS=(
  chromium
  chromium-browser
  google-chrome
  google-chrome-stable
  brave
  brave-browser
  vivaldi
  microsoft-edge
)

# True when CMD (a bare name, or a path as read from a desktop file's Exec=) is one of the
# Chromium-family executables.
browser_family_chromium_is() {
  local name=${1##*/} cmd
  for cmd in "${BROWSER_FAMILY_CHROMIUM_CMDS[@]}"; do
    [[ $name == "$cmd" ]] && return 0
  done
  return 1
}

# Print the first Chromium-family browser executable on PATH, in the list's priority order;
# false, printing nothing, when there is none.
browser_family_chromium_first() {
  local cmd
  for cmd in "${BROWSER_FAMILY_CHROMIUM_CMDS[@]}"; do
    command -v "$cmd" 2>/dev/null && return 0
  done
  return 1
}

# True when any Chromium-family browser executable is on PATH.
browser_family_chromium_present() {
  browser_family_chromium_first >/dev/null
}
```

And replace `bin/omarchy-launch-webapp` with exactly this content:

```bash
#!/bin/bash

# omarchy:summary=Launch a URL as a web app in the default supported browser
# omarchy:args=<url>

source "$OMARCHY_PATH/install/helpers/browser-family.sh"

if [[ -z ${1:-} ]]; then
  echo "Usage: omarchy-launch-webapp <url> [browser-flags...]" >&2
  exit 1
fi
url=$1

# 1. The xdg default browser, when it is a Chromium-family binary: the user's own choice
#    gets the borderless --app window.
browser=$(xdg-settings get default-web-browser 2>/dev/null)
browser_exec=""
if [[ -n $browser ]]; then
  browser_exec=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' {~/.local,~/.nix-profile,/usr}/share/applications/"$browser" 2>/dev/null | head -1)
fi
if [[ -n $browser_exec ]] && browser_family_chromium_is "$browser_exec"; then
  exec setsid uwsm-app -- "$browser_exec" --app="$url" "${@:2}"
fi

# 2. Otherwise the first Chromium-family browser on PATH, in the helper's priority order
#    (the --app flag is a Chromium-engine feature, so any of them gives the same window).
if browser_exec=$(browser_family_chromium_first); then
  exec setsid uwsm-app -- "$browser_exec" --app="$url" "${@:2}"
fi

# 3. None installed: a normal tab in whatever browser xdg-open finds. Degraded (no app
#    window, and the Chromium flags after the URL are dropped) but functional, instead of
#    upstream's empty command that ran "--app=URL" as a program (issue #51).
if command -v xdg-open &>/dev/null; then
  exec setsid uwsm-app -- xdg-open "$url"
fi

omarchy-notification-send -u critical "No web browser found" "Install a browser to open $url" 2>/dev/null
echo "omarchy-launch-webapp: no web browser and no xdg-open found to open $url" >&2
exit 1
```

Then produce the patch with the description header (no em dashes) and the diff:

```bash
{
cat <<'H'
Make omarchy-launch-webapp fall back instead of running "--app=URL" as a program.

Upstream resolves the xdg default browser, keeps it only when its desktop-file name
looks Chrome-like, and otherwise substitutes chromium.desktop. On a host with no
Chromium-family browser that desktop file does not exist, the Exec= lookup prints
nothing, and the launch line becomes `uwsm-app -- --app=URL`: the flag is run as a
program and every Learn menu row that uses the launcher fails (issue #51).

Detection now goes: the xdg default browser when its Exec= binary is Chromium-family
(the user's choice keeps the borderless --app window); else the first installed name
from the shared family list; else xdg-open, a plain tab in the default browser. The
list and its loop stay in install/helpers/browser-family.sh (issue #52), which gains
browser_family_chromium_is and browser_family_chromium_first; the old
browser_family_chromium_present now delegates to the latter. With neither a browser
nor xdg-open present the launcher notifies and exits 1 rather than executing nothing.

H
git diff
} > "$W/patches/0013-launch-webapp-browser-fallback.patch"
```

Check the patch file: it must contain `--- a/install/helpers/browser-family.sh` / `+++ b/install/helpers/browser-family.sh` and `--- a/bin/omarchy-launch-webapp` / `+++ b/bin/omarchy-launch-webapp` sections and no `index` lines are required (they are harmless). If `git diff` printed `diff --git` and `index` lines, leave them; `git apply -p1` accepts them.

- [ ] **Step 4: Register the patch in the series**

Append to `patches/series` (it must end with a newline):

```
0013-launch-webapp-browser-fallback.patch
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test-launch-webapp.sh`
Expected: every line `ok`, last line `1..NN` with no `not ok`. If a `not ok` mentions the log content, print `$LOG` and `$d/err` from a scratch copy to see what the stub recorded; do not weaken the assertion.

- [ ] **Step 6: ShellCheck the test and the patched script**

Run (in the worktree):

The scratch repo from Step 3 now holds the patched files, so check them there (the launcher and the helper) together with the test:

```bash
shellcheck -x -e SC1090,SC1091 tests/test-launch-webapp.sh "$scratch/bin/omarchy-launch-webapp" "$scratch/install/helpers/browser-family.sh"
```

Expected: no output. If `shellcheck` is not on the host, run the same command inside the container: `podman run --rm --userns=keep-id --security-opt label=disable -v "$PWD:/work" -v "$scratch:/scratch" -w /work -e HOME=/tmp tinkero-ci:44 shellcheck -x -e SC1090,SC1091 tests/test-launch-webapp.sh /scratch/bin/omarchy-launch-webapp /scratch/install/helpers/browser-family.sh`. If any warning appears, fix the file in the scratch repo, regenerate the patch (the `{ cat ...; git diff; } > ...` command from Step 3), and rerun Step 5.

- [ ] **Step 7: Prove the patch applies to the real upstream tree, in order**

Run: `./dev payload 2>&1 | grep -i 'patch\|error' | head`
Expected: no `patch failed` line. On this host `./dev payload` then stops at `error: branding needs ImageMagick (magick)`; that is after the patch step and is expected here (Task 4 runs it in the container where it completes).

- [ ] **Step 8: Commit**

```bash
git add patches/0013-launch-webapp-browser-fallback.patch patches/series tests/test-launch-webapp.sh
git commit -m "launch-webapp: fall back through the Chromium family to xdg-open instead of running --app=URL as a program

Patch 0013 rewrites bin/omarchy-launch-webapp: the xdg default browser when its
Exec= binary is Chromium-family, else the first installed name from the shared list
in install/helpers/browser-family.sh (issue #52), else xdg-open. The helper gains
browser_family_chromium_is and browser_family_chromium_first; present delegates.
tests/test-launch-webapp.sh applies 0012 and 0013 to an upstream-identical fixture
and drives the patched script through stubs on a closed PATH.

Closes #51

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Gd9PCQPAFriempqibdVrs6"
```

---

### Task 2: Require xdg-utils in the package

**Files:**
- Modify: `tinkero.spec.in:24-30` (the hard-requirements block)
- Test: `tests/test-render-spec.sh` (add one assertion)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: the rendered `tinkero.spec` carries `xdg-utils` in a `Requires:` line.

Why: `xdg-open` (the fallback) and `xdg-settings` (step 1, and upstream's `omarchy-launch-browser`) are in Fedora's `xdg-utils`, which Fedora Workstation does not install on its own (checked on this host: `rpm -q xdg-utils` reports it is not installed and nothing requires it). Without it the fallback would itself be a missing command.

- [ ] **Step 1: Write the failing test**

In `tests/test-render-spec.sh`, directly after the line that asserts the quickshell pin (line 27, `assert_contains "$s" "Requires:       (quickshell = ...`), add:

```bash
assert_contains "$s" "Requires:       xdg-utils" "xdg-utils is required: omarchy-launch-webapp falls back to xdg-open (issue #51)"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-render-spec.sh | grep -A1 'not ok'`
Expected: one `not ok ... xdg-utils is required ...` line.

- [ ] **Step 3: Add the requirement**

In `tinkero.spec.in`, after the line `Requires:       grim slurp wl-clipboard wtype tensaku hyprland-preview-share-picker ttfx`, add these two lines:

```
# xdg-utils: omarchy-launch-browser resolves the default browser with xdg-settings and
# omarchy-launch-webapp falls back to xdg-open (issue #51); Workstation does not pull it in.
Requires:       xdg-utils
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/test-render-spec.sh | tail -3 && bash tests/test-specs.sh | tail -2`
Expected: no `not ok`; final lines `1..N`.

- [ ] **Step 5: Commit**

```bash
git add tinkero.spec.in tests/test-render-spec.sh
git commit -m "spec: require xdg-utils, which owns the xdg-open fallback and xdg-settings (issue #51)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Gd9PCQPAFriempqibdVrs6"
```

---

### Task 3: Record the change in the audit and the roadmap

**Files:**
- Modify: `docs/research/arch-coupling-audit.md:205` (section 7, the keybindings paragraph's last sentence) and `:217-233` (section 9, the patch list)
- Modify: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md:101`
- Modify: `docs/superpowers/plans/2026-09-30-issue-51-launch-webapp-fallback.md` (this file: a `## Deviations` section at the end)

**Interfaces:**
- Consumes: the function names from Task 1 (`browser_family_chromium_is`, `browser_family_chromium_first`) and the patch number 0013.
- Produces: nothing for later tasks.

No em dashes anywhere in these edits.

- [ ] **Step 1: Section 7 of the audit**

In `docs/research/arch-coupling-audit.md`, the paragraph starting `**Keybindings.**` (line 205) ends with this sentence:

```
`omarchy-launch-browser` uses `xdg-settings get default-web-browser`, so it launches Firefox on a stock Fedora without changes; `omarchy-launch-webapp` falls back to Chromium and is unreachable once the web-app chords and menu entries are gone.
```

Replace exactly that sentence with:

```
`omarchy-launch-browser` uses `xdg-settings get default-web-browser`, so it launches Firefox on a stock Fedora without changes. `omarchy-launch-webapp` fell back to `chromium.desktop` and, with no Chromium installed, ran the literal `--app=URL` as a program; upstream's `learn.hyprland`, `learn.neovim` and `learn.bash` menu rows still reach it, so patch 0013 (issue #51) makes it use the xdg default browser when that is Chromium-family, then the first installed name from `install/helpers/browser-family.sh`, then `xdg-open` for a plain tab. `xdg-utils` is a package requirement for that fallback.
```

- [ ] **Step 2: Section 9 of the audit**

Change the first sentence of section 9 from `Twelve files carry a diff against upstream and therefore a rebase cost on each bump. All but the first and patch 0011 are under fifteen changed lines.` to:

```
Fourteen files carry a diff against upstream and therefore a rebase cost on each bump. All but the first, patch 0011 and the launcher in patch 0013 are under fifteen changed lines.
```

After item 11 (`bin/omarchy-launch-about` ...) add two items:

```
12. `bin/omarchy-theme-set-browser` (the browser-policy call gated on Chromium-family presence through the new `install/helpers/browser-family.sh`; 0012, issue #52)
13. `bin/omarchy-launch-webapp` and `install/helpers/browser-family.sh` (the launcher resolves the xdg default, then the family list, then `xdg-open`; the helper gains `browser_family_chromium_is` and `browser_family_chromium_first`; 0013, issue #51)
```

- [ ] **Step 3: The roadmap queue line**

In `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, replace the whole bullet that begins `- **2F or bare metal:** upstream's `learn.hyprland`` (line 101) with:

```
- **2F or bare metal, resolved by issue #51 (2026-09-30):** upstream's `learn.hyprland`, `learn.neovim` and `learn.bash` rows use `omarchy-launch-webapp`, which ran `chromium.desktop` unless the default browser was Chrome-like, and with no Chromium installed ran `--app=URL` as a program. Patch 0013 makes it use the xdg default browser when that is Chromium-family, else the first installed Chromium-family browser (the list in `install/helpers/browser-family.sh`, issue #52), else `xdg-open`; no name-map row for Chromium was needed, and `xdg-utils` is now a package requirement. 2D switched Tinkero's two Learn rows to `omarchy-launch-browser`.
```

- [ ] **Step 4: Deviations section**

Append to the end of this plan file:

```
## Deviations

- (filled in by the implementer: one line per review finding that changed the code, or "None.")
```

The implementer replaces the placeholder line with what actually deviated during Tasks 1 and 2 (the reviewer's findings and how they were fixed), or `- None.`

- [ ] **Step 5: Check the prose**

Run: `grep -n $'\xe2\x80\x94' docs/research/arch-coupling-audit.md docs/superpowers/plans/2026-09-17-phase-2-roadmap.md docs/superpowers/plans/2026-09-30-issue-51-launch-webapp-fallback.md tests/test-launch-webapp.sh patches/0013-launch-webapp-browser-fallback.patch tinkero.spec.in`
Expected: no output (no em dashes).

- [ ] **Step 6: Commit**

```bash
git add docs/research/arch-coupling-audit.md docs/superpowers/plans/2026-09-17-phase-2-roadmap.md docs/superpowers/plans/2026-09-30-issue-51-launch-webapp-fallback.md
git commit -m "docs: record patch 0013 (issue #51) in the audit, the roadmap queue and the plan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Gd9PCQPAFriempqibdVrs6"
```

---

### Task 4: Full verification in the CI container

**Files:** none modified.

- [ ] **Step 1: Run the unit tests and the gates in `tinkero-ci:44`**

From the worktree root:

```bash
podman run --rm --userns=keep-id --security-opt label=disable -v "$PWD:/work" -w /work -e HOME=/tmp tinkero-ci:44 \
  bash -c 'shellcheck -x -e SC1090,SC1091 tests/test-launch-webapp.sh tests/test-render-spec.sh && ./dev check && ./dev gates' 2>&1 | tail -40
```

Expected: no ShellCheck output; `./dev check` prints no `not ok` (a `1..N` line per test file, the Python suite `OK`); `./dev gates` prints a `PASS` line for every gate and no `FAIL`; the command exits 0. Then, in the same container, `./dev spec && rpmspec -P tinkero.spec >/dev/null && rpmlint tinkero.spec` must report no error (the new `Requires` line is the only spec change).

- [ ] **Step 2: Confirm the patched launcher in the real payload**

```bash
grep -c 'browser_family_chromium' .cache/payload/bin/omarchy-launch-webapp
grep -c 'browser_family_chromium_first' .cache/payload/install/helpers/browser-family.sh
```

Expected: `2` or more for the first, `2` for the second (definition plus the delegating call).

- [ ] **Step 3: Push the branch**

```bash
git push -u origin task/c3b13efe
```

No PR. GitHub Actions results are not a signal for this branch.

## Deviations

- Task 1 review: no code deviations. Two minors deferred to the final review: the family list omits Opera and Helium, which upstream accepted as defaults (recorded in the audit, section 7); no launcher-level test for several family browsers on PATH at once (the helper unit test covers list priority).
- Task 2 review: none.
