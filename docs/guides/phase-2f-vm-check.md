# Phase 2F VM check: the packaged session on a clean Fedora 44

Companion to plan 2F (`docs/superpowers/plans/2026-09-24-phase-2f-session-integration.md`, Task 9) and its design (`docs/superpowers/specs/2026-09-24-phase-2f-session-design.md`, section 7). It re-runs Phase 0's GNOME cycle against the real `tinkero` package from the COPR, with the session's own dconf database, and checks what 2F wired: the session units, the power key, the lock screen's PAM variants, removal. Budget: half a day, plus an hour if the VM has to be built from the ISO. Nothing here touches your real machine beyond running a VM.

**Status: written 2026-09-24; first run 2026-09-26 (#27, did not pass); corrected from that run (#36) for the re-run (#37).** Record every command that had to change in the issue, as Phase 0 and #27 did; those corrections are part of the result.

## 1. The VM

Everything on the host runs as your own user under the per-user libvirt daemon (Phase 0 guide `docs/guides/phase-0-spike.md`, section 2, and the environment notes of `docs/research/phase-0-findings.md`). Install the tools once, and set the URI in every host terminal:

```bash
sudo dnf install @virtualization virt-install virt-viewer     # once per host
export LIBVIRT_DEFAULT_URI=qemu:///session
virsh list --all
```

The viewer is always `virt-viewer --attach <name>` (the SPICE socket is local-only). Host-to-guest clipboard works while the guest shows GNOME, never while it shows Tinkero: this guide therefore fetches its scripts inside the guest and reads results back from GNOME.

If `virsh list --all` shows `tinkero-spike-clean-f44`, skip to "The test clone". Otherwise build it first; #27 had to, the Phase 0 VMs were gone.

### Build the clean checkpoint from the ISO

This is Phase 0 guide section 2 as #27 ran it. On the host:

```bash
cd ~/Downloads
curl -fLO https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/Fedora-Workstation-Live-44-1.7.x86_64.iso
curl -fLO https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/Fedora-Workstation-44-1.7-x86_64-CHECKSUM
curl -fLO https://fedoraproject.org/fedora.gpg
gpgv --keyring ./fedora.gpg Fedora-Workstation-44-1.7-x86_64-CHECKSUM             # Good signature from "Fedora (44) ..."
sha256sum --ignore-missing -c Fedora-Workstation-44-1.7-x86_64-CHECKSUM           # Fedora-Workstation-Live-44-1.7.x86_64.iso: OK
```

The CHECKSUM file's line for the ISO is `SHA256 (Fedora-Workstation-Live-44-1.7.x86_64.iso) = 1620295f6a00c27c3208f0c00b8ece4eab1ec69b9002152d97488bf26a426ddf` (2851612672 bytes).

Create the VM. Type or paste it exactly as below, one option group per line, every line but the last ending in `\`: in #27 a terminal wrap joined the lines, `--graphics` was lost, and qemu failed with "The display backend does not have OpenGL support enabled". If that happens, `virsh undefine tinkero-spike --nvram --remove-all-storage` and run it again.

```bash
virt-install \
  --name tinkero-spike \
  --memory 8192 --vcpus 4 \
  --disk size=40 \
  --cdrom ~/Downloads/Fedora-Workstation-Live-44-1.7.x86_64.iso \
  --osinfo detect=on,require=off \
  --boot uefi \
  --video virtio,accel3d=yes \
  --graphics spice,gl.enable=yes,listen=none,rendernode=/dev/dri/by-path/pci-0000:00:02.0-render
```

The `rendernode=` path pins virgl to the Intel iGPU of an Optimus laptop (Phase 0). On another host pick the right node from `ls -l /dev/dri/by-path/`, or drop `,rendernode=...` on a single-GPU Intel or AMD host. If no viewer opens, `virt-viewer --attach tinkero-spike`.

Install Fedora Workstation with the defaults (btrfs, no disk encryption). In #27 the installer then stopped at "finalization" and never moved: the VM's `qemu` process sat at 0% CPU in the host's `top`. The install was complete. Force it off and boot from disk:

```bash
virsh destroy tinkero-spike
virsh start tinkero-spike && virt-viewer --attach tinkero-spike
```

It boots into first-boot setup. Create your user there with a password; any name works, every command below uses `$USER` (#27's user was `d`, Phase 0's `dtest`). Log in, then in the guest:

```bash
sudo dnf upgrade -y --refresh && sudo reboot
```

Take the checkpoint from the shut-down VM (libvirt's internal snapshots do not work on a UEFI guest), and never boot the checkpoint itself:

```bash
virsh shutdown tinkero-spike        # wait until `virsh list --all` shows it shut off
virt-clone --original tinkero-spike --name tinkero-spike-clean-f44 --auto-clone
```

### The test clone

Start from the clean checkpoint, never from an assembled one. If a `tinkero-2f` from an earlier run exists, remove it first (a UEFI guest keeps an NVRAM file a plain undefine leaves behind): `virsh destroy tinkero-2f; virsh undefine tinkero-2f --nvram --remove-all-storage`.

```bash
virt-clone --original tinkero-spike-clean-f44 --name tinkero-2f --auto-clone
virsh start tinkero-2f && virt-viewer --attach tinkero-2f
```

In the guest, log into GNOME as your user, open a terminal, then:

```bash
sudo dnf upgrade -y --refresh     # reboot if the kernel moved
getenforce                        # Enforcing
authselect current                # profile local; note whether with-faillock is listed (stock: not)
mkdir -p ~/vmcheck
```

## 2. The GNOME baseline, then the install

The baseline is taken before anything of Tinkero is on the machine (spec 8: the install itself must change nothing). In GNOME, set Appearance to Dark (Phase 0: Fedora 44's default is Light) and set one key the Tinkero session never writes, as the canary for the seeded database: `gsettings set org.gnome.desktop.interface clock-show-seconds true`.

The two scripts this guide uses, `snap.sh` below and `insession.sh` in section 3, are fetched from this guide on `master` rather than pasted: pasting a heredoc into the guest mangles it. In the guest's GNOME terminal, one line at a time:

```bash
curl -fsSL https://raw.githubusercontent.com/dromeropa/tinkero/master/docs/guides/phase-2f-vm-check.md -o ~/vmcheck/guide.md
{ echo '#!/bin/bash'; sed -n '/^# snap\.sh NAME:/,/^# end of snap\.sh$/p' ~/vmcheck/guide.md; } > ~/vmcheck/snap.sh
{ echo '#!/bin/bash'; sed -n '/^# insession\.sh:/,/^# end of insession\.sh$/p' ~/vmcheck/guide.md; } > ~/vmcheck/insession.sh
chmod +x ~/vmcheck/snap.sh ~/vmcheck/insession.sh
tail -n 1 ~/vmcheck/snap.sh ~/vmcheck/insession.sh    # "# end of snap.sh", "# end of insession.sh"
```

If `tail` does not print both end markers, the guide on `master` predates #36's corrections: fetch it from the branch or tag that carries them instead of `master`.

This is `snap.sh`, what the commands above extract:

```bash
#!/bin/bash
# snap.sh NAME: everything the GNOME invariant (design spec 8) compares, into ~/vmcheck/snap-NAME.txt,
# plus the user dconf database alone, dumped into ~/vmcheck/userdb-NAME.ini to explain a checksum move
{
  echo "## dconf user db"; sha256sum ~/.config/dconf/user
  echo "## interface"; gsettings list-recursively org.gnome.desktop.interface
  echo "## browser"; xdg-settings get default-web-browser
  echo "## mailto"; xdg-mime query default x-scheme-handler/mailto
  echo "## xdg dirs"; for d in DESKTOP DOWNLOAD DOCUMENTS MUSIC PICTURES VIDEOS; do xdg-user-dir "$d"; done
  echo "## keyrings"; ls ~/.local/share/keyrings
  echo "## bashrc without the guarded line"; grep -v '# tinkero-provision$' ~/.bashrc | sha256sum
  echo "## user env"; systemctl --user show-environment | grep -E '^(DCONF_PROFILE|OMARCHY_PATH)=' || echo none
  echo "## running user services that see DCONF_PROFILE"
  for u in $(systemctl --user list-units --type=service --state=running --no-legend --plain | awk '{print $1}'); do
    pid=$(systemctl --user show -p MainPID --value "$u")
    if [ "${pid:-0}" -gt 0 ] && tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q '^DCONF_PROFILE='; then echo "$u"; fi
  done
  echo "## tinkero units"; systemctl --user list-units --state=active --no-legend 'omarchy-*' 'tinkero-*' bt-agent.service || true
} > ~/vmcheck/snap-"$1".txt 2>&1
# The user db alone, through a one-line profile (the same way tinkero-provision seeds, #28): the
# merged profile would mix in the system databases, which never change here
p=$(mktemp); printf 'user-db:user\n' > "$p"
DCONF_PROFILE=$p dconf dump / > ~/vmcheck/userdb-"$1".ini 2>&1
rm -f "$p"
# end of snap.sh
```

Take the baseline:

```bash
~/vmcheck/snap.sh 0-baseline
loginctl enable-linger "$USER"    # keeps the user manager alive between sessions: the hard case for 4.9
```

- [ ] `snap-0-baseline.txt` shows `color-scheme 'prefer-dark'`, `clock-show-seconds true`, `cursor-theme 'Adwaita'`, `text-scaling-factor 1.0`, `user env` `none`, no service under the `DCONF_PROFILE` heading, no active Tinkero units; `userdb-0-baseline.ini` shows `clock-show-seconds=true` under `[org/gnome/desktop/interface]`

**Reading a diff.** The dconf checksum alone cannot tell GNOME's own first-use writes from a leak: in #27 it moved on the first GNOME login after the session, from `Ptyxis window-size`, `nautilus migrated-gtk-settings`, `shell/world-clocks locations`, and `gtk4 file-chooser show-hidden` / `sort-directories-first`, none of them a key the session writes. So wherever this guide says a snapshot diff is "clean", it means: every section of `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-N.txt` is identical except, possibly, the `dconf user db` checksum line; and if that line moved, `diff ~/vmcheck/userdb-0-baseline.ini ~/vmcheck/userdb-N.ini` lists only such GNOME app state, and nothing under `[org/gnome/desktop/interface]` (where `omarchy-theme-set` and `omarchy-display-text-size` write) or any other key the session sets.

Install from `master` (until the first release is tagged, that is where `install.sh` lives):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dromeropa/tinkero/master/install.sh) 2>&1 | tee ~/vmcheck/install.txt
~/vmcheck/snap.sh 0b-installed
```

- [ ] `install.sh` finishes with "Log out and choose Tinkero" and `install.txt` shows `tinkero-provision: dconf: seeded the session's settings from GNOME's` and `tinkero-provision: provisioned for <release>`, not `not complete` (#28); `install.txt` shows `wrote wrapped` inside dnf's scriptlet output (`%posttrans`), then `current: wrapped` from `install.sh`'s own `sudo tinkero-pam-sync`, then `wrote tally <your user>` from `sudo tinkero-pam-sync --tally` (#29)
- [ ] `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-0b-installed.txt` is clean (see "Reading a diff"): installing and provisioning changed nothing GNOME sees (the guarded `~/.bashrc` line is filtered out by the snapshot, and since #28 no blank line comes with it)
- [ ] `rpm -qf /etc/pam.d/omarchy-lock-password` prints `tinkero-4.0.4-1.fc44.noarch`
- [ ] `tinkero-pam-sync --check; echo $?` prints `current: wrapped` and `0`; `tinkero-pam-sync --variant` prints `wrapped`
- [ ] `ls -Z /etc/pam.d/omarchy-lock-password` shows type `etc_t` (the SELinux user is whoever created it, `unconfined_u` or `system_u`; only the type matters), and `sudo restorecon -nv /etc/pam.d/omarchy-lock-password` prints nothing
- [ ] `tail -n 1 /etc/tmpfiles.d/tinkero-lockout-$USER.conf` prints `f /run/faillock/<your user> 0660 <your user> root -` (#29: systemd recreates the lock's tally file at every boot)
- [ ] `ls ~/.config/dconf/tinkero` exists (seeded from GNOME during provisioning)

Do not run `faillock` in any form from here until section 3's lock check says so.

## 3. Inside Tinkero

The lock check below must run on a freshly booted VM on which nothing has run `faillock` as root since the boot. #27 got 0 failures on the first try and 2 only after a root `faillock` had created the tally file (#29); `install.sh`'s `--tally` step also creates the file at once. Either way an existing file masks the defect #29 fixed, so reboot rather than log out:

```bash
sudo reboot
```

At GDM pick **Tinkero** and log in. Open a terminal (`Super+Return`) and run the checks as a script, since nothing can be pasted into the Tinkero session. This is `insession.sh`, fetched in section 2:

```bash
#!/bin/bash
# insession.sh: section 3's checks from inside the Tinkero session, into ~/vmcheck/3-insession.txt
{
  echo "## session"; echo "XDG_VTNR=${XDG_VTNR:-unset} XDG_SESSION_ID=${XDG_SESSION_ID:-unset}"
  echo "## manager env"; systemctl --user show-environment | grep DCONF_PROFILE || echo none
  echo "## units"; systemctl --user list-units --no-legend 'omarchy-*' 'tinkero-*' bt-agent.service
  echo "## fcitx5 unit files"; systemctl --user cat omarchy-fcitx5.service | grep '^# /'
  echo "## package units with [Install]"
  rpm -ql tinkero | grep '/systemd/user/.*\.service$' | xargs grep -l '^\[Install\]' || echo none
  echo "## inhibitors"; systemd-inhibit --list
  echo "## clock-show-seconds"; gsettings get org.gnome.desktop.interface clock-show-seconds
  echo "## tally file, created at boot by tmpfiles.d"; ls -l "/run/faillock/$USER"
} > ~/vmcheck/3-insession.txt 2>&1
# end of insession.sh
```

```bash
~/vmcheck/insession.sh; cat ~/vmcheck/3-insession.txt
```

The results go into the issue later, from GNOME (section 4's first login), where the clipboard works.

- [ ] `manager env` prints `DCONF_PROFILE=tinkero`
- [ ] `units` shows `omarchy-crash-watch`, `omarchy-sleep-lock`, `omarchy-fcitx5` and `tinkero-inhibit-power-key` active (`bt-agent` inactive without a Bluetooth adapter, the speaker tuning absent on a VM: both are expected); `omarchy-recover-internal-monitor` is inactive, its condition is false without the toggle
- [ ] `fcitx5 unit files` ends with the `tinkero.conf` drop-in; `package units with [Install]` prints `none`
- [ ] `inhibitors` shows `Tinkero` holding `handle-power-key` in `block` mode
- [ ] from the host, `virsh send-key tinkero-2f KEY_POWER`: the VM stays up and the shell's power menu opens
- [ ] `clock-show-seconds` prints `true`: the session reads its own database, seeded from GNOME's (the theme switch writes `color-scheme`, so that key proves nothing)
- [ ] the tally file exists without any root `faillock` call: `-rw-rw----` owned by your user and group `root`

### The lock screen

The second terminal is a text console. The viewer does not pass `Ctrl+Alt+F3` to the guest, so switch from the host: `virsh send-key tinkero-2f KEY_LEFTCTRL KEY_LEFTALT KEY_F3` goes to tty3 (log in there as your user), and `virsh send-key tinkero-2f KEY_LEFTCTRL KEY_LEFTALT KEY_F2` comes back, where `F2` is the session's `XDG_VTNR` from `3-insession.txt` (2 in #27; use its number if it differs). "From the TTY" below means this.

`Super+Ctrl+L`, type a wrong password twice, and leave the lock up.

- [ ] `rpm -q quickshell` prints `quickshell-0.3.0^20.git28771c7-2.fc44.x86_64` (Tinkero's build with the account-phase patch, #46)
- [ ] the lock appears and refuses both wrong passwords
- [ ] the on-screen counter reads `(1)` after the first wrong password and `(2)` after the second (#46 saw +2 per attempt; that came from the broken file's error path)
- [ ] from the TTY, `sudo faillock --user "$USER" | tee ~/vmcheck/3-lock.txt` shows 2 failures, both from `omarchy-lock-password` (#29, first defect: none were recorded after a boot)
- [ ] back in the session, the right password unlocks; then from the TTY, `sudo faillock --user "$USER" | tee -a ~/vmcheck/3-lock.txt` shows no failures (#29, second defect, fixed by #46: the lock now runs the account phase, whose `pam_faillock` resets the tally)
- [ ] the right password unlocks on the first try (#46: before the fix, no password did)
- [ ] `journalctl --user -b | grep -i "module is unknown"` prints nothing
- [ ] `sudo ausearch -m AVC -ts recent` prints `<no matches>`

Then switch the host to `with-faillock` and let the sync follow it. From the TTY, clear the tally first: `with-faillock` puts the host's own `pam_faillock` into `system-auth` and `password-auth` with its default `deny=3`, so a failure still on the tally plus the next check's wrong password, or a sudo typo, can lock both the lock screen and `sudo` out.

```bash
sudo faillock --user "$USER" --reset
sudo authselect enable-feature with-faillock
tinkero-pam-sync --check; echo $?     # "wrapped installed, plain needed", 1
sudo tinkero-pam-sync                 # wrote plain
tinkero-pam-sync --check; echo $?     # "current: plain", 0
```

- [ ] the three outputs are as commented
- [ ] lock again, one wrong password, then `sudo faillock --user "$USER" | tee -a ~/vmcheck/3-lock.txt` from the TTY shows exactly 1 failure (not 2: the `plain` variant does not double count); the right password unlocks, and `sudo faillock --user "$USER"` then shows no failures (`password-auth`'s own account-phase `pam_faillock`, run by the patched Quickshell, #46)
- [ ] `sudo authselect disable-feature with-faillock && sudo tinkero-pam-sync` prints `wrote wrapped`

Fingerprint unlock is not checked (the VM has no reader); the account phase applies to it too (spec 4.8).

## 4. The GNOME invariant, three ways

Each cycle: inside Tinkero, `omarchy-theme-set tokyo-night`, then `omarchy-theme-set catppuccin-latte`, then `omarchy-display-text-size 16` (it writes `text-scaling-factor`, Phase 0's second leak); end the session the cycle's way; log into GNOME; `~/vmcheck/snap.sh N-...`; `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-N-*.txt` and `diff ~/vmcheck/userdb-0-baseline.ini ~/vmcheck/userdb-N-*.ini`.

Optional control, before cycle 1: log out of GNOME, log back into GNOME, use the terminal and Files as you will after each cycle, and take `~/vmcheck/snap.sh 0c-control`. What `userdb-0c-control.ini` adds over the baseline is GNOME's own writes, with no Tinkero session in between.

1. End with the menu's logout. Snapshot `1-menu-logout`.
2. End with `loginctl terminate-session "$XDG_SESSION_ID"` from a terminal inside Tinkero. Snapshot `2-terminate`.
3. End with `pkill -9 Hyprland` from the TTY (section 3). Snapshot `3-kill`. (The next Tinkero login starts in Hyprland Safe Mode, `Super+M` leaves it; spec 4.11. #27 did not observe it.)

- [ ] cycle 1: the diff is clean (section 2, "Reading a diff")
- [ ] cycle 2: the diff is clean
- [ ] cycle 3: the diff is clean
- [ ] `diff ~/vmcheck/userdb-1-menu-logout.ini ~/vmcheck/userdb-2-terminate.ini` and the same for `3-kill` show nothing the session writes (in #27 they were byte-identical)
- [ ] in each snapshot, `user env` is `none` (uwsm's cleanup removed `DCONF_PROFILE` even with lingering on), no running user service sees `DCONF_PROFILE` (#27 found five here: `dconf.service`, `pipewire-pulse.service`, the at-spi registry and GNOME's Identity and OnlineAccounts `dbus-*` units), and `tinkero units` is empty
- [ ] inside Tinkero after cycle 3, `gsettings get org.gnome.desktop.interface text-scaling-factor` prints `1.3636...` (16 px): the session kept its own value
- [ ] after each cycle, `journalctl --user -b -u tinkero-session-end.service` shows a run at that session end with a `tinkero-session-end: restarting <unit>` line for each ordinary service still on the Tinkero profile and `tinkero-session-end: stopping <unit>` for each transient `dbus-*` one (issue #30), and no `restarting` or `stopping` line from inside a live session

If `user env` shows `DCONF_PROFILE=tinkero` in any GNOME snapshot, uwsm's cleanup did not run and `tinkero-session-end` did not repair it (design D4); if the checksum moved with `user env` at `none` and the user-db diff names a key the session writes, a key leaked some other way and spec 4.9's restore unit is the fallback. Record which. A service under the `DCONF_PROFILE` heading with `user env` at `none` means the session-end sweep did not run or missed it (issue #30): record the unit and that journal.

## 5. Milestone B lines 2D could not check

In a Tinkero session:

- [ ] the bar's menu button shows the Tinkero mark, and so does the Packages row in `Super+Space` > Update
- [ ] About (menu > About) shows the 54 by 26 logo and a "built on Omarchy" line, and its OS line names Fedora
- [ ] the screensaver (`omarchy-launch-screensaver`) shows the Tinkero logo
- [ ] the background switcher (`Super+Ctrl+Space`) on `catppuccin` lists `tinkero.png` and no `omarchy.png`, and selecting it shows the Tinkero wordmark
- [ ] design D16: menu > Learn > Hyprland with Firefox as the default browser. Record what happens (a Chromium web app, a Firefox tab, or nothing)

## 6. Removal

From GNOME:

```bash
tinkero-provision --remove
sudo dnf remove -y tinkero
sudo dnf copr remove dromero/tinkero
loginctl disable-linger "$USER"
~/vmcheck/snap.sh 4-removed
```

- [ ] `ls /etc/pam.d/ | grep -c omarchy` prints `0` (no `omarchy-lock-*`, no `.rpmsave`)
- [ ] `ls ~/.config/dconf/tinkero` fails: the session database is gone
- [ ] `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-4-removed.txt` is clean (section 2, "Reading a diff"), `~/.bashrc` included (#28)
- [ ] GDM no longer lists Tinkero; record whether dnf also removed `hyprland` as an unneeded dependency (dnf5 does by default) or left its own session in the list
- [ ] record whether `/etc/tmpfiles.d/tinkero-lockout-$USER.conf` is still there: `install.sh` wrote it, not the RPM, so `dnf remove` leaves it (a known follow-up of #29's fix, PR #43)

## 7. Recording

Comment on the Task 9 issue from GNOME with every checkbox's result, `3-insession.txt` and `3-lock.txt`, the four snapshot diffs with their user-db diffs, and `rpm -q tinkero hyprland quickshell uwsm` from before removal. Copy `~/vmcheck/` off the guest if a failure needs a closer look.
