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
