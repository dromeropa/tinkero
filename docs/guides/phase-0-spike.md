# Phase 0 spike: a Fedora 44 VM, the desktop by hand, and the questions a reading cannot answer

Companion to the design spec, section 7 (Phase 0). Budget: one to two days. Nothing here touches your real machine beyond running a VM.

**Status: executed 2026-09-20 to 2026-09-21; findings in `docs/research/phase-0-findings.md`.** The corrections that run found are folded in below (marked "Phase 0:"). Originally derived, not executed: Every command below was written from the upstream tree at `v4.0.4`, the research doc's section 4.4, the audit, and Fedora's documentation. None of it has been run end to end. Expect to correct it as you go, and record the corrections in the findings note (section 9): those corrections are part of what the spike is for.

## 1. What the spike must answer

| # | Question | Why it blocks | Pass condition |
|---|---|---|---|
| Q1 | Does the uwsm/Hyprland session start from **GDM** on Fedora 44? | The design keeps GDM (spec 3, 4.2) | Picking the session at GDM lands in a working desktop; `hyprctl configerrors` is empty |
| Q2 | Does the Quickshell **lock screen authenticate under SELinux enforcing** through a PAM service that includes `password-auth`? | Least-proven piece of the design (spec 4.8) | Correct password unlocks, wrong password does not, zero AVC denials |
| Q3 | Do both **PAM variants** keep lockout and count a failure once? | Spec 4.8's two-variant design | `faillock` shows +1 per wrong attempt in both host configurations; success resets |
| Q4 | Are there **AVC denials** after a normal session? | No SELinux policy changes allowed (spec 5) | `ausearch` shows none attributable to the desktop |
| Q5 | Does the **GNOME invariant** hold, and does restore-at-logout win its race? | GNOME is the recovery path (spec 4.9) | Snapshots before and after are identical; note how often the unit alone sufficed |
| Q7 | Can an unprivileged **power-key inhibitor** replace upstream's logind override? | Spec 4.2 installs nothing from upstream's `etc/` | Power key opens the power menu instead of powering off |
| Q6 | Do **Milestones A and B** work by hand? | Proves the desktop before 25 specs are forked | Checklists in section 7 |

The decision at the end is go / no-go on Phase 1, plus the lock-screen mechanism (Quickshell lock, or fall back to `hyprlock`).

## 2. Make the VM

Hyprland needs GPU acceleration; a VM without 3D will not start the compositor. On a Fedora host with an Intel or AMD GPU, virtio-gpu with virgl works. Phase 0: on an Optimus laptop (Intel plus NVIDIA), pin virgl to the Intel render node with `rendernode=/dev/dri/by-path/pci-0000:00:02.0-render` in the `--graphics` line and it works; a host with only the proprietary NVIDIA driver is the case to avoid.

Phase 0: run as an unprivileged user, `virt-install` creates the VM under the per-user `qemu:///session` daemon, so every `virsh`, `virt-clone` and `virt-viewer` call must target it: `export LIBVIRT_DEFAULT_URI=qemu:///session`. Disks live in `~/.local/share/libvirt/images/`; no sudo is needed; user-mode NAT gives the guest outbound network. The viewer needs `virt-viewer --connect qemu:///session --attach tinkero-spike` because the SPICE socket is local-only. Host-to-guest clipboard works under GNOME but not under Hyprland; use screenshots.

```bash
sudo dnf install @virtualization virt-install virt-viewer
sudo systemctl enable --now libvirtd
# Download Fedora-Workstation-Live-44-*.x86_64.iso from fedoraproject.org, verify its checksum, then:
virt-install \
  --name tinkero-spike \
  --memory 8192 --vcpus 4 \
  --disk size=40 \
  --cdrom ~/Downloads/Fedora-Workstation-Live-44-1.x.x86_64.iso \
  --osinfo detect=on,require=off \
  --boot uefi \
  --video virtio,accel3d=yes \
  --graphics spice,gl.enable=yes,listen=none,rendernode=/dev/dri/by-path/pci-0000:00:02.0-render
```

Phase 0: Fedora 44's web installer can look frozen at "Generating initramfs" when the install is actually complete (idle CPU, no journal progress for many minutes). Check `df` on `/mnt/sysroot`; if it is populated, force off and boot from disk.

If the viewer shows a black screen or qemu logs `GL_DRAW_COOKIE_INVALID`, recreate the VM with `--graphics gtk,gl.enable=yes` instead of the spice line.

Install Fedora Workstation with defaults (btrfs, one user with a password, no disk encryption needed). After first boot:

```bash
sudo dnf upgrade -y && sudo reboot
getenforce                      # must print Enforcing
authselect current              # expect profile "local", no with-faillock
```

Take a checkpoint now; you will return to it more than once. Libvirt's internal snapshots do not work on a UEFI guest (its pflash firmware cannot be snapshotted), so clone the shut-down VM instead:

```bash
virsh shutdown tinkero-spike        # wait until `virsh list --all` shows it shut off
virt-clone --original tinkero-spike --name tinkero-spike-clean-f44 --auto-clone
# to go back later (UEFI guests keep an NVRAM file that a plain undefine leaves behind):
#   virsh destroy tinkero-spike; virsh undefine tinkero-spike --nvram --remove-all-storage
#   virt-clone --original tinkero-spike-clean-f44 --name tinkero-spike --auto-clone
```

Optional 30-minute sanity check before anything else: on a throwaway clone of the snapshot, install Omedora as its own README describes and see whether its session starts from GDM and its lock screen works. It answers "can this work at all on this VM" cheaply. It does not answer Q2, Q3 or Q5, because its PAM file and provisioning are not Tinkero's. Do it on a clone of `tinkero-spike-clean-f44` and delete that clone afterwards.

## 3. Record the GNOME baseline (for Q5)

Log into GNOME as your user, set a non-default appearance so that a change would be visible (Phase 0: Fedora 44 defaults to Light, so choose **Dark**), then:

```bash
mkdir -p ~/spike && cat > ~/spike/snap.sh <<'EOF'
#!/bin/bash
# usage: snap.sh <label>
out=~/spike/snap-$1.txt
{
  echo "## gsettings interface"; gsettings list-recursively org.gnome.desktop.interface | sort
  echo "## default browser";     xdg-settings get default-web-browser
  echo "## mailto";              xdg-mime query default x-scheme-handler/mailto
  echo "## xdg dirs";            for d in DESKTOP TEMPLATES PUBLICSHARE DOCUMENTS DOWNLOAD; do echo "$d=$(xdg-user-dir $d)"; done
  echo "## keyrings";            ls -1 ~/.local/share/keyrings 2>/dev/null; cat ~/.local/share/keyrings/default 2>/dev/null
  echo "## bashrc";              sha256sum ~/.bashrc
  echo "## gtk bookmarks";       cat ~/.config/gtk-3.0/bookmarks 2>/dev/null
  echo "## user applications";   ls -1 ~/.local/share/applications 2>/dev/null
} > "$out"; echo "wrote $out"
EOF
chmod +x ~/spike/snap.sh && ~/spike/snap.sh 0-baseline
```

## 4. Install the package substrate

```bash
sudo dnf copr enable agaspar/omedora-4
# COPR: compositor stack, shell host, session manager, tools. Do NOT install the omedora or omedora-settings packages.
sudo dnf install hyprland hyprland-guiutils hyprland-preview-share-picker hyprpicker hyprsunset \
  xdg-desktop-portal-hyprland quickshell uwsm tensaku ttfx herdr mise omedora-nerd-fonts
# Fedora: the hard requirements from the spec's dependency manifest (section 6)
sudo dnf install xdg-desktop-portal-gtk lua qt6-qtwayland qt6-qtmultimedia qt6-qtimageformats qt6-qtsvg \
  gtk4-layer-shell fontawesome-fonts-all yaru-icon-theme polkit gnome-keyring pipewire wireplumber \
  pipewire-pulseaudio pamixer brightnessctl power-profiles-daemon bluez bluez-tools NetworkManager udiskie socat \
  inotify-tools jq gum git foot xdg-terminal-exec tmux grim slurp wl-clipboard wtype pamtester
rpm -q hyprland quickshell uwsm        # record the exact versions in the findings note
# Fedora also packages an older quickshell; make sure the COPR's build won:
dnf -q repoquery --installed --qf '%{name} %{version} %{from_repo}\n' quickshell hyprland uwsm
```

If a name does not resolve, note it: that is a correction to the spec's manifest. (`bluez-tools` provides `/usr/bin/bt-agent`, which the `bt-agent` user unit runs; add it to the spec's manifest if the unit proves useful.)

## 5. Assemble the tree by hand, the Tinkero way

This reproduces what the `tinkero` RPM will do (spec 4.2), minus the menu rewrite and branding, which are not what the spike is testing.

```bash
# 5.1 The tree, at the pinned commit
sudo git clone --depth 1 --branch v4.0.4 https://github.com/omacom/omarchy.git /usr/share/omarchy
sudo git -C /usr/share/omarchy rev-parse HEAD   # expect c668141e9c42b13c80c9ca4ea108e11708c5e8a5
sudo restorecon -R /usr/share/omarchy           # a hand copy needs this; the RPM will not

# 5.2 Commands on PATH the way upstream lays them out: real files in /usr/bin, symlinks in the tree
cd /usr/share/omarchy
for f in bin/omarchy*; do sudo mv "$f" /usr/bin/ && sudo ln -s "/usr/bin/$(basename "$f")" "$f"; done
sudo restorecon -R /usr/bin

# 5.3 Neutralise the package plumbing (minimal stand-ins for the spec's replacements)
sudo tee /usr/bin/omarchy-pkg-present >/dev/null <<'EOF'
#!/bin/bash
for p in "$@"; do rpm -q "$p" &>/dev/null || exit 1; done
EOF
sudo tee /usr/bin/omarchy-pkg-missing >/dev/null <<'EOF'
#!/bin/bash
for p in "$@"; do rpm -q "$p" &>/dev/null || exit 0; done; exit 1
EOF
sudo tee /usr/bin/omarchy-pkg-add >/dev/null <<'EOF'
#!/bin/bash
exec sudo dnf install -y "$@"
EOF
sudo tee /usr/bin/omarchy-update-available >/dev/null <<'EOF'
#!/bin/bash
exit 1
EOF
sudo tee /usr/bin/omarchy-update >/dev/null <<'EOF'
#!/bin/bash
echo "Tinkero updates through dnf upgrade and mise up."
EOF

# 5.4 Replace upstream's first-run chain with a no-op. This is the important one: left alone it rewrites
#     XDG dirs, the default browser, GNOME's dconf keys and the default keyring (audit, section 6).
sudo tee /usr/bin/omarchy-provision-first-run >/dev/null <<'EOF'
#!/bin/bash
exit 0
EOF
sudo cp /usr/bin/omarchy-provision-first-run /usr/bin/omarchy-provision-user

# 5.5 Session wiring
sudo install -Dm644 default/uwsm/env.d/10-omarchy /usr/share/uwsm/env.d/10-omarchy
sudo tee /usr/share/wayland-sessions/tinkero.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Tinkero
Comment=Tinkero Hyprland session managed by uwsm
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
TryExec=uwsm
Type=Application
EOF
sudo install -Dm644 default/fonts/omarchy/omarchy.ttf /usr/share/fonts/omarchy/omarchy.ttf
sudo install -Dm644 default/fontconfig/conf.avail/50-omarchy.conf /usr/share/fontconfig/conf.avail/50-omarchy.conf
sudo ln -sf /usr/share/fontconfig/conf.avail/50-omarchy.conf /etc/fonts/conf.d/50-omarchy.conf
sudo fc-cache -f
```

That is upstream's `default/wayland-sessions/omarchy.desktop` with only `Name` and `Comment` changed.

Phase 0: `tee`/`cp` may create the stand-ins without the execute bit; follow 5.3 and 5.4 with `sudo chmod +x /usr/bin/omarchy-pkg-present ... /usr/bin/omarchy-provision-user` and `sudo restorecon` on them. Also, pasting heredocs with indentation breaks them; write those files with an editor or one-line `printf | sudo tee` commands.

Per-user setup, as your user (this is what `tinkero-provision` will do; note every file that already existed):

```bash
export OMARCHY_PATH=/usr/share/omarchy
# seed configs, never overwriting
cp -rn "$OMARCHY_PATH"/config/. ~/.config/
# keep the preinstalled-app bindings off with upstream's own marker, re-add the host-neutral ones (audit, section 7)
mkdir -p ~/.local/state/omarchy && touch ~/.local/state/omarchy/preinstalls-removed
cat >> ~/.config/hypr/bindings.lua <<'EOF'
o.bind("SUPER + ALT + RETURN", "Tmux", { omarchy = "terminal-tmux" })
o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })
EOF
# skills
mkdir -p ~/.agents/skills ~/.claude/skills ~/.codex/skills
for s in "$OMARCHY_PATH"/default/agents/skills/*/; do s=${s%/}; n=${s##*/}
  ln -sfn "$s" ~/.agents/skills/"$n"; ln -sfn "$s" ~/.claude/skills/"$n"; ln -sfn "$s" ~/.codex/skills/"$n"; done
# agent stubs and ~/Work
# upstream sources these under `bash -eE`; keep that so a failure stops here instead of passing silently.
# mise-work.sh needs the network: it runs `mise use -g node@latest`.
bash -eE "$OMARCHY_PATH/install/user/mise.sh"
bash -eE "$OMARCHY_PATH/install/user/mise-work.sh"
# user units (five, not upstream's six)
mkdir -p ~/.config/systemd/user && cp "$OMARCHY_PATH"/default/systemd/user/*.service ~/.config/systemd/user/
rm -f ~/.config/systemd/user/omarchy-migrate-notify.service
systemctl --user daemon-reload
systemctl --user enable omarchy-crash-watch omarchy-sleep-lock omarchy-recover-internal-monitor omarchy-fcitx5 bt-agent
```

The Docker TUI binding is left out of the spike (no lazydocker installed). Do **not** run `omarchy-theme-set` yet; section 8 needs the baseline intact until the restore prototype is in place.

Checkpoint: shut down, `virt-clone --original tinkero-spike --name tinkero-spike-assembled --auto-clone`.

## 6. Lock-screen PAM (Q2, Q3)

Install the "wrapped" variant (this host has no `with-faillock`):

```bash
sudo tee /etc/pam.d/omarchy-lock-password >/dev/null <<'EOF'
auth     required       pam_faillock.so preauth silent deny=10 unlock_time=120
auth     include        password-auth
auth     [default=die]  pam_faillock.so authfail deny=10 unlock_time=120
account  required       pam_faillock.so
account  include        password-auth
EOF
sudo restorecon /etc/pam.d/omarchy-lock-password
```

**6.1 The stack alone, without the GUI** (as your user, not root; this is how the lock screen calls PAM):

```bash
sudo faillock --user "$USER" --reset
pamtester omarchy-lock-password "$USER" authenticate     # wrong password
sudo faillock --user "$USER"                             # expect exactly 1 failure
pamtester omarchy-lock-password "$USER" authenticate     # wrong again: expect 2
pamtester omarchy-lock-password "$USER" authenticate acct_mgmt   # correct password
sudo faillock --user "$USER"                             # expect the tally cleared
```

Record the counts. If an unprivileged `pamtester` cannot authenticate at all, that is already the answer to Q2 at the PAM level (check `journalctl -b | grep -i unix_chkpwd` and `sudo ausearch -m AVC -ts recent`).

**6.2 Through the real lock screen.** Log out, pick **Tinkero** at GDM (the gear icon). Once in: `Super+Ctrl+L` (or `omarchy-system-lock`). Wrong password twice, then the right one. From a TTY or after unlocking:

```bash
sudo faillock --user "$USER"
sudo ausearch -m AVC -ts recent
journalctl --user -t omarchy-shell -b | tail -50
```

If you get locked in: `Ctrl+Alt+F3`, log in, `loginctl unlock-sessions` or `loginctl terminate-session <id>`.

**6.3 The other variant.** `sudo authselect enable-feature with-faillock`, then:

- leave the wrapped file in place and repeat 6.1: expect **two** failures recorded per wrong attempt. That confirms why two variants exist. Note at what attempt lockout triggers (Fedora's `faillock.conf` default is `deny=3`).
- switch to the plain variant and repeat 6.1: expect one per attempt.

```bash
printf 'auth     include  password-auth\naccount  include  password-auth\n' | sudo tee /etc/pam.d/omarchy-lock-password
```

Finish with `sudo authselect disable-feature with-faillock`, restore the wrapped file, `sudo faillock --user "$USER" --reset`.

## 7. Milestones by hand (Q1, Q4, Q6)

In the Tinkero session, first:

```bash
hyprctl configerrors            # expect empty
omarchy-shell shell ping        # expect ok
echo "$XDG_SESSION_DESKTOP"     # expect Hyprland
command -v herdr mise claude    # herdr and mise from /usr/bin; claude is a stub in ~/.local/bin
```

**Milestone A, agent**

- [ ] `Super+Shift+Ctrl+A` opens the agent picker
- [ ] choosing an agent installs it through mise in a floating terminal and launches it
- [ ] the agent finds the `omarchy` skill (ask it "which skill covers customizing this desktop?")
- [ ] asked to install `htop`, it uses `omarchy pkg add` and dnf succeeds

**Milestone B, desktop** (branding is not part of the spike)

- [ ] bar renders with Nerd glyphs; clock, workspaces, tray
- [ ] `Super+Space` menu opens; note dead or wrong entries (expected before the menu rewrite; list them, they validate the audit's delete list)
- [ ] notification: `omarchy-notification-send "test" "hello"`
- [ ] lock and unlock (section 6.2); idle lock fires
- [ ] `Print` screenshot, region select, `tensaku` annotation opens
- [ ] `Super+Ctrl+V` clipboard history
- [ ] `Super+Return` terminal (foot); `Super+Ctrl+Return` herdr; `Super+Alt+Return` tmux
- [ ] screen share picker appears in a browser's share dialog (portal)
- [ ] polkit prompt appears for `pkexec true`
- [ ] suspend and resume returns to the lock screen, and the lock was already up when the screen came back (upstream raises logind's `InhibitDelayMaxSec` to 15 s for this; Tinkero leaves the default 5 s, so try it five times and record any resume that shows the desktop first)
- [ ] power key: run `systemd-inhibit --what=handle-power-key --who=tinkero --why=menu sleep infinity &` as your user (no sudo), then press the VM's power button (`virsh send-key tinkero-spike KEY_POWER`). Pass: the VM does not power off, and the shell's power menu opens. Note whether the inhibitor was granted without a polkit prompt (spec 4.2's `tinkero-inhibit-power-key.service` depends on it)

After a session of normal use:

```bash
sudo ausearch -m AVC -ts today | tee ~/spike/avc.txt
```

Paste every denial into the findings note, even ones that look unrelated.

## 8. GNOME invariant (Q5)

The save/restore mechanism of spec 4.9 does not exist yet, so prototype it. As your user:

```bash
mkdir -p ~/.local/bin ~/.local/state/tinkero
cat > ~/.local/bin/tinkero-gnome-keys <<'EOF'
#!/bin/bash
# usage: tinkero-gnome-keys save|restore
f=~/.local/state/tinkero/gnome-interface.saved
keys="color-scheme gtk-theme icon-theme"
case $1 in
save)    [[ -f $f ]] && exit 0
         for k in $keys; do echo "$k=$(gsettings get org.gnome.desktop.interface "$k")"; done > "$f" ;;
restore) [[ -f $f ]] || exit 0
         while IFS== read -r k v; do gsettings set org.gnome.desktop.interface "$k" "$v" || exit 1; done < "$f"
         rm -f "$f"; logger -t tinkero-gnome-restore "restored by ${2:-unknown}" ;;
esac
EOF
chmod +x ~/.local/bin/tinkero-gnome-keys

cat > ~/.config/systemd/user/tinkero-gnome-restore.service <<'EOF'
[Unit]
Description=Restore GNOME interface settings at Tinkero logout
PartOf=graphical-session.target
After=graphical-session.target dbus.service
# No [Install] section on purpose: GNOME activates graphical-session.target too, and a unit started there
# would save the login-time values and silently undo any appearance change made during that GNOME session.
# It is started explicitly from Hyprland's autostart instead (below).
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=%h/.local/bin/tinkero-gnome-keys save
ExecStop=%h/.local/bin/tinkero-gnome-keys restore unit
EOF
systemctl --user daemon-reload
# start it from inside the Tinkero session only, after Hyprland has imported its environment
# Phase 0: the user file uses the o. API, not hl.on
echo 'o.launch_on_start("systemctl --user start tinkero-gnome-restore.service")' >> ~/.config/hypr/autostart.lua

mkdir -p ~/.config/autostart
cat > ~/.config/autostart/tinkero-gnome-restore.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Tinkero GNOME restore
Exec=$HOME/.local/bin/tinkero-gnome-keys restore autostart
OnlyShowIn=GNOME;
EOF
# the heredoc above is quoted, so expand $HOME now: .desktop Exec lines have no shell and no single quotes
sed -i "s|\$HOME|$HOME|" ~/.config/autostart/tinkero-gnome-restore.desktop
```

Phase 0 result for this section: the unit's `ExecStop` fired on all three session ends, the autostart entry never did, and two keys the script did not list leaked (`cursor-theme`, changed by the shell before the save ran; `text-scaling-factor`, changed by `omarchy-display-text-size`). The design moved to a separate dconf profile for the session (spec 4.9); re-running this section for Phase 2F means adding `DCONF_PROFILE=tinkero` to the uwsm env and diffing `~/.config/dconf/user`'s checksum instead of a key list.

Run this cycle three times, ending the Tinkero session a different way each time: menu logout, `loginctl terminate-session`, and `pkill -9 Hyprland`.

1. Log into Tinkero. `omarchy-theme-set tokyo-night`, then `omarchy-theme-set catppuccin-latte`.
2. End the session.
3. Log into GNOME. `~/spike/snap.sh 1-after-menu-logout` (then `2-...`, `3-...`), and `diff ~/spike/snap-0-baseline.txt ~/spike/snap-1-*.txt`.
4. `journalctl -t tinkero-gnome-restore -b` tells you which path did the restore: `unit` or `autostart`.

Expected diff: nothing, apart from whatever you deliberately seeded. Record, per run, who restored. If `unit` never wins, the spec should drop the unit and keep only the autostart entry.

Also diff for damage from anywhere else: browser, mailto, XDG dirs, keyrings and `~/.local/share/applications` must be unchanged. If any moved, find which script did it (`grep -rl` in `/usr/bin/omarchy-*`) and add it to the audit.

## 9. Findings note

Write `docs/research/phase-0-findings.md` with:

```markdown
# Phase 0 findings
Date, host GPU, VM or bare metal, package versions (rpm -q hyprland quickshell uwsm qt6-qtbase).

## Answers
Q1 GDM session: pass/fail, notes
Q2 Lock under SELinux: pass/fail, AVC output
Q3 PAM variants: table of faillock counts per step in 6.1 and 6.3
Q4 AVC denials: full list, attribution
Q5 GNOME invariant: three diffs, who restored each time
Q6 Milestones A and B: the checklists with results
Q7 Power-key inhibitor: granted without prompt? menu opened?

## Corrections to this guide
Every command that had to change, and why.

## Corrections to the spec and audit
Missing or wrong package names (spec 6), scripts that touched shared state (audit 6), menu entries that were dead (audit 7), anything else.

## Decisions
Lock mechanism: Quickshell lock with two PAM variants / hyprlock fallback.
GNOME restore: unit plus autostart / autostart only.
Go or no-go on Phase 1, and why.
```

Bring that note back and the Phase 1 and Phase 2 implementation plans get written against facts instead of derivations.
