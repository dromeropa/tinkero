# Phase 2E: Provisioning and Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan runs through the issue loop** (`docs/guides/workflow.md`): dispatched only once Diego has applied `approved`, landed through a PR with green CI, tasks built serially on one branch in the order below.

**Goal:** A Fedora 44 Workstation user runs `install.sh`, gets the `tinkero` package and a provisioned home directory without any existing file being overwritten, can pick "Tinkero" at GDM, and can undo all of it with `tinkero-provision --remove`.

**Architecture:** `bin/tinkero-provision` (bash) is the only program that writes into a home directory: it seeds the packaged configuration per file, records every file it wrote in `~/.local/state/tinkero/seeded.tsv` with its sha256, and on later runs applies a pure three-way decision function per file. It also sources the upstream `install/user` leaves Tinkero keeps, seeds the session's dconf database, starts the session units at session start and undoes everything on `--remove`. Two replacement scripts route upstream's provisioning calls to it. `install.sh` is preflight, plan, `dnf`, `tinkero-provision`. Data files carry what changes per tag: the skip list, the session unit list, the config overrides, the config notes.

**Tech Stack:** bash, coreutils (`sha256sum`, `find`, `cmp`), `git config` (read-only), `dconf`, `systemctl --user`; the existing `tests/lib.sh` harness; no Python in this plan.

**Spec:** `docs/superpowers/specs/2026-09-23-phase-2e-provision-design.md` (the 2E design, derived from the master spec and binding for this plan; its section 7 lists the decisions D1 to D12 the operator may veto at approval) and `docs/superpowers/specs/2026-09-17-tinkero-design.md` sections 4.5, 4.6, 4.9, 4.11, 4.13, 5, 6 and 8. Audit: `docs/research/arch-coupling-audit.md` section 6. Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`. Placeholder issue: #9.

## Global Constraints

- Upstream tree pinned by `upstream.lock` at `v4.0.4`; every count in this plan is measured against that tag and the bump checklist updates it.
- `build/assemble TARBALL DEST` is the whole of `%install`; new payload files are new lines in its numbered steps, data over code. `tinkero.spec.in` gets `%files` lines and `Conflicts:`, no logic.
- Gate allowlists only shrink: `ci/allow/dropped-refs.allow` loses `usr/bin/omarchy-provision-user:omarchy-provision-owner` in the task that replaces the script (Task 5) and not before.
- Nothing in the payload may contain a token the arch-leak gate matches (`ci/gate-arch-leak`: `pacman`, `archlinux`, `limine`, `snapper`, `ufw`, ...). This binds `host.md` and `tinkero-provision`.
- Scripts start with `#!/bin/bash` and `set -euo pipefail`; ShellCheck clean with `-x -e SC1090,SC1091`; no `A && B || C` one-liners (SC2015); `# shellcheck disable=SC2016` above `printf`/heredoc lines that write literal `$*` into stub scripts.
- Tests never use the network and never run a real package manager, `dconf`, `systemctl` or `mise`: every such command is a stub on `PATH`, and every test runs under a temporary `HOME` with the seams `OMARCHY_PATH`, `TINKERO_SHARE`, `TINKERO_LOCK`, `TINKERO_DCONF_PROFILE`, `TINKERO_UNIT_DIR`, `TINKERO_EUID`, `TINKERO_OS_RELEASE`, `TINKERO_DM_UNIT`.
- Real home directories are never touched by any test or verification step in this plan; the real-tree check runs `tinkero-provision --plan` (which writes nothing) under a temporary `HOME`.
- No em dashes in Tinkero's own prose. Attribution trailers on every commit per the session's rules. Land through a PR against the approved issue; never push master.
- Each task's PR includes its Deviations line in this plan's "## Deviations" section when anything deviated.

## Issue map

Filed 2026-09-23 as one orchestrated issue, #16, superseding placeholder #9 (the plan itself landed through PR #15). The tasks land serially on one branch because they share `build/assemble`, `tests/test-assemble.sh`, `bin/tinkero-provision` and the allowlist. The `approved` label is Diego's.

| Task | Size | Area | WHAT | WHERE | HOW TO VERIFY |
|---|---|---|---|---|---|
| 1 Payload data and assemble steps | medium | build | the config override, skip list, unit list, dconf profile, `Conflicts: nwg-panel`, and the assemble steps that ship them and the host guide | `build/assemble`, `tinkero.spec.in`, `config/hypr/bindings.lua`, `provision/{skip,session-units}.list`, `distro/fedora/dconf/profile/tinkero`, `tests/fixtures/make-tree.sh`, `tests/test-assemble.sh` | `bash tests/test-assemble.sh` green at `1..43`; `./dev gates` four PASS; `ls .cache/payload/usr/share/tinkero/provision` lists both lists; `grep -c '^Conflicts:.*nwg-panel' tinkero.spec.in` is 1 |
| 2 `host.md` | small | provision | the host guide the patched skill points at | `distro/fedora/skills/host.md` | `./dev gates` green with the file in the payload (arch-leak gate proves no forbidden token); `test -f .cache/payload/usr/share/omarchy/default/agents/skills/omarchy/host.md`; the reviewer reads it against design section 5 |
| 3 `tinkero-provision`: the seeding engine | medium | provision | the decision function, sources, `seeded.tsv`, `--plan`, seeding, `--reset`, `--reset-all`, config notes | `bin/tinkero-provision`, `tests/fixtures/make-payload.sh`, `tests/test-provision.sh` | `bash tests/test-provision.sh` green (`1..79` after this task); real tree: `--plan` under an empty `HOME` prints 45 `seed` lines, 0 `conflict`, none naming `chromium` |
| 4 `tinkero-provision`: steps, session, dconf, removal | medium | provision | the upstream leaves, `--session` with units and notices, dconf seeding and `--reset dconf`, `--remove` | `bin/tinkero-provision`, `tests/test-provision.sh` | `bash tests/test-provision.sh` green at `1..130`; `./dev check` green |
| 5 The two provisioning wrappers | small | provision | `omarchy-provision-first-run` and `omarchy-provision-user` exec `tinkero-provision`; the allowlist shrinks | `distro/fedora/replacements/omarchy-provision-{first-run,user}`, `ci/allow/dropped-refs.allow`, `tests/test-replacements.sh` | `bash tests/test-replacements.sh` green at `1..36`; `grep -vc '^#' ci/allow/dropped-refs.allow` is 6; `./dev gates` four PASS |
| 6 `install.sh` | medium | provision | preflight, plan, two gates, system and user stages, against stubs | `install.sh`, `tests/test-install.sh`, `.github/workflows/ci.yml` | `bash tests/test-install.sh` green at `1..23`; ShellCheck clean; CI green |
| 7 Docs | small | docs | spec 4.6 status, roadmap, README install and remove sections, workflow guide | `docs/superpowers/specs/2026-09-17-tinkero-design.md`, `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, `README.md`, `docs/guides/workflow.md` | `./dev check` green; no em dash in the edited text; the reviewer reads each edit against the design |

## File Structure

| File | Responsibility |
|---|---|
| `bin/tinkero-provision` | the whole of provisioning: decision function, sources, state, steps, session, dconf, reset, remove |
| `tests/fixtures/make-payload.sh` | a stand-in for the installed payload (`usr/share/omarchy`, `usr/share/tinkero`, `etc/dconf`, `usr/lib/systemd/user`) whose leaves log to `$LOG` |
| `tests/test-provision.sh` | the decision table and every mode against the fixture under a temporary `HOME` |
| `config/hypr/bindings.lua` | Tinkero's seeded override: upstream's template plus the tmux and herdr bindings |
| `provision/skip.list` | `config/` paths never seeded |
| `provision/session-units.list` | units `--session` starts |
| `distro/fedora/dconf/profile/tinkero` | the session's dconf profile (D2) |
| `distro/fedora/skills/host.md` | the host guide |
| `distro/fedora/replacements/omarchy-provision-first-run`, `omarchy-provision-user` | wrappers |
| `install.sh`, `tests/test-install.sh` | the entry point and its stub-based test |
| `build/assemble` | step 3c (skills into the tree) and the provisioning data in step 5 |
| `tinkero.spec.in` | `Conflicts: nwg-panel`, `%config` for the dconf profile |

Interfaces later plans rely on: `provision/session-units.list` (2F appends `tinkero-inhibit-power-key.service`); `/etc/dconf/profile/tinkero` and `~/.config/dconf/tinkero` (2F exports `DCONF_PROFILE=tinkero`); `~/.local/state/tinkero/{seeded.tsv,release,done/}` and the `--plan` line format `<decision>\t<path>` (Phase 3's `tinkero-status`); `TINKERO_REF` in `install.sh` (the release workflow).

## Review Focus

Input classes the design implies that no requirement names; each has its test in the task that owns the code.

1. A file name with a space (`Disk Usage.desktop`): the tsv is tab-delimited, so a space in a path is data, and every shell expansion of a path is double-quoted; Task 3 seeds it and asserts the row.
2. A hand-edited or truncated `seeded.tsv`: provisioning refuses with the line number instead of misclassifying files; Task 3.
3. A target that is a symlink (a dotfiles repository linked into `~/.config`): never written through, never deleted, reported as the user's; Task 3 (decision table rows) and Task 4 (`--remove` keeps it).
4. No session bus (an SSH run): the dconf step is skipped with the reason and `--session` picks it up later; Task 4.
5. A run as root or under `sudo`: refused before anything is written; Task 3.

---

### Task 1: Payload data and assemble steps

**Files:**
- Create: `config/hypr/bindings.lua`, `provision/skip.list`, `provision/session-units.list`, `distro/fedora/dconf/profile/tinkero`
- Modify: `build/assemble` (header comment, new step 3c, additions to step 5), `tinkero.spec.in` (`Conflicts:`, `%files`), `tests/fixtures/make-tree.sh` (a skill directory), `tests/test-assemble.sh` (root files and six assertions)

**Interfaces:**
- Produces: `/usr/share/tinkero/config/**` (seeding overrides), `/usr/share/tinkero/provision/skip.list`, `/usr/share/tinkero/provision/session-units.list`, `/usr/share/tinkero/config-notes/*.md` (none at `v4.0.4`), `/etc/dconf/profile/tinkero`, and `default/agents/skills/omarchy/host.md` inside the tree once Task 2 adds the source. Task 3 reads the first two, Task 4 the unit list and the profile.

- [ ] **Step 1: The data files**

`config/hypr/bindings.lua` is upstream's `config/hypr/bindings.lua` at `v4.0.4` (copy it from the tree: `cp .cache/tree/config/hypr/bindings.lua config/hypr/bindings.lua` after `./dev payload` and `mkdir -p .cache/tree && tar -xzf .cache/omarchy-*.tar.gz -C .cache/tree --strip-components=1`) with this block appended after its last comment line:

```lua

-- Tinkero: the preinstalled-app bindings are switched off (the preinstalls-removed marker),
-- so the two host-neutral ones come back here. Docker and the music TUI stay off; see
-- docs/research/arch-coupling-audit.md section 4.3 for what re-enabling Docker takes.
o.bind("SUPER + ALT + RETURN", "Tmux", { omarchy = "terminal-tmux" })
o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })
```

`provision/skip.list`:

```
# provision/skip.list: paths under the packaged config/ that tinkero-provision never seeds
# (design 2E, D1). A line ending in / is a directory prefix; any other line is an exact path.
# Chromium is not part of Tinkero (spec 3), and its profile is shared with GNOME's Chromium.
chromium/
chromium-flags.conf
```

`provision/session-units.list`:

```
# provision/session-units.list: user units tinkero-provision --session starts at every Tinkero
# session start (spec 4.6, 4.9). Nothing is enabled; PartOf=graphical-session.target stops them.
# 2F appends tinkero-inhibit-power-key.service.
omarchy-crash-watch.service
omarchy-sleep-lock.service
omarchy-recover-internal-monitor.service
omarchy-fcitx5.service
bt-agent.service
```

`distro/fedora/dconf/profile/tinkero` (spec 4.9: the session's own user database, then Fedora's system databases):

```
user-db:tinkero
system-db:local
system-db:site
system-db:distro
```

- [ ] **Step 2: Fixture and failing tests**

In `tests/fixtures/make-tree.sh`, extend the first `mkdir -p` so the fixture tree has a skill directory: add `"$top"/default/agents/skills/omarchy` to the list, and after the `echo '<fontconfig/>' ...` line add:

```bash
echo '# fixture skill' > "$top/default/agents/skills/omarchy/SKILL.md"
```

In `tests/test-assemble.sh`, extend the root: change the `mkdir -p "$r"/{...}` line to include `distro/fedora/skills,distro/fedora/dconf/profile,config/hypr,provision,config-notes`, and after the `cp "$ROOT/session/tinkero.desktop" "$r/session/"` line add:

```bash
echo '# fixture host guide' > "$r/distro/fedora/skills/host.md"
echo '-- fixture bindings' > "$r/config/hypr/bindings.lua"
printf 'chromium/\n' > "$r/provision/skip.list"
printf 'omarchy-keep.service\n' > "$r/provision/session-units.list"
echo 'user-db:tinkero' > "$r/distro/fedora/dconf/profile/tinkero"
echo 'note' > "$r/config-notes/v0.md"
```

After the `assert_file "$d/dest/usr/share/tinkero/pkgmap.tsv" "name map shipped"` line add:

```bash
# Provisioning data (plan 2E)
assert_file "$o/default/agents/skills/omarchy/host.md" "host guide joins the omarchy skill inside the tree"
assert_eq "$(cat "$d/dest/usr/share/tinkero/config/hypr/bindings.lua")" "-- fixture bindings" "config overrides shipped under /usr/share/tinkero/config"
assert_file "$d/dest/usr/share/tinkero/provision/skip.list" "skip list shipped"
assert_file "$d/dest/usr/share/tinkero/provision/session-units.list" "session unit list shipped"
assert_file "$d/dest/usr/share/tinkero/config-notes/v0.md" "config notes shipped"
assert_file "$d/dest/etc/dconf/profile/tinkero" "dconf profile shipped"
```

Run: `bash tests/test-assemble.sh` Expected: the six new cases fail (`not ok`), the rest green.

- [ ] **Step 3: The assemble steps**

In `build/assemble`, add to the header comment block, after the `session/tinkero.desktop` line:

```bash
#   distro/fedora/skills/*.md           the host guide, into the omarchy skill inside the tree
#   config/**, provision/*.list, config-notes/*.md, distro/fedora/dconf/profile/tinkero
#                                        provisioning data under /usr/share/tinkero and /etc/dconf
```

After step 3b (the menu block) and before step 4, add:

```bash
# 3c. Skill guides. Tinkero's host guide joins the omarchy skill inside the tree, so the
# skill link provisioning makes covers it (design spec 4.5; patch 0006 points SKILL.md at it).
if [[ -d $root/distro/fedora/skills ]]; then
  [[ -d $tree/default/agents/skills/omarchy ]] || die "upstream has no default/agents/skills/omarchy; decide where the host guide goes"
  for f in "$root"/distro/fedora/skills/*.md; do
    [[ -f $f ]] && install -m 0644 "$f" "$tree/default/agents/skills/omarchy/$(basename "$f")"
  done
fi
```

At the end of step 5 (after the `pkgmap.tsv` line), add:

```bash
# Provisioning data (plan 2E): Tinkero's seeded config overrides, the skip list and the session
# unit list, the per-bump config notes (none until the first bump) and the session's dconf profile.
if [[ -d $root/config ]]; then
  mkdir -p "$dest/usr/share/tinkero/config"
  cp -a "$root/config/." "$dest/usr/share/tinkero/config/"
fi
for f in "$root"/provision/*.list; do
  [[ -f $f ]] && install -Dm 0644 "$f" "$dest/usr/share/tinkero/provision/$(basename "$f")"
done
for f in "$root"/config-notes/*.md; do
  [[ -f $f ]] && install -Dm 0644 "$f" "$dest/usr/share/tinkero/config-notes/$(basename "$f")"
done
install -Dm 0644 "$root/distro/fedora/dconf/profile/tinkero" "$dest/etc/dconf/profile/tinkero"
```

- [ ] **Step 4: The spec template**

In `tinkero.spec.in`, after `Conflicts:      omedora-settings` add:

```
# Fedora's nwg-panel declares Supplements: hyprland; a conflict makes dnf drop that weak
# dependency instead of installing a second bar (design spec 6, Phase 1 findings).
Conflicts:      nwg-panel
```

In `%files`, after the `%config(noreplace) %{_sysconfdir}/mise/conf.d/omarchy.toml` line add:

```
%config %{_sysconfdir}/dconf/profile/tinkero
```

- [ ] **Step 5: Verify**

Run: `bash tests/test-assemble.sh` Expected: `1..43`, no `not ok`.
Run: `./dev check` Expected: green.
Run: `./dev gates` Expected: four `PASS` (the host guide is not in the payload yet; Task 2 adds it).
Run: `ls .cache/payload/usr/share/tinkero/provision .cache/payload/etc/dconf/profile` Expected: `skip.list session-units.list` and `tinkero`.
Run: `test -f .cache/payload/usr/share/tinkero/config/hypr/bindings.lua && echo ok` Expected: `ok`.
Run: `grep -c '^Conflicts:.*nwg-panel' tinkero.spec.in` Expected: `1`.
Run: `shellcheck -x -e SC1090,SC1091 build/assemble tests/test-assemble.sh tests/fixtures/make-tree.sh` Expected: clean.
`./dev spec && rpmspec -P tinkero.spec >/dev/null && rpmlint tinkero.spec` in CI if `rpmspec` is not installed locally. Expected: green.

- [ ] **Step 6: Commit**

```bash
git add build/assemble tinkero.spec.in config provision distro/fedora/dconf tests/fixtures/make-tree.sh tests/test-assemble.sh
git commit -m "build: ship the provisioning data (config overrides, lists, dconf profile); Conflicts: nwg-panel"
```

**Verification for the issue:** Step 5's commands, plus CI green. The depsolve proof for `Conflicts: nwg-panel` (`dnf install --assumeno tinkero` against the COPR pulling no `nwg-panel`) needs the `tinkero` RPM in COPR and is owed by 2F's first-build issue; this task proves only that the spec parses and lints.

---

### Task 2: `host.md`

**Files:**
- Create: `distro/fedora/skills/host.md`

**Interfaces:**
- Consumes: Task 1's step 3c, which installs it into `default/agents/skills/omarchy/`. Patch 0006 already points `SKILL.md` at `host.md`.

- [ ] **Step 1: Write the guide**

`distro/fedora/skills/host.md`. Constraint: none of the arch-leak gate's tokens may appear (`pacman`, `archlinux`, `limine`, `snapper`, `ufw`, `makepkg`, `yay`, `paru`, `expac`, `mkinitcpio`, `checkupdates`, `paccache`, `pactree`, `pkgs.omarchy.org`); the gate scans this file once it is in the payload.

```markdown
# Host guide: this desktop runs on Fedora

This desktop is **Tinkero**. It is built on the Omarchy tree, so the commands are still
`omarchy-*`, the tree lives at `/usr/share/omarchy`, the user state at `~/.config/omarchy` and
`~/.local/state/omarchy`, and every path in the rest of this skill is right. Say "Tinkero" when
you talk about the desktop; use the real command names when you give instructions.

## Packages

- The host is Fedora, with `dnf`, RPM and Flatpak. Use `omarchy pkg add <name>` first: it maps
  the package names this skill and the menu use to Fedora packages or Flatpaks through
  `/usr/share/tinkero/pkgmap.tsv` (tab-separated: name, kind, target; kinds are `dnf`,
  `flatpak` and `none`). When a name is unmapped or `none`, the command prints what to do by
  hand. Then `dnf search` or `flatpak search`, and add a row to the map so the menu and you
  agree next time.
- There is no AUR here. The Arch package tools that upstream's documentation mentions do not
  exist on this host; do not try to install or emulate them.
- Recent package changes: `dnf history`. Updates are one command, `tinkero-update` (it runs
  `sudo dnf upgrade --refresh`, `mise up` and `flatpak update`). Nothing else keeps the desktop
  current. `tinkero-status` reports maintenance state when it exists (a later phase).
- `omarchy pkg add` elevates with `pkexec` inside the session, which raises the desktop's
  polkit dialog for the user to approve. Do not try to answer a `sudo` prompt yourself.

## What you never edit

- `/usr/share/omarchy` and `/usr/bin/omarchy-*` are package-owned. Never edit, copy into, or
  redirect them. User configuration lives in `~/.config`, seeded by `tinkero-provision`.
- `/etc/pam.d`: PAM is managed by `authselect`. Fingerprint and other login features go
  through `authselect enable-feature`, and the menu's setup entries already do that.
- SELinux stays enforcing. Read denials with `sudo ausearch -m AVC -ts recent`. Never change
  the mode, a boolean or a label; if something needs that, report it to the user instead.
- The firewall is `firewalld` (`firewall-cmd`). Containers: `podman` is the default.
- NVIDIA: the driver comes from RPM Fusion's `akmod-nvidia`; Tinkero does not enable RPM
  Fusion, the user does.

## Provisioning and recovery

- `tinkero-provision` seeds and updates the user's configuration from the packaged defaults
  without overwriting anything the user has. `tinkero-provision --plan` shows what a run would
  do; `--reset <path>` restores one packaged default with a backup; `--reset-all` restores all
  of them (that is what `omarchy-reinstall-configs` does here); `--remove` undoes provisioning.
  Files it wrote are listed in `~/.local/state/tinkero/seeded.tsv`.
- After a crash, Hyprland starts the next session in Safe Mode with an autogenerated config;
  `Super+M` leaves it. That is not a broken desktop.
- GNOME is still installed and untouched: logging into GNOME is always a way back.
```

- [ ] **Step 2: Verify**

Run: `./dev gates` Expected: four `PASS` (a forbidden token would fail the arch-leak gate with a finding naming `host.md`).
Run: `test -f .cache/payload/usr/share/omarchy/default/agents/skills/omarchy/host.md && echo ok` Expected: `ok`.
Run: `grep -nE 'pacman|archlinux|limine|snapper|\bufw\b' distro/fedora/skills/host.md` Expected: no output.
Run: `grep -n "—" distro/fedora/skills/host.md` Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add distro/fedora/skills/host.md
git commit -m "provision: host.md, the Fedora host guide for the omarchy skill"
```

**Verification for the issue:** Step 2's commands, CI green, and the reviewer reads the file against design section 5 (spec 4.5). There is no mechanical check of prose beyond the gate.

---

### Task 3: `tinkero-provision`, the seeding engine

**Files:**
- Create: `bin/tinkero-provision`, `tests/fixtures/make-payload.sh`, `tests/test-provision.sh`

**Interfaces:**
- Consumes: `/usr/share/tinkero/config/**`, `/usr/share/tinkero/provision/skip.list`, `/usr/share/tinkero/config-notes/<tag>.md` (Task 1); `$OMARCHY_PATH/config/**`, `icon.txt`, `logo.txt`, `default/hypr/toggles/flags.lua`, `default/tensaku/state.toml`, `applications/*.desktop`, `install/user/xcompose.sh` (upstream).
- Produces: `seed_decide SRC TGT ROW STATE` (sha256 or `-`, `link` for a symlinked target; state `seeded`, `removed-by-user`, `orphaned` or `-`) printing one word: `seed conflict current update keep-user moved mark-removed skip-removed delete orphan drop-row none`. Modes `--plan`, plain, `--reset PATH`, `--reset-all`, `--yes`. State files `~/.local/state/tinkero/{seeded.tsv,release,done/,provision.log}`. The `--plan` line format `<decision>\t<path>` and `step\t<name>: <text>`. Task 4 adds `--session`, `--reset dconf`, `--remove` and the step functions; the file is written here so that Task 4 only adds functions and replaces the two blocks marked `# Task 4 replaces this`.

- [ ] **Step 1: The fixture payload**

`tests/fixtures/make-payload.sh` (mode 0755):

```bash
#!/bin/bash
# make-payload.sh OUTDIR: a stand-in for the installed tinkero payload (usr/share/omarchy,
# usr/share/tinkero, etc/dconf, usr/lib/systemd/user) for the tinkero-provision tests.
# The install/user leaves are one-line scripts that append to $LOG. Prints OUTDIR.
# Re-running over the same OUTDIR restores every fixture file (tests mutate them).
set -euo pipefail
out=$1; o=$out/usr/share/omarchy; t=$out/usr/share/tinkero
mkdir -p "$o"/{config/hypr,config/git,config/chromium/Default,default/hypr/toggles,default/tensaku} \
         "$o"/default/agents/skills/{omarchy,diagnose-crash} "$o"/applications \
         "$o"/install/user/{hardware/asus,first-run} \
         "$t"/{config/hypr,provision,config-notes} "$out/etc/dconf/profile" "$out/usr/lib/systemd/user"
echo 'require("default.hypr.omarchy")' > "$o/config/hypr/hyprland.lua"
echo '-- upstream bindings template' > "$o/config/hypr/bindings.lua"
echo '-- looknfeel v1' > "$o/config/hypr/looknfeel.lua"
printf '[alias]\n\tst = status\n' > "$o/config/git/config"
echo '{"chromium":true}' > "$o/config/chromium/Default/Preferences"
echo '--flag' > "$o/config/chromium-flags.conf"
echo 'ASCII mark' > "$o/icon.txt"
echo 'ASCII logo' > "$o/logo.txt"
echo '-- flags' > "$o/default/hypr/toggles/flags.lua"
echo 'annotation-size-factor = 2.0' > "$o/default/tensaku/state.toml"
echo '# fixture skill' > "$o/default/agents/skills/omarchy/SKILL.md"
echo '# fixture skill' > "$o/default/agents/skills/diagnose-crash/SKILL.md"
printf '[Desktop Entry]\nName=Foot\nExec=foot\n' > "$o/applications/foot.desktop"
printf '[Desktop Entry]\nName=Disk Usage\nExec=xdg-terminal-exec -e dua\n' > "$o/applications/Disk Usage.desktop"
printf '[Desktop Entry]\nName=YouTube\nExec=omarchy-launch-webapp https://youtube.com/\n' > "$o/applications/YouTube.desktop"
printf '[Desktop Entry]\nName=HEY\nExec=omarchy-webapp-handler-hey %%u\n' > "$o/applications/HEY.desktop"
# leaf NAME FILE [EXTRA]: a stand-in for an install/user leaf; it logs its name and the two
# variables the real leaves care about, then runs EXTRA (used to make one leaf fail on demand).
leaf() {
  # shellcheck disable=SC2016  # the leaf expands these variables when it is sourced, not here
  printf 'echo "leaf %s headless=${OMARCHY_THEME_HEADLESS:-} name=${OMARCHY_USER_NAME:-}" >> "$LOG"\n%s\n' "$1" "${3:-}" > "$o/install/user/$2"
}
leaf theme theme.sh
# shellcheck disable=SC2016  # the leaf reads FAIL_MISE_WORK when it is sourced
leaf mise-work mise-work.sh 'if [[ ${FAIL_MISE_WORK:-} == 1 ]]; then exit 1; fi'
leaf mise mise.sh
leaf hardware-asus hardware/asus/fix-mic.sh
leaf hardware-nouveau hardware/fix-nouveau-cursor.sh
leaf audio-tuning first-run/audio-tuning.sh
# upstream's xcompose.sh shape: a heredoc into ~/.XCompose with the user's name from the environment
# shellcheck disable=SC2016
printf 'tee ~/.XCompose >/dev/null <<EOF\ninclude "/usr/share/omarchy/default/xcompose"\n<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"\nEOF\n' > "$o/install/user/xcompose.sh"
echo '-- tinkero bindings: tmux and herdr' > "$t/config/hypr/bindings.lua"
printf 'chromium/\nchromium-flags.conf\n' > "$t/provision/skip.list"
printf '# fixture units\nomarchy-keep.service\nmissing.service\n' > "$t/provision/session-units.list"
printf 'omarchy_tag=v4.0.4\ntinkero_rev=1\n' > "$t/upstream.lock"
echo 'Note for v4.0.4: nothing moved.' > "$t/config-notes/v4.0.4.md"
printf 'user-db:tinkero\nsystem-db:local\n' > "$out/etc/dconf/profile/tinkero"
printf '[Service]\nExecStart=/bin/true\n' > "$out/usr/lib/systemd/user/omarchy-keep.service"
echo "$out"
```

On an empty `HOME` this fixture yields twelve `seed` decisions: `.config/hypr/hyprland.lua`, `.config/hypr/bindings.lua` (Tinkero's), `.config/hypr/looknfeel.lua`, `.config/git/config`, `.config/omarchy/branding/about.txt`, `.config/omarchy/branding/screensaver.txt`, `.local/state/omarchy/toggles/hypr/flags.lua`, `.local/state/tensaku/state.toml`, `.local/share/applications/foot.desktop`, `.local/share/applications/Disk Usage.desktop`, `.local/state/omarchy/preinstalls-removed`, `.XCompose`. The two chromium files are skipped; the two web-app launchers are not launchers Tinkero seeds.

- [ ] **Step 2: The failing tests (this task's part)**

`tests/test-provision.sh` (Task 4 appends its cases at the marked spot; the file's tail stays `rm -rf "$d"; finish`):

```bash
#!/bin/bash
# bin/tinkero-provision against a fixture payload under a temporary HOME, with stub dconf,
# systemctl, git and the notification commands on PATH. No real home directory is touched.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); pay=$("$ROOT/tests/fixtures/make-payload.sh" "$d/payload"); mkdir -p "$d/bin"; export LOG=$d/log
T=$ROOT/bin/tinkero-provision
for s in systemctl omarchy-notification-send omarchy-notification-wait omarchy-theme-set; do
  # shellcheck disable=SC2016  # the stubs log their own arguments at run time
  printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n' "$s" > "$d/bin/$s"
done
cat > "$d/bin/dconf" <<'S'
#!/bin/bash
echo "dconf $* profile=${DCONF_PROFILE:-}" >> "$LOG"
case $1 in dump) printf '[org/gnome]\nk=1\n' ;; load) cat > "$DCONF_IN" ;; esac
S
printf '#!/bin/bash\nexit 1\n' > "$d/bin/git"     # no global identity configured
cat > "$d/bin/omarchy-default-agent" <<'S'
#!/bin/bash
printf '%s' "${AGENT:-}"
S
chmod +x "$d/bin"/*
export PATH=$d/bin:$PATH DCONF_IN=$d/dconf.in
export OMARCHY_PATH=$pay/usr/share/omarchy TINKERO_SHARE=$pay/usr/share/tinkero
export TINKERO_DCONF_PROFILE=$pay/etc/dconf/profile/tinkero TINKERO_UNIT_DIR=$pay/usr/lib/systemd/user
export TINKERO_EUID=1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
unset HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
newhome() { export HOME=$d/home$1; rm -rf "$HOME"; mkdir -p "$HOME"; : > "$LOG"; }
tsv() { grep -v '^#' "$HOME/.local/state/tinkero/seeded.tsv"; }
row() { tsv | awk -F'\t' -v p="$1" '$1 == p { print $2 "\t" $3 "\t" $4 }'; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

# 1. The decision table (design 2E, section 2.3), one row per case; "link" is a symlinked target.
while read -r name src tgt row st want; do
  got=$(TINKERO_PROVISION_SOURCED=1 bash -c 'source "$1"; seed_decide "$2" "$3" "$4" "$5"' bash "$T" "$src" "$tgt" "$row" "$st")
  assert_eq "$got" "$want" "decide: $name"
done <<'TABLE'
new h - - - seed
have h x - - conflict
unchanged h h h seeded current
upstream-changed h2 h h seeded update
user-changed h u h seeded keep-user
both-changed h2 u h seeded moved
user-deleted h - h seeded mark-removed
user-deleted-earlier h - h removed-by-user skip-removed
user-recreated-same h h h removed-by-user current
user-recreated-other h u h removed-by-user keep-user
upstream-removed-unchanged - h h seeded delete
upstream-removed-changed - u h seeded orphan
gone-both - - h seeded drop-row
orphan-readded h u h orphaned keep-user
symlink-new h link - - conflict
symlink-tracked h link h seeded keep-user
symlink-upstream-gone - link h seeded orphan
TABLE

# 2. --plan on an empty home writes nothing and names every file
newhome 1
out=$("$T" --plan)
assert_eq "$(grep -c $'^seed\t' <<<"$out")" 12 "plan: twelve files to seed on an empty home"
assert_contains "$out" $'seed\t.config/hypr/bindings.lua' "plan: config files"
assert_contains "$out" $'seed\t.local/share/applications/Disk Usage.desktop' "plan: a launcher with a space in its name"
assert_contains "$out" $'seed\t.XCompose' "plan: the XCompose file upstream's leaf would write"
assert_contains "$out" $'seed\t.local/state/omarchy/preinstalls-removed' "plan: the preinstalls marker"
if grep -q chromium <<<"$out"; then not_ok "plan: skip list honoured"; else ok "plan: skip list honoured"; fi
if grep -q -i 'youtube\|hey' <<<"$out"; then not_ok "plan: web-app launchers are not seeded"; else ok "plan: web-app launchers are not seeded"; fi
assert_contains "$out" $'step\tdconf:' "plan: lists the steps"
assert_eq "$(find "$HOME" -mindepth 1 | wc -l)" 0 "plan: the home is still empty"

# 3. A full run seeds, records, and is idempotent
echo 'echo mine' > "$HOME/.bashrc"
out=$("$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "provision: exit 0"
assert_eq "$(cat "$HOME/.config/hypr/bindings.lua")" "-- tinkero bindings: tmux and herdr" "provision: Tinkero's override wins over upstream's file"
assert_file "$HOME/.config/omarchy/branding/about.txt" "provision: branding seeded"
assert_file "$HOME/.local/share/applications/Disk Usage.desktop" "provision: launcher seeded"
assert_no_path "$HOME/.local/share/applications/YouTube.desktop" "provision: web-app launcher not seeded"
assert_no_path "$HOME/.config/chromium" "provision: skip list honoured"
assert_file "$HOME/.local/state/omarchy/preinstalls-removed" "provision: preinstalls marker"
assert_eq "$(sed -n 2p "$HOME/.XCompose")" '<Multi_key> <space> <n> : ""' "provision: XCompose from upstream's leaf, no identity"
assert_eq "$(tsv | wc -l)" 12 "provision: twelve rows recorded"
assert_eq "$(row .config/hypr/hyprland.lua)" "$(sha "$HOME/.config/hypr/hyprland.lua")"$'\tv4.0.4-1\tseeded' "provision: a row is sha256, release, state"
assert_eq "$(row '.local/share/applications/Disk Usage.desktop' | cut -f3)" seeded "provision: the row with a space in its path"
assert_eq "$(grep -c 'tinkero-provision' "$HOME/.bashrc")" 1 "provision: the guarded bashrc line, once"
assert_eq "$(head -n1 "$HOME/.bashrc")" "echo mine" "provision: the user's bashrc content is kept"
assert_eq "$(cat "$HOME/.local/state/tinkero/release")" "v4.0.4-1" "provision: release recorded"
assert_contains "$out" "Note for v4.0.4" "provision: config notes shown"
assert_eq "$(stat -c %a "$HOME/.config/hypr/hyprland.lua")" 644 "provision: seeded files are 0644"
: > "$LOG"; out2=$("$T" --yes 2>&1)
assert_eq "$(grep -c $'^current\t' <<<"$("$T" --plan)")" 12 "re-run: everything is current"
assert_eq "$(grep -c 'tinkero-provision' "$HOME/.bashrc")" 1 "re-run: the bashrc line is not duplicated"
if grep -q "Note for" <<<"$out2"; then not_ok "re-run: notes are shown once"; else ok "re-run: notes are shown once"; fi

# 4. Never overwrite: a file the user already has is a conflict
newhome 2
mkdir -p "$HOME/.config/hypr"; echo 'mine' > "$HOME/.config/hypr/hyprland.lua"
mkdir -p "$HOME/.config/git"; ln -s /dev/null "$HOME/.config/git/config"
out=$("$T" --yes 2>&1)
assert_eq "$(cat "$HOME/.config/hypr/hyprland.lua")" "mine" "conflict: the user's file is untouched"
assert_contains "$out" "conflict: .config/hypr/hyprland.lua" "conflict: reported"
assert_contains "$out" "diff $OMARCHY_PATH/config/hypr/hyprland.lua $HOME/.config/hypr/hyprland.lua" "conflict: with a diff command"
assert_symlink "$HOME/.config/git/config" /dev/null "conflict: a symlinked target is never written through"
assert_eq "$(tsv | wc -l)" 10 "conflict: neither file is recorded"
assert_contains "$("$T" --plan)" $'conflict\t.config/git/config' "conflict: still reported by --plan"

# 5. The git rule: no git configuration at all, or none is seeded
newhome 3; echo '[user]' > "$HOME/.gitconfig"
out=$("$T" --plan)
if grep -q 'git/config' <<<"$out"; then not_ok "git: ~/.gitconfig present, aliases not offered"; else ok "git: ~/.gitconfig present, aliases not offered"; fi

# 6. A bump: the three-way decisions on a provisioned home
newhome 4; "$T" --yes >/dev/null 2>&1
echo '-- looknfeel v2' > "$OMARCHY_PATH/config/hypr/looknfeel.lua"          # upstream changed, user did not
echo '-- tinkero bindings v2' > "$TINKERO_SHARE/config/hypr/bindings.lua"    # both changed
echo '-- my bindings' > "$HOME/.config/hypr/bindings.lua"
rm "$HOME/.config/hypr/hyprland.lua"                                        # user deleted
rm "$OMARCHY_PATH/config/git/config"                                        # upstream removed, user unchanged
rm "$OMARCHY_PATH/applications/Disk Usage.desktop"                          # upstream removed, user changed
echo 'edited' >> "$HOME/.local/share/applications/Disk Usage.desktop"
sed -i 's/tinkero_rev=1/tinkero_rev=2/' "$TINKERO_SHARE/upstream.lock"
plan=$("$T" --plan)
assert_contains "$plan" $'update\t.config/hypr/looknfeel.lua' "bump: unchanged by the user and changed upstream is updated"
assert_contains "$plan" $'moved\t.config/hypr/bindings.lua' "bump: changed by both is a moved default"
assert_contains "$plan" $'mark-removed\t.config/hypr/hyprland.lua' "bump: deleted by the user is marked"
assert_contains "$plan" $'delete\t.config/git/config' "bump: removed upstream and unchanged here is deleted"
assert_contains "$plan" $'orphan\t.local/share/applications/Disk Usage.desktop' "bump: removed upstream and changed here is an orphan"
out=$("$T" --yes 2>&1)
assert_eq "$(cat "$HOME/.config/hypr/looknfeel.lua")" "-- looknfeel v2" "bump: updated"
assert_eq "$(row .config/hypr/looknfeel.lua | cut -f2)" "v4.0.4-2" "bump: the row carries the new release"
assert_eq "$(cat "$HOME/.config/hypr/bindings.lua")" "-- my bindings" "bump: the user's edit is kept"
assert_contains "$out" "moved default: .config/hypr/bindings.lua" "bump: the moved default is reported"
assert_no_path "$HOME/.config/hypr/hyprland.lua" "bump: the deleted file is not reseeded"
assert_eq "$(row .config/hypr/hyprland.lua | cut -f3)" removed-by-user "bump: and its row says so"
assert_no_path "$HOME/.config/git/config" "bump: the upstream-removed file is deleted"
assert_eq "$(row .config/git/config)" "" "bump: and its row is dropped"
assert_eq "$(row '.local/share/applications/Disk Usage.desktop' | cut -f3)" orphaned "bump: the orphan is kept and marked"
"$T" --yes >/dev/null 2>&1
assert_no_path "$HOME/.config/hypr/hyprland.lua" "bump: a further run still does not reseed a removed file"
assert_contains "$("$T" --plan)" $'skip-removed\t.config/hypr/hyprland.lua' "bump: --plan shows it as removed by the user"

# 7. --reset and --reset-all
"$ROOT/tests/fixtures/make-payload.sh" "$d/payload" >/dev/null   # restore the fixture sources
sed -i 's/tinkero_rev=1/tinkero_rev=2/' "$TINKERO_SHARE/upstream.lock"
"$T" --reset .config/hypr/hyprland.lua >/dev/null
assert_file "$HOME/.config/hypr/hyprland.lua" "reset: a removed file comes back"
assert_eq "$(row .config/hypr/hyprland.lua | cut -f3)" seeded "reset: and its mark is cleared"
out=$("$T" --reset .config/hypr/bindings.lua 2>&1)
assert_eq "$(cat "$HOME/.config/hypr/bindings.lua")" "-- tinkero bindings: tmux and herdr" "reset: the packaged default is restored"
bak=$(find "$HOME/.config/hypr" -name 'bindings.lua.bak.*' | head -n1)
assert_eq "$(cat "${bak:-/dev/null}")" "-- my bindings" "reset: the user's version is backed up with a timestamp"
assert_contains "$out" "backed up .config/hypr/bindings.lua" "reset: the backup is named"
"$T" --reset nope >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" 1 "reset: an unknown path fails"
echo x > "$HOME/.config/hypr/looknfeel.lua"; echo y > "$HOME/.local/state/tensaku/state.toml"
"$T" --reset-all >/dev/null
assert_eq "$(cat "$HOME/.config/hypr/looknfeel.lua")$(cat "$HOME/.local/state/tensaku/state.toml")" "-- looknfeel v1annotation-size-factor = 2.0" "reset-all: every packaged default restored"
assert_eq "$(grep -c $'^current\t' <<<"$("$T" --plan)")" 12 "reset-all: everything current afterwards"
sed -i 's/tinkero_rev=2/tinkero_rev=1/' "$TINKERO_SHARE/upstream.lock"

# 8. Refusals
TINKERO_EUID=0 "$T" --plan >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" 1 "refuses to run as root"
newhome 5; "$T" --yes >/dev/null 2>&1
echo 'broken line' >> "$HOME/.local/state/tinkero/seeded.tsv"
out=$("$T" --plan 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a malformed seeded.tsv stops the run"
assert_contains "$out" "seeded.tsv line 14" "and names the line"

# Task 4 appends its cases here.
rm -rf "$d"; finish
```

Run: `bash tests/test-provision.sh` Expected: every case after the table fails (`bin/tinkero-provision` does not exist).

- [ ] **Step 3: The script**

`bin/tinkero-provision` (mode 0755). Task 4 adds the session, dconf and removal functions and replaces the two blocks marked `# Task 4 replaces this`; everything else is final.

```bash
#!/bin/bash
# tinkero-provision: the only thing Tinkero writes into a home directory (design spec 4.6;
# plan 2E design: docs/superpowers/specs/2026-09-23-phase-2e-provision-design.md).
#
#   tinkero-provision [--yes]         seed and update the user's configuration; idempotent
#   tinkero-provision --plan          print what a run would do; write nothing
#   tinkero-provision --session       session start: provision if needed, start the session units
#   tinkero-provision --reset PATH    restore one packaged default (PATH relative to $HOME)
#   tinkero-provision --reset dconf   reseed the session's dconf database from GNOME's
#   tinkero-provision --reset-all     restore every packaged default
#   tinkero-provision --remove        undo provisioning (design spec 4.11)
#
# Per file, never overwrite. Every file written is recorded in $XDG_STATE_HOME/tinkero/seeded.tsv
# (path, sha256, release, state), and a later run decides per file with seed_decide below.
set -euo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
TINKERO_SHARE=${TINKERO_SHARE:-/usr/share/tinkero}
TINKERO_LOCK=${TINKERO_LOCK:-$TINKERO_SHARE/upstream.lock}
TINKERO_DCONF_PROFILE=${TINKERO_DCONF_PROFILE:-/etc/dconf/profile/tinkero}
TINKERO_UNIT_DIR=${TINKERO_UNIT_DIR:-/usr/lib/systemd/user}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state=$state_home/tinkero
seeded=$state/seeded.tsv
log=$state/provision.log
bashrc_tag='# tinkero-provision'
bashrc_line="[[ \${XDG_SESSION_DESKTOP:-} == Hyprland && -r /usr/share/omarchy/default/bash/rc ]] && source /usr/share/omarchy/default/bash/rc  $bashrc_tag"
RELEASE=""; IN_SESSION=0; FAILED=(); SCRATCH=()
declare -A SRC ROW_HASH ROW_REL ROW_STATE DECISION
trap 'rm -rf "${SCRATCH[@]}"' EXIT

usage() { sed -n '5,11p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "tinkero-provision: $*" >&2; exit 1; }
say() { echo "tinkero-provision: $*"; }
mark() { mkdir -p "$state/done"; : > "$state/done/$1"; }
# lock_get KEY: the lock is parsed, never sourced.
lock_get() {
  local line
  line=$(grep -E "^$1=" "$TINKERO_LOCK" | tail -n1) || die "no key '$1' in $TINKERO_LOCK"
  printf '%s\n' "${line#*=}"
}
sha() { sha256sum -- "$1" | cut -d' ' -f1; }
# hash_of PATH: sha256 of a regular file, "-" when absent, "link" for a symlink (a symlinked
# target is the user's: never written through, never deleted).
hash_of() {
  if [[ -L $1 ]]; then echo link
  elif [[ -f $1 || $1 == /dev/null ]]; then sha "$1"
  else echo -; fi
}
rel_of() { case $1 in "$HOME"/*) printf '%s\n' "${1#"$HOME"/}" ;; *) printf '%s\n' "$1" ;; esac; }
abs_of() { case $1 in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$HOME/$1" ;; esac; }
in_session() { [[ $IN_SESSION == 1 || -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; }

# --- the decision ---------------------------------------------------------------------------
# seed_decide SRC TGT ROW STATE: sha256 sums (or "-" when absent, "link" for a symlinked target)
# of the packaged source, the target on disk and the recorded row, plus the row's state ("-"
# when there is no row). Prints one word. Pure; table-tested in tests/test-provision.sh.
seed_decide() {
  local src=$1 tgt=$2 row=$3 st=$4
  if [[ $row == - ]]; then
    if [[ $src == - ]]; then echo none
    elif [[ $tgt == - ]]; then echo seed
    else echo conflict; fi
    return
  fi
  if [[ $tgt != - && $st == removed-by-user ]]; then st=seeded; fi   # the user recreated it
  if [[ $src != - && $st == orphaned ]]; then st=seeded; fi          # upstream re-added it
  if [[ $src == - ]]; then
    if [[ $tgt == - ]]; then echo drop-row
    elif [[ $tgt == "$row" ]]; then echo delete
    else echo orphan; fi
    return
  fi
  if [[ $st == removed-by-user ]]; then echo skip-removed
  elif [[ $tgt == - ]]; then echo mark-removed
  elif [[ $tgt == "$row" ]]; then
    if [[ $src == "$row" ]]; then echo current; else echo update; fi
  elif [[ $src == "$row" ]]; then echo keep-user
  else echo moved; fi
}

# --- seeded.tsv ------------------------------------------------------------------------------
load_rows() {
  ROW_HASH=(); ROW_REL=(); ROW_STATE=()
  [[ -f $seeded ]] || return 0
  local n=0 p h r s
  while IFS=$'\t' read -r p h r s; do
    n=$((n + 1))
    [[ -z $p || $p == \#* ]] && continue
    [[ -n $h && -n $r && -n $s ]] || die "$seeded line $n is not 'path<TAB>sha256<TAB>release<TAB>state'; fix or remove the file"
    case $s in seeded|removed-by-user|orphaned) ;; *) die "$seeded line $n: unknown state '$s'" ;; esac
    ROW_HASH[$p]=$h; ROW_REL[$p]=$r; ROW_STATE[$p]=$s
  done < "$seeded"
}
save_rows() {
  local p
  mkdir -p "$state"
  {
    echo "# tinkero-provision: files Tinkero wrote. path<TAB>sha256<TAB>release<TAB>state. Do not edit."
    for p in "${!ROW_HASH[@]}"; do
      printf '%s\t%s\t%s\t%s\n' "$p" "${ROW_HASH[$p]}" "${ROW_REL[$p]}" "${ROW_STATE[$p]}"
    done | LC_ALL=C sort
  } > "$seeded.tmp" && mv "$seeded.tmp" "$seeded"
}
set_row() { ROW_HASH[$1]=$2; ROW_REL[$1]=$RELEASE; ROW_STATE[$1]=$3; }
# shellcheck disable=SC2016  # bash expands the subscript itself; single quotes keep spaces and globs in the key intact
drop_row() { unset 'ROW_HASH[$1]' 'ROW_REL[$1]' 'ROW_STATE[$1]'; }

# --- sources ---------------------------------------------------------------------------------
add_source() { SRC[$1]=$2; }
# skipped REL: is this config/ path on the skip list? A line ending in / is a directory prefix.
skipped() {
  local list=$TINKERO_SHARE/provision/skip.list line
  [[ -f $list ]] || return 1
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    if [[ $line == */ ]]; then
      [[ $1 == "$line"* ]] && return 0
    elif [[ $1 == "$line" ]]; then
      return 0
    fi
  done < "$list"
  return 1
}
# render_xcompose: what upstream's install/user/xcompose.sh would write, produced into a scratch
# HOME so that ~/.XCompose is a normal source with the normal three-way rule.
render_xcompose() {
  local leaf=$OMARCHY_PATH/install/user/xcompose.sh scratch
  [[ -f $leaf ]] || return 0
  scratch=$(mktemp -d); SCRATCH+=("$scratch")
  if ( HOME=$scratch bash -eE -c 'source "$1"' bash "$leaf" ) >/dev/null 2>&1 && [[ -f $scratch/.XCompose ]]; then
    add_source "$HOME/.XCompose" "$scratch/.XCompose"
  fi
}
# collect_sources [all]: fill SRC (target -> packaged source). Later sources win, so Tinkero's
# config/ overrides upstream's. With "all", the git rule is not applied (used by --reset).
collect_sources() {
  local root f rel
  SRC=()
  for root in "$OMARCHY_PATH/config" "$TINKERO_SHARE/config"; do
    [[ -d $root ]] || continue
    while IFS= read -r -d '' f; do
      rel=${f#"$root"/}
      skipped "$rel" && continue
      if [[ ${1:-} != all && $rel == git/config && ! -e $config_home/git/config && -e $HOME/.gitconfig ]]; then
        continue   # the user has a git configuration; upstream's aliases are not offered (spec 4.6)
      fi
      add_source "$config_home/$rel" "$f"
    done < <(find "$root" -type f -print0 | LC_ALL=C sort -z)
  done
  [[ -f $OMARCHY_PATH/icon.txt ]] && add_source "$config_home/omarchy/branding/about.txt" "$OMARCHY_PATH/icon.txt"
  [[ -f $OMARCHY_PATH/logo.txt ]] && add_source "$config_home/omarchy/branding/screensaver.txt" "$OMARCHY_PATH/logo.txt"
  [[ -f $OMARCHY_PATH/default/hypr/toggles/flags.lua ]] && add_source "$state_home/omarchy/toggles/hypr/flags.lua" "$OMARCHY_PATH/default/hypr/toggles/flags.lua"
  [[ -f $OMARCHY_PATH/default/tensaku/state.toml ]] && add_source "$state_home/tensaku/state.toml" "$OMARCHY_PATH/default/tensaku/state.toml"
  for f in "$OMARCHY_PATH"/applications/*.desktop; do
    [[ -f $f ]] || continue
    grep -qE '^Exec=(omarchy-launch-webapp|omarchy-webapp-handler-)' "$f" && continue   # web apps: a non-goal, and GNOME would list them
    add_source "$data_home/applications/$(basename "$f")" "$f"
  done
  render_xcompose
  add_source "$state_home/omarchy/preinstalls-removed" /dev/null   # closes upstream's preinstalled-bindings gate
}

# --- plan and apply --------------------------------------------------------------------------
compute_plan() {
  local t rel
  DECISION=()
  for t in "${!SRC[@]}"; do
    rel=$(rel_of "$t")
    DECISION[$t]=$(seed_decide "$(hash_of "${SRC[$t]}")" "$(hash_of "$t")" "${ROW_HASH[$rel]:--}" "${ROW_STATE[$rel]:--}")
  done
  for rel in "${!ROW_HASH[@]}"; do
    t=$(abs_of "$rel")
    [[ -n ${DECISION[$t]:-} ]] && continue
    DECISION[$t]=$(seed_decide - "$(hash_of "$t")" "${ROW_HASH[$rel]}" "${ROW_STATE[$rel]}")
  done
}
# print_plan: one line per path, "<decision><TAB><path relative to HOME>", sorted by path.
print_plan() {
  local t
  for t in "${!DECISION[@]}"; do printf '%s\t%s\n' "${DECISION[$t]}" "$(rel_of "$t")"; done | LC_ALL=C sort -t "$(printf '\t')" -k2
}
print_steps() {   # Task 4 replaces this
  printf 'step\tskills: link the agent skills into the harness directories\n'
  printf 'step\ttheme: install/user/theme.sh (headless outside a Tinkero session)\n'
  printf 'step\tmise-work: install/user/mise-work.sh\n'
  printf 'step\tmise: install/user/mise.sh\n'
  printf 'step\tdconf: seed ~/.config/dconf/tinkero from the GNOME settings\n'
  printf 'step\tbashrc: the guarded line in ~/.bashrc\n'
}
write_file() {   # SRC TGT
  local mode=0644
  [[ -x $1 ]] && mode=0755
  mkdir -p -- "$(dirname -- "$2")"
  cp -- "$1" "$2.tinkero-tmp" && chmod "$mode" "$2.tinkero-tmp" && mv -- "$2.tinkero-tmp" "$2"
}
apply_plan() {
  local t rel
  for t in "${!DECISION[@]}"; do
    rel=$(rel_of "$t")
    case ${DECISION[$t]} in
      seed|update)   write_file "${SRC[$t]}" "$t"; set_row "$rel" "$(sha "$t")" seeded ;;
      delete)        rm -f -- "$t"; drop_row "$rel" ;;
      drop-row)      drop_row "$rel" ;;
      mark-removed)  ROW_STATE[$rel]=removed-by-user ;;
      orphan)        ROW_STATE[$rel]=orphaned ;;
      current|keep-user|moved) ROW_STATE[$rel]=seeded ;;   # a recreated or re-added file loses its mark
      conflict|skip-removed|none) ;;
    esac
  done
}
report() {
  local d rel t n_seed=0 n_upd=0 n_cur=0 n_keep=0 n_conf=0 n_moved=0 n_orph=0 n_rem=0 n_del=0
  while IFS=$'\t' read -r d rel; do
    t=$(abs_of "$rel")
    case $d in
      seed) n_seed=$((n_seed + 1)) ;;
      update) n_upd=$((n_upd + 1)) ;;
      current) n_cur=$((n_cur + 1)) ;;
      keep-user) n_keep=$((n_keep + 1)) ;;
      delete) n_del=$((n_del + 1)) ;;
      conflict) n_conf=$((n_conf + 1)); say "conflict: $rel exists and is not Tinkero's; kept. Compare: diff ${SRC[$t]} $t" ;;
      moved) n_moved=$((n_moved + 1)); say "moved default: $rel (yours is kept; the packaged default changed: diff ${SRC[$t]} $t)" ;;
      orphan) n_orph=$((n_orph + 1)); say "orphaned: $rel was removed upstream; yours is kept" ;;
      mark-removed|skip-removed) n_rem=$((n_rem + 1)); say "removed by you: $rel (not reseeded; tinkero-provision --reset $rel brings it back)" ;;
    esac
  done < <(print_plan)
  say "files: $n_seed seeded, $n_upd updated, $n_cur current, $n_keep yours, $n_conf conflicts, $n_moved moved defaults, $n_orph orphaned, $n_rem removed by you, $n_del deleted"
}

# --- the steps that are not file copies ------------------------------------------------------
# seed_bashrc MODE (yes|ask|skip): append the guarded line once, with consent (spec 4.6).
seed_bashrc() {
  local rc=$HOME/.bashrc a
  if [[ -f $rc ]] && grep -qF -- "$bashrc_tag" "$rc"; then return 0; fi
  case $1 in
    skip) say "bashrc: the guarded line is not in ~/.bashrc; run 'tinkero-provision --yes' to add it"; return 0 ;;
    ask)
      if [[ ! -t 0 ]]; then say "bashrc: no terminal to ask; run 'tinkero-provision --yes' to add the guarded line"; return 0; fi
      read -r -p "Append one line to ~/.bashrc that loads Tinkero's bash setup only inside the Tinkero session? [y/N] " a
      if [[ $a != [yY]* ]]; then say "bashrc: ~/.bashrc left alone"; return 0; fi ;;
  esac
  printf '\n%s\n' "$bashrc_line" >> "$rc"
  say "bashrc: appended the guarded line to ~/.bashrc"
}
show_notes() {
  local tag f
  tag=$(lock_get omarchy_tag); f=$TINKERO_SHARE/config-notes/$tag.md
  [[ -f $f && ! -f $state/done/notes-$tag ]] || return 0
  echo; echo "Configuration notes for $tag ($f):"; cat "$f"; echo
  mark "notes-$tag"
}
run_steps() {   # Task 4 replaces this
  :
}

# --- modes -----------------------------------------------------------------------------------
provision() {   # CONSENT (yes|ask|skip)
  FAILED=()
  mkdir -p "$state/done"; : >> "$log"
  load_rows; collect_sources; compute_plan
  apply_plan; save_rows; report
  seed_bashrc "$1"
  run_steps
  show_notes
  if ((${#FAILED[@]})); then
    say "not complete: ${FAILED[*]} failed (see $log); fix and run again, or the next session start retries"
    return 1
  fi
  echo "$RELEASE" > "$state/release"
  say "provisioned for $RELEASE"
}
do_reset() {   # REL...
  local rel t src bak
  for rel in "$@"; do
    t=$(abs_of "$rel"); src=${SRC[$t]:-}
    [[ -n $src ]] || die "not a packaged default: $rel (tinkero-provision --plan lists them)"
    [[ -L $t ]] && die "$rel is a symlink; not touching it"
    if [[ -f $t ]] && ! cmp -s -- "$src" "$t"; then
      bak=$t.bak.$(date +%s); cp -p -- "$t" "$bak"; say "backed up $rel to $(rel_of "$bak")"
    fi
    write_file "$src" "$t"; set_row "$rel" "$(sha "$t")" seeded
    say "restored $rel"
  done
  save_rows
}

main() {
  local mode=provision consent=ask force=0 arg=""
  while (($#)); do
    case $1 in
      --yes|-y) consent=yes ;;
      --plan) mode=plan ;;
      --session) mode=session; consent=skip; IN_SESSION=1 ;;
      --force) force=1 ;;
      --reset) [[ -n ${2:-} ]] || die "--reset needs a path (relative to your home) or 'dconf'"; mode=reset; arg=$2; shift ;;
      --reset-all) mode=reset-all ;;
      --remove) mode=remove ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  [[ ${TINKERO_EUID:-$EUID} != 0 ]] || die "run as the user being provisioned, not as root"
  [[ -d $OMARCHY_PATH/config ]] || die "no Omarchy tree at $OMARCHY_PATH (is the tinkero package installed?)"
  RELEASE="$(lock_get omarchy_tag)-$(lock_get tinkero_rev)"
  export OMARCHY_PATH OMARCHY_INSTALL="$OMARCHY_PATH/install" OMARCHY_SETUP_CONTEXT=runtime
  OMARCHY_USER_NAME=$(git config --global user.name 2>/dev/null || true); export OMARCHY_USER_NAME
  OMARCHY_USER_EMAIL=$(git config --global user.email 2>/dev/null || true); export OMARCHY_USER_EMAIL
  case $mode in
    plan)      load_rows; collect_sources; compute_plan; print_plan; print_steps ;;
    provision) provision "$consent" ;;
    reset)     load_rows; collect_sources all; do_reset "$arg" ;;
    reset-all) load_rows; collect_sources all; mapfile -t targets < <(for t in "${!SRC[@]}"; do rel_of "$t"; done | LC_ALL=C sort); do_reset "${targets[@]}" ;;
    session|remove) die "$mode is not implemented yet (plan 2E, Task 4)" ;;
  esac
}
[[ ${TINKERO_PROVISION_SOURCED:-} == 1 ]] || main "$@"
```

Notes for the implementer: `hash_of` treats `/dev/null` as a readable source because the preinstalls marker is seeded from it (an empty file). `print_plan` sorts with `sort -t "$(printf '\t')"` because `$'\t'` inside `-t` is fine in bash but reads badly. The `--reset dconf` branch, `--session` and `--remove` are Task 4's; until then they fail with a clear message, and `force` is parsed but unused (ShellCheck SC2034 on `force`: add `# shellcheck disable=SC2034` above `main` in this task and remove it in Task 4).

- [ ] **Step 4: Verify**

Run: `bash tests/test-provision.sh` Expected: `1..79`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 bin/tinkero-provision tests/test-provision.sh tests/fixtures/make-payload.sh` Expected: clean.
Run: `./dev check` Expected: green.

Real tree (writes nothing; `./dev payload` first):

```bash
h=$(mktemp -d)
HOME=$h OMARCHY_PATH=$PWD/.cache/payload/usr/share/omarchy TINKERO_SHARE=$PWD/.cache/payload/usr/share/tinkero \
  TINKERO_EUID=1000 bin/tinkero-provision --plan > "$h/plan"
grep -c $'^seed\t' "$h/plan"; grep -c $'^conflict\t' "$h/plan"; grep -c chromium "$h/plan"
grep $'^seed\t.local/share/applications' "$h/plan" | cut -f2 | paste -sd,
find "$h" -mindepth 1 -not -name plan | wc -l; rm -rf "$h"
```

Expected, in order: `47`, `0`, `0`, `.local/share/applications/Disk Usage.desktop,.local/share/applications/foot.desktop,.local/share/applications/imv.desktop,.local/share/applications/mpv.desktop`, `0`. (47 is 37 config files after the drop and skip lists, two branding files, `flags.lua`, `state.toml`, four launchers, `.XCompose` rendered from upstream's `xcompose.sh`, and the preinstalls marker.)

- [ ] **Step 5: Commit**

```bash
git add bin/tinkero-provision tests/fixtures/make-payload.sh tests/test-provision.sh
git commit -m "provision: tinkero-provision seeds per file, never overwrites, and records what it wrote"
```

**Verification for the issue:** Step 4's commands with the measured real-tree numbers quoted verbatim, plus CI green.

---

### Task 4: `tinkero-provision`: steps, session, dconf, removal

**Files:**
- Modify: `bin/tinkero-provision` (add the functions below; replace `print_steps` and `run_steps`; extend `main`), `tests/test-provision.sh` (append the cases below at `# Task 4 appends its cases here.`)

**Interfaces:**
- Consumes: `/usr/share/tinkero/provision/session-units.list`, `/etc/dconf/profile/tinkero` (Task 1); `$OMARCHY_PATH/install/user/{theme.sh,mise-work.sh,mise.sh,hardware/**,first-run/audio-tuning.sh}` and `default/agents/skills/*/` (upstream); `omarchy-notification-wait`, `omarchy-notification-send`, `omarchy-default-agent`, `omarchy-theme-set` (upstream commands on `PATH`).
- Produces: `--session [--force]`, `--reset dconf`, `--remove`; markers `done/{hardware,audio-tuning,theme-in-session,dconf,welcome,agent-invite}`; the `step` lines of `--plan` with a trailing `done`, `pending` or `present`.

- [ ] **Step 1: The failing tests**

Insert before `# Task 4 appends its cases here.` in `tests/test-provision.sh`:

```bash
# 9. The upstream leaves run in order, headless outside a session, and one failure does not stop the rest
newhome 6
out=$("$T" --yes 2>&1)
assert_eq "$(grep -o '^leaf [a-z-]*' "$LOG" | paste -sd' ')" "leaf theme leaf mise-work leaf mise" "steps: skills, theme, mise-work, mise; nothing in-session"
assert_contains "$(cat "$LOG")" "leaf theme headless=1" "steps: the first theme is headless outside a session"
assert_symlink "$HOME/.claude/skills/omarchy" "$OMARCHY_PATH/default/agents/skills/omarchy" "steps: skills linked (claude)"
assert_symlink "$HOME/.hermes/skills/diagnose-crash" "$OMARCHY_PATH/default/agents/skills/diagnose-crash" "steps: skills linked (hermes)"
assert_contains "$(cat "$LOG")" "dconf dump / profile=user" "dconf: GNOME's settings are dumped from the user profile"
assert_contains "$(cat "$LOG")" "dconf load / profile=tinkero" "dconf: and loaded into the tinkero profile"
assert_eq "$(cat "$DCONF_IN")" $'[org/gnome]\nk=1' "dconf: the dump is what gets loaded"
assert_contains "$out" "step mise: ok" "steps: reported"
: > "$LOG"; "$T" --yes >/dev/null 2>&1
assert_eq "$(grep -c '^dconf' "$LOG")" 0 "dconf: seeded once"
assert_contains "$("$T" --plan)" $'step\tdconf: seed ~/.config/dconf/tinkero from the GNOME settings done' "plan: the dconf step shows done"
: > "$LOG"; "$T" --reset dconf >/dev/null 2>&1
assert_eq "$(grep -c '^dconf' "$LOG")" 2 "reset dconf: dumped and loaded again"
newhome 7
out=$(FAIL_MISE_WORK=1 "$T" --yes 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a failing leaf makes the run fail"
assert_contains "$out" "not complete: mise-work failed" "and names it"
assert_eq "$(grep -o '^leaf [a-z-]*' "$LOG" | paste -sd' ')" "leaf theme leaf mise-work leaf mise" "but the later leaves still ran"
assert_no_path "$HOME/.local/state/tinkero/release" "and the release is not recorded"
"$T" --yes >/dev/null 2>&1; assert_file "$HOME/.local/state/tinkero/release" "a later run completes and records it"
newhome 10
out=$(env -u DBUS_SESSION_BUS_ADDRESS "$T" --yes 2>&1)
assert_contains "$out" "dconf: no session bus" "dconf: no bus is a skip with the reason, not a failure"
assert_eq "$(grep -c '^dconf' "$LOG")" 0 "dconf: nothing ran without a bus"
assert_file "$HOME/.local/state/tinkero/release" "dconf: a skip does not stop provisioning"
: > "$LOG"; "$T" --session >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "dconf load / profile=tinkero" "dconf: the next session start seeds it"

# 10. --session: provision when stale, in-session steps once, units, notices once
newhome 8
out=$("$T" --session 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "session: a fresh home is provisioned"
assert_contains "$(cat "$LOG")" "leaf theme headless=0" "session: the first theme is applied for real inside the session"
assert_eq "$(grep -c '^leaf hardware' "$LOG")" 2 "session: the hardware fixes run"
assert_eq "$(grep -c '^leaf audio-tuning' "$LOG")" 1 "session: the speaker tuning runs"
assert_contains "$(cat "$LOG")" "systemctl --user start omarchy-keep.service" "session: listed units are started"
assert_contains "$out" "unit missing.service is not installed; skipped" "session: a missing unit is skipped and named"
assert_eq "$(grep -c '^omarchy-notification-send' "$LOG")" 2 "session: the welcome and the agent invitation"
assert_eq "$(grep -c '^omarchy-notification-wait' "$LOG")" 1 "session: after waiting for the notification service"
assert_eq "$(grep -c '^omarchy-theme-set' "$LOG")" 0 "session: no second theme application when the first was in-session"
assert_contains "$out" "bashrc: the guarded line is not in" "session: the bashrc line is never appended at session start"
: > "$LOG"; out=$("$T" --session 2>&1)
assert_eq "$(grep -c '^leaf' "$LOG")" 0 "session: current release, no leaves"
assert_contains "$(cat "$LOG")" "systemctl --user start omarchy-keep.service" "session: units are started every time"
assert_eq "$(grep -c '^omarchy-notification-send' "$LOG")" 0 "session: notices are sent once"
: > "$LOG"; "$T" --session --force >/dev/null 2>&1
assert_eq "$(grep -o '^leaf [a-z-]*' "$LOG" | paste -sd' ')" "leaf theme leaf mise-work leaf mise" "session --force: reprovisions, the once-only steps stay done"
newhome 9; AGENT=claude "$T" --session >/dev/null 2>&1
assert_eq "$(grep -c '^omarchy-notification-send' "$LOG")" 1 "session: no agent invitation when a default agent is set"
export HOME=$d/home6; : > "$LOG"   # provisioned outside a session above
mkdir -p "$HOME/.local/state/omarchy/current"; echo "Tokyo Night" > "$HOME/.local/state/omarchy/current/theme.name"
"$T" --session >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "omarchy-theme-set Tokyo Night" "session: a theme set headless at install is applied once inside the session"
: > "$LOG"; "$T" --session >/dev/null 2>&1
assert_eq "$(grep -c '^omarchy-theme-set' "$LOG")" 0 "session: and only once"

# 11. --remove undoes what was written and keeps what the user changed
export HOME=$d/home8; : > "$LOG"
echo 'edited' >> "$HOME/.config/hypr/hyprland.lua"
mkdir -p "$HOME/.config/dconf"; echo db > "$HOME/.config/dconf/tinkero"
mkdir -p "$HOME/.local/bin"; printf '#!/bin/bash\nexec mise x claude -- claude "$@"\n' > "$HOME/.local/bin/claude"
# shellcheck disable=SC2016  # the guarded line is written literally, as tinkero-provision writes it
printf 'echo mine\n%s\n' '[[ ${XDG_SESSION_DESKTOP:-} == Hyprland && -r /usr/share/omarchy/default/bash/rc ]] && source /usr/share/omarchy/default/bash/rc  # tinkero-provision' > "$HOME/.bashrc"
out=$("$T" --remove 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 "remove: exit 0"
assert_no_path "$HOME/.config/hypr/bindings.lua" "remove: an unchanged seeded file is deleted"
assert_no_path "$HOME/.local/state/omarchy/preinstalls-removed" "remove: the preinstalls marker is deleted"
assert_no_path "$HOME/.XCompose" "remove: the XCompose file is deleted"
assert_file "$HOME/.config/hypr/hyprland.lua" "remove: a changed file is kept"
assert_contains "$out" "kept (you changed it): .config/hypr/hyprland.lua" "remove: and listed"
assert_no_path "$HOME/.claude/skills/omarchy" "remove: skill links are removed"
assert_eq "$(cat "$HOME/.bashrc")" "echo mine" "remove: only the tagged bashrc line goes"
assert_no_path "$HOME/.config/dconf/tinkero" "remove: the session's dconf database is deleted"
assert_file "$HOME/.local/bin/claude" "remove: mise stubs are kept"
assert_contains "$out" "kept (mise stub, remove by hand if unwanted): .local/bin/claude" "remove: and listed"
assert_contains "$(cat "$LOG")" "systemctl --user stop omarchy-keep.service" "remove: the session units are stopped"
assert_no_path "$HOME/.local/state/tinkero" "remove: the state directory is gone"
assert_contains "$out" "sudo dnf remove tinkero" "remove: says what comes next"
```

Run: `bash tests/test-provision.sh` Expected: the new cases fail (`--session` and `--remove` die with "not implemented"; no leaf runs).

- [ ] **Step 2: The functions**

Add to `bin/tinkero-provision` after the `show_notes` function (before `# --- modes`), and delete the two `# Task 4 replaces this` stubs (`print_steps` and `run_steps`) in favour of the versions here:

```bash
# --- the upstream leaves ---------------------------------------------------------------------
# leaf FILE: source an install/user leaf the way upstream's run_logged does.
leaf() {
  [[ -f $1 ]] || { echo "missing leaf: $1"; return 1; }
  bash -eE -c 'source "$1"' bash "$1"
}
# run_step NAME CMD...: run in a subshell with the output appended to the log. A failure is
# recorded in FAILED and does not stop the other steps (design 2E, D9).
run_step() {
  local name=$1; shift
  printf '[%s] step %s\n' "$(date '+%F %T')" "$name" >> "$log"
  if ( "$@" ) >> "$log" 2>&1; then say "step $name: ok"
  else FAILED+=("$name"); say "step $name: failed (see $log)"; fi
}
# step_skills: upstream's loop, omarchy-provision-user:87-103 at v4.0.4, verbatim. Every skill
# directory is linked, so a skill a later tag adds is linked by the next run.
step_skills() {
  local skill name profile
  mkdir -p ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills ~/.hermes/skills
  for skill in "$OMARCHY_PATH"/default/agents/skills/*/; do
    skill=${skill%/}
    name=${skill##*/}
    ln -sfn "$skill" ~/.agents/skills/"$name"
    ln -sfn "$skill" ~/.claude/skills/"$name"
    ln -sfn "$skill" ~/.codex/skills/"$name"
    ln -sfn "$skill" ~/.pi/agent/skills/"$name"
    ln -sfn "$skill" ~/.hermes/skills/"$name"
    if [[ -d ~/.hermes/profiles ]]; then
      for profile in ~/.hermes/profiles/*/; do
        [[ -d $profile ]] || continue
        mkdir -p "$profile/skills"
        ln -sfn "$skill" "$profile/skills/$name"
      done
    fi
  done
}
# step_theme: the first theme. Outside a Tinkero session there is no shell to talk to, so
# upstream's headless mode stages the theme and runs none of the post-theme commands (nothing
# touches GNOME's dconf or an application's settings from GNOME). Inside, the full switch.
step_theme() {
  if in_session; then
    export OMARCHY_THEME_HEADLESS=0
    leaf "$OMARCHY_PATH/install/user/theme.sh" && mark theme-in-session
  else
    export OMARCHY_THEME_HEADLESS=1
    leaf "$OMARCHY_PATH/install/user/theme.sh"
  fi
}
run_steps() {
  run_step skills step_skills
  run_step theme step_theme
  run_step mise-work leaf "$OMARCHY_PATH/install/user/mise-work.sh"
  run_step mise leaf "$OMARCHY_PATH/install/user/mise.sh"
  seed_dconf 0
  if in_session; then in_session_steps; fi
}
# in_session_steps: once per home, inside a Tinkero session (design 2E, D4): the hardware
# fixes, the speaker tuning, and one real application of a theme that was set headless.
in_session_steps() {
  local before f name
  if [[ ! -f $state/done/hardware ]]; then
    before=${#FAILED[@]}
    for f in "$OMARCHY_PATH"/install/user/hardware/*.sh "$OMARCHY_PATH"/install/user/hardware/*/*.sh; do
      [[ -f $f ]] || continue
      run_step "hardware/$(basename "$f")" leaf "$f"
    done
    if [[ ${#FAILED[@]} == "$before" ]]; then mark hardware; fi
  fi
  if [[ ! -f $state/done/audio-tuning ]]; then
    before=${#FAILED[@]}
    run_step audio-tuning leaf "$OMARCHY_PATH/install/user/first-run/audio-tuning.sh"
    if [[ ${#FAILED[@]} == "$before" ]]; then mark audio-tuning; fi
  fi
  name=$state_home/omarchy/current/theme.name
  if [[ ! -f $state/done/theme-in-session && -s $name ]]; then
    before=${#FAILED[@]}
    run_step theme-in-session omarchy-theme-set "$(<"$name")"
    if [[ ${#FAILED[@]} == "$before" ]]; then mark theme-in-session; fi
  fi
}

# --- the session's dconf database (spec 4.9) ---------------------------------------------------
# seed_dconf FORCE (0|1): GNOME's settings, read through Fedora's "user" profile, loaded into
# the "tinkero" profile the package ships. Once, unless forced (--reset dconf backs the file up).
seed_dconf() {
  local db=$config_home/dconf/tinkero
  if [[ $1 == 0 && -f $state/done/dconf ]]; then return 0; fi
  if [[ ! -f $TINKERO_DCONF_PROFILE ]]; then say "dconf: $TINKERO_DCONF_PROFILE is missing; skipped"; return 0; fi
  if ! command -v dconf >/dev/null 2>&1; then say "dconf: dconf is not installed; skipped"; return 0; fi
  if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    say "dconf: no session bus; run tinkero-provision again from a graphical session to seed the session's settings"
    return 0
  fi
  if [[ $1 == 1 && -f $db ]]; then cp -p -- "$db" "$db.bak.$(date +%s)"; fi
  if DCONF_PROFILE=user dconf dump / | DCONF_PROFILE=tinkero dconf load /; then
    mark dconf; say "dconf: seeded the session's settings from GNOME's"
  else
    FAILED+=(dconf); say "dconf: seeding failed"
  fi
}

# --- the session ------------------------------------------------------------------------------
unit_list() {
  local f=$TINKERO_SHARE/provision/session-units.list
  [[ -f $f ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$f" || true
}
start_units() {
  local u
  while IFS= read -r u; do
    [[ -z $u ]] && continue
    if [[ -f $TINKERO_UNIT_DIR/$u || -f $config_home/systemd/user/$u ]]; then
      systemctl --user start "$u" || say "unit $u failed to start"
    else
      say "unit $u is not installed; skipped"
    fi
  done < <(unit_list)
}
stop_units() {
  local u
  while IFS= read -r u; do
    [[ -z $u ]] && continue
    systemctl --user stop "$u" >/dev/null 2>&1 || true
  done < <(unit_list)
}
# first_session_notices: the welcome toast and, when no default agent is chosen, the invitation
# upstream ships as a post-update hook (which never fires here). Once each.
first_session_notices() {
  if [[ -f $state/done/welcome && -f $state/done/agent-invite ]]; then return 0; fi
  omarchy-notification-wait || true
  if [[ ! -f $state/done/welcome ]]; then
    omarchy-notification-send -u critical "Welcome to Tinkero" $'Super + K for the cheat sheet.\nSuper + Space for the Tinkero menu.' --exec omarchy-menu-keybindings && mark welcome
  fi
  if [[ ! -f $state/done/agent-invite ]]; then
    if [[ -z $(omarchy-default-agent 2>/dev/null || true) ]]; then
      omarchy-notification-send -u critical "Set your default agent" "Let your favorite agent help with Tinkero." --exec omarchy menu summon setup.default.agent && mark agent-invite
    else
      mark agent-invite
    fi
  fi
  return 0
}
session_mode() {   # FORCE (0|1)
  local rc=0
  if [[ $1 == 1 || ! -f $state/release || $(cat "$state/release") != "$RELEASE" ]]; then
    provision skip || rc=1
  else
    FAILED=(); mkdir -p "$state/done"
    in_session_steps
    seed_dconf 0
    if ((${#FAILED[@]})); then rc=1; fi
  fi
  start_units
  first_session_notices
  return $rc
}

# --- removal (spec 4.11) ------------------------------------------------------------------------
do_remove() {
  local dir p t f kept=()
  load_rows
  stop_units
  rm -f -- "$config_home/dconf/tinkero"
  for dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills ~/.hermes/skills ~/.hermes/profiles/*/skills; do
    [[ -d $dir ]] || continue
    for p in "$dir"/*; do
      if [[ -L $p && $(readlink -- "$p") == "$OMARCHY_PATH"/* ]]; then rm -f -- "$p"; fi
    done
  done
  if [[ -f $HOME/.bashrc ]] && grep -qF -- "$bashrc_tag" "$HOME/.bashrc"; then
    grep -vF -- "$bashrc_tag" "$HOME/.bashrc" > "$HOME/.bashrc.tinkero-tmp" || true
    mv -- "$HOME/.bashrc.tinkero-tmp" "$HOME/.bashrc"
  fi
  for p in "${!ROW_HASH[@]}"; do
    [[ ${ROW_STATE[$p]} == seeded ]] || continue
    t=$(abs_of "$p")
    if [[ $(hash_of "$t") == "${ROW_HASH[$p]}" ]]; then rm -f -- "$t"
    elif [[ -e $t || -L $t ]]; then kept+=("$p"); fi
  done
  say "removed the files Tinkero wrote and you did not change, the skill links, the bashrc line and the session's dconf database"
  for p in "${kept[@]}"; do say "kept (you changed it): $p"; done
  for f in "$HOME"/.local/bin/*; do
    if [[ -f $f ]] && grep -q 'mise x' "$f" 2>/dev/null; then say "kept (mise stub, remove by hand if unwanted): $(rel_of "$f")"; fi
  done
  for p in Work .local/state/omarchy .config/omarchy/themes .cache/omarchy; do
    if [[ -e $HOME/$p ]]; then say "kept (yours to delete): $p"; fi
  done
  rm -rf -- "$state"
  say "then: sudo dnf remove tinkero && sudo dnf copr remove dromero/tinkero"
}
```

The final `print_steps` (replacing Task 3's stub, placed where it was):

```bash
print_steps() {
  local st
  printf 'step\tskills: link the agent skills into the harness directories\n'
  printf 'step\ttheme: install/user/theme.sh (headless outside a Tinkero session)\n'
  printf 'step\tmise-work: install/user/mise-work.sh\n'
  printf 'step\tmise: install/user/mise.sh\n'
  st=pending; if [[ -f $state/done/hardware ]]; then st="done"; fi
  printf 'step\thardware: install/user/hardware/*.sh (in a Tinkero session, once) %s\n' "$st"
  st=pending; if [[ -f $state/done/audio-tuning ]]; then st="done"; fi
  printf 'step\taudio-tuning: install/user/first-run/audio-tuning.sh (in a Tinkero session, once) %s\n' "$st"
  st=pending; if [[ -f $state/done/dconf ]]; then st="done"; fi
  printf 'step\tdconf: seed ~/.config/dconf/tinkero from the GNOME settings %s\n' "$st"
  st=pending; if [[ -f $HOME/.bashrc ]] && grep -qF -- "$bashrc_tag" "$HOME/.bashrc"; then st=present; fi
  printf 'step\tbashrc: the guarded line in ~/.bashrc %s\n' "$st"
}
```

In `main`, replace the `case $mode in` block with:

```bash
  case $mode in
    plan)      load_rows; collect_sources; compute_plan; print_plan; print_steps ;;
    provision) provision "$consent" ;;
    session)   session_mode "$force" ;;
    reset)
      if [[ $arg == dconf ]]; then
        mkdir -p "$state"; FAILED=(); seed_dconf 1
        [[ ${#FAILED[@]} == 0 ]] || exit 1
      else
        load_rows; collect_sources all; do_reset "$arg"
      fi ;;
    reset-all) load_rows; collect_sources all; mapfile -t targets < <(for t in "${!SRC[@]}"; do rel_of "$t"; done | LC_ALL=C sort); do_reset "${targets[@]}" ;;
    remove)    do_remove ;;
  esac
```

Remove the `# shellcheck disable=SC2034` line Task 3 put above `main` (`force` is used now), and the `run_steps` stub.

- [ ] **Step 3: Verify**

Run: `bash tests/test-provision.sh` Expected: `1..130`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 bin/tinkero-provision tests/test-provision.sh` Expected: clean.
Run: `./dev check` Expected: green.
Run: `bin/tinkero-provision --help` Expected: the seven usage lines from the header, exit 0.

- [ ] **Step 4: Commit**

```bash
git add bin/tinkero-provision tests/test-provision.sh
git commit -m "provision: the upstream leaves, session start with units and notices, dconf seeding, --remove"
```

**Verification for the issue:** Step 3's commands, plus CI green. What CI cannot prove and the issue records as owed to 2F's VM check: that `dconf load` under `DCONF_PROFILE=tinkero` writes `~/.config/dconf/tinkero` on a real host, that the five units start from `--session` inside a real uwsm session, and that `install/user/theme.sh` stages a theme headless on the real tree.

---

### Task 5: The two provisioning wrappers

**Files:**
- Create: `distro/fedora/replacements/omarchy-provision-first-run`, `distro/fedora/replacements/omarchy-provision-user`
- Modify: `ci/allow/dropped-refs.allow` (one line removed), `tests/test-replacements.sh` (three cases)

**Interfaces:**
- Consumes: `tinkero-provision --session [--force]` and `tinkero-provision [--force]` (Tasks 3 and 4).
- Produces: upstream's `default/hypr/autostart.lua:7` (`omarchy-provision-first-run` at every session start) now runs `tinkero-provision --session`; the dropped-refs allowlist is at its six permanent entries.

- [ ] **Step 1: The failing tests**

Append to `tests/test-replacements.sh` before its final `rm -rf "$d"; finish` line:

```bash
# provisioning wrappers (plan 2E): exec tinkero-provision, flags passed through
cat > "$d/bin/tinkero-provision" <<'S'
#!/bin/bash
echo "tinkero-provision${*:+ $*}" >> "$LOG"
S
chmod +x "$d/bin/tinkero-provision"
: > "$LOG"; "$R/omarchy-provision-first-run"; assert_eq "$(cat "$LOG")" "tinkero-provision --session" "first-run: session mode"
: > "$LOG"; "$R/omarchy-provision-first-run" --force; assert_eq "$(cat "$LOG")" "tinkero-provision --session --force" "first-run: --force passes through"
: > "$LOG"; "$R/omarchy-provision-user"; assert_eq "$(cat "$LOG")" "tinkero-provision" "provision-user: a plain provision"
```

Run: `bash tests/test-replacements.sh` Expected: the three new cases fail (no such replacement).

- [ ] **Step 2: The replacements**

`distro/fedora/replacements/omarchy-provision-first-run` (mode 0755):

```bash
#!/bin/bash

# omarchy:summary=Finish first-login setup (Tinkero: tinkero-provision --session)
# omarchy:args=[--force]
# omarchy:hidden=true

# Upstream's autostart runs this at every session start. Tinkero's provisioning is
# tinkero-provision (design spec 4.6): --session is a fast no-op once done and starts the
# session-scoped user units; --force reprovisions.
exec tinkero-provision --session "$@"
```

`distro/fedora/replacements/omarchy-provision-user` (mode 0755):

```bash
#!/bin/bash

# omarchy:summary=Provision this user's configuration (Tinkero: tinkero-provision)
# omarchy:hidden=true

# Upstream's finalizer repointed XDG directories, changed the default browser and mail handler
# and created an unencrypted keyring; Tinkero's provisioning does none of that (design spec 4.6).
exec tinkero-provision "$@"
```

- [ ] **Step 3: Shrink the allowlist**

In `ci/allow/dropped-refs.allow`, delete the line `usr/bin/omarchy-provision-user:omarchy-provision-owner   # plan 2E`. Six entries remain, all marked permanent or `returns with Docker`.

- [ ] **Step 4: Verify**

Run: `bash tests/test-replacements.sh` Expected: `1..36`, no `not ok`.
Run: `grep -vc '^#' ci/allow/dropped-refs.allow` Expected: `6`.
Run: `./dev gates` Expected: four `PASS` (the replaced script no longer names `omarchy-provision-owner`; a stale allowlist entry would fail the gate).
Run: `shellcheck -x -e SC1090,SC1091 distro/fedora/replacements/* tests/test-replacements.sh` Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add distro/fedora/replacements/omarchy-provision-first-run distro/fedora/replacements/omarchy-provision-user ci/allow/dropped-refs.allow tests/test-replacements.sh
git commit -m "provision: omarchy-provision-first-run and -user exec tinkero-provision; dropped-refs.allow at its permanent entries"
```

**Verification for the issue:** Step 4's commands, plus CI green.

---

### Task 6: `install.sh`

**Files:**
- Create: `install.sh`, `tests/test-install.sh`
- Modify: `.github/workflows/ci.yml` (ShellCheck list gains `install.sh tests/fixtures/make-payload.sh`)

**Interfaces:**
- Consumes: `upstream.lock` keys `fedora`; `tinkero-provision --plan` and `tinkero-provision [--yes]` (Tasks 3 and 4).
- Produces: `bash install.sh [--yes] [--lock FILE]`; `TINKERO_REF` (the release workflow rewrites it), `TINKERO_COPR`; the seams `TINKERO_OS_RELEASE`, `TINKERO_DM_UNIT`, `TINKERO_EUID`, `TINKERO_LOCK`.

- [ ] **Step 1: The failing tests**

`tests/test-install.sh`:

```bash
#!/bin/bash
# install.sh against stub dnf, sudo, getenforce, uname, tinkero-provision and curl, with a
# fixture os-release and display-manager link. No package manager runs.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin" "$d/alone"; export LOG=$d/log
I=$ROOT/install.sh
cat > "$d/bin/dnf" <<'S'
#!/bin/bash
echo "dnf $*" >> "$LOG"
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
cat > "$d/bin/curl" <<'S'
#!/bin/bash
echo "curl $*" >> "$LOG"
while (($#)); do [[ $1 == -o ]] && { printf 'fedora=44\n' > "$2"; }; shift; done
S
printf '#!/bin/bash\necho Enforcing\n' > "$d/bin/getenforce"
# shellcheck disable=SC2016  # the stub reads ARCH at run time
printf '#!/bin/bash\necho "${ARCH:-x86_64}"\n' > "$d/bin/uname"
chmod +x "$d/bin"/*
printf 'ID=fedora\nVERSION_ID=44\n' > "$d/os-release"
printf 'ID=fedora\nVERSION_ID=43\n' > "$d/os-release-43"
ln -s /usr/lib/systemd/system/gdm.service "$d/dm-gdm"
ln -s /usr/lib/systemd/system/sddm.service "$d/dm-sddm"
printf 'omarchy_tag=v4.0.4\nfedora=44\n' > "$d/lock"
: > "$d/none"
export PATH=$d/bin:$PATH TINKERO_OS_RELEASE=$d/os-release TINKERO_DM_UNIT=$d/dm-gdm TINKERO_EUID=1000 REPOQUERY=$d/none
run() { : > "$LOG"; out=$(bash "$I" "$@" 2>&1 </dev/null) && rc=0 || rc=$?; }

# the happy path
run --yes --lock "$d/lock"
assert_eq "$rc" 0 "install: exit 0"
assert_eq "$(paste -sd'|' "$LOG")" "dnf repoquery --installed --queryformat %{name} %{from_repo}\n hyprland quickshell omedora omedora-settings|sudo dnf copr enable -y dromero/tinkero|dnf copr enable -y dromero/tinkero|sudo dnf install -y tinkero|dnf install -y tinkero|tinkero-provision --plan|tinkero-provision --yes" "install: preflight query, copr enable, install, plan, provision, in that order"
assert_contains "$out" "SELinux is Enforcing" "install: reports SELinux"
assert_contains "$out" "Log out and choose Tinkero" "install: says what comes next"
assert_contains "$out" $'seed\t.config/hypr/hyprland.lua' "install: shows the provisioning plan"
run --yes --lock "$d/lock"; assert_eq "$rc" 0 "install: re-running is fine (both stages are no-ops on a current machine)"

# the gates
run --lock "$d/lock"
assert_eq "$rc" 1 "gate: no terminal and no --yes stops"
assert_contains "$out" "run with --yes or from a terminal" "gate: and says how to proceed"
assert_eq "$(grep -c '^sudo' "$LOG")" 0 "gate: nothing was changed"

# preflight
TINKERO_OS_RELEASE=$d/os-release-43 run --yes --lock "$d/lock"
assert_eq "$rc" 1 "preflight: wrong Fedora release stops"; assert_contains "$out" "Fedora 44" "preflight: names the expected release"
ARCH=aarch64 run --yes --lock "$d/lock"
assert_eq "$rc" 1 "preflight: not x86_64 stops"
TINKERO_DM_UNIT=$d/dm-sddm run --yes --lock "$d/lock"
assert_eq "$rc" 1 "preflight: another display manager stops"; assert_contains "$out" "GDM" "preflight: names GDM"
printf 'hyprland copr:copr.fedorainfracloud.org:agaspar:omedora-4\n' > "$d/foreign"
REPOQUERY=$d/foreign run --yes --lock "$d/lock"
assert_eq "$rc" 1 "preflight: hyprland from another repository stops"; assert_contains "$out" "agaspar:omedora-4" "preflight: names the repository"
printf 'omedora copr:copr.fedorainfracloud.org:agaspar:omedora-4\n' > "$d/omedora"
REPOQUERY=$d/omedora run --yes --lock "$d/lock"
assert_eq "$rc" 1 "preflight: omedora installed stops"
printf 'hyprland copr:copr.fedorainfracloud.org:dromero:tinkero\n' > "$d/own"
REPOQUERY=$d/own run --yes --lock "$d/lock"
assert_eq "$rc" 0 "preflight: our own COPR's hyprland is fine"
TINKERO_EUID=0 run --yes --lock "$d/lock"
assert_eq "$rc" 1 "preflight: root stops"
assert_eq "$(grep -c '^sudo' "$LOG")" 0 "preflight: a failed preflight changes nothing"

# the lock: beside the script, or fetched from the ref
cp "$I" "$d/alone/install.sh"; cp "$d/lock" "$d/alone/upstream.lock"
: > "$LOG"; bash "$d/alone/install.sh" --yes >/dev/null 2>&1 </dev/null; rc=$?
assert_eq "$rc:$(grep -c '^curl' "$LOG")" "0:0" "lock: a lock beside the script is used, nothing fetched"
rm "$d/alone/upstream.lock"
: > "$LOG"; bash "$d/alone/install.sh" --yes >/dev/null 2>&1 </dev/null; rc=$?
assert_eq "$rc" 0 "lock: fetched when there is none beside the script"
assert_contains "$(cat "$LOG")" "https://raw.githubusercontent.com/dromeropa/tinkero/master/upstream.lock" "lock: from the ref the script names"
rm -rf "$d"; finish
```

Run: `bash tests/test-install.sh` Expected: fails (`install.sh` missing).

- [ ] **Step 2: The script**

`install.sh` (mode 0755):

```bash
#!/bin/bash
# install.sh: install Tinkero on Fedora Workstation (design spec 4.6). Run it as your own user:
#
#   bash install.sh [--yes] [--lock FILE]
#
# 1. preflight (no changes)  2. the plan, confirmed  3. system stage (sudo): enable the COPR and
# install the tinkero package  4. user stage: tinkero-provision, its own plan confirmed first.
# Re-running is safe: both stages are no-ops when the machine is current.
set -euo pipefail
copr=${TINKERO_COPR:-dromero/tinkero}
# The release workflow rewrites this to the tag it attaches the script to (design 2E, D7), so
# a script fetched from a release installs that release's lock.
TINKERO_REF=${TINKERO_REF:-master}
own_repo="copr:copr.fedorainfracloud.org:${copr//\//:}"
os_release=${TINKERO_OS_RELEASE:-/etc/os-release}
dm_unit=${TINKERO_DM_UNIT:-/etc/systemd/system/display-manager.service}
euid=${TINKERO_EUID:-$EUID}
yes=0; lock=${TINKERO_LOCK:-}

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "install.sh: $*" >&2; exit 1; }
say() { echo "install.sh: $*"; }
confirm() {   # QUESTION
  local a
  if (( yes )); then return 0; fi
  [[ -t 0 ]] || die "$1 needs a yes; run with --yes or from a terminal"
  read -r -p "$1 [y/N] " a
  [[ $a == [yY]* ]] || die "stopped; nothing was changed"
}
lock_get() {   # KEY: parsed, never sourced
  local line
  line=$(grep -E "^$1=" "$lock" | tail -n1) || die "no key '$1' in $lock"
  printf '%s\n' "${line#*=}"
}

while (($#)); do
  case $1 in
    --yes|-y) yes=1 ;;
    --lock) [[ -n ${2:-} ]] || die "--lock needs a file"; lock=$2; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -z $lock ]]; then
  if [[ -f $here/upstream.lock ]]; then
    lock=$here/upstream.lock
  else
    lock=$(mktemp); trap 'rm -f "$lock"' EXIT
    url="https://raw.githubusercontent.com/dromeropa/tinkero/$TINKERO_REF/upstream.lock"
    curl -fsSL -o "$lock" "$url" || die "could not fetch $url"
  fi
fi

# 1. Preflight: nothing changes.
[[ $euid != 0 ]] || die "run as your own user, not as root; the system stage uses sudo"
want=$(lock_get fedora)
id=$(sed -n 's/^ID=//p' "$os_release" | tr -d '"'); ver=$(sed -n 's/^VERSION_ID=//p' "$os_release" | tr -d '"')
[[ $id == fedora && $ver == "$want" ]] || die "this release of Tinkero is for Fedora $want; this host is ${id:-unknown} ${ver:-?}"
arch=$(uname -m)
[[ $arch == x86_64 ]] || die "Tinkero is x86_64 only; this host is $arch"
dm=$(basename "$(readlink "$dm_unit" 2>/dev/null || echo none)")
[[ $dm == gdm.service ]] || die "Tinkero needs GDM as the display manager; this host has ${dm%.service}"
if command -v getenforce >/dev/null 2>&1; then say "SELinux is $(getenforce)"; else say "SELinux: getenforce not found"; fi
installed=$(dnf repoquery --installed --queryformat '%{name} %{from_repo}\n' hyprland quickshell omedora omedora-settings 2>/dev/null || true)
while read -r name repo; do
  [[ -z $name ]] && continue
  [[ $name != omedora* ]] || die "$name is installed; remove Omedora first (sudo dnf remove 'omedora*')"
  [[ $repo == "$own_repo" ]] || die "$name is installed from $repo, not from $own_repo; remove it first so the pinned build can be installed"
done <<<"$installed"
say "preflight passed: Fedora $ver, $arch, GDM"

# 2. The plan and the first gate.
cat <<EOF

Plan:
  system stage (sudo):  dnf copr enable $copr
                        dnf install tinkero      (the desktop with its pinned Hyprland and Quickshell)
  user stage (you):     tinkero-provision        (its own plan is shown and confirmed first)
Nothing else changes: no other repository, no versionlock, no Flathub, nothing under /etc beyond the package's files.

EOF
confirm "Continue with the system stage?"

# 3. System stage.
y=()
if (( yes )); then y=(-y); fi
sudo dnf copr enable "${y[@]}" "$copr"
sudo dnf install "${y[@]}" tinkero
say "system stage done"

# 4. The provisioning plan, the second gate, the user stage.
echo; echo "Provisioning plan (per file; nothing you already have is overwritten):"
tinkero-provision --plan
echo
confirm "Continue with the user stage?"
if (( yes )); then tinkero-provision --yes; else tinkero-provision; fi
say "done. Log out and choose Tinkero at the GDM login screen."
```

In `.github/workflows/ci.yml`, add `install.sh tests/fixtures/make-payload.sh` to the ShellCheck run's file list (the line that names `tests/fixtures/make-tree.sh`).

- [ ] **Step 3: Verify**

Run: `bash tests/test-install.sh` Expected: `1..23`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 install.sh tests/test-install.sh` Expected: clean.
Run: `./dev check` Expected: green.
Run: `bash install.sh --help` Expected: the seven header lines, exit 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh tests/test-install.sh .github/workflows/ci.yml
git commit -m "provision: install.sh, preflight, plan, system and user stages with two gates"
```

**Verification for the issue:** Step 3's commands, plus CI green. Not provable here and recorded on the issue as owed to the VM smoke test (Phase 3): that dnf5's `repoquery --queryformat '%{from_repo}'` prints `copr:copr.fedorainfracloud.org:dromero:tinkero` for a package from the COPR, and that `dnf copr enable -y` accepts the flag; if either differs on a real Fedora 44, the implementer of that check fixes the two lines and records it under Deviations.

---

### Task 7: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` (status line; 4.6 additions), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (the 2E row; a "What executing 2E added to the queue" section), `README.md` (an Install section and a Remove section), `docs/guides/workflow.md` ("Where the build is")

- [ ] **Step 1: The master spec**

Status line (line 4): append `; 2E (provisioning and install) done 2026-09-XX (design: 2026-09-23-phase-2e-provision-design.md)`. Replace `XX` with the merge date.

In 4.6, after the paragraph beginning "Re-running is safe", add:

```
Two details settled by plan 2E (`docs/superpowers/specs/2026-09-23-phase-2e-provision-design.md`, decisions D3 and D7): the provisioning plan can only be printed once the package is installed, so `install.sh` confirms twice on a first install, before the system stage and before the user stage; and the script finds its lock beside itself in a checkout or fetches it from the ref the release workflow bakes into `TINKERO_REF`.
```

In 4.6, after the seeding rules list, add:

```
Plan 2E's design records the seeding set at `v4.0.4` (37 config files, the two branding files, `toggles/hypr/flags.lua`, tensaku's `state.toml`, four launchers, `.XCompose`, the preinstalls marker), the skip list (`provision/skip.list`: Chromium's profile and flags, decision D1), and what is deliberately not seeded (the nautilus-python extensions and the launcher icons, D12). The upstream leaves that are commands rather than copies (theme, mise, the work directory, the hardware fixes, the speaker tuning) are sourced from the tree, not copied into Tinkero, so the roster and the fixes are whatever the tag ships.
```

In 4.9, after "`tinkero-provision` seeds the Tinkero database once from the user's GNOME settings", add ` (the profile file itself ships with the package from plan 2E, so the seeding has somewhere to load into; the `DCONF_PROFILE` export is 2F's)`.

- [ ] **Step 2: The roadmap**

The 2E row's Status becomes `**done** 2026-09-XX: `2026-09-23-phase-2e-provision-and-install.md`; design `specs/2026-09-23-phase-2e-provision-design.md``. Add before "## What executing 2C added to the queue":

```
## What executing 2E added to the queue (2026-09-XX)

- **2F:** append `tinkero-inhibit-power-key.service` to `provision/session-units.list`; export `DCONF_PROFILE=tinkero` from uwsm's `env.d` (the profile file and the seeded database exist); the VM check proves `dconf load` under the profile wrote `~/.config/dconf/tinkero`, that the units start from `tinkero-provision --session`, and whether `omarchy-speaker-tuning.service` (installed and enabled under `~/.config/systemd/user` by `omarchy-audio-tuning on` on matching laptops, design D4) starts under GNOME; if it does and must not, 2F conditions it like `omarchy-fcitx5.service`. `omarchy-tailscale-receive.service` ships with its `[Install]` section too and is inert without `/usr/bin/tailscale`; 2F's stripping covers it. 2F's first COPR build issue also re-runs the depsolve for `Conflicts: nwg-panel`.
- **Phase 3:** `tinkero-status` reads `~/.local/state/tinkero/{seeded.tsv,release,done/}` and `tinkero-provision --plan`; the release workflow rewrites `TINKERO_REF` in `install.sh` and attaches it to the release; the VM smoke test runs `install.sh --yes` and confirms dnf5's `%{from_repo}` tag and `dnf copr enable -y`.
- **Bump checklist:** after a tag bump, diff `config/`, `applications/` and `install/user/**` against the previous tag (audit section 10, item 2); update `provision/skip.list` if a new shared-with-GNOME file appears; write `config-notes/<tag>.md` from the config-only migrations; re-run `tinkero-provision --plan` on the real payload and record the new `seed` count in the design's section 8.
- **Later polish:** the four seeded launchers show a generic icon (D12); the nautilus-python extensions are not seeded.
- **Permanent allowlist entries, final:** dropped-refs 6 (five comment-only, the Docker binding); arch-leak 7 (six comment-only, `omarchy-setup-security-fingerprint` until 2F).
```

- [ ] **Step 3: README and the workflow guide**

In `README.md`, after the "## Status" section, add:

```
## Install

On Fedora 44 Workstation with GDM, as your own user:

    bash <(curl -fsSL https://raw.githubusercontent.com/dromeropa/tinkero/master/install.sh)

The script checks the host first (Fedora release, x86_64, GDM, no Hyprland from another repository), prints its plan and asks before each of its two stages: `sudo dnf copr enable dromero/tinkero` plus `sudo dnf install tinkero`, then `tinkero-provision`, which seeds Tinkero's configuration into your home directory without overwriting anything you already have. Log out and choose Tinkero at the login screen. `tinkero-provision --plan` shows what provisioning would do; `--reset <path>` restores a packaged default with a backup.

Until the first release is tagged, the URL above installs from `master`. Releases attach a pinned `install.sh`.

## Remove

`tinkero-provision --remove`, then `sudo dnf remove tinkero` and `sudo dnf copr remove dromero/tinkero`. Files you changed are listed and kept. Your GNOME session was never touched; logging into it is always a way back, and after a crash Hyprland starts in Safe Mode (`Super+M` leaves it).
```

In `docs/guides/workflow.md`, under "Where the build is", replace the "Next" and "Then" bullets with:

```
- Done since: 2C (menu rewrite, 2026-09-23) and 2E (provisioning and install, 2026-09-XX).
- Then 2D (branding), 2F (session integration, which makes the `tinkero` RPM installable),
  Phase 3 (maintenance), each planned when the one before it has landed.
```

- [ ] **Step 4: Verify and commit**

Run: `./dev check` Expected: green.
Run: `git diff -U0 -- docs README.md | grep '^+' | grep -c "—"` Expected: `0`.

```bash
git add docs README.md
git commit -m "docs: 2E done, provisioning and install; roadmap queue and README install section"
```

**Verification for the issue:** the two commands, CI green, and the reviewer reads each edit against the 2E design. No mechanical check of prose exists beyond that.

---

## Deviations

Recorded per task by the implementing PR, as `docs/guides/workflow.md` requires. Empty until the plan runs.

## What this plan deliberately leaves out

- The `DCONF_PROFILE` export, the `[Install]` stripping with the fcitx5 drop-in, `tinkero-inhibit-power-key.service`, the PAM variants and `tinkero-pam-sync` in `%posttrans`: plan 2F.
- The first COPR build of the `tinkero` RPM and the `nwg-panel` depsolve proof: 2F's last issue.
- `tinkero-status`, the release workflow that bakes `TINKERO_REF` and archives the RPM set, the VM smoke test: Phase 3.
- Seeding the nautilus-python extensions and installing the launcher icons (design D12); modifying `omarchy-refresh-applications` (D11).
- A `--check` mode for unread config notes: `tinkero-status` reads the `done/notes-<tag>` markers instead.
