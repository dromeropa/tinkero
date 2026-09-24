# Plan 2F design: session integration

**Status:** design for plan 2F, derived from the Tinkero design spec (`2026-09-17-tinkero-design.md`, revision 2.1) on 2026-09-24. The master spec stays the binding authority; this document works out sections 4.2, 4.3, 4.6, 4.8, 4.9 and 8 to the level a plan needs and records the decisions the master spec leaves open. Where the two disagree, this document says so under "Decisions" and the master spec is amended when the plan lands.
**Plan:** `docs/superpowers/plans/2026-09-24-phase-2f-session-integration.md`.
**Scope source:** the 2F row of `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` and placeholder issue #10 (body only; the thread has no comments), plus the roadmap's queue items addressed to 2F by Phase 0, 2E and 2D.
**Depends on:** plans 2A and 2E, both on `master` (2E landed at `118bd1a`, 2D at `ba77d8d`, and 2E's four parked follow-ups at `baec68e`, PR #22, which closed issue #20). Nothing in 2F edits `bin/tinkero-provision`.

## 1. What 2F delivers

Plan 2F wires the provisioned home directory into a session that behaves on Fedora, and makes the `tinkero` RPM installable. The roadmap row lists six deliverables; the queue items add three:

1. **Session-scoped user units.** Every user unit the package ships has its `[Install]` section stripped at build time (spec 4.9), Tinkero's `tinkero-inhibit-power-key.service` joins them (spec 4.2), `omarchy-fcitx5.service` gets its drop-in (spec 4.9), and `provision/session-units.list` gains the inhibitor (2E design D6).
2. **The `DCONF_PROFILE` export** from uwsm's `env.d`, which completes the separate dconf database 2E seeded (spec 4.9).
3. **Lock-screen authentication:** the two PAM variants, `tinkero-pam-sync` and the RPM plumbing around them (`%ghost`, `%posttrans`) (spec 4.8).
4. **The fingerprint port:** the `omarchy-apply-lock` patch (0011) and the two fingerprint replacements (spec 4.3), which clears the last non-permanent arch-leak allowlist entry.
5. **The first real COPR build of `tinkero`**, closed by hand after the green build (workflow guide, adaptation 1), with the `nwg-panel` depsolve re-run (Phase 1 queue) and the proof that `BuildRequires: python3` reaches the mock chroot (issue #5's caveat).
6. **The VM check** of spec 7: the Phase 0 GNOME cycle re-run with the dconf profile, and the stripped units shown not to start under GNOME. A manual step recorded on its issue, not a CI job.

Added by this design, each argued under Decisions: a gate for the session units (D3), a binary RPM build in CI (D14), and drop-ins that make two listed units follow the session (D2).

Not in 2F: `tinkero-status` and its drift report (Phase 3; 2F gives it `tinkero-pam-sync --check`); the release workflow and the VM smoke test in CI (Phase 3); suspend-to-lock timing, the lid-closed fingerprint behaviour and the speaker tuning's absence under GNOME on a matching laptop (bare metal; a VM matches no tuning); the `learn.*` web-app rows on a Firefox host (D16).

## 2. The session units

### 2.1 What the tree ships

At `v4.0.4` the tree's `default/systemd/user/` holds eight units and one drop-in directory (`app.slice.d/10-oomd.conf`). `build/drop.list` removes `omarchy-migrate-notify.service`, so seven units reach the payload, each with `[Install] WantedBy=graphical-session.target` (or `graphical-session-pre.target`), and each in two places: `/usr/lib/systemd/user/` (assemble step 5) and `/usr/share/omarchy/default/systemd/user/` (the tree, step 6). The real payload today has 14 `[Install]` sections.

| Unit | Bound to the session today | On the session list |
|---|---|---|
| `omarchy-crash-watch.service` | `PartOf=graphical-session.target` | yes |
| `omarchy-sleep-lock.service` | `PartOf=graphical-session.target` | yes |
| `omarchy-fcitx5.service` | `PartOf=graphical-session.target` | yes |
| `omarchy-recover-internal-monitor.service` | oneshot, runs and exits | yes |
| `bt-agent.service` | **no `PartOf`** | yes |
| `omarchy-speaker-tuning.service` | `PartOf=pipewire.service` only | yes (copied to `~/.config/systemd/user` on matching laptops) |
| `omarchy-tailscale-receive.service` | no; inert without `/usr/bin/tailscale` | no |

Spec 4.6 says all the listed units are `PartOf=graphical-session.target`. Two are not: `bt-agent` (an auto-accepting Bluetooth pairing agent) and the speaker tuning keep running after the Tinkero session ends for as long as the user manager lives, which is ten seconds on a stock Fedora (`UserStopDelaySec`) and indefinitely with lingering enabled (podman users enable it). A GNOME login in that window inherits them. D2 closes this.

### 2.2 Stripping

A new assemble step, **3e**, runs after branding and before the relocation: for every regular file matching `*.service`, `*.socket`, `*.timer`, `*.path` or `*.target` under the tree's `default/systemd/user/`, delete the `[Install]` section (from its header line to the next section header or the end of the file). Stripping in the tree, not in the copy, matters: `omarchy-audio-tuning` copies `$OMARCHY_PATH/default/systemd/user/omarchy-speaker-tuning.service` into `~/.config/systemd/user/` and enables it, so a tree that kept the section would re-enable the unit under GNOME on every laptop the tuning matches (D1). The step prints `stripped [Install] from N unit(s)` and fails if any unit file under the tree's directory still has a section afterwards. At `v4.0.4`, N is 7; after steps 5 and 6 the payload has 0.

`systemctl --user enable` on a unit with no `[Install]` section prints a notice and changes nothing, which is what `omarchy-audio-tuning` then does; its `restart` still starts the unit for the current session, and the list starts it at every later session (2E design D4).

### 2.3 Tinkero's unit files

All under `systemd/` at the repo root (spec 12), installed by step 5 into `/usr/lib/systemd/user/` with the tree's units. None has an `[Install]` section; the gate (2.4) proves it.

`systemd/tinkero-inhibit-power-key.service`:

```ini
[Unit]
Description=Tinkero: the power key opens the shell's power menu instead of powering off
# logind's default polkit policy grants handle-power-key to the active session without a
# prompt (Phase 0, Q7); upstream binds XF86PowerOff to the power menu. Spec 4.2.
After=graphical-session.target
PartOf=graphical-session.target
ConditionEnvironment=WAYLAND_DISPLAY

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=handle-power-key --who=Tinkero --why="The power key opens the power menu" --mode=block /usr/bin/sleep infinity
Restart=on-failure
RestartSec=5
```

`systemd/omarchy-fcitx5.service.d/tinkero.conf` (spec 4.9; `fcitx5` is a hard requirement since 2B, so the condition is the quiet failure for a host that removed it anyway):

```ini
[Unit]
ConditionPathExists=/usr/bin/fcitx5
StartLimitIntervalSec=60
StartLimitBurst=5
```

`systemd/bt-agent.service.d/tinkero.conf` (D2; the `ConditionPathExists` line is D17):

```ini
[Unit]
# Tinkero: stop with the Tinkero session, so nothing of it runs under a later GNOME login.
PartOf=graphical-session.target
# Tinkero: bt-agent's binary ships in Fedora's bluez-tools, not bluez itself (D17); belt and
# braces alongside the spec's Requires, the same pattern as the fcitx5 drop-in above.
ConditionPathExists=/usr/bin/bt-agent
```

`systemd/omarchy-speaker-tuning.service.d/tinkero.conf` (D2):

```ini
[Unit]
# Tinkero: stop with the Tinkero session, so nothing of it runs under a later GNOME login.
PartOf=graphical-session.target
```

systemd reads a drop-in directory from every unit path, so the speaker tuning's drop-in under `/usr/lib/systemd/user/` applies to the copy in `~/.config/systemd/user/` too.

`provision/session-units.list` gains `tinkero-inhibit-power-key.service` after `bt-agent.service`.

### 2.4 The session-units gate

`ci/gate-session-units PAYLOAD LIST` (D3), run by `./dev gates` after the five existing gates, no allowlist. It fails when:

1. any regular unit file under `usr/lib/systemd/user/` or `usr/share/omarchy/default/systemd/user/` contains an `[Install]` line;
2. a unit named in `LIST` has no file under `usr/lib/systemd/user/`;
3. a unit named in `LIST` is neither bound to the session (`PartOf=graphical-session.target` in the unit or in any `usr/lib/systemd/user/<unit>.d/*.conf`) nor a `Type=oneshot` without `RemainAfterExit=yes`.

It prints `PASS: session units (N listed, M unit files, no [Install])` or one line per finding. At `v4.0.4` after 2F: 7 listed, 8 unit files (seven upstream, the inhibitor), no `[Install]`. After a bump, a new upstream unit is stripped automatically; the gate catches a listed unit that upstream renamed or unbound.

## 3. The session's dconf profile

`session/uwsm-env.d/20-tinkero`, installed to `/usr/share/uwsm/env.d/20-tinkero` beside upstream's `10-omarchy` (D4):

```sh
# Tinkero: the session reads and writes its own dconf database, ~/.config/dconf/tinkero,
# never GNOME's ~/.config/dconf/user (spec 4.9). /etc/dconf/profile/tinkero names it.
export DCONF_PROFILE=tinkero
```

uwsm sources `env.d` files in lexical order with `sh` and exports what they change into the systemd user manager's activation environment, so the variable reaches Hyprland, everything it spawns, the portals and every D-Bus or systemd activated service started during the session. Phase 0 confirmed that `/usr/share/uwsm/env.d/` is read (it is where `10-omarchy` put `OMARCHY_PATH` on the spike).

uwsm removes the variables it exported from the activation environment when the session stops. That cleanup is what keeps a GNOME login that reuses a still-running user manager (the ten-second window, or lingering) from inheriting `DCONF_PROFILE=tinkero`; the VM check tests it after each of the three session ends, with lingering enabled. If it fails, the fallback is one more line in the inhibitor unit, `ExecStopPost=/usr/bin/systemctl --user unset-environment DCONF_PROFILE`, which fires on every session end for the same reason the Phase 0 restore unit did.

`%files` gains `%{_datadir}/uwsm/env.d/20-tinkero`. The profile file and the seeding shipped with 2E; nothing in `tinkero-provision` changes. The spec's fallback, `tinkero-gnome-restore.service`, is not shipped (D5).

## 4. Lock-screen authentication

### 4.1 The variants

`distro/fedora/pam/omarchy-lock-password.wrapped` and `.plain`, installed to `/usr/share/tinkero/pam/`. The PAM lines are spec 4.8's, which Phase 0 validated line for line (Q2, Q3), after a header:

```
#%PAM-1.0
# omarchy-lock-password, variant "wrapped": written by tinkero-pam-sync because this host's
# password-auth has no pam_faillock. Do not edit; run `sudo tinkero-pam-sync` after changing
# authselect features. Design spec 4.8.
auth     required       pam_faillock.so preauth silent deny=10 unlock_time=120
auth     include        password-auth
auth     [default=die]  pam_faillock.so authfail deny=10 unlock_time=120
account  required       pam_faillock.so
account  include        password-auth
```

```
#%PAM-1.0
# omarchy-lock-password, variant "plain": written by tinkero-pam-sync because this host's
# password-auth already runs pam_faillock. Do not edit; run `sudo tinkero-pam-sync` after
# changing authselect features. Design spec 4.8.
auth     include        password-auth
account  include        password-auth
```

### 4.2 `tinkero-pam-sync`

`distro/fedora/bin/tinkero-pam-sync` (spec 12), installed to `/usr/bin` by a new loop in assemble step 6 (`distro/fedora/bin/tinkero-*`, the same shape as the `bin/tinkero-*` loop). Bash. Modes:

| Invocation | Does | Needs root |
|---|---|---|
| `tinkero-pam-sync` | writes the variant the host calls for to `/etc/pam.d/omarchy-lock-password` when the file differs or is missing; prints `wrote <variant>` or `current: <variant>` | yes (refuses otherwise with exit 2, naming `sudo tinkero-pam-sync`, and writes nothing) |
| `tinkero-pam-sync --variant` | prints `wrapped` or `plain` | no |
| `tinkero-pam-sync --check` | exit 0 with `current: <variant>` when the installed file equals the variant the host calls for; exit 1 with one line naming the difference (`missing`, `wrapped installed, plain needed`, `modified`) | no |

**Which variant** (D6): `plain` when `/etc/pam.d/password-auth` has an active auth line naming `pam_faillock.so` (the regex `^[[:space:]]*-?auth[[:space:]].*pam_faillock\.so`), otherwise `wrapped`. The included stack is what causes the double count, so the script reads it directly; on an authselect host the line is there exactly when `with-faillock` is on, which is spec 4.8's rule. A missing `password-auth` is an error (the lock's include would fail too): exit 2 with a message.

**Writing** (D7): `mktemp` in `/etc/pam.d` itself, `install`-style mode `0644`, then `mv` over the target, so the file inherits the directory's SELinux context (`etc_t`) with no `restorecon`, and a crash never leaves a half-written PAM file.

Seams for the tests: `TINKERO_PAM_DIR` (default `/etc/pam.d`), `TINKERO_SHARE` (default `/usr/share/tinkero`), `TINKERO_EUID` (the existing convention).

### 4.3 Packaging and install

`tinkero.spec.in`:

```
%posttrans
/usr/bin/tinkero-pam-sync || echo "tinkero: tinkero-pam-sync failed; the lock screen will refuse to lock until 'sudo tinkero-pam-sync' succeeds" >&2
```

and in `%files`:

```
%ghost %attr(0644,root,root) %{_sysconfdir}/pam.d/omarchy-lock-password
%ghost %attr(0644,root,root) %{_sysconfdir}/pam.d/omarchy-lock-fingerprint
```

`%ghost` makes RPM own both files (`rpm -qf` answers, erase removes them) without shipping content. Neither is `%config`: rpm skips `%ghost` entries in `rpm -V` entirely, so `%config`/`missingok` on a ghost buys nothing and risks an `.rpmsave` on erase (D9). The missing-file signal Phase 3's `tinkero-status` reads is `tinkero-pam-sync --check` reporting `missing`, not `rpm -V`. Neither file is created in the build root.

`%posttrans` runs on every install and upgrade, so an upgrade also corrects a variant the user's authselect change made stale. If the file is missing, upstream's lock refuses to lock (`Service.qml` checks `/etc/pam.d/omarchy-lock-password` and logs `lock-denied: missing-pam`) rather than locking the user out; the failure mode is a session that does not lock, which the message names.

`install.sh`'s system stage runs `sudo tinkero-pam-sync` after `dnf install` (D8): on a re-run the install is a no-op and `%posttrans` does not fire, so this is what repairs drift.

## 5. The fingerprint port

### 5.1 Patch 0011, `omarchy-apply-lock`

Upstream's script writes both PAM files: the password one with an Arch-shaped stack (`pam_unix` directly, `account include system-local-login`, which does not exist on Fedora), the fingerprint one when `fprintd-list` shows enrolments for the target user. The patch (spec 4.3, audit sections 4.3 and 9):

- deletes the password-file block; that file is `tinkero-pam-sync`'s;
- writes the fingerprint file only when upstream's own test passes (`fprintd-list <user> | grep -qi finger`, which in practice means a reader is present, since its "no fingers enrolled" line matches too) **and** the host's `/etc/pam.d/system-auth` has an active line naming `pam_fprintd.so` (D10), so the lock offers a finger exactly when the host's own login does, and turning fingerprint off host-wide turns it off here;
- writes `account include password-auth` instead of `system-local-login`;
- keeps upstream's target-user logic (`OMARCHY_INSTALL_USER`, `SUDO_USER`, `PKEXEC_UID`), its root `PATH` guard and its `omarchy-shell lock status` echo.

The patch is generated from the edited file with `diff -u` and applied with `git apply` like 0001 to 0010. It has 19 changed lines (16 removed, 3 added), over the fifteen-line size spec 4.3 gives for all patches but the menu one; nearly all of it is the deleted password block, which costs nothing to rebase, and spec 4.3's sentence is amended to say so.

### 5.2 The replacements

`distro/fedora/replacements/omarchy-setup-security-fingerprint` (spec 4.3):

1. `omarchy-hw-fingerprint` or exit 1 with upstream's message (the detection script is portable and kept).
2. `omarchy-pkg-add fprintd fprintd-pam` (the name map routes both to dnf; `pkexec` inside the session).
3. `fprintd-enroll` as the user (Fedora's fprintd polkit policy lets the active session enrol its own finger; upstream's `sudo fprintd-enroll "$USER"` is not needed), then `fprintd-verify`. On failure, upstream's messages and exit codes.
4. `authselect enable-feature with-fingerprint`, elevated the way the package wrappers elevate (`pkexec` in a session, `sudo` otherwise, the `elevate` function of `/usr/share/tinkero/pkg.sh`); a no-op when the feature is on, which it is by default on Fedora 44 Workstation (Phase 0, correction 5).
5. `omarchy-apply-lock`, elevated the same way, so upstream's `PKEXEC_UID` logic finds the user.

`distro/fedora/replacements/omarchy-remove-security-fingerprint`:

1. `authselect disable-feature with-fingerprint`, elevated, after printing that this turns fingerprint login off for the whole host, GDM included (upstream's removal also changes `sudo` and polkit host-wide).
2. `omarchy-apply-lock`, elevated, which now removes the fingerprint file because `system-auth` no longer names `pam_fprintd.so`.
3. No package removal (D11): `fprintd` and `fprintd-pam` ship with Fedora Workstation, and Tinkero does not erase a Fedora default (spec 6's `ppd-service` rule; spec 4.11: removal leaves the host as it was). The enrolled prints stay; they are the user's and GNOME's too.

`distro/fedora/pkgmap.tsv` gains `fprintd-pam<TAB>dnf<TAB>fprintd-pam` (the name-map gate requires a row for every literal package name). Upstream's clamshell gate (`pam_exec.so ... omarchy-hw-laptop-closed` inserted before `pam_fprintd` in `sudo` and `polkit-1`) is not ported (D12).

The menu's Remove > Fingerprint row (`remove.security.fingerprint`) upstream gates on `"when":"omarchy-pkg-present fprintd"`; since D11 never removes `fprintd`, that guard is always true on Fedora Workstation and the row would always show, whether or not the lock screen actually offers a finger. `menu/overrides.jsonc` replaces it, keeping upstream's `icon`, `label` and `action`, with `"when":"test -f /etc/pam.d/omarchy-lock-fingerprint"`: the file `omarchy-apply-lock` actually writes, so the row tracks what the lock screen does.

With both replacements in place, `usr/bin/omarchy-setup-security-fingerprint   # plan 2F` leaves `ci/allow/arch-leak.allow`, which is then at its six permanent entries. `host.md`'s PAM bullet, which today says the fingerprint entry is ported in 2F and must not be run until then, is rewritten to describe the port.

## 6. The first COPR build

`build/tinkero-copr` learns the `tinkero` package (D13): `tinkero` becomes the last line of `distro/fedora/specs/build-order.txt`, and for that one name the existence check looks for `tinkero.spec.in` at the root and the registration drops `--subdir` and passes `--spec tinkero.spec`, which `.copr/Makefile` already routes to `srpm-tinkero`. Registration keeps `--webhook-rebuild off`: the package builds when the `copr-build` workflow is dispatched from `master`, like the rest of the set, never on push. The master spec's 4.2 sentence "COPR rebuilds on push through its GitHub webhook" is amended.

Two-stage verification (workflow guide, adaptation 1). Before the merge, CI proves the SRPM and, new in 2F, the binary RPM (D14). After the merge, the operator dispatches `copr-build` with `packages=tinkero`, `command=all`, and records on the issue: the build is green; its build log shows `python3`, `python3-fonttools` and `ImageMagick` installed into the mock chroot; on a Fedora 44 host with the COPR enabled, `dnf install --assumeno tinkero` resolves with no `nwg-panel` and no `playerctl` in the transaction. The issue is then closed by hand.

## 7. The VM check

A guide, `docs/guides/phase-2f-vm-check.md`, in the shape of `phase-0-spike.md`: the Phase 0 VM restored to `tinkero-spike-clean-f44` (Fedora 44, GDM, no Tinkero), `install.sh` from `master` against the COPR, and these checks, each a checkbox with its pass condition:

1. **Install:** `install.sh` completes; `rpm -qf /etc/pam.d/omarchy-lock-password` names `tinkero`; `tinkero-pam-sync --check` exits 0 without root; `ls ~/.config/dconf/tinkero` exists after provisioning from GNOME.
2. **Units inside Tinkero:** after login, `systemctl --user list-units 'omarchy-*' 'tinkero-*' bt-agent.service` shows the listed units active (bt-agent skipped without Bluetooth, the tuning skipped on a VM); `systemctl --user show-environment | grep DCONF_PROFILE` prints `DCONF_PROFILE=tinkero`; `systemd-inhibit --list` shows the Tinkero `handle-power-key` lock; `virsh send-key ... KEY_POWER` opens the power menu and does not power off.
3. **Lock:** `Super+Ctrl+L`, wrong password twice, right password; `faillock --user $USER` counts 2 then 0; no AVC (`sudo ausearch -m AVC -ts recent`). Repeat after `sudo authselect enable-feature with-faillock && sudo tinkero-pam-sync`: `--check` says current, the file is the plain variant, and each failure counts once.
4. **The GNOME invariant** (spec 8), three cycles, against a baseline taken in GNOME before `install.sh` runs (the install itself must change nothing), with `clock-show-seconds` set in GNOME as a canary the session never writes: record `sha256sum ~/.config/dconf/user`, the `gsettings list-recursively org.gnome.desktop.interface` output, `xdg-settings get default-web-browser`, the `xdg-user-dir` outputs and the keyring listing in GNOME; enable lingering (`loginctl enable-linger`); log into Tinkero, switch theme twice, run `omarchy-display-text-size` once (it writes `text-scaling-factor`); end the session by menu logout, by `loginctl terminate-session`, by `pkill -9 Hyprland` in turn; log into GNOME and compare. Pass: identical, including the checksum, after each cycle; `cursor-theme` and `text-scaling-factor` unchanged (Phase 0's two leaks); `systemctl --user show-environment` has no `DCONF_PROFILE`; `systemctl --user list-units 'omarchy-*' 'tinkero-*' bt-agent.service` shows nothing active.
5. **Removal:** `tinkero-provision --remove`, `sudo dnf remove tinkero`: no `/etc/pam.d/omarchy-lock-*` and no `.rpmsave` beside them, no `~/.config/dconf/tinkero`, and the GNOME records still identical.
6. **Milestone B lines 2D could not check** (roadmap, 2D queue): the mark in the bar's menu button and beside the Packages row; About with the 54 by 26 logo and its "built on Omarchy" line; the screensaver; a theme's rotation showing `tinkero.png`. And one observation for D16: whether `learn.hyprland` opens anything with Firefox as the default browser.

Results, including any failure, are recorded on the issue and summarised in the roadmap's "What executing 2F added" section. A failure of item 4 reopens D4's fallback or spec 4.9's; a failure of item 3 is a blocker for Milestone B.

## 8. Decisions taken by this design

Each is a call the master spec leaves open or states in a form that cannot be built literally. They are listed so the operator can veto any of them at the approval gate; each says how to reverse it.

- **D1, `[Install]` is stripped inside the tree, before the copies.** Spec 4.2 says the build strips "every unit it ships"; the tree's copy is shipped too, and `omarchy-audio-tuning` installs from it. Reversal: move the step after step 5 and accept that the tuning unit is enabled under GNOME on matching laptops.
- **D2, drop-ins bind `bt-agent` and the speaker tuning to the session.** Spec 4.6 assumes every listed unit is `PartOf=graphical-session.target`; two are not, and one of them auto-accepts Bluetooth pairing. A drop-in per unit, no patch. Reversal: delete the two drop-in files.
- **D3, a gate for the session units, with no allowlist.** The strip and the drop-ins are properties of the built payload that a bump can silently undo; the gate makes them CI facts. Reversal: remove the gate from `./dev gates`.
- **D4, the `DCONF_PROFILE` export is Tinkero's own `env.d` file**, `20-tinkero`, not a patch to upstream's `10-omarchy`: no rebase cost, and upstream's file stays byte-identical. Isolation after the session ends relies on uwsm's own cleanup of the activation environment; the VM check tests it and section 3 names the one-line fallback. Reversal: one file.
- **D5, `tinkero-gnome-restore.service` is not shipped.** Spec 4.2 lists it among the installed units and spec 12 in the layout, but 4.9 makes it the fallback "if the profile approach fails its check in Phase 2F". Shipping an unused unit invites someone to start it. If the VM check fails, a follow-up issue adds it from the Phase 0 prototype. Reversal: that issue.
- **D6, `tinkero-pam-sync` chooses the variant from `password-auth`'s content, not from `authselect current`.** The double count is caused by the lines in the included stack; reading them gives spec 4.8's answer on every authselect profile and also on a host that is not authselect-managed. Reversal: replace the one `grep` with a parse of `authselect current`.
- **D7, the PAM file is written through a temporary file in `/etc/pam.d`**, so it inherits the directory's SELinux label (spec 5: no `restorecon` choreography) and is replaced atomically. Reversal: none needed; it is how the file is written.
- **D8, `install.sh` runs `sudo tinkero-pam-sync`** after `dnf install`. Spec 4.8 says so; spec 4.6's system stage says "nothing else". A re-run of `install.sh` is otherwise unable to repair a stale variant. Reversal: delete the line.
- **D9, both PAM files are `%ghost`, RPM owns them so erase removes them and `rpm -qf` explains them; no `%config`: rpm does not verify ghosts, and `%config` on a ghost could leave an `.rpmsave`.** Spec 4.8 names only the password file. Owning the fingerprint file too means `dnf remove tinkero` removes it (spec 4.11: nothing left behind). Reversal: drop the line and document the manual removal.
- **D10, the lock offers fingerprint when the user has enrolments and the host's `system-auth` uses `pam_fprintd.so`**, and the fingerprint file's account line includes `password-auth`. Upstream checks enrolments only; on Fedora the enrolments are GNOME's too and survive a removal, so without the second condition the remove command could never take fingerprint off the lock. Reversal: delete the condition in the patch.
- **D11, fingerprint removal disables `with-fingerprint` and removes no package.** Spec 4.3 has it drop `fprintd-pam`; Fedora 44 Workstation installs `fprintd` and `fprintd-pam` and enables the feature by default, and Tinkero does not erase a Fedora default (spec 6, 4.11). The command says it changes the host-wide setting before it does. Because `fprintd` is never removed, the menu's Remove > Fingerprint row (upstream: `when: omarchy-pkg-present fprintd`) can no longer use presence of the package as its visibility guard; `menu/overrides.jsonc` replaces the row to gate on `/etc/pam.d/omarchy-lock-fingerprint` existing instead (section 5.2). Reversal: add `omarchy-pkg-drop fprintd-pam` back, and drop the menu replacement.
- **D12, upstream's clamshell gate is not ported.** It inserts a `pam_exec` line into `sudo` and `polkit-1`, which authselect owns on Fedora, and `with-fingerprint` has no hook for it. With the lid closed, a fingerprint prompt waits for the reader's timeout before the password; that is stock Fedora's behaviour and a bare-metal check. Reversal: an authselect custom profile, which is host policy and out of scope.
- **D13, `tinkero` is registered by `tinkero-copr` and built by the workflow, webhook off.** Spec 4.2 says COPR rebuilds on push; the workflow guide makes every COPR build a post-merge, operator-dispatched step, and a push to `master` that rebuilt the user-facing package would bypass that. Reversal: `--webhook-rebuild on` for the one package.
- **D14, CI builds the binary RPM and inspects it.** COPR builds are post-merge, so a `%files`, `%ghost` or `%posttrans` mistake would otherwise surface only after a merge. CI rebuilds the SRPM it already makes (`rpmbuild --rebuild`), queries the file flags and scriptlets, unpacks the payload and runs the gates on it. The job's timeout rises from 15 to 30 minutes, since the build renders the wallpapers a second time. Reversal: delete the step.
- **D15, the VM check is a guide in the tree and its own last issue**, run against the COPR build, results on the issue. The roadmap calls it a manual step recorded on the issue; a written procedure is what made Phase 0 repeatable, and a bump re-runs it.
- **D16, the `learn.*` web-app rows are not 2F's.** The 2D queue left "2F or bare metal" to decide between a patch to `omarchy-launch-webapp`'s fallback and a name-map row for Chromium. It is a menu question, not session integration; the VM check records the behaviour (section 7, item 6) and the decision moves to the bare-metal pass.
- **D17, the spec requires `bluez-tools` and the `bt-agent` drop-in gets `ConditionPathExists=/usr/bin/bt-agent`.** `/usr/bin/bt-agent` ships in Fedora's `bluez-tools` (0.2.0 on Fedora 44), which the spec's `bluez` requirement does not pull in; without it, on a laptop with Bluetooth the unit would 203/EXEC and restart-loop. The condition is belt and braces, the same pattern as the fcitx5 drop-in (2.3), in case the package is ever missing despite the Requires. Reversal: drop both the Requires and the condition line.

## 9. What can be verified now, and what cannot

Hermetic, in `./dev check` and CI: the strip, the new files and the env file against the fixture tree (`tests/test-assemble.sh`); the session-units gate against fixture payloads (`tests/test-gates.sh`); every mode of `tinkero-pam-sync` against a fixture `/etc/pam.d` (`tests/test-pam-sync.sh`); the fingerprint replacements against stub `authselect`, `fprintd-*`, `pkexec` and package commands (`tests/test-replacements.sh`); `install.sh`'s new line (`tests/test-install.sh`); `tinkero-copr`'s new package (`tests/test-copr.sh`).

Against the real tree, in `./dev gates` and CI: patch 0011 applies; the payload has no `[Install]`; the session-units gate passes; the arch-leak allowlist is at six. In CI only: the binary RPM builds, its file list carries the two `%ghost` entries with their flags, `%posttrans` names `tinkero-pam-sync`, and the gates pass on its unpacked payload.

Only after the merge: the COPR build and the depsolve (section 6). Only on a VM: section 7. Only on bare metal: suspend-to-lock timing, the lid-closed fingerprint prompt, the polkit dialog's fingerprint mode (it reads `/etc/pam.d/polkit-1` for `pam_fprintd`, which Fedora includes through `system-auth`, so the dialog stays in password mode while PAM waits for the finger).

## 10. Interfaces later plans rely on

- Phase 3, `tinkero-status`: `tinkero-pam-sync --check` (exit 0 or 1, one line) for the PAM drift report; the `tinkero` package in `build-order.txt` for the release workflow's archive of each release's RPM set.
- Phase 3, the VM smoke test: `docs/guides/phase-2f-vm-check.md` sections 1, 3 and 4 are the automatable part.
- Bump checklist: `ci/gate-session-units` fails on a listed unit upstream renamed or unbound; a new upstream unit is stripped automatically and needs a decision about the list; patch 0011 rebases with the others.

## 11. Planning review record (2026-09-24)

Every task's code in the plan was prototyped and run green, reviewed per task, and applied serially in one copy of `master` at `baec68e`. A final end-to-end review then found, and this design and the plan now carry, these corrections: the base moved to `baec68e` (PR #22), which changed one master-spec sentence Task 7 amends and two test tallies; `rpm -V` skips `%ghost` entries, so both PAM files are plain `%ghost` and the drift signal is `tinkero-pam-sync --check` (D9); `bt-agent` needs `bluez-tools` (D17); the menu's Remove > Fingerprint row is regated on the lock's fingerprint file (D11); spec 4.9's unit sentence and the audit's patch-size sentence are amended; the VM guide takes its baseline before the install, uses a canary key the session never writes, checks the SELinux type rather than the user, scopes its `[Install]` check to the package's files, uses `sudo faillock`, and checks running services' environments; the speaker-tuning check moves to bare metal. Two review points were not taken: `ci/gate-session-units` keeps reading the repository's unit list rather than the payload's copy (the bytes are the same, and the gate runs from the repository); and D13's `make_srpm` registration without `--subdir` stays as designed, since `.copr/Makefile` already routes `spec=tinkero.spec`, and Task 8 is its proof.
