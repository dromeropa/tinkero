# Phase 2F VM check: the packaged session on a clean Fedora 44

Companion to plan 2F (`docs/superpowers/plans/2026-09-24-phase-2f-session-integration.md`, Task 9) and its design (`docs/superpowers/specs/2026-09-24-phase-2f-session-design.md`, section 7). It re-runs Phase 0's GNOME cycle against the real `tinkero` package from the COPR, with the session's own dconf database, and checks what 2F wired: the session units, the power key, the lock screen's PAM variants, removal. Budget: half a day. Nothing here touches your real machine beyond running a VM.

**Status: written 2026-09-24, not yet executed.** Record every command that had to change in the issue, as Phase 0 did; those corrections are part of the result.

## 1. The VM

Reuse the Phase 0 VM setup (`docs/guides/phase-0-spike.md`, section 2, and the environment notes of `docs/research/phase-0-findings.md`): `export LIBVIRT_DEFAULT_URI=qemu:///session`, viewer with `virt-viewer --attach`. Start from the clean checkpoint, never from the assembled one:

```bash
virt-clone --original tinkero-spike-clean-f44 --name tinkero-2f --auto-clone
virsh start tinkero-2f && virt-viewer --attach tinkero-2f
```

In the guest, log into GNOME as `dtest`, then:

```bash
sudo dnf upgrade -y --refresh     # reboot if the kernel moved
getenforce                        # Enforcing
authselect current                # profile local; note whether with-faillock is listed (stock: not)
mkdir -p ~/vmcheck
```

## 2. The GNOME baseline, then the install

The baseline is taken before anything of Tinkero is on the machine (spec 8: the install itself must change nothing). In GNOME, set Appearance to Dark (Phase 0: Fedora 44's default is Light) and set one key the Tinkero session never writes, as the canary for the seeded database: `gsettings set org.gnome.desktop.interface clock-show-seconds true`. Then write the snapshot script and take the baseline:

```bash
cat > ~/vmcheck/snap.sh <<'EOF'
#!/bin/bash
# snap.sh NAME: everything the GNOME invariant (design spec 8) compares, into ~/vmcheck/snap-NAME.txt
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
EOF
chmod +x ~/vmcheck/snap.sh
~/vmcheck/snap.sh 0-baseline
loginctl enable-linger "$USER"    # keeps the user manager alive between sessions: the hard case for 4.9
```

- [ ] `snap-0-baseline.txt` shows `color-scheme 'prefer-dark'`, `clock-show-seconds true`, `cursor-theme 'Adwaita'`, `text-scaling-factor 1.0`, `user env` `none`, no service under the `DCONF_PROFILE` heading, no active Tinkero units

Install from `master` (until the first release is tagged, that is where `install.sh` lives):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dromeropa/tinkero/master/install.sh) 2>&1 | tee ~/vmcheck/install.txt
~/vmcheck/snap.sh 0b-installed
```

- [ ] `install.sh` finishes with "Log out and choose Tinkero"; `install.txt` shows `wrote wrapped` inside dnf's scriptlet output (`%posttrans`), then `current: wrapped` from `install.sh`'s own `sudo tinkero-pam-sync`
- [ ] `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-0b-installed.txt` is empty: installing and provisioning changed nothing GNOME sees (the guarded `~/.bashrc` line is filtered out by the snapshot)
- [ ] `rpm -qf /etc/pam.d/omarchy-lock-password` prints `tinkero-4.0.4-1.fc44.noarch`
- [ ] `tinkero-pam-sync --check; echo $?` prints `current: wrapped` and `0`; `tinkero-pam-sync --variant` prints `wrapped`
- [ ] `ls -Z /etc/pam.d/omarchy-lock-password` shows type `etc_t` (the SELinux user is whoever created it, `unconfined_u` or `system_u`; only the type matters), and `sudo restorecon -nv /etc/pam.d/omarchy-lock-password` prints nothing
- [ ] `ls ~/.config/dconf/tinkero` exists (seeded from GNOME during provisioning)

## 3. Inside Tinkero

Log out, pick **Tinkero** at GDM, log in.

- [ ] `systemctl --user show-environment | grep DCONF_PROFILE` prints `DCONF_PROFILE=tinkero`
- [ ] `systemctl --user list-units --no-legend 'omarchy-*' 'tinkero-*' bt-agent.service` shows `omarchy-crash-watch`, `omarchy-sleep-lock`, `omarchy-fcitx5` and `tinkero-inhibit-power-key` active (`bt-agent` inactive without a Bluetooth adapter, the speaker tuning absent on a VM: both are expected); `omarchy-recover-internal-monitor` is inactive, its condition is false without the toggle
- [ ] `systemctl --user cat omarchy-fcitx5.service` ends with the `tinkero.conf` drop-in; `grep -l '^\[Install\]' $(rpm -ql tinkero | grep '/systemd/user/.*\.service$')` prints nothing
- [ ] `systemd-inhibit --list` shows `Tinkero` holding `handle-power-key` in `block` mode
- [ ] from the host, `virsh send-key tinkero-2f KEY_POWER`: the VM stays up and the shell's power menu opens
- [ ] `gsettings get org.gnome.desktop.interface clock-show-seconds` inside the session prints `true`: the session reads its own database, seeded from GNOME's (the theme switch writes `color-scheme`, so that key proves nothing)

### The lock screen

`Super+Ctrl+L`, type a wrong password twice, then the right one.

- [ ] the lock appears, the wrong passwords are refused, the right one unlocks
- [ ] `sudo faillock --user "$USER"` right after the second wrong attempt (from a second TTY, `Ctrl+Alt+F3`) shows 2 failures; after unlocking, 0
- [ ] `sudo ausearch -m AVC -ts recent` prints `<no matches>`

Then switch the host to `with-faillock` and let the sync follow it:

```bash
sudo authselect enable-feature with-faillock
tinkero-pam-sync --check; echo $?     # "wrapped installed, plain needed", 1
sudo tinkero-pam-sync                 # wrote plain
tinkero-pam-sync --check; echo $?     # 0
```

- [ ] the three outputs are as commented
- [ ] lock again, one wrong password, then `sudo faillock --user "$USER"` from the TTY shows exactly 1 failure (not 2: the plain variant does not double count); the right password unlocks
- [ ] `sudo authselect disable-feature with-faillock && sudo tinkero-pam-sync` prints `wrote wrapped`

## 4. The GNOME invariant, three ways

Each cycle: inside Tinkero, `omarchy-theme-set tokyo-night`, then `omarchy-theme-set catppuccin-latte`, then `omarchy-display-text-size 16` (it writes `text-scaling-factor`, Phase 0's second leak); end the session the cycle's way; log into GNOME; `~/vmcheck/snap.sh N-...`; `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-N-*.txt`.

1. End with the menu's logout. Snapshot `1-menu-logout`.
2. End with `loginctl terminate-session "$XDG_SESSION_ID"` from a terminal inside Tinkero. Snapshot `2-terminate`.
3. End with `pkill -9 Hyprland` from a TTY. Snapshot `3-kill`. (The next Tinkero login starts in Hyprland Safe Mode, `Super+M` leaves it; spec 4.11.)

- [ ] cycle 1: the diff is empty
- [ ] cycle 2: the diff is empty
- [ ] cycle 3: the diff is empty
- [ ] in each snapshot, `user env` is `none` (uwsm's cleanup removed `DCONF_PROFILE` even with lingering on), no running user service sees `DCONF_PROFILE`, and `tinkero units` is empty
- [ ] inside Tinkero after cycle 3, `gsettings get org.gnome.desktop.interface text-scaling-factor` prints `1.3636...` (16 px): the session kept its own value

If `user env` shows `DCONF_PROFILE=tinkero` in any GNOME snapshot, that is design D4's fallback case; if the checksum moved with `user env` at `none`, a key leaked some other way (find it with `dconf dump /` under GNOME against the baseline) and spec 4.9's restore unit is the fallback. Record which.

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
- [ ] `diff ~/vmcheck/snap-0-baseline.txt ~/vmcheck/snap-4-removed.txt` is empty
- [ ] GDM no longer lists Tinkero; record whether dnf also removed `hyprland` as an unneeded dependency (dnf5 does by default) or left its own session in the list

## 7. Recording

Comment on the Task 9 issue with every checkbox's result, the four diffs, and `rpm -q tinkero hyprland quickshell uwsm` from before removal. Copy `~/vmcheck/` off the guest if a failure needs a closer look.
