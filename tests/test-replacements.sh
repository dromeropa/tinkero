#!/bin/bash
# The Fedora replacement wrappers, run against stub package tools on PATH.
# Each stub appends its argv to $LOG; rpm/flatpak answer from files the test writes.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
export TINKERO_PKG_LIB=$ROOT/distro/fedora/lib/pkg.sh TINKERO_PKGMAP=$d/map TINKERO_EUID=1000
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
: > "$LOG"; TINKERO_EUID=0 "$R/omarchy-pkg-add" vim >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "dnf install -y vim-enhanced" "add: runs dnf directly when already root"
if grep -qE "^(pkexec|sudo) " "$LOG"; then not_ok "add: no pkexec or sudo when already root"; else ok "add: no pkexec or sudo when already root"; fi
: > "$LOG"; out=$("$R/omarchy-pkg-add" openclaw 2>&1); rc=$?
assert_eq "$rc" 1 "add: kind none fails"
assert_contains "$out" "no Fedora package is mapped for 'openclaw'" "add: and explains how to install by hand"
out=$("$R/omarchy-pkg-add" nope 2>&1); assert_contains "$out" "no Fedora package is mapped for 'nope'" "add: unmapped name explains too"
: > "$LOG"; "$R/omarchy-pkg-add" signal-desktop >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "flatpak install -y flathub org.signal.Signal" "add: flatpak target installs from flathub"
printf 'fedora\n' > "$REMOTES"; out=$("$R/omarchy-pkg-add" signal-desktop 2>&1); rc=$?
assert_eq "$rc" 1 "add: no flathub remote fails"; assert_contains "$out" "Flathub is not configured" "add: and says so"
mv "$d/bin/flatpak" "$d/bin/flatpak.off"
out=$("$R/omarchy-pkg-add" signal-desktop 2>&1)
assert_contains "$out" "flatpak is not installed" "add: distinguishes a missing flatpak from a missing remote"
mv "$d/bin/flatpak.off" "$d/bin/flatpak"

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

# provisioning wrappers (plan 2E): exec tinkero-provision, flags passed through
# shellcheck disable=SC2016  # the $* below belongs to the stub script being written, not to this shell
cat > "$d/bin/tinkero-provision" <<'S'
#!/bin/bash
echo "tinkero-provision${*:+ $*}" >> "$LOG"
S
chmod +x "$d/bin/tinkero-provision"
: > "$LOG"; "$R/omarchy-provision-first-run"; assert_eq "$(cat "$LOG")" "tinkero-provision --session" "first-run: session mode"
: > "$LOG"; "$R/omarchy-provision-first-run" --force; assert_eq "$(cat "$LOG")" "tinkero-provision --session --force" "first-run: --force passes through"
: > "$LOG"; "$R/omarchy-provision-user"; assert_eq "$(cat "$LOG")" "tinkero-provision" "provision-user: a plain provision"

# fingerprint setup/remove (plan 2F): the hardware check, fprintd and authselect on PATH,
# argv logged the same way as the package tool stubs above; exit codes come from files so a
# later case can flip just one without rebuilding the others.
printf '0\n' > "$d/hw-rc"; printf '0\n' > "$d/enroll-rc"; printf '0\n' > "$d/verify-rc"
export HW_RC=$d/hw-rc ENROLL_RC=$d/enroll-rc VERIFY_RC=$d/verify-rc
cat > "$d/bin/omarchy-hw-fingerprint" <<'S'
#!/bin/bash
echo "omarchy-hw-fingerprint" >> "$LOG"
exit "$(cat "$HW_RC")"
S
cat > "$d/bin/omarchy-pkg-add" <<'S'
#!/bin/bash
echo "omarchy-pkg-add $*" >> "$LOG"
S
cat > "$d/bin/fprintd-enroll" <<'S'
#!/bin/bash
echo "fprintd-enroll $*" >> "$LOG"
exit "$(cat "$ENROLL_RC")"
S
cat > "$d/bin/fprintd-verify" <<'S'
#!/bin/bash
echo "fprintd-verify $*" >> "$LOG"
exit "$(cat "$VERIFY_RC")"
S
cat > "$d/bin/authselect" <<'S'
#!/bin/bash
echo "authselect $*" >> "$LOG"
S
cat > "$d/bin/omarchy-apply-lock" <<'S'
#!/bin/bash
echo "omarchy-apply-lock $*" >> "$LOG"
S
chmod +x "$d/bin"/*
logseq() { awk '{print $1}' "$LOG" | paste -sd, -; }

# setup: no reader -> exit 1, nothing else called
printf '1\n' > "$HW_RC"
: > "$LOG"; "$R/omarchy-setup-security-fingerprint" >/dev/null 2>&1; rc=$?
assert_eq "$rc" 1 "fingerprint setup: no reader fails"
assert_eq "$(logseq)" "omarchy-hw-fingerprint" "fingerprint setup: no reader calls nothing else"
printf '0\n' > "$HW_RC"

# setup: happy path, elevated through pkexec inside a session
: > "$LOG"; WAYLAND_DISPLAY=w "$R/omarchy-setup-security-fingerprint" >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "fingerprint setup: happy path succeeds"
assert_eq "$(logseq)" "omarchy-hw-fingerprint,omarchy-pkg-add,fprintd-enroll,fprintd-verify,pkexec,authselect,pkexec,omarchy-apply-lock" \
  "fingerprint setup: happy path call order (pkg-add, enroll, verify, then authselect and apply-lock through pkexec)"
assert_contains "$(cat "$LOG")" "omarchy-pkg-add fprintd fprintd-pam" "fingerprint setup: pkg-add both package names"
assert_contains "$(cat "$LOG")" "pkexec authselect enable-feature with-fingerprint" "fingerprint setup: authselect enable through pkexec"
assert_contains "$(cat "$LOG")" "pkexec omarchy-apply-lock" "fingerprint setup: apply-lock through pkexec"

# setup: enroll failure -> exit 1, nothing after it runs
printf '1\n' > "$ENROLL_RC"
: > "$LOG"; WAYLAND_DISPLAY=w "$R/omarchy-setup-security-fingerprint" >/dev/null 2>&1; rc=$?
assert_eq "$rc" 1 "fingerprint setup: enroll failure fails"
if grep -qE '^(authselect|omarchy-apply-lock|fprintd-verify) ' "$LOG"; then not_ok "fingerprint setup: enroll failure calls nothing after it"
else ok "fingerprint setup: enroll failure calls nothing after it"; fi
printf '0\n' > "$ENROLL_RC"

# setup: verify failure -> no authselect change (upstream's own exit code: 0, enrollment already happened)
printf '1\n' > "$VERIFY_RC"
: > "$LOG"; WAYLAND_DISPLAY=w "$R/omarchy-setup-security-fingerprint" >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "fingerprint setup: verify failure keeps upstream's exit code"
if grep -qE '^(authselect|omarchy-apply-lock) ' "$LOG"; then not_ok "fingerprint setup: verify failure leaves authselect and the lock alone"
else ok "fingerprint setup: verify failure leaves authselect and the lock alone"; fi
printf '0\n' > "$VERIFY_RC"

# setup: sudo used instead of pkexec without a graphical session
: > "$LOG"; env -u WAYLAND_DISPLAY -u DISPLAY "$R/omarchy-setup-security-fingerprint" >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "sudo authselect enable-feature with-fingerprint" "fingerprint setup: sudo outside a graphical session"
assert_contains "$(cat "$LOG")" "sudo omarchy-apply-lock" "fingerprint setup: apply-lock through sudo too"

# remove: warns, disables the feature and re-applies the lock, drops no package
: > "$LOG"; out=$(WAYLAND_DISPLAY=w "$R/omarchy-remove-security-fingerprint" 2>&1); rc=$?
assert_eq "$rc" 0 "fingerprint remove: succeeds"
assert_contains "$out" "turns fingerprint login off for the whole host" "fingerprint remove: warns before it acts"
assert_contains "$(cat "$LOG")" "pkexec authselect disable-feature with-fingerprint" "fingerprint remove: authselect disable through pkexec"
assert_contains "$(cat "$LOG")" "pkexec omarchy-apply-lock" "fingerprint remove: apply-lock through pkexec"
if grep -q 'pkg-drop' "$LOG"; then not_ok "fingerprint remove: no package removal"; else ok "fingerprint remove: no package removal"; fi

rm -rf "$d"; finish
