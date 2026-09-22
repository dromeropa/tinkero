#!/bin/bash
# The Fedora replacement wrappers, run against stub package tools on PATH.
# Each stub appends its argv to $LOG; rpm/flatpak answer from files the test writes.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
export TINKERO_PKG_LIB=$ROOT/distro/fedora/lib/pkg.sh TINKERO_PKGMAP=$d/map
printf 'foot\tdnf\tfoot\nvim\tdnf\tvim-enhanced\nsignal-desktop\tflatpak\torg.signal.Signal\nopenclaw\tnone\t-\n' > "$d/map"
# rpm -q NAME: installed if NAME is listed in $d/rpms; rpm -qa --qf: print $d/rpms lines
cat > "$d/bin/rpm" <<'S'
#!/bin/bash
echo "rpm $*" >> "$LOG"
case $1 in
  -q) grep -qx "$2" "${RPMS}" ;;
  -qa) [[ ${3:-} == *INSTALLTIME* ]] && printf '1700000000\n1800000000\n' || cat "${RPMS}" ;;
esac
S
cat > "$d/bin/flatpak" <<'S'
#!/bin/bash
echo "flatpak $*" >> "$LOG"
case $1 in
  info) grep -qx "$2" "${FLATPAKS}" ;;
  remotes) cat "${REMOTES}" ;;
  install|uninstall) exit 0 ;;
esac
S
# shellcheck disable=SC2016  # the $* and $@ below belong to the stub scripts being written, not to this shell
printf '#!/bin/bash\necho "pkexec $*" >> "$LOG"; exec "$@"\n' > "$d/bin/pkexec"
# shellcheck disable=SC2016  # the $* and $@ below belong to the stub scripts being written, not to this shell
printf '#!/bin/bash\necho "sudo $*" >> "$LOG"; exec "$@"\n' > "$d/bin/sudo"
# shellcheck disable=SC2016  # the $* and $@ below belong to the stub scripts being written, not to this shell
printf '#!/bin/bash\necho "dnf $*" >> "$LOG"\n' > "$d/bin/dnf"
chmod +x "$d/bin"/*
export PATH=$d/bin:$PATH RPMS=$d/rpms FLATPAKS=$d/flatpaks REMOTES=$d/remotes
printf 'foot\n' > "$RPMS"; : > "$FLATPAKS"; printf 'fedora\nflathub\n' > "$REMOTES"
R=$ROOT/distro/fedora/replacements

# present / missing
"$R/omarchy-pkg-present" foot;        assert_eq "$?" 0 "present: mapped and installed"
"$R/omarchy-pkg-present" vim;         assert_eq "$?" 1 "present: mapped, not installed"
"$R/omarchy-pkg-present" foot vim;    assert_eq "$?" 1 "present: all names must be installed"
"$R/omarchy-pkg-present" nope;        assert_eq "$?" 1 "present: unmapped name is not installed"
"$R/omarchy-pkg-present" openclaw;    assert_eq "$?" 1 "present: kind none is never installed"
"$R/omarchy-pkg-missing" foot;        assert_eq "$?" 1 "missing: installed name is not missing"
"$R/omarchy-pkg-missing" foot vim;    assert_eq "$?" 0 "missing: any missing name suffices"

# add: dnf through pkexec inside a graphical session, sudo without one
: > "$LOG"; WAYLAND_DISPLAY=wayland-1 "$R/omarchy-pkg-add" vim >/dev/null 2>&1; rc=$?
assert_contains "$(cat "$LOG")" "pkexec dnf install -y vim-enhanced" "add: dnf target through pkexec in a session"
assert_eq "$rc" 1 "add: fails when the package is still not installed afterwards (stub dnf installs nothing)"
printf 'foot\nvim-enhanced\n' > "$RPMS"
: > "$LOG"; env -u WAYLAND_DISPLAY -u DISPLAY "$R/omarchy-pkg-add" vim >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "add: already installed is a no-op success"
assert_eq "$(cat "$LOG" | grep -c dnf)" 0 "add: no dnf call when nothing is missing"
printf 'foot\n' > "$RPMS"
: > "$LOG"; env -u WAYLAND_DISPLAY -u DISPLAY "$R/omarchy-pkg-add" vim >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "sudo dnf install -y vim-enhanced" "add: sudo outside a graphical session"
: > "$LOG"; out=$("$R/omarchy-pkg-add" openclaw 2>&1); rc=$?
assert_eq "$rc" 1 "add: kind none fails"
assert_contains "$out" "no Fedora package is mapped for 'openclaw'" "add: and explains how to install by hand"
out=$("$R/omarchy-pkg-add" nope 2>&1); assert_contains "$out" "no Fedora package is mapped for 'nope'" "add: unmapped name explains too"
: > "$LOG"; "$R/omarchy-pkg-add" signal-desktop >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "flatpak install -y flathub org.signal.Signal" "add: flatpak target installs from flathub"
printf 'fedora\n' > "$REMOTES"; out=$("$R/omarchy-pkg-add" signal-desktop 2>&1); rc=$?
assert_eq "$rc" 1 "add: no flathub remote fails"; assert_contains "$out" "Flathub is not configured" "add: and says so"

# drop
printf 'foot\n' > "$RPMS"; printf 'org.signal.Signal\n' > "$FLATPAKS"
: > "$LOG"; WAYLAND_DISPLAY=w "$R/omarchy-pkg-drop" foot vim signal-desktop nope >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "drop: succeeds"
assert_contains "$(cat "$LOG")" "pkexec dnf remove -y foot" "drop: removes only installed dnf targets"
assert_contains "$(cat "$LOG")" "flatpak uninstall -y org.signal.Signal" "drop: uninstalls installed flatpaks"
if grep "dnf remove" "$LOG" | grep -q vim-enhanced; then not_ok "drop: skips names that are not installed"; else ok "drop: skips names that are not installed"; fi

# the stubs and one-liners
"$R/omarchy-pkg-aur-accessible";      assert_eq "$?" 1 "aur-accessible: false"
"$R/omarchy-pkg-aur-add" x 2>/dev/null; assert_eq "$?" 1 "aur-add: fails"
"$R/omarchy-update-available";        assert_eq "$?" 1 "update-available: nothing to announce"
assert_eq "$("$R/omarchy-channel-current")" tinkero "channel-current"
assert_eq "$("$R/omarchy-version-channel")" tinkero "version-channel"
"$R/omarchy-channel-set" edge 2>/dev/null; assert_eq "$?" 1 "channel-set: refuses"
"$R/omarchy-hibernation-available";   assert_eq "$?" 1 "hibernation-available: false"
assert_eq "$(TZ=UTC "$R/omarchy-version-pkgs")" "2027-01-15 08:00" "version-pkgs: newest rpm install time"
rm -rf "$d"; finish
