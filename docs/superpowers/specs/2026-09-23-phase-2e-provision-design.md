# Plan 2E design: provisioning and install

**Status:** design for plan 2E, derived from the Tinkero design spec (`2026-09-17-tinkero-design.md`, revision 2.1) on 2026-09-23. The master spec stays the binding authority; this document works out sections 4.5, 4.6, 4.9, 4.11 and 4.13 to the level a plan needs and records the decisions the master spec leaves open. Where the two disagree, this document says so under "Decisions" and the master spec is amended when the plan lands.
**Plan:** `docs/superpowers/plans/2026-09-23-phase-2e-provision-and-install.md`.
**Depends on:** plans 2A and 2B (on `master`). Not blocked by 2C or 2D (issue #9). 2F (session integration) provisions nothing and wires what 2E provisions.

## 1. What 2E delivers

Plan 2E is the path from a Fedora 44 Workstation with GDM to a user who can pick "Tinkero" at the login screen and land in a configured session, and back. Five deliverables:

1. **`tinkero-provision`**, the only program that writes into a home directory. It seeds the packaged user configuration per file without ever overwriting, records what it wrote, and on later runs makes a three-way decision per file (spec 4.6). It also runs the steps upstream keeps as commands (skill links, first theme, mise stubs, the work directory, hardware fixes), seeds the session's dconf database (spec 4.9), starts the session units at session start, and undoes all of it on `--remove` (spec 4.11).
2. **Two replacement scripts**, `omarchy-provision-first-run` and `omarchy-provision-user`, thin wrappers over `tinkero-provision`. Upstream's autostart calls the first at every session start; nothing else in the payload calls either. Replacing them clears the last non-permanent entry of `ci/allow/dropped-refs.allow`.
3. **`install.sh`**, the single entry point: preflight, plan, system stage, user stage (spec 4.6).
4. **`host.md`**, the host guide the patched `omarchy` skill already points at (spec 4.5, patch 0006).
5. **Payload data**: Tinkero's config overrides (`config/hypr/bindings.lua`), the seeding skip list, the session unit list, the session's dconf profile file, `Conflicts: nwg-panel` on the package, and the `assemble` steps that install them.

Not in 2E: the `DCONF_PROFILE` export in uwsm's `env.d`, the `[Install]` stripping of the user units and the fcitx5 drop-in, `tinkero-inhibit-power-key.service`, the PAM files (all 2F); `tinkero-status` and the release workflow (Phase 3); the first COPR build of the `tinkero` RPM (2F's last issue).

## 2. `tinkero-provision`

One bash script, `bin/tinkero-provision`, installed to `/usr/bin` by the existing `assemble` step 6. Modes:

| Invocation | Does |
|---|---|
| `tinkero-provision [--yes]` | provision: seed and update files, run the steps, report. Idempotent. `--yes` answers the one consent question (the `~/.bashrc` line) |
| `tinkero-provision --plan` | print the decision for every file and step; write nothing, not even the state directory |
| `tinkero-provision --session [--force]` | at session start: a fast no-op when the recorded release is current, otherwise a full provision; then the in-session steps once, then start the session units. `--force` reprovisions |
| `tinkero-provision --reset PATH` | restore one packaged default (PATH relative to `$HOME`, as `seeded.tsv` records it) with a timestamped backup; clears a `removed-by-user` mark |
| `tinkero-provision --reset dconf` | reseed the session's dconf database from GNOME's |
| `tinkero-provision --reset-all` | `--reset` for every packaged default (what the patched `omarchy-reinstall-configs` calls) |
| `tinkero-provision --remove` | undo provisioning (section 2.6) |

Refuses to run as root. Reads `OMARCHY_PATH` (upstream's own variable, default `/usr/share/omarchy`), `TINKERO_SHARE` (default `/usr/share/tinkero`), `TINKERO_LOCK` (default `$TINKERO_SHARE/upstream.lock`), `TINKERO_DCONF_PROFILE` (default `/etc/dconf/profile/tinkero`), `TINKERO_UNIT_DIR` (default `/usr/lib/systemd/user`) and the XDG base directories; these are the test seams, and the tests run against a fixture payload under a temporary `HOME`.

### 2.1 State

`$XDG_STATE_HOME/tinkero/` (normally `~/.local/state/tinkero/`):

- `seeded.tsv`: one row per file Tinkero wrote, tab-separated: `path` (relative to `$HOME`), `sha256` (of the content written), `release` (`<omarchy_tag>-<tinkero_rev>` from the lock, `v4.0.4-1` today), `state` (`seeded`, `removed-by-user`, `orphaned`). Sorted by path, rewritten atomically on every run.
- `release`: the release string of the last fully successful provision. `--session` compares it with the lock and does nothing when equal.
- `done/<name>`: markers for once-only steps (`hardware`, `audio-tuning`, `theme-in-session`, `welcome`, `agent-invite`, `dconf`, `notes-<tag>`).
- `provision.log`: the output of every step run, appended, timestamped.

Upstream's own state under `~/.local/state/omarchy/` is left to upstream's scripts, with two files Tinkero owns because upstream would have seeded them from `/etc/skel`: `preinstalls-removed` (the marker that closes the preinstalled-bindings gate, `default/hypr/helpers.lua:84-89`) and `toggles/hypr/flags.lua` (the file `default/hypr/toggles.lua` needs to exist). Both are seeded files with rows in `seeded.tsv`.

### 2.2 What is seeded

Sources and targets, in this order (a later source for the same target wins):

| Source | Target | Note |
|---|---|---|
| `$OMARCHY_PATH/config/**` | `~/.config/<same path>` | 37 files at `v4.0.4` after the drop list (39) and the skip list (2) |
| `$TINKERO_SHARE/config/**` | `~/.config/<same path>` | Tinkero's overrides; `hypr/bindings.lua` today |
| `$OMARCHY_PATH/icon.txt`, `logo.txt` | `~/.config/omarchy/branding/about.txt`, `screensaver.txt` | upstream treats these as user-replaceable branding; 2D replaces the sources at build time and the three-way rule carries the change to users who did not edit theirs |
| `$OMARCHY_PATH/default/hypr/toggles/flags.lua` | `~/.local/state/omarchy/toggles/hypr/flags.lua` | required by `default/hypr/toggles.lua` |
| `$OMARCHY_PATH/default/tensaku/state.toml` | `~/.local/state/tensaku/state.toml` | tensaku's defaults |
| `$OMARCHY_PATH/applications/*.desktop` whose `Exec=` does not start with `omarchy-launch-webapp` or `omarchy-webapp-handler-` | `~/.local/share/applications/<name>` | the TUI and application launchers (`foot`, `imv`, `mpv`, `Disk Usage`: 4 at `v4.0.4`); web-app launchers would appear in GNOME's overview |
| (marker) | `~/.local/state/omarchy/preinstalls-removed` | empty file, recorded like any seeded file |

The skip list, `$TINKERO_SHARE/provision/skip.list` (repo: `provision/skip.list`), names `config/` paths never seeded: `chromium/` and `chromium-flags.conf` (decision D1). A line ending in `/` is a directory prefix; any other line is an exact path.

`~/.config/git/config` has one extra rule: it is seeded only when neither it nor `~/.gitconfig` exists (spec 4.6: git configuration only when the user has none at all). Upstream's `install/user/git.sh` is not sourced (decision D5).

Three more things are written that are not file copies:

- **`~/.XCompose`**: upstream's `install/user/xcompose.sh` is sourced into a scratch home with `OMARCHY_USER_NAME` and `OMARCHY_USER_EMAIL` taken from `git config --global user.name` and `user.email` (empty when unset), and the file it renders is treated as one more packaged source: seeded when absent, updated when the user never edited it, kept otherwise, recorded in `seeded.tsv`. That is upstream's "only when absent" rule plus the three-way rule every other file gets.
- **The `~/.bashrc` line**, with consent (`--yes`, or an interactive yes; otherwise skipped with a message). Exactly this line, appended once, identified by its trailing tag:

  ```bash
  [[ ${XDG_SESSION_DESKTOP:-} == Hyprland && -r /usr/share/omarchy/default/bash/rc ]] && source /usr/share/omarchy/default/bash/rc  # tinkero-provision
  ```

  `~/.bashrc` is never replaced. A missing `~/.bashrc` is created with only that line.
- **The session's dconf database** (section 2.5).

### 2.3 The three-way decision

For every target in the union of the current sources and the rows of `seeded.tsv`, with `src`, `tgt`, `row` the sha256 of the source, the target on disk and the recorded row (`-` when absent) and `state` the row's state:

| Case | src | tgt | row | state | Decision |
|---|---|---|---|---|---|
| new to this user | h | - | - | - | **seed**: write, record |
| the user already has one | h | x | - | - | **conflict**: leave, report with a diff command |
| unchanged by both | h | r=h | r | seeded | **current**: nothing |
| changed upstream, not by the user | h | r | r, r != h | seeded | **update**: overwrite, record h |
| changed by the user, not upstream | h=r | u != r | r | seeded | **keep-user**: nothing |
| changed by both | h != r | u != r | r | seeded | **moved**: leave, report that the packaged default moved |
| deleted by the user | h | - | r | seeded | **mark-removed**: state becomes `removed-by-user` |
| deleted by the user, earlier | h | - | r | removed-by-user | **skip-removed**: never reseeded; listed |
| recreated by the user | h | x | r | removed-by-user | as `seeded` (the mark is cleared, then the rules above apply) |
| removed upstream, unchanged here | - | r | r | seeded | **delete**: remove the target, drop the row |
| removed upstream, changed here | - | u != r | r | seeded | **orphan**: leave, state becomes `orphaned`, reported until the user deals with it |
| removed upstream and here | - | - | r | any | **drop-row** |
| upstream re-added an orphan | h | x | r | orphaned | as `seeded` |

A target that is a symlink is never written through and never deleted: it decides as if its content were the user's (`conflict` when there is no row, `keep-user` or `moved` otherwise). `seed_decide` is a pure function of the four inputs and is table-tested.

### 2.4 The steps

After the files, in this order. Each step is run in a subshell with its output appended to `provision.log`; a failing step is reported and does not stop the others, and `release` is written only when every step succeeded, so `--session` retries at the next login (upstream's first-run has the same retry rule).

1. **Skill links**: upstream's loop from `omarchy-provision-user:87-103` verbatim (five harness directories plus Hermes profiles), so a new skill in a later tag is linked by the next run. `host.md` is inside the `omarchy` skill directory, so it is linked with it.
2. **First theme**: source `install/user/theme.sh`. Outside a Tinkero session (no `HYPRLAND_INSTANCE_SIGNATURE`) it runs with `OMARCHY_THEME_HEADLESS=1`, which upstream provides for exactly this (no shell to talk to): the theme is staged, the background link set, and none of the post-theme commands run, so nothing touches GNOME's dconf or any application's settings from GNOME.
3. **Work directory**: source `install/user/mise-work.sh` (`~/Work`, its `.mise.toml`, `mise trust`, `mise use -g node@latest`; the last one needs the network and is the usual reason this step fails offline).
4. **mise stubs**: source `install/user/mise.sh` (the roster is whatever the tag ships, spec 4.1).
5. **In-session only** (`--session`, once, markers under `done/`): the five hardware fixes under `install/user/hardware/`, then `install/user/first-run/audio-tuning.sh`, then, when the first theme was set headless at install time (`~/.local/state/omarchy/current/theme.name` exists and `done/theme-in-session` does not), one real `omarchy-theme-set` of that theme so that foot, tmux and the other post-theme targets get their files. They are in-session because two of the fixes talk to the audio server, one sets a gsettings key, and the theme's post commands need the shell (decision D4).
6. **Config notes**: print `$TINKERO_SHARE/config-notes/<omarchy_tag>.md` when it exists and has not been shown (marker `done/notes-<tag>`). No note exists at `v4.0.4`; the bump checklist writes the first one.

### 2.5 The session's dconf database

`tinkero-provision` seeds `~/.config/dconf/tinkero` once (marker `done/dconf`; `--reset dconf` repeats it after backing the file up):

```bash
DCONF_PROFILE=user dconf dump / | DCONF_PROFILE=tinkero dconf load /
```

`user` is Fedora's own profile (`/etc/dconf/profile/user`), so the dump is what GNOME sees; `tinkero` is the profile 2E ships as `/etc/dconf/profile/tinkero` (decision D2). The step runs only when that profile file exists, `dconf` is on `PATH` and `DBUS_SESSION_BUS_ADDRESS` is set; otherwise it is skipped with a message that names the reason and says to run `tinkero-provision` again from a graphical session. Nothing in 2E exports `DCONF_PROFILE` for the session; that is 2F's uwsm `env.d` line, and 2F's VM check proves the isolation.

### 2.6 Session start and removal

`--session` (from the replacement `omarchy-provision-first-run`, which upstream's `default/hypr/autostart.lua:7` runs at every start):

1. If `release` differs from the lock (or `--force`): provision as in 2.2 to 2.4, without the consent question (the `~/.bashrc` step is skipped when the line is not already there; it was offered at install time).
2. The in-session steps of 2.4 item 5, once.
3. Start every unit named in `$TINKERO_SHARE/provision/session-units.list` (repo: `provision/session-units.list`) whose unit file exists under `$TINKERO_UNIT_DIR` or `~/.config/systemd/user/`; a missing unit is logged and skipped. At `v4.0.4` the list is the five session units the master spec names, `omarchy-crash-watch.service`, `omarchy-sleep-lock.service`, `omarchy-recover-internal-monitor.service`, `omarchy-fcitx5.service`, `bt-agent.service`, plus `omarchy-speaker-tuning.service`, which exists only under `~/.config/systemd/user/` on the laptops `omarchy-audio-tuning on` matches and is skipped everywhere else (D4). 2F appends `tinkero-inhibit-power-key.service`. Nothing is enabled. The one remaining unit in the tree, `omarchy-tailscale-receive.service`, is gated on `ConditionPathExists=/usr/bin/tailscale` and inert (Tinkero packages no tailscale).
4. Once (markers): after `omarchy-notification-wait`, the welcome toast ("Super + K for the cheat sheet. Super + Space for the Tinkero menu.") and, when `omarchy-default-agent` prints nothing, "Set your default agent" with `--exec omarchy menu summon setup.default.agent` (upstream's `setup-agent.hook`, which never fires in Tinkero because it is a post-update hook).

`--remove` (spec 4.11): stop the listed units; delete `~/.config/dconf/tinkero`; remove every symlink in the five skill directories and the Hermes profiles whose target starts with `$OMARCHY_PATH/`; delete the tagged `~/.bashrc` line; delete every `seeded` row's target whose sha256 still matches and drop the row; list, without deleting, the rows whose target was modified, the mise stubs in `~/.local/bin` (files containing `mise x`), `~/Work`, `~/.local/state/omarchy`, `~/.config/omarchy/themes` and `~/.cache/omarchy`; finally delete the state directory. Then the README says: `sudo dnf remove tinkero` and `sudo dnf copr remove dromero/tinkero`.

## 3. The two replacements

`distro/fedora/replacements/omarchy-provision-first-run` is `exec tinkero-provision --session "$@"` (upstream's only flag, `--force`, passes through). `distro/fedora/replacements/omarchy-provision-user` is `exec tinkero-provision "$@"`. Both keep upstream's `# omarchy:summary` header line so `omarchy commands` lists them. `usr/bin/omarchy-provision-user:omarchy-provision-owner` leaves `ci/allow/dropped-refs.allow`, which is then at its six permanent entries.

## 4. `install.sh`

At the repo root, fetched from a tagged release URL in use, run as the desktop user. Flag: `--yes` (`-y`). The script uses one value from `upstream.lock`, the Fedora release it accepts, and carries it as a variable, `TINKERO_FEDORA=44`, beside `TINKERO_REF=master`; a repository test fails when that value differs from the lock's `fedora` key, and the release workflow (Phase 3) rewrites both variables when it attaches the script to a release (decision D7). The script makes no network request of its own.

1. **Preflight**, no changes: `/etc/os-release` says `ID=fedora` and `VERSION_ID` equals `TINKERO_FEDORA`; `uname -m` is `x86_64`; `/etc/systemd/system/display-manager.service` resolves to `gdm.service`; `getenforce` is reported; `dnf repoquery --installed --queryformat '%{name} %{from_repo}\n' hyprland quickshell omedora omedora-settings` shows nothing from a repository other than `copr:copr.fedorainfracloud.org:dromero:tinkero` and no `omedora*` at all; not root. Each failure stops with one explanation.
2. **Plan and first gate**: print the repository, the package and the user stage; confirm unless `--yes`. Without a terminal and without `--yes` it stops and says so.
3. **System stage**: `sudo dnf copr enable dromero/tinkero` and `sudo dnf install tinkero` (`-y` with `--yes`). Nothing else.
4. **Second gate and user stage**: `tinkero-provision --plan`, then a confirmation that names what the plan showed and the one existing file it touches ("create the files above and append the guarded line to ~/.bashrc?"), unless `--yes`; then `tinkero-provision --yes`, because the user has just answered the consent question the plan carries. Then: log out and pick "Tinkero" at GDM.

Two gates instead of the master spec's one (decision D3): the provisioning plan can only be printed by `tinkero-provision`, which does not exist on the machine before the system stage on a first install. Two prompts in total on an interactive first install, since the second gate answers the `~/.bashrc` question too. Both gates are the same question on a re-run, where both stages are no-ops.

## 5. `host.md`

`distro/fedora/skills/host.md`, installed by `assemble` into `default/agents/skills/omarchy/` inside the tree (so the skill link covers it). Content per spec 4.5: the host is Fedora; `omarchy pkg add` first, then `dnf` and `flatpak`; there is no AUR and the Arch package tools upstream's documentation mentions do not exist here; the name map at `/usr/share/tinkero/pkgmap.tsv` (kinds `dnf`, `flatpak`, `none`; how to add a row); PAM is `authselect`-managed and `/etc/pam.d` is never edited; SELinux stays enforcing, denials are read with `sudo ausearch -m AVC -ts recent`, never change mode, booleans or labels; `/usr/share/omarchy` and `/usr/bin/omarchy-*` are package-owned; `dnf history` for recent package changes; RPM Fusion's `akmod-nvidia`; `firewall-cmd`; podman; the desktop is Tinkero, built on the Omarchy tree, whose command names and paths it keeps; updates are `tinkero-update` (`dnf upgrade`, `mise up`, `flatpak update`); `tinkero-status` (Phase 3) reports maintenance state; Hyprland Safe Mode after a crash and `Super+M` to leave it; `tinkero-provision` and its `--plan`, `--reset` and `--remove`.

The file must not contain the tokens the arch-leak gate matches (`pacman`, `archlinux` and the rest of the pattern in `ci/gate-arch-leak`): the gate scans the payload and the allowlist may only shrink.

## 6. Payload and packaging

`build/assemble` gains two things: step 3c, inside the tree, `distro/fedora/skills/*.md` into `default/agents/skills/omarchy/`; and in step 5, `config/**` to `/usr/share/tinkero/config/`, `provision/*.list` to `/usr/share/tinkero/provision/`, `config-notes/*.md` (none yet; the loop tolerates the absent directory) to `/usr/share/tinkero/config-notes/`, `distro/fedora/dconf/profile/tinkero` to `/etc/dconf/profile/tinkero`, and the two launcher icons to `/usr/share/icons/hicolor/512x512/apps/` (D12). `tinkero.spec.in` gains `Conflicts: nwg-panel` (spec 6) and `%config %{_sysconfdir}/dconf/profile/tinkero`; `%{_datadir}/tinkero` already covers the rest. The depsolve proof for `nwg-panel` needs the `tinkero` RPM in COPR and belongs to 2F's first-build issue; 2E's proof is that the spec renders, parses and lints in CI.

`config/hypr/bindings.lua` is upstream's `config/hypr/bindings.lua` (the commented template) plus the two host-neutral bindings the closed gate would otherwise remove (spec 4.6):

```lua
o.bind("SUPER + ALT + RETURN", "Tmux", { omarchy = "terminal-tmux" })
o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })
```

`distro/fedora/dconf/profile/tinkero` is `user-db:tinkero` followed by Fedora's three `system-db:` lines (`local`, `site`, `distro`), per spec 4.9.

## 7. Decisions taken by this design

Each is a call the master spec leaves open or states in a form that cannot be built literally. They are listed so the operator can veto any of them at the approval gate.

- **D1, chromium is not seeded.** `config/chromium/Default/Preferences` and `config/chromium-flags.conf` are on the skip list. Spec 4.6 says `config/**`, but the non-goals exclude the Chromium micro-fork and its helpers, and a pre-seeded Chromium profile is read by the same Chromium under GNOME, which is the kind of shared state 4.9 keeps provisioning out of. The skip list is data, so the decision costs one line to reverse.
- **D2, 2E ships `/etc/dconf/profile/tinkero`.** The roadmap gives the profile to 2F, but the dconf seeding the roadmap gives to 2E cannot load into a profile that does not exist. 2E ships the file (inert until `DCONF_PROFILE` names it); 2F ships the uwsm export and the VM check.
- **D3, two confirmation gates in `install.sh`** (section 4).
- **D4, hardware fixes, speaker tuning and the theme's real application run in-session, once.** Upstream runs the hardware fixes at finalize time and the tuning at first run. Two of the five fixes need the audio server and one sets `text-scaling-factor` through gsettings; in the session that key goes to the Tinkero database (once 2F exports the profile) instead of GNOME's. The nouveau fix appends to a seeded `looknfeel.lua`, after which the file counts as user-modified, which is the truthful classification. A theme set headless at install time is applied once for real inside the first session, because headless mode skips the post-theme commands that write foot's, tmux's and the other targets' theme files. The tuning's unit is handled like every other session unit: `omarchy-audio-tuning on` copies `omarchy-speaker-tuning.service` from the tree into `~/.config/systemd/user/`, enables it and starts it; the unit is on `provision/session-units.list`, so `--session` starts it at every later login and `--remove` stops it. Until 2F strips the `[Install]` sections at build time, the copied unit still carries `WantedBy=graphical-session.target` and the enable succeeds, so on a matching laptop the EQ also runs under a GNOME login, the same exposure the other five units have today and the state 2F exists to end: once the tree's unit has no install section, the enable fails silently, the restart starts it for the current session, and only the list starts it afterwards. On machines no tuning matches (the usual case) the step is a no-op and the list entry is skipped.
- **D5, `install/user/git.sh` is not sourced.** It only sets `user.name` and `user.email` from installer inputs Tinkero does not have. The aliases arrive through the seeded `config/git/config`, with the "no git config at all" rule of section 2.2.
- **D6, the session unit list is data** (`provision/session-units.list`), so 2F appends a line instead of editing `tinkero-provision`.
- **D7, `install.sh` carries the one lock value it needs** (section 4). The master spec (4.12) has the script parse the lock; a script fetched with `bash <(curl ...)` has no lock beside it, and fetching one is a network round trip to read a single integer. The value is baked in, pinned to the lock by a test, and rewritten at release time with the ref.
- **D8, an `orphaned` state** for a file upstream removed that the user had changed, so it is reported at every run until the user deletes or keeps it (the master spec says "report it as orphaned" and no more).
- **D9, steps do not abort each other**; `release` is written only on full success and `--session` retries. Same rule as upstream's first-run, without its log file format.
- **D10, the launcher rule is mechanical** (`Exec=` not a web-app command), so a new upstream launcher is classified by what it does, not by a list.
- **D11, `omarchy-refresh-applications` ships unmodified.** It is not in the audit's patch or replacement list; nothing kept calls it (its callers are dropped), and a user who runs it by hand gets upstream's behaviour, web-app launchers included. `host.md` does not mention it.
- **D12, nautilus-python extensions are not seeded; the two launcher icons ship in the package.** Upstream's `/etc/skel` carries `default/nautilus-python/extensions/*.py`; GNOME's Files loads the same directory, so they would add Omarchy actions to GNOME, and nautilus-python has no per-session extension path. The icons the seeded launchers name (`disk-usage`, `imv`) are package content upstream installs system-wide, so `assemble` installs `applications/icons/Disk Usage.png` and `imv.png` (512 by 512) under `/usr/share/icons/hicolor/512x512/apps/`; the other fourteen icons belong to web apps and are not installed.

## 8. What can be verified now, and what cannot

Hermetic, in `./dev check` and CI: the decision table; every mode of `tinkero-provision` against a fixture payload under a temporary `HOME` with stub `dconf`, `systemctl`, `git`, `mise` and the notification commands on `PATH`; the two wrappers; `install.sh` against stub `dnf`, `sudo`, `getenforce`, `uname` and `tinkero-provision` with a fixture `os-release` and display-manager link, plus a test that its `TINKERO_FEDORA` equals the lock's `fedora`; the assemble steps against the fixture tree; the gates against the real tree, with the dropped-refs allowlist at six entries.

Measured against the real payload, in the plan's verification steps: `tinkero-provision --plan` on an empty `HOME` decides `seed` for exactly 47 paths at `v4.0.4` (37 config files, 2 branding files, `flags.lua`, `state.toml`, 4 launchers, `.XCompose`, the preinstalls marker), none of them under `chromium`, and no `conflict`.

Only on a real host or VM, and therefore recorded on the issue rather than proven by CI: that dnf5's `%{from_repo}` tag and `dnf copr enable -y` behave as the stubs assume; that `dconf load` under `DCONF_PROFILE=tinkero` writes `~/.config/dconf/tinkero` (2F's VM check, which also proves the isolation); that `install/user/theme.sh` in headless mode stages a theme on the real tree; that the units start from `--session` inside a real uwsm session; that `mise use -g node@latest` and the Hermes installer complete with network. Spec 8's VM smoke test (Phase 3) runs `install.sh --yes` end to end and provisions a fresh user and one with dotfiles; until then these are the manual checks 2F's and Phase 3's issues carry.

## 9. Interfaces later plans rely on

- 2F: `provision/session-units.list` (append `tinkero-inhibit-power-key.service`); `/etc/dconf/profile/tinkero` exists and `~/.config/dconf/tinkero` is seeded, so `DCONF_PROFILE=tinkero` in uwsm's `env.d` completes spec 4.9; `tinkero-provision --session` is what starts the units, so stripping `[Install]` changes nothing for it.
- Phase 3, `tinkero-status`: `~/.local/state/tinkero/seeded.tsv` (four columns as in 2.1) and `release` for the provisioning state; `--plan` output (one decision word, a tab, the path) for conflicts, moved defaults and orphans; `done/notes-<tag>` for unread config notes; `install.sh`'s `TINKERO_REF` and `TINKERO_FEDORA` for the release workflow.
- Bump checklist: `config-notes/<tag>.md` is where config-only migrations go (audit, section 10, item 5); `provision/skip.list` and the launcher rule are re-checked against the new tag's `config/` and `applications/`.
