# Phase 2F: Session Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan runs through the issue loop** (`docs/guides/workflow.md`): dispatched only once Diego has applied `approved`, landed through a PR with green CI, tasks built serially on one branch in the order below. Tasks 8 and 9 are post-merge and have their own issues.

**Goal:** The `tinkero` RPM installs from the COPR and gives a session that locks and unlocks through the host's own PAM stack, keeps the power key for the shell, runs its user units only inside Tinkero, and reads and writes its own dconf database, so that a GNOME login on the same account is unchanged.

**Architecture:** Everything is payload data plus one small root tool. `build/assemble` strips the `[Install]` sections of the tree's user units (new step 3e) and installs Tinkero's unit, three drop-ins, a uwsm `env.d` file exporting `DCONF_PROFILE=tinkero`, two PAM variants and `tinkero-pam-sync`, which copies the variant the host's `password-auth` calls for into an RPM-owned `%ghost` file from `%posttrans`. Patch 0011 and two replacement scripts port the fingerprint commands to authselect. A new gate proves the unit properties on every build, CI builds and inspects the binary RPM, and `build/tinkero-copr` learns the `tinkero` package, whose first COPR build and a VM run of the GNOME invariant close the plan after the merge.

**Tech Stack:** bash, awk, systemd user units and drop-ins, uwsm `env.d`, Linux-PAM, `rpm`/`rpmbuild` (`%ghost`, `%posttrans`, `fflags`), `copr-cli` (through the existing workflow), the existing `tests/lib.sh` harness and gates; no Python in this plan.

**Spec:** `docs/superpowers/specs/2026-09-24-phase-2f-session-design.md` (the 2F design, derived from the master spec and binding for this plan; its section 8 lists the decisions D1 to D17 the operator may veto at approval) and `docs/superpowers/specs/2026-09-17-tinkero-design.md` sections 4.2, 4.3, 4.6, 4.8, 4.9, 5, 7 and 8. Audit: `docs/research/arch-coupling-audit.md` sections 4.3, 6 and 9. Phase 0: `docs/research/phase-0-findings.md` (Q2, Q3, Q5, Q7). Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`. Placeholder issue: #10.

## Global Constraints

- Upstream tree pinned by `upstream.lock` at `v4.0.4`; every count in this plan (7 units stripped, 14 `[Install]` sections before and 0 after, 7 listed units, 8 unit files, 367 commands (366 before), arch-leak 7 entries before and 6 after, 11 patches, 18 replacements) was measured against that tag on 2026-09-24 and the bump checklist re-measures it.
- `build/assemble TARBALL DEST` is the whole of `%install`; 2F adds step 3e (inside the tree, after branding) and lines in steps 5 and 6. `tinkero.spec.in` gets `%files` lines and one `%posttrans` scriptlet, no other logic.
- Data over code: Tinkero's units are files under `systemd/`, the env export is `session/uwsm-env.d/20-tinkero`, the PAM variants are files under `distro/fedora/pam/`, the session unit list is `provision/session-units.list`, the fingerprint package name is a row of `distro/fedora/pkgmap.tsv`.
- Nothing in 2F edits `bin/tinkero-provision` (2E's follow-ups landed in PR #22 and are the base this plan was measured on) or any upstream file except through patch 0011. The upstream tree is never copied into the repo.
- Gate allowlists only shrink: `ci/allow/arch-leak.allow` loses `usr/bin/omarchy-setup-security-fingerprint` in Task 4 and not before. The new session-units gate has no allowlist.
- Nothing in the payload may contain a token the arch-leak gate matches (`ci/gate-arch-leak`: `pacman`, `archlinux`, `limine`, `snapper`, `ufw`, ...).
- Scripts start with `#!/bin/bash` and `set -euo pipefail` (the replacement scripts follow their neighbours, see Task 4); ShellCheck clean with `-x -e SC1090,SC1091`; no `A && B || C` one-liners (SC2015); `# shellcheck disable=SC2016` above `printf` lines that write literal `$*` into stub scripts.
- Tests never use the network and never run a real package manager, `authselect`, `fprintd`, `systemctl`, `rpm` or `dconf`: every such command is a stub on `PATH`, and the seams are `TINKERO_ROOT`, `TINKERO_PAM_DIR`, `TINKERO_SHARE`, `TINKERO_EUID`, `TINKERO_PKG_LIB`, `TINKERO_PKGMAP`. No test writes outside its temporary directory; no test touches `/etc`.
- No em dashes in Tinkero's own prose. Attribution trailers on every commit per the session's rules. Land through a PR against the approved issue; never push master. `copr-build` is triggered only by Task 8's issue.
- Each task's PR includes its Deviations line in this plan's "## Deviations" section when anything deviated.

## Issue map

To be filed as three issues superseding placeholder #10 (which is then closed with a comment naming them). Tasks 1 to 7 are one orchestrated issue, built serially on one branch because they share `build/assemble`, `tests/test-assemble.sh`, `tinkero.spec.in`, `dev`, `.github/workflows/ci.yml` and the allowlist, and land as one PR. Task 8 is a post-merge issue `blocked by` the first and closed by hand (workflow guide, adaptation 1). Task 9 is a manual issue `blocked by` Task 8's. The `approved` label is Diego's.

| Task | Size | Area | WHAT | WHERE | HOW TO VERIFY |
|---|---|---|---|---|---|
| 1 Session wiring in the payload | medium | session | assemble step 3e strips `[Install]` inside the tree; Tinkero's inhibitor unit and three drop-ins; `20-tinkero` exports `DCONF_PROFILE`; the unit list gains the inhibitor | `build/assemble`, `systemd/**`, `session/uwsm-env.d/20-tinkero`, `provision/session-units.list`, `tinkero.spec.in`, `tests/fixtures/make-tree.sh`, `tests/test-assemble.sh` | `bash tests/test-assemble.sh` at `1..59`; real tree: `stripped [Install] from 7 unit(s)`, 0 `[Install]` left in both unit directories (14 before) |
| 2 The session-units gate | small | ci | `ci/gate-session-units`, no allowlist, the sixth gate of `./dev gates` | `ci/gate-session-units`, `dev`, `.github/workflows/ci.yml`, `tests/test-gates.sh` | `bash tests/test-gates.sh` at `1..79`; real tree: `PASS: session units (7 listed, 8 unit files, no [Install])` |
| 3 PAM variants and `tinkero-pam-sync` | medium | session | the two variants, the sync tool with `--variant` and `--check`, `%posttrans`, the two `%ghost` files, `install.sh` runs it | `distro/fedora/pam/*`, `distro/fedora/bin/tinkero-pam-sync`, `build/assemble`, `tinkero.spec.in`, `install.sh`, `.github/workflows/ci.yml`, `tests/test-pam-sync.sh`, `tests/test-assemble.sh`, `tests/test-render-spec.sh`, `tests/test-install.sh` | `bash tests/test-pam-sync.sh` at `1..42`; test-assemble `1..64`, test-render-spec `1..21`, test-install `1..33`; real tree: `assembled 367 commands` |
| 4 The fingerprint port | medium | session | patch 0011 to `omarchy-apply-lock`, the two fingerprint replacements, the `fprintd-pam` name-map row, `host.md`, the arch-leak allowlist shrinks, the menu's Remove > Fingerprint row regated | `patches/0011-*`, `patches/series`, `distro/fedora/replacements/omarchy-{setup,remove}-security-fingerprint`, `distro/fedora/pkgmap.tsv`, `distro/fedora/skills/host.md`, `ci/allow/arch-leak.allow`, `menu/overrides.jsonc`, `tests/test-replacements.sh` | `bash tests/test-replacements.sh` at `1..54`; `./dev gates` six `PASS`, arch-leak at 6 allowed; the patched script's three greps; menu: `3 replaced`, `ci/gate-name-map` still `PASS` |
| 5 The binary RPM in CI | small | ci | CI rebuilds the SRPM into the RPM, `ci/check-rpm` checks ghosts, scriptlet and payload, `./dev gates-at` runs the gates on it | `ci/check-rpm`, `tests/test-check-rpm.sh`, `dev`, `.github/workflows/ci.yml` | `bash tests/test-check-rpm.sh` at `1..16`; CI prints `PASS: rpm tinkero-4.0.4-1.fc44.noarch.rpm ...` and six gate `PASS` lines |
| 6 `tinkero` in the COPR tooling | small | build | `tinkero` is the last line of `build-order.txt`; `tinkero-copr` registers it from the root spec, webhook off | `distro/fedora/specs/build-order.txt`, `build/tinkero-copr`, `tests/test-copr.sh`, `tests/test-specs.sh`, `docs/guides/workflow.md` | `bash tests/test-copr.sh` at `1..21`, `bash tests/test-specs.sh` at `1..84` |
| 7 Docs | small | docs | master spec amendments (D2, D5, D6, D9 to D13), audit, roadmap, workflow guide, README, the VM-check guide | `docs/**`, `README.md` | `./dev check` green; no em dash added; one `gnome-restore` left in the master spec |
| 8 First COPR build (post-merge) | medium | build | dispatch `copr-build` for `tinkero`, read the log, `check-rpm` the COPR's RPM, the depsolve | none (a record on the issue) | green build; `python3`, `python3-fonttools`, `ImageMagick` in the mock root; no `nwg-panel`, `playerctl`, `wofi` or `newt` in the transaction; closed by hand |
| 9 VM check (manual) | medium | session | `docs/guides/phase-2f-vm-check.md` on a clean Fedora 44 VM | none (a record on the issue, one roadmap line) | every checkbox of the guide recorded; the three GNOME cycles diff empty |

After Tasks 1 to 7, `./dev check` runs: test-assemble `1..64`, test-gates `1..79`, test-pam-sync `1..42`, test-install `1..33`, test-render-spec `1..21`, test-replacements `1..54`, test-check-rpm `1..16`, test-copr `1..21`, test-specs `1..84`; the others unchanged (test-provision `1..178`, test-branding `1..14`, test-fetch `1..9`, test-lock `1..4`, test-menu-guards `1..8`, test-update `1..6`, Python `Ran 33 tests`).

## File Structure

| File | Responsibility |
|---|---|
| `build/assemble` | step 3e (strip `[Install]` in the tree); step 5 installs `systemd/`, `20-tinkero` and the PAM variants; step 6 installs `distro/fedora/bin/tinkero-*` |
| `systemd/tinkero-inhibit-power-key.service` | holds the `handle-power-key` inhibitor for the session (spec 4.2) |
| `systemd/{omarchy-fcitx5,bt-agent,omarchy-speaker-tuning}.service.d/tinkero.conf` | the fcitx5 condition and start limit; `PartOf=graphical-session.target` for the two unbound units (D2); `bt-agent`'s also gets `ConditionPathExists=/usr/bin/bt-agent` (D17) |
| `session/uwsm-env.d/20-tinkero` | `export DCONF_PROFILE=tinkero` (D4) |
| `provision/session-units.list` | gains the inhibitor |
| `ci/gate-session-units` | no `[Install]` anywhere; every listed unit exists and is session-bound (D3) |
| `distro/fedora/pam/omarchy-lock-password.{wrapped,plain}` | spec 4.8's two variants |
| `distro/fedora/bin/tinkero-pam-sync` | writes, prints or checks the variant `password-auth` calls for (D6, D7) |
| `tinkero.spec.in` | `%posttrans`, two `%ghost` lines with no `%config` (D9), the env file, `Requires: bluez-tools` (D17) and `diffutils` (for `tinkero-pam-sync`'s `cmp`) |
| `install.sh` | `sudo tinkero-pam-sync` after the install (D8) |
| `patches/0011-omarchy-apply-lock-fingerprint-only.patch` | the fingerprint file only, gated on enrolments and `system-auth` (D10) |
| `distro/fedora/replacements/omarchy-{setup,remove}-security-fingerprint` | the authselect port (D11, D12) |
| `menu/overrides.jsonc` | Remove > Fingerprint row regated on the fingerprint PAM file, not on `fprintd` being present (D11) |
| `ci/check-rpm`, `dev gates-at` | the built package's flags, scriptlet and payload, and the gates on it (D14) |
| `build/tinkero-copr`, `distro/fedora/specs/build-order.txt` | `tinkero` registered from the root spec (D13) |
| `docs/guides/phase-2f-vm-check.md` | the VM procedure (D15) |

Interfaces later plans rely on: `tinkero-pam-sync --check` and `--variant` (Phase 3's `tinkero-status`); `ci/check-rpm` and `./dev gates-at` (the release workflow can run them on each release's RPM); `ci/gate-session-units` (the bump checklist); `docs/guides/phase-2f-vm-check.md` (Phase 3's VM smoke test automates its sections 1, 3 and 4).

## Review Focus

Input classes the design implies that no requirement names; each has its test in the task that owns the code.

1. A unit file whose `[Install]` header has trailing spaces, or whose `[Install]` is the last section, or a unit with no `[Install]` at all: the strip removes exactly that section, keeps the others byte for byte, counts only units it changed, and the post-check (unanchored on purpose) catches a header the strip missed; Task 1 (the fixture has all three shapes and a broken-header case).
2. A `password-auth` that names `pam_faillock.so` only in a comment, or with a leading `-auth`: a comment is not an active line (wrapped), a dashed line is (plain); Task 3.
3. `tinkero-pam-sync` interrupted or failing mid-write (unreadable variant file, missing `password-auth`): no temporary file is left in the PAM directory and the existing file is untouched; Task 3.
4. `tinkero-pam-sync` run by a user (a desktop user typing it, or `tinkero-status` later): the write refuses with exit 2 and names `sudo`, while `--check` and `--variant` work unprivileged; Task 3.
5. Fingerprint enrolment or verification failing, or no reader at all: authselect is never touched and the lock file is never written; Task 4 (the stub-based order and absence checks). And a unit bound through a `PartOf=` line naming several units, or kept alive by `RemainAfterExit=true`: bound, and not exempt, respectively; Task 2.

---

### Task 1: Session wiring in the payload

**Files:**
- Create: `systemd/tinkero-inhibit-power-key.service`, `systemd/omarchy-fcitx5.service.d/tinkero.conf`, `systemd/bt-agent.service.d/tinkero.conf`, `systemd/omarchy-speaker-tuning.service.d/tinkero.conf`, `session/uwsm-env.d/20-tinkero`
- Modify: `build/assemble` (header comment, new step 3e, additions to step 5), `tinkero.spec.in` (`%files`, and the `Requires:` line that lists `bluez`), `provision/session-units.list` (append, header comment), `tests/fixtures/make-tree.sh` (unit fixtures), `tests/test-assemble.sh` (private root files and assertions)

**Interfaces:**
- Produces: `/usr/lib/systemd/user/tinkero-inhibit-power-key.service`, `/usr/lib/systemd/user/{omarchy-fcitx5,bt-agent,omarchy-speaker-tuning}.service.d/tinkero.conf` (design section 2.3); `/usr/share/uwsm/env.d/20-tinkero` exporting `DCONF_PROFILE=tinkero` (design section 3); a payload with 0 `[Install]` lines under either unit directory (was 14); `provision/session-units.list` with `tinkero-inhibit-power-key.service` appended after `bt-agent.service`. Task 2's gate reads all of this: the unit directories under `PAYLOAD`, and `provision/session-units.list` by path (not from the payload). Nothing in `bin/tinkero-provision` changes (2E already reads `provision/session-units.list` and the dconf profile). `bt-agent`'s binary ships in Fedora's `bluez-tools`, not `bluez`; the spec now requires it too, and the drop-in's `ConditionPathExists=/usr/bin/bt-agent` is belt and braces (design D17).

- [ ] **Step 1: The unit files and the env export**

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

`systemd/omarchy-fcitx5.service.d/tinkero.conf`:

```ini
[Unit]
ConditionPathExists=/usr/bin/fcitx5
StartLimitIntervalSec=60
StartLimitBurst=5
```

`systemd/bt-agent.service.d/tinkero.conf` (the `ConditionPathExists` line is design D17: `bt-agent`'s binary ships in Fedora's `bluez-tools`, which the spec's `bluez` requirement does not pull in; belt and braces alongside the new `Requires`, same pattern as the fcitx5 drop-in above):

```ini
[Unit]
# Tinkero: stop with the Tinkero session, so nothing of it runs under a later GNOME login.
PartOf=graphical-session.target
ConditionPathExists=/usr/bin/bt-agent
```

`systemd/omarchy-speaker-tuning.service.d/tinkero.conf` (design section 2.3):

```ini
[Unit]
# Tinkero: stop with the Tinkero session, so nothing of it runs under a later GNOME login.
PartOf=graphical-session.target
```

In `tinkero.spec.in`'s `Requires:` line that lists `bluez` (design D17):

```diff
-Requires:       ppd-service bluez NetworkManager udiskie socat inotify-tools jq gum git-core fcitx5
+Requires:       ppd-service bluez bluez-tools NetworkManager udiskie socat inotify-tools jq gum git-core fcitx5
```

`session/uwsm-env.d/20-tinkero`:

```sh
# Tinkero: the session reads and writes its own dconf database, ~/.config/dconf/tinkero,
# never GNOME's ~/.config/dconf/user (spec 4.9). /etc/dconf/profile/tinkero names it.
export DCONF_PROFILE=tinkero
```

In `provision/session-units.list`, the header no longer promises future work and the inhibitor joins the list after `bt-agent.service`:

```diff
 # provision/session-units.list: user units tinkero-provision --session starts at every Tinkero
 # session start (spec 4.6, 4.9). Nothing is enabled; PartOf=graphical-session.target stops them.
-# A unit whose file is not installed is skipped. 2F appends tinkero-inhibit-power-key.service.
+# A unit whose file is not installed is skipped.
 omarchy-crash-watch.service
 omarchy-sleep-lock.service
 omarchy-recover-internal-monitor.service
 omarchy-fcitx5.service
 bt-agent.service
+tinkero-inhibit-power-key.service
 # installed under ~/.config/systemd/user by `omarchy-audio-tuning on` on the laptops it matches (design D4)
 omarchy-speaker-tuning.service
```

- [ ] **Step 2: Fixture and failing tests**

In `tests/fixtures/make-tree.sh`, the two existing unit lines gain `[Install]` sections (one in the middle of the file, followed by another section that must survive the strip) and a third unit ships with none at all, so the strip is tested both ways:

```diff
-printf '[Service]\nExecStart=/usr/bin/omarchy-keep-me\n' > "$top/default/systemd/user/omarchy-keep.service"
-printf '[Service]\nExecStart=/usr/bin/omarchy-migrate-notify\n' > "$top/default/systemd/user/omarchy-migrate-notify.service"
+printf '[Unit]\nDescription=Keep me\n\n[Install]\nWantedBy=graphical-session.target\n\n[Service]\nExecStart=/usr/bin/omarchy-keep-me\n' > "$top/default/systemd/user/omarchy-keep.service"
+printf '[Service]\nExecStart=/usr/bin/omarchy-migrate-notify\n\n[Install]\nWantedBy=graphical-session.target\n' > "$top/default/systemd/user/omarchy-migrate-notify.service"
+printf '[Unit]\nDescription=No install section\n\n[Service]\nExecStart=/usr/bin/true\n' > "$top/default/systemd/user/omarchy-no-install.service"
```

(`omarchy-migrate-notify.service` is dropped by `build/drop.list` before step 3e ever runs, in both the real tree and the fixture's own drop list, so it does not add to the stripped count; it still exercises step 1's drop before the strip step touches anything. `omarchy-no-install.service` is what makes the stripped-count assertion below meaningful: without it, "files changed" and "files matching the five unit extensions" would agree by coincidence.)

In `tests/test-assemble.sh`, the private root gains a `systemd/` tree and `session/uwsm-env.d/`:

```diff
-r=$d/root; mkdir -p "$r"/{build,patches,distro/fedora/{replacements,lib,skills,dconf/profile},session,bin,config/hypr,provision,config-notes}
+r=$d/root; mkdir -p "$r"/{build,patches,distro/fedora/{replacements,lib,skills,dconf/profile},session/uwsm-env.d,bin,config/hypr,provision,config-notes}
+mkdir -p "$r"/systemd/{omarchy-fcitx5.service.d,bt-agent.service.d,omarchy-speaker-tuning.service.d}
 printf '# lib\n' > "$r/distro/fedora/lib/pkg.sh"; printf 'foot\tdnf\tfoot\n' > "$r/distro/fedora/pkgmap.tsv"
 cp "$ROOT/session/tinkero.desktop" "$r/session/"
 echo '# fixture host guide' > "$r/distro/fedora/skills/host.md"
+printf '[Unit]\nDescription=fixture inhibitor\n\n[Service]\nExecStart=/usr/bin/true\n' > "$r/systemd/tinkero-inhibit-power-key.service"
+printf '[Unit]\nConditionPathExists=/usr/bin/fcitx5\n' > "$r/systemd/omarchy-fcitx5.service.d/tinkero.conf"
+printf '[Unit]\nPartOf=graphical-session.target\n' > "$r/systemd/bt-agent.service.d/tinkero.conf"
+printf '[Unit]\nPartOf=graphical-session.target\n' > "$r/systemd/omarchy-speaker-tuning.service.d/tinkero.conf"
+printf 'export DCONF_PROFILE=tinkero\n' > "$r/session/uwsm-env.d/20-tinkero"
```

and, right after the existing `imv icon shipped` assertion, ten new assertions (four of these incidentally already pass, since the tree's own units are copied by the existing, unmodified step 5, and their absence-of-Tinkero-files checks are vacuously true until step 3 wires the copy in):

```bash
# Session units (plan 2F): [Install] stripped in the tree, Tinkero's own units join it
assert_contains "$out" "stripped [Install] from 1 unit(s)" "assemble logs how many units were stripped"
for copy in "$d/dest/usr/lib/systemd/user" "$o/default/systemd/user"; do
  if grep -rq '^\[Install\]' "$copy"; then not_ok "no [Install] survives in $copy"; else ok "no [Install] survives in $copy"; fi
done
assert_eq "$(sed -n '/^\[Service\]/,$p' "$d/dest/usr/lib/systemd/user/omarchy-keep.service")" "$(printf '[Service]\nExecStart=/usr/bin/omarchy-keep-me')" \
  "a section after [Install] survives intact"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-no-install.service" "a unit with no [Install] section is untouched"
assert_file "$d/dest/usr/lib/systemd/user/tinkero-inhibit-power-key.service" "Tinkero's inhibitor unit lands beside the tree's units"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-fcitx5.service.d/tinkero.conf" "Tinkero's fcitx5 drop-in lands"
assert_file "$d/dest/usr/lib/systemd/user/bt-agent.service.d/tinkero.conf" "Tinkero's bt-agent drop-in lands"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-speaker-tuning.service.d/tinkero.conf" "Tinkero's speaker-tuning drop-in lands"
assert_eq "$(cat "$d/dest/usr/share/uwsm/env.d/20-tinkero")" "export DCONF_PROFILE=tinkero" "the DCONF_PROFILE env file lands"

# a fixture root without systemd/ still assembles (other tests' private roots have none)
r2=$d/root-nosystemd; cp -a "$r" "$r2"; rm -rf "$r2/systemd"
TINKERO_ROOT=$r2 "$ROOT/build/assemble" "$tb" "$d/dest-nosystemd" >/dev/null
assert_no_path "$d/dest-nosystemd/usr/lib/systemd/user/tinkero-inhibit-power-key.service" "no Tinkero units without a systemd/ dir in the root"
assert_file "$d/dest-nosystemd/usr/lib/systemd/user/omarchy-keep.service" "the tree's own units still land"

# a unit whose [Install] header the strip cannot recognise (leading whitespace) fails the build
mkdir -p "$d/y"
tar -xzf "$tb" -C "$d/y"
printf '[Unit]\nDescription=broken\n\n  [Install]\nWantedBy=graphical-session.target\n' \
  > "$d/y/omarchy-fixture/default/systemd/user/omarchy-broken-install.service"
tar -C "$d/y" -czf "$d/broken-install.tar.gz" omarchy-fixture
out=$(TINKERO_ROOT=$r "$ROOT/build/assemble" "$d/broken-install.tar.gz" "$d/dest-broken" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a header the strip cannot recognise fails the build"
assert_contains "$out" "still have [Install] after stripping" "and names the failure"
```

Run: `bash tests/test-assemble.sh` Expected: `1..59`; 10 `not ok` (cases 27, 28, 29, 32 to 36, 39, 40 in the run above: the stripped-count line, both no-`[Install]` checks, the four Tinkero-file and env-file checks, and the two broken-header checks), the other 49 (including the four incidental passes) green.

- [ ] **Step 3: The strip step and the new installs in `build/assemble`**

After the header's input list (following the `applications/icons/{Disk Usage,imv}.png` line), document the two new inputs:

```diff
 #   applications/icons/{Disk Usage,imv}.png   the icons the seeded launchers name, under hicolor
+#   systemd/**                          Tinkero's own session units and drop-ins (step 3e strips
+#                                        [Install] from the tree's units first), into
+#                                        /usr/lib/systemd/user alongside the tree's units
+#   session/uwsm-env.d/20-tinkero       the DCONF_PROFILE export, into /usr/share/uwsm/env.d
 set -euo pipefail
```

After step 3d (branding) and before step 4 (relocate), insert step 3e. Two things here read differently from a literal pass of design section 2.2 and 2.4, both accepted by the operator at review: the post-strip safety check below is unanchored on the section name (`\[Install\]`, not `^\[Install\]`), and `N` counts units the strip actually changed rather than every file that matched the five unit-file extensions. Both are explained inline where they happen:

```bash
# 3e. Strip [Install] from every session unit, in the tree (not just the copy): a unit that
# omarchy-audio-tuning installs from here into ~/.config/systemd/user keeps whatever section is
# still here, and `systemctl --user enable` on a unit with an [Install] section registers it, so
# a later GNOME login that reuses the still-running user manager would start it (design D1, D2).
units=$tree/default/systemd/user
[[ -d $units ]] || die "upstream has no default/systemd/user; decide where session units go"
n=0
while IFS= read -r -d '' f; do
  # A section header is a whole line (trailing whitespace ignored) of the form [Name]; the
  # Install section runs from its header to the next section header or EOF. Trimming only for the
  # comparison keeps every other line's exact bytes.
  awk '
    { line = $0; sub(/[ \t\r]+$/, "", line) }
    line ~ /^\[.*\]$/ { in_install = (line == "[Install]") }
    !in_install
  ' "$f" > "$f.tinkero"
  # N counts units actually changed by the strip, not every file the find below matches: a unit
  # that already ships with no [Install] section (none does at v4.0.4, but the fixture tree
  # carries one to prove this) does not add to it.
  cmp -s "$f" "$f.tinkero" || n=$((n + 1))
  mv "$f.tinkero" "$f"
done < <(find "$units" -type f \( -name '*.service' -o -name '*.socket' -o -name '*.timer' -o -name '*.path' -o -name '*.target' \) -print0)
echo "stripped [Install] from $n unit(s)"
# Unanchored on purpose: a header the strip failed to recognise (leading whitespace, say) still
# contains the literal text and must fail the build rather than ship unnoticed. Anchoring this
# check the same way the stripper recognises headers would make the safety net blind to exactly
# the failure mode it exists for; the broken-header fixture case above (Step 2) is what this
# check is for.
remaining=$(grep -rl '\[Install\]' "$units" 2>/dev/null | sed "s|^$units/||" || true)
[[ -z $remaining ]] || die "unit(s) still have [Install] after stripping: $remaining"
```

In step 5, install the env file beside `10-omarchy` and copy Tinkero's own units in after the tree's:

```diff
 # 5. System files that live outside the tree.
 install -Dm 0644 "$tree/default/uwsm/env.d/10-omarchy" "$dest/usr/share/uwsm/env.d/10-omarchy"
+install -Dm 0644 "$root/session/uwsm-env.d/20-tinkero" "$dest/usr/share/uwsm/env.d/20-tinkero"
 install -Dm 0644 "$root/session/tinkero.desktop" "$dest/usr/share/wayland-sessions/tinkero.desktop"
 install -Dm 0644 "$tree/default/fonts/omarchy/omarchy.ttf" "$dest/usr/share/fonts/omarchy/omarchy.ttf"
 install -Dm 0644 "$tree/default/fontconfig/conf.avail/50-omarchy.conf" "$dest/usr/share/fontconfig/conf.avail/50-omarchy.conf"
 mkdir -p "$dest/usr/lib/systemd/user"
 cp -a "$tree/default/systemd/user/." "$dest/usr/lib/systemd/user/"
+# Tinkero's own session units and drop-ins (design section 2.3), joining the tree's units in the
+# same directory so systemd reads a drop-in for either one the same way; after the copy above,
+# so a name collision would overwrite the tree's file rather than the other way round.
+[[ -d $root/systemd ]] && cp -a "$root/systemd/." "$dest/usr/lib/systemd/user/"
 install -Dm 0644 "$tree/LICENSE" "$dest/usr/share/licenses/tinkero/LICENSE.omarchy"
```

- [ ] **Step 4: The spec template**

In `tinkero.spec.in`'s `%files`, after the `10-omarchy` line add the new env file (the `%{_prefix}/lib/systemd/user/*` glob already covers Tinkero's own units and drop-ins, since a matched directory entry is packaged with its contents):

```diff
 %{_datadir}/uwsm/env.d/10-omarchy
+%{_datadir}/uwsm/env.d/20-tinkero
```

- [ ] **Step 5: Verify**

Run: `bash tests/test-assemble.sh` Expected: `1..59`, no `not ok`.
Run: `./dev check` Expected: green (`1..82` on `tests/test-specs.sh`, `1..178` on `tests/test-provision.sh`, unchanged; only `test-assemble.sh`'s tally moves, 45 to 59).
Run: `shellcheck -x -e SC1090,SC1091 build/assemble tests/test-assemble.sh tests/fixtures/make-tree.sh` Expected: clean.
Run (real tree, no branding): `TINKERO_ROOT=<root without branding/strings.tsv> build/assemble .cache/omarchy-*.tar.gz /tmp/payload` Expected: prints `stripped [Install] from 7 unit(s)`.
Run: `grep -rl '^\[Install\]' /tmp/payload/usr/lib/systemd/user /tmp/payload/usr/share/omarchy/default/systemd/user | wc -l` Expected: `0` (was 14 before this task).
Run: `ls /tmp/payload/usr/lib/systemd/user` Expected: `app.slice.d bt-agent.service bt-agent.service.d omarchy-crash-watch.service omarchy-fcitx5.service omarchy-fcitx5.service.d omarchy-recover-internal-monitor.service omarchy-sleep-lock.service omarchy-speaker-tuning.service omarchy-speaker-tuning.service.d omarchy-tailscale-receive.service tinkero-inhibit-power-key.service`.
Run: `test -f /tmp/payload/usr/share/uwsm/env.d/20-tinkero && stat -c '%a' /tmp/payload/usr/share/uwsm/env.d/20-tinkero` Expected: `644`.
Run: `grep -c '^ConditionPathExists=/usr/bin/bt-agent$' /tmp/payload/usr/lib/systemd/user/bt-agent.service.d/tinkero.conf` Expected: `1` (design D17).
Run: `grep -c bluez-tools tinkero.spec.in` Expected: `1` (the `Requires:` line, design D17).

- [ ] **Step 6: Commit**

```bash
git add systemd session/uwsm-env.d build/assemble tinkero.spec.in provision/session-units.list tests/fixtures/make-tree.sh tests/test-assemble.sh
git commit -m "build: strip [Install] from session units, ship Tinkero's own unit and drop-ins, export DCONF_PROFILE"
```

**Verification for the issue:** Step 5's commands, plus CI green. Task 2's gate is what proves the stripped payload's unit properties in `./dev gates` and CI; this task's own verification is the assemble output and the fixture-level tests.

---

### Task 2: The session-units gate

**Files:**
- Create: `ci/gate-session-units`
- Modify: `dev` (`gates()` gains a sixth call), `.github/workflows/ci.yml` (ShellCheck list), `tests/test-gates.sh` (fixture payloads and assertions)

**Interfaces:**
- Consumes: Task 1's payload shape: `usr/lib/systemd/user/` and `usr/share/omarchy/default/systemd/user/` with no `[Install]`, Tinkero's drop-ins beside the tree's units; `provision/session-units.list` (Task 1's updated copy in the repo, read by path, not from the payload).
- Produces: `ci/gate-session-units PAYLOAD LIST` (exit 0 pass, 1 findings, 2 bad input), and its exact `PASS: session units (N listed, M unit files, no [Install])` line, wired into `./dev gates` as the sixth and last gate. No allowlist: design D3 argues the strip and the drop-ins are payload properties a bump can silently undo, so there is nothing to grandfather.

- [ ] **Step 1: The failing tests**

Append to `tests/test-gates.sh` before its final `rm -rf "$d"; finish` line:

```bash
# session-units (plan 2F): unit-a is bound directly, unit-b only through a drop-in, unit-c is a
# plain oneshot; all three pass, so this fixture is also the "bound through a drop-in" and
# "oneshot passes" case, restored between the mutations below.
su=$d/su
mkdir -p "$su/usr/bin" "$su/usr/lib/systemd/user/unit-b.service.d" "$su/usr/share/omarchy/default/systemd/user"
reset_su() {
  printf '[Unit]\nPartOf=graphical-session.target\n\n[Service]\nExecStart=/usr/bin/true\n' > "$su/usr/lib/systemd/user/unit-a.service"
  printf '[Unit]\nDescription=b\n\n[Service]\nExecStart=/usr/bin/true\n' > "$su/usr/lib/systemd/user/unit-b.service"
  printf '[Unit]\nPartOf=graphical-session.target\n' > "$su/usr/lib/systemd/user/unit-b.service.d/tinkero.conf"
  printf '[Unit]\nDescription=c\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\n' > "$su/usr/lib/systemd/user/unit-c.service"
  cp "$su/usr/lib/systemd/user/unit-a.service" "$su/usr/share/omarchy/default/systemd/user/unit-a.service"
  cp "$su/usr/lib/systemd/user/unit-b.service" "$su/usr/share/omarchy/default/systemd/user/unit-b.service"
  cp "$su/usr/lib/systemd/user/unit-c.service" "$su/usr/share/omarchy/default/systemd/user/unit-c.service"
}
reset_su
printf '# comment\nunit-a.service\nunit-b.service\nunit-c.service\n' > "$d/session-units.list"
GS=$ROOT/ci/gate-session-units

out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "session-units: pass case (a bound directly, b through a drop-in, c a plain oneshot)"
assert_eq "$out" "PASS: session units (3 listed, 3 unit files, no [Install])" "session-units: exact PASS line, comment line not counted"

printf '\n[Install]\nWantedBy=graphical-session.target\n' >> "$su/usr/lib/systemd/user/unit-a.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: [Install] in the usr/lib copy fails"
assert_contains "$out" "usr/lib/systemd/user/unit-a.service" "session-units: names the usr/lib copy"
reset_su

printf '\n[Install]\nWantedBy=graphical-session.target\n' >> "$su/usr/share/omarchy/default/systemd/user/unit-a.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: [Install] in the tree copy fails"
assert_contains "$out" "usr/share/omarchy/default/systemd/user/unit-a.service" "session-units: names the tree copy"
reset_su

printf 'unit-a.service\nunit-missing.service\n' > "$d/session-units-missing.list"
out=$("$GS" "$su" "$d/session-units-missing.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: a listed unit with no file fails"
assert_contains "$out" "listed unit has no file: unit-missing.service" "session-units: names it"

rm -f "$su/usr/lib/systemd/user/unit-b.service.d/tinkero.conf"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: a listed unit bound neither directly nor by a drop-in fails"
assert_contains "$out" "neither bound to the session nor a plain oneshot: unit-b.service" "session-units: names it"
reset_su

printf 'RemainAfterExit=yes\n' >> "$su/usr/lib/systemd/user/unit-c.service"
cp "$su/usr/lib/systemd/user/unit-c.service" "$su/usr/share/omarchy/default/systemd/user/unit-c.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: a oneshot with RemainAfterExit=yes is no longer exempt"
assert_contains "$out" "neither bound to the session nor a plain oneshot: unit-c.service" "session-units: names it"
reset_su

printf 'RemainAfterExit=true\n' >> "$su/usr/lib/systemd/user/unit-c.service"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "session-units: RemainAfterExit=true is a remaining oneshot too"
reset_su

printf '[Unit]\nPartOf=pipewire.service graphical-session.target\n' > "$su/usr/lib/systemd/user/unit-b.service.d/tinkero.conf"
out=$("$GS" "$su" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "session-units: a PartOf= line naming several units binds the unit"
reset_su

out=$("$GS" "$su" "does-not-exist" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "session-units: exits 2 on an unreadable list"
assert_contains "$out" "cannot read session unit list" "session-units: and says so"

out=$("$GS" "$d/no-such-payload" "$d/session-units.list" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "session-units: exits 2 on a missing payload"
assert_contains "$out" "no payload at DEST" "session-units: and says so"

out=$("$GS" "$su" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 2 "session-units: exits 2 on the wrong number of arguments"
assert_contains "$out" "usage: gate-session-units" "session-units: and prints usage"
```

Run: `bash tests/test-gates.sh` Expected: the 20 new cases fail (`ci/gate-session-units` does not exist yet), the other 59 green.

- [ ] **Step 2: The gate**

`ci/gate-session-units` (mode 0755):

```bash
#!/bin/bash
# gate-session-units PAYLOAD LIST: properties of the session units a bump can silently
# undo (design spec 4.9, section 2.4). No allowlist. Fails when:
#   1. any regular unit file under usr/lib/systemd/user/ or
#      usr/share/omarchy/default/systemd/user/ still contains an [Install] line;
#   2. a unit named in LIST has no file under usr/lib/systemd/user/;
#   3. a unit named in LIST is neither bound to the session (PartOf=graphical-session.target
#      in the unit itself or in any usr/lib/systemd/user/<unit>.d/*.conf) nor a Type=oneshot
#      unit without RemainAfterExit=yes (or true, on, 1). A PartOf= line may name several units.
set -euo pipefail
export LC_ALL=C
[[ $# -eq 2 ]] || { echo "usage: gate-session-units PAYLOAD LIST" >&2; exit 2; }
dest=$1; list=$2
[[ -d $dest/usr/bin ]] || { echo "FAIL: no payload at DEST (run ./dev payload first)"; exit 2; }
[[ -r $list ]] || { echo "FAIL: cannot read session unit list: $list"; exit 2; }
unitdir=$dest/usr/lib/systemd/user
[[ -d $unitdir ]] || { echo "FAIL: no unit directory in the payload: $unitdir"; exit 2; }
rc=0

# 1. No [Install] anywhere under either copy. Unanchored on the section name (same choice as
#    build/assemble step 3e's own safety check, and for the same reason) so a header the build's
#    strip step failed to recognise still fails here rather than shipping unnoticed.
leaked=$(grep -rl '\[Install\]' "$unitdir" "$dest/usr/share/omarchy/default/systemd/user" 2>/dev/null | sed "s|^$dest/||" | sort || true)
if [[ -n $leaked ]]; then
  echo "FAIL: [Install] survives in:"; printf '  %s\n' "${leaked//$'\n'/$'\n'  }"; rc=1
fi

# 2 and 3: every listed unit.
n=0
while IFS= read -r name; do
  [[ -z $name || $name == \#* ]] && continue
  n=$((n + 1))
  unit=$unitdir/$name
  if [[ ! -f $unit ]]; then
    echo "FAIL: listed unit has no file: $name"; rc=1; continue
  fi
  bound=0
  grep -qE '^[[:space:]]*PartOf=(.*[[:space:]])?graphical-session\.target([[:space:]].*)?$' "$unit" && bound=1
  if [[ $bound -eq 0 ]]; then
    shopt -s nullglob
    dropins=("$unitdir/$name.d"/*.conf)
    shopt -u nullglob
    for d in "${dropins[@]}"; do
      grep -qE '^[[:space:]]*PartOf=(.*[[:space:]])?graphical-session\.target([[:space:]].*)?$' "$d" && { bound=1; break; }
    done
  fi
  oneshot_ok=0
  if grep -qE '^[[:space:]]*Type=oneshot[[:space:]]*$' "$unit" \
      && ! grep -qE '^[[:space:]]*RemainAfterExit=(yes|true|on|1)[[:space:]]*$' "$unit"; then
    oneshot_ok=1
  fi
  if [[ $bound -eq 0 && $oneshot_ok -eq 0 ]]; then
    echo "FAIL: listed unit is neither bound to the session nor a plain oneshot: $name"; rc=1
  fi
done < "$list"

m=$(find "$unitdir" -maxdepth 1 -type f \( -name '*.service' -o -name '*.socket' -o -name '*.timer' -o -name '*.path' -o -name '*.target' \) | wc -l)
[[ $rc -eq 0 ]] && echo "PASS: session units ($n listed, $m unit files, no [Install])"
exit $rc
```

`chmod +x ci/gate-session-units`

- [ ] **Step 3: Wire it into `./dev gates` and CI**

In `dev`, add the sixth call at the end of `gates()`:

```diff
   ci/gate-branding "$payload" branding/images.tsv branding/strings.tsv "$allow/branding.allow" || rc=1
+  ci/gate-session-units "$payload" provision/session-units.list || rc=1
   return $rc
 }
```

In `.github/workflows/ci.yml`'s ShellCheck step, add the new gate to the list:

```diff
-          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/lib-gate.sh
+          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/gate-name-map ci/gate-branding ci/gate-session-units ci/lib-gate.sh
```

- [ ] **Step 4: Verify**

Run: `bash tests/test-gates.sh` Expected: `1..79`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 ci/gate-session-units dev tests/test-gates.sh` Expected: clean.
Run: `./dev check` Expected: green.
Run (real tree, Task 1's payload already assembled at `/tmp/payload`): `ci/gate-session-units /tmp/payload provision/session-units.list` Expected exactly: `PASS: session units (7 listed, 8 unit files, no [Install])`.
Run: `ci/gate-single-copy /tmp/payload && ci/gate-arch-leak /tmp/payload ci/allow/arch-leak.allow && ci/gate-dropped-refs /tmp/payload build/drop.list ci/allow/dropped-refs.allow && ci/gate-name-map /tmp/payload distro/fedora/pkgmap.tsv` Expected: the other four gates still `PASS` (`ci/gate-branding` needs ImageMagick and python3-fonttools; CI runs it, this machine does not).

- [ ] **Step 5: Commit**

```bash
git add ci/gate-session-units dev .github/workflows/ci.yml tests/test-gates.sh
git commit -m "ci: gate-session-units proves the stripped payload's unit properties, wired into ./dev gates"
```

**Verification for the issue:** Step 4's commands, plus CI green (`./dev gates` prints six `PASS` lines, the session-units one last). Design section 9 lists this gate among what `./dev gates` and CI prove against the real tree; the bump checklist (design section 10) relies on it catching a listed unit upstream renamed or unbound.

---

### Task 3: PAM variants and `tinkero-pam-sync`

**Files:**
- Create: `distro/fedora/pam/omarchy-lock-password.wrapped`, `distro/fedora/pam/omarchy-lock-password.plain`, `distro/fedora/bin/tinkero-pam-sync`, `tests/test-pam-sync.sh`
- Modify: `build/assemble` (header comment, an addition to step 5, a new loop in step 6), `tinkero.spec.in` (`%posttrans`, two `%ghost` lines in `%files`, `diffutils` on the `Requires:` line), `install.sh` (the printed plan, `sudo tinkero-pam-sync` after `dnf install`), `.github/workflows/ci.yml` (ShellCheck list), `tests/test-assemble.sh` (fixture and assertions), `tests/test-render-spec.sh` (five assertions), `tests/test-install.sh` (a stub and two assertions)

**Interfaces:**
- Consumes: `TINKERO_EUID` and the string-compare root check, the same convention as `distro/fedora/lib/pkg.sh`'s `elevate` and `install.sh`'s preflight (`[[ ${TINKERO_EUID:-$EUID} == 0 ]]`); `/etc/pam.d/password-auth`, read only, never written.
- Produces: `/usr/bin/tinkero-pam-sync [--variant|--check]` (design spec 4.8, table in section 4.2): with no option, writes `/etc/pam.d/omarchy-lock-password` when it differs or is missing, printing `wrote <variant>` (exit 0) or `current: <variant>` (exit 0, no-op); refuses as non-root, naming `sudo tinkero-pam-sync`, and writes nothing (exit 2); `--variant` prints `wrapped` or `plain` (exit 0, no root needed); `--check` (Phase 3's `tinkero-status` consumes this) exits 0 with `current: <variant>` when the installed file matches, or exits 1 with one line naming the difference (`missing`, `<variant> installed, <variant> needed`, `modified`); any other error (a missing `password-auth`, a missing packaged variant file, an unknown option) exits 2 with a message. `/usr/share/tinkero/pam/omarchy-lock-password.{wrapped,plain}`, the two variants `tinkero-pam-sync` writes from; `/etc/pam.d/omarchy-lock-password`, `%ghost`-owned by the package, no `%config` (design spec 4.8, design D9: rpm skips `%ghost` entries in `rpm -V` entirely, so `tinkero-pam-sync --check` is the drift signal, not `rpm -V`). Task 4 (the fingerprint port, `omarchy-apply-lock`) writes the sibling `/etc/pam.d/omarchy-lock-fingerprint` this task only reserves with the second `%ghost` line; it does not touch that file.

- [ ] **Step 1: The PAM variants and `tinkero-pam-sync`**

`distro/fedora/pam/omarchy-lock-password.wrapped` (design spec 4.8, section 4.1 of the 2F design, byte for byte):

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

`distro/fedora/pam/omarchy-lock-password.plain`:

```
#%PAM-1.0
# omarchy-lock-password, variant "plain": written by tinkero-pam-sync because this host's
# password-auth already runs pam_faillock. Do not edit; run `sudo tinkero-pam-sync` after
# changing authselect features. Design spec 4.8.
auth     include        password-auth
account  include        password-auth
```

`distro/fedora/bin/tinkero-pam-sync` (mode 0755):

```bash
#!/bin/bash
# tinkero-pam-sync: keep /etc/pam.d/omarchy-lock-password in the variant the host's own PAM
# stack calls for (design spec 4.8; plan 2F design: docs/superpowers/specs/
# 2026-09-24-phase-2f-session-design.md, section 4). Run after any authselect change;
# %posttrans and install.sh both call it, so a fresh install and an authselect drift both land
# on the right variant.
#
#   tinkero-pam-sync              write the variant the host calls for; a no-op if already current
#   tinkero-pam-sync --variant    print the variant the host calls for ("wrapped" or "plain")
#   tinkero-pam-sync --check      exit 0 when the installed file matches; exit 1 and say why not
#
# "wrapped" adds its own pam_faillock.so around password-auth, for a host whose password-auth
# has none; "plain" just includes password-auth, for a host whose password-auth already counts
# failures, so the lock does not double-count them (D6: read from password-auth's own content,
# not from `authselect current`, so this works on every authselect profile and off it too).
set -euo pipefail

TINKERO_PAM_DIR=${TINKERO_PAM_DIR:-/etc/pam.d}
TINKERO_SHARE=${TINKERO_SHARE:-/usr/share/tinkero}
target=$TINKERO_PAM_DIR/omarchy-lock-password
password_auth=$TINKERO_PAM_DIR/password-auth
pam_dir=$TINKERO_SHARE/pam

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "tinkero-pam-sync: $1" >&2; exit "${2:-2}"; }   # default: bad input

TMP=""
cleanup() { [[ -z $TMP ]] || rm -f -- "$TMP"; }
trap cleanup EXIT

# variant_wanted: "plain" when password-auth has an active auth line naming pam_faillock.so
# (a "-auth" line counts; a commented "#auth" one does not), else "wrapped".
variant_wanted() {
  [[ -r $password_auth ]] || die "no $password_auth to read (is authselect installed?)"
  if grep -Eq '^[[:space:]]*-?auth[[:space:]]+.*pam_faillock\.so' "$password_auth"; then
    echo plain
  else
    echo wrapped
  fi
}

# variant_file VARIANT: the packaged source for that variant, or die (a packaging problem).
variant_file() {
  local f=$pam_dir/omarchy-lock-password.$1
  [[ -r $f ]] || die "no variant file $f (package problem; reinstall tinkero)"
  printf '%s\n' "$f"
}

do_write() {
  [[ ${TINKERO_EUID:-$EUID} == 0 ]] || die "must be root to write $target; run: sudo tinkero-pam-sync"
  local want src
  want=$(variant_wanted)
  src=$(variant_file "$want")
  if [[ -f $target ]] && cmp -s "$src" "$target"; then
    echo "current: $want"
    return 0
  fi
  # Atomic write (D7): mktemp in the PAM dir itself, so the file inherits the directory's
  # SELinux context with no restorecon, mode 0644, then mv over the target so a crash never
  # leaves a half-written PAM file.
  TMP=$(mktemp "$TINKERO_PAM_DIR/.omarchy-lock-password.XXXXXX") || die "mktemp failed in $TINKERO_PAM_DIR"
  cp "$src" "$TMP"
  chmod 0644 "$TMP"
  mv -f "$TMP" "$target"
  TMP=""
  echo "wrote $want"
}

do_check() {
  local want got wrapped_src plain_src
  want=$(variant_wanted)
  if [[ ! -f $target ]]; then
    echo missing
    exit 1
  fi
  wrapped_src=$(variant_file wrapped)
  plain_src=$(variant_file plain)
  if cmp -s "$wrapped_src" "$target"; then got=wrapped
  elif cmp -s "$plain_src" "$target"; then got=plain
  else got=modified
  fi
  if [[ $got == "$want" ]]; then
    echo "current: $want"
    return 0
  elif [[ $got == modified ]]; then
    echo modified
    exit 1
  else
    echo "$got installed, $want needed"
    exit 1
  fi
}

main() {
  local mode=write
  while (($#)); do
    case $1 in
      --check) mode=check ;;
      --variant) mode=variant ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  case $mode in
    write)   do_write ;;
    check)   do_check ;;
    variant) variant_wanted ;;
  esac
}
main "$@"
```

Run: `shellcheck -x -e SC1090,SC1091 distro/fedora/bin/tinkero-pam-sync` Expected: clean.

- [ ] **Step 2: `tests/test-pam-sync.sh`**

Create `tests/test-pam-sync.sh`:

```bash
#!/bin/bash
# tinkero-pam-sync against a fixture PAM directory and a fixture TINKERO_SHARE/pam (design spec
# 4.8; plan 2F design, section 4.2). No sudo, no real /etc: TINKERO_PAM_DIR, TINKERO_SHARE and
# TINKERO_EUID are the seams.
source "$(dirname "$0")/lib.sh"
S=$ROOT/distro/fedora/bin/tinkero-pam-sync
d=$(mktmp)
mkdir -p "$d/pam" "$d/share/pam"
cp "$ROOT/distro/fedora/pam/omarchy-lock-password.wrapped" "$d/share/pam/"
cp "$ROOT/distro/fedora/pam/omarchy-lock-password.plain" "$d/share/pam/"
export TINKERO_PAM_DIR=$d/pam TINKERO_SHARE=$d/share
target=$d/pam/omarchy-lock-password
pa=$d/pam/password-auth

run() { out=$(TINKERO_EUID="${euid:-1000}" "$S" "$@" 2>&1) && rc=0 || rc=$?; }
no_faillock() { printf 'auth        required      pam_unix.so try_first_pass nullok\naccount     required      pam_unix.so\n' > "$pa"; }
active_faillock() { printf 'auth        required      pam_faillock.so preauth silent\nauth        required      pam_unix.so try_first_pass nullok\nauth        required      pam_faillock.so authfail\naccount     required      pam_faillock.so\naccount     required      pam_unix.so\n' > "$pa"; }
commented_faillock() { printf '#auth       required      pam_faillock.so preauth silent\nauth        required      pam_unix.so try_first_pass nullok\naccount     required      pam_unix.so\n' > "$pa"; }
dash_faillock() { printf -- '-auth       required      pam_faillock.so preauth silent\nauth        required      pam_unix.so try_first_pass nullok\naccount     required      pam_unix.so\n' > "$pa"; }
no_temp_files() { [[ -z $(find "$d/pam" -maxdepth 1 -name '.omarchy-lock-password.*') ]]; }

# --- --variant: which variant the host calls for, D6's regex against password-auth -----------
no_faillock
run --variant
assert_eq "$rc" 0 "variant: exit 0"
assert_eq "$out" "wrapped" "variant: no pam_faillock.so in password-auth -> wrapped"

active_faillock
run --variant
assert_eq "$out" "plain" "variant: an active auth line naming pam_faillock.so -> plain"

commented_faillock
run --variant
assert_eq "$out" "wrapped" "variant: a commented #auth pam_faillock.so line does not count -> wrapped"

dash_faillock
run --variant
assert_eq "$out" "plain" "variant: a -auth prefixed (ignore-failure) line still counts -> plain"

# --- writing, as root (TINKERO_EUID seam) -----------------------------------------------------
no_faillock
rm -f "$target"
euid=0 run
assert_eq "$rc" 0 "write: exit 0"
assert_eq "$out" "wrote wrapped" "write: names the variant it wrote"
assert_eq "$(cmp "$target" "$d/share/pam/omarchy-lock-password.wrapped" && echo same)" "same" "write: the file is byte-equal to the wrapped variant"
assert_eq "$(stat -c %a "$target")" "644" "write: mode 0644"
if no_temp_files; then ok "write: no temp file left in the PAM dir"; else not_ok "write: no temp file left in the PAM dir"; fi

mt1=$(stat -c %Y "$target"); sleep 1
euid=0 run
assert_eq "$rc" 0 "write again: exit 0"
assert_eq "$out" "current: wrapped" "write again: already current, says so"
mt2=$(stat -c %Y "$target")
assert_eq "$mt2" "$mt1" "write again: mtime is unchanged (no rewrite)"
if no_temp_files; then ok "write again: no temp file left"; else not_ok "write again: no temp file left"; fi

active_faillock
euid=0 run
assert_eq "$out" "wrote plain" "write: switching the host config to faillock rewrites to plain"
assert_eq "$(cmp "$target" "$d/share/pam/omarchy-lock-password.plain" && echo same)" "same" "write: now byte-equal to the plain variant"

no_faillock
euid=0 run
assert_eq "$out" "wrote wrapped" "write: switching back rewrites to wrapped"

# --- --check ------------------------------------------------------------------------------
no_faillock
euid=0 run   # get back to a known-current state (wrapped)
euid=1000 run --check
assert_eq "$rc" 0 "check: exit 0 when current"
assert_eq "$out" "current: wrapped" "check: names the current variant"

rm -f "$target"
run --check
assert_eq "$rc" 1 "check: exit 1 when the file is missing"
assert_eq "$out" "missing" "check: says missing"

euid=0 run   # wrapped installed
active_faillock   # host now wants plain
run --check
assert_eq "$rc" 1 "check: exit 1 when the wrong variant is installed"
assert_eq "$out" "wrapped installed, plain needed" "check: names both the installed and the wanted variant"

no_faillock   # back to wanting wrapped; put plain on disk to get the reverse message
euid=0 run
active_faillock; euid=0 run; no_faillock
run --check
assert_eq "$out" "plain installed, wrapped needed" "check: the reverse mismatch message"

echo "hand-edited, not either variant" > "$target"
run --check
assert_eq "$rc" 1 "check: exit 1 for a modified file"
assert_eq "$out" "modified" "check: a file that is neither variant is 'modified'"

# --- non-root: write refuses, --check and --variant still work --------------------------------
no_faillock
rm -f "$target"
euid=1000 run
assert_eq "$rc" 2 "non-root write: refuses (exit 2)"
assert_contains "$out" "sudo" "non-root write: names sudo"
assert_no_path "$target" "non-root write: nothing was written"
if no_temp_files; then ok "non-root write: no temp file left"; else not_ok "non-root write: no temp file left"; fi

euid=0 run   # now write it for real, as a base for the read-only checks below
euid=1000 run --check
assert_eq "$rc" 0 "non-root --check: works without root"
euid=1000 run --variant
assert_eq "$rc" 0 "non-root --variant: works without root"
assert_eq "$out" "wrapped" "non-root --variant: correct answer"

# --- errors: missing password-auth, missing variant file, unknown option ----------------------
rm -f "$pa"
run --variant
assert_eq "$rc" 2 "missing password-auth: exit 2"
assert_contains "$out" "password-auth" "missing password-auth: names the file"
no_faillock

f=$d/share/pam/omarchy-lock-password.wrapped
mv "$f" "$f.bak"
euid=0 run
assert_eq "$rc" 2 "missing variant file: exit 2"
assert_contains "$out" "omarchy-lock-password.wrapped" "missing variant file: names the missing file"
if no_temp_files; then ok "missing variant file: no temp file left"; else not_ok "missing variant file: no temp file left"; fi
mv "$f.bak" "$f"

run --nope
assert_eq "$rc" 2 "unknown option: exit 2"
assert_contains "$out" "unknown option" "unknown option: says so"

# -h/--help
out=$("$S" -h); assert_contains "$out" "tinkero-pam-sync --check" "help: usage lists --check"
out=$("$S" --help); rc=$?
assert_eq "$rc" 0 "--help: exit 0"

rm -rf "$d"; finish
```

Run: `bash tests/test-pam-sync.sh` Expected: `1..42`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 tests/test-pam-sync.sh` Expected: clean.

- [ ] **Step 3: `build/assemble`: install the PAM variants and the host-only `distro/fedora/bin/`**

In the header comment block, after the `session/uwsm-env.d/20-tinkero` line Task 1 added add:

```bash
#   distro/fedora/pam/*                  the PAM variants tinkero-pam-sync writes from (plan 2F)
#   distro/fedora/bin/tinkero-*          host-only commands, installed like bin/tinkero-* (plan 2F)
```

In step 5, right after the `pkgmap.tsv` line, add:

```bash
# The PAM variants tinkero-pam-sync writes from (design spec 4.8, plan 2F).
if [[ -d $root/distro/fedora/pam ]]; then
  for f in "$root"/distro/fedora/pam/*; do
    [[ -f $f ]] && install -Dm 0644 "$f" "$dest/usr/share/tinkero/pam/$(basename "$f")"
  done
fi
```

In step 6, right after the `bin/tinkero-*` loop, add:

```bash
# Host-only commands that need root, not user provisioning (distro/fedora, plan 2F).
if [[ -d $root/distro/fedora/bin ]]; then
  for f in "$root"/distro/fedora/bin/tinkero-*; do
    [[ -f $f ]] && install -m 0755 "$f" "$dest/usr/bin/$(basename "$f")"
  done
fi
```

Both are guarded the same way step 3d (branding) is: a fixture root with neither directory still assembles.

- [ ] **Step 4: `tests/test-assemble.sh`: the guard and the positive path**

After Task 1's block, that is after the line `assert_contains "$out" "still have [Install] after stripping" "and names the failure"`, add:

```bash
# PAM variants and the host-only bin/ (plan 2F). The fixture root above has neither
# distro/fedora/pam nor distro/fedora/bin, and the run at "$d/dest" above still assembled: both
# steps are guarded. Add them now and assemble again to prove the positive path too.
mkdir -p "$r/distro/fedora/pam" "$r/distro/fedora/bin"
printf 'password fixture wrapped\n' > "$r/distro/fedora/pam/omarchy-lock-password.wrapped"
printf 'password fixture plain\n' > "$r/distro/fedora/pam/omarchy-lock-password.plain"
printf '#!/bin/bash\necho pam-sync fixture\n' > "$r/distro/fedora/bin/tinkero-pam-sync"
run "$d/dest-pam" >/dev/null
assert_eq "$(cat "$d/dest-pam/usr/share/tinkero/pam/omarchy-lock-password.wrapped")" "password fixture wrapped" "PAM wrapped variant shipped under usr/share/tinkero/pam"
assert_eq "$(cat "$d/dest-pam/usr/share/tinkero/pam/omarchy-lock-password.plain")" "password fixture plain" "PAM plain variant shipped"
assert_eq "$(stat -c %a "$d/dest-pam/usr/share/tinkero/pam/omarchy-lock-password.wrapped")" "644" "PAM variant installed mode 0644"
assert_eq "$(tail -n1 "$d/dest-pam/usr/bin/tinkero-pam-sync")" "echo pam-sync fixture" "distro/fedora/bin/tinkero-* installed to usr/bin, like bin/tinkero-*"
assert_eq "$(stat -c %a "$d/dest-pam/usr/bin/tinkero-pam-sync")" "755" "distro/fedora/bin/tinkero-pam-sync installed mode 0755"
```

The fixture root `r` gains `distro/fedora/pam` and `distro/fedora/bin` only after this point in the file; every earlier assertion (including the first `run "$d/dest"`) ran against a root with neither directory, which is the guard proof.

Run: `bash tests/test-assemble.sh` Expected: `1..64`, no `not ok` (59 after Task 1, plus this task's 5).
Run: `shellcheck -x -e SC1090,SC1091 build/assemble tests/test-assemble.sh` Expected: clean.

- [ ] **Step 5: `tinkero.spec.in`: `%posttrans` and the two `%ghost` lines**

Between `%install` and `%files`, add (spec convention: scriptlets before `%files`):

```
# tinkero-pam-sync writes the lock-screen PAM file for the host it is installed on (design
# spec 4.8, plan 2F); nothing is created in the build root, so this runs on every install and
# upgrade. The message names the failure mode: the lock refuses to lock, not a lockout.
%posttrans
/usr/bin/tinkero-pam-sync || echo "tinkero: tinkero-pam-sync failed; the lock screen will refuse to lock until 'sudo tinkero-pam-sync' succeeds" >&2
```

At the end of `%files`, after the `imv.png` line, add (no `%config`: rpm skips `%ghost` entries in `rpm -V` entirely, so `%config`/`missingok` on them buys nothing and risks an `.rpmsave` on erase; design D9):

```
%ghost %attr(0644,root,root) %{_sysconfdir}/pam.d/omarchy-lock-password
%ghost %attr(0644,root,root) %{_sysconfdir}/pam.d/omarchy-lock-fingerprint
```

`%{_datadir}/tinkero` already owns `usr/share/tinkero/pam/*` recursively and `%{_bindir}/tinkero-*` already owns `/usr/bin/tinkero-pam-sync`; neither needs its own `%files` line.

`tinkero-pam-sync` uses `cmp` (from `diffutils`) to compare the installed file against the packaged variant; add it to the same `Requires:` line Task 1 added `bluez-tools` to:

```diff
-Requires:       ppd-service bluez bluez-tools NetworkManager udiskie socat inotify-tools jq gum git-core fcitx5
+Requires:       ppd-service bluez bluez-tools NetworkManager udiskie socat inotify-tools jq gum git-core fcitx5 diffutils
```

- [ ] **Step 6: `tests/test-render-spec.sh`: the `%posttrans` and `%ghost` assertions**

After the `assert_contains "$s" "Source0:        omarchy-c668141e9c42b13c80c9ca4ea108e11708c5e8a5.tar.gz" "source names the commit"` line add:

```bash
assert_contains "$s" "%posttrans" "posttrans scriptlet present (plan 2F, PAM sync)"
assert_contains "$s" "/usr/bin/tinkero-pam-sync" "posttrans runs tinkero-pam-sync"
assert_contains "$s" "%ghost %attr(0644,root,root) %{_sysconfdir}/pam.d/omarchy-lock-password" "ghost: the password PAM file, no %config (D9)"
assert_contains "$s" "%ghost %attr(0644,root,root) %{_sysconfdir}/pam.d/omarchy-lock-fingerprint" "ghost: the fingerprint PAM file, no %config (D9)"
assert_contains "$s" "diffutils" "requires diffutils, for tinkero-pam-sync's cmp"
```

Run: `bash tests/test-render-spec.sh` Expected: `1..21`, no `not ok`.
`build/render-spec` is plain `sed`, so nothing else in that script needs to change; `%posttrans` and `%ghost` pass through untouched.

- [ ] **Step 7: `install.sh`: `sudo tinkero-pam-sync` after `dnf install`**

In the printed plan (the `cat <<EOF ... EOF` block), after the `dnf install tinkero` line add:

```
                        tinkero-pam-sync         (writes the lock screen's PAM file for this host)
```

After `sudo dnf install "${y[@]}" tinkero` add:

```bash
# %posttrans already ran this once, but a re-run of install.sh is otherwise unable to repair a
# variant an authselect change made stale in between (design spec 4.8, plan 2F design D8).
sudo tinkero-pam-sync
```

- [ ] **Step 8: `tests/test-install.sh`: the stub and two assertions**

After the `tinkero-provision` stub add:

```bash
cat > "$d/bin/tinkero-pam-sync" <<'S'
#!/bin/bash
echo "tinkero-pam-sync $*" >> "$LOG"
exit 0
S
```

Replace the happy-path log assertion's expected string (the old string ends `...|dnf install -y tinkero|tinkero-provision --plan|tinkero-provision --yes"`) with:

```bash
assert_eq "$(paste -sd'|' "$LOG")" "dnf repoquery --installed --queryformat %{name} %{from_repo}\n hyprland quickshell omedora omedora-settings|sudo dnf copr enable -y dromero/tinkero|dnf copr enable -y dromero/tinkero|sudo dnf install -y tinkero|dnf install -y tinkero|sudo tinkero-pam-sync|tinkero-pam-sync |tinkero-provision --plan|tinkero-provision --yes" "install: preflight query, copr enable, install, pam-sync, plan, provision, in that order"
```

and after the provisioning-plan assertion add:

```bash
assert_contains "$out" "tinkero-pam-sync" "install: the printed plan names tinkero-pam-sync"
```

Run: `bash tests/test-install.sh` Expected: `1..33`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 install.sh tests/test-install.sh` Expected: clean.

- [ ] **Step 9: `.github/workflows/ci.yml`: the ShellCheck list**

Change:

```
          distro/fedora/specs/srpm.sh build/tinkero-copr bin/tinkero-*
```

to:

```
          distro/fedora/specs/srpm.sh build/tinkero-copr bin/tinkero-* distro/fedora/bin/*
```

- [ ] **Step 10: Verify**

Run: `./dev check` Expected: green; `1..64` (`tests/test-assemble.sh`), `1..33` (`tests/test-install.sh`), `1..21` (`tests/test-render-spec.sh`), `1..42` (`tests/test-pam-sync.sh`); `tests/test-gates.sh` at `1..79` from Task 2; every other file unchanged from master; the Python suite `Ran 33 tests ... OK (skipped=6)`.
Run: `shellcheck -x -e SC1090,SC1091 build/assemble tests/test-assemble.sh tests/test-render-spec.sh tests/test-install.sh tests/test-pam-sync.sh install.sh distro/fedora/bin/*` Expected: clean.
Real payload (`TINKERO_ROOT` pointed at a copy of the tree with `branding/strings.tsv` removed, since this host has no ImageMagick or python3-fonttools):
- `build/assemble <tarball> DEST` Expected: `assembled 367 commands into DEST` (was 366 before this task; `tinkero-pam-sync` is the new one).
- `ls DEST/usr/share/tinkero/pam` Expected: `omarchy-lock-password.plain  omarchy-lock-password.wrapped`, both mode 644.
- `test -x DEST/usr/bin/tinkero-pam-sync && stat -c %a DEST/usr/bin/tinkero-pam-sync` Expected: `755`.
- `ci/gate-single-copy`, `ci/gate-arch-leak`, `ci/gate-dropped-refs`, `ci/gate-name-map` against that payload Expected: all four `PASS`, findings counts unchanged from before this task (arch-leak 7 allowed, dropped-refs 6 allowed, name-map covers 56 names).

- [ ] **Step 11: Commit**

```bash
git add distro/fedora/pam distro/fedora/bin/tinkero-pam-sync build/assemble tinkero.spec.in install.sh .github/workflows/ci.yml tests/test-assemble.sh tests/test-render-spec.sh tests/test-install.sh tests/test-pam-sync.sh
git commit -m "pam: the two lock-screen variants and tinkero-pam-sync; %posttrans and %ghost; install.sh runs it after dnf install"
```

**Verification for the issue:** Step 10's commands, plus CI green. What CI cannot prove and the VM check (design section 7, item 3) owes: that the real `pam_faillock` counts and resets against a live login manager, that SELinux logs no AVC for the `mktemp`-then-`mv` write inside `/etc/pam.d` on a real host, and that `%posttrans` actually runs `tinkero-pam-sync` against a real `/etc/pam.d/password-auth` during a COPR-built install (this task proves only that the scriptlet and its message are in the rendered, parsed spec; the binary-RPM build and inspection, design D14, is the later task that adds it to CI).

---

### Task 4: The fingerprint port

**Files:**
- Create: `patches/0011-omarchy-apply-lock-fingerprint-only.patch`
- Create: `distro/fedora/replacements/omarchy-setup-security-fingerprint`, `distro/fedora/replacements/omarchy-remove-security-fingerprint` (they shadow the upstream commands of the same name, so no `replacements.new` entry)
- Modify: `patches/series`, `distro/fedora/pkgmap.tsv`, `ci/allow/arch-leak.allow`, `distro/fedora/skills/host.md`, `menu/overrides.jsonc`
- Test: `tests/test-replacements.sh`

**Interfaces:**
- Consumes: `elevate()` and `TINKERO_PKG_LIB` from `distro/fedora/lib/pkg.sh` (plan 2B); `omarchy-pkg-add` and `omarchy-hw-fingerprint` (both already on `PATH` once assembled); `/etc/pam.d/system-auth`, which authselect maintains and 2F does not touch.
- Produces: a patched `bin/omarchy-apply-lock` that writes only `/etc/pam.d/omarchy-lock-fingerprint`, gated on the host's own `with-fingerprint` setting; two replacement commands that enroll a print and flip that setting on or off; a menu Remove > Fingerprint row gated on that same file's presence, not on `fprintd` being installed. Task 3 (`tinkero-pam-sync`) owns `/etc/pam.d/omarchy-lock-password`; this task's patch only stops `omarchy-apply-lock` from writing it.

**Verification choice (read before Step 1):** spec 4.2 says the upstream tree is never copied into this repo, so the patched script cannot be tested by keeping a copy of upstream's file as a fixture. Patch 0011 is therefore verified two ways, both against the real tree: `git apply -p1 --check` inside `build/assemble` itself (assemble already dies loudly if a patch stops applying cleanly, so a green `./dev gates` run *is* the patch-applies proof), and a grep-based check in this task's verification step that reads the assembled payload's `usr/bin/omarchy-apply-lock` for the expected lines and the absence of the two upstream strings the patch deletes (`omarchy-lock-password`, `system-local-login`). The two replacement commands are fully hermetic (stubs on `PATH`, no tarball needed) and get a real `tests/test-replacements.sh` block.

- [ ] **Step 1: Generate patch 0011 against the pinned tag**

Extract the pinned tree if you have not already (`mkdir -p .cache/tree && tar -xzf .cache/omarchy-*.tar.gz -C .cache/tree --strip-components=1`) and read `.cache/tree/bin/omarchy-apply-lock`. Edit a scratch copy per design 5.1: delete the block that writes `/etc/pam.d/omarchy-lock-password` (the `echo "Configuring lock screen password authentication..."` line through the `tee ... <<'EOF' ... EOF` heredoc that follows it, plus the blank line that separated it from the `as_root` function above); add a third condition to the fingerprint `if`, a grep of `/etc/pam.d/system-auth` for an active line naming `pam_fprintd.so`; change the fingerprint file's `account` line from `system-local-login` to `password-auth`. Generate the patch with `diff -u` against `a/bin/omarchy-apply-lock` / `b/bin/omarchy-apply-lock` prefixes (the same shape 0001 to 0010 use), with a short prose header above the diff, no `diff --git` line:

`patches/0011-omarchy-apply-lock-fingerprint-only.patch`:

```
Port omarchy-apply-lock to write only the fingerprint PAM file.

The password file is tinkero-pam-sync's (spec 4.8): it is built for a Fedora
password-auth stack, not written here, so the block that shelled out to
Arch's pam_unix/pam_systemd_home stack is deleted outright. The fingerprint
file is still this script's job, gated on the host's own login offering a
finger too (system-auth naming pam_fprintd.so), so removing fingerprint with
`authselect disable-feature with-fingerprint` also takes it off the lock; its
account line includes password-auth, which exists on Fedora, instead of
system-local-login, which does not.

--- a/bin/omarchy-apply-lock
+++ b/bin/omarchy-apply-lock
@@ -26,27 +26,14 @@
   fi
 }
 
-echo "Configuring lock screen password authentication..."
-
-as_root tee /etc/pam.d/omarchy-lock-password >/dev/null <<'EOF'
-#%PAM-1.0
-auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
--auth      [success=2 default=ignore]  pam_systemd_home.so
-auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok
-auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
-auth       optional                    pam_permit.so
-auth       required                    pam_env.so
-auth       required                    pam_faillock.so authsucc
-account    include                     system-local-login
-EOF
-
 if [[ -x /usr/bin/fprintd-list ]] &&
-  /usr/bin/fprintd-list "$target_user" 2>/dev/null | grep -qi finger; then
+  /usr/bin/fprintd-list "$target_user" 2>/dev/null | grep -qi finger &&
+  grep -qE '^[[:space:]]*-?auth[[:space:]].*pam_fprintd\.so' /etc/pam.d/system-auth 2>/dev/null; then
   echo "Configuring lock screen fingerprint authentication..."
   as_root tee /etc/pam.d/omarchy-lock-fingerprint >/dev/null <<'EOF'
 #%PAM-1.0
 auth       required                    pam_fprintd.so
-account    include                     system-local-login
+account    include                     password-auth
 EOF
 else
   as_root rm -f /etc/pam.d/omarchy-lock-fingerprint
```

The summary header (`# omarchy:summary=Configure Quickshell lock screen authentication`) stays byte-identical: the script still configures lock screen authentication, just one PAM file's worth instead of two, so rewording it would be a change with nothing behind it. Everything else in the file (the root `PATH` guard, `target_user` resolution from `OMARCHY_INSTALL_USER`/`SUDO_USER`/`PKEXEC_UID`, `as_root`, the `omarchy-shell lock status` echo) is untouched.

Verify the patch applies cleanly and produces exactly this file, against the extracted tree, before moving on:

```bash
cd .cache/tree && git apply -p1 --check ../../patches/0011-omarchy-apply-lock-fingerprint-only.patch && git apply -p1 ../../patches/0011-omarchy-apply-lock-fingerprint-only.patch
grep -c 'omarchy-lock-password\|system-local-login' bin/omarchy-apply-lock   # expect 0
cd ../..
```

Changed-line count (measured, `+`/`-` lines excluding the `---`/`+++` header pair): 16 removed, 3 added, 19 total.

Append the patch name to `patches/series`:

```
0001-omarchy-version-from-rpm.patch
0002-omarchy-debug-rpm-inventory.patch
0003-omarchy-reinstall-configs-provision-reset.patch
0004-omarchy-remove-launcher-entry-rpm.patch
0005-omarchy-remove-dev-env-pkg-drop.patch
0006-omarchy-skill-host-guide.patch
0007-diagnose-crash-fedora-debuginfod.patch
0008-omarchy-launch-about-fastfetch-config.patch
0009-sshd-firewalld.patch
0010-menu-package-guards-rpm.patch
0011-omarchy-apply-lock-fingerprint-only.patch
```

- [ ] **Step 2: The two replacements**

`distro/fedora/replacements/omarchy-setup-security-fingerprint` (spec 4.3, design 5.2). `set -euo pipefail`, not the `-uo` (no `-e`) that `omarchy-pkg-add`/`omarchy-pkg-drop` use: those two loop over several package names and must keep going after one fails so they can report on all of them, but this script is upstream's own linear sequence of gated steps (detect, install, enroll, verify, then the two elevated calls). Detect, enroll and verify are already wrapped in an explicit `if`; install (`omarchy-pkg-add`) and the two elevated calls are plain statements the script means to abort on, exactly the CLAUDE.md-default behaviour, so `-e` is the right default here and not an addition that needs its own guard:

```bash
#!/bin/bash

# omarchy:summary=Set up fingerprint authentication for the lock screen
# omarchy:requires-sudo=true

# Tinkero: sudo, polkit and the clamshell gate stay authselect's (design D12); this only
# enrolls a print and turns the host's own with-fingerprint feature on, which is what
# omarchy-apply-lock reads to decide whether the lock screen offers a finger too.
set -euo pipefail
# shellcheck source=distro/fedora/lib/pkg.sh
source "${TINKERO_PKG_LIB:-/usr/share/tinkero/pkg.sh}"

echo -e "\033[32mSetting up fingerprint scanner for authentication.\n\033[0m"

# Bail before installing anything if there's no reader to talk to.
if ! omarchy-hw-fingerprint; then
  echo -e "\033[31mNo fingerprint sensor detected.\033[0m"
  exit 1
fi

omarchy-pkg-add fprintd fprintd-pam

# Fedora's fprintd polkit policy lets the active session enroll its own finger, so no
# sudo (unlike upstream's Arch stack, which runs this as root).
echo -e "\033[32m\nLet's set up your right index finger as the first fingerprint.\033[0m"
echo -e "Keep moving the finger around on the sensor until the process completes.\n"

if fprintd-enroll "$USER"; then
  echo -e "\033[32m\nFingerprint enrolled successfully!\033[0m"

  echo -e "\nNow let's verify that it's working correctly.\n"
  if fprintd-verify; then
    # A no-op when the feature is already on, which it is by default on Fedora 44
    # Workstation. omarchy-apply-lock then offers the lock screen a finger too.
    elevate authselect enable-feature with-fingerprint
    elevate omarchy-apply-lock
    echo -e "\033[32m\nPerfect! Fingerprint authentication is now configured.\033[0m"
    echo "You can use your fingerprint for the lock screen (Super + Ctrl + L)."
  else
    echo -e "\033[31m\nVerification failed. You may want to try enrolling again.\033[0m"
  fi
else
  echo -e "\033[31m\nEnrollment failed. Please try again.\033[0m"
  exit 1
fi
```

`elevate` runs `omarchy-apply-lock` and `authselect` by their bare names, the same way `omarchy-pkg-add` already runs `dnf` through it: `pkexec` resolves an unqualified `PROGRAM` against its own fixed search path (verified locally: `pkexec nonexistent-cmd` answers "Cannot run program ...: No such file or directory" rather than refusing for lack of an absolute path), and both commands land in `/usr/bin` once assembled, the same directory `dnf` is found in. No `command -v` or hard-coded `/usr/bin/` prefix is needed; using one here and not for `dnf` would be an inconsistency with no reader-visible reason.

Verification failure keeps upstream's own control flow: upstream does not `exit 1` when `fprintd-verify` fails either (enrollment already happened; only the PAM wiring is skipped), so neither does this port. The colour codes are `\033[...m`, matching `omarchy-pkg-add`'s convention in this tree, not upstream's `\e[...m`.

`distro/fedora/replacements/omarchy-remove-security-fingerprint` (design 5.2, D11):

```bash
#!/bin/bash

# omarchy:summary=Turn off fingerprint authentication for the whole host
# omarchy:requires-sudo=true

set -euo pipefail
# shellcheck source=distro/fedora/lib/pkg.sh
source "${TINKERO_PKG_LIB:-/usr/share/tinkero/pkg.sh}"

echo -e "\033[32mRemoving fingerprint scanner from authentication.\n\033[0m"
echo "This turns fingerprint login off for the whole host, GDM included, not just the lock screen."

elevate authselect disable-feature with-fingerprint
# system-auth no longer names pam_fprintd.so, so this also drops the lock screen's file.
elevate omarchy-apply-lock

# fprintd and fprintd-pam ship with Fedora Workstation (design D11): removing them would
# erase a Fedora default. The enrolled prints stay; they are the user's and GNOME's too.
echo -e "\033[32mFingerprint authentication has been turned off.\033[0m"
```

Both files replace the upstream commands of the same name (already present in the pinned tree, so `build/assemble`'s replacement step needs no `replacements.new` entry); `chmod 0755` is not needed by hand, `build/assemble` installs every replacement at mode `0755`.

- [ ] **Step 3: `pkgmap.tsv`**

In `distro/fedora/pkgmap.tsv`, `fprintd` is already mapped (row 21); insert the new row directly after it, keeping the file's sort order (`fprintd` < `fprintd-pam` < `fwupd`):

```diff
 fprintd	dnf	fprintd
+fprintd-pam	dnf	fprintd-pam
 fwupd	dnf	fwupd
```

- [ ] **Step 4: `menu/overrides.jsonc`: gate the Remove > Fingerprint row on the lock file, not on `fprintd` being present**

Upstream guards `remove.security.fingerprint` with `"when":"omarchy-pkg-present fprintd"`. Fedora Workstation ships `fprintd` and `fprintd-pam` by default and D11 never removes them, so that guard is always true and the row always shows, whether or not the lock screen actually offers a finger. Gate it on the file this task's patch writes instead (design section 5.2, D11):

In `menu/overrides.jsonc`, add a `replace` entry, keeping upstream's `icon`, `label` and `action` (from `default/omarchy/omarchy-menu.jsonc`) and changing only `when`:

```diff
   "replace": {
     // learn.omarchy opened the Omarchy manual; the id stays (identifiers keep upstream's names, spec 4.13),
     // the label and the target are Tinkero's, the glyph is the rebranded U+E900 (plan 2D)
     "learn.omarchy": {"icon":"","iconFont":"omarchy","label":"Tinkero","action":"omarchy-launch-browser https://github.com/dromeropa/tinkero#readme"},
     // update.omarchy ran omarchy-update; Tinkero updates through dnf, mise and flatpak (spec 4.7)
     "update.omarchy": {"icon":"","iconFont":"omarchy","label":"Packages","action":"omarchy-launch-floating-terminal-with-presentation tinkero-update"},
+    // remove.security.fingerprint: upstream gates the row on fprintd being installed; Fedora
+    // Workstation ships it by default and design D11 never removes it, so that guard is always
+    // true. Gate on the file omarchy-apply-lock actually writes instead (plan 2F, design D11).
+    "remove.security.fingerprint": {"icon":"󰈷","label":"Fingerprint","when":"test -f /etc/pam.d/omarchy-lock-fingerprint","action":"omarchy-launch-floating-terminal-with-presentation omarchy-remove-security-fingerprint"},
   },
```

`expect_rows` stays `258`: a `replace` swaps a row's content, it does not change the row count. `menu/apply-overrides`'s summary line moves from `2 replaced` to `3 replaced`.

- [ ] **Step 5: `ci/allow/arch-leak.allow`**

Remove the one line the fingerprint setup replacement clears (it named `pacman` before this task; the new replacement calls `omarchy-pkg-add` instead):

```diff
 usr/bin/omarchy-install-openclaw-cli   # comment only, permanent
-usr/bin/omarchy-setup-security-fingerprint   # plan 2F
 usr/share/omarchy/default/agents/skills/omarchy/hooks.md   # comment only, permanent
```

- [ ] **Step 6: `distro/fedora/skills/host.md`**

Rewrite the bullet that told the agent the fingerprint entry was not ported yet:

```diff
 - `/etc/pam.d`: PAM is managed by `authselect`. Fingerprint and other login features go
-  through `authselect enable-feature`; the fingerprint setup entry is ported to that in a
-  later plan (2F), and until then it is upstream's and must not be run on this host.
+  through `authselect enable-feature`/`disable-feature`. `omarchy setup security fingerprint`
+  enrolls a print and turns `with-fingerprint` on; the lock screen (Super+Ctrl+L) then offers
+  a finger too, because it reads the same host-wide setting. `omarchy remove security
+  fingerprint` turns `with-fingerprint` off host-wide, GDM included, and the lock screen with
+  it; it leaves `fprintd`/`fprintd-pam` installed and the enrolled prints in place, since both
+  ship with Fedora Workstation by default.
```

None of the arch-leak gate's tokens (`pacman`, `yay`, `paru`, `expac`, `makepkg`, `limine`, `mkinitcpio`, `snapper`, `ufw`, `pkgs.omarchy.org`, `archlinux`, `checkupdates`, `paccache`, `pactree`) appear in the new text.

- [ ] **Step 7: Tests**

Append to `tests/test-replacements.sh`, just before the final `rm -rf "$d"; finish` line. It reuses `$d`, `$LOG`, `$R` and the `pkexec`/`sudo`/`TINKERO_EUID` seams the file already sets up; each new stub logs its own argv the same way the existing `rpm`/`flatpak`/`dnf` stubs do, and the three that can fail read their exit code from a file so one case can flip it without rebuilding the others:

```bash
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
```

Run: `bash tests/test-replacements.sh` Expected: `1..54`, no `not ok` (was `1..36`; this task adds 18 cases).

- [ ] **Step 8: Verify against the real tree**

```bash
shellcheck -x -e SC1090,SC1091 distro/fedora/replacements/omarchy-setup-security-fingerprint distro/fedora/replacements/omarchy-remove-security-fingerprint tests/test-replacements.sh
./dev check
./dev gates
```

Expected: ShellCheck clean; `./dev check` all green (`test-replacements` at `1..54`); `./dev gates` prints six `PASS` lines, in particular `PASS: files naming Arch tooling (6 allowed finding(s))` (down from 7).

Then check the patched script inside the assembled payload directly, since the patch itself has no hermetic test (see the note above Step 1):

```bash
grep -c 'omarchy-lock-password\|system-local-login' .cache/payload/usr/bin/omarchy-apply-lock   # expect 0
grep -c 'account    include                     password-auth' .cache/payload/usr/bin/omarchy-apply-lock   # expect 1
grep -c "pam_fprintd\\\\.so' /etc/pam.d/system-auth" .cache/payload/usr/bin/omarchy-apply-lock   # expect 1
```

Expected: `0`, `1`, `1`. (Measured against this task's own assembled payload: `0`, `1`, `1`.)

Then check the menu row (`build/assemble` calls `menu/apply-overrides` as part of the tree steps that produced `.cache/payload` above):

```bash
grep -c "^apply-overrides: .* 3 replaced" <(build/assemble .cache/omarchy-*.tar.gz .cache/payload 2>&1)   # or re-check the log from the run above; expect 1
grep -F '"remove.security.fingerprint"' .cache/payload/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc
```

Expected: the assemble log's `apply-overrides:` summary line says `3 replaced` (was `2 replaced`); the menu row's `when` is `test -f /etc/pam.d/omarchy-lock-fingerprint`, its `icon`, `label` and `action` unchanged from upstream's.

Run: `ci/gate-name-map .cache/payload distro/fedora/pkgmap.tsv` Expected: `PASS: name map covers 54 package name(s) used by the payload` (was 56 at the end of Task 3; `fprintd` is still used, now only through the setup replacement's `omarchy-pkg-add fprintd fprintd-pam`, not through the menu's old `when`, but the count still drops by two: upstream's own setup and remove scripts, which this task's replacements shadow, also named `libfprint`, `libfprint-git` and `usbutils` through `omarchy-pkg-missing`/`omarchy-pkg-drop`; the replacements need neither the git driver nor `usbutils`, so those three names stop being used, `fprintd-pam` is the only one added, net -2).

- [ ] **Step 9: Commit**

```bash
git add patches/0011-omarchy-apply-lock-fingerprint-only.patch patches/series \
  distro/fedora/replacements/omarchy-setup-security-fingerprint \
  distro/fedora/replacements/omarchy-remove-security-fingerprint \
  distro/fedora/pkgmap.tsv distro/fedora/skills/host.md \
  ci/allow/arch-leak.allow menu/overrides.jsonc tests/test-replacements.sh
git commit -m "fingerprint: port omarchy-apply-lock to the fingerprint file only, ship the setup/remove replacements"
```

**Verification for the issue:** `bash tests/test-replacements.sh` at `1..54`; `./dev check` green; `./dev gates` six `PASS`, `files naming Arch tooling (6 allowed finding(s))` in particular; the three greps in Step 8 against `.cache/payload/usr/bin/omarchy-apply-lock`; the menu row's `when` and the `3 replaced` count; `ci/gate-name-map` still `PASS`; `shellcheck -x -e SC1090,SC1091` clean on both replacements and the test file.

---

### Task 5: The binary RPM in CI

**Files:**
- Create: `ci/check-rpm`, `tests/test-check-rpm.sh`
- Modify: `dev` (a `gates-at DIR` command), `.github/workflows/ci.yml` (tools, timeout, ShellCheck list, one step)

**Interfaces:**
- Consumes: Task 1's `usr/share/uwsm/env.d/20-tinkero`; Task 2's `ci/gate-session-units` inside `./dev gates`; Task 3's `%posttrans`, the two `%ghost` lines, `usr/bin/tinkero-pam-sync` and `usr/share/tinkero/pam/*`.
- Produces: `ci/check-rpm RPM DIR` (exit 0 pass, 1 findings, 2 bad input; unpacks the payload into DIR) and `./dev gates-at DIR` (the gates of `./dev gates` against any unpacked payload). Task 8's post-merge check reuses both on the COPR's RPM.

Design D14: COPR builds are post-merge, so CI rebuilds the SRPM it already makes into the binary RPM, checks what 2F put into the package that no gate on the assembled tree can see (file flags, the scriptlet), and runs every gate on the RPM's own payload, which is what spec 8 item 1 asks for ("build the RPM; grep the installed payload").

- [ ] **Step 1: Write the failing test**

`tests/test-check-rpm.sh` (new):

```bash
#!/bin/bash
# ci/check-rpm against stub rpm and rpm2cpio: rpm answers the two queries from files the test
# writes, rpm2cpio prints a cpio archive the test builds from a fixture payload.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"
cat > "$d/bin/rpm" <<'S'
#!/bin/bash
case "$*" in
  *POSTTRANS*) cat "$POSTTRANS" ;;
  *FILEFLAGS*) cat "$FILES" ;;
  *) exit 1 ;;
esac
S
# shellcheck disable=SC2016  # $ARCHIVE belongs to the stub
printf '#!/bin/bash\ncat "$ARCHIVE"\n' > "$d/bin/rpm2cpio"
chmod +x "$d/bin"/*
export PATH=$d/bin:$PATH FILES=$d/files POSTTRANS=$d/posttrans ARCHIVE=$d/payload.cpio
: > "$d/tinkero.rpm"
good_files() {
  cat > "$FILES" <<'F'
g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-password
g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-fingerprint
 -rwxr-xr-x root:root /usr/bin/tinkero-pam-sync
F
  echo '/usr/bin/tinkero-pam-sync || echo "tinkero: tinkero-pam-sync failed" >&2' > "$POSTTRANS"
}
payload() {   # build the archive from a fixture payload; extra args are paths to leave out
  local p=$d/p skip
  rm -rf "$p"; mkdir -p "$p/usr/bin" "$p/usr/share/tinkero/pam" "$p/usr/share/uwsm/env.d"
  printf '#!/bin/bash\n' > "$p/usr/bin/tinkero-pam-sync"; chmod 755 "$p/usr/bin/tinkero-pam-sync"
  echo wrapped > "$p/usr/share/tinkero/pam/omarchy-lock-password.wrapped"
  echo plain > "$p/usr/share/tinkero/pam/omarchy-lock-password.plain"
  echo 'export DCONF_PROFILE=tinkero' > "$p/usr/share/uwsm/env.d/20-tinkero"
  for skip in "$@"; do rm -f "$p/$skip"; done
  ( cd "$p" && find . -mindepth 1 | cpio -o -H newc --quiet ) > "$ARCHIVE"
}
C=$ROOT/ci/check-rpm

good_files; payload
out=$("$C" "$d/tinkero.rpm" "$d/x1"); rc=$?
assert_eq "$rc" 0 "a good package passes"
assert_contains "$out" "PASS: rpm tinkero.rpm" "and says so"
assert_file "$d/x1/usr/share/uwsm/env.d/20-tinkero" "the payload is unpacked into DIR"

sed -i 's#^g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-password#c -rw-r--r-- root:root /etc/pam.d/omarchy-lock-password#' "$FILES"
out=$("$C" "$d/tinkero.rpm" "$d/x2"); rc=$?
assert_eq "$rc" 1 "a PAM file that is not %ghost fails"
assert_contains "$out" "FAIL: /etc/pam.d/omarchy-lock-password: want 'g -rw-r--r-- root:root', got 'c -rw-r--r-- root:root'" "and names the flags"

good_files; sed -i '/omarchy-lock-fingerprint/d' "$FILES"
out=$("$C" "$d/tinkero.rpm" "$d/x3"); rc=$?
assert_eq "$rc" 1 "a missing fingerprint entry fails"
assert_contains "$out" "FAIL: /etc/pam.d/omarchy-lock-fingerprint is not in the package" "and names it"

good_files; sed -i 's#^g -rw-r--r-- root:root /etc/pam.d/omarchy-lock-fingerprint#g -rw------- root:root /etc/pam.d/omarchy-lock-fingerprint#' "$FILES"
out=$("$C" "$d/tinkero.rpm" "$d/x4"); rc=$?
assert_contains "$out" "FAIL: /etc/pam.d/omarchy-lock-fingerprint: want 'g -rw-r--r-- root:root', got 'g -rw------- root:root'" "a wrong mode fails"

good_files; echo '(none)' > "$POSTTRANS"
out=$("$C" "$d/tinkero.rpm" "$d/x5"); rc=$?
assert_eq "$rc" 1 "no %posttrans fails"
assert_contains "$out" "%posttrans does not run /usr/bin/tinkero-pam-sync" "and says so"

good_files; payload usr/share/uwsm/env.d/20-tinkero
out=$("$C" "$d/tinkero.rpm" "$d/x6"); rc=$?
assert_eq "$rc" 1 "a payload without the env file fails"
assert_contains "$out" "FAIL: payload lacks /usr/share/uwsm/env.d/20-tinkero" "and names it"

payload; mkdir -p "$d/p/etc/pam.d"; echo x > "$d/p/etc/pam.d/omarchy-lock-password"
( cd "$d/p" && find . -mindepth 1 | cpio -o -H newc --quiet ) > "$ARCHIVE"
out=$("$C" "$d/tinkero.rpm" "$d/x7"); rc=$?
assert_contains "$out" "FAIL: %ghost file /etc/pam.d/omarchy-lock-password has content in the payload" "a ghost file with content fails"

payload; mkdir -p "$d/x8"; echo x > "$d/x8/stale"
out=$("$C" "$d/tinkero.rpm" "$d/x8" 2>&1); rc=$?
assert_eq "$rc" 2 "a non-empty DIR is refused"
assert_contains "$out" "DIR must be empty" "and says so"
"$C" >/dev/null 2>&1; assert_eq "$?" 2 "no arguments print usage and exit 2"
rm -rf "$d"; finish
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/test-check-rpm.sh`
Expected: every case `not ok` (no `ci/check-rpm` yet), exit 1.

- [ ] **Step 3: `ci/check-rpm`**

`fflags` prints the flag letters in the order `c` (config), `m` (missingok), `n` (noreplace), `g` (ghost): a plain `%ghost` with no `%config` is just `g` (design D9; checked against the host's own rpm database while planning: 1882 files are `g`).

```bash
#!/bin/bash
# check-rpm RPM DIR: what plan 2F promises about the built package (design 2F, D14). CI runs it
# on the binary RPM it rebuilds from the SRPM, then runs the gates on DIR (./dev gates-at DIR).
# Unpacks the payload into DIR (which must be empty or absent) and checks:
#   1. the two PAM files are %ghost entries with their flags, mode 0644, root:root, and are not
#      in the payload;
#   2. %posttrans runs tinkero-pam-sync;
#   3. the payload has tinkero-pam-sync, both PAM variants and uwsm's 20-tinkero env file.
# Needs rpm, rpm2cpio and cpio.
set -euo pipefail
[[ $# -eq 2 && -f $1 ]] || { echo "usage: check-rpm RPM DIR" >&2; exit 2; }
rpm=$1; dir=$2
[[ ! -e $dir || -z $(ls -A "$dir" 2>/dev/null) ]] || { echo "check-rpm: DIR must be empty: $dir" >&2; exit 2; }
rc=0
fail() { echo "FAIL: $*"; rc=1; }

# 1. File flags: fflags prints c (config), m (missingok), n (noreplace), g (ghost), in that order.
files=$(rpm -qp --qf '[%{FILEFLAGS:fflags} %{FILEMODES:perms} %{FILEUSERNAME}:%{FILEGROUPNAME} %{FILENAMES}\n]' "$rpm")
want() {   # PATH FLAGS
  local line
  line=$(awk -v p="$1" '$4 == p' <<<"$files")
  if [[ -z $line ]]; then fail "$1 is not in the package"; return; fi
  [[ $line == "$2 -rw-r--r-- root:root $1" ]] || fail "$1: want '$2 -rw-r--r-- root:root', got '${line% "$1"}'"
}
want /etc/pam.d/omarchy-lock-password g
want /etc/pam.d/omarchy-lock-fingerprint g

# 2. The scriptlet.
posttrans=$(rpm -qp --qf '%{POSTTRANS}\n' "$rpm")
grep -q '^/usr/bin/tinkero-pam-sync' <<<"$posttrans" || fail "%posttrans does not run /usr/bin/tinkero-pam-sync: $posttrans"

# 3. The payload.
mkdir -p "$dir"
rpm2cpio "$rpm" | ( cd "$dir" && cpio -idm --quiet )
for p in usr/bin/tinkero-pam-sync usr/share/tinkero/pam/omarchy-lock-password.wrapped \
         usr/share/tinkero/pam/omarchy-lock-password.plain usr/share/uwsm/env.d/20-tinkero; do
  [[ -f $dir/$p ]] || fail "payload lacks /$p"
done
[[ -x $dir/usr/bin/tinkero-pam-sync ]] || fail "/usr/bin/tinkero-pam-sync is not executable"
for p in etc/pam.d/omarchy-lock-password etc/pam.d/omarchy-lock-fingerprint; do
  [[ ! -e $dir/$p ]] || fail "%ghost file /$p has content in the payload"
done

if ((rc == 0)); then echo "PASS: rpm $(basename "$rpm") (ghost PAM files, %posttrans, payload files)"; fi
exit $rc
```

`chmod +x ci/check-rpm`.

- [ ] **Step 4: `./dev gates-at DIR`**

In `dev`, add the help line after the `./dev gates` line:

```bash
#   ./dev gates-at DIR   run the CI gates against an unpacked payload (CI: the binary RPM's)
```

add the case after `gates)`:

```bash
  gates-at) [[ -d ${2:-} ]] || { echo "usage: ./dev gates-at DIR" >&2; exit 2; }; payload=$2; gates ;;
```

and widen the usage printer from `sed -n '2,9p'` to `sed -n '2,10p'`.

- [ ] **Step 5: CI**

In `.github/workflows/ci.yml`: add `cpio` to the `dnf -y install` list of the Tools step; raise `timeout-minutes: 15` to `timeout-minutes: 30` (the RPM build renders the wallpapers a second time); add `ci/check-rpm` to the ShellCheck list after `ci/gate-branding`; and append after the step "SRPM builds the way COPR builds it":

```yaml
      - name: The binary RPM builds from that SRPM and carries what plan 2F promises
        run: |
          rpmbuild --rebuild --define "_topdir $PWD/.cache/rpmbuild" .cache/srpm/*.src.rpm
          ci/check-rpm .cache/rpmbuild/RPMS/noarch/tinkero-*.noarch.rpm .cache/rpm-payload
          ./dev gates-at .cache/rpm-payload
```

The container already has the four `BuildRequires` (`git-core python3 python3-fonttools ImageMagick`) from the Tools step, so `rpmbuild` needs nothing else.

- [ ] **Step 6: Run the tests**

Run: `bash tests/test-check-rpm.sh` Expected: `1..16`, all ok.
Run: `./dev gates-at /nonexistent; echo $?` Expected: the usage line, `2`.
Run: `shellcheck -x -e SC1090,SC1091 ci/check-rpm tests/test-check-rpm.sh dev` Expected: no output.
Run: `./dev check` Expected: green.

- [ ] **Step 7: Commit**

```bash
git add ci/check-rpm tests/test-check-rpm.sh dev .github/workflows/ci.yml
git commit -m "ci: build the binary RPM and check its PAM ghosts, scriptlet and payload (plan 2F, D14)"
```

**Verification for the issue:** `bash tests/test-check-rpm.sh` at `1..16`; on the pushed branch, CI's new step prints `PASS: rpm tinkero-4.0.4-1.fc44.noarch.rpm (ghost PAM files, %posttrans, payload files)` followed by six gate `PASS` lines, and the job finishes inside 30 minutes. `rpmbuild` is not on the planning machine, so this step is the first `rpmbuild` of the `tinkero` package ever (Phase 1 built only the 25 substrate specs), and the 30-minute timeout is an estimate. Before dispatch, or as this task's first action, run it once locally: `podman run --rm -v "$PWD":/src:Z -w /src fedora:44 bash -c 'dnf -y install git-core curl rpm-build python3 python3-fonttools ImageMagick cpio make && make -f .copr/Makefile srpm outdir=/src/.cache/srpm && rpmbuild --rebuild --define "_topdir /src/.cache/rpmbuild" .cache/srpm/*.src.rpm'`. The brp scripts and unpackaged-file checks surface only here; expect a possible fix round (the planning review found no env-style shebangs outside the dropped `test/` directory). A failure is a Deviations line, not a skip.

---

### Task 6: `tinkero` in the COPR tooling

**Files:**
- Modify: `distro/fedora/specs/build-order.txt`, `build/tinkero-copr`, `tests/test-specs.sh`,
  `tests/test-copr.sh`, `docs/guides/workflow.md` (one number)

**Interfaces:**
- Consumes: `tinkero.spec.in` at the repo root (rendered by `.copr/Makefile`); the 25 existing
  specs in `distro/fedora/specs/`
- Produces: `distro/fedora/specs/build-order.txt` with tinkero as the last line (26 packages);
  `build/tinkero-copr` registration and build commands that handle tinkero specially (no
  `--subdir`, `--spec tinkero.spec`). Task 8's issue dispatches
  `gh workflow run copr-build --ref master -f packages=tinkero -f command=all`, which reaches
  `build/tinkero-copr all tinkero`; the workflow's `packages` input description ("Space-separated
  package names from distro/fedora/specs/build-order.txt, or 'all'") still reads true because
  `tinkero` is a name in that file, even though its spec lives at the root.

- [ ] **Step 1: Add tinkero to the build order**

In `distro/fedora/specs/build-order.txt`, after the `xdg-desktop-portal-hyprland` line add:

```
# the desktop package itself, spec rendered from tinkero.spec.in at the repo root by .copr/Makefile
tinkero
```

- [ ] **Step 2: Fix the now-stale package count in the workflow guide**

`docs/guides/workflow.md`'s "Four adaptations" section says "The 25 packages are registered
against `master`"; after Step 1 that is 26 (`tinkero` is registered by `tinkero-copr` too).
Change:

```
- **COPR builds are post-merge.** The 25 packages are registered against `master`, and a
```

to:

```
- **COPR builds are post-merge.** The 26 packages are registered against `master`, and a
```

(`distro/fedora/specs/README.md` does not state a package count anywhere, so it needs no
edit. The two historical mentions of "25 packages"/"25-package" in
`docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` and `docs/guides/workflow.md`'s own
"Baseline" bullet describe Phase 1's landed state as of a specific commit and stay correct as
history; they are not touched.)

- [ ] **Step 3: Update `build/tinkero-copr` to handle the desktop package**

In `build/tinkero-copr`, update the header comment to note that tinkero (the desktop package) is
built last from tinkero.spec.in at the repo root. Change the first paragraph to:

```
#   tinkero-copr register [PKG...]   (re)register packages as SCM/make_srpm sources
#   tinkero-copr build [PKG...]      build one at a time, waiting for each (the Hyprland
#                                    stack needs each -devel published before the next)
#   tinkero-copr all [PKG...]        register, then build
#   tinkero-copr order [PKG...]      print the build order and exit
#
# Without PKG arguments every package in distro/fedora/specs/build-order.txt is
# used; with them, only those, still in canonical order. The desktop package "tinkero"
# is built last from tinkero.spec.in at the root (design 2F, D13). Environment:
```

This inserts one extra line into the header comment block, which shifts the usage fallback
(the `*)` case at the bottom of the script) down by a line: it must be updated too, or the last
line of usage ("Needs copr-cli...") silently gets cut. Change:

```bash
  *)        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
```

to:

```bash
  *)        sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
```

In the existence check (the loop after `(( ${#all[@]} ))`), replace:

```bash
for p in "${all[@]}"; do
  [[ -f $root/distro/fedora/specs/$p.spec ]] || die "$p is in build-order.txt but distro/fedora/specs/$p.spec does not exist"
done
```

with:

```bash
for p in "${all[@]}"; do
  if [[ $p == tinkero ]]; then
    [[ -f $root/tinkero.spec.in ]] || die "$p is in build-order.txt but tinkero.spec.in does not exist"
  else
    [[ -f $root/distro/fedora/specs/$p.spec ]] || die "$p is in build-order.txt but distro/fedora/specs/$p.spec does not exist"
  fi
done
```

In the `register_one()` function, replace the entire function:

```bash
register_one() {
  local name=$1 add_err
  local args=(--name "$name" --clone-url "$clone" --commit "$commit"
              --subdir distro/fedora/specs --spec "$name.spec"
              --type git --method make_srpm --timeout 18000 --webhook-rebuild off)
  # add fails when the package exists, edit fails when it does not: try both, and
  # if both fail show both messages (an auth or network error hits add first)
  if [[ ${TINKERO_COPR_DRY_RUN:-0} == 1 ]]; then
    run copr-cli add-package-scm "$project" "${args[@]}"; echo "registered: $name (dry run)"; return 0
  fi
  if add_err=$(run copr-cli add-package-scm "$project" "${args[@]}" 2>&1); then echo "registered: $name"
  elif run copr-cli edit-package-scm "$project" "${args[@]}"; then echo "updated:    $name"
  else printf 'add-package-scm said: %s\n' "$add_err" >&2; die "could not register $name"; fi
}
```

with:

```bash
register_one() {
  local name=$1 add_err
  local args=(--name "$name" --clone-url "$clone" --commit "$commit")
  # tinkero (the desktop package) is built from tinkero.spec.in at the root; the rest are
  # built from distro/fedora/specs/<name>.spec
  if [[ $name == tinkero ]]; then
    args+=(--spec tinkero.spec)
  else
    args+=(--subdir distro/fedora/specs --spec "$name.spec")
  fi
  args+=(--type git --method make_srpm --timeout 18000 --webhook-rebuild off)
  # add fails when the package exists, edit fails when it does not: try both, and
  # if both fail show both messages (an auth or network error hits add first)
  if [[ ${TINKERO_COPR_DRY_RUN:-0} == 1 ]]; then
    run copr-cli add-package-scm "$project" "${args[@]}"; echo "registered: $name (dry run)"; return 0
  fi
  if add_err=$(run copr-cli add-package-scm "$project" "${args[@]}" 2>&1); then echo "registered: $name"
  elif run copr-cli edit-package-scm "$project" "${args[@]}"; then echo "updated:    $name"
  else printf 'add-package-scm said: %s\n' "$add_err" >&2; die "could not register $name"; fi
}
```

- [ ] **Step 4: Update `tests/test-specs.sh` to handle tinkero**

In `tests/test-specs.sh`, change the count assertions to 26 and 25 with clearer messages. Replace:

```bash
mapfile -t order < <(grep -vE '^\s*(#|$)' "$D/build-order.txt")
assert_eq "${#order[@]}" 25 "build-order.txt lists 25 packages"
specs=("$D"/*.spec); assert_eq "${#specs[@]}" 25 "there are 25 spec files"
```

with:

```bash
mapfile -t order < <(grep -vE '^\s*(#|$)' "$D/build-order.txt")
assert_eq "${#order[@]}" 26 "build-order.txt lists 26 packages (25 in distro/fedora/specs, tinkero at root)"
specs=("$D"/*.spec); assert_eq "${#specs[@]}" 25 "there are 25 spec files in distro/fedora/specs (tinkero.spec.in is at the root)"
```

The per-spec loop right after this iterates over `specs` (still 25 spec files under
`distro/fedora/specs/`, unaffected by the new `tinkero` line) and only checks, for each spec
file, that its name appears somewhere in `order`; it does not require `order` and `specs` to
have the same members, so the extra `tinkero` entry in `order` does not break it.

After the per-spec loop, replace:

```bash
ok "per-spec checks ran"
assert_file "$D/srpm.sh" "srpm.sh present"; assert_file "$D/macros.hyprland" "hyprland macros present"
```

with:

```bash
ok "per-spec checks ran"
# tinkero (the desktop package) is built from tinkero.spec.in at the root, not from distro/fedora/specs
if printf '%s\n' "${order[@]}" | grep -qx tinkero; then
  ok "tinkero is in build-order.txt"
else
  not_ok "tinkero is in build-order.txt" "not found"
fi
assert_file "$ROOT/tinkero.spec.in" "tinkero.spec.in present at the root"
assert_file "$D/srpm.sh" "srpm.sh present"; assert_file "$D/macros.hyprland" "hyprland macros present"
```

(An `A || not_ok` followed by an unconditional `ok` would emit a different number of tally
lines depending on whether the check passed, like line 12's existing per-spec `|| not_ok` with
no matching `ok`. Using if/else here keeps exactly one tally line for the "in build-order.txt"
check and one for `assert_file`, in both outcomes: +2 over the previous total either way.)

- [ ] **Step 5: Update `tests/test-copr.sh` to verify tinkero**

In `tests/test-copr.sh`, update the order checks. Replace:

```bash
assert_eq "$("$T" order | head -n1)" tinkero-nerd-fonts "order: first package"
assert_eq "$("$T" order | wc -l)" 25 "order: all 25"
assert_eq "$("$T" order hyprutils glaze | paste -sd' ')" "glaze hyprutils" "order: subset keeps canonical order"
```

with:

```bash
assert_eq "$("$T" order | head -n1)" tinkero-nerd-fonts "order: first package"
assert_eq "$("$T" order | wc -l)" 26 "order: all 26 (25 in specs, tinkero at root)"
assert_eq "$("$T" order | tail -n1)" tinkero "order: tinkero is last"
assert_eq "$("$T" order hyprutils glaze | paste -sd' ')" "glaze hyprutils" "order: subset keeps canonical order"
```

After the existing dry-run register block and before the "all" count line, replace:

```bash
out=$(TINKERO_COPR_DRY_RUN=1 "$T" register glaze 2>&1)
assert_contains "$out" "copr-cli add-package-scm dromero/tinkero --name glaze" "dry run: register prints the add command"
assert_contains "$out" "registered: glaze (dry run)" "dry run: register says it is a dry run"
assert_eq "$(TINKERO_COPR_DRY_RUN=1 "$T" all 2>&1 | grep -c '^copr-cli ')" 50 "dry run: all prints 25 register and 25 build commands"
```

with:

```bash
out=$(TINKERO_COPR_DRY_RUN=1 "$T" register glaze 2>&1)
assert_contains "$out" "copr-cli add-package-scm dromero/tinkero --name glaze" "dry run: register prints the add command"
assert_contains "$out" "registered: glaze (dry run)" "dry run: register says it is a dry run"
: > "$LOG"; "$T" register tinkero >/dev/null
assert_contains "$(cat "$LOG")" "add-package-scm dromero/tinkero --name tinkero --clone-url https://github.com/dromeropa/tinkero.git --commit master --spec tinkero.spec --type git --method make_srpm" "register tinkero: no --subdir, --spec tinkero.spec"
if grep -qF -- '--subdir' "$LOG"; then
  not_ok "register tinkero: must not have --subdir"
else
  ok "register tinkero: no --subdir"
fi
: > "$LOG"; "$T" build tinkero >/dev/null
assert_contains "$(cat "$LOG")" "copr-cli build-package dromero/tinkero --name tinkero" "build tinkero: one build-package for tinkero"
assert_eq "$(TINKERO_COPR_DRY_RUN=1 "$T" all 2>&1 | grep -c '^copr-cli ')" 52 "dry run: all prints 26 register and 26 build commands"
```

(This asserts registration and build against the stub's `$LOG`, the same way the file's existing
"register: add with the SCM settings" case does, so it exercises the real, non-dry-run code
path in `register_one()` and `build_one()`, not just the `run()` dry-run branch. `$EXISTING`
still only contains `glaze` at this point in the file, so `add-package-scm` for `tinkero`
succeeds. The `--subdir` check uses if/else, not `A && B || C` (SC2015).)

- [ ] **Step 6: Run the tests, ShellCheck and `./dev check`**

Run: `bash tests/test-specs.sh`
Expected: `1..84` (was 82, +2: "tinkero is in build-order.txt" and "tinkero.spec.in present at
the root"), no `not ok`.

Run: `bash tests/test-copr.sh`
Expected: `1..21` (was 17, +4: "order: tinkero is last", "register tinkero: no --subdir, --spec
tinkero.spec", "register tinkero: no --subdir", "build tinkero: one build-package for tinkero"),
no `not ok`.

Run: `shellcheck -x -e SC1090,SC1091 build/tinkero-copr tests/test-copr.sh tests/test-specs.sh`
Expected: no output.

Run: `./dev check`
Expected: all tests green, including test-specs (`1..84`) and test-copr (`1..21`); every other
test file's tally unchanged from master.

- [ ] **Step 7: Commit**

```bash
git add distro/fedora/specs/build-order.txt build/tinkero-copr tests/test-specs.sh tests/test-copr.sh docs/guides/workflow.md
git commit -m "build: tinkero-copr registers and builds the tinkero package (plan 2F, D13)"
```

**Verification for the issue:** Step 6's commands pass with the tallies above. The registration
command for tinkero omits `--subdir` and passes `--spec tinkero.spec` (no path); the build
command is a plain `build-package ... --name tinkero`. Build-order.txt lists tinkero as the
26th and final line. `.copr/Makefile` already routes the rendered `tinkero.spec` to the SRPM
step. The COPR build and depsolve proof that `BuildRequires: python3` and other requirements
reach the mock chroot and that no `nwg-panel` or `playerctl` are installed is owed by the
post-merge, operator-dispatched COPR build step on the issue (workflow guide, adaptation 1;
Task 8 dispatches it with `packages=tinkero command=all`).

---

### Task 7: Docs

**Files:**
- Create: `docs/guides/phase-2f-vm-check.md`
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` (status line, 4.2, 4.3, 4.6, 4.8, 4.9, the decision log, 12), `docs/research/arch-coupling-audit.md` (sections 4.3 and 9), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (the 2F row, a "What executing 2F added to the queue" section), `docs/guides/workflow.md` ("Where the build is"), `README.md` (the Remove section)

**Interfaces:**
- Consumes: every earlier task's facts (the counts below are the measured ones).
- Produces: the guide Task 9 runs; a master spec that says what the code now does.

Every edit below is an exact replacement: find the quoted text, replace it with the block. Where a sentence is amended rather than rewritten, the design decision that amends it is named, so the reader of the master spec can find the reason.

- [ ] **Step 1: The master spec**

In `docs/superpowers/specs/2026-09-17-tinkero-design.md`:

1. Status line: after `2D (branding) done 2026-09-24 (design: 2026-09-23-phase-2d-branding-design.md)` insert `; 2F (session integration) done 2026-09-XX (design: 2026-09-24-phase-2f-session-design.md), the first COPR build of tinkero and the VM check being its post-merge issues`.

2. 4.2, **Build.** paragraph: replace `COPR rebuilds on push through its GitHub webhook; no API token is needed for that.` with `The package is registered with its webhook off and built by the manually dispatched copr-build workflow, like the rest of the set, so a build that publishes to users is always a post-merge decision (plan 2F, design D13).`

3. 4.2, `%install` item 6: replace `the user systemd units (upstream's kept ones with their \`[Install]\` sections stripped at build time, the \`omarchy-fcitx5\` drop-in, \`tinkero-inhibit-power-key.service\` and \`tinkero-gnome-restore.service\`; nothing is enabled) (4.9)` (the wording PR #22 left) with `the user systemd units (upstream's kept ones with their \`[Install]\` sections stripped at build time, inside the tree as well as in \`/usr/lib/systemd/user\`, Tinkero's drop-ins for \`omarchy-fcitx5\`, \`bt-agent\` and \`omarchy-speaker-tuning\`, and \`tinkero-inhibit-power-key.service\`; nothing is enabled) (4.9), \`/usr/share/uwsm/env.d/20-tinkero\` (the \`DCONF_PROFILE\` export, 4.9)`; and replace `with \`/etc/pam.d/omarchy-lock-password\` as a \`%ghost\` written by` with `with \`/etc/pam.d/omarchy-lock-password\` and \`omarchy-lock-fingerprint\` as \`%ghost\` files, the first written by`.

4. 4.3, the **Patches** sentence: replace `Twelve files, all but the first under fifteen changed lines (patches 0001 to 0010 exist after plan 2B; \`omarchy-apply-lock\` is plan 2F's):` with `Twelve files in eleven patches, all but the first and \`omarchy-apply-lock\` under fifteen changed lines (patch 0011, \`omarchy-apply-lock\`, has 19, sixteen of them the deleted password block):`.

5. 4.3, the fingerprint replacement row: replace `Remove: \`authselect disable-feature with-fingerprint\`, \`omarchy-apply-lock\`, \`omarchy-pkg-drop fprintd-pam\` |` with `Remove: \`authselect disable-feature with-fingerprint\` (host-wide; the command says so first), then \`omarchy-apply-lock\`; no package is removed, because Fedora Workstation installs \`fprintd\` and \`fprintd-pam\` and enables the feature by default (plan 2F, design D11). Upstream's lid-closed gate on \`sudo\` and \`polkit-1\` is not ported (D12) |`.

6. 4.6, the `tinkero-provision` paragraph: replace `None has an \`[Install]\` section: all are \`PartOf=graphical-session.target\`, which GNOME activates too, so they are only ever started from inside the Tinkero session (4.9).` with `None has an \`[Install]\` section, and all are \`PartOf=graphical-session.target\` (\`bt-agent\` and the speaker tuning through Tinkero's drop-ins, plan 2F design D2), so they are only ever started from inside the Tinkero session and stop with it (4.9); \`ci/gate-session-units\` checks both properties on every build. The list is \`provision/session-units.list\`, which also names the speaker tuning, present only on the laptops \`omarchy-audio-tuning\` matches.`

7. 4.8: replace `copies the variant that matches \`authselect current\`:` with `copies the variant the host's \`/etc/pam.d/password-auth\` calls for: \`plain\` when it has an active auth line naming \`pam_faillock.so\` (which on an authselect host is exactly \`with-faillock\`), \`wrapped\` otherwise (plan 2F, design D6). It writes through a temporary file in \`/etc/pam.d\`, so the file inherits that directory's SELinux label, and \`tinkero-pam-sync --check\` reports drift without root:`.

8. 4.8, the fingerprint paragraph: replace `the patched \`omarchy-apply-lock\` writes it only when \`fprintd-list\` shows enrolments for the target user (upstream's \`SUDO_USER\`/\`PKEXEC_UID\` logic) and removes it otherwise.` with `the patched \`omarchy-apply-lock\` writes it only when \`fprintd-list\` shows enrolments for the target user (upstream's \`SUDO_USER\`/\`PKEXEC_UID\` logic) and the host's \`system-auth\` uses \`pam_fprintd.so\` (plan 2F, design D10), and removes it otherwise. The RPM owns it as \`%ghost\`, no \`%config\` (rpm does not verify ghosts), so removal of the package removes it (D9).`

9. 4.9, the units bullet: replace `starts the five kept upstream units and Tinkero's own two at Tinkero session start` with `starts the units on \`provision/session-units.list\` (five kept upstream ones, the speaker tuning where it is installed, and \`tinkero-inhibit-power-key.service\`) at Tinkero session start`. Then the fallback bullet: after `and that the baseline would have to be captured at GNOME login, not at Tinkero start.` add ` Plan 2F does not ship the unit (design D5); its VM check decides whether it is ever needed.`

10. Section 11, the "Lock PAM file" row: replace `chosen by \`tinkero-pam-sync\` from the authselect profile;` with `chosen by \`tinkero-pam-sync\` from what the host's \`password-auth\` already does (2F D6);` (the cell's closing `(R2)` stays).

11. Section 12: delete the line `  systemd/tinkero-gnome-restore.service`; after `  systemd/omarchy-fcitx5.service.d/tinkero.conf` add `  systemd/{bt-agent,omarchy-speaker-tuning}.service.d/tinkero.conf` and `  session/uwsm-env.d/20-tinkero    the DCONF_PROFILE export (4.9)`; replace `    bin/tinkero-pam-sync           reads \`authselect current\`, so it is host-specific` with `    bin/tinkero-pam-sync           reads the host's password-auth, so it is host-specific`; replace `  ci/                              the four gates, lint, VM smoke test` with `  ci/                              the gates (six), check-rpm, lint, VM smoke test`.

12. Section 6, the Session services row: replace `\`bluez\`, \`NetworkManager\`,` with `\`bluez\`, \`bluez-tools\` (for \`bt-agent\`, the Bluetooth pairing agent the shell's panel uses), \`NetworkManager\`,` (plan 2F, design D17).

13. 4.8, the packaging sentence: replace `owns \`/etc/pam.d/omarchy-lock-password\` as a \`%ghost %config\` file` with `owns \`/etc/pam.d/omarchy-lock-password\` as a \`%ghost\` file (plan 2F, design D9)` (verify the exact current text before editing; this is a separate substring of the same paragraph item 7 also touches).

- [ ] **Step 2: The audit**

In `docs/research/arch-coupling-audit.md`, section 4.3: in the `omarchy-remove-security-fingerprint` row, replace `\`omarchy-apply-lock\` (which removes the fingerprint PAM file when no enrolment remains), \`omarchy-pkg-drop fprintd-pam\`.` with `\`omarchy-apply-lock\` (which removes the fingerprint PAM file once \`system-auth\` no longer uses \`pam_fprintd.so\`); no package removal (plan 2F, design D11).`. In section 9, replace `All but the first are under fifteen changed lines.` with `All but the first and patch 0011 are under fifteen changed lines.`, and replace `\`omarchy-apply-lock\` waits for plan 2F.` with `\`omarchy-apply-lock\` is patch 0011 (plan 2F, 19 changed lines, most of them a deletion).`

- [ ] **Step 3: The roadmap, the workflow guide, the README**

Roadmap, the 2F row's Status cell becomes `**done** 2026-09-XX: \`2026-09-24-phase-2f-session-integration.md\`; design \`specs/2026-09-24-phase-2f-session-design.md\`; the first COPR build and the VM check are its post-merge issues`. Add before "## What executing 2E added to the queue":

```
## What executing 2F added to the queue (2026-09-XX)

- **Post-merge (this plan's own issues):** the first COPR build of `tinkero` (Task 8: build, log facts, `ci/check-rpm` on the COPR's RPM, the `nwg-panel` depsolve), then the VM check (`docs/guides/phase-2f-vm-check.md`, Task 9).
- **Phase 3, `tinkero-status`:** `tinkero-pam-sync --check` is the PAM drift report (exit 0 or 1, one line; both PAM files are `%ghost` with no `%config`, so `rpm -V` does not see them, design D9); the release workflow archives `tinkero` with the set (it is the last line of `build-order.txt`).
- **Phase 3, VM smoke test:** sections 1, 3 and 4 of the VM-check guide are the automatable part.
- **Bump checklist:** a new upstream user unit is stripped automatically; decide whether it belongs on `provision/session-units.list` (and whether it needs a `PartOf` drop-in: `ci/gate-session-units` fails on a listed unit that is not bound to the session); rebase patch 0011 with the others.
- **Bare metal:** the speaker tuning not starting under GNOME on a laptop `omarchy-audio-tuning` matches (the 2E queue's line; a VM matches none); the lid-closed fingerprint prompt (design D12) and the polkit dialog's fingerprint mode, which reads `/etc/pam.d/polkit-1` for `pam_fprintd` and so stays in password mode on Fedora; the `learn.*` web-app rows on a Firefox host (D16), with what the VM check recorded.
- **Permanent allowlist entries, final:** arch-leak 6 (all comment-only), dropped-refs 6.
```

`docs/guides/workflow.md`, "Where the build is": replace the two bullets beginning `- Done since:` and `- Then 2F` with:

```
- Done since: 2C (menu rewrite, 2026-09-23), 2E (provisioning and install, 2026-09-23), 2D
  (branding, 2026-09-24) and 2F (session integration, 2026-09-XX; its first COPR build and VM
  check are post-merge issues).
- Then Phase 3 (maintenance), planned when 2F's post-merge issues are closed.
```

`README.md`, the Remove section: after `Files you changed are listed and kept.` insert ` Removing the package also removes the lock screen's two PAM files; a fingerprint setup made from the menu stays as the host's authselect setting, and the menu's Remove > Fingerprint entry is how to turn it off.`

- [ ] **Step 4: The VM-check guide**

Create `docs/guides/phase-2f-vm-check.md` with exactly this content:

````markdown
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
````

The guide's checkboxes are the Task 9 issue's record; its commands were written from the design and the upstream tree and are first executed in Task 9, which records every correction on its issue, as Phase 0 did.

- [ ] **Step 5: Verify and commit**

Run: `./dev check` Expected: green.
Run: `git diff -U0 -- docs README.md | grep '^+' | grep -c "—"` Expected: `0`.
Run: `grep -c 'gnome-restore' docs/superpowers/specs/2026-09-17-tinkero-design.md` Expected: `1` (the fallback bullet in 4.9 only).

```bash
git add docs README.md
git commit -m "docs: 2F done, session integration; spec amendments, roadmap queue, the VM-check guide"
```

**Verification for the issue:** the three commands, CI green, and the reviewer reads each edit against the 2F design's decisions. The `2026-09-XX` placeholders become the date the branch is pushed; the merge date is the operator's.

---

### Task 8: The first COPR build of `tinkero` (post-merge, closed by hand)

**Files:** none. This task's deliverable is a build and a record on its issue (workflow guide, adaptation 1: "COPR builds are post-merge").

**Interfaces:**
- Consumes: Tasks 1 to 7 on `master`; Task 6's `tinkero` row in `build-order.txt` and its registration path in `build/tinkero-copr`; Task 5's `ci/check-rpm` and `./dev gates-at`.
- Produces: the first `tinkero` build in `dromero/tinkero` for `fedora-44-x86_64`, which Task 9 installs.

Dispatch this issue only after the orchestrated PR has merged. `copr-build` publishes to the user-facing repository, and this issue is the one that says to trigger it.

- [ ] **Step 1: Register and build from `master`**

Run: `gh workflow run copr-build --ref master -f packages=tinkero -f command=all`
Then: `gh run watch "$(gh run list --workflow copr-build --limit 1 --json databaseId --jq '.[0].databaseId')"`
Expected: the job prints `registered: tinkero` (or `updated:    tinkero`) and `==> building tinkero in dromero/tinkero`, and ends green. The COPR import queue can hold a build in `importing` for 40 minutes (roadmap, COPR operations); that is not a hang.

- [ ] **Step 2: Read the build log**

Open the build's `builder-live.log` from the COPR web UI (build page, chroot `fedora-44-x86_64`). Expected: the mock root installs `python3`, `python3-fonttools` and `ImageMagick` (the proof issue #5 asked for); `build/assemble` prints `stripped [Install] from 7 unit(s)`, `258 rows out` and `assembled 367 commands`; `rpmbuild` writes `tinkero-4.0.4-1.fc44.noarch.rpm`.

- [ ] **Step 3: Check the COPR's RPM like CI checks its own**

On a Fedora 44 machine with the repository checked out at `master`:

```bash
d=$(mktemp -d); cd "$d"
dnf download --repofrompath=t,https://download.copr.fedorainfracloud.org/results/dromero/tinkero/fedora-44-x86_64/ --repo=t tinkero
cd - && ci/check-rpm "$d"/tinkero-*.noarch.rpm "$d/payload" && ./dev gates-at "$d/payload"
```

Expected: `PASS: rpm tinkero-4.0.4-1.fc44.noarch.rpm ...` and six gate `PASS` lines.

- [ ] **Step 4: The depsolve**

On a Fedora 44 Workstation (the Task 9 VM before installing, or any host) with the COPR enabled (`sudo dnf copr enable dromero/tinkero`):

Run: `sudo dnf install --assumeno tinkero 2>&1 | tee /tmp/depsolve.txt; grep -Ec '^ (nwg-panel|playerctl|wofi|newt) ' /tmp/depsolve.txt`
Expected: the transaction resolves (dnf stops only at the `--assumeno` answer), `hyprland 0.56.2` and `quickshell 0.3.0^20.git28771c7` come from `copr:copr.fedorainfracloud.org:dromero:tinkero`, and the count is `0`: `Conflicts: nwg-panel` drops the weak dependency Fedora's `Supplements: hyprland` would add (spec 6).

- [ ] **Step 5: Record and close**

Comment on the issue with: the COPR build id and link, the three log facts of Step 2, the `check-rpm` and gate lines of Step 3, the transaction summary of Step 4 (package count, the `hyprland` and `quickshell` lines). Close the issue by hand. A failure at any step is a new issue against the task that owns the cause, and this one stays open.

**Verification for the issue:** the comment of Step 5, with every expected line present.

---

### Task 9: The VM check (manual)

**Files:** none; the procedure is `docs/guides/phase-2f-vm-check.md` (Task 7). The results go on the issue and, summarised, into the roadmap.

**Interfaces:**
- Consumes: Task 8's COPR build; Task 7's guide; the Phase 0 VM and its checkpoint `tinkero-spike-clean-f44` (`docs/research/phase-0-findings.md`, environment notes: `qemu:///session`, `virt-viewer --attach`, user `dtest`).
- Produces: the evidence spec 7 asks of 2F (the dconf profile isolates every key; the stripped units do not start under GNOME), Milestone B's four lines that 2D could not check, and the D16 observation.

- [ ] **Step 1: Run the guide**

Follow `docs/guides/phase-2f-vm-check.md` from section 1 to the end, ticking each checkbox, on a clone of `tinkero-spike-clean-f44`. Keep every command's output the guide asks to keep under `~/vmcheck/` in the guest.

- [ ] **Step 2: Record**

Comment on the issue with each section's result (pass, or the failing command and its output), the three GNOME-invariant cycles side by side (dconf checksum, the two Phase 0 keys, the environment and unit lines), and the D16 observation. Then, in a small PR against its own issue (`docs:` only), add a line under the roadmap's "What executing 2F added to the queue" section with the date and the verdict.

- [ ] **Step 3: Decide on failures**

A failure of the GNOME invariant (guide section 4) opens an issue for design D4's fallback (`ExecStopPost=` unset in the inhibitor unit) when `DCONF_PROFILE` survived the session, or for spec 4.9's `tinkero-gnome-restore.service` when a key leaked with the profile in place. A failure of lock authentication (section 3) blocks Milestone B and opens an issue against Task 3. Anything else is recorded and triaged by the operator.

**Verification for the issue:** the comment of Step 2 and the merged roadmap line; the issue is closed by hand when the operator accepts the verdict.

---

## Deviations

Filled by the PR that implements Tasks 1 to 7 (and by Task 8's and 9's issues for theirs), per task, when anything deviated from this plan.

## What this plan deliberately leaves out

- `tinkero-status` and its PAM drift report (Phase 3; `tinkero-pam-sync --check` is the interface), the release workflow, the VM smoke test in CI.
- `tinkero-gnome-restore.service` (design D5): only if Task 9's GNOME cycles fail with the profile in place.
- Upstream's lid-closed fingerprint gate (D12) and the polkit dialog's fingerprint mode: bare metal.
- The `learn.*` web-app rows on a Firefox host (D16): recorded by Task 9, decided at the bare-metal pass.
- Any edit to `bin/tinkero-provision`.
- Suspend-to-lock timing with logind's five-second margin: bare metal, before Milestone B is signed off (spec 7).
- The 2E queue's "on a matching laptop, the speaker tuning no longer starts under GNOME": a VM matches no tuning, so this moves to the bare-metal pass (the strip and the drop-in are proven by `ci/gate-session-units`; the laptop check proves the behaviour).
