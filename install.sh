#!/bin/bash
# install.sh: install Tinkero on Fedora Workstation (design spec 4.6). Run it as your own user:
#
#   bash install.sh [--yes]
#
# 1. preflight (no changes)  2. the plan, confirmed  3. system stage (sudo): enable the COPR and
# install the tinkero package  4. user stage: the provisioning plan, confirmed, then tinkero-provision.
# Re-running is safe: both stages are no-ops when the machine is current.
set -euo pipefail
copr=${TINKERO_COPR:-dromero/tinkero}
# The release workflow rewrites these two when it attaches the script to a release (design 2E,
# D7): the git ref the script belongs to, and the Fedora release its lock names. tests/test-install.sh
# fails when TINKERO_FEDORA differs from upstream.lock. TINKERO_FEDORA is the pin, not an
# environment seam: a stray TINKERO_FEDORA already set in the caller's environment must not
# silently override it (preflight warns and uses the pin instead).
TINKERO_REF=${TINKERO_REF:-master}
tinkero_fedora_env=${TINKERO_FEDORA:-}
TINKERO_FEDORA=44
own_repo="copr:copr.fedorainfracloud.org:${copr//\//:}"
os_release=${TINKERO_OS_RELEASE:-/etc/os-release}
dm_unit=${TINKERO_DM_UNIT:-/etc/systemd/system/display-manager.service}
euid=${TINKERO_EUID:-$EUID}
yes=0

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "install.sh: $*" >&2; exit 1; }
say() { echo "install.sh: $*"; }
confirm() {   # QUESTION [STOP_MESSAGE]
  local a
  if (( yes )); then return 0; fi
  [[ -t 0 ]] || die "$1 needs a yes; run with --yes or from a terminal"
  read -r -p "$1 [y/N] " a || a=""
  [[ $a == [yY]* ]] || die "${2:-stopped; nothing was changed}"
}

while (($#)); do
  case $1 in
    --yes|-y) yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

# 1. Preflight: nothing changes.
if [[ -n $tinkero_fedora_env && $tinkero_fedora_env != "$TINKERO_FEDORA" ]]; then
  say "ignoring TINKERO_FEDORA=$tinkero_fedora_env from the environment; this release is pinned to Fedora $TINKERO_FEDORA"
fi
[[ $euid != 0 ]] || die "run as your own user, not as root; the system stage uses sudo"
id=$(sed -n 's/^ID=//p' "$os_release" | tr -d '"'); ver=$(sed -n 's/^VERSION_ID=//p' "$os_release" | tr -d '"')
[[ $id == fedora && $ver == "$TINKERO_FEDORA" ]] || die "this release of Tinkero ($TINKERO_REF) is for Fedora $TINKERO_FEDORA; this host is ${id:-unknown} ${ver:-?}"
arch=$(uname -m)
[[ $arch == x86_64 ]] || die "Tinkero is x86_64 only; this host is $arch"
dm=$(basename "$(readlink "$dm_unit" 2>/dev/null || echo none)")
[[ $dm == gdm.service ]] || die "Tinkero needs GDM as the display manager; this host has ${dm%.service}"
if command -v getenforce >/dev/null 2>&1; then say "SELinux is $(getenforce)"; else say "SELinux: getenforce not found"; fi
if ! installed=$(dnf repoquery --installed --queryformat '%{name} %{from_repo}\n' hyprland quickshell omedora omedora-settings 2>/dev/null); then
  die "dnf repoquery failed; cannot verify what is already installed"
fi
while read -r name repo; do
  [[ -z $name ]] && continue
  [[ $name != omedora* ]] || die "$name is installed; remove Omedora first (sudo dnf remove 'omedora*')"
  [[ $repo == "$own_repo" ]] || die "$name is installed from ${repo:-an unknown source}, not from $own_repo; remove it first so the pinned build can be installed"
done <<<"$installed"
say "preflight passed: Fedora $ver, $arch, GDM"

# 2. The plan and the first gate.
cat <<EOF

Plan:
  system stage (sudo):  dnf copr enable $copr
                        dnf install tinkero      (the desktop with its pinned Hyprland and Quickshell)
                        tinkero-pam-sync         (writes the lock screen's PAM file for this host)
  user stage (you):     tinkero-provision        (its own plan is shown and confirmed first)
Nothing else changes: no other repository, no versionlock, no Flathub, nothing under /etc beyond the package's files and the COPR repository file.

EOF
confirm "Continue with the system stage?"

# 3. System stage.
y=()
if (( yes )); then y=(-y); fi
sudo dnf copr enable "${y[@]}" "$copr"
sudo dnf install "${y[@]}" tinkero
# %posttrans already ran this once, but a re-run of install.sh is otherwise unable to repair a
# variant an authselect change made stale in between (design spec 4.8, plan 2F design D8).
sudo tinkero-pam-sync
say "system stage done"

# 4. The provisioning plan, the second gate, the user stage. The plan lists every file that
# would be created (nothing you have is overwritten) and the one existing file it touches,
# ~/.bashrc, so answering here answers tinkero-provision's own consent question too.
echo; echo "Provisioning plan (per file; nothing you already have is overwritten):"
tinkero-provision --plan
echo
confirm "Create the files above and append the guarded line to ~/.bashrc?" "stopped; the tinkero package is installed, run tinkero-provision when you are ready"
tinkero-provision --yes
say "done. Log out and choose Tinkero at the GDM login screen."
