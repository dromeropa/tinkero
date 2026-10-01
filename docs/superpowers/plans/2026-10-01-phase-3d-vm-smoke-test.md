# Phase 3D: VM Smoke Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan runs through the issue loop** (`docs/guides/workflow.md`): dispatched only once Diego has applied `approved`, landed through a PR with green CI, tasks built serially on one branch in the order below. Task 5 is manual, runs on the operator's host, and has its own issue. **No agent session runs the smoke test itself or creates a virtual machine:** an agent runs `tests/test-vm-smoke.sh`, which needs neither libvirt nor a network.

**Goal:** One unattended command, `./dev vm-smoke`, installs the COPR's `tinkero` into a throwaway Fedora VM on the packager's host, drives it through GDM into the Tinkero session and back, types at its lock screen, removes it again, and reports every check of the 2F VM guide's automatable sections as a TAP line, so that a release can cite a passing run.

**Architecture:** Two bash scripts and two data files under `ci/vm-smoke/`. `guest` runs inside the VM: it takes the guide's snapshot, compares two snapshots by the guide's "Reading a diff" rule, runs each stage's assertions as TAP lines, and holds the session controls (which session GDM starts next, waiting for a session, ending one, the lock's state). `run` is the host side: it builds the base VM once from the pinned Fedora Cloud image with cloud-init (`image.lock`, `cloud-init.yaml`), clones it for each run, reaches the clone over the guide's passt port forward, calls the guest script over SSH, sends keys with `virsh send-key`, and renumbers the guest's TAP lines into one `report.tap` in a results directory. Because no agent session has libvirt, the guest's logic is tested against stub commands and the driver in a dry-run mode that prints its host commands; the first real run is this plan's last task, on the operator's host.

**Tech Stack:** bash, libvirt's `virsh`, `virt-install` and `virt-clone` under `qemu:///session`, cloud-init, OpenSSH, `systemd-run --user`, AccountsService over `busctl`, GDM's timed login, TAP, the existing `tests/lib.sh` harness; no Python in this plan.

**Spec:** `docs/superpowers/specs/2026-10-01-phase-3-maintenance-release-design.md` (the Phase 3 design, binding for this plan: section 6 in full, the 3D row of section 7, decisions D17 to D20, and the smoke-test parts of section 9) and `docs/superpowers/specs/2026-09-17-tinkero-design.md` sections 4.6, 4.8, 4.9, 4.11, 8 (item 6 and the GNOME invariant) and 12. The procedure being automated: `docs/guides/phase-2f-vm-check.md`, corrected by the runs #27 and #37. Phase 0: `docs/research/phase-0-findings.md` (environment notes), `docs/guides/phase-0-spike.md` section 2. Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` ("Phase 3: maintenance and release"). Placeholder issue: #11.

## Global Constraints

- Every count and tally in this plan was measured on 2026-10-01 against `master` at `95bb8d4` (upstream tree pinned at `v4.0.4`, `tinkero_rev=2`).
- Phase 3's plans land serially (3A, 3B, 3C, 3D): where a step shows a diff of a file another Phase 3 plan also edits (`.github/workflows/ci.yml`, `dev`, the roadmap, the master spec, `CLAUDE.md`, `README.md`), apply the change to the file as it is then, and read a tally as "N more than before". `tests/test-vm-smoke.sh` computes the expected package from `upstream.lock`, so plan 3A's `tinkero_rev=3` needs no change here.
- Data over code: the image is pinned in `ci/vm-smoke/image.lock` (`key=value`, parsed, never sourced), the base's contents are `ci/vm-smoke/cloud-init.yaml`, the stage list, the names, the timeouts and the key table are variables at the top of `ci/vm-smoke/run`. The locks are parsed with `lock_get`, never sourced.
- Gate allowlists under `ci/allow/` only shrink. This plan adds no allowlist entry and changes nothing in the payload: `tinkero_rev` does not move (design D22).
- Scripts start with `#!/bin/bash` and `set -euo pipefail`, carry a header comment that is their usage text (printed with `sed -n 'A,Bp' "$0"`), and are ShellCheck clean with `-x -e SC1090,SC1091`; no `A && B || C` one-liners (SC2015); `# shellcheck disable=SC2016` above `printf` lines that write a literal `$*` into a stub. New scripts join the ShellCheck step of `.github/workflows/ci.yml`.
- Tests are `tests/test-<area>.sh`, source `tests/lib.sh`, use its helpers and assert on messages, not only on exit codes. They never use the network and never run a real `virsh`, `virt-install`, `virt-clone`, `ssh`, `scp`, `ssh-keygen`, `curl`, `qemu-img`, package manager, `rpm`, `dnf`, `systemctl`, `systemd-run`, `loginctl`, `busctl`, `gsettings`, `dconf`, `sudo`, `faillock`, `ausearch` or `authselect`: each is a stub on a `PATH` the test builds in its temporary directory. `sha256sum`, `cp`, `mv`, `diff`, `cmp`, `awk`, `sed` and `timeout` are the real ones. CI runs the suite as root in a container: the driver's refusal to run as root goes through `TINKERO_EUID`.
- **Test safety.** A test deletes only its own `mktmp` directory, by the house idiom's last line (`rm -rf "$d"; finish`), and nothing else: where a case needs a file to be absent it points the command at another fixture directory (`GHOME`, `GROOT`, `STATE`), it does not delete. No test exports `HOME` or reassigns a variable that a later `rm` expands; the guest gets `HOME="$d/home"` on its own command line and the driver gets `TINKERO_SMOKE_STATE` and `TINKERO_SMOKE_RESULTS` under `$d`, so nothing depends on the caller's `HOME`.
- **Host safety** (the operator reads `ci/vm-smoke/run` with this in mind). Every host path the driver writes derives from two variables set once at its top: `TINKERO_SMOKE_STATE` (default `${XDG_CACHE_HOME:-$HOME/.cache}/tinkero-smoke`) and the results directory (default `.cache/vm-smoke/` in the checkout). Neither script contains `rm`, `rmdir`, `unlink` or `shred`: a stale file is overwritten, never removed. The only thing ever removed is the clone the driver created, through `virsh undefine --nvram --remove-all-storage` on a name that is checked to start with `tinkero-smoke` and not to name a base, and only after `virsh domblklist --details` has shown that every disk of that domain is a file directly under `TINKERO_SMOKE_STATE` (so a domain of that name made by hand, with its disk elsewhere, is refused). The base domain and its disk are never removed by the script, and no disk file the run did not just create is overwritten. Both scripts set `LC_ALL=C` (bash's `[0-9]` admits non-ASCII digits under a UTF-8 locale; sibling plans' reviews found it), `ci/vm-smoke/guest` refuses to run on a machine without the marker file `/etc/tinkero-smoke-vm` that cloud-init writes into the VM, and the values read from `upstream.lock` that reach a command line are validated against a fixed pattern.
- No em dashes in Tinkero's own prose. Attribution trailers on every commit per the session's rules. Land through a PR against the approved issue; never push master. `copr-build` is never triggered by this plan's code issue, and no step of Tasks 1 to 4 starts a virtual machine.
- Each task's PR includes its Deviations line in this plan's "## Deviations" section when anything deviated.

## Issue map

To be filed as two issues superseding the 3D part of placeholder #11 (which is closed, with a comment naming the Phase 3 issues, when the last of them is filed). Tasks 1 to 4 are one orchestrated issue, built serially on one branch because they share `tests/test-vm-smoke.sh`, `ci/vm-smoke/run` and `.github/workflows/ci.yml`, and land as one PR. Task 5 is a manual issue, run by the operator on a host with libvirt, `blocked by` the first and by plan 3A's post-merge issue (the COPR must hold the `tinkero` build the lock names, or the `install` stage fails by design), and closed by hand. The `approved` label is Diego's.

| Task | Size | Area | WHAT | WHERE | HOW TO VERIFY |
|---|---|---|---|---|---|
| 1 The guest script | medium | ci | `ci/vm-smoke/guest`: `snap`, `diff-snap`, `check STAGE` for every stage of design 6.1 as TAP, the steps and the session controls | `ci/vm-smoke/guest`, `tests/test-vm-smoke.sh`, `.github/workflows/ci.yml` | `bash tests/test-vm-smoke.sh` at `1..153`; ShellCheck clean |
| 2 The base image | medium | ci | `ci/vm-smoke/run base`: the SSH key, the pinned image checked by sha256 before use, the rendered user-data, `virt-install --import --cloud-init`; never rebuilt over an existing base, nor over a disk file of its name | `ci/vm-smoke/run`, `ci/vm-smoke/cloud-init.yaml`, `ci/vm-smoke/image.lock`, `tests/test-vm-smoke.sh`, `.github/workflows/ci.yml` | `bash tests/test-vm-smoke.sh` at `1..216` (63 more); the dry run prints the eleven-line sequence |
| 3 The run stages | large | ci | `ci/vm-smoke/run [--stages LIST] [--keep] [--lockout]`: clone, boot, SSH, the eight stages, the key table, `report.tap` and the results directory, exit 0, 1 or 2; `./dev vm-smoke` | `ci/vm-smoke/run`, `dev`, `tests/test-vm-smoke.sh` | `bash tests/test-vm-smoke.sh` at `1..306` (90 more); no `rm` in the dry run's sequence |
| 4 Docs | small | docs | `docs/guides/vm-smoke.md`; the pointer in the 2F guide; master spec 4.7, 7, 8 item 6 and 12 (D17); roadmap; workflow guide; `CLAUDE.md` | `docs/**`, `CLAUDE.md` | `./dev check` green; no em dash added; each quoted string replaced once |
| 5 The first run (manual) | medium | ci | on the operator's host: build the base, run every stage, record `report.tap`, the duration, every correction, and the verdict on the three unproven mechanisms of design 6.5 | none (a record on the issue, one roadmap line, follow-up issues) | every line of `report.tap` recorded; each of the three mechanisms marked worked or fallen back; closed by hand |

After Tasks 1 to 4, `./dev check` runs one more test file, `tests/test-vm-smoke.sh`, at `1..306`; every other file keeps the tally it has when this plan's branch starts (at `95bb8d4`: test-assemble `1..70`, test-branding-render `1..34`, test-branding `1..14`, test-check-rpm `1..16`, test-copr `1..21`, test-fastfetch-fedora `1..3`, test-fetch `1..9`, test-gates `1..94`, test-install `1..34`, test-launch-webapp `1..41`, test-lock `1..4`, test-menu-guards `1..8`, test-pam-sync `1..75`, test-provision `1..189`, test-render-spec `1..25`, test-replacements `1..54`, test-session-end `1..35`, test-specs `1..88`, test-theme-set-browser `1..15`, test-update `1..6`, Python `Ran 45 tests`; plans 3A to 3C move some of these and add their own files). The whole-suite run was not measured at planning time (the planning session ran under a no-delete rule and did not execute tests that delete files); the implementer measures it.

## File Structure

| File | Responsibility |
|---|---|
| `ci/vm-smoke/guest` | the guest side, copied into the VM by the driver: `snap NAME` (the guide's `snap.sh`), `diff-snap A B` ("Reading a diff"), `check STAGE` (TAP), `step NAME` (what a stage does before its checks), the session controls (`session-kind`, `session-next`, `session-wait`, `session-end`, `in-session`) and the lock controls (`lock`, `lock-wait`, `lock-reset`) |
| `ci/vm-smoke/run` | the host side: `base`; the stages `clone`, `baseline`, `install`, `users`, `session`, `lock`, `gnome`, `reinstall`, `remove`; one `run` helper for host commands, one `guest` helper for guest commands; the report and the results directory |
| `ci/vm-smoke/cloud-init.yaml` | the base's user-data, with five placeholders the driver fills: two accounts, the key, sudo without a password for the first account, Workstation's environment group, GDM, the timed login, sshd, the power-off |
| `ci/vm-smoke/image.lock` | the Fedora Cloud Base image: `url`, `sha256`, `size` |
| `tests/test-vm-smoke.sh` | the guest against stubs; the cloud-init file and the image lock by inspection; `run base` and the stages in dry-run mode and against stub `virsh`, `ssh` and `scp` |
| `dev` | `./dev vm-smoke [ARG...]` |
| `docs/guides/vm-smoke.md` | prerequisites and the one-time setup, running and re-running, reading the results, what is written and removed on the host, the fallbacks, what stays manual |

Interfaces later work relies on: `./dev vm-smoke`'s exit status (0, 1, 2) and `report.tap`, which the record named by the `release` workflow's `smoke` input quotes (plan 3B); the bump guide's stage 7, which names the smoke test (plan 3C); the `TINKERO_SMOKE_*` environment, which is the whole configuration of the driver, so that a runner with KVM is one workflow file once software rendering is shown to carry the session (design D17's reversal); the "Stages dropped from the automatic run" table of the guide, which is where a fallback is recorded.

## Review Focus

Failure modes the design implies and does not spell out; each has its tests in the task that owns the code.

1. **The driver on the operator's host must not be able to delete anything it did not create.** Every host path derives from `TINKERO_SMOKE_STATE` or the results directory, both refused when relative or `/`; neither script contains `rm`; a partial download and a rendered `user-data` are overwritten; the clone is removed only through `virsh undefine --nvram --remove-all-storage`, on a name checked before anything runs and again in `remove_clone`; a base that exists is never rebuilt over, a disk file with the base's or the clone's name that no domain owns stops the run instead of being overwritten or removed, and before the clone is undefined `virsh domblklist --details` must show every one of its disks as a file directly under the state directory (a hand-made domain of that name, with its disk elsewhere, is refused with the disk's path and nothing is stopped). Tasks 2 and 3 (the static `rm` greps on both scripts, the dry-run sequence with no `rm`, with the `domblklist` call before the `destroy` and the `undefine`, and no `destroy` or `undefine` of anything but the clone, the refused clone names, the existing-base, the stale base-disk, the stale clone-disk and the foreign-disk cases: outside the state directory, a subdirectory, a sibling directory whose name starts like it, a block device, a second disk elsewhere).
2. **A check that passes by not running.** A guest check that dies half way, an SSH connection that drops, an empty `install.txt`, a stage whose prerequisite never came up: each must be a line that is not ok, never a shorter report. The guest ends every check with its plan line; the driver fails a check that has no plan line or an exit status above 1, and gives every other guest call its own line; a dry run asserts nothing and prints no `ok`. Task 1 (the plan line, the single failure for an empty log) and Task 3 (the check without a plan line, the failing step, exit 2 with `Bail out!` when the VM does not answer).
3. **GNOME's own writes against a leak.** After a Tinkero session the first GNOME login moves the dconf checksum by itself (#27: Ptyxis, Nautilus, the file chooser). The diff must stay clean for those, and must fail for a key under `org/gnome/desktop/interface` in GNOME's own database, for a changed line in any other section, and for `DCONF_PROFILE` left in the user manager or in a running service. Task 1 (the five `diff-snap` cases, the `check gnome` cases).
4. **A stuck lock or a host left on `with-faillock`.** `with-faillock` brings the host's `deny=3`: a failure left on the tally, or a mistyped line, can lock the lock screen for ten minutes, and the stages after `lock` need the session. So the tally is cleared before the switch, the host is put back on `wrapped` whatever the plain rounds did, the switch is never made behind a lock that could not be cleared, and a lock that survives a tally reset and the right password ends the session so that GDM is back. Task 3 (the stuck-lock case) and Task 1 (`check pam-plain` and `check pam-wrapped`).
5. **The wrong build under test.** The COPR keeps earlier builds (#48), and a merged revision may not have been built yet: the run would pass on a package that is not the one being released. The `install` stage compares the PAM file's owner with the package the checkout's lock names, and `hyprland` and `quickshell` must come from the COPR by dnf5's `%{from_repo}`. Task 1 (`check install`'s cases) and Task 3 (the header line of the report carries the expected package).
6. **The test's own traces in the home it tests.** The menu guard canary rewrites the user's seeded `omarchy-menu.jsonc`; if it were not put back byte for byte, the `reinstall` plan and the removal would see a file the "user" changed. It is put back on the failing path too, and the script leaves no other file in a seeded place. And a password that `virsh send-key` cannot type (a capital letter, a symbol) is refused before anything runs. The canary is put back by a trap on `EXIT`, `HUP` and `TERM` (an SSH session the driver times out ends with a TERM), and a check that finds a canary left behind by a killed one puts the file back before it does anything else. Task 1 (the canary's passing and failing cases, the TERM case, the leftover case) and Task 2 (the refused password).
7. **The guest script on the wrong machine, and a tally that reads zero because it was read.** `ci/vm-smoke/guest` removes packages, switches authselect features and ends sessions; it refuses to run (exit 2) without `/etc/tinkero-smoke-vm`, which cloud-init writes into the VM and nothing else does. The faillock tally is read without `sudo`, whose PAM account phase on a `with-faillock` host could clear it first; a snapshot cut short fails the checks of its last two sections instead of passing them as empty. Task 1 (the marker cases for seven subcommands, the `sudo`-free reads, the incomplete snapshot) and Task 2 (the marker in `cloud-init.yaml`, and the guest looking for that very path).

---

### Task 1: The guest script

**Files:**
- Create: `ci/vm-smoke/guest` (mode 0755), `tests/test-vm-smoke.sh`
- Modify: `.github/workflows/ci.yml` (the ShellCheck list)

**Interfaces:**
- Consumes: the 2F guide's `snap.sh` and `insession.sh` and its "Reading a diff" rule (`docs/guides/phase-2f-vm-check.md`, sections 2 to 4 and 6); the messages of `install.sh`, `bin/tinkero-provision` (`conflict<TAB>path` in `--plan`, `conflict: <path> exists and is not Tinkero's; kept.`, `files: N seeded, ...`, `provisioned for <release>`) and `distro/fedora/bin/tinkero-pam-sync` (`current: <variant>`, `<a> installed, <b> needed`, `wrote <variant>`, `wrote tally <user>`); upstream's `omarchy-shell`, `omarchy-menu`, `omarchy-system-lock`, `omarchy-system-logout`, `omarchy-hyprland-session-locked` (exit 0 locked, 1 unlocked), `omarchy-theme-set`, `omarchy-display-text-size`; plan 3A's `tinkero-status` (by name: exit 0 or 1 is a pass).
- Produces: `ci/vm-smoke/guest SUBCOMMAND`, run inside the VM as the test user:

| Subcommand | Does | Exit |
|---|---|---|
| `snap NAME` | writes `snap-NAME.txt` (the guide's ten sections, in its order) and `userdb-NAME.ini`, from inside the session's environment | 0; 1 not written; 2 bad name |
| `diff-snap A B` | "Reading a diff": writes `diff-A-B.txt` and `userdb-diff-A-B.txt`, prints `clean: ...` or `not clean: ...` with the lines | 0 clean; 1 not clean; 2 a snapshot is missing |
| `check STAGE [ARG]` | TAP: `ok N - ...` or `not ok N - ...` with `#   ` detail lines, numbered from 1, `1..N` last. Stages: `baseline`, `install`, `users`, `session`, `power-key`, `lock-failures N`, `lock-clear`, `lock-journal`, `pam-plain`, `pam-wrapped`, `theme`, `gnome NAME`, `reinstall`, `remove` | 0 all ok; 1 any not ok; 2 unknown stage |
| `step NAME` | `baseline` (Dark and the canary key), `linger-on`, `install` and `reinstall` (`install.sh --yes` into `install.txt` or `install-2.txt`, its status into `.rc`), `users` (three dotfiles for the second account), `remove` (the guide's section 6 into `remove.txt`) | the step's; 2 unknown name |
| `session-kind` | prints `tinkero`, `gnome` or `none` | 0 |
| `session-next NAME` | sets the session GDM starts next, in AccountsService | 0; 1 not set; 2 bad name |
| `session-wait NAME [S]` | waits until that session is up and answers (default 180 s) | 0; 1 timeout |
| `session-end WAY` | `menu`, `terminate` or `kill`; records the moment in `cycle-start` | 0; 1; 2 bad way |
| `in-session CMD...` | `systemd-run --user --wait --pipe --quiet --collect -- CMD...` | CMD's |
| `lock`, `lock-wait STATE [S]`, `lock-reset` | lock and wait for the compositor's lock; wait for `unlocked` or `idle`; clear the tally | 0; 1 |

  Files go to `$TINKERO_SMOKE_DIR` (default `~/vmcheck`). Environment: `TINKERO_SMOKE_USER2` (default `smoke2`), `TINKERO_SMOKE_EXPECT_NVR`, `TINKERO_COPR`. Test seams: `TINKERO_SMOKE_ROOT` (a prefix for `/etc`, `/run`, `/usr/share`), `TINKERO_PROC`, `TINKERO_SMOKE_HOME2`, `TINKERO_SMOKE_MARKER` (the marker file, default `/etc/tinkero-smoke-vm`). Every subcommand except the usage text exits 2 with `this script is for the smoke-test VM only` when the marker file is missing: cloud-init writes it into the VM (Task 2), so a copy of the script run on a real machine by mistake does nothing. Task 3's driver calls every one of these.

Two decisions of this task that the design leaves open:

- **"The menu model loads" (design 6.1, spec 8 item 6 "with guards evaluated").** Two calls exist at `v4.0.4` and both are used. `omarchy-menu ping` is `omarchy-shell shell call omarchy.menu ping`: the shell answers `unknown` unless the menu plugin's `Menu.qml` is instantiated (`callIfLoaded` in `shell/shell.qml`), and `Menu.qml` imports the patched `MenuModel.js`, so `ok` proves the model's code loaded. No IPC call returns the guard results (`whenResults` is a QML property without an accessor), so the check makes the evaluation visible instead: it writes one row into the user's menu extension, `~/.config/omarchy/extensions/omarchy-menu.jsonc`, whose `when:` guard is `touch <marker>`, calls `omarchy-menu refresh` (which reloads both menu files; each load ends in `evaluateGuards()`), and waits for the marker. The marker appears only if the model parsed and merged both files and the one bash batch that evaluates every guard, Tinkero's rpm prelude of patch 0010 included, ran as far as that row. The user's file is put back byte for byte on the passing and the failing path, by a trap on `EXIT`, `HUP` and `TERM` when the check is killed (a timed-out SSH session sends a TERM), and, if even the trap did not run (`kill -9`), by the next `check`, which finds `menu-canary.state` still `pending` and restores first; it is a seeded file and the later stages read the provisioning plan. The faillock tally is read as the user, without `sudo`: the tally file is `0660 <user> root`, and sudo's account phase on a `with-faillock` host runs `pam_faillock`, which could clear the tally before it is printed.
- **Where a command runs.** The snapshot, `install.sh`, `tinkero-provision --remove` and everything that asks the shell or Hyprland run through `systemd-run --user --wait --pipe`, so they see what the graphical session put into the user manager's environment (upstream's autostart imports Hyprland's whole environment into it; under GNOME it is what a terminal there has). An SSH shell has no `DBUS_SESSION_BUS_ADDRESS`, and `tinkero-provision` skips the dconf seeding without one. `systemctl --user`, `loginctl`, `rpm`, `faillock` and the files under `/etc` are read directly.

- [ ] **Step 1: Write the failing test**

`tests/test-vm-smoke.sh` (new). Every command the guest calls is a stub in `$d/gbin`, on the guest's `PATH` only, answering from a file under `$d/st`; `good` writes the state of a healthy VM and each case changes one file. The `tinkero-pam-sync` stub is a small model of the real tool (the installed variant follows what the host calls for, with its real messages and the repository's real variant files), and the `omarchy-menu` stub evaluates the canary row's guard on `refresh`. No case deletes a fixture file: a case that needs a file to be absent points the guest at another fixture home or root (`GHOME`, `GROOT`) or marker (`GMARK`); `$d/vm-marker` is the marker file the guest finds by default.

```bash
#!/bin/bash
# The VM smoke test (Phase 3 design, section 6) without a VM. ci/vm-smoke/guest runs against
# stub commands on its own PATH and a fixture home; ci/vm-smoke/run runs in dry-run mode and
# against stub virsh, ssh and scp. Nothing here talks to libvirt, the network or a package
# manager, and nothing is written outside the temporary directory.
source "$(dirname "$0")/lib.sh"
d=$(mktmp)
G=$ROOT/ci/vm-smoke/guest
guide=$ROOT/docs/guides/phase-2f-vm-check.md

# --- the guest script: stubs and fixture -----------------------------------------------------
# Every command the guest calls is a stub in $d/gbin that answers from a file under $d/st, so
# a case changes one file and runs again. The stubs are on the guest's PATH only (helper g).
mkdir -p "$d/gbin" "$d/st" "$d/vm" "$d/run" "$d/proc/4242" "$d/home/.config/dconf" \
  "$d/home/.config/omarchy/extensions" "$d/home/.local/share/keyrings" "$d/home2" \
  "$d/root/etc/pam.d" "$d/root/etc/tmpfiles.d" "$d/root/etc/systemd/system" \
  "$d/root/run/faillock" "$d/root/usr/share/wayland-sessions" "$d/pkg/usr/lib/systemd/user" \
  "$d/root-clean/etc/pam.d" "$d/root-left/etc/pam.d" "$d/home-clean/.config/dconf"
export ST=$d/st GLOG=$d/glog FIXROOT=$d/root VARIANTS=$ROOT/distro/fedora/pam
: > "$d/vm-marker"   # the file cloud-init writes into the smoke-test VM; the guest refuses to run without it
gstub() { cat > "$d/gbin/$1"; chmod +x "$d/gbin/$1"; }
gstub systemd-run <<'S'
#!/bin/bash
echo "systemd-run $*" >> "$GLOG"
while (($#)) && [[ $1 != -- ]]; do shift; done
shift; exec "$@"
S
gstub systemctl <<'S'
#!/bin/bash
case "$*" in
  "--user show-environment") cat "$ST/env" ;;
  "--user list-units --type=service --state=running --no-legend --plain") cat "$ST/running" ;;
  "--user show -p MainPID --value "*) echo 4242 ;;
  "--user list-units --state=active --no-legend omarchy-* tinkero-* bt-agent.service") cat "$ST/tinkero-units" ;;
  "--user list-units --no-legend --state=active wayland-wm@*.service") cat "$ST/wm" ;;
  "--user is-active --quiet graphical-session.target") exit 0 ;;
  "--user is-active "*) if grep -qx -- "${*: -1}" "$ST/inactive"; then echo inactive; exit 3; fi; echo active ;;
  "--user cat omarchy-fcitx5.service") cat "$ST/fcitx5-cat" ;;
  *) echo "systemctl stub: $*" >&2; exit 1 ;;
esac
S
gstub pgrep <<'S'
#!/bin/bash
case "${*: -1}" in
  Hyprland) [[ $(cat "$ST/session") == tinkero ]] ;;
  gnome-shell) [[ $(cat "$ST/session") == gnome ]] ;;
  *) exit 1 ;;
esac
S
gstub pkill <<'S'
#!/bin/bash
echo "pkill $*" >> "$GLOG"
S
gstub loginctl <<'S'
#!/bin/bash
echo "loginctl $*" >> "$GLOG"
case "$1" in
  list-sessions) cat "$ST/sessions" ;;
  show-session) sed -n "s/^$2 $4=//p" "$ST/session-props" ;;
  show-user) cat "$ST/linger" ;;
esac
S
gstub busctl <<'S'
#!/bin/bash
echo "busctl $*" >> "$GLOG"
case "$*" in
  *FindUserByName*) cat "$ST/accounts-user" ;;
  *SetSession*) echo "${*: -1}" > "$ST/next" ;;
  *get-property*) echo "s \"$(cat "$ST/next")\"" ;;
esac
S
gstub sudo <<'S'
#!/bin/bash
echo "sudo $*" >> "$GLOG"
if [[ $1 == -u ]]; then shift 4; HOME=$TINKERO_SMOKE_HOME2 exec "$@"; fi
exec "$@"
S
gstub gsettings <<'S'
#!/bin/bash
echo "gsettings[${DCONF_PROFILE:-user}] $*" >> "$GLOG"
case "$1" in
  list-recursively) cat "$ST/interface" ;;
  get) sed -n "s/^${DCONF_PROFILE:-user} $3 //p" "$ST/gsettings" ;;
esac
S
gstub dconf <<'S'
#!/bin/bash
[[ $(cat "$DCONF_PROFILE") == user-db:user ]] || { echo "dconf stub: wrong profile" >&2; exit 1; }
cat "$ST/userdb"
S
gstub xdg-settings <<'S'
#!/bin/bash
echo org.mozilla.firefox.desktop
S
gstub xdg-mime <<'S'
#!/bin/bash
echo org.gnome.Geary.desktop
S
gstub xdg-user-dir <<'S'
#!/bin/bash
echo "$HOME/$1"
S
gstub getenforce <<'S'
#!/bin/bash
cat "$ST/enforce"
S
gstub authselect <<'S'
#!/bin/bash
echo "authselect $*" >> "$GLOG"
case "$1" in
  current) cat "$ST/authselect" ;;
  enable-feature) echo plain > "$ST/pam-want" ;;
  disable-feature) echo wrapped > "$ST/pam-want" ;;
esac
S
gstub rpm <<'S'
#!/bin/bash
case "$*" in
  "-q tinkero") if [[ $(cat "$ST/installed") == yes ]]; then cat "$ST/nvr"; else echo "package tinkero is not installed"; exit 1; fi ;;
  "-qf "*) cat "$ST/owner" ;;
  "-ql tinkero") cat "$ST/files" ;;
  "-q tinkero hyprland quickshell uwsm") cat "$ST/nvr"; echo hyprland-0.56.2-1.fc44.x86_64; echo quickshell-0.3.0^20.git28771c7-2.fc44.x86_64; echo uwsm-0.26.5-1.fc44.noarch ;;
  "-q hyprland") echo "package hyprland is not installed"; exit 1 ;;
  *) echo "rpm stub: $*" >&2; exit 1 ;;
esac
S
gstub dnf <<'S'
#!/bin/bash
echo "dnf $*" >> "$GLOG"
case "$1" in
  repoquery) cat "$ST/from-repo" ;;
  remove) echo no > "$ST/installed"; echo "Removing: tinkero" ;;
  copr) echo "Copr repository removed" ;;
esac
S
# A small model of tinkero-pam-sync: the installed variant follows what the host calls for.
gstub tinkero-pam-sync <<'S'
#!/bin/bash
echo "tinkero-pam-sync $*" >> "$GLOG"
want=$(cat "$ST/pam-want"); have=$(cat "$ST/pam-installed")
case "${1:-}" in
  --variant) echo "$want" ;;
  --check) if [[ $have == "$want" ]]; then echo "current: $want"; else echo "$have installed, $want needed"; exit 1; fi ;;
  "") if [[ $have == "$want" ]]; then echo "current: $want"; else
        echo "$want" > "$ST/pam-installed"; cat "$VARIANTS/omarchy-lock-password.$want" > "$FIXROOT/etc/pam.d/omarchy-lock-password"; echo "wrote $want"; fi ;;
esac
S
gstub tinkero-provision <<'S'
#!/bin/bash
echo "tinkero-provision[$HOME] $*" >> "$GLOG"
case "$1" in
  --plan) if [[ -n $(find "$HOME/.config" -type f 2>/dev/null) ]]; then cat "$ST/plan-conflict"; else cat "$ST/plan-fresh"; fi ;;
  --yes) if [[ $(cat "$ST/clobber") == yes ]]; then echo clobbered > "$HOME/.config/foot/foot.ini"; fi
         echo "[[ x ]] && source /usr/share/omarchy/default/bash/rc  # tinkero-provision" >> "$HOME/.bashrc"
         cat "$ST/provision-out" ;;
  --remove) echo "tinkero-provision: removed the files Tinkero wrote and you did not change, the skill links, the bashrc line and the session's dconf database" ;;
esac
S
gstub tinkero-status <<'S'
#!/bin/bash
echo "tinkero-status: Tinkero v4.0.4-3 on Fedora 44"
exit "$(cat "$ST/status-rc")"
S
gstub restorecon <<'S'
#!/bin/bash
cat "$ST/restorecon"
S
gstub ls <<'S'
#!/bin/bash
if [[ $1 == -Zd ]]; then echo "$(cat "$ST/label") $2"; else exec /usr/bin/ls "$@"; fi
S
gstub stat <<'S'
#!/bin/bash
if [[ -e ${*: -1} ]]; then cat "$ST/stat"; else echo "stat: cannot statx '${*: -1}'" >&2; exit 1; fi
S
gstub hyprctl <<'S'
#!/bin/bash
case "$*" in
  configerrors) cat "$ST/configerrors" ;;
  "-j layers") cat "$ST/layers" ;;
esac
S
gstub omarchy-shell <<'S'
#!/bin/bash
case "$*" in
  "shell ping") cat "$ST/ping" ;;
  "lock status") cat "$ST/lock-status" ;;
esac
S
# The menu stub evaluates the canary row's guard on refresh, as the real menu's guard batch does.
gstub omarchy-menu <<'S'
#!/bin/bash
echo "omarchy-menu $*" >> "$GLOG"
ext=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
case "$1" in
  ping) cat "$ST/menu-ping" ;;
  refresh) if [[ $(cat "$ST/guards") == term ]]; then echo off > "$ST/guards"; kill -TERM "$PPID"; fi   # a TERM, once, as a timed-out SSH session sends
           if [[ $(cat "$ST/guards") == on ]]; then
             guard=$(sed -n 's/.*"when":"\(touch [^"]*\)".*/\1/p' "$ext"); [[ -z $guard ]] || $guard
           fi; echo ok ;;
esac
S
gstub omarchy-system-lock <<'S'
#!/bin/bash
echo "omarchy-system-lock" >> "$GLOG"
if [[ $(cat "$ST/lock-works") == yes ]]; then echo locked > "$ST/lock"; fi
S
gstub omarchy-hyprland-session-locked <<'S'
#!/bin/bash
case $(cat "$ST/lock") in locked) exit 0 ;; unlocked) exit 1 ;; *) exit 2 ;; esac
S
gstub omarchy-system-logout <<'S'
#!/bin/bash
echo "omarchy-system-logout" >> "$GLOG"
S
gstub omarchy-theme-set <<'S'
#!/bin/bash
echo "omarchy-theme-set[${DCONF_PROFILE:-none}] $*" >> "$GLOG"
exit "$(cat "$ST/theme-rc")"
S
gstub omarchy-display-text-size <<'S'
#!/bin/bash
echo "omarchy-display-text-size $*" >> "$GLOG"
S
gstub systemd-inhibit <<'S'
#!/bin/bash
cat "$ST/inhibit"
S
gstub faillock <<'S'
#!/bin/bash
echo "faillock $*" >> "$GLOG"
case "$*" in *--reset*) ;; *) cat "$ST/faillock" ;; esac
S
gstub ausearch <<'S'
#!/bin/bash
cat "$ST/avc"; exit 1
S
gstub journalctl <<'S'
#!/bin/bash
case "$*" in
  *tinkero-session-end.service*) cat "$ST/session-end-journal" ;;
  *) cat "$ST/journal" ;;
esac
S
gstub sleep <<'S'
#!/bin/bash
exit 0
S

nvr=tinkero-4.0.4-3.fc44.noarch
repo=copr:copr.fedorainfracloud.org:dromero:tinkero
fail2='2026-10-01 10:00:01 SVC   omarchy-lock-password                            V
2026-10-01 10:00:07 SVC   omarchy-lock-password                            V'
# good: the state of a healthy VM. Each case starts from it.
good() {
  : > "$GLOG"
  echo gnome > "$ST/session"; : > "$ST/env"; : > "$ST/tinkero-units"; : > "$ST/inactive"
  printf 'dconf.service\npipewire.service\n' > "$ST/running"; : > "$d/proc/4242/environ"
  echo "wayland-wm@hyprland.desktop.service loaded active running Hyprland" > "$ST/wm"
  printf '# /usr/lib/systemd/user/omarchy-fcitx5.service\n# /usr/lib/systemd/user/omarchy-fcitx5.service.d/tinkero.conf\n' > "$ST/fcitx5-cat"
  printf '3 1000 smoke seat0 tty2\n7 1000 smoke - -\n' > "$ST/sessions"
  printf '3 Name=smoke\n3 Type=wayland\n3 Class=user\n7 Name=smoke\n7 Type=tty\n7 Class=user\n' > "$ST/session-props"
  echo 'o "/org/freedesktop/Accounts/User1000"' > "$ST/accounts-user"; echo gnome > "$ST/next"; echo yes > "$ST/linger"
  printf "org.gnome.desktop.interface clock-show-seconds true\norg.gnome.desktop.interface color-scheme 'prefer-dark'\norg.gnome.desktop.interface cursor-theme 'Adwaita'\norg.gnome.desktop.interface text-scaling-factor 1.0\n" > "$ST/interface"
  printf 'user clock-show-seconds true\nuser text-scaling-factor 1.0\ntinkero clock-show-seconds true\ntinkero text-scaling-factor 1.3636363636363635\n' > "$ST/gsettings"
  printf "[org/gnome/desktop/interface]\nclock-show-seconds=true\ncolor-scheme='prefer-dark'\n" > "$ST/userdb"
  echo Enforcing > "$ST/enforce"
  printf 'Profile ID: local\nEnabled features:\n- with-silent-lastlog\n- with-mdns4\n- with-fingerprint\n' > "$ST/authselect"
  echo yes > "$ST/installed"; echo "$nvr" > "$ST/nvr"; echo "$nvr" > "$ST/owner"; echo no > "$ST/clobber"
  printf 'hyprland %s\nquickshell %s\n' "$repo" "$repo" > "$ST/from-repo"
  echo wrapped > "$ST/pam-want"; echo wrapped > "$ST/pam-installed"
  cat "$VARIANTS/omarchy-lock-password.wrapped" > "$d/root/etc/pam.d/omarchy-lock-password"
  echo "system_u:object_r:etc_t:s0" > "$ST/label"; : > "$ST/restorecon"
  printf '# tinkero (issue #29)\nf /run/faillock/smoke 0660 smoke root -\n' > "$d/root/etc/tmpfiles.d/tinkero-lockout-smoke.conf"
  ln -sfn /usr/lib/systemd/system/gdm.service "$d/root/etc/systemd/system/display-manager.service"
  : > "$d/root/usr/share/wayland-sessions/tinkero.desktop"
  : > "$d/root/run/faillock/smoke"; echo "660 smoke root" > "$ST/stat"
  echo db > "$d/home/.config/dconf/user"; echo db > "$d/home/.config/dconf/tinkero"
  printf '# .bashrc\nalias ll="ls -l"\n' > "$d/home/.bashrc"
  printf '{\n  // Extend the menu.\n}\n' > "$d/home/.config/omarchy/extensions/omarchy-menu.jsonc"
  : > "$ST/configerrors"; echo ok > "$ST/ping"; echo ok > "$ST/menu-ping"; echo on > "$ST/guards"
  echo '{"0x1": {"levels": {"3": [{"namespace": "omarchy-menu"}]}}}' > "$ST/layers"
  echo '{"locked":true,"authenticating":false}' > "$ST/lock-status"; echo unlocked > "$ST/lock"; echo yes > "$ST/lock-works"
  echo 0 > "$ST/theme-rc"; echo 1 > "$ST/status-rc"
  echo "Tinkero 1000 smoke 2345 systemd-inhibit handle-power-key The power key opens the power menu block" > "$ST/inhibit"
  printf 'smoke:\nWhen                Type  Source                                           Valid\n' > "$ST/faillock"
  echo "<no matches>" > "$ST/avc"; echo "Oct 01 10:00:00 quickshell[900]: omarchy lock unlocked" > "$ST/journal"
  echo "Finished tinkero-session-end.service" > "$ST/session-end-journal"
  printf '%s\n' "$d/pkg/usr/lib/systemd/user/omarchy-crash-watch.service" > "$ST/files"; printf '[Unit]\nDescription=x\n' > "$d/pkg/usr/lib/systemd/user/omarchy-crash-watch.service"
  printf 'seed\t.config/alacritty/alacritty.toml\nseed\t.config/foot/foot.ini\nseed\t.config/hypr/hyprland.lua\nseed\t.config/kitty/kitty.conf\nseed\t.local/state/omarchy/preinstalls-removed\n' > "$ST/plan-fresh"
  printf 'conflict\t.config/alacritty/alacritty.toml\nconflict\t.config/foot/foot.ini\nconflict\t.config/hypr/hyprland.lua\nseed\t.config/kitty/kitty.conf\n' > "$ST/plan-conflict"
  {
    for f in alacritty/alacritty.toml foot/foot.ini hypr/hyprland.lua; do
      echo "tinkero-provision: conflict: .config/$f exists and is not Tinkero's; kept. Compare: diff /usr/share/omarchy/config/$f $d/home2/.config/$f"
    done
    echo "tinkero-provision: files: 34 seeded, 0 updated, 0 current, 0 yours, 3 conflicts, 0 moved defaults, 0 orphaned, 0 removed by you, 0 deleted"
    echo "tinkero-provision: provisioned for v4.0.4-3"
  } > "$ST/provision-out"
  {
    echo "install.sh: preflight passed: Fedora 44, x86_64, GDM"
    echo "wrote wrapped"
    echo "current: wrapped"
    echo "wrote tally smoke"
    echo "tinkero-provision: dconf: seeded the session's settings from GNOME's"
    echo "tinkero-provision: provisioned for v4.0.4-3"
    echo "install.sh: done. Log out and choose Tinkero at the GDM login screen."
  } > "$d/vm/install.txt"; echo 0 > "$d/vm/install.rc"
  {
    echo "Nothing to do."
    echo "current: wrapped"
    echo "current: tally smoke"
    printf 'current\t.config/hypr/hyprland.lua\nkeep-user\t.config/foot/foot.ini\n'
    echo "tinkero-provision: files: 0 seeded, 0 updated, 36 current, 1 yours, 0 conflicts, 0 moved defaults, 0 orphaned, 0 removed by you, 0 deleted"
    echo "tinkero-provision: provisioned for v4.0.4-3"
    echo "install.sh: done. Log out and choose Tinkero at the GDM login screen."
  } > "$d/vm/install-2.txt"; echo 0 > "$d/vm/install-2.rc"
}
# g ARG...: run the guest as the test user "smoke"; its output lands in $out, its status in $rc.
# GHOME and GROOT choose another fixture home or root for one call (a home without the session
# database, a root without Tinkero's files): the tests never delete a fixture file.
g() {
  out=$(HOME="${GHOME:-$d/home}" USER=smoke XDG_RUNTIME_DIR="$d/run" TINKERO_SMOKE_DIR="$d/vm" TINKERO_SMOKE_ROOT="${GROOT:-$d/root}" \
    TINKERO_PROC="$d/proc" TINKERO_SMOKE_HOME2="$d/home2" TINKERO_SMOKE_EXPECT_NVR="$nvr" TINKERO_SMOKE_MARKER="${GMARK:-$d/vm-marker}" PATH="$d/gbin:$PATH" bash "$G" "$@" 2>&1) && rc=0 || rc=$?
}
not_oks() { grep -c '^not ok ' <<<"$out"; }

# --- snap: the guide's snap.sh --------------------------------------------------------------
good; g snap 0-baseline
assert_eq "$rc" 0 "snap: exit 0"
assert_eq "$(grep '^## ' "$d/vm/snap-0-baseline.txt")" \
  "$(sed -n '/^# snap\.sh NAME:/,/^# end of snap\.sh$/p' "$guide" | grep -o 'echo "## [^"]*"' | sed 's/^echo "//; s/"$//')" \
  "snap: the sections are the guide's snap.sh's, in its order"
assert_contains "$(cat "$d/vm/snap-0-baseline.txt")" "org.gnome.desktop.interface color-scheme 'prefer-dark'" "snap: the interface keys are in it"
assert_contains "$(cat "$GLOG")" "systemd-run --user --wait --pipe --quiet --collect -- env" "snap: it runs with the session's environment"
assert_eq "$(cat "$d/vm/userdb-0-baseline.ini")" "$(cat "$ST/userdb")" "snap: the user database alone is dumped beside it"
assert_eq "$(sed -n '/^## user env/{n;p}' "$d/vm/snap-0-baseline.txt")" "none" "snap: a clean user manager reads 'none'"
printf 'HOME=/home/smoke\0DCONF_PROFILE=tinkero\0' > "$d/proc/4242/environ"; echo "DCONF_PROFILE=tinkero" > "$ST/env"
g snap leaked
assert_contains "$(cat "$d/vm/snap-leaked.txt")" "dconf.service" "snap: a running service that still sees DCONF_PROFILE is listed"
g snap "../x"; assert_eq "$rc" 2 "snap: a name with a slash is refused"

# --- diff-snap: the guide's "Reading a diff" ----------------------------------------------------
good; g snap 0-baseline; g snap same
g diff-snap 0-baseline same
assert_eq "$rc" 0 "diff-snap: identical snapshots are clean"
assert_contains "$out" "clean: 0-baseline and same are identical" "diff-snap: and it says so"
echo db-after-gnome-wrote > "$d/home/.config/dconf/user"
printf "[org/gnome/Ptyxis]\nwindow-size=(1200, 800)\n\n[org/gnome/desktop/interface]\nclock-show-seconds=true\ncolor-scheme='prefer-dark'\n" > "$ST/userdb"
g snap gnome-wrote; g diff-snap 0-baseline gnome-wrote
assert_eq "$rc" 0 "diff-snap: a moved checksum with only GNOME app state behind it is clean"
assert_contains "$out" "[org/gnome/Ptyxis]" "diff-snap: and names the sections GNOME wrote"
assert_file "$d/vm/diff-0-baseline-gnome-wrote.txt" "diff-snap: the snapshot diff is kept"
assert_file "$d/vm/userdb-diff-0-baseline-gnome-wrote.txt" "diff-snap: the user-db diff is kept"
printf "[org/gnome/desktop/interface]\nclock-show-seconds=true\ncolor-scheme='prefer-dark'\ntext-scaling-factor=1.3636363636363635\n" > "$ST/userdb"
g snap leak-db; g diff-snap 0-baseline leak-db
assert_eq "$rc" 1 "diff-snap: a key under org/gnome/desktop/interface in GNOME's database is not clean"
assert_contains "$out" "not clean: [org/gnome/desktop/interface] differs in GNOME's own database" "diff-snap: and names the section"
assert_contains "$out" "text-scaling-factor=1.3636363636363635" "diff-snap: and shows the key"
good; sed -i "s/cursor-theme 'Adwaita'/cursor-theme 'default'/" "$ST/interface"
g snap leak-cursor; g diff-snap 0-baseline leak-cursor
assert_eq "$rc" 1 "diff-snap: a changed interface key (Phase 0's cursor-theme leak) is not clean"
assert_contains "$out" "not clean: a section other than the dconf checksum differs" "diff-snap: and says which rule broke"
assert_contains "$out" "cursor-theme 'default'" "diff-snap: and shows the line"
g diff-snap 0-baseline leaked
assert_eq "$rc" 1 "diff-snap: DCONF_PROFILE left in the user manager is not clean"
g diff-snap 0-baseline nope
assert_eq "$rc" 2 "diff-snap: a missing snapshot is exit 2"
assert_contains "$out" "missing $d/vm/snap-nope.txt" "diff-snap: and names the file"

# --- check baseline -----------------------------------------------------------------------------
good; echo no > "$ST/installed"; g snap 0-baseline; g check baseline
assert_eq "$rc" 0 "check baseline: a stock GNOME host passes"
assert_eq "$(head -n 1 <<<"$out")" "ok 1 - the clone is in a GNOME session" "check: TAP lines are numbered from 1 per invocation"
assert_eq "$(tail -n 1 <<<"$out")" "1..14" "check baseline: 14 assertions, and the plan line comes last"
echo Permissive > "$ST/enforce"; g check baseline
assert_eq "$rc" 1 "check baseline: a permissive host fails"
assert_contains "$out" "not ok 2 - SELinux is enforcing" "check baseline: and the line says which"
assert_contains "$out" "#   expected 'Enforcing', got 'Permissive'" "check: a failure carries a # detail line"
good; echo no > "$ST/installed"; echo "- with-faillock" >> "$ST/authselect"; g check baseline
assert_contains "$out" "not ok 4 - with-faillock is off, as on a stock host" "check baseline: with-faillock already on fails"
good; g check baseline
assert_contains "$out" "not ok 6 - nothing of Tinkero is installed yet" "check baseline: a host with tinkero installed fails"
good; echo no > "$ST/installed"; sed -i '/clock-show-seconds/d' "$ST/interface" "$ST/userdb"; g snap 0-baseline; g check baseline
assert_eq "$(not_oks)" 2 "check baseline: a missing canary fails in the snapshot and in the user database"

# --- step install, check install ------------------------------------------------------------------
good; printf '#!/bin/bash\necho "install.sh: done. Log out and choose Tinkero at the GDM login screen."\n' > "$d/vm/install.sh"
g step install
assert_eq "$rc" 0 "step install: install.sh's status is the step's"
assert_contains "$(cat "$GLOG")" "systemd-run --user --wait --pipe --quiet --collect -- bash $d/vm/install.sh --yes" "step install: install.sh --yes runs with the session's environment"
assert_eq "$(cat "$d/vm/install.rc")" 0 "step install: the exit status is recorded"
printf '#!/bin/bash\necho "install.sh: dnf repoquery failed"; exit 1\n' > "$d/vm/install.sh"; g step reinstall
assert_eq "$rc" 1 "step reinstall: a failing install.sh fails the step"
assert_contains "$(cat "$d/vm/install-2.txt")" "dnf repoquery failed" "step reinstall: the output goes to install-2.txt"
good; g snap 0-baseline; g check install
assert_eq "$rc" 0 "check install: a good install passes"
assert_eq "$(tail -n 1 <<<"$out")" "1..18" "check install: 18 assertions"
assert_contains "$out" "# quickshell-0.3.0^20.git28771c7-2.fc44.x86_64" "check install: the installed versions are recorded as # lines"
echo tinkero-4.0.4-2.fc44.noarch > "$ST/owner"; g check install
assert_contains "$out" "not ok 8 - the lock's PAM file belongs to $nvr" "check install: a build other than the checkout's fails"
good; printf 'hyprland fedora\nquickshell %s\n' "$repo" > "$ST/from-repo"; g check install
assert_contains "$out" "not ok 9 - hyprland is installed from the COPR" "check install: a Hyprland from another repository fails"
good; sed -i '/^wrote wrapped$/d' "$d/vm/install.txt"; echo "wrote wrapped" >> "$d/vm/install.txt"; g check install
assert_contains "$out" "not ok 7 - the PAM lines come in order" "check install: %posttrans's line after install.sh's own fails"
good; echo "unconfined_u:object_r:user_tmp_t:s0" > "$ST/label"; echo "Would relabel" > "$ST/restorecon"; g check install
assert_eq "$(not_oks)" 2 "check install: a wrong SELinux label fails twice (the type, and restorecon)"
good; echo "tinkero-provision: not complete: dconf failed" >> "$d/vm/install.txt"; GHOME=$d/home-clean g check install
assert_eq "$(not_oks)" 2 "check install: an unseeded dconf database fails twice (the log line, the file)"
good; : > "$d/vm/install.txt"; g check install
assert_eq "$(tail -n 1 <<<"$out")" "1..1" "check install: an empty install.txt is the one failure reported"

# --- step users, check users ------------------------------------------------------------------------
good; printf '# .bashrc of smoke2\n' > "$d/home2/.bashrc"
g step users
assert_eq "$rc" 0 "step users: exit 0"
assert_eq "$(wc -l < "$d/vm/users-manifest.tsv")" 3 "step users: three dotfiles are put in place for the second account"
assert_file "$d/home2/.config/foot/foot.ini" "step users: in its own home, through sudo -u"
g check users
assert_eq "$rc" 0 "check users: conflicts reported, files kept"
assert_eq "$(tail -n 1 <<<"$out")" "1..7" "check users: 7 assertions"
assert_eq "$(cat "$d/home2/.config/foot/foot.ini")" "# tinkero-smoke: .config/foot/foot.ini was here before Tinkero" "check users: the file is what the step wrote"
echo yes > "$ST/clobber"; g check users
assert_contains "$out" "not ok 4 - each one is byte for byte what it was" "check users: a provisioning run that overwrites a dotfile fails"
echo no > "$ST/clobber"; printf 'seed\t.config/foot/foot.ini\n' > "$ST/plan-conflict"; g check users
assert_contains "$out" "not ok 1 - tinkero-provision --plan reports each of the 3 pre-existing dotfiles as a conflict" "check users: a plan that would seed over them fails"

# --- check session, check power-key --------------------------------------------------------------------
ext=$d/home/.config/omarchy/extensions/omarchy-menu.jsonc
good; echo tinkero > "$ST/session"; echo "DCONF_PROFILE=tinkero" > "$ST/env"; cp "$ext" "$d/ext.orig"
g check session
assert_eq "$rc" 0 "check session: a healthy Tinkero session passes"
assert_eq "$(tail -n 1 <<<"$out")" "1..17" "check session: 17 assertions"
assert_contains "$out" "- tinkero-status exits 0 or 1 (exit 1)" "check session: tinkero-status exit 1 (something to act on) is a pass"
assert_eq "$(cmp -s "$ext" "$d/ext.orig" && echo same)" same "check session: the user's menu extension is byte for byte what it was"
assert_eq "$(find "$d/run" -name 'tinkero-smoke-guard.*' | wc -l)" 1 "check session: the canary guard ran (its marker is in the runtime directory)"
echo off > "$ST/guards"; g check session
assert_contains "$out" "not ok 6 - the menu model loads with its guards evaluated" "check session: a menu whose guards never run fails"
assert_eq "$(cmp -s "$ext" "$d/ext.orig" && echo same)" same "check session: and the extension file is still put back"
good; echo tinkero > "$ST/session"; echo "DCONF_PROFILE=tinkero" > "$ST/env"; echo term > "$ST/guards"; g check session
assert_eq "$rc" 143 "check session: a TERM while the canary is in place ends the check"
assert_eq "$(cmp -s "$ext" "$d/ext.orig" && echo same)" same "check session: and the trap puts the user's menu extension back"
assert_eq "$(cat "$d/vm/menu-canary.state")" restored "check session: and records that it did"
good; echo tinkero > "$ST/session"; cp "$ext" "$d/ext.orig"; cp "$ext" "$d/vm/menu-extension.orig"; echo pending > "$d/vm/menu-canary.state"
printf '{\n  "tinkero-smoke": {"label":"Tinkero smoke canary","when":"touch /nonexistent"}\n}\n' > "$ext"
g check power-key
assert_eq "$(cmp -s "$ext" "$d/ext.orig" && echo same)" same "check: a canary left behind by a check that was killed is taken out before anything else runs"
assert_contains "$out" "# an earlier check was cut short with the menu canary in place" "check: and the report says so"
printf '# the user added this later\n' >> "$ext"; g check power-key
assert_contains "$(cat "$ext")" "the user added this later" "check: once restored, a later check leaves the user's file alone"
assert_eq "$(grep -c 'cut short' <<<"$out")" 0 "check: and says nothing"
good; echo tinkero > "$ST/session"; echo "DCONF_PROFILE=tinkero" > "$ST/env"; echo 2 > "$ST/status-rc"; g check session
assert_contains "$out" "not ok 17 - tinkero-status exits 0 or 1" "check session: tinkero-status exit 2 (a check failed) fails"
echo 1 > "$ST/status-rc"; echo "omarchy-fcitx5.service" > "$ST/inactive"; g check session
assert_contains "$out" "not ok 10 - omarchy-fcitx5.service is active" "check session: a listed unit that is not active fails"
: > "$ST/inactive"; echo "Config error in file bindings.lua" > "$ST/configerrors"; g check session
assert_contains "$out" "not ok 3 - hyprctl configerrors is empty" "check session: a config error fails"
: > "$ST/configerrors"; printf '[Unit]\n[Install]\nWantedBy=graphical-session.target\n' > "$d/pkg/usr/lib/systemd/user/omarchy-crash-watch.service"; g check session
assert_contains "$out" "not ok 13 - no unit of the package has an [Install] section" "check session: a packaged unit with [Install] fails"
good; echo tinkero > "$ST/session"; : > "$ST/env"; g check session
assert_contains "$out" "not ok 7 - the user manager has DCONF_PROFILE=tinkero" "check session: a session without the profile export fails"
good; echo tinkero > "$ST/session"; echo "DCONF_PROFILE=tinkero" > "$ST/env"; GROOT=$d/root-clean g check session
assert_contains "$out" "not ok 16 - the lock's tally file exists" "check session: no tally file after boot fails (#29)"
good; echo tinkero > "$ST/session"; g check power-key
assert_eq "$rc" 0 "check power-key: the menu layer is up"
assert_contains "$(cat "$GLOG")" "omarchy-menu close" "check power-key: and the menu is closed again"
echo '{"0x1": {"levels": {"3": []}}}' > "$ST/layers"; g check power-key
assert_contains "$out" "not ok 1 - the power key opened the shell's power menu" "check power-key: no menu layer fails"

# --- the lock ------------------------------------------------------------------------------------------
good; echo tinkero > "$ST/session"; g lock
assert_eq "$rc:$out" "0:locked" "lock: locks through omarchy-system-lock and waits for the compositor's lock"
echo no > "$ST/lock-works"; echo unlocked > "$ST/lock"; g lock
assert_eq "$rc" 1 "lock: a lock that never comes up is exit 1"
echo locked > "$ST/lock"; g lock-wait unlocked 4
assert_eq "$rc" 1 "lock-wait unlocked: still locked is exit 1"
g lock-wait idle 4
assert_eq "$rc" 0 "lock-wait idle: locked with no password check in flight"
echo '{"locked":true,"authenticating":true}' > "$ST/lock-status"; g lock-wait idle 4
assert_eq "$rc" 1 "lock-wait idle: a check still in flight is exit 1"
echo unlocked > "$ST/lock"; g lock-wait unlocked 4
assert_eq "$rc" 0 "lock-wait unlocked: the compositor holds no lock"
echo gone > "$ST/lock"; g lock-wait unlocked 4
assert_eq "$rc" 1 "lock-wait unlocked: a compositor that cannot be asked (a session that died) is not an unlock"
good; printf '%s\n' "$fail2" >> "$ST/faillock"; g check lock-failures 2
assert_eq "$rc" 0 "check lock-failures: two failures from omarchy-lock-password"
assert_contains "$(cat "$GLOG")" "faillock --user smoke" "check lock-failures: read with the guide's command"
assert_eq "$(grep -c '^sudo faillock' "$GLOG")" 0 "check lock-failures: without sudo, whose PAM account phase could clear the tally before it is read"
assert_contains "$(cat "$d/vm/lock.txt")" "omarchy-lock-password" "check lock-failures: the tally is kept in lock.txt"
printf '%s\n' "$fail2" >> "$ST/faillock"; g check lock-failures 2
assert_contains "$out" "not ok 1 - faillock shows exactly 2 failures" "check lock-failures: four (a double count) fails"
assert_contains "$out" "expected '2', got '4'" "check lock-failures: and says how many it saw"
g check lock-clear
assert_eq "$rc" 1 "check lock-clear: failures left after an unlock fail"
good; g check lock-clear
assert_eq "$rc" 0 "check lock-clear: an empty tally passes"
assert_eq "$(grep -c '^sudo faillock' "$GLOG")" 0 "check lock-clear: read without sudo too"
g check lock-journal
assert_eq "$rc" 0 "check lock-journal: a clean journal and no AVC"
echo "PAM unable to dlopen(substack): module is unknown" >> "$ST/journal"; echo 'type=AVC msg=audit(1): avc:  denied  { read } comm="quickshell"' > "$ST/avc"
g check lock-journal
assert_eq "$(not_oks)" 2 "check lock-journal: #46's journal line and an AVC denial both fail"
assert_contains "$out" 'comm="quickshell"' "check lock-journal: the denial is shown"
good; g lock-reset
assert_contains "$(cat "$GLOG")" "sudo faillock --user smoke --reset" "lock-reset: clears the tally (the guide's escape hatch)"
good; g check pam-plain
assert_eq "$rc" 0 "check pam-plain: the sync follows with-faillock"
assert_eq "$(tail -n 1 <<<"$out")" "1..5" "check pam-plain: 5 assertions"
assert_eq "$(grep -c pam_faillock <(grep -v '^#' "$d/root/etc/pam.d/omarchy-lock-password"))" 0 "check pam-plain: the installed file is the plain variant"
assert_contains "$(cat "$GLOG")" "faillock --user smoke --reset" "check pam-plain: the tally is cleared before the host's deny=3 applies"
g check pam-wrapped
assert_eq "$rc" 0 "check pam-wrapped: back to the stock host"
assert_contains "$out" "ok 2 - sudo tinkero-pam-sync is back on wrapped" "check pam-wrapped: wrote wrapped"

# --- check theme, check gnome ---------------------------------------------------------------------------
good; echo tinkero > "$ST/session"; echo "DCONF_PROFILE=tinkero" > "$ST/env"
printf 'user clock-show-seconds true\nuser text-scaling-factor 1.3636363636363635\n' > "$ST/gsettings"; g check theme
assert_eq "$rc" 0 "check theme: two theme switches and a text size"
assert_eq "$(grep -c '^omarchy-theme-set' "$GLOG")" 2 "check theme: tokyo-night, then catppuccin-latte"
assert_contains "$(cat "$GLOG")" "omarchy-display-text-size 16" "check theme: and Phase 0's second leak, the text size"
echo 1 > "$ST/theme-rc"; g check theme
assert_eq "$(not_oks)" 2 "check theme: a failing theme switch fails"
good; g snap 1-menu-logout; g session-end terminate; g check gnome 1-menu-logout
assert_eq "$rc" 0 "check gnome: a clean GNOME login after a Tinkero session"
assert_eq "$(tail -n 1 <<<"$out")" "1..8" "check gnome: 8 assertions"
assert_contains "$(cat "$GLOG")" "gsettings[tinkero] get org.gnome.desktop.interface text-scaling-factor" "check gnome: Tinkero's own database is read through its profile"
echo "-- No entries --" > "$ST/session-end-journal"; g check gnome 1-menu-logout
assert_contains "$out" "not ok 5 - tinkero-session-end ran at that session end" "check gnome: no session-end run fails (#30)"
g check gnome leaked
assert_contains "$out" "not ok 2 - snapshot leaked: the user manager has no DCONF_PROFILE or OMARCHY_PATH" "check gnome: a leaked profile fails"
assert_contains "$out" "not ok 3 - snapshot leaked: no running user service sees DCONF_PROFILE" "check gnome: and so does a service that kept it"
good; printf 'user text-scaling-factor 1.3636363636363635\ntinkero text-scaling-factor 1.3636363636363635\n' > "$ST/gsettings"; g check gnome 1-menu-logout
assert_contains "$out" "not ok 7 - GNOME's text-scaling-factor is still 1.0" "check gnome: the session's text size in GNOME's database fails"
good; echo no > "$ST/linger"; g check gnome 1-menu-logout
assert_contains "$out" "not ok 8 - lingering is on" "check gnome: a cycle without lingering did not test the hard case, and fails"
good; g snap 1-menu-logout; sed '/^## tinkero units$/,$d' "$d/vm/snap-1-menu-logout.txt" > "$d/vm/snap-short.txt"; g check gnome short
assert_contains "$out" "not ok 4 - snapshot short: no Tinkero unit is active" "check gnome: a snapshot cut short is not an empty section"
assert_contains "$out" "the snapshot is incomplete" "check gnome: and the detail says why"

# --- check reinstall, step remove, check remove ------------------------------------------------------------
good; g check reinstall
assert_eq "$rc" 0 "check reinstall: a second install that changes nothing"
assert_eq "$(tail -n 1 <<<"$out")" "1..8" "check reinstall: 8 assertions"
printf 'seed\t.config/kitty/kitty.conf\n' >> "$d/vm/install-2.txt"; g check reinstall
assert_contains "$out" "not ok 5 - the provisioning plan would write nothing" "check reinstall: a plan with a seed line fails"
good; sed -i 's/files: 0 seeded/files: 2 seeded/; s/^Nothing to do\.$/Installing: tinkero/' "$d/vm/install-2.txt"; g check reinstall
assert_eq "$(not_oks)" 2 "check reinstall: a dnf transaction and a seeding run both fail"
good; g step remove
assert_eq "$rc" 0 "step remove: exit 0"
assert_eq "$(grep -c '^# exit 0: ' "$d/vm/remove.txt")" 4 "step remove: the guide's four commands ran and their status is recorded"
assert_contains "$(cat "$GLOG")" "dnf copr remove -y dromero/tinkero" "step remove: the COPR repository is removed"
GROOT=$d/root-clean GHOME=$d/home-clean g check remove
assert_eq "$rc" 0 "check remove: nothing of Tinkero is left"
assert_eq "$(tail -n 1 <<<"$out")" "1..8" "check remove: 8 assertions"
: > "$d/root-left/etc/pam.d/omarchy-lock-password.rpmsave"; GROOT=$d/root-left g check remove
assert_eq "$(not_oks)" 2 "check remove: a PAM file left behind and a surviving session database both fail"

# --- the session controls -----------------------------------------------------------------------------------
good; g session-kind; assert_eq "$out" gnome "session-kind: gnome-shell of the test user is a GNOME session"
echo tinkero > "$ST/session"; g session-kind; assert_eq "$out" tinkero "session-kind: Hyprland is a Tinkero session"
echo none > "$ST/session"; g session-kind; assert_eq "$out" none "session-kind: neither is none"
good; g session-next tinkero
assert_eq "$rc:$out" "0:next session: tinkero" "session-next: sets the session through AccountsService"
assert_contains "$(cat "$GLOG")" "busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User1000 org.freedesktop.Accounts.User SetSession s tinkero" "session-next: SetSession on the user's object, as root"
g session-next kde; assert_eq "$rc" 2 "session-next: only tinkero and gnome"
: > "$ST/accounts-user"; g session-next gnome
assert_eq "$rc" 1 "session-next: an account AccountsService does not know is exit 1"
good; g session-wait gnome 4
assert_eq "$rc:$out" "0:session up: gnome" "session-wait: the GNOME session answers"
g session-wait tinkero 4
assert_eq "$rc" 1 "session-wait: the wrong session is a timeout"
assert_contains "$out" "no tinkero session after 4s (running: gnome)" "session-wait: and says what is running"
echo tinkero > "$ST/session"; echo "not ready" > "$ST/ping"; g session-wait tinkero 4
assert_eq "$rc" 1 "session-wait: a Tinkero session whose shell does not answer is not up"
good; echo tinkero > "$ST/session"; g session-end menu
assert_contains "$(cat "$GLOG")" "omarchy-system-logout" "session-end menu: the menu's logout command"
: > "$GLOG"; g session-end terminate
assert_contains "$(cat "$GLOG")" "loginctl terminate-session 3" "session-end terminate: the graphical session, not the SSH one"
g session-end kill
assert_contains "$(cat "$GLOG")" "pkill -9 -u smoke -x Hyprland" "session-end kill: the compositor is killed"
assert_file "$d/vm/cycle-start" "session-end: the moment is recorded for the journal check"
g session-end nicely; assert_eq "$rc" 2 "session-end: an unknown way is exit 2"
g in-session echo hello; assert_eq "$out" hello "in-session: runs a command through systemd-run --user"

# --- the script itself -----------------------------------------------------------------------------------------
g; assert_eq "$rc" 2 "no subcommand prints usage and exits 2"
assert_contains "$out" "guest check STAGE" "usage: names the subcommands"
g check nope; assert_eq "$rc" 2 "check: an unknown stage is exit 2"
good; codes=""
for c in "snap x" "check baseline" "step remove" "session-next gnome" "lock-reset" "in-session true" "session-end kill"; do read -ra w <<<"$c"; GMARK=$d/no-such-marker g "${w[@]}"; codes+=" $rc"; done
assert_eq "$codes" " 2 2 2 2 2 2 2" "without the smoke-test VM's marker file every subcommand is exit 2"
assert_contains "$out" "this script is for the smoke-test VM only" "and says why"
assert_eq "$(wc -l < "$GLOG")" 0 "and no command was called"
GMARK=$d/no-such-marker g --help; assert_eq "$rc" 0 "the usage text needs no marker"
assert_eq "$(grep -c '^export LC_ALL=C$' "$G")" 1 "the guest fixes the locale: its patterns are byte patterns"
assert_eq "$(grep -v '^[[:space:]]*#' "$G" | grep -cE '(^|[^[:alnum:]_.-])(rm|rmdir|unlink|shred)([[:space:]]|$)')" 0 "the guest script deletes nothing"
rm -rf "$d"; finish
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/test-vm-smoke.sh`
Expected: `1..153`, exit 1, 143 `not ok` (every call fails with `ci/vm-smoke/guest: No such file or directory`; cases 35, 58, 61, 63, 67, 68, 87, 93, 150 and 153 pass without the script: they look at files the test itself wrote, count nothing in a log that is not there, or grep a file that is not there).

- [ ] **Step 3: `ci/vm-smoke/guest`**

Create `ci/vm-smoke/guest` with exactly this content, then `chmod +x ci/vm-smoke/guest`. It contains no `rm`: the one-line dconf profile, the saved copy of the menu extension and its state file are overwritten on the next call, and the guard canary's marker stays in the runtime directory, which the next boot empties.

```bash
#!/bin/bash
# guest: the guest side of the VM smoke test (Phase 3 design, section 6.3). ci/vm-smoke/run
# copies this file into the test VM and calls it over SSH as the test user; it is never packaged.
#
#   guest snap NAME               the GNOME-invariant snapshot (the 2F guide's snap.sh): writes
#                                 snap-NAME.txt and userdb-NAME.ini
#   guest diff-snap A B           compare two snapshots by the guide's "Reading a diff" rule;
#                                 exit 0 clean, 1 not clean, 2 a snapshot is missing
#   guest check STAGE [ARG]       a stage's assertions as TAP lines, numbered from 1, the plan
#                                 line last; exit 0 when every line is ok, 1 otherwise
#   guest step NAME               what a stage does before its checks: baseline, linger-on,
#                                 install, reinstall, users, remove
#   guest session-kind            print tinkero, gnome or none: the test user's graphical session
#   guest session-next NAME       make NAME (tinkero or gnome) the session GDM starts next
#   guest session-wait NAME [S]   wait up to S seconds (default 180) until that session answers
#   guest session-end WAY         end the running session: menu, terminate or kill
#   guest in-session CMD...       run CMD with the graphical session's environment
#   guest lock                    lock the Tinkero session and wait for the compositor's lock
#   guest lock-wait STATE [S]     wait up to S seconds (default 30) until the lock is "unlocked",
#                                 or "idle" (still up, no password check in flight)
#   guest lock-reset              clear the test user's faillock tally (the guide's escape hatch)
#
# Files go to $TINKERO_SMOKE_DIR (default ~/vmcheck). Other environment: TINKERO_SMOKE_USER2
# (the second account, default smoke2), TINKERO_SMOKE_EXPECT_NVR (the tinkero package the
# checkout's lock names), TINKERO_COPR. Seams for tests/test-vm-smoke.sh: TINKERO_SMOKE_ROOT (a
# prefix for /etc, /run and /usr/share), TINKERO_PROC, TINKERO_SMOKE_HOME2, TINKERO_SMOKE_MARKER.
# Every subcommand but the usage text refuses to run (exit 2) unless the marker file
# /etc/tinkero-smoke-vm exists: cloud-init writes it into the smoke-test VM, so a copy of this
# script run by mistake on a real machine does nothing (it would otherwise remove packages, switch
# authselect features and end sessions).
# This script deletes nothing: what it writes it overwrites, and it leaves its files in place.
set -euo pipefail
# The patterns below are byte patterns: under a UTF-8 locale bash's [0-9] admits non-ASCII digits
# (a sibling plan's review found it), so the locale is fixed.
export LC_ALL=C

self=$(readlink -f -- "${BASH_SOURCE[0]}")
dir=${TINKERO_SMOKE_DIR:-$HOME/vmcheck}
root=${TINKERO_SMOKE_ROOT:-}
marker=${TINKERO_SMOKE_MARKER:-/etc/tinkero-smoke-vm}
proc=${TINKERO_PROC:-/proc}
user=${USER:-$(id -un)}
user2=${TINKERO_SMOKE_USER2:-smoke2}
copr=${TINKERO_COPR:-dromero/tinkero}
own_repo="copr:copr.fedorainfracloud.org:${copr//\//:}"
iface=org.gnome.desktop.interface
pam_file=$root/etc/pam.d/omarchy-lock-password
# The dconf sections the Tinkero session writes (omarchy-theme-set-gnome, omarchy-display-text-size
# and Hyprland's cursor all write org.gnome.desktop.interface): a change under one of them in
# GNOME's own database is a leak, whatever else GNOME wrote there itself.
session_sections="org/gnome/desktop/interface"
# The units that are active in a Tinkero session on a VM (guide, section 3): bt-agent needs an
# adapter, the speaker tuning a matching laptop, the monitor recovery its toggle.
active_units="omarchy-crash-watch.service omarchy-sleep-lock.service omarchy-fcitx5.service tinkero-inhibit-power-key.service"
poll=2   # seconds between two looks, in every wait below
T=0; F=0

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "guest: $*" >&2; exit 2; }

# --- TAP -------------------------------------------------------------------------------------
prefixed() {   # PREFIX TEXT: every line of TEXT behind PREFIX
  local l
  while IFS= read -r l; do printf '%s%s\n' "$1" "$l"; done <<<"$2"
}
ok() { T=$((T + 1)); echo "ok $T - $1"; }
not_ok() {   # DESCRIPTION [DETAIL]
  T=$((T + 1)); F=$((F + 1)); echo "not ok $T - $1"
  if [[ -n ${2:-} ]]; then prefixed "#   " "$2"; fi
}
eq() { if [[ $1 == "$2" ]]; then ok "$3"; else not_ok "$3" "expected '$2', got '$1'"; fi; }
has() { if grep -qF -- "$2" <<<"$1"; then ok "$3"; else not_ok "$3" "no '$2' in: $(tail -n 5 <<<"$1")"; fi; }
lacks() { if grep -qF -- "$2" <<<"$1"; then not_ok "$3" "found: $(grep -F -- "$2" <<<"$1" | head -n 5)"; else ok "$3"; fi; }
line() { if grep -qxF -- "$2" <<<"$1"; then ok "$3"; else not_ok "$3" "no line '$2' in: $(tail -n 5 <<<"$1")"; fi; }
note() { prefixed "# " "$1"; }

# --- the session -----------------------------------------------------------------------------
# in_session CMD...: a transient unit of the user manager, so CMD sees what the graphical session
# put into the manager's environment (the bus, WAYLAND_DISPLAY, and in Tinkero DCONF_PROFILE and
# HYPRLAND_INSTANCE_SIGNATURE). An SSH shell has none of it (design 6.3).
in_session() { systemd-run --user --wait --pipe --quiet --collect -- "$@"; }
session_kind() {
  if pgrep -u "$user" -x Hyprland >/dev/null 2>&1; then echo tinkero
  elif pgrep -u "$user" -x gnome-shell >/dev/null 2>&1; then echo gnome
  else echo none; fi
}
session_answers() {   # NAME: the session is far enough up to be asked something
  case $1 in
    tinkero) [[ $(in_session omarchy-shell shell ping 2>/dev/null) == ok ]] ;;
    gnome)   systemctl --user is-active --quiet graphical-session.target && in_session gsettings get "$iface" color-scheme >/dev/null 2>&1 ;;
  esac
}
# graphical_session_id: the test user's wayland or x11 login session (never the SSH one).
graphical_session_id() {
  local id
  while read -r id _; do
    [[ $(loginctl show-session "$id" -p Name --value 2>/dev/null) == "$user" ]] || continue
    [[ $(loginctl show-session "$id" -p Class --value 2>/dev/null) == user ]] || continue
    case $(loginctl show-session "$id" -p Type --value 2>/dev/null) in
      wayland|x11) echo "$id"; return 0 ;;
    esac
  done < <(loginctl list-sessions --no-legend)
  return 1
}
# session-next NAME: AccountsService holds the session GDM starts for a user. Setting it there and
# letting the timed login run enters the session through GDM and uwsm, as a user picking it at the
# greeter does (design 6.3, D20). Root may set it for anyone; the test account's sudo has no prompt.
cmd_session_next() {
  local name=${1:-} path got
  case $name in tinkero|gnome) ;; *) die "session-next: NAME is tinkero or gnome" ;; esac
  path=$(sudo busctl call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts FindUserByName s "$user" | sed -n 's/^o "\(.*\)"$/\1/p')
  [[ -n $path ]] || { echo "AccountsService does not know $user"; return 1; }
  sudo busctl call org.freedesktop.Accounts "$path" org.freedesktop.Accounts.User SetSession s "$name"
  got=$(sudo busctl get-property org.freedesktop.Accounts "$path" org.freedesktop.Accounts.User Session)
  [[ $got == "s \"$name\"" ]] || { echo "AccountsService kept $got, not $name"; return 1; }
  echo "next session: $name"
}
cmd_session_wait() {
  local name=${1:-} secs=${2:-180} i kind=none
  case $name in tinkero|gnome) ;; *) die "session-wait: NAME is tinkero or gnome" ;; esac
  for ((i = 0; i * poll < secs; i++)); do
    kind=$(session_kind)
    if [[ $kind == "$name" ]] && session_answers "$name"; then echo "session up: $name"; return 0; fi
    sleep "$poll"
  done
  echo "no $name session after ${secs}s (running: $kind)"
  return 1
}
# session-end WAY: the guide's three ends (section 4). The moment is recorded so that check gnome
# can ask the journal what ran after it.
cmd_session_end() {
  local way=${1:-} id
  case $way in menu|terminate|kill) ;; *) die "session-end: WAY is menu, terminate or kill" ;; esac
  mkdir -p "$dir"; date +%s > "$dir/cycle-start"
  case $way in
    # The menu's System > Logout row runs this command. It stops uwsm two seconds after it starts,
    # from a background job, so the unit that runs it has to outlive that.
    menu)      systemd-run --user --quiet --collect -- bash -c 'omarchy-system-logout; sleep 10' ;;
    terminate) id=$(graphical_session_id) || { echo "no graphical session to terminate"; return 1; }
               loginctl terminate-session "$id" ;;
    kill)      pkill -9 -u "$user" -x Hyprland ;;
  esac
  echo "session end: $way"
}
# The lock's state is asked of the compositor (upstream's omarchy-hyprland-session-locked: exit 0
# when a session lock is held), not of the shell that draws it; "idle" is the shell's own word that
# no password check is in flight, so the next keys land in an empty field.
lock_is() {
  local st rc=0
  case $1 in
    locked)   in_session omarchy-hyprland-session-locked >/dev/null 2>&1 ;;
    # Exit 1 exactly: 2 is "could not tell" (no compositor to ask), and a session that died is not an unlock.
    unlocked) in_session omarchy-hyprland-session-locked >/dev/null 2>&1 || rc=$?
              ((rc == 1)) ;;
    idle)     st=$(in_session omarchy-shell lock status 2>/dev/null) || return 1
              [[ $st == *'"locked":true'* && $st == *'"authenticating":false'* ]] ;;
  esac
}
lock_wait() {   # STATE SECONDS
  local i
  for ((i = 0; i * poll < $2; i++)); do
    if lock_is "$1"; then return 0; fi
    sleep "$poll"
  done
  return 1
}
cmd_lock() {
  in_session omarchy-system-lock >/dev/null 2>&1 || true
  if lock_wait locked 20; then echo locked; else echo "the lock did not come up"; return 1; fi
}
cmd_lock_wait() {
  local state=${1:-} secs=${2:-30}
  case $state in unlocked|idle) ;; *) die "lock-wait: STATE is unlocked or idle" ;; esac
  if lock_wait "$state" "$secs"; then echo "lock: $state"; else echo "lock: not $state after ${secs}s"; return 1; fi
}

# --- snapshots -------------------------------------------------------------------------------
# snap_body NAME: the guide's snap.sh, section for section, with ~/vmcheck as $dir. Like the
# guide's it stops at nothing: a command that fails leaves its message in the snapshot.
snap_body() {
  local name=$1
  (
    set +e +o pipefail
    {
      echo "## dconf user db"; sha256sum "$HOME/.config/dconf/user"
      echo "## interface"; gsettings list-recursively "$iface"
      echo "## browser"; xdg-settings get default-web-browser
      echo "## mailto"; xdg-mime query default x-scheme-handler/mailto
      echo "## xdg dirs"; for x in DESKTOP DOWNLOAD DOCUMENTS MUSIC PICTURES VIDEOS; do xdg-user-dir "$x"; done
      echo "## keyrings"; ls "$HOME/.local/share/keyrings"
      echo "## bashrc without the guarded line"; grep -v '# tinkero-provision$' "$HOME/.bashrc" | sha256sum
      echo "## user env"; systemctl --user show-environment | grep -E '^(DCONF_PROFILE|OMARCHY_PATH)=' || echo none
      echo "## running user services that see DCONF_PROFILE"
      for u in $(systemctl --user list-units --type=service --state=running --no-legend --plain | awk '{print $1}'); do
        pid=$(systemctl --user show -p MainPID --value "$u")
        if [ "${pid:-0}" -gt 0 ] && tr '\0' '\n' < "$proc/$pid/environ" 2>/dev/null | grep -q '^DCONF_PROFILE='; then echo "$u"; fi
      done
      echo "## tinkero units"; systemctl --user list-units --state=active --no-legend 'omarchy-*' 'tinkero-*' bt-agent.service || true
    } > "$dir/snap-$name.txt" 2>&1
    # The user db alone, through a one-line profile (the same way tinkero-provision seeds, #28):
    # the merged profile would mix in the system databases, which never change here.
    printf 'user-db:user\n' > "$dir/userdb.profile"
    DCONF_PROFILE=$dir/userdb.profile dconf dump / > "$dir/userdb-$name.ini" 2>&1
  )
}
cmd_snap() {
  [[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "snap: NAME is letters, digits, dots and dashes"
  mkdir -p "$dir"
  # From a terminal inside GNOME, as the guide took it: xdg-settings and gsettings answer for the session.
  in_session env TINKERO_SMOKE_DIR="$dir" TINKERO_PROC="$proc" bash "$self" snap-body "$1"
  [[ -s $dir/snap-$1.txt ]] || { echo "snap-$1.txt was not written"; return 1; }
  echo "snapshot $1: $dir/snap-$1.txt and $dir/userdb-$1.ini"
}
# section FILE HEADING: the lines of one "## HEADING" section of a snapshot.
section() { awk -v h="## $2" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$1"; }
# without_checksum FILE: a snapshot with the body of its "## dconf user db" section left out.
without_checksum() { awk '$0 == "## dconf user db" { print; skip = 1; next } /^## / { skip = 0 } !skip' "$1"; }
# ini_section FILE NAME: the keys of one [NAME] section of a dconf dump, sorted.
ini_section() { awk -v h="[$2]" '$0 == h { on = 1; next } /^\[/ { on = 0 } on && NF' "$1" | LC_ALL=C sort; }
# ini_moved A B: the sections whose keys differ between two dconf dumps.
ini_moved() {
  local s
  while IFS= read -r s; do
    [[ $(ini_section "$1" "$s") == "$(ini_section "$2" "$s")" ]] || printf '[%s]\n' "$s"
  done < <(sed -n 's/^\[\(.*\)\]$/\1/p' "$1" "$2" | LC_ALL=C sort -u)
}
# diff-snap A B: the guide's "Reading a diff". Clean means: every section of the two snapshots
# is identical except, possibly, the dconf checksum; and whatever moved that checksum, nothing
# under a section the Tinkero session writes differs between the two dumps of GNOME's database.
cmd_diff_snap() {
  local a=${1:-} b=${2:-} sa sb ua ub f s rc=0 moved
  sa=$dir/snap-$a.txt; sb=$dir/snap-$b.txt; ua=$dir/userdb-$a.ini; ub=$dir/userdb-$b.ini
  for f in "$sa" "$sb" "$ua" "$ub"; do
    [[ -f $f ]] || { echo "missing $f"; return 2; }
  done
  diff "$sa" "$sb" > "$dir/diff-$a-$b.txt" || true
  diff "$ua" "$ub" > "$dir/userdb-diff-$a-$b.txt" || true
  if ! diff <(without_checksum "$sa") <(without_checksum "$sb") > /dev/null; then
    echo "not clean: a section other than the dconf checksum differs between $a and $b:"
    diff <(without_checksum "$sa") <(without_checksum "$sb") || true
    rc=1
  fi
  for s in $session_sections; do
    if [[ $(ini_section "$ua" "$s") != "$(ini_section "$ub" "$s")" ]]; then
      echo "not clean: [$s] differs in GNOME's own database between $a and $b, and the Tinkero session writes there:"
      diff <(ini_section "$ua" "$s") <(ini_section "$ub" "$s") || true
      rc=1
    fi
  done
  if ((rc == 0)); then
    if [[ $(section "$sa" "dconf user db") == "$(section "$sb" "dconf user db")" ]]; then
      echo "clean: $a and $b are identical"
    else
      moved=$(ini_moved "$ua" "$ub" | paste -sd' ')
      echo "clean: only the dconf checksum moved between $a and $b, from GNOME's own writes in: ${moved:-nothing the dump shows}"
    fi
  fi
  return $rc
}

# --- the steps -------------------------------------------------------------------------------
# run_install NAME: the checkout's install.sh, unattended, from inside the GNOME session as a
# user runs it from a terminal there (tinkero-provision seeds dconf over the session bus).
run_install() {
  local rc=0
  in_session bash "$dir/install.sh" --yes > "$dir/$1.txt" 2>&1 || rc=$?
  echo "$rc" > "$dir/$1.rc"
  tail -n 3 "$dir/$1.txt"
  return "$rc"
}
as2() { sudo -u "$user2" -H -- "$@"; }
home2() {
  if [[ -n ${TINKERO_SMOKE_HOME2:-} ]]; then echo "$TINKERO_SMOKE_HOME2"; else getent passwd "$user2" | cut -d: -f6; fi
}
# step_users: give the second account dotfiles of its own at three paths tinkero-provision would
# otherwise seed, taken from its own plan so that no file name is hard-coded here.
step_users() {
  local h plan decision rel n=0
  h=$(home2); [[ -n $h ]] || { echo "no account $user2"; return 1; }
  plan=$(as2 tinkero-provision --plan) || { echo "tinkero-provision --plan failed for $user2"; return 1; }
  : > "$dir/users-manifest.tsv"
  while IFS=$'\t' read -r decision rel; do
    [[ $decision == seed && $rel == .config/* ]] || continue
    as2 mkdir -p -- "$h/$(dirname -- "$rel")"
    printf '# tinkero-smoke: %s was here before Tinkero\n' "$rel" | as2 tee -- "$h/$rel" > /dev/null
    printf '%s\t%s\n' "$(as2 sha256sum -- "$h/$rel" | cut -d' ' -f1)" "$rel" >> "$dir/users-manifest.tsv"
    n=$((n + 1))
    ((n < 3)) || break
  done <<<"$plan"
  ((n == 3)) || { echo "the plan offered $n files under .config to put in place, 3 wanted"; return 1; }
  as2 cat -- "$h/.bashrc" > "$dir/users-bashrc.orig"
  echo "put $n dotfiles in place for $user2"
}
logged() {   # LABEL CMD...: run CMD, then record its exit status under LABEL
  local label=$1 rc=0; shift
  "$@" || rc=$?
  echo "# exit $rc: $label"
}
# step_remove: the guide's section 6, from GNOME.
step_remove() {
  {
    logged "tinkero-provision --remove" in_session tinkero-provision --remove
    logged "dnf remove tinkero" sudo dnf remove -y tinkero
    logged "dnf copr remove $copr" sudo dnf copr remove -y "$copr"
    logged "loginctl disable-linger" loginctl disable-linger "$user"
  } > "$dir/remove.txt" 2>&1
  cat "$dir/remove.txt"
}
cmd_step() {
  mkdir -p "$dir"
  case ${1:-} in
    # Fedora 44's default appearance is Light (Phase 0), so Dark is a value the install must not
    # lose; clock-show-seconds is a key the Tinkero session never writes: the canary for the seeding.
    baseline)  in_session gsettings set "$iface" color-scheme prefer-dark
               in_session gsettings set "$iface" clock-show-seconds true
               echo "baseline: the dark appearance and the canary key are set" ;;
    # Keeps the user manager alive between sessions: the hard case for spec 4.9.
    linger-on) loginctl enable-linger "$user"; echo "lingering is on for $user" ;;
    install)   run_install install ;;
    reinstall) run_install install-2 ;;
    users)     step_users ;;
    remove)    step_remove ;;
    *) die "step: NAME is baseline, linger-on, install, reinstall, users or remove" ;;
  esac
}

# --- the checks ------------------------------------------------------------------------------
# empty_section SNAP HEADING DESCRIPTION: the section is there and has no line. A snapshot cut short
# has no such section, and an absent section is not an empty one.
empty_section() {
  if ! grep -qxF -- "## $2" "$1"; then not_ok "$3" "no '## $2' section in $1: the snapshot is incomplete"; return; fi
  eq "$(section "$1" "$2")" "" "$3"
}
snap_env_checks() {   # NAME: the three sections of a GNOME snapshot that must be empty
  local snap=$dir/snap-$1.txt
  eq "$(section "$snap" "user env")" none "snapshot $1: the user manager has no DCONF_PROFILE or OMARCHY_PATH"
  empty_section "$snap" "running user services that see DCONF_PROFILE" "snapshot $1: no running user service sees DCONF_PROFILE"
  empty_section "$snap" "tinkero units" "snapshot $1: no Tinkero unit is active"
}
check_baseline() {
  local snap=$dir/snap-0-baseline.txt db=$dir/userdb-0-baseline.ini out
  eq "$(session_kind)" gnome "the clone is in a GNOME session"
  eq "$(getenforce 2>&1)" Enforcing "SELinux is enforcing"
  out=$(authselect current 2>&1)
  has "$out" "Profile ID: local" "authselect's profile is local"
  lacks "$out" "with-faillock" "with-faillock is off, as on a stock host"
  eq "$(basename "$(readlink "$root/etc/systemd/system/display-manager.service" 2>/dev/null)")" gdm.service "GDM is the display manager"
  if out=$(rpm -q tinkero 2>&1); then not_ok "nothing of Tinkero is installed yet" "$out"; else ok "nothing of Tinkero is installed yet"; fi
  if [[ ! -f $snap || ! -f $db ]]; then not_ok "snapshot 0-baseline exists" "missing $snap or $db"; return; fi
  out=$(section "$snap" interface)
  line "$out" "$iface color-scheme 'prefer-dark'" "baseline: the dark appearance is set"
  line "$out" "$iface clock-show-seconds true" "baseline: the canary key is set"
  line "$out" "$iface cursor-theme 'Adwaita'" "baseline: GNOME's cursor theme"
  line "$out" "$iface text-scaling-factor 1.0" "baseline: GNOME's text scaling"
  snap_env_checks 0-baseline
  eq "$(ini_section "$db" org/gnome/desktop/interface | grep -cx 'clock-show-seconds=true')" 1 "baseline: the canary is in GNOME's own database"
}
check_install() {
  local log=$dir/install.txt out rc n1 n2 n3 want
  if [[ ! -s $log ]]; then not_ok "install.txt exists and is not empty" "missing or empty: $log"; return; fi
  ok "install.txt exists and is not empty"
  out=$(<"$log")
  eq "$(cat "$dir/install.rc" 2>/dev/null)" 0 "install.sh --yes exits 0"
  has "$out" "Log out and choose Tinkero" "install.sh reaches its closing line"
  has "$out" "tinkero-provision: dconf: seeded the session's settings from GNOME's" "provisioning seeded the session's dconf database (#28)"
  has "$out" "tinkero-provision: provisioned for " "provisioning completed"
  lacks "$out" "not complete" "no provisioning step failed"
  n1=$(grep -n -m1 -F 'wrote wrapped' "$log" | cut -d: -f1)
  n2=$(grep -n -m1 -F 'current: wrapped' "$log" | cut -d: -f1)
  n3=$(grep -n -m1 -F "wrote tally $user" "$log" | cut -d: -f1)
  if [[ -n $n1 && -n $n2 && -n $n3 ]] && ((n1 < n2 && n2 < n3)); then
    ok "the PAM lines come in order: wrote wrapped (%posttrans), current: wrapped, wrote tally $user (#29)"
  else
    not_ok "the PAM lines come in order: wrote wrapped (%posttrans), current: wrapped, wrote tally $user (#29)" "at lines '${n1:-none}', '${n2:-none}', '${n3:-none}'"
  fi
  want=${TINKERO_SMOKE_EXPECT_NVR:-$(rpm -q tinkero 2>&1)}
  eq "$(rpm -qf "$pam_file" 2>&1)" "$want" "the lock's PAM file belongs to $want"
  out=$(dnf repoquery --installed --queryformat '%{name} %{from_repo}\n' hyprland quickshell 2>&1)
  line "$out" "hyprland $own_repo" "hyprland is installed from the COPR (dnf5's %{from_repo})"
  line "$out" "quickshell $own_repo" "quickshell is installed from the COPR"
  eq "$(grep -v '^#' "$pam_file" 2>/dev/null | grep -c substack)" 0 "the PAM file has no substack line (#46)"
  eq "$(grep -cE '^auth[[:space:]]+include[[:space:]]+password-auth$' "$pam_file" 2>/dev/null)" 1 "its auth phase includes password-auth"
  out=$(tinkero-pam-sync --check 2>&1); rc=$?
  eq "$out (exit $rc)" "current: wrapped (exit 0)" "tinkero-pam-sync --check"
  eq "$(tinkero-pam-sync --variant 2>&1)" wrapped "tinkero-pam-sync --variant"
  out=$(ls -Zd "$pam_file" 2>&1)
  if [[ ${out%% *} == *:etc_t:* ]]; then ok "the PAM file's SELinux type is etc_t"; else not_ok "the PAM file's SELinux type is etc_t" "$out"; fi
  eq "$(sudo restorecon -nv "$pam_file" 2>&1)" "" "restorecon would change nothing on it"
  eq "$(tail -n 1 "$root/etc/tmpfiles.d/tinkero-lockout-$user.conf" 2>&1)" "f /run/faillock/$user 0660 $user root -" "the tmpfiles.d entry recreates the lock's tally file (#29)"
  if [[ -f $HOME/.config/dconf/tinkero ]]; then ok "the session's dconf database exists"; else not_ok "the session's dconf database exists" "no $HOME/.config/dconf/tinkero"; fi
  note "$(rpm -q tinkero hyprland quickshell uwsm 2>&1)"
}
check_users() {
  local h plan out rc sum rel n=0 kept=0 conflicts=0 reported=0
  h=$(home2)
  if [[ ! -s $dir/users-manifest.tsv ]]; then not_ok "the second account has dotfiles of its own" "no $dir/users-manifest.tsv: 'guest step users' comes first"; return; fi
  plan=$(as2 tinkero-provision --plan 2>&1)
  out=$(as2 tinkero-provision --yes 2>&1); rc=$?
  printf '%s\n' "$out" > "$dir/users-provision.txt"
  while IFS=$'\t' read -r sum rel; do
    n=$((n + 1))
    if grep -qxF -- "conflict"$'\t'"$rel" <<<"$plan"; then conflicts=$((conflicts + 1)); fi
    if grep -qF -- "conflict: $rel exists and is not Tinkero's; kept." <<<"$out"; then reported=$((reported + 1)); fi
    if [[ $(as2 sha256sum -- "$h/$rel" 2>/dev/null | cut -d' ' -f1) == "$sum" ]]; then kept=$((kept + 1)); fi
  done < "$dir/users-manifest.tsv"
  eq "$conflicts" "$n" "tinkero-provision --plan reports each of the $n pre-existing dotfiles as a conflict"
  eq "$rc" 0 "tinkero-provision --yes exits 0 for the second account"
  eq "$reported" "$n" "the run reports each one as kept"
  eq "$kept" "$n" "each one is byte for byte what it was"
  has "$out" "tinkero-provision: provisioned for " "the second account is provisioned"
  eq "$(as2 grep -c '# tinkero-provision$' "$h/.bashrc" 2>/dev/null)" 1 "its ~/.bashrc gained the one guarded line"
  if as2 grep -v '# tinkero-provision$' "$h/.bashrc" 2>/dev/null | cmp -s - "$dir/users-bashrc.orig"; then
    ok "and is otherwise what it was"
  else
    not_ok "and is otherwise what it was" "compare $h/.bashrc with $dir/users-bashrc.orig"
  fi
}
wait_active() {   # UNIT: its state, after waiting up to 30 s for "active" (tinkero-provision --session starts the list)
  local i st=unknown
  for ((i = 0; i * poll < 30; i++)); do
    st=$(systemctl --user is-active "$1" 2>/dev/null)
    [[ $st != active ]] || break
    sleep "$poll"
  done
  echo "$st"
}
# menu_guards: "the menu model loads with guards evaluated" (spec 8, item 6). The menu runs every
# `when:` guard in one bash batch after each (re)load, and at v4.0.4 no IPC call returns the
# results. So the check adds one row to the user's menu extension whose guard touches a marker
# file: the marker appears only if the model parsed and merged both menu files and the batch,
# Tinkero's rpm prelude included (patch 0010), ran as far as that row. The user's file is put
# back byte for byte: on the way out, by a trap on EXIT, HUP and TERM (an SSH session the driver
# times out ends this way), and, if even that did not run (kill -9), by the next `check`, which
# finds menu-canary.state still saying "pending" and restores first. The guard marker stays in the
# runtime directory, which the next boot empties.
menu_ext=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
restore_menu() {
  if [[ -f $dir/menu-canary.state && $(<"$dir/menu-canary.state") == pending ]]; then
    cat -- "$dir/menu-extension.orig" > "$menu_ext"
    echo restored > "$dir/menu-canary.state"
    in_session omarchy-menu refresh >/dev/null 2>&1 || true
  fi
}
on_signal() { restore_menu; exit "$1"; }
menu_guards() {
  local guard_marker i seen=0
  guard_marker=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tinkero-smoke-guard.$$
  if [[ ! -f $menu_ext ]]; then
    not_ok "the menu model loads with its guards evaluated" "no $menu_ext to add the canary row to (tinkero-provision seeds it)"
    return
  fi
  cat -- "$menu_ext" > "$dir/menu-extension.orig"
  echo pending > "$dir/menu-canary.state"
  trap restore_menu EXIT
  trap 'on_signal 129' HUP
  trap 'on_signal 143' TERM
  printf '{\n  "tinkero-smoke": {"label":"Tinkero smoke canary","when":"touch %s"}\n}\n' "$guard_marker" > "$menu_ext"
  in_session omarchy-menu refresh >/dev/null 2>&1
  for ((i = 0; i * poll < 20; i++)); do
    if [[ -e $guard_marker ]]; then seen=1; break; fi
    sleep "$poll"
  done
  restore_menu
  trap - EXIT HUP TERM
  if ((seen)); then
    ok "the menu model loads with its guards evaluated (a canary guard ran)"
  else
    not_ok "the menu model loads with its guards evaluated" "the canary row's guard never ran: no $guard_marker after 20 s"
  fi
}
check_session() {
  local out rc u
  eq "$(session_kind)" tinkero "the Tinkero session is running"
  if [[ -n $(systemctl --user list-units --no-legend --state=active 'wayland-wm@*.service' 2>/dev/null) ]]; then
    ok "it was started through uwsm (a wayland-wm@ unit is active)"
  else
    not_ok "it was started through uwsm (a wayland-wm@ unit is active)" "no active wayland-wm@*.service in the user manager"
  fi
  out=$(in_session hyprctl configerrors 2>&1); rc=$?
  eq "$rc:$(tr -d '[:space:]' <<<"$out")" "0:" "hyprctl configerrors is empty"
  eq "$(in_session omarchy-shell shell ping 2>&1)" ok "omarchy-shell shell ping answers"
  eq "$(in_session omarchy-menu ping 2>&1)" ok "the menu plugin is loaded (omarchy-menu ping)"
  menu_guards
  eq "$(systemctl --user show-environment | grep '^DCONF_PROFILE=')" "DCONF_PROFILE=tinkero" "the user manager has DCONF_PROFILE=tinkero"
  for u in $active_units; do eq "$(wait_active "$u")" active "$u is active"; done
  out=$(systemctl --user cat omarchy-fcitx5.service 2>&1 | grep '^# /' | tail -n 1)
  if [[ $out == *omarchy-fcitx5.service.d/tinkero.conf ]]; then ok "omarchy-fcitx5 ends with Tinkero's drop-in"; else not_ok "omarchy-fcitx5 ends with Tinkero's drop-in" "$out"; fi
  out=$(rpm -ql tinkero 2>/dev/null | grep '/systemd/user/.*\.service$' | xargs -r grep -l '^\[Install\]' 2>/dev/null)
  eq "$out" "" "no unit of the package has an [Install] section"
  out=$(systemd-inhibit --list --no-legend --no-pager 2>&1 | grep -F Tinkero)
  if [[ $out == *handle-power-key* && $out == *block* ]]; then
    ok "Tinkero holds the handle-power-key inhibitor in block mode"
  else
    not_ok "Tinkero holds the handle-power-key inhibitor in block mode" "${out:-no inhibitor named Tinkero}"
  fi
  eq "$(in_session gsettings get "$iface" clock-show-seconds 2>&1)" true "the session reads its own database, seeded from GNOME's (the canary key)"
  eq "$(stat -c '%a %U %G' "$root/run/faillock/$user" 2>&1)" "660 $user root" "the lock's tally file exists without any root faillock call (#29)"
  in_session tinkero-status > "$dir/status.txt" 2>&1; rc=$?
  if ((rc == 0 || rc == 1)); then
    ok "tinkero-status exits 0 or 1 (exit $rc)"
  else
    not_ok "tinkero-status exits 0 or 1" "exit $rc: $(tail -n 5 "$dir/status.txt")"
  fi
}
# check_power_key: upstream binds XF86PowerOff to `omarchy-menu toggle system`; the menu is a
# layer surface with the namespace omarchy-menu that exists only while the menu is open.
check_power_key() {
  local out
  out=$(in_session hyprctl -j layers 2>&1)
  if grep -q '"namespace": *"omarchy-menu"' <<<"$out"; then
    ok "the power key opened the shell's power menu"
  else
    not_ok "the power key opened the shell's power menu" "no omarchy-menu layer among: $(grep -o '"namespace": *"[^"]*"' <<<"$out" | sort -u | paste -sd' ')"
  fi
  in_session omarchy-menu close >/dev/null 2>&1
}
# tally: the guide's reading of the tally, kept in lock.txt, taken without sudo: the file is the
# user's (tmpfiles.d makes it 0660 user root), and sudo runs PAM's account phase, where a host on
# with-faillock has pam_faillock, which clears the invoking user's tally before faillock prints it
# (a reading of 0 would then mean nothing). Nothing calls it before the first wrong password: a
# root faillock call creates the tally file and would hide #29's first defect.
tally() { faillock --user "$user" 2>&1 | tee -a "$dir/lock.txt"; }
check_lock_failures() {
  local want=${1:-} out
  [[ $want =~ ^[0-9]+$ ]] || die "check lock-failures: a number"
  out=$(tally)
  eq "$(grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' <<<"$out")" "$want" "faillock shows exactly $want failures"
  eq "$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' <<<"$out" | grep -c omarchy-lock-password)" "$want" "all of them from omarchy-lock-password"
}
check_lock_clear() {
  eq "$(tally | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ')" 0 "faillock shows no failures after the unlock: the account phase cleared the tally (#46)"
}
check_lock_journal() {
  local j avc
  j=$(journalctl --user -b --no-pager 2>&1)
  grep -iE 'pam|quickshell' <<<"$j" | tail -n 60 > "$dir/lock-journal.txt"   # the guide's excerpt, kept for a look
  eq "$(grep -ci 'module is unknown' <<<"$j")" 0 "no 'module is unknown' in the user journal (#46)"
  eq "$(grep -ci 'account check' <<<"$j")" 0 "no 'account check' line: the account phase neither refused nor found the password expired"
  avc=$(sudo ausearch -m AVC -ts boot 2>&1)
  printf '%s\n' "$avc" > "$dir/avc.txt"
  has "$avc" "<no matches>" "no AVC denial since boot"
}
# check_pam_plain and check_pam_wrapped run the guide's commands and assert what each prints.
check_pam_plain() {
  local out rc
  # with-faillock brings the host's own deny=3: a failure left on the tally plus two more would lock sudo too.
  sudo faillock --user "$user" --reset >/dev/null 2>&1
  out=$(sudo authselect enable-feature with-faillock 2>&1); rc=$?
  if ((rc == 0)); then ok "authselect enable-feature with-faillock"; else not_ok "authselect enable-feature with-faillock" "exit $rc: $out"; fi
  out=$(tinkero-pam-sync --check 2>&1); rc=$?
  eq "$out (exit $rc)" "wrapped installed, plain needed (exit 1)" "tinkero-pam-sync --check sees the drift"
  eq "$(sudo tinkero-pam-sync 2>&1)" "wrote plain" "sudo tinkero-pam-sync follows the host"
  out=$(tinkero-pam-sync --check 2>&1); rc=$?
  eq "$out (exit $rc)" "current: plain (exit 0)" "tinkero-pam-sync --check is current again"
  eq "$(grep -vE '^[[:space:]]*(#|$)' "$pam_file" 2>&1 | tr -s ' ')" $'auth include password-auth\naccount include password-auth' "the installed file is the two include lines and nothing else"
}
check_pam_wrapped() {
  local out rc
  sudo faillock --user "$user" --reset >/dev/null 2>&1
  out=$(sudo authselect disable-feature with-faillock 2>&1); rc=$?
  if ((rc == 0)); then ok "authselect disable-feature with-faillock"; else not_ok "authselect disable-feature with-faillock" "exit $rc: $out"; fi
  eq "$(sudo tinkero-pam-sync 2>&1)" "wrote wrapped" "sudo tinkero-pam-sync is back on wrapped"
}
# check_theme: what each GNOME cycle does inside Tinkero first (guide, section 4): two theme
# switches, and the text size, which writes text-scaling-factor (Phase 0's second leak).
check_theme() {
  local out rc cmd
  for cmd in "omarchy-theme-set tokyo-night" "omarchy-theme-set catppuccin-latte" "omarchy-display-text-size 16"; do
    # shellcheck disable=SC2086  # a command and its one argument
    out=$(in_session timeout 120 $cmd 2>&1); rc=$?
    if ((rc == 0)); then ok "$cmd"; else not_ok "$cmd" "exit $rc: $(tail -n 5 <<<"$out")"; fi
  done
  out=$(in_session gsettings get "$iface" text-scaling-factor 2>&1)
  if [[ $out == 1.36* ]]; then ok "inside the session text-scaling-factor is 1.3636 (16 px)"; else not_ok "inside the session text-scaling-factor is 1.3636 (16 px)" "$out"; fi
}
check_gnome() {
  local name=${1:-} since out
  eq "$(session_kind)" gnome "GNOME is the running session"
  if [[ ! -f $dir/snap-$name.txt ]]; then not_ok "snapshot $name exists" "missing $dir/snap-$name.txt"; return; fi
  snap_env_checks "$name"
  since=$(cat "$dir/cycle-start" 2>/dev/null || echo 0)
  out=$(journalctl --user -u tinkero-session-end.service --since "@$since" --no-pager -o cat 2>&1)
  printf '%s\n' "$out" > "$dir/session-end-$name.txt"
  if [[ -n $out && $out != *"No entries"* ]]; then
    ok "tinkero-session-end ran at that session end (#30)"
  else
    not_ok "tinkero-session-end ran at that session end (#30)" "the user journal has nothing from tinkero-session-end.service since the session ended"
  fi
  out=$(in_session env DCONF_PROFILE=tinkero gsettings get "$iface" text-scaling-factor 2>&1)
  if [[ $out == 1.36* ]]; then ok "Tinkero's own database kept its text-scaling-factor"; else not_ok "Tinkero's own database kept its text-scaling-factor" "$out"; fi
  eq "$(in_session gsettings get "$iface" text-scaling-factor 2>&1)" 1.0 "GNOME's text-scaling-factor is still 1.0"
  eq "$(loginctl show-user "$user" -p Linger --value 2>&1)" yes "lingering is on: the user manager outlived the Tinkero session (the hard case of spec 4.9)"
}
check_reinstall() {
  local log=$dir/install-2.txt out
  if [[ ! -s $log ]]; then not_ok "install-2.txt exists and is not empty" "missing or empty: $log"; return; fi
  out=$(<"$log")
  eq "$(cat "$dir/install-2.rc" 2>/dev/null)" 0 "the second install.sh --yes exits 0"
  has "$out" "Nothing to do" "dnf has no transaction to run"
  has "$out" "current: wrapped" "the PAM file is current"
  has "$out" "current: tally $user" "the tally entry is current"
  # After the GNOME cycles the terminal configs carry the text size the test set, so they are
  # the user's (keep-user), not current: what must be absent is every decision that writes.
  eq "$(grep -E $'^(seed|update|delete|drop-row|conflict|moved|orphan|mark-removed|skip-removed)\t' "$log")" "" "the provisioning plan would write nothing: every file is current or the user's"
  if grep -q $'^current\t' "$log"; then ok "the plan lists the seeded files as current"; else not_ok "the plan lists the seeded files as current" "no 'current' line in $log"; fi
  if grep -qE 'tinkero-provision: files: 0 seeded, 0 updated, .* 0 deleted$' "$log"; then
    ok "the run seeded, updated and deleted nothing"
  else
    not_ok "the run seeded, updated and deleted nothing" "$(grep -F 'tinkero-provision: files:' "$log")"
  fi
  has "$out" "tinkero-provision: provisioned for " "provisioning completed again"
}
check_remove() {
  local log=$dir/remove.txt out
  if [[ ! -s $log ]]; then not_ok "remove.txt exists and is not empty" "missing or empty: $log ('guest step remove' comes first)"; return; fi
  out=$(<"$log")
  has "$out" "# exit 0: tinkero-provision --remove" "tinkero-provision --remove exits 0"
  has "$out" "removed the files Tinkero wrote" "and says what it removed"
  has "$out" "# exit 0: dnf remove tinkero" "dnf remove tinkero exits 0"
  has "$out" "# exit 0: dnf copr remove" "dnf copr remove exits 0"
  if out=$(rpm -q tinkero 2>&1); then not_ok "the tinkero package is gone" "$out"; else ok "the tinkero package is gone"; fi
  eq "$(find "$root/etc/pam.d" -maxdepth 1 -name '*omarchy*' 2>/dev/null | wc -l)" 0 "no omarchy-lock file is left in /etc/pam.d, .rpmsave included"
  if [[ ! -e $HOME/.config/dconf/tinkero ]]; then ok "the session's dconf database is gone"; else not_ok "the session's dconf database is gone" "still there: $HOME/.config/dconf/tinkero"; fi
  if [[ ! -e $root/usr/share/wayland-sessions/tinkero.desktop ]]; then ok "GDM no longer has a Tinkero session to list"; else not_ok "GDM no longer has a Tinkero session to list" "still there: /usr/share/wayland-sessions/tinkero.desktop"; fi
  # Recorded, not asserted (guide, section 6): dnf5 removes unneeded dependencies by default, and
  # install.sh wrote the tmpfiles.d entry, not the RPM.
  if rpm -q hyprland >/dev/null 2>&1; then note "hyprland is still installed"; else note "dnf removed hyprland with tinkero"; fi
  if [[ -e $root/etc/tmpfiles.d/tinkero-lockout-$user.conf ]]; then note "tinkero-lockout-$user.conf is still in /etc/tmpfiles.d"; else note "tinkero-lockout-$user.conf is gone"; fi
}
# check STAGE: a check never stops at a failing command; each failure is an assertion's business.
cmd_check() {
  local stage=${1:-}
  shift || true
  mkdir -p "$dir"
  set +e
  if [[ -f $dir/menu-canary.state && $(<"$dir/menu-canary.state") == pending ]]; then
    note "an earlier check was cut short with the menu canary in place: putting the user's menu extension back first"
    restore_menu
  fi
  case $stage in
    baseline|install|users|session|power-key|lock-failures|lock-clear|lock-journal|pam-plain|pam-wrapped|theme|gnome|reinstall|remove)
      "check_${stage//-/_}" "$@" ;;
    *) die "check: unknown stage '$stage'" ;;
  esac
  echo "1..$T"
  ((F == 0))
}

cmd=${1:-}
shift || true
case $cmd in
  ""|-h|--help) ;;
  *) [[ -f $marker ]] || die "this script is for the smoke-test VM only: $marker is missing" ;;
esac
case $cmd in
  snap)         cmd_snap "$@" ;;
  snap-body)    snap_body "$@" ;;
  diff-snap)    cmd_diff_snap "$@" ;;
  check)        cmd_check "$@" ;;
  step)         cmd_step "$@" ;;
  session-kind) session_kind ;;
  session-next) cmd_session_next "$@" ;;
  session-wait) cmd_session_wait "$@" ;;
  session-end)  cmd_session_end "$@" ;;
  in-session)   in_session "$@" ;;
  lock)         cmd_lock ;;
  lock-wait)    cmd_lock_wait "$@" ;;
  lock-reset)   sudo faillock --user "$user" --reset; echo "tally reset for $user" ;;
  -h|--help)    usage ;;
  *)            usage >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run the tests**

Run: `bash tests/test-vm-smoke.sh` Expected: `1..153`, no `not ok`, exit 0.

- [ ] **Step 5: CI and ShellCheck**

In `.github/workflows/ci.yml`, add the script to the ShellCheck list (`tests/test-*.sh` is already a glob there):

```diff
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -26,7 +26,7 @@
         run: >
           shellcheck -x -e SC1090,SC1091
           dev build/assemble build/fetch-upstream build/render-spec build/lib.sh
-          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/gate-session-units ci/check-rpm ci/lib-gate.sh
+          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/gate-session-units ci/check-rpm ci/lib-gate.sh ci/vm-smoke/guest
           branding/render-wallpapers branding/inventory-images branding/contact-sheet
           tests/run tests/lib.sh tests/test-*.sh tests/fixtures/make-tree.sh install.sh tests/fixtures/make-payload.sh
           distro/fedora/replacements/* distro/fedora/lib/pkg.sh
```

Run: `shellcheck -x -e SC1090,SC1091 ci/vm-smoke/guest tests/test-vm-smoke.sh` Expected: no output.
Run: `bash -n ci/vm-smoke/guest` Expected: no output.
Run: `./dev check` Expected: green; `# tests/test-vm-smoke.sh` ends with `1..153` and every other file keeps its tally (not measured at planning time: the planning session ran under a no-delete rule and did not execute tests that delete files; the implementer measures it).

- [ ] **Step 6: Commit**

```bash
git add ci/vm-smoke/guest tests/test-vm-smoke.sh .github/workflows/ci.yml
git commit -m "ci: the VM smoke test's guest script: snapshots, the diff rule, the stage checks as TAP (plan 3D)"
```

**Verification for the issue:** `bash tests/test-vm-smoke.sh` at `1..153`; ShellCheck clean on both files; `grep -v '^[[:space:]]*#' ci/vm-smoke/guest | grep -cE '(^|[^[:alnum:]_.-])(rm|rmdir|unlink|shred)([[:space:]]|$)'` prints `0`; CI green.

---

### Task 2: The base image

**Files:**
- Create: `ci/vm-smoke/run` (mode 0755), `ci/vm-smoke/cloud-init.yaml`, `ci/vm-smoke/image.lock`
- Modify: `tests/test-vm-smoke.sh` (a block before its last line), `.github/workflows/ci.yml` (the ShellCheck list)

**Interfaces:**
- Consumes: `upstream.lock` (`fedora`); the 2F guide's VM (8192 MiB, 4 vCPUs, 40 GiB, UEFI, `--video virtio,accel3d=yes --graphics spice,gl.enable=yes,listen=none`, the `rendernode=` of an Optimus host) and its passt port forward (`<backend type='passt'/>`, `<portForward proto='tcp'><range start='2222' to='22'/>`, which the driver binds to `127.0.0.1` with `portForward0.address`); Fedora's `Fedora-Cloud-44-1.7-x86_64-CHECKSUM`.
- Produces: `ci/vm-smoke/run base` (exit 0 built; 2 anything else), which leaves the shut-off domain `tinkero-smoke-base-f<fedora>` and, under `TINKERO_SMOKE_STATE`: `id_ed25519` and `id_ed25519.pub`, the verified image under its own name, `user-data`, `tinkero-smoke-base-f<fedora>.qcow2`. The helpers Task 3 builds on: `run CMD...` (every host command that changes something; prints it in a dry run), `probe DEFAULT CMD...` and `domain_state NAME DEFAULT` (host commands that only ask; a dry run prints them and answers the default), `show`, `lock_get FILE KEY`, `die` (exit 2), `say`. Environment: `TINKERO_SMOKE_DRY_RUN`, `TINKERO_SMOKE_STATE`, `TINKERO_SMOKE_BASE`, `TINKERO_SMOKE_USER`, `TINKERO_SMOKE_PASSWORD`, `TINKERO_SMOKE_USER2`, `TINKERO_SMOKE_PASSWORD2`, `TINKERO_SMOKE_SSH_PORT`, `TINKERO_SMOKE_RENDERNODE`, `TINKERO_SMOKE_URI`; seams `TINKERO_ROOT`, `TINKERO_LOCK`, `TINKERO_SMOKE_IMAGE_LOCK`, `TINKERO_EUID`.

Design 6.2 and D18: the base is Workstation's package set on the Cloud image's disk layout, built without a person. `cloud-init.yaml` is a template: the driver fills `@USER@`, `@PASSWORD@`, `@USER2@`, `@PASSWORD2@` and `@SSH_KEY@`, so that the accounts the stages use and the accounts the base has are one set of variables. Four things in it go beyond the design's list and are needed for it to work: `--allowerasing` on the group install (the Cloud image's `fedora-release-cloud` has to give way to Workstation's release package), `/etc/cloud/cloud-init.disabled` (virt-install's own "disable after first boot" only applies to user-data it generates itself, and a clone must not run cloud-init again), `systemctl set-default graphical.target` (the Cloud image boots to a text console), and a `write_files` entry, `/etc/tinkero-smoke-vm`, the marker file without which `ci/vm-smoke/guest` refuses to run (a copy of it run by mistake on a real machine then does nothing; a hand-built base gets the file by hand).

The image line comes from Fedora's signed CHECKSUM file, fetched by the orchestrator on 2026-10-01: `SHA256 (Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2) = 28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f`, 583729152 bytes.

- [ ] **Step 1: The failing tests**

In `tests/test-vm-smoke.sh`, replace the last line (`rm -rf "$d"; finish`) with this block followed by that same line. The host's tools are stubs in `$d/hbin`; `sha256sum`, `cp` and `mv` are the real ones and work under `$d/state` only; the image lock the driver reads is a fixture whose checksum is the stub download's.

```bash
# --- the base: cloud-init.yaml and image.lock ---------------------------------------------------
R=$ROOT/ci/vm-smoke/run
ci_yaml=$ROOT/ci/vm-smoke/cloud-init.yaml
ilock=$ROOT/ci/vm-smoke/image.lock
assert_eq "$(head -n 1 "$ci_yaml")" "#cloud-config" "cloud-init: the file is a cloud-config"
first=$(sed -n '/name: "@USER@"/,/name: "@USER2@"/p' "$ci_yaml"); second=$(sed -n '/name: "@USER2@"/,/^[a-z_]*:/p' "$ci_yaml")
assert_contains "$first" 'plain_text_passwd: "@PASSWORD@"' "cloud-init: the test account has its known password"
assert_contains "$second" 'plain_text_passwd: "@PASSWORD2@"' "cloud-init: the second account has its own"
assert_eq "$(grep -c 'lock_passwd: false' "$ci_yaml")" 2 "cloud-init: both passwords can be typed at a prompt"
assert_contains "$first" '- "@SSH_KEY@"' "cloud-init: the host's SSH key goes to the test account"
assert_contains "$first" 'sudo: "ALL=(ALL) NOPASSWD:ALL"' "cloud-init: the test account has password-less sudo (D19)"
assert_eq "$(grep -c 'NOPASSWD\|ssh_authorized_keys' <<<"$second")" 0 "cloud-init: the second account has neither sudo nor the key"
assert_contains "$(cat "$ci_yaml")" "dnf -y install --allowerasing @workstation-product-environment" "cloud-init: Workstation's environment group is installed"
assert_contains "$(cat "$ci_yaml")" "systemctl enable gdm.service sshd.service" "cloud-init: GDM and sshd are enabled"
assert_contains "$(cat "$ci_yaml")" "systemctl set-default graphical.target" "cloud-init: the clones boot to GDM"
assert_contains "$(cat "$ci_yaml")" 'TimedLoginEnable=true\nTimedLogin=%s\nTimedLoginDelay=5' "cloud-init: GDM logs the test account in after five seconds (D20)"
assert_eq "$(grep -cx 'package_upgrade: true' "$ci_yaml")" 1 "cloud-init: the base is upgraded"
assert_contains "$(cat "$ci_yaml")" "/etc/cloud/cloud-init.disabled" "cloud-init: it switches itself off for the clones"
assert_contains "$(cat "$ci_yaml")" "path: /etc/tinkero-smoke-vm" "cloud-init: it writes the marker file without which the guest script refuses to run"
assert_contains "$(cat "$G")" 'TINKERO_SMOKE_MARKER:-/etc/tinkero-smoke-vm' "cloud-init: and the guest script looks for that very file"
assert_eq "$(sed -n '/^power_state:/,$p' "$ci_yaml" | grep -c 'mode: poweroff')" 1 "cloud-init: it powers the base off at the end"
assert_eq "$(grep -o '@[A-Z0-9_]*@' "$ci_yaml" | LC_ALL=C sort -u | paste -sd" ")" "@PASSWORD2@ @PASSWORD@ @SSH_KEY@ @USER2@ @USER@" "cloud-init: the five placeholders run base fills, and no other"
url=$(sed -n 's/^url=//p' "$ilock"); fed=$(sed -n 's/^fedora=//p' "$ROOT/upstream.lock")
assert_eq "$url" "https://download.fedoraproject.org/pub/fedora/linux/releases/$fed/Cloud/x86_64/images/${url##*/}" "image.lock: the image is the Cloud image of the lock's Fedora release, over https"
if [[ ${url##*/} =~ ^Fedora-Cloud-Base-Generic-$fed-[0-9.]+\.x86_64\.qcow2$ ]]; then ok "image.lock: it is the Generic qcow2"; else not_ok "image.lock: it is the Generic qcow2" "${url##*/}"; fi
if [[ $(sed -n 's/^sha256=//p' "$ilock") =~ ^[0-9a-f]{64}$ ]]; then ok "image.lock: it carries a sha256"; else not_ok "image.lock: it carries a sha256"; fi

# --- the base: ci/vm-smoke/run base against stub host tools ------------------------------------
# The host's tools are stubs in $d/hbin that log to $HLOG; sha256sum, cp and mv are the real ones
# and work inside $d/state only.
mkdir -p "$d/hbin"; export HLOG=$d/hlog
hstub() { cat > "$d/hbin/$1"; chmod +x "$d/hbin/$1"; }
hstub virsh <<'S'
#!/bin/bash
echo "virsh $*" >> "$HLOG"
case "$3" in
  dominfo) grep -qx -- "$4" "$ST/domains" ;;
  domstate) cat "$ST/domstate" ;;
  domblklist) cat "$ST/blklist" ;;
esac
S
hstub virt-install <<'S'
#!/bin/bash
echo "virt-install $*" >> "$HLOG"
exit "$(cat "$ST/virt-install-rc")"
S
hstub ssh-keygen <<'S'
#!/bin/bash
echo "ssh-keygen $*" >> "$HLOG"
echo "PRIVATE" > "${*: -1}"; echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureKey+With/Slash tinkero-smoke" > "${*: -1}.pub"
S
hstub curl <<'S'
#!/bin/bash
echo "curl $*" >> "$HLOG"
while (($#)); do if [[ $1 == -o ]]; then cat "$ST/download" > "$2"; fi; shift; done
S
hstub qemu-img <<'S'
#!/bin/bash
echo "qemu-img $*" >> "$HLOG"
S
hstub sleep <<'S'
#!/bin/bash
exit 0
S
echo "the cloud image" > "$ST/download"
img=Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
printf 'url=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/%s\nsha256=%s\n' "$img" "$(sha256sum "$ST/download" | cut -d' ' -f1)" > "$d/image.lock"
printf 'url=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/%s\nsha256=%064d\n' "$img" 0 > "$d/image-bad.lock"
hgood() { : > "$HLOG"; : > "$ST/domains"; echo "shut off" > "$ST/domstate"; echo 0 > "$ST/virt-install-rc"; }
# r ARG...: run the driver as an ordinary user with its state and results under $d. STATE picks
# another state directory for one call.
r() {
  out=$(TINKERO_EUID="${EUID_AS:-1000}" TINKERO_SMOKE_STATE="${STATE:-$d/state}" TINKERO_SMOKE_RESULTS="$d/results" \
    TINKERO_SMOKE_IMAGE_LOCK="${ILOCK:-$d/image.lock}" PATH="$d/hbin:$PATH" bash "$R" "$@" 2>&1) && rc=0 || rc=$?
}
s=$d/state-dry
hgood; STATE=$s TINKERO_SMOKE_DRY_RUN=1 r base
assert_eq "$rc" 0 "base, dry run: exit 0"
assert_eq "$out" "virsh -c qemu:///session dominfo tinkero-smoke-base-f44
mkdir -p $s
ssh-keygen -q -t ed25519 -N '' -C tinkero-smoke -f $s/id_ed25519
curl -fL --retry 3 -o $s/$img.part https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/$img
sha256sum -- $s/$img.part
mv -f -- $s/$img.part $s/$img
# write $s/user-data from ci/vm-smoke/cloud-init.yaml
cp --reflink=auto -- $s/$img $s/tinkero-smoke-base-f44.qcow2
qemu-img resize $s/tinkero-smoke-base-f44.qcow2 40G
virt-install --connect qemu:///session --name tinkero-smoke-base-f44 --memory 8192 --vcpus 4 --import --disk path=$s/tinkero-smoke-base-f44.qcow2,format=qcow2,bus=virtio --osinfo detect=on,require=off --boot uefi --network user,model.type=virtio,backend.type=passt,portForward0.proto=tcp,portForward0.address=127.0.0.1,portForward0.range0.start=2222,portForward0.range0.to=22 --video virtio,accel3d=yes --graphics spice,gl.enable=yes,listen=none --cloud-init user-data=$s/user-data --noautoconsole --wait 90
virsh -c qemu:///session domstate tinkero-smoke-base-f44
vm-smoke: the base tinkero-smoke-base-f44 is ready. It is never booted again: every run clones it" "base, dry run: the command sequence, checksum before use"
assert_no_path "$s" "base, dry run: nothing is written"
assert_eq "$(wc -l < "$HLOG")" 0 "base, dry run: nothing is called"
STATE=$s TINKERO_SMOKE_DRY_RUN=1 TINKERO_SMOKE_RENDERNODE=/dev/dri/by-path/pci-0000:00:02.0-render TINKERO_SMOKE_SSH_PORT=2200 r base
assert_contains "$out" "--graphics spice,gl.enable=yes,listen=none,rendernode=/dev/dri/by-path/pci-0000:00:02.0-render" "base: TINKERO_SMOKE_RENDERNODE pins virgl on an Optimus host"
assert_contains "$out" "portForward0.range0.start=2200" "base: TINKERO_SMOKE_SSH_PORT is the forwarded port"
assert_eq "$(grep -c 'portForward0.address=127.0.0.1,portForward0.range0.start' <<<"$out")" 1 "base: the forward is bound to 127.0.0.1, not to every address of the host"

hgood; r base
assert_eq "$rc" 0 "base: builds against the stubs"
assert_contains "$out" "the base tinkero-smoke-base-f44 is ready" "base: and says so"
ud=$(cat "$d/state/user-data")
assert_eq "$(grep -cE "@[A-Z0-9_]+@" <<<"$ud")" 0 "base: the rendered user-data has no placeholder left"
assert_contains "$ud" '      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureKey+With/Slash tinkero-smoke"' "base: the generated public key is in it"
assert_contains "$ud" 'plain_text_passwd: "tinkero1"' "base: and the test account's password"
assert_contains "$ud" '"smoke" > /etc/gdm/custom.conf' "base: and the timed login's account"
assert_eq "$(grep -c '^ssh-keygen ' "$HLOG")" 1 "base: the SSH key is generated once, under the state directory"
assert_eq "$(cat "$d/state/tinkero-smoke-base-f44.qcow2")" "the cloud image" "base: the base disk is a copy of the verified image"
assert_contains "$(cat "$HLOG")" "--cloud-init user-data=$d/state/user-data --noautoconsole --wait 90" "base: virt-install gets the rendered user-data and waits for the power-off"
echo "somebody's disk" > "$d/state/tinkero-smoke-base-f44.qcow2"; hgood; r base
assert_eq "$rc" 2 "base: a disk file with the base's name and no domain owning it stops the run"
assert_contains "$out" "This script overwrites nothing it did not just create" "base: and the operator is told to move that file aside"
assert_eq "$(grep -vc '^virsh -c qemu:///session dominfo ' "$HLOG")" 0 "base: nothing but the question was asked"
assert_eq "$(cat "$d/state/tinkero-smoke-base-f44.qcow2")" "somebody's disk" "base: and the file is what it was"
s2=$d/state2; mkdir -p "$s2"; cp "$d/state/id_ed25519" "$d/state/id_ed25519.pub" "$d/state/$img" "$s2/"
hgood; STATE=$s2 r base
assert_eq "$rc:$(grep -c '^curl \|^ssh-keygen ' "$HLOG")" "0:0" "base: a cached image that verifies and an existing key are reused"
s3=$d/state3; mkdir -p "$s3"; cp "$d/state/id_ed25519" "$d/state/id_ed25519.pub" "$s3/"; echo "tampered" > "$s3/$img"
hgood; STATE=$s3 r base
assert_eq "$rc:$(grep -c '^curl ' "$HLOG")" "0:1" "base: a cached image that fails the checksum is downloaded again"
assert_eq "$(cat "$s3/$img")" "the cloud image" "base: and overwritten, not removed"
hgood; STATE=$d/state-bad ILOCK=$d/image-bad.lock r base
assert_eq "$rc" 2 "base: a download that fails the checksum is exit 2"
assert_contains "$out" "checksum mismatch" "base: and says so"
assert_eq "$(grep -c '^virt-install \|^qemu-img ' "$HLOG")" 0 "base: and nothing is built from it"
assert_no_path "$d/state-bad/$img" "base: the unverified download never gets the image's name"
hgood; echo tinkero-smoke-base-f44 > "$ST/domains"; r base
assert_eq "$rc" 2 "base: an existing base is refused"
assert_contains "$out" "already exists. This script never removes it" "base: and the message says who removes it"
assert_eq "$(grep -vc '^virsh -c qemu:///session dominfo ' "$HLOG")" 0 "base: nothing but the question was asked"
hgood; echo 1 > "$ST/virt-install-rc"; STATE=$d/state-vi1 r base
assert_eq "$rc" 2 "base: a failing virt-install is exit 2"
assert_contains "$out" "virt-viewer --connect qemu:///session --attach tinkero-smoke-base-f44" "base: and says how to look at it"
hgood; echo running > "$ST/domstate"; STATE=$d/state-vi2 r base
assert_eq "$rc" 2 "base: a base that is not shut off afterwards is exit 2"
hgood; EUID_AS=0 r base
assert_eq "$rc" 2 "root is refused (through TINKERO_EUID)"
assert_contains "$out" "run as your own user" "and told why"
hgood; TINKERO_SMOKE_PASSWORD=Tinkero1 r base
assert_eq "$rc" 2 "a password with a capital letter is refused"
assert_contains "$out" "lower-case letters and digits" "since virsh send-key types one key per character"
hgood; TINKERO_SMOKE_BASE=tinkero-spike-clean-f44 r base
assert_eq "$rc" 2 "base: refuses to build a base that TINKERO_SMOKE_BASE says was built by hand"
printf 'fedora=44; touch x\n' > "$d/bad-fedora.lock"; hgood; TINKERO_LOCK=$d/bad-fedora.lock r base
assert_eq "$rc" 2 "a lock whose fedora value is not a number is refused"
assert_contains "$out" "fedora must be a number" "and the message says so"
hgood; STATE=relative/path r base
assert_eq "$rc" 2 "a relative TINKERO_SMOKE_STATE is refused"
assert_eq "$(grep -c '^export LC_ALL=C$' "$R")" 1 "the driver fixes the locale: its patterns are byte patterns"
assert_eq "$(grep -v '^[[:space:]]*#' "$R" | grep -cE '(^|[^[:alnum:]_.-])(rm|rmdir|unlink|shred)([[:space:]]|$)')" 0 "the driver has no rm, rmdir, unlink or shred"
```

Run: `bash tests/test-vm-smoke.sh` Expected: `1..216`, exit 1, 53 `not ok`, all among the 63 new cases (153 was the tally before; ten of the new cases pass without the files: they count lines in a log that is empty, look for a path that is not there, or look in the guest script for a path the new files are meant to match).

- [ ] **Step 2: The two data files**

`ci/vm-smoke/image.lock`:

```ini
# ci/vm-smoke/image.lock: the Fedora Cloud Base image the smoke test's base VM is built from
# (Phase 3 design, section 6.2). key=value, parsed, never sourced. `ci/vm-smoke/run base`
# downloads url into TINKERO_SMOKE_STATE and uses no file whose sha256 differs.
# The values are the Generic qcow2 line of Fedora's Fedora-Cloud-44-1.7-x86_64-CHECKSUM (signed
# with the Fedora 44 key), read on 2026-10-01. When upstream.lock's fedora moves, take the new
# release's line from its own CHECKSUM file; tests/test-vm-smoke.sh fails until the two agree.
url=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
sha256=28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f
size=583729152
```

`ci/vm-smoke/cloud-init.yaml`:

```yaml
#cloud-config
# ci/vm-smoke/cloud-init.yaml: the user-data that turns Fedora's Cloud Base image into the smoke
# test's base VM (Phase 3 design 6.2, decisions D18 to D20). `ci/vm-smoke/run base` fills the five
# placeholders and hands the result to virt-install --cloud-init. What the stages rely on:
#   - two accounts with known passwords of lower-case letters and digits (virsh send-key types
#     the first one at the lock screen, one key per character);
#   - the host's SSH key, and sudo without a password, for the first account only: install.sh
#     calls sudo and nothing can answer its prompt (D19). The lock screen and polkit do not read
#     sudoers, so the PAM rounds are what they are on a stock host;
#   - Workstation's package set on the Cloud image's disk layout (D18), GDM as the display
#     manager with a five-second timed login of the first account (GDM starts every session of a
#     run, D20), and sshd;
#   - an upgraded system, cloud-init switched off for the clones, and a power-off at the end,
#     which is what virt-install --wait waits for;
#   - /etc/tinkero-smoke-vm, the marker file without which ci/vm-smoke/guest refuses to run, so
#     that a copy of it run on a real machine by mistake does nothing.
hostname: tinkero-smoke
users:
  - name: "@USER@"
    gecos: Tinkero smoke test
    groups: [wheel]
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "@PASSWORD@"
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - "@SSH_KEY@"
  - name: "@USER2@"
    gecos: Tinkero smoke test, the account with dotfiles of its own
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "@PASSWORD2@"
ssh_pwauth: false
write_files:
  - path: /etc/tinkero-smoke-vm
    content: |
      This is the Tinkero smoke-test VM (ci/vm-smoke/cloud-init.yaml).
      ci/vm-smoke/guest runs only where this file exists.
package_update: true
package_upgrade: true
runcmd:
  - |
    set -eux
    # --allowerasing: the Cloud image's fedora-release-cloud gives way to Workstation's.
    dnf -y install --allowerasing @workstation-product-environment
    systemctl set-default graphical.target
    systemctl enable gdm.service sshd.service
    printf '[daemon]\nTimedLoginEnable=true\nTimedLogin=%s\nTimedLoginDelay=5\n' "@USER@" > /etc/gdm/custom.conf
    echo "disabled by tinkero-smoke: a clone must not run cloud-init again" > /etc/cloud/cloud-init.disabled
power_state:
  mode: poweroff
  message: the tinkero-smoke base is built
  timeout: 120
  condition: true
```

- [ ] **Step 3: `ci/vm-smoke/run`, with `base`**

Create `ci/vm-smoke/run` with exactly this content, then `chmod +x ci/vm-smoke/run`. Task 3 adds the stages to it. Read `build_base` for what it does on the host: it refuses when the base exists and when a disk file of the base's name exists with no domain to own it (move it aside by hand), it never removes anything and overwrites no disk it did not just create, it binds the SSH forward to 127.0.0.1 only, it validates the lock's `fedora` value before using it in a name, and the downloaded file gets the image's name only after its checksum matched.

```bash
#!/bin/bash
# run: the host side of the VM smoke test (Phase 3 design, section 6; docs/guides/vm-smoke.md).
# Run it as your own user on a host with libvirt.
#
#   ci/vm-smoke/run base    build the base VM once, unattended, from the pinned Fedora Cloud
#                           image and ci/vm-smoke/cloud-init.yaml; it is never booted again
#
# Exit status: 0 done; 2 the VM could not be built, or bad usage.
# Environment, every one optional:
#   TINKERO_SMOKE_DRY_RUN     1 prints the host commands instead of running them
#   TINKERO_SMOKE_STATE       where the image, the SSH key and the disks live
#                             (default ${XDG_CACHE_HOME:-~/.cache}/tinkero-smoke)
#   TINKERO_SMOKE_BASE        the base domain to clone (default tinkero-smoke-base-f<fedora>);
#                             set it to use a base built by hand (the guide's fallbacks)
#   TINKERO_SMOKE_USER, TINKERO_SMOKE_PASSWORD, TINKERO_SMOKE_USER2, TINKERO_SMOKE_PASSWORD2
#                             the two accounts (smoke/tinkero1 and smoke2/tinkero2); passwords
#                             are lower-case letters and digits, one key each
#   TINKERO_SMOKE_SSH_PORT    the host port forwarded to the guest's sshd (default 2222)
#   TINKERO_SMOKE_RENDERNODE  a /dev/dri/by-path/...-render node for virgl (an Optimus host)
#   TINKERO_SMOKE_URI         the libvirt URI (default qemu:///session)
# On the host this script writes under TINKERO_SMOKE_STATE and nowhere else. It deletes nothing:
# a stale download or user-data is overwritten, a disk file it did not make is never touched, and
# the base domain and its disk are yours to remove (docs/guides/vm-smoke.md says how).
set -euo pipefail
# The patterns below are byte patterns: under a UTF-8 locale bash's [0-9] admits non-ASCII digits
# (a sibling plan's review found it), so the locale is fixed.
export LC_ALL=C

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${TINKERO_ROOT:-$(cd "$here/../.." && pwd)}
lock=${TINKERO_LOCK:-$root/upstream.lock}
image_lock=${TINKERO_SMOKE_IMAGE_LOCK:-$here/image.lock}
user_data_in=$here/cloud-init.yaml
dry=${TINKERO_SMOKE_DRY_RUN:-0}
euid=${TINKERO_EUID:-$EUID}

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "vm-smoke: $*" >&2; exit 2; }
say() { echo "vm-smoke: $*" >&2; }
# lock_get FILE KEY: upstream.lock and image.lock are parsed, never sourced.
lock_get() {
  local line
  line=$(grep -E "^$2=" "$1" | tail -n1) || die "no key '$2' in $1"
  printf '%s\n' "${line#*=}"
}

# Every host path this script writes derives from the variable set here, once.
state=${TINKERO_SMOKE_STATE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/tinkero-smoke}
[[ $state == /* && $state != / ]] || die "TINKERO_SMOKE_STATE must be an absolute path, and not /: $state"

# Names.
uri=${TINKERO_SMOKE_URI:-qemu:///session}
fedora=$(lock_get "$lock" fedora)
[[ $fedora =~ ^[0-9]+$ ]] || die "$lock: fedora must be a number: $fedora"
base=${TINKERO_SMOKE_BASE:-tinkero-smoke-base-f$fedora}
user=${TINKERO_SMOKE_USER:-smoke}
password=${TINKERO_SMOKE_PASSWORD:-tinkero1}
user2=${TINKERO_SMOKE_USER2:-smoke2}
password2=${TINKERO_SMOKE_PASSWORD2:-tinkero2}
ssh_port=${TINKERO_SMOKE_SSH_PORT:-2222}
rendernode=${TINKERO_SMOKE_RENDERNODE:-}
key=$state/id_ed25519
# The VM, as the 2F guide built it.
memory=8192; vcpus=4; disk_gb=40
graphics=spice,gl.enable=yes,listen=none
if [[ -n $rendernode ]]; then graphics+=,rendernode=$rendernode; fi
# Timeouts.
base_wait=90   # minutes virt-install waits for cloud-init to power the base off

[[ $euid != 0 ]] || die "run as your own user, not as root: the VMs live under your own libvirt daemon ($uri)"
[[ $user =~ ^[a-z][a-z0-9]*$ && $user2 =~ ^[a-z][a-z0-9]*$ && $user != "$user2" ]] || die "the two account names must differ and be lower-case letters and digits: $user, $user2"
[[ $password =~ ^[a-z0-9]+$ && $password2 =~ ^[a-z0-9]+$ ]] || die "passwords must be lower-case letters and digits: virsh send-key types one key per character"
[[ $ssh_port =~ ^[0-9]+$ ]] || die "TINKERO_SMOKE_SSH_PORT must be a number: $ssh_port"

# --- host commands ---------------------------------------------------------------------------
exec 3>&1   # a dry run's command lines go here, also from inside $(...)
# show CMD...: one command line, quoted only where the shell needs it.
show() {
  local a s=""
  for a in "$@"; do
    if [[ $a =~ ^[A-Za-z0-9_./:=,@%+-]+$ ]]; then s+=" $a"; else s+=" ${a@Q}"; fi
  done
  echo "${s# }" >&3
}
# run CMD...: every host command that changes something goes through here.
run() {
  if [[ $dry == 1 ]]; then show "$@"; return 0; fi
  "$@"
}
# probe DEFAULT CMD...: a host command that only asks. A dry run prints it and answers DEFAULT.
probe() {
  local default=$1; shift
  if [[ $dry == 1 ]]; then show "$@"; return "$default"; fi
  "$@" >/dev/null 2>&1
}
domain_exists() { probe "$1" virsh -c "$uri" dominfo "$2"; }   # DEFAULT NAME
domain_state() {   # NAME DEFAULT: "running", "shut off", ...
  if [[ $dry == 1 ]]; then show virsh -c "$uri" domstate "$1"; echo "$2"; return 0; fi
  virsh -c "$uri" domstate "$1" 2>/dev/null || echo unknown
}

# --- the base (design 6.2) -------------------------------------------------------------------
# verified FILE SHA256: the file is there and has that checksum.
verified() {
  local got
  [[ -f $1 ]] || return 1
  got=$(sha256sum -- "$1" | cut -d' ' -f1)
  [[ $got == "$2" ]]
}
# fetch_image: the pinned cloud image in $state, checked against image.lock before every use. A
# copy that fails the check is neither used nor removed: the next download overwrites it.
fetch_image() {
  local url sha name
  url=$(lock_get "$image_lock" url); sha=$(lock_get "$image_lock" sha256); name=${url##*/}
  [[ $url == https://* && $name == *.qcow2 ]] || die "$image_lock: url must be the https URL of a .qcow2 image: $url"
  [[ $sha =~ ^[0-9a-f]{64}$ ]] || die "$image_lock: sha256 must be 64 hex digits"
  image=$state/$name
  if [[ $dry != 1 ]] && verified "$image" "$sha"; then return 0; fi
  run curl -fL --retry 3 -o "$image.part" "$url" || die "could not download $url"
  if [[ $dry == 1 ]]; then
    show sha256sum -- "$image.part"
  elif ! verified "$image.part" "$sha"; then
    die "checksum mismatch for $image.part: image.lock says $sha. It was not used; the next run downloads it again"
  fi
  run mv -f -- "$image.part" "$image"
}
# render_user_data: cloud-init.yaml with its five placeholders filled in, as $state/user-data.
render_user_data() {
  local text pub name
  text=$(<"$user_data_in")
  for name in USER PASSWORD USER2 PASSWORD2 SSH_KEY; do
    [[ $text == *"@$name@"* ]] || die "$user_data_in has no @$name@ placeholder"
  done
  if [[ $dry == 1 ]]; then echo "# write $state/user-data from ${user_data_in#"$root"/}" >&3; return 0; fi
  pub=$(<"$key.pub")
  [[ $pub == ssh-ed25519\ * && $pub != *$'\n'* ]] || die "$key.pub is not one ed25519 public key"
  text=${text//@USER@/"$user"}; text=${text//@PASSWORD@/"$password"}
  text=${text//@USER2@/"$user2"}; text=${text//@PASSWORD2@/"$password2"}
  text=${text//@SSH_KEY@/"$pub"}
  [[ ! $text =~ @[A-Z0-9_]+@ ]] || die "$user_data_in has a placeholder this script does not fill: ${BASH_REMATCH[0]}"
  printf '%s\n' "$text" > "$state/user-data"
}
build_base() {
  local disk=$state/$base.qcow2 st
  [[ -z ${TINKERO_SMOKE_BASE:-} ]] || die "TINKERO_SMOKE_BASE is set: that base is built by hand, not by 'run base'"
  if domain_exists 1 "$base"; then
    die "the base domain $base already exists. This script never removes it: to rebuild, remove it by hand (docs/guides/vm-smoke.md, 'Removing the base') and run 'base' again"
  fi
  # Nothing is overwritten that this run did not create: a disk file with the base's name and no
  # domain to own it is somebody's (an older base whose domain was undefined, say).
  if [[ $dry != 1 && -e $disk ]]; then
    die "$disk exists and no domain $base owns it. This script overwrites nothing it did not just create: move that file aside by hand (mv), and run 'base' again"
  fi
  run mkdir -p "$state"
  if [[ $dry == 1 || ! -f $key ]]; then run ssh-keygen -q -t ed25519 -N "" -C tinkero-smoke -f "$key"; fi
  fetch_image
  render_user_data
  run cp --reflink=auto -- "$image" "$disk"
  run qemu-img resize "$disk" "${disk_gb}G"
  # The guide's VM (memory, UEFI, virgl), its passt port forward for SSH, and cloud-init in
  # place of the installer. --wait returns when cloud-init's power_state has shut the VM down.
  run virt-install --connect "$uri" --name "$base" --memory "$memory" --vcpus "$vcpus" \
    --import --disk "path=$disk,format=qcow2,bus=virtio" --osinfo detect=on,require=off --boot uefi \
    --network "user,model.type=virtio,backend.type=passt,portForward0.proto=tcp,portForward0.address=127.0.0.1,portForward0.range0.start=$ssh_port,portForward0.range0.to=22" \
    --video virtio,accel3d=yes --graphics "$graphics" \
    --cloud-init "user-data=$state/user-data" --noautoconsole --wait "$base_wait" \
    || die "virt-install failed, or cloud-init did not power the base off within $base_wait minutes. Look at it with: virt-viewer --connect $uri --attach $base"
  st=$(domain_state "$base" "shut off")
  [[ $st == "shut off" ]] || die "the base is '$st', not shut off: cloud-init has not finished"
  say "the base $base is ready. It is never booted again: every run clones it"
}

case ${1:-} in
  base)      [[ $# == 1 ]] || { usage >&2; exit 2; }
             build_base ;;
  -h|--help) usage ;;
  *)         usage >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Run the tests**

Run: `bash tests/test-vm-smoke.sh` Expected: `1..216`, no `not ok`.
Run: `TINKERO_EUID=1000 TINKERO_SMOKE_DRY_RUN=1 TINKERO_SMOKE_STATE=/nonexistent/state ci/vm-smoke/run base` Expected: eleven lines on stdout and one on stderr, and nothing is created (a dry run touches no path; `TINKERO_EUID=1000` is for an agent session that runs as root, which the script otherwise refuses):

```
virsh -c qemu:///session dominfo tinkero-smoke-base-f44
mkdir -p /nonexistent/state
ssh-keygen -q -t ed25519 -N '' -C tinkero-smoke -f /nonexistent/state/id_ed25519
curl -fL --retry 3 -o /nonexistent/state/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2.part https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
sha256sum -- /nonexistent/state/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2.part
mv -f -- /nonexistent/state/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2.part /nonexistent/state/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2
# write /nonexistent/state/user-data from ci/vm-smoke/cloud-init.yaml
cp --reflink=auto -- /nonexistent/state/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2 /nonexistent/state/tinkero-smoke-base-f44.qcow2
qemu-img resize /nonexistent/state/tinkero-smoke-base-f44.qcow2 40G
virt-install --connect qemu:///session --name tinkero-smoke-base-f44 --memory 8192 --vcpus 4 --import --disk path=/nonexistent/state/tinkero-smoke-base-f44.qcow2,format=qcow2,bus=virtio --osinfo detect=on,require=off --boot uefi --network user,model.type=virtio,backend.type=passt,portForward0.proto=tcp,portForward0.address=127.0.0.1,portForward0.range0.start=2222,portForward0.range0.to=22 --video virtio,accel3d=yes --graphics spice,gl.enable=yes,listen=none --cloud-init user-data=/nonexistent/state/user-data --noautoconsole --wait 90
virsh -c qemu:///session domstate tinkero-smoke-base-f44
vm-smoke: the base tinkero-smoke-base-f44 is ready. It is never booted again: every run clones it
```

If `cloud-init` is installed where the task is built, check the rendered template too. The planning session did, with cloud-init 26.1, on the `user-data` the stubbed test run wrote: `Valid schema`. It is not part of the test suite, because CI's container has no cloud-init:

```bash
mkdir -p .cache
sed 's/@USER@/smoke/g; s/@PASSWORD@/tinkero1/; s/@USER2@/smoke2/; s/@PASSWORD2@/tinkero2/; s|@SSH_KEY@|ssh-ed25519 AAAA tinkero-smoke|' ci/vm-smoke/cloud-init.yaml > .cache/user-data.check
cloud-init schema --config-file .cache/user-data.check
```

- [ ] **Step 5: CI and ShellCheck**

In `.github/workflows/ci.yml`:

```diff
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -26,7 +26,7 @@
         run: >
           shellcheck -x -e SC1090,SC1091
           dev build/assemble build/fetch-upstream build/render-spec build/lib.sh
-          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/gate-session-units ci/check-rpm ci/lib-gate.sh ci/vm-smoke/guest
+          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/gate-session-units ci/check-rpm ci/lib-gate.sh ci/vm-smoke/guest ci/vm-smoke/run
           branding/render-wallpapers branding/inventory-images branding/contact-sheet
           tests/run tests/lib.sh tests/test-*.sh tests/fixtures/make-tree.sh install.sh tests/fixtures/make-payload.sh
           distro/fedora/replacements/* distro/fedora/lib/pkg.sh
```

Run: `shellcheck -x -e SC1090,SC1091 ci/vm-smoke/run ci/vm-smoke/guest tests/test-vm-smoke.sh` Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add ci/vm-smoke/run ci/vm-smoke/cloud-init.yaml ci/vm-smoke/image.lock tests/test-vm-smoke.sh .github/workflows/ci.yml
git commit -m "ci: the smoke test's base VM from the pinned Fedora Cloud image and cloud-init (plan 3D, D18)"
```

**Verification for the issue:** `bash tests/test-vm-smoke.sh` at `1..216`; the dry run prints the lines of Step 4 and creates nothing; `grep -c '^sha256=28680fe5b371a5a82ebf43a31926e086a168e59949d03969c5093e7071f90b7f$' ci/vm-smoke/image.lock` prints `1`; CI green. The build itself (`virt-install`, cloud-init, the group install) runs for the first time in Task 5: nothing here downloads the image or starts a VM.

---

### Task 3: The run stages

**Files:**
- Modify: `ci/vm-smoke/run` (the usage header, the variables, the `run` helper, everything from "the report" on), `dev` (the `vm-smoke` command), `tests/test-vm-smoke.sh` (a block before its last line)

**Interfaces:**
- Consumes: Task 1's guest subcommands, exactly as its table lists them; Task 2's helpers and base; `upstream.lock` (`omarchy_tag`, `tinkero_rev`, `fedora`: the expected package is `tinkero-<tag without v>-<rev>.fc<fedora>.noarch`); the checkout's `install.sh`.
- Produces: `ci/vm-smoke/run [--stages LIST] [--keep] [--lockout]` and `./dev vm-smoke [ARG...]`.
  - Stages, in the default order: `clone`, `baseline`, `install`, `users`, `session`, `lock`, `gnome`, `reinstall`, `remove`. `--stages a,b` runs those on the kept clone (a list with `clone`, which must come first or the run is refused with exit 2, starts from a fresh one) and keeps the clone; `--keep` keeps it after a passing full run; a run with a failure always keeps it; `--lockout` adds round 3.
  - Stdout is the report: a `# vm-smoke: <package>, base <base>, clone <clone>, stages: <list>` line, `# stage <name>` lines, `ok N - <stage>: <description>` and `not ok N - <stage>: <description>` with `#   ` detail lines, numbered across the whole run, then `1..N` and `# <a> ok, <b> not ok, <seconds>s`. Everything else goes to stderr.
  - Results: `<TINKERO_SMOKE_RESULTS>/<UTC timestamp, YYYYMMDDTHHMMSSZ>/` with `report.tap`, `commands.log`, `host.log`, `stage-<name>.log` and `vmcheck/` (the guest's files, copied out after every stage).
  - Exit status: 0 every line ok; 1 any line not ok; 2 the VM could not be built or reached (the report ends with `Bail out! <reason>`), or bad usage.
  - Environment added to Task 2's: `TINKERO_SMOKE_RESULTS` (default `.cache/vm-smoke` in the checkout), `TINKERO_SMOKE_CLONE` (default `tinkero-smoke`), `TINKERO_SMOKE_WRONG_PASSWORD` (default `wrong1`).

How the stages map to design 6.1 and 6.3, and what the first run may have to correct:

- **One function per stage, two helpers for everything outside it.** Host commands go through `run` (or `probe`, `domain_state` when they only ask), guest commands through `guest`; `guest_do` turns one guest command into one report line, `guest_check` renumbers a check's TAP lines. Names and timeouts are variables at the top. A stage that cannot get the session it needs returns after its failed lines; the run goes on with the next stage.
- **Sessions** are entered by `enter NAME`: the guest sets the session in AccountsService (`session-next`), ends the running session (`session-end terminate`), and waits for GDM's timed login to start the next one (`session-wait`). The `session` stage reboots instead of logging out, as the guide does, because the lock rounds need a boot on which nothing has run `faillock` as root.
- **Typing** is `type_line`: one `virsh send-key` per character from the key table, a first key that types nothing (it wakes a lock that has blanked the display), and Enter. The lock's state is asked of the compositor through upstream's `omarchy-hyprland-session-locked`, never assumed.
- **Removing the clone** (`remove_clone`, the only place the driver destroys anything) first checks the name again and then asks `virsh domblklist --details` for the clone's disks: every one must be a file directly under `TINKERO_SMOKE_STATE`, or the driver stops with exit 2 naming the disk, before anything is stopped. `virt-clone --file` puts the clone's disk there, so a clone the driver made always passes, and a domain with a `tinkero-smoke*` name that somebody made by hand, with its disk elsewhere, never has its storage removed. An empty CD-ROM drive (source `-`) is not a disk. The lock's `omarchy_tag` and `tinkero_rev` are validated before they are used to build the expected package name, which reaches the guest's command line quoted with `printf %q`.
- **The clone's disk** is given to `virt-clone` with `--file` under `TINKERO_SMOKE_STATE`, where the guide used `--auto-clone`: the path then derives from the state variable for a hand-built base too, whose own disk lives in libvirt's image directory.
- **The `reinstall` stage's plan check** is "nothing a run would write", not the design's literal "all-`current` plan": after the `gnome` stage the terminal configs carry the text size the test set, so tinkero-provision reports them as the user's (`keep-user`). The guest's `check reinstall` (Task 1) allows `current` and `keep-user` and fails on every decision that writes; see "Deviations".

- [ ] **Step 1: The failing tests**

In `tests/test-vm-smoke.sh`, replace the last line (`rm -rf "$d"; finish`) with this block followed by that same line. The dry-run cases fold the constant part of each printed line away (`GUEST` is a guest call over SSH, `SSH` and `SCP` carry the key and the port, `VIRSH` the URI), so that each stage's sequence reads as one line. The second half runs the stages for real against a stub `ssh` that answers each guest call from a file.

```bash
# --- the run stages, dry run: the command sequence per stage ------------------------------------
# dry ARG...: a dry run, with the constant parts of each line folded away: GUEST is a guest
# script call over SSH, SSH and SCP carry the key and the port, VIRSH the libvirt URI.
tag=$(sed -n 's/^omarchy_tag=v//p' "$ROOT/upstream.lock"); rev=$(sed -n 's/^tinkero_rev=//p' "$ROOT/upstream.lock")
lock_nvr=tinkero-$tag-$rev.fc$fed.noarch
dry() {
  STATE=$s TINKERO_SMOKE_DRY_RUN=1 r "$@"
  seq=$(sed -e "s|^timeout 3600 ssh .* smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=$lock_nvr bash vmcheck/guest \(.*\)'\$|GUEST \1|" \
    -e "s|^ssh -n -i $s/id_ed25519 -p 2222 .* smoke@localhost |SSH |" -e "s|^scp -r -i $s/id_ed25519 -P 2222 .*-o LogLevel=ERROR |SCP -r |" \
    -e "s|^scp -i $s/id_ed25519 -P 2222 .*-o LogLevel=ERROR |SCP |" -e "s|^virsh -c qemu:///session |VIRSH |" \
    -e "s|$s|STATE|g; s|$d/results/dry-run|RESULTS|g; s|$ROOT|ROOT|g" <<<"$out")
}
calls() { grep -E "^($1) " <<<"$seq" | paste -sd'|'; }   # the lines of $seq that start with one of the words
attach="VIRSH dominfo tinkero-smoke
VIRSH domstate tinkero-smoke
SSH true
SSH 'mkdir -p vmcheck'
SCP ROOT/ci/vm-smoke/guest ROOT/install.sh smoke@localhost:vmcheck/"
enter_gnome="GUEST session-kind
GUEST session-next gnome
GUEST session-end terminate
GUEST session-wait gnome 180"
kept="vm-smoke: the clone tinkero-smoke is kept: virt-viewer --connect qemu:///session --attach tinkero-smoke; ssh -i STATE/id_ed25519 -p 2222 smoke@localhost. The next full run replaces it"
hgood; dry --stages baseline
assert_eq "$rc" 0 "dry run: exit 0"
assert_eq "$seq" "# vm-smoke: $lock_nvr, base tinkero-smoke-base-f44, clone tinkero-smoke, stages: baseline
$attach
# stage baseline
$enter_gnome
GUEST step baseline
GUEST snap 0-baseline
GUEST check baseline
GUEST step linger-on
SCP -r smoke@localhost:vmcheck RESULTS/
$kept" "stage baseline: attach to the kept clone, enter GNOME through GDM, set the canary, snapshot, check, linger"
dry --stages clone
assert_eq "$seq" "# vm-smoke: $lock_nvr, base tinkero-smoke-base-f44, clone tinkero-smoke, stages: clone
# stage clone
VIRSH dominfo tinkero-smoke-base-f44
VIRSH dominfo tinkero-smoke
VIRSH domblklist --details tinkero-smoke
VIRSH domstate tinkero-smoke
VIRSH destroy tinkero-smoke
VIRSH undefine tinkero-smoke --nvram --remove-all-storage
virt-clone --connect qemu:///session --original tinkero-smoke-base-f44 --name tinkero-smoke --file STATE/tinkero-smoke.qcow2
VIRSH start tinkero-smoke
SSH true
SSH 'mkdir -p vmcheck'
SCP ROOT/ci/vm-smoke/guest ROOT/install.sh smoke@localhost:vmcheck/
$kept" "stage clone: an old clone is removed through libvirt, the base is cloned onto a disk under the state directory, booted, reached"
dry --stages install
assert_eq "$(calls GUEST)" "GUEST session-kind|GUEST session-next gnome|GUEST session-end terminate|GUEST session-wait gnome 180|GUEST step install|GUEST snap 0b-installed|GUEST check install|GUEST diff-snap 0-baseline 0b-installed" "stage install: install.sh --yes, snapshot, checks, the diff against the baseline"
dry --stages users
assert_eq "$(calls GUEST)" "GUEST step users|GUEST check users" "stage users: dotfiles in place, then the plan and the run"
dry --stages session
assert_eq "$(calls 'GUEST|SSH|VIRSH send-key|VIRSH domstate' | sed 's/^.*SCP[^|]*|//')" "VIRSH domstate tinkero-smoke|SSH true|SSH 'mkdir -p vmcheck'|GUEST session-next tinkero|SSH 'sudo systemctl reboot'|SSH true|GUEST session-wait tinkero 180|GUEST check session|VIRSH send-key tinkero-smoke KEY_POWER|VIRSH domstate tinkero-smoke|GUEST check power-key" "stage session: a reboot into Tinkero through GDM, the checks, the power key from the host"
dry --stages lock
pw="VIRSH send-key tinkero-smoke KEY_LEFTSHIFT|VIRSH send-key tinkero-smoke KEY_T|VIRSH send-key tinkero-smoke KEY_I|VIRSH send-key tinkero-smoke KEY_N|VIRSH send-key tinkero-smoke KEY_K|VIRSH send-key tinkero-smoke KEY_E|VIRSH send-key tinkero-smoke KEY_R|VIRSH send-key tinkero-smoke KEY_O|VIRSH send-key tinkero-smoke KEY_1|VIRSH send-key tinkero-smoke KEY_ENTER"
assert_eq "$(calls 'GUEST')" "GUEST session-kind|GUEST session-next tinkero|GUEST session-end terminate|GUEST session-wait tinkero 180|GUEST lock|GUEST lock-wait unlocked 30|GUEST lock|GUEST lock-wait idle 30|GUEST lock-wait idle 30|GUEST check lock-failures 2|GUEST lock-wait unlocked 30|GUEST check lock-clear|GUEST check lock-journal|GUEST check pam-plain|GUEST lock|GUEST lock-wait unlocked 30|GUEST lock|GUEST lock-wait idle 30|GUEST lock-wait idle 30|GUEST check lock-failures 2|GUEST lock-wait unlocked 30|GUEST check lock-clear|GUEST check lock-journal|GUEST check pam-wrapped" "stage lock: rounds 1 and 2 on wrapped, the switch to plain, rounds 4 and 5, the switch back"
assert_eq "$(calls 'VIRSH send-key' | cut -d'|' -f1-10)" "$pw" "stage lock: the password is typed one key per character, after a key that wakes the lock, and ends with Enter"
assert_eq "$(grep -c '^VIRSH send-key tinkero-smoke KEY_ENTER$' <<<"$seq")" 8 "stage lock: eight lines are typed (two right and two wrong per variant)"
assert_eq "$(grep -c '^VIRSH send-key tinkero-smoke KEY_W$' <<<"$seq")" 4 "stage lock: four of them are the wrong password"
dry --stages lock --lockout
assert_eq "$(grep -c '^VIRSH send-key tinkero-smoke KEY_ENTER$' <<<"$seq")" 20 "--lockout: round 3 types ten wrong passwords and the right one twice"
assert_contains "$(calls GUEST)" "GUEST check lock-failures 10|GUEST lock-wait idle 30|GUEST lock-wait unlocked 30|GUEST check lock-clear|GUEST check lock-journal" "--lockout: ten failures, a refused right password, the unlock after the wait"
dry --stages gnome
cycle() { echo "GUEST session-kind|GUEST session-next tinkero|GUEST session-end terminate|GUEST session-wait tinkero 180|GUEST check theme|GUEST session-next gnome|GUEST session-end $1|GUEST session-wait gnome 180|GUEST snap $2|GUEST diff-snap 0-baseline $2|GUEST check gnome $2"; }
assert_eq "$(calls GUEST)" "$(cycle menu 1-menu-logout)|$(cycle terminate 2-terminate)|$(cycle kill 3-kill)|GUEST diff-snap 1-menu-logout 2-terminate|GUEST diff-snap 1-menu-logout 3-kill" "stage gnome: three cycles, each ended its own way, each snapshot against the baseline"
dry --stages reinstall
assert_eq "$(calls GUEST | sed 's/^.*session-wait gnome 180|//')" "GUEST step reinstall|GUEST check reinstall|GUEST snap 5-reinstalled|GUEST diff-snap 0-baseline 5-reinstalled" "stage reinstall: a second install.sh --yes and its checks"
dry --stages remove
assert_eq "$(calls GUEST | sed 's/^.*session-wait gnome 180|//')" "GUEST step remove|GUEST snap 4-removed|GUEST check remove|GUEST diff-snap 0-baseline 4-removed" "stage remove: the guide's removal, the snapshot, the checks"
dry
assert_eq "$(grep '^# stage ' <<<"$seq" | paste -sd' ')" "# stage clone # stage baseline # stage install # stage users # stage session # stage lock # stage gnome # stage reinstall # stage remove" "no --stages: every stage, in the design's order"
assert_eq "$(tail -n 4 <<<"$seq")" "VIRSH domblklist --details tinkero-smoke
VIRSH domstate tinkero-smoke
VIRSH destroy tinkero-smoke
VIRSH undefine tinkero-smoke --nvram --remove-all-storage" "a full run that passed removes its clone at the end, through libvirt, after looking at its disks"
assert_eq "$(grep -cE '(^|[ /])(rm|rmdir|unlink|shred)( |$)' <<<"$out")" 0 "dry run: no rm of any kind in the whole sequence"
assert_eq "$(grep -E 'destroy|undefine|remove-all-storage' <<<"$seq" | grep -vcE '^VIRSH (destroy|undefine) tinkero-smoke( --nvram --remove-all-storage)?$')" 0 "dry run: the only thing ever destroyed or undefined is the clone, by name"
assert_eq "$(grep -c 'tinkero-smoke-base-f44' <<<"$(grep -vE '^(VIRSH dominfo|virt-clone|# vm-smoke)' <<<"$seq")")" 0 "dry run: the base is only asked about and cloned"
dry --keep
assert_eq "$(grep -c 'undefine' <<<"$(sed -n '/# stage remove/,$p' <<<"$seq")")" 0 "--keep: the clone stays"
assert_no_path "$d/results" "dry run: no results directory is created"
assert_no_path "$s" "dry run: no state directory either"
assert_eq "$(wc -l < "$HLOG")" 0 "dry run: no host tool is called"
STATE=$s TINKERO_SMOKE_DRY_RUN=1 TINKERO_EUID=1000 TINKERO_SMOKE_RESULTS="$d/results" PATH="$d/hbin:$PATH" "$ROOT/dev" vm-smoke --stages users > "$d/dev.out" 2>&1; rc=$?
assert_eq "$rc:$(grep -c 'bash vmcheck/guest check users' "$d/dev.out")" "0:1" "./dev vm-smoke is the same command"
dry --stages base; assert_eq "$rc" 2 "--stages base is refused"
assert_contains "$out" "the base is built by 'run base'" "and says how the base is built"
dry --stages; assert_eq "$rc" 2 "--stages without a list is exit 2"
dry --stages baseline,clone; assert_eq "$rc" 2 "--stages with clone after another stage is exit 2"
assert_contains "$out" "clone must come first" "and says why"
printf 'fedora=44\nomarchy_tag=v4.0.4; touch x\ntinkero_rev=3\n' > "$d/bad-tag.lock"; TINKERO_LOCK=$d/bad-tag.lock dry --stages users
assert_eq "$rc" 2 "a lock whose tag is not a version is refused: it would reach the guest's command line"
assert_contains "$out" "malformed" "and the message says so"
dry --frobnicate; assert_eq "$rc" 2 "an unknown option is exit 2"
TINKERO_SMOKE_CLONE=tinkero-smoke-base-f44 dry --stages users
assert_eq "$rc" 2 "a clone name that names the base is refused"
TINKERO_SMOKE_CLONE=fedora-workstation dry --stages users
assert_eq "$rc" 2 "a clone name without the tinkero-smoke prefix is refused"
assert_contains "$out" "must start with tinkero-smoke" "and the message says so"

# --- the run stages against stub virsh, ssh and scp: the report and the exit status ---------------
# The ssh stub answers a guest call from $ST/h-<what>: a check prints TAP, the others succeed
# unless their words are listed in $ST/h-fail.
hstub ssh <<'S'
#!/bin/bash
cmd=${*: -1}; echo "ssh $cmd" >> "$HLOG"
[[ $(cat "$ST/h-ssh") == up ]] || exit 255
case $cmd in
  *"vmcheck/guest check "*) what=${cmd##*vmcheck/guest check }; what=${what%% *}
     if [[ -f $ST/h-check-$what ]]; then cat "$ST/h-check-$what"; else printf 'ok 1 - %s is fine\n1..1\n' "$what"; fi
     if grep -q '^not ok' "$ST/h-check-$what" 2>/dev/null; then exit 1; fi ;;
  *"vmcheck/guest session-kind") cat "$ST/h-kind" ;;
  *"vmcheck/guest "*) what=${cmd##*vmcheck/guest }
     if grep -qxF -- "$what" "$ST/h-fail"; then echo "guest: $what failed"; exit 1; fi; echo "done: $what" ;;
esac
S
hstub scp <<'S'
#!/bin/bash
echo "scp ${*: -2}" >> "$HLOG"
S
hstub virt-clone <<'S'
#!/bin/bash
echo "virt-clone $*" >> "$HLOG"
S
blk() { printf ' Type   Device   Target   Source\n------------------------------------------------\n%s\n' "$1" > "$ST/blklist"; }
sgood() { hgood; blk " file   disk     vda      $d/state/tinkero-smoke.qcow2
 file   cdrom    sda      -"; printf 'tinkero-smoke-base-f44\ntinkero-smoke\n' > "$ST/domains"; echo running > "$ST/domstate"; echo up > "$ST/h-ssh"; echo gnome > "$ST/h-kind"; : > "$ST/h-fail"; }
report() { cat "$d"/results/*/report.tap | tail -n "${1:-1000}"; }
latest() { find "$d/results" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -n 1; }
sgood; r --stages baseline
assert_eq "$rc" 0 "a stage whose every line is ok exits 0"
res=$(latest)
assert_eq "$(grep -v '^#' "$res/report.tap")" "ok 1 - baseline: the dark appearance and the canary key are set
ok 2 - baseline: snapshot 0-baseline taken
ok 3 - baseline: baseline is fine
ok 4 - baseline: lingering is on
1..4" "report.tap: one numbering for the whole run, each line named after its stage"
assert_contains "$out" "ok 3 - baseline: baseline is fine" "the report is also printed"
assert_file "$res/commands.log" "results: every command is logged"
assert_contains "$(cat "$res/stage-baseline.log")" "done: snap 0-baseline" "results: every guest command's output is kept per stage"
assert_contains "$(cat "$HLOG")" "scp smoke@localhost:vmcheck $res/" "results: the guest's files are copied out after the stage"
assert_contains "$out" "the clone tinkero-smoke is kept" "--stages keeps the clone"
assert_eq "$(grep -c 'undefine\|destroy' "$HLOG")" 0 "and nothing is removed"
sgood; printf 'ok 1 - the clone is in a GNOME session\nnot ok 2 - SELinux is enforcing\n#   expected '"'"'Enforcing'"'"', got '"'"'Permissive'"'"'\n1..2\n' > "$ST/h-check-baseline"; r --stages baseline
assert_eq "$rc" 1 "a line that is not ok exits 1"
assert_contains "$out" "not ok 4 - baseline: SELinux is enforcing" "the guest's failure is renumbered into the report"
assert_contains "$out" "#   expected 'Enforcing', got 'Permissive'" "with its detail line"
sgood; printf 'ok 1 - the clone is in a GNOME session\n' > "$ST/h-check-baseline"; r --stages baseline
assert_eq "$rc" 1 "a guest check that ends without its plan line fails the run"
assert_contains "$out" "not ok 4 - baseline: guest check baseline ran to its end" "and the report says which"
sgood; echo "ok 1 - fine" > "$ST/h-check-baseline"; printf 'ok 1 - fine\n1..1\n' > "$ST/h-check-baseline"; echo "snap 0-baseline" > "$ST/h-fail"; r --stages baseline
assert_eq "$rc" 1 "a guest step that fails is a line that is not ok"
assert_contains "$out" "not ok 2 - baseline: snapshot 0-baseline taken" "named after what it was for"
assert_contains "$out" "#   guest snap 0-baseline (exit 1): guest: snap 0-baseline failed" "with the guest's last words"
assert_contains "$out" "ok 3 - baseline: fine" "and the stage goes on"
sgood; echo tinkero > "$ST/h-kind"; r --stages baseline
assert_contains "$out" "ok 2 - baseline: the tinkero session is ended" "a stage that needs GNOME ends a Tinkero session first"
assert_contains "$(cat "$HLOG")" "vmcheck/guest session-wait gnome 180" "and waits for GDM's timed login"
sgood; echo down > "$ST/h-ssh"; r --stages baseline
assert_eq "$rc" 2 "a VM that does not answer SSH is exit 2"
assert_contains "$out" "Bail out! the VM does not answer SSH on port 2222" "with a Bail out! line"
sgood; echo tinkero-smoke-base-f44 > "$ST/domains"; r --stages baseline
assert_eq "$rc" 2 "--stages without a kept clone is exit 2"
assert_contains "$out" "there is no kept clone tinkero-smoke" "and says so"
sgood; : > "$ST/domains"; r
assert_eq "$rc" 2 "a full run without a base is exit 2"
assert_contains "$out" "run 'ci/vm-smoke/run base' first" "and names the command"
sgood; r
assert_eq "$rc" 0 "a full run against the stubs passes"
assert_eq "$(grep -c '^virt-clone --connect qemu:///session --original tinkero-smoke-base-f44 --name tinkero-smoke --file '"$d"'/state/tinkero-smoke.qcow2$' "$HLOG")" 1 "full run: the base is cloned onto a disk under the state directory"
assert_eq "$(tail -n 1 "$HLOG")" "virsh -c qemu:///session undefine tinkero-smoke --nvram --remove-all-storage" "full run: a passing run removes its clone last"
assert_eq "$(grep -c 'undefine tinkero-smoke-base\|destroy tinkero-smoke-base' "$HLOG")" 0 "full run: the base is never destroyed or undefined"
assert_eq "$(grep -c '^virsh -c qemu:///session send-key tinkero-smoke KEY_POWER$' "$HLOG")" 1 "full run: the power key is pressed once"
assert_contains "$(tail -n 3 "$(latest)/report.tap")" " ok, 0 not ok, " "full run: the report ends with its tally and duration"
sgood; printf 'not ok 1 - no AVC denial since boot\n1..1\n' > "$ST/h-check-lock-journal"; r
assert_eq "$rc" 1 "full run: one failing line fails the run"
assert_eq "$(grep -c 'undefine tinkero-smoke --nvram' "$HLOG")" 1 "full run: and the clone is kept for a look (only the old one was removed)"
sgood; : > "$ST/h-check-lock-journal"; printf 'ok 1 - fine\n1..1\n' > "$ST/h-check-lock-journal"; r --keep
assert_eq "$rc:$(grep -c 'undefine tinkero-smoke --nvram' "$HLOG")" "0:1" "--keep: a passing full run keeps its clone too"
sgood; echo "lock-wait unlocked 30" > "$ST/h-fail"; echo "lock-wait unlocked 2" >> "$ST/h-fail"; echo tinkero > "$ST/h-kind"; r --stages lock
assert_eq "$rc" 1 "lock: a lock that never opens fails the stage"
assert_contains "$out" "lock: round 1 (wrapped): the right password unlocks on the first try" "lock: the round is named"
assert_contains "$out" "lock: the lock could be cleared for the next round" "lock: the recovery is reported"
assert_contains "$(cat "$HLOG")" "vmcheck/guest lock-reset" "lock: the tally is cleared (the guide's escape hatch)"
assert_contains "$(cat "$HLOG")" "vmcheck/guest session-end terminate" "lock: and the session is ended so that GDM is back"
assert_eq "$(grep -c 'check pam-plain' "$HLOG")" 0 "lock: the host is not switched to with-faillock behind a stuck lock"
for bad in " file   disk     vda      /var/lib/libvirt/images/tinkero-smoke.qcow2" " file   disk     vda      $d/state/sub/tinkero-smoke.qcow2" \
           " file   disk     vda      $d/state-other/tinkero-smoke.qcow2" " block  disk     vda      /dev/sdb" \
           " file   disk     vda      $d/state/tinkero-smoke.qcow2
 file   disk     vdb      $HOME/secrets.qcow2"; do
  sgood; blk "$bad"; r --stages clone
  assert_eq "$rc:$(grep -c 'destroy\|undefine\|^virt-clone' "$HLOG")" "2:0" "a clone whose disk is not a file directly under the state directory is refused, and nothing is stopped or removed"
  assert_contains "$out" "is not a file directly under $d/state, so this script did not create it" "and the message names the disk"
done
sgood; r --stages clone,baseline
assert_eq "$rc" 0 "a clone whose only disk is under the state directory (and an empty CD-ROM drive) is removed and made again"
sgood; : > "$d/state/tinkero-smoke.qcow2"; echo tinkero-smoke-base-f44 > "$ST/domains"; r
assert_eq "$rc" 2 "a disk under the clone's name that no domain owns stops the run"
assert_contains "$out" "This script removes nothing by path" "and the operator is told to remove that one file"
assert_file "$d/state/tinkero-smoke.qcow2" "and it is still there"
```

Run: `bash tests/test-vm-smoke.sh` Expected: `1..306`, exit 1, 63 `not ok`, all among the 90 new cases (216 was the tally before): Task 2's driver knows no stage and no `--stages`.

- [ ] **Step 2: The stages in `ci/vm-smoke/run`**

Apply this diff to `ci/vm-smoke/run` (`git apply` takes it as it is). It replaces the usage header, adds the results variable, the names and timeouts, the key table and the clone-name check, makes `run` log and keep its output during a run, and adds everything from "the report" to `main_run`; the final `case` now sends everything that is not `base` or `--help` to `main_run`.

```diff
--- a/ci/vm-smoke/run
+++ b/ci/vm-smoke/run
@@ -4,23 +4,38 @@
 #
 #   ci/vm-smoke/run base    build the base VM once, unattended, from the pinned Fedora Cloud
 #                           image and ci/vm-smoke/cloud-init.yaml; it is never booted again
+#   ci/vm-smoke/run [--stages LIST] [--keep] [--lockout]
+#                           clone the base, boot the clone and run the stages. LIST is comma
+#                           separated; the default is every stage, in this order:
+#                           clone,baseline,install,users,session,lock,gnome,reinstall,remove
+#     --stages LIST         run only these, on the kept clone (a list with "clone", which must come
+#                           first, starts from a fresh one); the clone is kept afterwards
+#     --keep                keep the clone after a full run that passed (a failed run keeps it)
+#     --lockout             add round 3 to the lock stage: ten failures and the two-minute wait
 #
-# Exit status: 0 done; 2 the VM could not be built, or bad usage.
+# Exit status: 0 every line of report.tap is ok; 1 at least one is not; 2 the VM could not be
+# built or reached, or bad usage. The report goes to stdout, everything else to stderr.
 # Environment, every one optional:
 #   TINKERO_SMOKE_DRY_RUN     1 prints the host commands instead of running them
 #   TINKERO_SMOKE_STATE       where the image, the SSH key and the disks live
 #                             (default ${XDG_CACHE_HOME:-~/.cache}/tinkero-smoke)
+#   TINKERO_SMOKE_RESULTS     where a run's results directory is created
+#                             (default .cache/vm-smoke in the checkout)
 #   TINKERO_SMOKE_BASE        the base domain to clone (default tinkero-smoke-base-f<fedora>);
 #                             set it to use a base built by hand (the guide's fallbacks)
+#   TINKERO_SMOKE_CLONE       the clone's name (default tinkero-smoke; it must start with that)
 #   TINKERO_SMOKE_USER, TINKERO_SMOKE_PASSWORD, TINKERO_SMOKE_USER2, TINKERO_SMOKE_PASSWORD2
 #                             the two accounts (smoke/tinkero1 and smoke2/tinkero2); passwords
 #                             are lower-case letters and digits, one key each
+#   TINKERO_SMOKE_WRONG_PASSWORD  what the lock stage types as a wrong password (default wrong1)
 #   TINKERO_SMOKE_SSH_PORT    the host port forwarded to the guest's sshd (default 2222)
 #   TINKERO_SMOKE_RENDERNODE  a /dev/dri/by-path/...-render node for virgl (an Optimus host)
 #   TINKERO_SMOKE_URI         the libvirt URI (default qemu:///session)
-# On the host this script writes under TINKERO_SMOKE_STATE and nowhere else. It deletes nothing:
-# a stale download or user-data is overwritten, a disk file it did not make is never touched, and
-# the base domain and its disk are yours to remove (docs/guides/vm-smoke.md says how).
+# On the host this script writes under TINKERO_SMOKE_STATE and TINKERO_SMOKE_RESULTS and nowhere
+# else. It deletes nothing by path: a stale download or user-data is overwritten, a disk file it
+# did not make is never touched, the clone it made is removed through libvirt, by name (and only
+# if its disks are files directly under TINKERO_SMOKE_STATE), and the base domain and its disk
+# are yours to remove (docs/guides/vm-smoke.md says how).
 set -euo pipefail
 # The patterns below are byte patterns: under a UTF-8 locale bash's [0-9] admits non-ASCII digits
 # (a sibling plan's review found it), so the locale is fixed.
@@ -34,7 +49,7 @@
 dry=${TINKERO_SMOKE_DRY_RUN:-0}
 euid=${TINKERO_EUID:-$EUID}
 
-usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }
+usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }
 die() { echo "vm-smoke: $*" >&2; exit 2; }
 say() { echo "vm-smoke: $*" >&2; }
 # lock_get FILE KEY: upstream.lock and image.lock are parsed, never sourced.
@@ -44,33 +59,62 @@
   printf '%s\n' "${line#*=}"
 }
 
-# Every host path this script writes derives from the variable set here, once.
+# Every host path this script writes derives from the two variables set here, once.
 state=${TINKERO_SMOKE_STATE:-${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/tinkero-smoke}
+results_root=${TINKERO_SMOKE_RESULTS:-$root/.cache/vm-smoke}
 [[ $state == /* && $state != / ]] || die "TINKERO_SMOKE_STATE must be an absolute path, and not /: $state"
+[[ $results_root == /* && $results_root != / ]] || die "TINKERO_SMOKE_RESULTS must be an absolute path, and not /: $results_root"
 
 # Names.
 uri=${TINKERO_SMOKE_URI:-qemu:///session}
 fedora=$(lock_get "$lock" fedora)
 [[ $fedora =~ ^[0-9]+$ ]] || die "$lock: fedora must be a number: $fedora"
 base=${TINKERO_SMOKE_BASE:-tinkero-smoke-base-f$fedora}
+clone=${TINKERO_SMOKE_CLONE:-tinkero-smoke}
 user=${TINKERO_SMOKE_USER:-smoke}
 password=${TINKERO_SMOKE_PASSWORD:-tinkero1}
 user2=${TINKERO_SMOKE_USER2:-smoke2}
 password2=${TINKERO_SMOKE_PASSWORD2:-tinkero2}
+wrong_password=${TINKERO_SMOKE_WRONG_PASSWORD:-wrong1}
 ssh_port=${TINKERO_SMOKE_SSH_PORT:-2222}
 rendernode=${TINKERO_SMOKE_RENDERNODE:-}
 key=$state/id_ed25519
+tag=$(lock_get "$lock" omarchy_tag); rev=$(lock_get "$lock" tinkero_rev)
+[[ $tag =~ ^v[0-9]+(\.[0-9]+)*$ && $rev =~ ^[0-9]+$ ]] || die "$lock: omarchy_tag (vN.N.N) or tinkero_rev (a number) is malformed: $tag, $rev"
+# The tinkero package this checkout's lock names: what the COPR must have built for the run to mean anything.
+expect_nvr=tinkero-${tag#v}-$rev.fc$fedora.noarch
+all_stages="clone baseline install users session lock gnome reinstall remove"
 # The VM, as the 2F guide built it.
 memory=8192; vcpus=4; disk_gb=40
 graphics=spice,gl.enable=yes,listen=none
 if [[ -n $rendernode ]]; then graphics+=,rendernode=$rendernode; fi
 # Timeouts.
-base_wait=90   # minutes virt-install waits for cloud-init to power the base off
+base_wait=90        # minutes virt-install waits for cloud-init to power the base off
+ssh_wait=300        # seconds for the VM to answer SSH after a boot
+session_wait=180    # seconds for a session to come up after GDM's timed login
+guest_timeout=3600  # seconds for one guest command (install.sh downloads the package set)
+reboot_pause=20     # seconds between asking for a reboot and waiting for SSH again
+key_gap=0.2         # seconds between two typed keys
+lock_settle=3       # seconds PAM gets after a wrong password before the lock is asked
+lockout_wait=130    # seconds: unlock_time=120 of the wrapped variant, and a margin
+ssh_opts=(-n -i "$key" -p "$ssh_port" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR)
+scp_opts=(-i "$key" -P "$ssh_port" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
+# virsh send-key's names (the Linux key codes, its default code set) for what a password may hold.
+declare -A keymap=(
+  [a]=KEY_A [b]=KEY_B [c]=KEY_C [d]=KEY_D [e]=KEY_E [f]=KEY_F [g]=KEY_G [h]=KEY_H [i]=KEY_I
+  [j]=KEY_J [k]=KEY_K [l]=KEY_L [m]=KEY_M [n]=KEY_N [o]=KEY_O [p]=KEY_P [q]=KEY_Q [r]=KEY_R
+  [s]=KEY_S [t]=KEY_T [u]=KEY_U [v]=KEY_V [w]=KEY_W [x]=KEY_X [y]=KEY_Y [z]=KEY_Z
+  [0]=KEY_0 [1]=KEY_1 [2]=KEY_2 [3]=KEY_3 [4]=KEY_4 [5]=KEY_5 [6]=KEY_6 [7]=KEY_7 [8]=KEY_8 [9]=KEY_9
+)
 
 [[ $euid != 0 ]] || die "run as your own user, not as root: the VMs live under your own libvirt daemon ($uri)"
 [[ $user =~ ^[a-z][a-z0-9]*$ && $user2 =~ ^[a-z][a-z0-9]*$ && $user != "$user2" ]] || die "the two account names must differ and be lower-case letters and digits: $user, $user2"
-[[ $password =~ ^[a-z0-9]+$ && $password2 =~ ^[a-z0-9]+$ ]] || die "passwords must be lower-case letters and digits: virsh send-key types one key per character"
+[[ $password =~ ^[a-z0-9]+$ && $password2 =~ ^[a-z0-9]+$ && $wrong_password =~ ^[a-z0-9]+$ ]] || die "passwords must be lower-case letters and digits: virsh send-key types one key per character"
+[[ $wrong_password != "$password" ]] || die "TINKERO_SMOKE_WRONG_PASSWORD is the right password"
 [[ $ssh_port =~ ^[0-9]+$ ]] || die "TINKERO_SMOKE_SSH_PORT must be a number: $ssh_port"
+# The clone is the one thing this script ever removes (remove_clone), so its name is checked
+# here, before anything runs: it carries the prefix, and it is not a base.
+[[ $clone =~ ^tinkero-smoke[a-z0-9-]*$ && $clone != *base* && $clone != "$base" ]] || die "TINKERO_SMOKE_CLONE must start with tinkero-smoke and must not name a base: $clone"
 
 # --- host commands ---------------------------------------------------------------------------
 exec 3>&1   # a dry run's command lines go here, also from inside $(...)
@@ -82,10 +126,14 @@
   done
   echo "${s# }" >&3
 }
-# run CMD...: every host command that changes something goes through here.
+results=""   # this run's results directory, once main_run has created it
+log() { if [[ $dry != 1 && -n $results ]]; then printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" >> "$results/commands.log"; fi; }
+# run CMD...: every host command that changes something goes through here. During a run its
+# output is kept in host.log and shown on stderr, so that stdout stays the report.
 run() {
   if [[ $dry == 1 ]]; then show "$@"; return 0; fi
-  "$@"
+  log "$*"
+  if [[ -n $results ]]; then "$@" 2>&1 | tee -a "$results/host.log" >&2; else "$@"; fi
 }
 # probe DEFAULT CMD...: a host command that only asks. A dry run prints it and answers DEFAULT.
 probe() {
@@ -170,9 +218,358 @@
   say "the base $base is ready. It is never booted again: every run clones it"
 }
 
+# --- the report --------------------------------------------------------------------------------
+n=0; fails=0; stage=setup; lockout=0
+# emit LINE: a line of the report: stdout, and report.tap once the results directory exists.
+emit() {
+  echo "$1"
+  if [[ $dry != 1 && -n $results ]]; then echo "$1" >> "$results/report.tap"; fi
+}
+# tap ok|not_ok DESCRIPTION [DETAIL]: one numbered line. A dry run asserts nothing.
+tap() {
+  local l
+  if [[ $dry == 1 ]]; then return 0; fi
+  n=$((n + 1))
+  if [[ $1 == ok ]]; then emit "ok $n - $2"; return 0; fi
+  fails=$((fails + 1)); emit "not ok $n - $2"
+  if [[ -n ${3:-} ]]; then
+    while IFS= read -r l; do emit "#   $l"; done <<<"$3"
+  fi
+}
+# bail MESSAGE: the VM could not be built or reached. The report ends where it is; exit 2.
+bail() {
+  emit "Bail out! $*"
+  if [[ $dry != 1 && -n $results ]]; then emit "1..$n"; say "results: $results"; fi
+  exit 2
+}
+
+# --- the guest ---------------------------------------------------------------------------------
+# guest ARG...: every guest command goes through here: the guest script, over SSH, as the test user.
+guest() {
+  local s remote
+  printf -v s '%q ' "$@"
+  remote="TINKERO_SMOKE_USER2=$(printf '%q' "$user2") TINKERO_SMOKE_EXPECT_NVR=$(printf '%q' "$expect_nvr") bash vmcheck/guest ${s% }"
+  if [[ $dry == 1 ]]; then show timeout "$guest_timeout" ssh "${ssh_opts[@]}" "$user@localhost" "$remote"; return 0; fi
+  log "guest $*"
+  timeout "$guest_timeout" ssh "${ssh_opts[@]}" "$user@localhost" "$remote"
+}
+keep_output() {   # WHAT STATUS OUTPUT: into this stage's log
+  printf '== guest %s (exit %s)\n%s\n' "$1" "$2" "$3" >> "$results/stage-$stage.log"
+}
+# guest_do DESCRIPTION ARG...: one guest command, one line of the report; its status is the guest's.
+guest_do() {
+  local desc=$1 out rc=0; shift
+  if [[ $dry == 1 ]]; then guest "$@"; return 0; fi
+  out=$(guest "$@" 2>&1) || rc=$?
+  keep_output "$*" "$rc" "$out"
+  if ((rc == 0)); then
+    tap ok "$stage: $desc"
+  else
+    tap not_ok "$stage: $desc" "guest $* (exit $rc): $(tail -n 8 <<<"$out")"
+  fi
+  return "$rc"
+}
+# guest_check STAGE [ARG]: the guest's TAP lines, renumbered into the report under this stage's
+# name. A check that ends without its plan line, or with a status that is not 0 or 1, is a
+# failure of its own: nothing passes by not running.
+guest_check() {
+  local out rc=0 line planned=0
+  if [[ $dry == 1 ]]; then guest check "$@"; return 0; fi
+  out=$(guest check "$@" 2>&1) || rc=$?
+  keep_output "check $*" "$rc" "$out"
+  while IFS= read -r line; do
+    case $line in
+      "ok "*)     tap ok "$stage: ${line#ok * - }" ;;
+      "not ok "*) tap not_ok "$stage: ${line#not ok * - }" ;;
+      "#"*)       emit "$line" ;;
+      1..*)       planned=1 ;;
+      "")         ;;
+      *)          emit "# $line" ;;
+    esac
+  done <<<"$out"
+  if ((planned == 0 || rc > 1)); then
+    tap not_ok "$stage: guest check $* ran to its end" "exit $rc; its output is in stage-$stage.log"
+  fi
+}
+# guest_out DEFAULT ARG...: what a guest command prints. A dry run prints the command and answers DEFAULT.
+guest_out() {
+  local default=$1; shift
+  if [[ $dry == 1 ]]; then guest "$@"; echo "$default"; return 0; fi
+  guest "$@" 2>/dev/null || true
+}
+wait_ssh() {
+  local i
+  if [[ $dry == 1 ]]; then show ssh "${ssh_opts[@]}" "$user@localhost" true; return 0; fi
+  log "ssh ${ssh_opts[*]} $user@localhost true (every 5 s, up to ${ssh_wait}s)"
+  for ((i = 0; i * 5 < ssh_wait; i++)); do
+    if ssh "${ssh_opts[@]}" "$user@localhost" true 2>/dev/null; then return 0; fi
+    sleep 5
+  done
+  bail "the VM does not answer SSH on port $ssh_port after ${ssh_wait}s. Look at it with: virt-viewer --connect $uri --attach $clone"
+}
+# push_files: the guest script and the checkout's install.sh, into ~/vmcheck. Every run copies
+# them again, so a corrected script reaches a kept clone.
+push_files() {
+  run ssh "${ssh_opts[@]}" "$user@localhost" "mkdir -p vmcheck" || bail "could not create ~/vmcheck in the VM"
+  run scp "${scp_opts[@]}" "$here/guest" "$root/install.sh" "$user@localhost:vmcheck/" || bail "could not copy the guest script and install.sh into the VM"
+}
+# pull_results: the guest's files so far (snapshots, diffs, logs), after every stage.
+pull_results() {
+  run scp -r "${scp_opts[@]}" "$user@localhost:vmcheck" "$results/" || emit "# could not copy ~/vmcheck out of the VM after stage $stage"
+}
+pause() { if [[ $dry != 1 ]]; then sleep "$1"; fi; }
+send_key() { run virsh -c "$uri" send-key "$clone" "$@" || bail "virsh send-key failed: is $clone running?"; }
+# type_line TEXT: TEXT and Enter into whatever has the keyboard, one key per character. The first
+# key types nothing: it wakes a lock screen that has blanked the display.
+type_line() {
+  local i
+  send_key KEY_LEFTSHIFT; pause 1
+  for ((i = 0; i < ${#1}; i++)); do
+    send_key "${keymap[${1:i:1}]}"; pause "$key_gap"
+  done
+  send_key KEY_ENTER
+}
+# enter NAME: make NAME (gnome or tinkero) the running session, the way a user gets there: the
+# session is set in AccountsService, the running one is ended, and GDM's timed login starts the
+# next (design 6.3, D20). A dry run prints the longest path.
+enter() {
+  local kind
+  kind=$(guest_out other session-kind)
+  if [[ $kind == "$1" ]]; then return 0; fi
+  guest_do "GDM's next session is $1 (AccountsService)" session-next "$1" || return 1
+  if [[ $kind != none ]]; then
+    guest_do "the $kind session is ended" session-end terminate || return 1
+  fi
+  guest_do "the $1 session comes up through GDM's timed login" session-wait "$1" "$session_wait"
+}
+
+# --- the clone ---------------------------------------------------------------------------------
+# clone_disks_are_ours: every disk of the clone is a file directly under $state, as virt-clone
+# --file put it there. A domain with this name that somebody made by hand, its disk anywhere else,
+# is refused before anything is stopped: --remove-all-storage would delete that disk.
+clone_disks_are_ours() {
+  local out type dev src
+  if [[ $dry == 1 ]]; then show virsh -c "$uri" domblklist --details "$clone"; return 0; fi
+  out=$(virsh -c "$uri" domblklist --details "$clone" 2>&1) || die "could not read the disks of $clone: $out"
+  while read -r type dev _ src; do
+    case $type in Type|---*|"") continue ;; esac
+    if [[ $src == - ]]; then continue; fi   # an empty CD-ROM drive
+    [[ $type == file && $src == "${state%/}"/* && ${src#"${state%/}"/} != */* && ${src#"${state%/}"/} != .. ]] \
+      || die "refusing to remove '$clone': its disk '$src' (a $type $dev) is not a file directly under $state, so this script did not create it. Remove the domain yourself if it is yours"
+  done <<<"$out"
+}
+# remove_clone: the one place this script destroys anything, and it does so through libvirt: the
+# clone it made itself, by name. Never the base, never a path.
+remove_clone() {
+  [[ $clone == tinkero-smoke* && $clone != *base* && $clone != "$base" ]] || die "refusing to remove '$clone': it is not a smoke-test clone"
+  clone_disks_are_ours
+  if [[ $(domain_state "$clone" running) == running ]]; then run virsh -c "$uri" destroy "$clone" || true; fi
+  run virsh -c "$uri" undefine "$clone" --nvram --remove-all-storage || bail "could not remove the clone $clone"
+}
+stage_clone() {
+  local disk=$state/$clone.qcow2
+  domain_exists 0 "$base" || bail "there is no base domain $base: run 'ci/vm-smoke/run base' first (docs/guides/vm-smoke.md)"
+  if domain_exists 0 "$clone"; then remove_clone; fi
+  if [[ $dry != 1 && -e $disk ]]; then
+    bail "$disk exists and no domain $clone owns it. This script removes nothing by path: delete that one file yourself and run again"
+  fi
+  run virt-clone --connect "$uri" --original "$base" --name "$clone" --file "$disk" || bail "virt-clone failed"
+  run virsh -c "$uri" start "$clone" || bail "the clone did not start"
+  wait_ssh
+  push_files
+}
+# attach: a run without the clone stage works on the clone an earlier run kept.
+attach() {
+  domain_exists 0 "$clone" || bail "there is no kept clone $clone: run without --stages, or put clone first in the list"
+  if [[ $(domain_state "$clone" running) != running ]]; then
+    run virsh -c "$uri" start "$clone" || bail "the clone did not start"
+  fi
+  wait_ssh
+  push_files
+}
+
+# --- the stages (design 6.1) ---------------------------------------------------------------------
+stage_baseline() {
+  enter gnome || return 0
+  guest_do "the dark appearance and the canary key are set" step baseline || true
+  guest_do "snapshot 0-baseline taken" snap 0-baseline || true
+  guest_check baseline
+  guest_do "lingering is on" step linger-on || true
+}
+stage_install() {
+  enter gnome || return 0
+  guest_do "install.sh --yes from the checkout exits 0" step install || true
+  guest_do "snapshot 0b-installed taken" snap 0b-installed || true
+  guest_check install
+  guest_do "the snapshot diff against the baseline is clean: installing changed nothing GNOME sees" diff-snap 0-baseline 0b-installed || true
+}
+stage_users() {
+  guest_do "the second account has dotfiles of its own" step users || return 0
+  guest_check users
+}
+stage_session() {
+  local st
+  guest_do "GDM's next session is tinkero (AccountsService)" session-next tinkero || return 0
+  # A reboot, not a logout: the lock rounds need a boot on which nothing has run faillock as
+  # root (guide, section 3). The connection drops with it, so the status means nothing.
+  run ssh "${ssh_opts[@]}" "$user@localhost" "sudo systemctl reboot" || true
+  pause "$reboot_pause"
+  wait_ssh
+  guest_do "after a reboot GDM's timed login starts the Tinkero session" session-wait tinkero "$session_wait" || return 0
+  guest_check session
+  send_key KEY_POWER; pause 3
+  st=$(domain_state "$clone" running)
+  if [[ $st == running ]]; then
+    tap ok "$stage: the power key leaves the VM running"
+  else
+    tap not_ok "$stage: the power key leaves the VM running" "virsh domstate says: $st"
+  fi
+  guest_check power-key
+}
+# ensure_unlocked: a round that left the lock up must not take the next ones with it. The guide's
+# escape hatch: clear the tally and type the right password once more; if the lock still stands,
+# end the session, so that GDM is back for the stages that follow.
+ensure_unlocked() {
+  if [[ $dry == 1 ]]; then return 0; fi
+  if guest lock-wait unlocked 2 >/dev/null 2>&1; then return 0; fi
+  emit "# the lock is still up: clearing the tally and typing the right password once more"
+  guest lock-reset >/dev/null 2>&1 || true
+  type_line "$password"
+  if guest lock-wait unlocked 30 >/dev/null 2>&1; then return 0; fi
+  tap not_ok "$stage: the lock could be cleared for the next round" "it still stands after a tally reset and the right password; the session is ended so that GDM is back"
+  guest session-end terminate >/dev/null 2>&1 || true
+  return 1
+}
+wrong_passwords() {   # LABEL COUNT
+  local i
+  for ((i = 1; i <= $2; i++)); do
+    type_line "$wrong_password"; pause "$lock_settle"
+    guest_do "$1: after wrong password $i of $2 the lock is up and idle" lock-wait idle 30 || true
+  done
+}
+# lock_rounds VARIANT FIRST SECOND: the guide's pair of rounds on one PAM variant: the right
+# password first, then two wrong ones counted once each and cleared by the unlock.
+lock_rounds() {
+  local a="round $2 ($1)" b="round $3 ($1)"
+  if guest_do "$a: the lock comes up" lock; then
+    type_line "$password"
+    guest_do "$a: the right password unlocks on the first try" lock-wait unlocked 30 || true
+  fi
+  ensure_unlocked || return 1
+  if guest_do "$b: the lock comes up" lock; then
+    wrong_passwords "$b" 2
+    guest_check lock-failures 2
+    type_line "$password"
+    guest_do "$b: the right password then unlocks" lock-wait unlocked 30 || true
+    guest_check lock-clear
+  fi
+  ensure_unlocked
+}
+# lock_lockout: the guide's optional round 3, on the wrapped variant: ten failures lock the
+# account, the right password is refused, and unlock_time later it unlocks and clears the tally.
+lock_lockout() {
+  local a="round 3 (wrapped)"
+  if guest_do "$a: the lock comes up" lock; then
+    wrong_passwords "$a" 10
+    guest_check lock-failures 10
+    type_line "$password"; pause "$lock_settle"
+    guest_do "$a: after the right password during the lockout the lock is still up and idle" lock-wait idle 30 || true
+    pause "$lockout_wait"
+    type_line "$password"
+    guest_do "$a: two minutes later the right password unlocks" lock-wait unlocked 30 || true
+    guest_check lock-clear
+  fi
+  ensure_unlocked
+}
+stage_lock() {
+  enter tinkero || return 0
+  lock_rounds wrapped 1 2 || return 0
+  if ((lockout)); then lock_lockout || return 0; fi
+  guest_check lock-journal
+  # From here the host is on with-faillock; pam-wrapped puts it back whatever the rounds do.
+  guest_check pam-plain
+  if lock_rounds plain 4 5; then guest_check lock-journal; fi
+  guest_check pam-wrapped
+}
+stage_gnome() {
+  local cycle way name
+  for cycle in menu:1-menu-logout terminate:2-terminate kill:3-kill; do
+    way=${cycle%%:*}; name=${cycle#*:}
+    enter tinkero || return 0
+    guest_check theme
+    guest_do "cycle $name: GDM's next session is gnome (AccountsService)" session-next gnome || continue
+    guest_do "cycle $name: the Tinkero session is ended ($way)" session-end "$way" || continue
+    guest_do "cycle $name: GNOME comes up through GDM's timed login" session-wait gnome "$session_wait" || continue
+    guest_do "cycle $name: snapshot taken" snap "$name" || continue
+    guest_do "cycle $name: the snapshot diff against the baseline is clean" diff-snap 0-baseline "$name" || true
+    guest_check gnome "$name"
+  done
+  guest_do "cycles 1 and 2 left the same in GNOME's database where the session writes" diff-snap 1-menu-logout 2-terminate || true
+  guest_do "cycles 1 and 3 too" diff-snap 1-menu-logout 3-kill || true
+}
+stage_reinstall() {
+  enter gnome || return 0
+  guest_do "the second install.sh --yes exits 0" step reinstall || true
+  guest_check reinstall
+  guest_do "snapshot 5-reinstalled taken" snap 5-reinstalled || return 0
+  guest_do "the snapshot diff against the baseline is clean" diff-snap 0-baseline 5-reinstalled || true
+}
+stage_remove() {
+  enter gnome || return 0
+  guest_do "the guide's removal commands ran" step remove || true
+  guest_do "snapshot 4-removed taken" snap 4-removed || true
+  guest_check remove
+  guest_do "the snapshot diff against the baseline is clean, ~/.bashrc included" diff-snap 0-baseline 4-removed || true
+}
+
+main_run() {
+  local list="" keep=0 s
+  while (($#)); do
+    case $1 in
+      --stages)  [[ -n ${2:-} ]] || die "--stages needs a comma-separated list"
+                 list=${2//,/ }; shift ;;
+      --keep)    keep=1 ;;
+      --lockout) lockout=1 ;;
+      -h|--help) usage; exit 0 ;;
+      *)         usage >&2; exit 2 ;;
+    esac
+    shift
+  done
+  if [[ -n $list ]]; then keep=1; else list=$all_stages; fi
+  [[ " $list " != *" clone "* || $list == clone || $list == "clone "* ]] || die "clone must come first in --stages: it replaces the VM that the stages before it would have used"
+  for s in $list; do
+    [[ " $all_stages " == *" $s "* ]] || die "unknown stage '$s'. Stages: ${all_stages// /, }; the base is built by 'run base'"
+  done
+  # The results directory is named by the moment the run starts (a dry run creates none).
+  if [[ $dry == 1 ]]; then
+    results=$results_root/dry-run
+  else
+    s=$results_root/$(date -u +%Y%m%dT%H%M%SZ)
+    run mkdir -p "$s"; results=$s
+  fi
+  emit "# vm-smoke: $expect_nvr, base $base, clone $clone, stages: $list"
+  [[ " $list " == *" clone "* ]] || attach
+  for stage in $list; do
+    emit "# stage $stage"
+    "stage_$stage"
+    if [[ $stage != clone ]]; then pull_results; fi
+  done
+  stage=end
+  if ((keep == 0 && fails == 0)); then
+    remove_clone
+  else
+    say "the clone $clone is kept: virt-viewer --connect $uri --attach $clone; ssh -i $key -p $ssh_port $user@localhost. The next full run replaces it"
+  fi
+  if [[ $dry == 1 ]]; then exit 0; fi
+  emit "1..$n"
+  emit "# $((n - fails)) ok, $fails not ok, ${SECONDS}s"
+  say "results: $results"
+  if ((fails)); then exit 1; fi
+}
+
 case ${1:-} in
   base)      [[ $# == 1 ]] || { usage >&2; exit 2; }
              build_base ;;
   -h|--help) usage ;;
-  *)         usage >&2; exit 2 ;;
+  *)         main_run "$@" ;;
 esac
```

- [ ] **Step 3: `./dev vm-smoke`**

```diff
--- a/dev
+++ b/dev
@@ -7,6 +7,7 @@
 #   ./dev gates-at DIR   run the CI gates against an unpacked payload (CI: the binary RPM's)
 #   ./dev baseline   assemble, then rewrite the allowlists from the findings (review the diff!)
 #   ./dev spec       render tinkero.spec from the template and the lock
+#   ./dev vm-smoke [ARG...]   the VM smoke test on this host (ci/vm-smoke/run; docs/guides/vm-smoke.md)
 #   ./dev clean
 set -euo pipefail
 cd "$(dirname "${BASH_SOURCE[0]}")"
@@ -37,6 +38,7 @@
   gates-at) [[ -d ${2:-} ]] || { echo "usage: ./dev gates-at DIR" >&2; exit 2; }; payload=$2; gates ;;
   baseline) assemble; mkdir -p "$allow"; TINKERO_GATE_WRITE=1 gates ;;
   spec)     build/render-spec ;;
+  vm-smoke) shift; exec ci/vm-smoke/run "$@" ;;
   clean)    rm -rf .cache tinkero.spec ;;
-  *)        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
+  *)        sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
 esac
```

- [ ] **Step 4: Run the tests**

Run: `bash tests/test-vm-smoke.sh` Expected: `1..306`, no `not ok`.
Run: `TINKERO_EUID=1000 TINKERO_SMOKE_DRY_RUN=1 TINKERO_SMOKE_STATE=/nonexistent/state TINKERO_SMOKE_RESULTS=/nonexistent/results ./dev vm-smoke --stages clone,baseline` Expected: these 24 lines, with the checkout's path where the listing says `<checkout>` and the package the lock names at that time (`tinkero-4.0.4-3` once plan 3A has landed); nothing is created or called:

```
# vm-smoke: tinkero-4.0.4-2.fc44.noarch, base tinkero-smoke-base-f44, clone tinkero-smoke, stages: clone baseline
# stage clone
virsh -c qemu:///session dominfo tinkero-smoke-base-f44
virsh -c qemu:///session dominfo tinkero-smoke
virsh -c qemu:///session domblklist --details tinkero-smoke
virsh -c qemu:///session domstate tinkero-smoke
virsh -c qemu:///session destroy tinkero-smoke
virsh -c qemu:///session undefine tinkero-smoke --nvram --remove-all-storage
virt-clone --connect qemu:///session --original tinkero-smoke-base-f44 --name tinkero-smoke --file /nonexistent/state/tinkero-smoke.qcow2
virsh -c qemu:///session start tinkero-smoke
ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost true
ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'mkdir -p vmcheck'
scp -i /nonexistent/state/id_ed25519 -P 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR <checkout>/ci/vm-smoke/guest <checkout>/install.sh smoke@localhost:vmcheck/
# stage baseline
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest session-kind'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest session-next gnome'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest session-end terminate'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest session-wait gnome 180'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest step baseline'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest snap 0-baseline'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest check baseline'
timeout 3600 ssh -n -i /nonexistent/state/id_ed25519 -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o ServerAliveInterval=15 -o LogLevel=ERROR smoke@localhost 'TINKERO_SMOKE_USER2=smoke2 TINKERO_SMOKE_EXPECT_NVR=tinkero-4.0.4-2.fc44.noarch bash vmcheck/guest step linger-on'
scp -r -i /nonexistent/state/id_ed25519 -P 2222 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR smoke@localhost:vmcheck /nonexistent/results/dry-run/
vm-smoke: the clone tinkero-smoke is kept: virt-viewer --connect qemu:///session --attach tinkero-smoke; ssh -i /nonexistent/state/id_ed25519 -p 2222 smoke@localhost. The next full run replaces it
```

Run: `TINKERO_EUID=1000 TINKERO_SMOKE_DRY_RUN=1 TINKERO_SMOKE_STATE=/nonexistent/state TINKERO_SMOKE_RESULTS=/nonexistent/results ./dev vm-smoke 2>&1 | grep -cE '(^|[ /])(rm|rmdir|unlink|shred)( |$)'` Expected: `0`.
Run: `shellcheck -x -e SC1090,SC1091 dev ci/vm-smoke/run ci/vm-smoke/guest tests/test-vm-smoke.sh` Expected: no output.
Run: `./dev check` Expected: green, `# tests/test-vm-smoke.sh` at `1..306` (the whole suite was not measured at planning time: the planning session ran under a no-delete rule and did not execute tests that delete files; the implementer measures it).
Do not run `./dev vm-smoke` without `TINKERO_SMOKE_DRY_RUN=1` in an agent session: it would try to reach libvirt. Task 5 is the first real run.

- [ ] **Step 5: Commit**

```bash
git add ci/vm-smoke/run dev tests/test-vm-smoke.sh
git commit -m "ci: the VM smoke test's stages: clone, GDM sessions, the lock typed with send-key, the report (plan 3D)"
```

**Verification for the issue:** `bash tests/test-vm-smoke.sh` at `1..306`; the two dry runs of Step 4; `grep -v '^[[:space:]]*#' ci/vm-smoke/run | grep -cE '(^|[^[:alnum:]_.-])(rm|rmdir|unlink|shred)([[:space:]]|$)'` prints `0`; ShellCheck clean; CI green.

---

### Task 4: Docs

**Files:**
- Create: `docs/guides/vm-smoke.md`
- Modify: `docs/guides/phase-2f-vm-check.md` (a pointer under the title), `docs/superpowers/specs/2026-09-17-tinkero-design.md` (status line, 4.7, 7, 8 item 6, 12), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (the 3D row, a "What executing 3D added to the queue" section), `docs/guides/workflow.md` ("Where the build is", "Rules for agent sessions"), `CLAUDE.md` (the conventions paragraph)

**Interfaces:**
- Consumes: Tasks 1 to 3 as built (names, options, files, exit codes); the Phase 3 design's D17 to D20 and section 6.5.
- Produces: the guide Task 5 follows; a master spec that says what the smoke test is and where it runs.

Every edit below is an exact replacement: find the quoted text, replace it with the block. Each quoted string was checked with `grep -cF` against the repository on 2026-10-01 and occurs once in its file. Plans 3A to 3C edit the same documents before this one lands: where a quoted sentence has been reworded by then, apply the change to the sentence as it is, keeping what the other plan put there.

- [ ] **Step 1: The guide**

Create `docs/guides/vm-smoke.md` with exactly this content (`2026-10-XX` is the date the branch is pushed):

````markdown
# VM smoke test: the packaged desktop on a clean Fedora, unattended

`./dev vm-smoke` installs Tinkero from the COPR into a throwaway Fedora VM on your own machine, logs in and out of it through GDM, locks and unlocks it, and removes it again, checking at each step what `docs/guides/phase-2f-vm-check.md` checks by hand. It is the release gate of the Phase 3 design (`docs/superpowers/specs/2026-10-01-phase-3-maintenance-release-design.md`, section 6, decisions D17 to D20): it runs on the packager's host after the COPR build and before the `release` workflow, whose `smoke` input names the record of the run.

**Status: written 2026-10-XX with plan 3D; not yet executed.** No agent session has libvirt, so the scripts were tested without a VM (`tests/test-vm-smoke.sh`: the guest script against stub commands, the driver in dry-run mode). The first run is plan 3D's Task 5. Record every command that had to change on that run's issue, as #27 and #37 did for the manual guide; those corrections are part of the result.

## 1. Prerequisites and the one-time host setup

The host is the one the 2F guide used: a Fedora machine with an Intel or AMD GPU (virgl needs it; on an Optimus laptop set `TINKERO_SMOKE_RENDERNODE`, see section 2), about 20 GiB of free disk, 8 GiB of memory for the VM, and a network connection. Everything runs as your own user under the per-user libvirt daemon (`qemu:///session`); nothing here needs `sudo` after the packages are installed, and the script refuses to run as root.

```bash
sudo dnf install @virtualization virt-install virt-viewer qemu-img passt openssh-clients curl     # once per host
```

The COPR must hold the `tinkero` build this checkout's `upstream.lock` names (`tinkero-<tag without v>-<tinkero_rev>.fc<fedora>`): the `install` stage fails on any other build, because a smoke record is only worth citing for the package being released. Run the test from a checkout of the commit that was built.

Build the base VM once:

```bash
TINKERO_SMOKE_DRY_RUN=1 ./dev vm-smoke base     # prints what it would do, changes nothing
./dev vm-smoke base
```

It does, in this order, and nothing else:

1. creates `~/.cache/tinkero-smoke/` and, in it, an SSH key pair used only for these VMs (`id_ed25519`);
2. downloads the Fedora Cloud Base image named in `ci/vm-smoke/image.lock` (0.6 GiB) into that directory and refuses to use it unless its sha256 is the pinned one;
3. writes `user-data` there from `ci/vm-smoke/cloud-init.yaml` (two accounts, the key, Workstation's package set, GDM with a five-second timed login, sshd, and the marker file `/etc/tinkero-smoke-vm` that the guest script requires: see section 4);
4. copies the image to `tinkero-smoke-base-f44.qcow2`, grows it to 40 GiB (sparse), and runs `virt-install --import --cloud-init` on it with the 2F guide's graphics and its passt port forward (host port 2222, bound to 127.0.0.1 only, to the guest's sshd);
5. waits, up to 90 minutes, until cloud-init has installed everything and powered the VM off.

`virt-viewer --connect qemu:///session --attach tinkero-smoke-base-f44` shows it working (a text console; the desktop only starts in the clones). If you have `cloud-init` on the host, `cloud-init schema --config-file ~/.cache/tinkero-smoke/user-data` checks the rendered file before the VM is built (it printed "Valid schema" with cloud-init 26.1 when the plan was written). The base is never booted again; every run clones it. Building it again is refused while the domain exists, and also when a file named `~/.cache/tinkero-smoke/tinkero-smoke-base-f44.qcow2` is there with no domain owning it (the script overwrites no disk it did not just create: move that file aside with `mv` and run again): see "Removing the base" in section 4.

## 2. Running it

```bash
./dev vm-smoke                    # every stage on a fresh clone; exit 0 when every line is ok
```

Nobody needs to watch. `virt-viewer --connect qemu:///session --attach tinkero-smoke` shows the VM; do not type or click in the viewer while the `lock` stage runs, the keys it sends go to whatever has the keyboard. A run is expected to take about half an hour (the design's estimate; the first run records the real figure), most of it `dnf install`.

The stages, in order (design 6.1):

| Stage | Does | Needs, on a kept clone |
|---|---|---|
| `clone` | removes the previous clone, clones the base, boots it, waits for SSH, copies `ci/vm-smoke/guest` and the checkout's `install.sh` into `~/vmcheck` | the base |
| `baseline` | GNOME through GDM's timed login; sets Dark and the canary key; snapshot `0-baseline`; turns lingering on | a clone without Tinkero |
| `install` | `install.sh --yes` from inside the GNOME session; the guide's post-install checks; snapshot `0b-installed` against the baseline | `baseline` |
| `users` | gives the second account three dotfiles of its own; `tinkero-provision --plan` must call them conflicts and a run must leave them byte for byte | `install` |
| `session` | reboots into the Tinkero session through GDM; the guide's section 3 checks, the menu's guard canary, `tinkero-status`, the power key | `install` |
| `lock` | rounds 1, 2, 4 and 5 of the guide, typed with `virsh send-key`; `--lockout` adds round 3 | `session`, in the same boot |
| `gnome` | the three cycles: two theme switches and a text size in Tinkero, the session ended by the menu's logout, `loginctl terminate-session`, a killed compositor; each GNOME snapshot against the baseline | `install`, `baseline` |
| `reinstall` | a second `install.sh --yes` that must change nothing | `install` |
| `remove` | `tinkero-provision --remove`, `dnf remove`, `dnf copr remove`; snapshot `4-removed` against the baseline | `install`, `baseline` |

Options:

- `--stages LIST` (comma separated) runs only those stages, on the clone the last run left, and keeps it afterwards. A list that starts with `clone` starts from a fresh clone. This is how a failed stage is run again after a fix: every run copies the guest script and `install.sh` into the VM again.
- `--keep` keeps the clone after a full run that passed. A run with a failure always keeps it, and says how to look at it; the next full run replaces it.
- `--lockout` adds the guide's round 3 (ten wrong passwords, the two-minute wait) to the `lock` stage.
- `TINKERO_SMOKE_DRY_RUN=1` prints every host command of the chosen stages instead of running it.

After the `gnome` stage the clone's next Tinkero login starts in Hyprland Safe Mode (the third cycle kills the compositor; spec 4.11), so `session` and `lock` cannot be run again on that clone: start from `clone`.

Environment, every one optional:

| Variable | Default | Meaning |
|---|---|---|
| `TINKERO_SMOKE_STATE` | `${XDG_CACHE_HOME:-~/.cache}/tinkero-smoke` | the image, the key, `user-data`, the base's and the clone's disks |
| `TINKERO_SMOKE_RESULTS` | `.cache/vm-smoke` in the checkout | where each run's results directory is created |
| `TINKERO_SMOKE_BASE` | `tinkero-smoke-base-f<fedora>` | the domain to clone; set it to use a base built by hand (section 5) |
| `TINKERO_SMOKE_CLONE` | `tinkero-smoke` | the clone's name; it must start with `tinkero-smoke` and must not name a base |
| `TINKERO_SMOKE_USER`, `TINKERO_SMOKE_PASSWORD` | `smoke`, `tinkero1` | the test account; the password is lower-case letters and digits, because each character is typed as one key |
| `TINKERO_SMOKE_USER2`, `TINKERO_SMOKE_PASSWORD2` | `smoke2`, `tinkero2` | the account with dotfiles of its own |
| `TINKERO_SMOKE_WRONG_PASSWORD` | `wrong1` | what the `lock` stage types as a wrong password |
| `TINKERO_SMOKE_SSH_PORT` | `2222` | the host port forwarded to the guest's sshd; it is fixed in the base when the base is built |
| `TINKERO_SMOKE_RENDERNODE` | none | a `/dev/dri/by-path/...-render` node for virgl; on the Phase 0 laptop `/dev/dri/by-path/pci-0000:00:02.0-render` (the Intel GPU); it is fixed in the base when the base is built |
| `TINKERO_SMOKE_URI` | `qemu:///session` | the libvirt URI |

The names and timeouts that are not in this table are variables at the top of `ci/vm-smoke/run`.

## 3. Reading the results

Each run writes `.cache/vm-smoke/<UTC timestamp>/` (git ignores `.cache/`):

| File | Content |
|---|---|
| `report.tap` | the report: one `ok N - <stage>: ...` or `not ok N - ...` line per assertion, `#` lines with the detail of a failure and with recorded facts, `1..N` and a tally with the duration at the end. It is also the run's stdout |
| `commands.log` | every host command and every guest call, with the time |
| `host.log` | the output of the host commands (`virt-clone`, `virsh`, `scp`) |
| `stage-<name>.log` | the full output of every guest call of that stage |
| `vmcheck/` | the guest's own files, copied out after every stage: `snap-*.txt` and `userdb-*.ini` (the snapshots), `diff-*.txt` and `userdb-diff-*.txt` (their diffs), `install.txt` and `install-2.txt` (the two install logs), `status.txt` (`tinkero-status`), `lock.txt` (every `faillock` reading), `lock-journal.txt` and `avc.txt` (the user journal's PAM and Quickshell lines, the AVC search), `session-end-*.txt` (the journal of `tinkero-session-end` after each cycle), `remove.txt`, `users-manifest.tsv` and `users-provision.txt` (the second account) |

Exit status: 0 when every line is `ok`; 1 when at least one is not; 2 when the VM could not be built or reached (the report then ends with a `Bail out!` line) or the command line was wrong.

A snapshot diff is "clean" by the rule of the 2F guide ("Reading a diff"), which `ci/vm-smoke/guest diff-snap` implements: every section of the two snapshots is identical except, possibly, the `dconf user db` checksum; and whatever moved the checksum, nothing under `[org/gnome/desktop/interface]` differs between the two dumps of GNOME's own database. GNOME's own first-use writes (Ptyxis' window size, Nautilus' migration flag and the like) move the checksum and are named in the report line's stage log, not counted as a leak.

When a line fails, read its `#` detail, then the stage's log, then the file under `vmcheck/` it came from. The clone is kept: `ssh -i ~/.cache/tinkero-smoke/id_ed25519 -p 2222 smoke@localhost` reaches it, and `./dev vm-smoke --stages <stage>` runs the stage again.

## 4. What it writes and removes on your host

- Files: only under the two directories of section 2's table (`~/.cache/tinkero-smoke/` and `.cache/vm-smoke/` in the checkout). libvirt keeps the two domains' definitions and UEFI variables in its own directories.
- The scripts contain no `rm`. A stale partial download or the rendered `user-data` is overwritten; a disk file the run did not just create is never overwritten (a base disk or a clone disk that is already there stops the run with the file's name). A results directory is never removed.
- The one thing the run removes is the clone it created, through libvirt and by name: `virsh destroy tinkero-smoke` and `virsh undefine tinkero-smoke --nvram --remove-all-storage`, at the start of the next full run and at the end of a full run that passed. The name is checked first: it must start with `tinkero-smoke` and must not be a base. Its disks are checked too, with `virsh domblklist --details`: every one must be a file directly under `~/.cache/tinkero-smoke/` (where `virt-clone --file` puts them), or the run refuses, naming the disk, before it stops or removes anything. A domain with that name that you made by hand, with its disk somewhere else, is therefore never touched; remove it yourself or choose another `TINKERO_SMOKE_CLONE`.
- The guest script (`ci/vm-smoke/guest`) deletes nothing either, and refuses to run (exit 2, "this script is for the smoke-test VM only") on any machine that lacks the marker file `/etc/tinkero-smoke-vm`, which cloud-init writes into the VM. A hand-built base (section 5) needs that file too: `echo smoke-test VM | sudo tee /etc/tinkero-smoke-vm`.
- The base and its disk are never removed by the script.

**Removing the base** (to rebuild it after a Fedora release, an `image.lock` change or a failed build), by hand:

```bash
virsh -c qemu:///session undefine tinkero-smoke-base-f44 --nvram --remove-all-storage
```

That removes the domain and `~/.cache/tinkero-smoke/tinkero-smoke-base-f44.qcow2`. The downloaded image and the key stay and are reused. To remove everything the test ever put on the host, undefine the clone the same way if one is left, then delete `~/.cache/tinkero-smoke/` and `.cache/vm-smoke/` yourself.

## 5. What is unproven until the first run, and the fallbacks

The design (6.5) names three mechanisms that no test without a VM can prove. Each has a fallback that keeps the rest unattended.

1. **The base from the Cloud image.** Symptom: `./dev vm-smoke base` fails, or the clone never answers SSH, or `baseline` fails on GDM, SELinux or authselect. Fallback: build the base by hand as the 2F guide's section 1 does (the clean checkpoint), and give it what the stages rely on: `sudo systemctl enable sshd`, the passt port forward of the guide's "Optional: SSH" paragraph, `~/.cache/tinkero-smoke/id_ed25519.pub` in the account's `~/.ssh/authorized_keys` (make the key with `ssh-keygen -t ed25519 -N '' -f ~/.cache/tinkero-smoke/id_ed25519`), a sudoers file `<user> ALL=(ALL) NOPASSWD:ALL`, the marker file `/etc/tinkero-smoke-vm` (any content), a password of lower-case letters and digits, `TimedLoginEnable=true`, `TimedLogin=<user>` and `TimedLoginDelay=5` under `[daemon]` in `/etc/gdm/custom.conf`, and a second account. Then run with `TINKERO_SMOKE_BASE=<that domain> TINKERO_SMOKE_USER=<user> TINKERO_SMOKE_PASSWORD=<password> TINKERO_SMOKE_USER2=<second>`.
2. **GDM's timed login with the AccountsService session switch.** Symptom: the `session-wait` lines fail (the wrong session, or none, comes up after a session end). Fallback: the `gnome` stage is dropped from the automatic run and stays the 2F guide's section 4. `session` and `lock` still run, half attended: when the `session` stage waits after its reboot, pick Tinkero at GDM in the viewer and log in by hand within three minutes.
3. **Typing at the lock with `virsh send-key`.** Symptom: the lock comes up and "the right password unlocks" fails while the guide's manual round passes. Fallback: the `lock` stage is dropped and stays the 2F guide's section 3.

A stage that falls back is removed from the default list: delete its name from `all_stages` at the top of `ci/vm-smoke/run` (and from the list in the usage comment and in `tests/test-vm-smoke.sh`'s "every stage" case), and add a row to the table at the end of this guide with the reason and the issue. It can still be asked for with `--stages`.

Smaller things the first run is the first contact with, each one line to correct in the script named:

- the `virt-install` spelling of the passt port forward and `--boot uefi` with the Cloud image (`build_base` in `ci/vm-smoke/run`). If `virt-install` refuses the `--network` option, drop its `backend.type` and `portForward0` parts and add the forward with `virsh edit`, as the 2F guide does (keep `address='127.0.0.1'` on the `<portForward>` element: the build binds the forward to localhost only, and `ss -ltn` should show `127.0.0.1:2222`);
- `dnf -y install --allowerasing @workstation-product-environment` on the Cloud image (`ci/vm-smoke/cloud-init.yaml`);
- reading the tally with `faillock --user` on a `with-faillock` host (rounds 4 and 5): the guest reads it without `sudo`, because sudo's own account phase runs `pam_faillock` there and could clear the tally before it is printed (the 2F guide used `sudo faillock` with a password and saw the failures, so both may work). The tally file belongs to the user (`0660 user root`); if the unprivileged read is refused, put `sudo` back in `tally` in `ci/vm-smoke/guest` and read the first round's count carefully;
- the menu's guard canary and the power menu's layer name (`menu_guards` and `check_power_key` in the guest script);
- `omarchy-theme-set` without a person: on a VM with a Chromium-family browser it raises a polkit dialog (#52; #56 removed it where none is installed, which is the base's case). If one appears, `check theme` fails after its 120 seconds instead of hanging;
- `install.sh` and the snapshots running inside a transient unit of the user manager (`in_session`).

## 6. What stays manual

- Section 5 of the 2F guide: the Milestone B lines that need eyes (the mark in the bar, About, the screensaver, the background switcher, the Learn row).
- The lock's on-screen failure counter, fingerprint unlock, suspend and resume: a VM has no reader and cannot enter S3 (bare metal).
- Hyprland's Safe Mode after the killed compositor: the test leaves the clone there and does not enter it.
- Any stage listed in the table below.

## 7. Recording a run

For a release, comment on the release's issue with: the checkout's commit, the COPR build ids of `tinkero` and `quickshell`, `report.tap` in full, the duration (its last line), and every command that had to change. The comment's URL is the `smoke` input of the `release` workflow (`docs/guides/release.md`). A failure is a new issue against the code that owns it; the run is repeated on the fix.

## Stages dropped from the automatic run

| Stage | Since | Reason | Issue |
|---|---|---|---|
| none | | | |
````

- [ ] **Step 2: The pointer in the 2F guide**

In `docs/guides/phase-2f-vm-check.md`, after the title line `# Phase 2F VM check: the packaged session on a clean Fedora 44` and its blank line, insert this paragraph and a blank line (the test in `tests/test-vm-smoke.sh` that compares the guest's snapshot sections with this guide's `snap.sh` keeps passing: nothing below the title changes):

```
**Automated since Phase 3:** `./dev vm-smoke` (`docs/guides/vm-smoke.md`) runs sections 1 to 4 and 6 of this guide unattended, with the same commands and the same "Reading a diff" rule. This guide stays the manual procedure for a stage that guide lists as dropped from the automatic run, the source its scripts are checked against, and the only procedure for section 5, the lines that need eyes.
```

- [ ] **Step 3: The master spec**

In `docs/superpowers/specs/2026-09-17-tinkero-design.md`:

1. Status line: replace `. Fedora 44 x86_64 is the first target.` with `; 3D (the VM smoke test) done 2026-10-XX, its first run on the operator's host being a manual issue. Fedora 44 x86_64 is the first target.`

2. 4.7, the bump bullet: replace `CI (section 8) must pass, including the VM smoke test, before the COPR build is tagged for release.` with `CI (section 8) must pass, and after the COPR build the VM smoke test (section 8, item 6: run from the packager's host against the COPR's packages, Phase 3 design D17) must pass before the release is cut.`

3. Section 7, the Phase 3 line: replace `the VM smoke test in CI,` with `the VM smoke test as a release gate run from the packager's host (Phase 3 design D17),`

4. Section 8, item 6: replace the whole item, `6. **VM smoke test** (Phase 3; manual before then). Fedora 44 image: run \`install.sh --yes\`, provision a fresh user and a user with pre-existing dotfiles, start the session headless, assert \`hyprctl configerrors\` is empty, \`omarchy-shell shell ping\` answers, the menu model loads with guards evaluated, zero AVC denials, and a second \`install.sh\` run changes nothing.` (written here with its backticks escaped; in the file they are plain), with:

```
6. **VM smoke test** (a release gate, not a push check: Phase 3 design D17; plan 3D). `./dev vm-smoke` on the packager's host, after the COPR build and before the release, whose `smoke` input names the run's record: it installs from the COPR, whose builds are post-merge, and it needs a VM with GL. On a clone of a Fedora 44 base built from the Cloud image with cloud-init (D18): `install.sh --yes` from the checkout, with the package the lock names; a second account with dotfiles of its own, which `tinkero-provision --plan` reports as conflicts and a run leaves byte for byte; the Tinkero session entered through GDM's timed login and uwsm, not headless (D20), where `hyprctl configerrors` is empty, `omarchy-shell shell ping` answers, the menu model loads and a canary guard is evaluated, the session units are active, the power key opens the menu and `tinkero-status` exits 0 or 1; the lock screen's rounds on both PAM variants, typed with `virsh send-key`, with zero AVC denials since boot; the GNOME invariant after each of the three session ends; a second `install.sh` run that changes nothing; removal. Its scripts are tested without a VM on every push (`tests/test-vm-smoke.sh`); `docs/guides/vm-smoke.md` is the procedure, and what it leaves manual.
```

5. Section 12: the `ci/` line is today `  ci/                              the gates (six), check-rpm, lint, VM smoke test` (plan 3C adds its two watches before `lint`). Remove `, VM smoke test` from its end, so that today's line becomes the first of these two, and add the second after it:

```
  ci/                              the gates (six), check-rpm, lint
  ci/vm-smoke/                     the VM smoke test: run (host side), guest, cloud-init.yaml, image.lock (section 8, item 6)
```

   after `  docs/guides/phase-0-spike.md     the VM spike procedure` add the line `  docs/guides/vm-smoke.md          the VM smoke test's procedure`; and replace `(check, lock, payload, gates, baseline, spec)` with `(check, lock, payload, gates, baseline, spec, vm-smoke)`.

- [ ] **Step 4: The roadmap**

In `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, the 3D row's Status cell: replace `**planned** 2026-10-01: \`2026-10-01-phase-3d-vm-smoke-test.md\`; awaiting approval. One orchestrated issue; the first run on the operator's host is a manual issue` (backticks plain in the file) with `**done** 2026-10-XX: \`2026-10-01-phase-3d-vm-smoke-test.md\`; the first run on the operator's host is its manual issue`.

Add this section immediately before the heading `## What the first real assembly found (inputs to 2B and 2C)` (after the "What executing 3A", "3B" and "3C" sections if they are there):

```
## What executing 3D added to the queue (2026-10-XX)

- **The first run (this plan's own issue):** `./dev vm-smoke base`, then `./dev vm-smoke`, on the operator's host, against the COPR's build of the package the lock names. Until it has passed, nothing in `ci/vm-smoke/` has met a real VM: the plan's tests cover the guest's logic against stubs and the driver's command sequence.
- **Three mechanisms it decides (design 6.5):** the Cloud image base (fallback `TINKERO_SMOKE_BASE`), GDM's timed login with the AccountsService session switch (fallback: `gnome` leaves the default stages), the lock typed with `virsh send-key` (fallback: `lock` leaves them). A stage that falls back is recorded in the table at the end of `docs/guides/vm-smoke.md`.
- **Smaller first contacts, each a one-line correction if wrong:** virt-install's spelling of the passt port forward; `--boot uefi` and `dnf install --allowerasing @workstation-product-environment` on the Cloud image; the faillock tally read without `sudo` on a `with-faillock` host; the menu's guard canary; `install.sh` run from a transient unit of the user manager.
- **The release (plan 3B):** the `smoke` input of the `release` workflow names the comment that records a passing run for the package being released; a manual pass of the 2F guide still qualifies (design D23).
- **Bump checklist:** `ci/vm-smoke/image.lock` moves with `upstream.lock`'s `fedora` (a test fails until it does), and the base is rebuilt by hand then; `active_units` and `session_sections` at the top of `ci/vm-smoke/guest` are the two lists a new upstream unit or a new gsettings write would extend.
- **Not built, by decision:** a smoke job on a hosted runner (D17: the driver takes its whole configuration from `TINKERO_SMOKE_*`, so it is one workflow file once software rendering is shown to carry the session); a way out of Hyprland's Safe Mode, so `session` and `lock` cannot be re-run on a clone after `gnome`; the lock's on-screen failure counter.
```

- [ ] **Step 5: The workflow guide and `CLAUDE.md`**

`docs/guides/workflow.md`, "Where the build is": add a new last bullet to that list. Today the list ends with the line `  in the roadmap's Phase 3 section. Its issues await approval.`; plan 3A rewords that line and plans 3B and 3C each add a bullet after it, so this one goes after plan 3C's:

```
- 3D (the VM smoke test) landed 2026-10-XX: `./dev vm-smoke`, run on the operator's host
  after the COPR build, is the release gate (`docs/guides/vm-smoke.md`). Its first run there
  is a manual issue.
```

If the Phase 3 bullet still counts 3D among the issues that await approval (plan 3A's wording is "the issues of 3B, 3C and 3D await approval"), take 3D out of that list.

`docs/guides/workflow.md`, "Rules for agent sessions": after the bullet that begins `- \`copr-build\` publishes to the user's COPR: trigger it only when the issue says so.` add:

```
- The VM smoke test (`./dev vm-smoke`) creates virtual machines on the operator's host. A
  session runs its hermetic tests (`tests/test-vm-smoke.sh`) and, at most, a dry run
  (`TINKERO_SMOKE_DRY_RUN=1`); it never runs the test itself.
```

`CLAUDE.md`, the conventions paragraph: after the sentence about `copr-build` (today it ends `publishes to the user's COPR and is triggered only when an issue says so.`; plan 3B extends it with `release`) add the sentence `\`./dev vm-smoke\` drives virtual machines on the operator's host (\`docs/guides/vm-smoke.md\`): a session runs \`tests/test-vm-smoke.sh\`, never the smoke test itself.` (backticks plain; re-wrap the paragraph at the file's width).

- [ ] **Step 6: Verify and commit**

Run: `./dev check` Expected: green (`tests/test-vm-smoke.sh` still at `1..306`: its comparison with the 2F guide's `snap.sh` reads below the new pointer; not measured at planning time, the implementer measures it).
Run: `git diff -U0 -- docs CLAUDE.md | grep '^+' | grep -c "$(printf '\342\200\224')"` Expected: `0` (no em dash added).
Run: `grep -c 'VM smoke test in CI\|manual before then' docs/superpowers/specs/2026-09-17-tinkero-design.md` Expected: `0`.
Run: `grep -c 'vm-smoke' docs/guides/phase-2f-vm-check.md docs/guides/workflow.md CLAUDE.md` Expected: each file at `1` or more.

```bash
git add docs CLAUDE.md
git commit -m "docs: 3D done, the VM smoke test: its guide, spec 8 item 6 as a release gate (D17), roadmap queue"
```

**Verification for the issue:** the four commands, CI green, and the reviewer reads the guide against `ci/vm-smoke/run`'s usage text and each spec edit against the Phase 3 design's D17, D18 and D20. The `2026-10-XX` placeholders become the date the branch is pushed; the merge date is the operator's.

---

### Task 5: The first run (manual, on the operator's host, closed by hand)

**Files:** none. The deliverable is a run and its record on the issue, one roadmap line, and a follow-up issue per correction (as #36 and #54 were for the manual guide).

**Interfaces:**
- Consumes: Tasks 1 to 4 on `master`; `docs/guides/vm-smoke.md`; the COPR build of the `tinkero` package the lock names (plan 3A's post-merge issue: `tinkero-4.0.4-3`), and of `quickshell` release 2 or later; a host with libvirt, an Intel or AMD GPU, and a checkout of the commit that was built.
- Produces: the evidence design 6.5 asks for (each of the three unproven mechanisms worked, or its fallback was taken), the run's duration, and, when it passes, a smoke record a release can cite (plan 3B's `smoke` input).

This task is run by the operator, not by an agent session: no session has libvirt. A first run that fails is expected to be cheap to correct: every name and timeout is a variable at the top of `ci/vm-smoke/run`, every stage is one function, `--stages` runs any stage again on the kept clone, and the results directory keeps every command's output.

- [ ] **Step 1: Before the base**

On the host, in the checkout at the commit the COPR built:

```bash
git log -1 --format=%H
sudo dnf install @virtualization virt-install virt-viewer qemu-img passt openssh-clients curl
dnf -q repoquery --repofrompath=t,https://download.copr.fedorainfracloud.org/results/dromero/tinkero/fedora-44-x86_64/ --repo=t --latest-limit=1 --queryformat '%{name}-%{version}-%{release}\n' tinkero quickshell
bash tests/test-vm-smoke.sh | tail -n 1
TINKERO_SMOKE_DRY_RUN=1 ./dev vm-smoke base
```

Expected: the repoquery prints the `tinkero` package of `upstream.lock` (`tinkero-<tag without v>-<tinkero_rev>.fc44`) and a `quickshell` whose release is at least the lock's `quickshell_release`; the test file ends with `1..306`; the dry run prints the base's eleven commands. If the COPR does not have that `tinkero` build, stop: the `install` stage would fail on it by design. On the Phase 0 laptop (Optimus), `export TINKERO_SMOKE_RENDERNODE=/dev/dri/by-path/pci-0000:00:02.0-render` before the next step.

- [ ] **Step 2: The base**

```bash
time ./dev vm-smoke base
```

Expected: it ends with `vm-smoke: the base tinkero-smoke-base-f44 is ready`, and `virsh -c qemu:///session domstate tinkero-smoke-base-f44` prints `shut off`. Record how long it took. If it fails: record the message and what `virt-viewer --connect qemu:///session --attach tinkero-smoke-base-f44` shows, correct the command in `build_base` or the line in `ci/vm-smoke/cloud-init.yaml`, remove the half-built base by hand (guide, "Removing the base") and run it again. If the Cloud image route cannot be made to work, take fallback 1 of the guide's section 5 (a base built by hand, `TINKERO_SMOKE_BASE`) and say so on the issue.

- [ ] **Step 3: The run**

```bash
./dev vm-smoke; echo "exit $?"
```

Do not type in the viewer while it runs. While it runs, `ss -ltn | grep 2222` in another terminal must show the forward on `127.0.0.1:2222` only (record it). Expected: exit 0, and `.cache/vm-smoke/<timestamp>/report.tap` ends with `1..N` and `# N ok, 0 not ok, <seconds>s`. On a failure the clone is kept: read the line's `#` detail and the stage's log, correct the script, and run that stage again with `./dev vm-smoke --stages <stage>` (start from `clone` again once `gnome` has run: the clone is then in Safe Mode for its next Tinkero login). Then run `./dev vm-smoke --lockout --stages clone,baseline,install,session,lock` once, for round 3.

- [ ] **Step 4: Record**

Comment on the issue with:

- the commit, the host (Fedora release, GPU), the COPR build ids of `tinkero` and `quickshell`;
- `report.tap` of the passing run in full, and its duration; the base build's duration;
- every command or line that had to change, as a diff, with the failing output that led to it;
- for each of the three mechanisms of design 6.5, one line: **the Cloud image base** (built by `run base`, or fallback 1), **the timed login with the AccountsService session switch** (every `session-wait` line ok, or `gnome` dropped), **typing at the lock** (rounds 1, 2, 4 and 5 ok, or `lock` dropped);
- the smaller first contacts of the guide's section 5 that needed a correction (the passt option, `--allowerasing`, the tally read without `sudo` under `with-faillock` (the first round's count of 2 is the evidence; if the unprivileged read is refused, put `sudo` back and read round 4's count with care), the guard canary, the power menu's layer, `install.sh` in a transient unit), and whether the one AVC denial Phase 0 saw at boot (`systemd-resolve`, not the desktop's) appeared: if it did, the `lock-journal` check needs the list of the desktop's processes that plan 3A's `selinux` check uses, and that is a follow-up issue, not a pass.

- [ ] **Step 5: Corrections and the verdict**

Each correction becomes a `size:small` follow-up issue against the script it touches, with the diff from Step 4 as its WHAT and `bash tests/test-vm-smoke.sh` plus the stage's re-run as its HOW TO VERIFY; a stage that fell back is removed from `all_stages` in the same issue, with its row in the guide's table. Then, in a small PR against this issue (`docs:` only), set the guide's status line to the run's date and verdict and add a line under the roadmap's "What executing 3D added to the queue" with the date, the verdict, the duration and the mechanisms' three results. Close the issue by hand when the operator accepts the verdict.

**Verification for the issue:** the comment of Step 4 with every item present, the follow-up issues filed, and the merged status and roadmap lines.

---

## Deviations

Filled by the PR that implements Tasks 1 to 4 (and by Task 5's issue for its own), per task, when anything deviated from this plan.

Recorded at planning time, where the plan builds something other than the Phase 3 design's letter (each is in the planning report for the operator):

- Design 6.1, `reinstall`: "an all-`current` plan" is built as "a plan that would write nothing: every line is `current` or `keep-user`, and the run reports 0 seeded, 0 updated, 0 deleted". After the `gnome` stage the seeded terminal configs carry the text size `omarchy-display-text-size 16` wrote, so tinkero-provision rightly calls them the user's.
- Design 6.1 names eight stages after `base`; the driver has a ninth, `clone`, so that `--stages` can say whether a run starts from a fresh clone or from the kept one.
- Design 6.2 calls `cloud-init.yaml` the user-data; it is a template with five placeholders, and the user-data is the rendered `user-data` under the state directory. It also carries three lines the design does not list (`--allowerasing`, `cloud-init.disabled`, `set-default graphical.target`), each needed for the base to work.
- Design 6.3 and the 2F guide clone with `virt-clone --auto-clone`; the driver passes `--file <state>/<clone>.qcow2`, so that every path it writes derives from the state variable.
- Design 6.1, `session`: "the menu model loads" is two checks, `omarchy-menu ping` and a guard canary written into the user's menu extension file and taken out again, because no IPC call at `v4.0.4` returns the guard results.
- Added to what design 6.3 says, none of it contradicting it (the safety requirements of the resumed planning session and the plan review): the driver binds the SSH forward to `127.0.0.1`, refuses to overwrite a base disk it did not create, checks the clone's disks with `virsh domblklist --details` before undefining it, and validates the lock values that reach a command line; the guest script refuses to run without the marker file `/etc/tinkero-smoke-vm` that `cloud-init.yaml` writes; the faillock tally is read without `sudo`; `--stages` refuses a `clone` that is not first.

## What this plan deliberately leaves out

- A smoke job on a GitHub-hosted runner (design D17), and a staging COPR: the build under test has already reached users.
- Section 5 of the 2F guide (the Milestone B lines that need eyes), the lock's on-screen failure counter, fingerprint unlock, suspend and resume, anything bare metal.
- Leaving Hyprland's Safe Mode after the killed compositor: the `gnome` stage's third cycle is the last thing a clone's Tinkero session does.
- A filter for AVC denials that are not the desktop's: the check is the guide's (`<no matches>` since boot), and Task 5 says what to do if the first run meets one.
- Fedora 45: `image.lock` and the base's name follow `upstream.lock`'s single `fedora` key (design section 10).
- Any change to the payload, to `install.sh`, to `bin/tinkero-provision` or to `tinkero-pam-sync`: the smoke test reads their output, and a wording change there is caught by `tests/test-vm-smoke.sh` only through its fixtures, by the first run after it for real.
- `cloud-init schema` as a test: CI's container has no cloud-init. The rendered template was validated once at planning time, and the guide says how to repeat it.

## Planning review record (2026-10-01)

The planning session had no libvirt and ran under a no-delete rule: it wrote the plan's code in a sandboxed copy of the repository (read-only file system outside the copy, no network, `rm` a no-op), and ran only the new test file. What that leaves measured and what it does not:

**Prototyped and run green in the sandbox:** `ci/vm-smoke/guest`, `ci/vm-smoke/run`, `ci/vm-smoke/cloud-init.yaml`, `ci/vm-smoke/image.lock`, the `dev` and `ci.yml` edits, and `tests/test-vm-smoke.sh`, task by task and test first. Measured tallies: Task 1 `1..153` (143 not ok before the guest existed); Task 2 `1..216` (53 not ok before the driver existed); Task 3 `1..306` (63 not ok against Task 2's driver); all green at the end. ShellCheck 0.11 with `-x -e SC1090,SC1091` is clean on `dev`, both scripts and the test file, and `bash -n` passes on each. The code blocks of this plan were generated from the prototype's files, not retyped. The rendered `user-data` of the stubbed base build passed `cloud-init schema` (cloud-init 26.1: "Valid schema"). The `dnf5 environment` and `dnf5-specs` man pages of dnf5 5.4.3 were read for the group install's spelling (`dnf install @<environment id>` selects an environment).

**Read, not run:** upstream's tree at `v4.0.4` for every command the guest calls: `shell/shell.qml` (the `shell` IPC target: `ping`, `call`, `listPlugins`), `shell/plugins/menu/Menu.qml` and `MenuModel.js` (`ping`, `refresh`, the guard batch, the user extension file), `shell/plugins/lock/Service.qml` (`lock isLocked`, `lock status` and its `authenticating` field, the five-second blank timer that the wake key answers), `bin/omarchy-hyprland-session-locked`, `bin/omarchy-system-logout` (`uwsm stop` from a background job two seconds later, which is why the guest keeps its unit alive), `default/hypr/bindings/utilities.lua` (`XF86PowerOff` toggles the `system` menu), `default/hypr/autostart.lua` (the whole environment is imported into the user manager), `bin/omarchy-display-text-size` (it rewrites seeded terminal configs: the `reinstall` deviation).

**Not measured at planning time; the implementer measures it:** `./dev check` as a whole and every pre-existing test file (the no-delete rule: those tests delete files as part of their work). In CI the suite runs as root in the `fedora:44` container, where the test file's stubs stand in for every host and guest tool; that run is the implementer's.

**Not measurable before Task 5:** everything that needs a VM. In particular: that Fedora's Cloud Base image boots under `--boot uefi` and takes the Workstation environment group with `--allowerasing`; that virt-install accepts the `--network user,...,backend.type=passt,portForward0...` spelling of the guide's hand-edited XML; that GDM's timed login starts the session AccountsService holds after every session end (the `SetSession` call was not checked against an installed AccountsService: this machine has none); that `virsh send-key` reaches the lock's password field and that a modifier key wakes it; that `systemd-run --user --wait --pipe` gives `install.sh` and the snapshot the environment they need; that `faillock --user`, run by the user without `sudo`, may read the tally on a `with-faillock` host (the tally file is `0660 user root`; the guide's runs used `sudo` with a password, and if the unprivileged read is refused `sudo` goes back into `tally`); the layer name of the power menu; the menu guard canary; `journalctl --user -u tinkero-session-end.service --since @<epoch>`; the run's duration. Each is named in the guide's section 5 with its correction or fallback, and Task 5 records the outcome.

**Review findings applied while writing:** the tests never delete a fixture file (cases that need an absent file use a second fixture home or root); a packaged-unit fixture that sat outside `/systemd/user/` made the `[Install]` check pass vacuously and was moved; the driver's dry run prints commands quoted only where the shell needs it, so the sequences can be read and compared; `lock-reset` was added to the guest so that the driver's recovery from a stuck lock stays behind the `guest` helper; the expected package comes from the lock in both the driver and the test, so plan 3A's `tinkero_rev` bump changes neither.

**Review.** An independent review of this plan found 0 Critical, 0 Important and 7 Minor findings, and the host-safety reading of `ci/vm-smoke/run` found no input that makes it touch what it did not create. What changed: (1) `build_base` stops when a disk file with the base's name exists and no domain owns it, instead of overwriting it with `cp`, and the tests that rebuilt over their own state directory use fresh ones; (2) the passt forward is bound to `127.0.0.1` (`portForward0.address`), and the guide and Task 5 say how to check it; (3) both scripts `export LC_ALL=C`, `fedora`, `omarchy_tag` and `tinkero_rev` are validated after `lock_get`, and the expected package name reaches the guest's command line through `printf %q`; (4) `--stages` with `clone` anywhere but first is refused with exit 2; (5) the guest reads the faillock tally without `sudo`, an absent snapshot section no longer passes as an empty one, and two report lines that claimed more than `lock-wait idle` shows were reworded; (6) `ci/vm-smoke/guest` refuses to run (exit 2) without `/etc/tinkero-smoke-vm`, which `cloud-init.yaml` writes, with a `TINKERO_SMOKE_MARKER` seam; (7) the menu canary is restored by a trap on `EXIT`, `HUP` and `TERM`, and a later `check` restores a canary a killed one left behind. The orchestrator's item: `remove_clone` reads `virsh domblklist --details` first and refuses unless every disk is a file directly under `TINKERO_SMOKE_STATE`, so that a hand-made domain with a `tinkero-smoke*` name never has its storage removed. Tallies after the round, measured in the sandbox: Task 1 `1..153`, Task 2 `1..216`, Task 3 `1..306`, all green; ShellCheck and `bash -n` clean.
