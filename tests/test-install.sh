#!/bin/bash
# install.sh against stub dnf, sudo, getenforce, uname and tinkero-provision, with a fixture
# os-release and display-manager link. No package manager runs; nothing is fetched.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
I=$ROOT/install.sh
cat > "$d/bin/dnf" <<'S'
#!/bin/bash
echo "dnf $*" >> "$LOG"
[[ $1 == repoquery && ${DNF_FAIL:-0} == 1 ]] && exit 3
case $1 in repoquery) cat "${REPOQUERY:-/dev/null}" ;; esac
S
cat > "$d/bin/sudo" <<'S'
#!/bin/bash
echo "sudo $*" >> "$LOG"; exec "$@"
S
cat > "$d/bin/tinkero-provision" <<'S'
#!/bin/bash
echo "tinkero-provision $*" >> "$LOG"
[[ $1 == --plan ]] && printf 'seed\t.config/hypr/hyprland.lua\n'
exit 0
S
printf '#!/bin/bash\necho Enforcing\n' > "$d/bin/getenforce"
# shellcheck disable=SC2016  # the stub reads ARCH at run time
printf '#!/bin/bash\necho "${ARCH:-x86_64}"\n' > "$d/bin/uname"
chmod +x "$d/bin"/*
printf 'ID=fedora\nVERSION_ID=44\n' > "$d/os-release"
printf 'ID=fedora\nVERSION_ID=43\n' > "$d/os-release-43"
ln -s /usr/lib/systemd/system/gdm.service "$d/dm-gdm"
ln -s /usr/lib/systemd/system/sddm.service "$d/dm-sddm"
: > "$d/none"
export PATH=$d/bin:$PATH TINKERO_OS_RELEASE=$d/os-release TINKERO_DM_UNIT=$d/dm-gdm TINKERO_EUID=1000 REPOQUERY=$d/none
unset TINKERO_FEDORA TINKERO_REF
run() { : > "$LOG"; out=$(bash "$I" "$@" 2>&1 </dev/null) && rc=0 || rc=$?; }

# the script's Fedora release is the lock's (the release workflow rewrites both variables together);
# TINKERO_FEDORA is a plain pin, not an env-overridable seam like TINKERO_REF (issue #20)
assert_eq "$(sed -n 's/^TINKERO_FEDORA=\([0-9]*\)$/\1/p' "$I")" "$(sed -n 's/^fedora=//p' "$ROOT/upstream.lock")" "install.sh carries the lock's fedora release"

# the happy path
run --yes
assert_eq "$rc" 0 "install: exit 0"
assert_eq "$(paste -sd'|' "$LOG")" "dnf repoquery --installed --queryformat %{name} %{from_repo}\n hyprland quickshell omedora omedora-settings|sudo dnf copr enable -y dromero/tinkero|dnf copr enable -y dromero/tinkero|sudo dnf install -y tinkero|dnf install -y tinkero|tinkero-provision --plan|tinkero-provision --yes" "install: preflight query, copr enable, install, plan, provision, in that order"
assert_contains "$out" "SELinux is Enforcing" "install: reports SELinux"
assert_contains "$out" "Log out and choose Tinkero" "install: says what comes next"
assert_contains "$out" $'seed\t.config/hypr/hyprland.lua' "install: shows the provisioning plan"
run --yes; assert_eq "$rc" 0 "install: re-running is fine (both stages are no-ops on a current machine)"

# the gates
run
assert_eq "$rc" 1 "gate: no terminal and no --yes stops"
assert_contains "$out" "run with --yes or from a terminal" "gate: and says how to proceed"
assert_eq "$(grep -c '^sudo' "$LOG")" 0 "gate: nothing was changed"

# preflight
TINKERO_OS_RELEASE=$d/os-release-43 run --yes
assert_eq "$rc" 1 "preflight: wrong Fedora release stops"; assert_contains "$out" "Fedora 44" "preflight: names the expected release"
TINKERO_FEDORA=99 run --yes
assert_eq "$rc" 0 "preflight: a stray TINKERO_FEDORA in the environment does not override the pin"
assert_contains "$out" "ignoring TINKERO_FEDORA=99" "preflight: says it ignored the stray env var"
DNF_FAIL=1 run --yes
assert_eq "$rc" 1 "preflight: dnf itself failing stops, not treated as a pass"
assert_contains "$out" "dnf repoquery failed" "preflight: names the dnf failure"
assert_eq "$(grep -c '^sudo' "$LOG")" 0 "preflight: a dnf failure changes nothing"
ARCH=aarch64 run --yes
assert_eq "$rc" 1 "preflight: not x86_64 stops"
assert_contains "$out" "x86_64" "preflight: names the architecture"
TINKERO_DM_UNIT=$d/dm-sddm run --yes
assert_eq "$rc" 1 "preflight: another display manager stops"; assert_contains "$out" "GDM" "preflight: names GDM"
printf 'hyprland copr:copr.fedorainfracloud.org:agaspar:omedora-4\n' > "$d/foreign"
REPOQUERY=$d/foreign run --yes
assert_eq "$rc" 1 "preflight: hyprland from another repository stops"; assert_contains "$out" "agaspar:omedora-4" "preflight: names the repository"
assert_eq "$(grep -c '^sudo' "$LOG")" 0 "preflight: a repository failure changes nothing"
printf 'hyprland\n' > "$d/local"
REPOQUERY=$d/local run --yes
assert_eq "$rc" 1 "preflight: a locally built package with no repo stops"; assert_contains "$out" "an unknown source" "preflight: names it an unknown source"
printf 'omedora copr:copr.fedorainfracloud.org:agaspar:omedora-4\n' > "$d/omedora"
REPOQUERY=$d/omedora run --yes
assert_eq "$rc" 1 "preflight: omedora installed stops"
assert_contains "$out" "remove Omedora first" "preflight: says to remove Omedora"
printf 'hyprland copr:copr.fedorainfracloud.org:dromero:tinkero\n' > "$d/own"
REPOQUERY=$d/own run --yes
assert_eq "$rc" 0 "preflight: our own COPR's hyprland is fine"
TINKERO_EUID=0 run --yes
assert_eq "$rc" 1 "preflight: root stops"
assert_contains "$out" "not as root" "preflight: says not as root"
assert_eq "$(grep -c '^sudo' "$LOG")" 0 "preflight: a failed preflight changes nothing"
rm -rf "$d"; finish
