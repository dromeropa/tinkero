# Tinkero design spec

**Tagline:** a tinkerable desktop for Hyprland, bring your own distro.
**Status:** revision 2.1, 2026-09-21. Phase 0 spike done (`docs/research/phase-0-findings.md`, GO on Phase 1); plan 2A executed. Fedora 44 x86_64 is the first target.
**Pronunciation:** tin-KEH-ro.

This document records what Tinkero is, why it is shaped the way it is, and the decisions behind it. It is the input to the implementation plans.

Revision 2.1 folds in the Phase 0 findings: the lock screen and both PAM variants work under SELinux, the power-key inhibitor works, and the GNOME invariant needed a different mechanism (4.9), a manifest correction (section 6) and session-scoped user units (4.6). Revision 2 incorporates `docs/spec-review.md` (the critical review of revision 1) and `docs/research/arch-coupling-audit.md` (the classified audit of the pinned upstream tag). Revision 1 is in git history at commit `d4c01c7`. Where this document gives specifics about upstream (script names, counts, line numbers, the agent roster), they come from the audit of tag `v4.0.4`, not from `docs/research/omarchy-research.md`, which studied `quattro` HEAD a day later and differs in places.

## 1. Problem and goals

The author runs Fedora and wants to keep the Fedora and Red Hat base: dnf, RPM, SELinux enforcing, point releases, the stock kernel, GRUB, firewalld. They want three things Omarchy does well, without any of the Arch parts:

1. **Tiling.** Hyprland with Omarchy's keybindings and workflow, the terminal setup, and herdr as the session layer for agents.
2. **Plugins.** The ability to build their own bar widgets, panels and services for their workflows, with the connections between them. In Omarchy this is the Quickshell shell's plugin system, which is not Arch-specific at all.
3. **The agent as a first-class citizen.** Choose one agent as the default, launch it unattended from a keybinding, let it create plugins, edit configuration and customize the desktop through skills, plus dictation. The Omarchy workflow for this is the model.

They also like the look, and they have one hard constraint: **low maintenance.** On every machine, updates are `sudo dnf upgrade` plus `mise up` and nothing else; `dnf install` keeps working; nothing requires weekly tinkering to stay current. The *packager's* cost (the author, once, for all machines) is separate and is budgeted in 1.1.

Tinkero is also meant as a base others can build on, eventually installable over other distros as an alternative desktop experience. It is explicitly not an "omakase" project: the idea is the opposite of chef's choice, a kit you assemble yourself.

Each goal has an acceptance test in section 8; a goal without a passing test is not done.

### 1.1 Why this overrides the research recommendation

`docs/research/omarchy-research.md` section 4.6 recommends against this project: "Do not port the Omarchy desktop to Fedora. Either migrate to Omarchy, or stay on Fedora and take only the agent layer." It gives three reasons. This spec proceeds anyway, with these answers:

| Research objection | Answer in this design |
|---|---|
| A port delivers the files but not the maintenance; the porter becomes the maintainer of every seam, and upstream moves weekly | Tinkero **pins** a tag and bumps deliberately, so upstream's pace sets the size of a bump, not its frequency. The seam is measured (audit: 11 small patches, 21 replacement scripts, the rest dropped or untouched) and guarded by CI gates that fail a bump when upstream adds a new Arch assumption (section 8) |
| The Hyprland stack on Fedora lives in one-person COPRs | True, and the one person is now the author, by choice: owning the specs removes the dependency on someone else's pace. The cost is real and is budgeted below. Phase 0 proves the desktop on the existing `omedora-4` COPR before any spec is forked |
| A port gets Omarchy's churn without Omarchy's rollback | Nothing under a pinned tree rolls except Fedora itself. Rollback is: GNOME stays installed and unaffected (an invariant, section 4.9, with a test); every release's RPM set is archived on the matching GitHub release, because COPR prunes old builds and only its administrators can turn that off (4.11); the tree and its compositor pin move in one dnf transaction (4.2), so there is no half-upgraded state to roll back from |

**Maintenance budget (proposed, author to confirm; see section 10).** Per machine: zero beyond `dnf upgrade` and `mise up`. For the packager: an average of four hours a month over a quarter, expected to be spiky around Fedora Qt updates (4.1), Hyprland releases and Fedora branch points. **Exit criterion:** if the packager cost exceeds the budget for two consecutive quarters, or a Fedora update leaves the desktop unusable for more than a week, fall back to the research's alternative: stay on Fedora GNOME and keep only the agent layer, which Tinkero's own packaging makes a clean `dnf remove`.

## 2. What it is, in one paragraph

Hyprland is the compositor and does the heavy lifting of window management. Tinkero is the desktop environment around it: the Quickshell shell (bar, launcher, menu, notifications, OSD, lock, idle, wallpaper, polkit), the session wiring, the keybinding and theme system, the tooling, and the agent harness. Tinkero does not rewrite any of that. It vendors the distro-neutral part of Omarchy at a pinned tag and replaces Omarchy's Arch substrate (installer, provisioning, migrations, pacman wrappers, Limine, snapper, ufw, kernel, pacman hooks) with the Fedora substrate: a COPR for the packages Fedora lacks, an RPM for the tree, and Fedora-native replacements for the scripts that touch the package manager or the host.

## 3. Non-goals

- Not a distribution, not an ISO, not an installer for a fresh machine. It installs on top of an existing Fedora Workstation with GDM.
- Not a port of Omarchy's Arch machinery. No `omarchy update`, no migrations, no channels, no Limine or snapper integration, no custom kernel, no ufw, no hibernation setup, no factory reset, no log upload to Omarchy's servers.
- Not Omarchy's app catalogue. No Chromium micro-fork, no web apps, no gaming, no Windows VM, no Docker setup, and in v1 no AI desktop apps or third-party service installers. Their menu entries are removed at build time (4.4).
- Not bootc or image mode, at least for now. The author wants `dnf install` to keep working on the host.
- Not a reimplementation. Reimplementations of Omarchy go stale in months because upstream releases weekly; the only porting pattern that has held up is vendoring the real tree and patching the seams (Omedora on Fedora, zicochaos/omarchy-nix on NixOS).
- Not multi-architecture. x86_64 only. aarch64 is out of scope until someone needs it.
- No SELinux policy changes. Tinkero ships no policy module and sets no booleans or permissive domains (section 5).
- No changes to the host's login, boot or firewall: GDM, GRUB, dracut, plymouth, firewalld and authselect stay as Fedora configured them. SDDM is not installed. The opt-in exceptions are the menu actions a user asks for explicitly: fingerprint setup (through `authselect`, the Fedora-native mechanism) and enabling the SSH server (through `firewall-cmd`).
- NVIDIA is documented, not supported: the host guide tells the agent and the user to use RPM Fusion's `akmod-nvidia`; `install.sh` does not enable RPM Fusion.
- HiDPI, multi-monitor and input behaviour are "as upstream"; Tinkero adds nothing.

## 4. Architecture

Four pieces, all delivered from one public repo, `github.com/dromeropa/tinkero`.

### 4.1 Fedora package substrate (a COPR)

The COPR project is `<fas-user>/tinkero`, chroot `fedora-44-x86_64`, with COPR's default retention (`auto_prune` stays on: only COPR administrators may disable it, found when the project was created on 2026-09-22; superseded builds therefore disappear after COPR's retention window, and 4.11 archives them elsewhere). It carries what Fedora lacks, with RPM specs forked from the `agaspar/omedora-4` COPR so that Tinkero owns its recipes:

- The Hyprland stack: `hyprland` (0.56.x, Lua config), `hyprutils`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `hyprwire`, `hyprtoolkit`, `aquamarine`, `hyprland-protocols`, `hyprwayland-scanner`, `glaze`, `hyprland-guiutils`, `hyprland-preview-share-picker`, `hyprpicker`, `hyprsunset`, `xdg-desktop-portal-hyprland`.
- `quickshell` at the commit upstream pins, `uwsm`, `gpu-screen-recorder`, `tensaku`, `ttfx`, `voxtype`, a Nerd-patched JetBrains Mono.
- **`mise`** and **`herdr`**. Both are core to the design (`mise up` is half the update contract; herdr is goal 1), neither is in Fedora, and at the pinned tag upstream ships herdr as a system package, not through mise. Packaging them keeps them under `dnf upgrade`. mise's self-update is disabled in the package.

`satty` is not packaged: the v4 tree uses `tensaku`.

**The Qt obligation.** Quickshell links Qt private APIs: Fedora's own `quickshell` requires `libQt6Core.so.6(Qt_6.10_PRIVATE_API)` and equivalents for Gui, Qml, Quick and WaylandClient, and Fedora 44 has already moved Qt from 6.10.2 to 6.11.2 inside the release, which forced a Quickshell rebuild. RPM generates those symbol-version requirements automatically, so a stale COPR build shows up as a **held-back `dnf upgrade`, never a broken shell**. The packager's duty is to rebuild Quickshell when Fedora's Qt minor version changes; the weekly workflow (4.7) detects it and triggers the rebuild.

The agent CLIs are **not packaged**. They are installed lazily through mise stubs created by upstream's `install/user/mise.sh` at the pinned tag (at `v4.0.4`: codex, claude, crush, gemini, gh, copilot, opencode, playwright, pi, omp, grok, cursor-agent, ghui, hunk, muse, plus hermes through its own installer). This spec does not enumerate the roster beyond that; it is whatever the tag ships. `openclaw` is removed from the agent picker because it is a pacman package upstream.

### 4.2 The `tinkero` RPM (vendored Omarchy tree plus Fedora substrate)

**Build.** COPR's SCM source type with the `make_srpm` method (`.copr/Makefile`). At SRPM time, with network: read `upstream.lock`, download the upstream tarball for `omarchy_commit`, verify `omarchy_sha256`, and template `tinkero.spec` from `tinkero.spec.in`. The RPM build itself runs offline in mock, as COPR requires. `Version:` is the upstream tag without the `v` (4.0.4); `Release:` is `tinkero_rev` from the lock. COPR rebuilds on push through its GitHub webhook; no API token is needed for that.

**The pin is RPM metadata, not machine state.** Generated from `upstream.lock` (the Quickshell line is the lock's `quickshell` value verbatim, which is why the lock stores the full snapshot version):

```
Requires: (hyprland >= 0.56.2 with hyprland < 0.57)
Requires: quickshell = 0.3.0^20.git28771c7
Conflicts: omedora, omedora-settings
```

The `with` form is RPM's rich-dependency idiom for a version range on one package; `rpmspec --parse` in CI lint confirms the generated spec parses. A tree bump and the compositor bump it needs therefore land in the same dnf transaction or not at all. There is no `dnf versionlock`, nothing to unlock per machine, and nothing left behind on removal.

**`%install`**, in this order:

1. Unpack the tree to `/usr/share/omarchy` (upstream's own path; `OMARCHY_PATH` defaults to it, and the `omarchy` skill teaches the agent that this directory is package-owned and read-only, which is exactly right under RPM).
2. Delete everything the audit marks *drop* (`build/drop.list`: 79 commands at `v4.0.4`, plus `migrations/`, `default/pacman/`, `default/limine/`, `default/snapper/`, `default/libalpm/`, the plymouth and sddm themes, `omarchy-migrate-notify.service`, and the parts of `install/` that the replacement provisioning does not source).
3. Apply the patch set (4.3) and copy the replacement scripts over their upstream namesakes.
4. Rewrite the default menu (4.4) and apply branding: replace the logo files, rebuild the icon font, apply `branding/strings.tsv` (4.13).
5. Move `bin/omarchy-*` to `/usr/bin` and populate `/usr/share/omarchy/bin/` with **symlinks** to them. This is upstream's own layout; it matters because the Hyprland environment puts `$OMARCHY_PATH/bin` first on `PATH`, so there must be exactly one copy of each script.
6. Install `/usr/share/wayland-sessions/tinkero.desktop` (`Name=Tinkero`, `Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop`), `/usr/share/uwsm/env.d/10-omarchy` (upstream's file; it also activates mise shims for the graphical session, which is how herdr-era tools and agent stubs reach keybindings), the user systemd units (upstream's kept ones with their `[Install]` sections stripped at build time, the `omarchy-fcitx5` drop-in, `tinkero-inhibit-power-key.service` and `tinkero-gnome-restore.service`; nothing is enabled, 4.9), the dconf profile `/etc/dconf/profile/tinkero` (4.9), the `omarchy.ttf` icon font and fontconfig snippet, the two lock-screen PAM variants under `/usr/share/tinkero/pam/` with `/etc/pam.d/omarchy-lock-password` as a `%ghost` written by `tinkero-pam-sync` in `%posttrans` (4.8), `/usr/share/tinkero/upstream.lock`, `/usr/share/tinkero/pkgmap.tsv`, and the `tinkero-*` commands.

**Not installed: upstream's `etc/` tree.** Upstream ships 40 files of system policy under `etc/` (audit, section 12): sudoers `NOPASSWD` rules, `faillock.conf`, `nsswitch.conf`, sysctl, logind, resolved, oomd and system-manager overrides, NetworkManager and modprobe tweaks, and the Arch boot, SDDM and Docker configuration. None of it is installed: it is host policy, and section 5 forbids sudoers additions. Three exceptions, each relocated so that it cannot affect other sessions: `etc/fastfetch/config.jsonc` goes to `/usr/share/tinkero/fastfetch/` (it drives the About screen; see the `omarchy-launch-about` patch); `etc/mise/conf.d/omarchy.toml` (a tool alias for `cursor-agent`) is installed as is, since it only matters when that tool is installed; and the one behaviour worth keeping from the logind override, not powering off when the power key is pressed so that the shell's power menu can handle it, is obtained without touching `/etc` by `tinkero-inhibit-power-key.service`, a user unit started from inside the Tinkero session (4.6) that holds a `handle-power-key` inhibitor lock (logind's default polkit policy grants `inhibit-handle-power-key` to the active session without a prompt, and upstream binds `XF86PowerOff` to the power menu, so the key keeps working; Phase 0 confirms). The same directory's `InhibitDelayMaxSec=15` override has no unprivileged equivalent and is dropped: `omarchy-sleep-lock` then has logind's default five seconds, not fifteen, to get the lock screen up before suspend. Upstream's comment says five is not always enough, so this is an accepted risk that Phase 0 measures; if the lock loses that race, the fallback is documenting the one-line logind override for the user to add, not shipping it. The consequence of dropping the sudoers rules is only that changing DNS, time zone or browser policy from the menu asks for a password.

**Not installed: `/etc/skel`.** Revision 1 seeded new users through `/etc/skel`. That is global to the machine (every new account, including ones that only use GNOME) and does nothing for existing accounts, which is what every real user of Tinkero has. `tinkero-provision` (4.6) is the single seeding path.

The `hyprland` package ships its own session files, so GDM also lists "Hyprland". That session lacks the uwsm environment and is not supported; the README says so. Hiding another package's session file is not worth a patch.

The upstream tree is never copied into this repo. The repo holds `upstream.lock`, the spec template, the patches, and Tinkero's own files.

### 4.3 Replacements and patches

The authoritative, per-script classification is `docs/research/arch-coupling-audit.md` sections 4 to 6. Summary:

**Patches** (a diff against upstream, so a rebase cost on every bump; this is the number to keep small). Twelve files, all but the first under fifteen changed lines (patches 0001 to 0010 exist after plan 2B; `omarchy-apply-lock` is plan 2F's):

| File | Change |
|---|---|
| `shell/plugins/menu/MenuModel.js` | `guardHelpers()` builds the installed-package set from `rpm -qa` names and provides, mapped back to Arch names through the reverse index of `pkgmap.tsv`, instead of `pacman -Qq`/`-Qi`. Without this every menu package guard is wrong, because the menu defines its own `omarchy-pkg-present` function that shadows the command |
| `bin/omarchy-apply-lock` | manages only the fingerprint PAM file; the password file is RPM-owned and written by `tinkero-pam-sync` (4.8). Upstream's target-user logic is kept |
| `bin/omarchy-debug` | package inventory through `rpm -qa --qf`; product line from `rpm -q tinkero` |
| `bin/omarchy-version` | version and release from `rpm -q tinkero`. The tree's own `version` file is not usable: at tag `v4.0.4` it still reads `4.0.0.alpha` |
| `bin/omarchy-reinstall-configs` | upstream replays `/etc/skel` over `$HOME` and then calls `omarchy-refresh-limine` and `omarchy-refresh-plymouth`; none of the three exists in Tinkero, so the body becomes `tinkero-provision --reset-all`. The command name is kept because the `omarchy` skill documents it as the rollback |
| `bin/omarchy-setup-security-sshd`, `bin/omarchy-remove-security-sshd` | the `ufw` blocks become `firewall-cmd --add-service=ssh` / `--remove-service=ssh`; the other 170 lines are portable, so a patch beats a replacement |
| `bin/omarchy-launch-about` | passes `-c /usr/share/tinkero/fastfetch/config.jsonc` on its two `fastfetch` calls, **only when the user has no `~/.config/fastfetch/config.jsonc`**: the script already has a `custom_fastfetch_config` test that it uses to skip its window-fit logic, and `-c` would otherwise override the user's own file. Upstream relies on a system-wide `/etc/fastfetch/config.jsonc`, which Tinkero does not install because it would change `fastfetch` for every session on the host |
| `bin/omarchy-remove-launcher-entry` | `rpm -qf` and `dnf remove` instead of `pacman -Qqo` and `pacman -Rns` |
| `bin/omarchy-remove-dev-env` | two direct `pacman -Rns` calls become `omarchy-pkg-drop` |
| `default/agents/skills/omarchy/SKILL.md` | the package idiom (lines 149, 256) points at `host.md`; the "Other Configs" row for fastfetch (line 175) names the relocated default instead of `/etc/fastfetch/config.jsonc` |
| `default/agents/skills/diagnose-crash/SKILL.md` | "This is Arch" and the debuginfod URL become Fedora's (`https://debuginfod.fedoraproject.org/`) |

**Replacements** (Tinkero's own file under the upstream name; no rebase):

| Script | Tinkero behaviour |
|---|---|
| `omarchy-pkg-present`, `omarchy-pkg-missing` | `rpm -q` through the name map |
| `omarchy-pkg-add`, `omarchy-pkg-drop` | name map, then `dnf install`/`remove` or `flatpak install`/`uninstall`. Elevation: `pkexec` whenever a Wayland display is present, `sudo` only over SSH or on a console. Upstream's rule (`sudo` in a terminal) breaks the agent workflow: Phase 0's Milestone A stalled at `sudo`'s password prompt in the agent's own terminal, which the agent cannot answer. `pkexec` raises the shell's polkit dialog instead, the user approves it there, and no sudoers or polkit rule is added (section 5). An unmapped name, a `none` target, or a Flatpak target without a Flathub remote prints what to do by hand and exits 1 |
| `omarchy-pkg-aur-accessible`, `-aur-add`, `-aur-install` | stubs: no AUR on this host |
| `omarchy-update` | prints "Tinkero updates through dnf upgrade and mise up; see tinkero-status", exit 0 |
| `omarchy-update-available` | exit 1, so the bar's update indicator stays off |
| `omarchy-channel-current`, `omarchy-channel-set`, `omarchy-version-channel` | report `tinkero`; `-set` refuses |
| `omarchy-version-pkgs` | last dnf transaction time |
| `omarchy-hibernation-available` | false, so the menu row hides itself |
| `omarchy-setup-security-fingerprint`, `omarchy-remove-security-fingerprint` | upstream edits `/etc/pam.d/sudo` and `polkit-1` with `sed -i`, which authselect owns on Fedora. Setup: `dnf install fprintd fprintd-pam`, enrol, `authselect enable-feature with-fingerprint`, then `omarchy-apply-lock`. Remove: `authselect disable-feature with-fingerprint`, `omarchy-apply-lock`, `omarchy-pkg-drop fprintd-pam` |
| `omarchy-provision-first-run`, `omarchy-provision-user` | thin wrappers over `tinkero-provision` (4.6) |

Dropped for the same reason, until authselect-based replacements exist: `omarchy-setup-security-fido2` and `omarchy-remove-security-fido2` (they `sed` `pam_u2f.so` into PAM files; the Fedora route is `authselect enable-feature with-pam-u2f`). Dropped outright: `omarchy-sudo-passwordless` (writes sudoers), `omarchy-toggle-hybrid-gpu` (`supergfxd` is not packaged for Fedora), `omarchy-dev-link`/`-unlink`/`-status` (a root-level redirect of the package-owned tree).

**The name map** is `distro/fedora/pkgmap.tsv`, installed to `/usr/share/tinkero/pkgmap.tsv`: tab-separated `arch-name`, `kind` (`dnf`, `flatpak`, `none`), `target`. Every literal package name that the installed payload passes to a package wrapper or a menu guard must have a row, even if its kind is `none`; CI enforces this (section 8). The initial content comes from the package table in the research doc, section 3.3.

Everything else in `bin/` (336 of 444 scripts at `v4.0.4`) ships unmodified, and that claim is enforced by the Arch-leak gate rather than asserted.

### 4.4 Menu: build-time rewrite of the default, not an extension file

Revision 1 planned a system-level extension file. Upstream has none: `Menu.qml` loads exactly two sources, the package default and `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Two properties of the merge rule out doing this through the user file: an entry cannot be deleted by a merge, only overridden, and hiding a submenu with `"when": "false"` leaves its children reachable through menu search.

So `menu/apply-overrides` rewrites `default/omarchy/omarchy-menu.jsonc` during `%install`, driven by `menu/overrides.jsonc`:

- **delete by id prefix**: the Arch-only and out-of-scope groups listed in the audit, section 7 (77 of 333 entries at `v4.0.4`);
- **delete by action**: any remaining entry whose action or guard names a dropped script. This list is computed, so a new upstream entry that calls a dropped script is removed automatically, and the build log names it;
- **replace**: `update.omarchy` becomes "Update (dnf + mise)" and runs `tinkero-update` in a floating terminal (`sudo dnf upgrade`, then `mise up`).

The user's own extension file is untouched and layers on top exactly as upstream documents. There is no QML patch and nothing to conflict textually; ids that stop matching after an upstream rename are reported by the build. A system-level extension path will be offered upstream as a PR, since any port would use it; if it lands, this mechanism can shrink.

Visible strings in the menu are rebranded as part of the same rewrite (4.13).

### 4.5 Skill guides for the agent

The `omarchy` skill loads topic guides on demand from the same directory as `SKILL.md`. Tinkero adds one, and the patched `SKILL.md` points at it:

- `host.md` (source: `distro/fedora/skills/host.md`): the host is Fedora; use `omarchy pkg add` first, then `dnf` and `flatpak`, never `pacman`; there is no AUR; PAM is `authselect`-managed and the agent never edits `/etc/pam.d`; SELinux is enforcing, denials are read with `sudo ausearch -m AVC -ts recent`, and the agent never changes SELinux mode, booleans or labels; `/usr/share/omarchy` and `/usr/bin/omarchy-*` are package-owned and are never edited or copied into; recent package changes are `dnf history`; RPM Fusion's `akmod-nvidia` for NVIDIA; `firewall-cmd`, not `ufw`; podman is the container default; the desktop is called Tinkero and is built on the Omarchy tree, whose command names and paths it keeps (4.13); updates are `sudo dnf upgrade` and `mise up`; `tinkero-status` reports maintenance state.

The file name is distro-neutral on purpose (4.10). A `maintenance.md` guide arrives with the advisor in phase 5, not before.

Skills are linked into the harness directories by upstream's loop, run from `tinkero-provision`. At `v4.0.4` that is five directories: `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills`, `~/.hermes/skills` (plus Hermes profiles). Re-running provisioning after a bump links any skill the new tag adds, which is what upstream uses migrations for.

### 4.6 Install flow and config lifecycle

**`install.sh`** is the single entry point. It is fetched from a **tagged release URL**, not a branch, and is run as the desktop user, never as root.

1. *Preflight* (no changes): Fedora release equals `fedora=` in the lock; x86_64; GDM is the display manager; SELinux mode is reported; no `hyprland`, `quickshell` or `omedora*` package from another repository is installed; not running as root. Any failure stops with an explanation.
2. *Plan*: print exactly what will happen (repository enabled, packages installed, what provisioning would write) and ask for confirmation unless `--yes`.
3. *System stage* (`sudo`): `dnf copr enable <fas-user>/tinkero`, `dnf install tinkero` (whose `%posttrans` runs `tinkero-pam-sync`, 4.8). Nothing else: no RPM Fusion, no versionlock, no Flathub remote.
4. *User stage*: `tinkero-provision`.

Re-running is safe: stage 3 is a no-op when current, stage 4 is idempotent by construction. Log out, pick "Tinkero" at GDM.

**`tinkero-provision`** is the only thing that writes to a home directory. It replaces upstream's `omarchy-provision-user` and `omarchy-provision-first-run`, whose unmodified behaviour on an existing Fedora account would repoint XDG directories, change the default browser and mail handler, write GNOME's dconf keys and create an unencrypted default keyring (audit, section 6). Upstream's autostart still calls `omarchy-provision-first-run` at every session start; Tinkero's replacement runs `tinkero-provision --session`, which is a fast no-op for provisioning once done and, on every session start, starts the session-scoped user units: the five kept upstream ones (`omarchy-crash-watch`, `omarchy-sleep-lock`, `omarchy-recover-internal-monitor`, `omarchy-fcitx5`, `bt-agent`) and Tinkero's `tinkero-inhibit-power-key.service` (4.2). None has an `[Install]` section: all are `PartOf=graphical-session.target`, which GNOME activates too, so they are only ever started from inside the Tinkero session (4.9).

Seeding rules:

- Source is `/usr/share/omarchy/config/**` plus Tinkero's own overrides in `/usr/share/tinkero/config/**` (notably `hypr/bindings.lua`, which re-adds the two host-neutral bindings that sit inside upstream's gate: tmux on `Super+Alt+Return` and herdr on `Super+Ctrl+Return`. Not re-added: the Docker TUI on `Super+Shift+D` (Docker is deferred with its whole script family, not Arch-specific; the audit, section 4.3, says what re-enabling takes) and the `cliamp` music TUI on `Super+Shift+Alt+M` (`cliamp` is an Omarchy-repo package that Tinkero does not build). Terminal, browser, file manager and editor are declared outside the gate upstream and need nothing).
- The gate itself is closed with upstream's own switch, not a forked config file: `tinkero-provision` creates `~/.local/state/omarchy/preinstalls-removed`, the marker `o.preinstalled_bindings_enabled()` checks (`default/hypr/helpers.lua:84-89`). Its only other readers are the two `preinstalls` menu rows, which are deleted.
- **Per file, never overwrite.** A target that exists is left alone and reported as a conflict with a diff command. `--plan` prints the full list without writing; `install.sh` shows it in step 2.
- Every file written is recorded in `~/.local/state/tinkero/seeded.tsv` with its sha256 and the tag it came from.
- The Tinkero dconf database is seeded once from the user's GNOME settings (4.9).
- `~/.bashrc` is never replaced. With consent, one guarded line is appended: source `/usr/share/omarchy/default/bash/rc` only when `XDG_SESSION_DESKTOP` is `Hyprland`, so terminals in GNOME are unchanged. Hyprland sets that variable for everything it spawns (`default/hypr/envs.lua:22`), which covers every terminal opened from a keybinding or the menu; a shell started by a D-Bus-activated or systemd user service would not see it, and simply gets stock bash.
- Steps adapted from upstream because they are commands rather than file copies: `install/user/git.sh` (global git aliases and identity) runs only when the user has no git config at all; `install/user/xcompose.sh` only when `~/.XCompose` is absent; `omarchy-refresh-applications` copies only the TUI launchers into `~/.local/share/applications`, not the web-app launchers, which would show up in GNOME's overview.
- Steps kept from upstream: skill links, first theme set, mise stubs, `~/Work`, the self-detecting hardware fixes, speaker tuning, and a first-session notification "Set your default agent". Steps dropped: XDG directory changes, GTK bookmarks, default browser and mail handler, the default keyring, the Chromium helpers, web-app launchers, the `post-update` hooks (they would never fire), the Wi-Fi/update toast.

After a tree bump, `tinkero-provision` (run by the user, or on the next session start) uses `seeded.tsv` for a three-way decision per file: unchanged by the user and changed upstream, update it and record the new hash; changed by the user, leave it and report that the packaged default moved; new upstream file, seed it; **deleted by the user** (recorded in `seeded.tsv`, missing on disk), leave it deleted and keep the row marked `removed-by-user` so it is never reseeded; **removed upstream**, delete the target only if its hash still matches the recorded one, otherwise leave it and report it as orphaned. It also prints any notes in `/usr/share/tinkero/config-notes/<tag>.md`, which the packager writes during the bump from upstream's config-only migrations (audit, section 10). This is the replacement for migrations: user state is versioned against the tree.

`tinkero-provision --reset <path>` restores one packaged default with a timestamped backup and clears any `removed-by-user` mark; `--reset-all` does so for every seeded path and is what `omarchy-reinstall-configs` calls. `tinkero-provision --remove` undoes provisioning (4.11).

### 4.7 Maintenance model

On every machine: `sudo dnf upgrade` and `mise up`. Nothing else, ever. The menu's Update entry runs exactly that.

For the packager:

- **When wanted (monthly or less): bump the tree.** Follow the bump checklist in the audit, section 10: re-run the coupling greps on the new tag, diff the provisioning chain, the roster and the menu ids, classify new migrations into config notes, rebase the eleven patches, set the new Hyprland and Quickshell pins in `upstream.lock`, bump `tinkero_rev`. CI (section 8) must pass, including the VM smoke test, before the COPR build is tagged for release.
- **When Fedora's Qt minor version changes:** rebuild Quickshell (4.1).
- **Twice a year: Fedora major upgrade.** Add the new chroot to the COPR and get green builds before upgrading any machine.

**`tinkero-status`** (v1: a command the user or an agent runs; no timer) prints a plain report and supports `--json` (with a top-level `schema` integer, so a later consumer can detect changes):

- installed `tinkero`, `hyprland`, `quickshell` versions against `/usr/share/tinkero/upstream.lock`, and whether `dnf upgrade` is currently holding anything back (the visible symptom of a pending Quickshell rebuild);
- newest upstream Omarchy tag versus the pinned one. It reports the tag name and date only. Upstream's tree carries no Hyprland version requirement, so none is claimed; the heuristic signal, "upstream's packaging repo built against Hyprland X at that date", is labelled as a heuristic;
- whether the COPR has a chroot for the next Fedora release;
- `rpm -V tinkero`, and whether the installed lock-screen PAM file is the variant the current authselect profile calls for (4.8);
- provisioning state: conflicts, moved defaults, unread config notes;
- SELinux denials in the last seven days, only when run with `sudo`; without it, the report says the check was skipped rather than implying zero.

Exit status: 0 nothing to do, 1 something actionable, 2 check failed (for example, no network). Everything it emits is locally generated facts; it never relays text fetched from the network (section 5).

**GitHub Actions, weekly:** check upstream tags and open an issue when a new release appears; compare Fedora's current `qt6-qtbase` version with the one the COPR's Quickshell was built against and trigger a COPR rebuild when they differ (this one needs a COPR API token as a repository secret); run the CI gates against the current lock.

### 4.8 Lock screen authentication

The v4 lock screen is Quickshell's `WlSessionLock` authenticating through the PAM service `omarchy-lock-password`.

Requirements for `/etc/pam.d/omarchy-lock-password`:

- Authentication goes through the host's authselect-managed stack, so that sssd, systemd-homed and the rest apply to the lock screen too. The file to include is **`password-auth`, not `system-auth`**: Fedora's `system-auth` contains `pam_fprintd.so` when `with-fingerprint` is enabled, which would make the *password* service wait for a finger first, while `password-auth` is the same stack without it (it is what GDM's own password service uses). Upstream keeps fingerprint in a separate service, and so does Tinkero.
- **Brute-force lockout is kept regardless of the authselect profile.** Upstream's file stacks `pam_faillock` unconditionally (`deny=10 unlock_time=120`); stock Fedora Workstation (profile `local`) does not enable `with-faillock`, so delegating everything to `password-auth` would silently drop the lockout.
- **A failure is counted once.** When `with-faillock` is enabled, `password-auth` already contains `pam_faillock.so preauth` and `authfail` as plain `required` lines, followed by `pam_deny.so required`. `required` never jumps, so after a failed password the included stack falls through into whatever follows the `include`. An outer `authfail` line would therefore count every failure twice on those hosts. PAM has no conditional include, so one static file cannot satisfy both this requirement and the previous one.

Design: the RPM ships two variants under `/usr/share/tinkero/pam/` and owns `/etc/pam.d/omarchy-lock-password` as a `%ghost %config` file. `tinkero-pam-sync` (root; run from `%posttrans` and from `install.sh`'s system stage; idempotent) copies the variant that matches `authselect current`:

```
# variant "wrapped": host WITHOUT with-faillock
auth     required       pam_faillock.so preauth silent deny=10 unlock_time=120
auth     include        password-auth
auth     [default=die]  pam_faillock.so authfail deny=10 unlock_time=120
account  required       pam_faillock.so
account  include        password-auth

# variant "plain": host WITH with-faillock (password-auth already does it)
auth     include        password-auth
account  include        password-auth
```

In the wrapped variant, a correct password ends the stack at `pam_unix.so sufficient` inside the include, before `authfail`; a wrong one falls through `pam_deny.so required` to the outer `authfail`, which records it once. If the user later toggles `with-faillock`, the installed variant no longer matches: enabling it leaves the wrapped file double counting (fails safe: lockout comes sooner, and how much sooner depends on the host's own `deny=` in `/etc/security/faillock.conf`, whose default of 3 is far stricter than the wrapper's 10); disabling it leaves the plain file with no lockout (fails open). `tinkero-status` therefore compares the installed file with the variant the current profile calls for and reports a mismatch as actionable, with `sudo tinkero-pam-sync` as the fix. The ghost entry is `%attr(0644,root,root)`; removal of the RPM removes the file. Phase 0 validates both variants on a real host, including the lockout count.

The fingerprint variant, `/etc/pam.d/omarchy-lock-fingerprint`, is the one dynamic file: the patched `omarchy-apply-lock` writes it only when `fprintd-list` shows enrolments for the target user (upstream's `SUDO_USER`/`PKEXEC_UID` logic) and removes it otherwise. It runs only from the fingerprint setup and removal commands, on the user's request.

This is the least-proven part of the design: an unprivileged Wayland client authenticating through PAM under SELinux's targeted policy. Phase 0 exists largely to test it. If it cannot work without policy changes, the fallback is packaging `hyprlock` (which the research found only in the older `solopasha/hyprland` COPR, so it is one more spec to own) and binding lock to it; that decision is taken at the end of Phase 0, not during Phase 2.

### 4.9 Coexistence with GNOME

**Invariant: installing, using and removing Tinkero leaves the user's GNOME session unchanged.** It is what makes "log into GNOME" a real recovery path, and section 8 tests it.

- Session environment lives in uwsm's `env.d`, never in dotfiles. The one `~/.bashrc` line is guarded by session.
- Provisioning does not touch XDG user directories, default applications, the keyring, GTK bookmarks or dconf.
- **The Tinkero session uses its own dconf database.** Phase 0 showed that the session writes more `org.gnome.desktop.interface` keys than the theme switcher's three: the shell sets `cursor-theme` during Hyprland start-up and `omarchy-display-text-size` sets `text-scaling-factor`, and a save-at-session-start snapshot lost the race with the cursor change every time. Saving and restoring a list of keys guards only the keys someone thought of, at a moment that is already too late. So the session does not share GNOME's database at all: the RPM installs the dconf profile `/etc/dconf/profile/tinkero` as `%config` (`user-db:tinkero`, then the same `system-db:` lines as Fedora's `user` profile: `local`, `site`, `distro`, so system-wide settings still apply), uwsm's `env.d` exports `DCONF_PROFILE=tinkero` (dconf(7) reads that variable and looks the name up under `/etc/dconf/profile/`), and every gsettings read and write inside the session, by GTK, the portal, the shell's scripts and the theme switcher, goes to `~/.config/dconf/tinkero`. GNOME's `~/.config/dconf/user` is never opened. `tinkero-provision` seeds the Tinkero database once from the user's GNOME settings (`dconf dump /` in GNOME, loaded under `DCONF_PROFILE=tinkero`), so the first Tinkero session starts from the user's own preferences, and `--reset dconf` reseeds it. Removal deletes the file. Two known limits: application settings kept in dconf (Nautilus view preferences, for example) are separate per session from then on, which is the point; and a user service that was already running with GNOME's environment (only possible without a full logout in between) keeps reading GNOME's database until it restarts.
- The unit-based save/restore that Phase 0 prototyped is the **fallback** if the profile approach fails its check in Phase 2F: `tinkero-gnome-restore.service`, started from `tinkero-provision --session`, `PartOf=graphical-session.target`, restoring on `ExecStop`. Phase 0 found that `ExecStop` fired on all three ways of ending the session, including a killed compositor, so the `/etc/xdg/autostart` entry of revision 2 is dropped; and that the baseline would have to be captured at GNOME login, not at Tinkero start.
- **Upstream's user units are session-scoped, not enabled.** Upstream ships them `WantedBy=graphical-session.target`, which GNOME activates too; Phase 0 saw `omarchy-fcitx5` crash-loop under a plain GNOME login and `omarchy-crash-watch` report GNOME's own IBus service. The build strips the `[Install]` section from every unit it ships (4.2), nothing is enabled, and `tinkero-provision --session` starts the five kept upstream units and Tinkero's own two at Tinkero session start; `PartOf=graphical-session.target` stops them at its end. A drop-in for `omarchy-fcitx5.service` adds `ConditionPathExists=/usr/bin/fcitx5` and `StartLimitIntervalSec=60`/`StartLimitBurst=5`, so a missing binary is a quiet condition failure instead of the 188-restart notification storm Phase 0 measured.
- Documented exception: theme sync into VS Code, Obsidian and the browser edits those applications' own settings, which are visible from GNOME because they are the same applications. That is the feature; upstream's skip toggles are the opt-out, and the README lists them.

### 4.10 The distro seam

Everything Fedora-specific lives under `distro/fedora/`: the RPM specs, the replacement scripts that call `rpm`, `dnf`, `firewall-cmd` or `authselect`, `tinkero-pam-sync`, `pkgmap.tsv`, the PAM variants, and `skills/host.md`. Everything else in the repo (patches, menu overrides, `tinkero-provision`, `tinkero-status`'s framework, CI gates) is host-neutral. Revision 1 claimed that for another distro "only the package substrate changes"; that was wrong, since the replacements, the name map, PAM and the host guide all change too. The directory boundary is the honest version of the claim, and it costs nothing now. No other distro work happens before Phase 4.

### 4.11 Removal and rollback

**Rollback of a bad update:** log into GNOME (4.9), then `sudo dnf downgrade tinkero hyprland quickshell` (primary; it does not depend on what else was installed since), or `sudo dnf history undo <id>` for the specific transaction. The old RPMs come from the **release archive**, not from the COPR: the release process (Phase 3's workflow) downloads the RPM set of every tagged release from the COPR and attaches it to the matching GitHub release, so `tinkero-status` can print a `dnf downgrade` command that points at those files, and a rollback works even after COPR has pruned the build. Within COPR's retention window plain `dnf downgrade` works too. The tree and its pins move together (4.2), so there is no half-upgraded state.

**After a crash:** Hyprland starts its next session in Safe Mode (an autogenerated config, the user's Lua not loaded; `Super+M` leaves it). Phase 0 saw this after a killed compositor. The README and `host.md` say so, because a user who lands there otherwise concludes the desktop is broken.

**Removal:** `tinkero-provision --remove` (deletes the session's dconf database; stops the session units; removes skill links that point into `/usr/share/omarchy`, the guarded `~/.bashrc` line, and seeded files whose hash still matches `seeded.tsv`; lists, without deleting, files the user has modified and the mise stubs), then `sudo dnf remove tinkero` and `sudo dnf copr remove <fas-user>/tinkero`. Nothing else was changed on the host, so nothing else needs undoing.

### 4.12 `upstream.lock`

The single source of truth for what is vendored and what it needs. Format: shell-sourceable `key=value`, comments with `#`, no quoting, no expansion. Parsed by `.copr/Makefile`, `install.sh`, `tinkero-status` and the workflows. Shipped to `/usr/share/tinkero/upstream.lock`.

```
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
# omarchy_sha256 is added by `make lock` when the tarball is first fetched
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
quickshell_commit=28771c7c74b42e20afca0b1b63980cb46515537c
fedora=44
tinkero_rev=1
```

- `omarchy_commit` and `omarchy_sha256` exist because tags are mutable; the SRPM build fails if either does not match.
- `hyprland` sets the lower bound and, through its minor version, the upper bound of the RPM requirement. The `Version:` in `distro/fedora/specs/hyprland.spec` is independent and may be newer within the same minor; CI fails if the COPR's Hyprland does not satisfy the lock.
- `fedora` is the release `install.sh` accepts. On any other release it stops and points at `tinkero-status`.
- `tinkero_rev` increments whenever patches, replacements or menu overrides change without a tag change.

### 4.13 Branding

**Decision (2026-09-17): nothing a user sees says or shows Omarchy.** Tinkero presents its own name and mark. This also settles most of the trademark question: MIT licenses the code, not Omarchy's name and logo, so Tinkero does not display them.

The line is drawn between what is *seen* and what is an *identifier*:

- **Rebranded (seen in the graphical session):** the logo glyph, the ASCII and image logos, the wordmark wallpaper each theme ships, the About screen, the screensaver, the installer presentation screens, menu labels, keybinding descriptions in the `Super+K` cheat sheet, notifications, tooltips, the GDM session name.
- **Kept (identifiers):** the `omarchy-*` command names and the `omarchy` CLI, `~/.config/omarchy` and `~/.local/state/omarchy`, `OMARCHY_PATH` and `/usr/share/omarchy`, plugin ids (`omarchy.bar` and so on), the `omarchy` skill's name, the PAM service names, window classes (`org.omarchy.*`). Renaming these would mean patching several hundred files on every bump, would break every upstream plugin, theme and piece of documentation a user might follow, and is exactly the reimplementation this design rejects. `--help` text printed by those commands also stays as upstream in v1.

At `v4.0.4` the seen surface is small and almost entirely data (audit, section 11). It is handled by build-time file replacement, one generated set of images and a short substitution list. Those do change upstream bytes, but none is a diff with a position in a file, so none carries a rebase cost, and each fails loudly when upstream moves:

| Surface | Upstream source | Tinkero handling |
|---|---|---|
| Logo in the bar's menu button and beside menu rows | glyph `U+E900` in `default/fonts/omarchy/omarchy.ttf` (`shell/plugins/menu/BarWidget.qml`, menu JSONC) | the font is rebuilt at RPM build time with the Tinkero mark in `U+E900`; every other glyph (the agent logos) is untouched, and no QML or JSONC changes |
| About screen, screensaver, floating-terminal presentation screens | `icon.txt`, `logo.txt` (copied to `~/.config/omarchy/branding/about.txt` and `screensaver.txt`; upstream already treats these as user-replaceable branding) | replaced by Tinkero's files at build time; `tinkero-provision` seeds the branding directory from them |
| Image logos | `logo.svg`, `icon.png` | replaced |
| **Theme wallpapers** | 18 of the 22 themes ship `backgrounds/omarchy.png`: the OMARCHY wordmark in the theme's accent colour on its flat background colour, one entry in each theme's wallpaper rotation. At least six more of the 92 shipped wallpapers carry the wordmark, an upstream house mark or release artwork, in illustrated form or under other names (audit, section 11) | the 18 flat ones are regenerated at build time as `backgrounds/tinkero.png` from the Tinkero wordmark and each theme's own `colors.toml` (`branding/render-wallpapers`, ImageMagick), so no per-theme artwork is needed. Illustrated ones cannot be regenerated and are deleted. Every shipped wallpaper has a row in `branding/images.tsv` (path, sha256, verdict: keep, regenerate or delete) filled in by a person looking at the image; the build fails on a wallpaper with no row, which is how a new upstream image gets looked at |
| About screen's OS line | `etc/fastfetch/config.jsonc:74` prints "Omarchy <version>" | the relocated config (4.2) is on the substitution list |
| Plugin metadata | `"author": "Omarchy"` in 28 `shell/plugins/**/manifest.json`, and the menu plugin's `name`, `displayName` and `description` | rewritten by a small JSON transform (`branding/rewrite-manifests`), not by 28 rows: author becomes "Tinkero (from Omarchy)", the menu plugin's strings say Tinkero. Plugin **ids** are identifiers and do not change |
| Menu | `learn.omarchy` (opens the Omarchy manual as a web app), `update.omarchy` | the first is replaced by a `learn.tinkero` row that opens Tinkero's README in the default browser; the second is already replaced (4.4) |
| Cheat sheet | two `"Omarchy menu"` binding descriptions in `default/hypr/bindings/utilities.lua` | substitution list: becomes "Tinkero menu" |
| Notifications and tooltips | the welcome toast ("Super + Space for Omarchy Menu"), `SystemUpdate.qml`'s tooltip, the plugin registry's "reserved for first-party Omarchy plugins" message | welcome toast is Tinkero's own (4.6); the other two are on the substitution list |
| Session name at GDM | `Name=Omarchy (Hyprland uwsm)` | Tinkero ships its own session file (4.2) |

The substitution list is `branding/strings.tsv` (file, exact upstream string, replacement, expected count), applied with a fixed-string replace during `%install`. **Each row must match exactly its expected count or the build fails** (the count is 1 except where upstream repeats a string, as with the two identical `"Omarchy menu"` descriptions in `utilities.lua`), so an upstream rewording is caught at the bump instead of silently shipping the old name. The branding gate in section 8 covers what a substitution list cannot know about: it greps the payload's QML, JS, Lua, JSON, JSONC and `.desktop` files for the capitalised word inside string literals and fails on anything outside an allowlist (the dev gallery and its window rule, and a title-matching window rule in `default/hypr/apps/system.lua`), and it fails if any file named `*omarchy*` remains under a theme's `backgrounds/`, if a wallpaper in the payload has no row in `branding/images.tsv`, or if one marked delete or regenerate is still present. The font rebuild needs `python3-fonttools` and the wallpapers need `ImageMagick` as `BuildRequires`; both are in Fedora.

**Attribution stays, prominently and deliberately.** The MIT license requires keeping Omarchy's copyright and license text, which ships in `/usr/share/licenses/tinkero/`. Beyond the legal minimum, the README and the About screen say "built on Omarchy" with a link: rebranding the surface is about not presenting someone else's marks as one's own product, not about hiding where the work comes from. `host.md` (4.5) tells the agent the same thing in one paragraph (this desktop is Tinkero; it is built on the Omarchy tree; the commands and paths keep Omarchy's names; say "Tinkero" when talking about the desktop and use the real command names when giving instructions).

Prerequisite that does not exist yet: a Tinkero mark (a monochrome glyph for the font, an SVG wordmark that the wallpapers are rendered from, and ASCII renderings at the two sizes upstream uses). Until it exists, the build uses a plain "T" placeholder glyph and a text wordmark, which is enough for every milestone.

## 5. Security and privacy

**Accepted risk, stated.** Omarchy launches agents in each harness's "do not ask" mode (`--permission-mode auto`, `--yolo`, `--dangerously-skip-permissions` and so on), and Tinkero keeps that: it is goal 3. An agent started this way can do anything the user can. The mitigations are upstream's (agents start in `~/Work`, not `$HOME`; the skill forbids touching package-owned paths and requires confirmation before resets) plus the rules below.

1. **No untrusted text reaches an unattended agent.** Nothing Tinkero builds passes content fetched from the network (release notes, issue text, tag messages) into an agent prompt. `tinkero-status` emits locally computed facts only. This is why the revision 1 advisor (a weekly timer whose notification launches the agent) is not in v1; section 7 sets the conditions for bringing it back.
2. **Supply chain.** The upstream tarball is pinned by commit and sha256. Every bump is reviewed as the upstream diff between the two tags, with the provisioning chain, installers and anything using `sudo`/`pkexec` read in full; the CI gates cover the mechanical part. The COPR signs its packages. `install.sh` is fetched from a tagged release, shows its plan and asks before acting.
3. **Privilege boundary.** Tinkero adds no setuid files, no polkit rules, no sudoers entries and no system services. Root-owned content is what the RPM installs. The user units run as the user.
4. **SELinux stays enforcing, policy stays stock.** No policy module, no booleans, no permissive domains, no `restorecon` choreography (RPM labels its own files). If a feature cannot work under the targeted policy, the feature is redesigned or dropped (4.8).
5. **Keyring.** Upstream's passwordless default keyring is not created. GDM's PAM stack unlocks the login keyring as on stock Fedora.
6. **No data leaves the machine on Tinkero's account.** `omarchy-upload-log` is dropped. Two upstream features do talk to third parties by design and are left as upstream: the agent usage collectors read the user's own agent credentials and transcripts (for example under `~/.claude`) to query the provider's usage endpoint, and voxtype records the microphone and downloads a speech model when the user installs it. The README states both.
7. **Third-party plugins** run unsandboxed inside the shell process, which also hosts the lock screen and the polkit agent. Upstream's `omarchy plugin add` requires explicit confirmation and never executes code on add; Tinkero keeps that and `host.md` repeats the warning to the agent.

## 6. Dependency manifest

This table is the `Requires:`/`Recommends:` list of `tinkero.spec`. "COPR" means the Tinkero COPR.

| Feature | Hard requires | Source |
|---|---|---|
| Compositor and session | `hyprland` (pinned), `uwsm`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk`, `hyprland-guiutils`, `hyprsunset`, `hyprpicker`, `lua` | COPR; Fedora for the gtk portal and lua |
| Shell | `quickshell` (pinned), `qt6-qtwayland`, `qt6-qtmultimedia`, `qt6-qtimageformats`, `qt6-qtsvg`, `gtk4-layer-shell`, Nerd-patched JetBrains Mono (COPR package `tinkero-nerd-fonts`), `fontawesome-fonts-all`, `yaru-icon-theme` | COPR for quickshell and the font; Fedora |
| Session services | `polkit`, `gnome-keyring`, `pipewire`, `wireplumber`, `pipewire-pulseaudio`, `pamixer`, `brightnessctl`, `ppd-service` (the virtual provide; Fedora 44 Workstation ships `tuned-ppd`, and requiring `power-profiles-daemon` by name would erase it), `bluez`, `NetworkManager`, `udiskie`, `socat`, `inotify-tools`, `jq`, `gum`, `git-core` | Fedora |
| Input method | `fcitx5` (the kept `omarchy-fcitx5` unit runs it; Phase 0 found it missing and the unit crash-looping) | Fedora |
| Terminal | `foot`, `xdg-terminal-exec`, `tmux`, `herdr` | Fedora; COPR for herdr |
| Capture | `grim`, `slurp`, `wl-clipboard`, `wtype`, `tensaku`, `hyprland-preview-share-picker` | Fedora; COPR for the last two |
| Agent layer | `mise` | COPR |
| Screensaver | `ttfx` | COPR |

| Weak (`Recommends:`) | Why weak |
|---|---|
| `gpu-screen-recorder`, `tesseract`, `tesseract-langpack-eng`, `zbar`, `qrencode` | screen recording, OCR and QR are features, not the desktop |
| `voxtype` | dictation; heavy, and installs a model on first use |
| `nautilus`, `nautilus-python`, `sushi`, `imv`, `mpv` | file manager and viewers; GNOME hosts already have most |
| `fcitx5-gtk`, `fcitx5-qt` | input-method integration for GTK and Qt applications |
| `ddcutil`, `plocate`, `btop`, `fzf`, `ripgrep`, `bat`, `eza`, `fd-find`, `zoxide`, `neovim` | external-monitor brightness and the shell ergonomics upstream's bash config expects; each degrades gracefully |

Phase 0 also found that the `omedora-4` COPR packages recommend `nwg-panel`, `wofi`, `playerctl` and `newt`, a second bar and launcher; the forked specs in Phase 1 drop those `Recommends:`. `install.sh` does not disable weak dependencies globally, because Tinkero's own `Recommends:` above are wanted.

Not required: `alacritty`, `kitty` (installable from the menu), any browser (the browser binding uses the XDG default, Firefox on stock Fedora), `chromium`, `sddm`, `plymouth` themes, `snapper`, `satty`, and the v3-era `waybar`, `mako`, `swaybg`, `wofi`, `cliphist`, which the v4 shell replaced. Through mise, not RPM: the agent CLIs, and optionally `starship`, `lazygit`, `lazydocker`.

## 7. Phases

- **Phase 0, spike: done 2026-09-21, GO** (`docs/research/phase-0-findings.md`). Original scope: Fedora 44 Workstation, the existing `agaspar/omedora-4` COPR, the `v4.0.4` tree assembled by hand following the research doc's section 4.4 with the audit's drop list applied. Goal: reach Milestones A and B by hand and answer, with evidence, the questions a reading cannot: does the lock screen authenticate under SELinux, and does each PAM variant lock out after ten failures, counting each failure once, on a host without and with `with-faillock` (4.8); are there AVC denials after a session; does GDM start the uwsm session cleanly; does the GNOME invariant hold with the 4.9 mechanism, and how often does the logout-time restore actually win its race; is the power-key inhibitor granted to an unprivileged session unit (4.2). The step-by-step procedure is `docs/guides/phase-0-spike.md`. Output: a short findings note, and a go/no-go on forking the specs. Runs in parallel with FAS and COPR account setup.
- **Phase 1, packages.** Create the COPR (default retention; see 4.1); fork the specs listed in 4.1; green builds for fedora-44-x86_64. Milestone: `dnf install hyprland quickshell uwsm mise herdr` from the Tinkero COPR on a clean Fedora 44.
- **Phase 2, the tree.** `.copr/Makefile`, `tinkero.spec.in`, patches, replacements, `pkgmap.tsv`, menu rewrite, PAM file, session file, `tinkero-provision`, `install.sh`, and the four CI gates plus lint (section 8), which are built first because they define done for everything else. Milestones A, B and C (section 8).
- **Phase 2F (session integration) additionally checks, in the same VM:** that `DCONF_PROFILE=tinkero` isolates every key the session writes (repeat the Phase 0 cycle with `cursor-theme` and `text-scaling-factor` in the diff), and that the stripped-`[Install]` units no longer start under GNOME.
- **Phase 3, maintenance.** `tinkero-status`, the weekly workflow (upstream watch, Qt watch and rebuild trigger), the VM smoke test in CI, the bump checklist exercised once for real. Milestone D.
- **Phase 4, base for others.** Second-machine install test, README and user documentation, the upstream PR for a system menu extension path, then evaluate a second distro across the `distro/` seam.
- **Bare metal, before Milestone B is signed off:** suspend and resume with the five-second lock margin (a VM cannot enter S3), and the Hyprland Safe Mode entry after a crash (4.11).
- **Phase 5, maintenance advisor (conditional).** The revision 1 idea: a timer runs `tinkero-status` and, when something is actionable, a notification offers to open the default agent with a `maintenance.md` guide. Preconditions: Phase 3 has run for a quarter; the agent's input is `tinkero-status --json` and nothing else; `maintenance.md` contains an explicit table of what the agent may do unattended (run `mise up`, report) versus what needs the human (anything with `sudo`, any lock bump, anything under `/etc`); the unit only fires inside a Tinkero session.

Revision 1 numbered its phases from 2 because an earlier "phase 1" (agent layer under GNOME first, the research's suggested sequence) was skipped; the numbering above replaces it.

## 8. Testing and acceptance

**CI on every push and on every lock bump:**

1. **Arch-leak gate.** Build the RPM in mock; grep the installed payload with the audit's tier 1 pattern; any match outside the allowlist fails.
2. **Dropped-reference gate.** Nothing in the payload still names a command that `build/drop.list` removed. (The broader check, "every `omarchy-*` token resolves to a file", was tried first and reports 110 false positives on the untouched upstream tree: PAM service names, CSS ids, window classes, unit names. The narrower question has none, and it is the one that matters.) Like the arch-leak gate, it compares its findings with a checked-in allowlist that may only shrink.
3. **Name-map gate.** Every literal package name reaching a package wrapper or menu guard has a row in `pkgmap.tsv`.
4. **Single-copy gate.** `/usr/share/omarchy/bin` contains only symlinks into `/usr/bin`.
4a. **Branding gate.** No capitalised "Omarchy" inside a string literal in the payload's QML, JS, Lua, JSON, JSONC or `.desktop` files outside the allowlist; no `*omarchy*` file under a theme's `backgrounds/`, and every wallpaper in the payload has a keep row in `branding/images.tsv`; every row of `branding/strings.tsv` matched its expected count during the build (4.13).
5. **Lint.** `shellcheck` on Tinkero's scripts, `rpmlint` and `rpmspec --parse` on the specs, a JSONC parse of the built menu, and a lock check (COPR's Hyprland and Quickshell satisfy `upstream.lock`).
6. **VM smoke test** (Phase 3; manual before then). Fedora 44 image: run `install.sh --yes`, provision a fresh user and a user with pre-existing dotfiles, start the session headless, assert `hyprctl configerrors` is empty, `omarchy-shell shell ping` answers, the menu model loads with guards evaluated, zero AVC denials, and a second `install.sh` run changes nothing.

**Milestones** (each is a checklist run on the author's machine or the VM; a milestone passes when every line does):

- **A, agent.** In a Tinkero session: `Super+Shift+Ctrl+A` opens the agent picker, choosing an agent installs it through mise and launches it; the `omarchy` skill and `host.md` are found by the harness; asked to install a package, the agent uses `omarchy pkg add` and it succeeds through dnf.
- **B, desktop.** Nothing on screen says or shows Omarchy (bar button, menu, About including its OS line, screensaver, every theme's wallpaper rotation, cheat sheet, welcome toast, GDM session list), and About credits it. Pressing the power key opens the power menu instead of powering off. Bar, menu (no dead entries; install and remove of one dnf-mapped package round-trips and the guard flips), notifications, lock and unlock with password under SELinux enforcing, idle lock, screenshots with annotation, clipboard history, theme switching; herdr opens on `Super+Ctrl+Return`; voxtype dictates on F9 when installed.
- **C, plugins (goals 2 and 3).** `omarchy plugin clone` of a built-in widget, an edit, and enable works; a third-party plugin installs with `omarchy plugin add`; the default agent, asked in plain language, builds a new bar widget that appears in the bar without touching package-owned paths.
- **GNOME invariant (part of B).** Record `gsettings list-recursively org.gnome.desktop.interface`, `xdg-settings get default-web-browser`, `xdg-user-dir` outputs, the default keyring and `~/.bashrc` before install; after install, a Tinkero session with two theme switches, logout, and a GNOME login, they are identical except for the one guarded `~/.bashrc` line, and `~/.config/dconf/user` has the same checksum. The run is repeated with the Tinkero session ended three ways (menu logout, `loginctl terminate-session`, and a killed compositor). Under GNOME, `systemctl --user list-units 'omarchy-*' 'tinkero-*'` shows nothing active. After removal (4.11) they are identical.
- **D, maintenance.** After a simulated upstream tag, `tinkero-status` exits 1 and names it; after a real bump to the next upstream tag, the bump checklist was followed end to end, CI passed, and `dnf upgrade` on a second machine moved the tree and its pins in one transaction with provisioning reporting moved defaults correctly.

## 9. Risks and mitigations

- **Lock screen PAM under SELinux.** Was the least-proven piece; Phase 0 passed it (Quickshell lock, both PAM variants, zero desktop AVCs), so `hyprlock` is no longer needed as a fallback.
- **Qt updates inside a Fedora release.** Force a Quickshell rebuild; has already happened once in Fedora 44. Mitigation: automatic symbol-version requires hold the upgrade rather than break the shell; the weekly workflow triggers the rebuild (4.1, 4.7). Because bar, notifications, polkit agent and lock screen are one process, a Quickshell crash while locked leaves the session locked until a TTY login; `allow_session_lock_restore` is set upstream, and this is accepted.
- **Hyprland currency.** Omarchy tracks new Hyprland releases within weeks. Mitigation: the pin is an RPM requirement that moves with the tree (4.2); the weekly workflow makes drift visible.
- **Config drift across bumps.** Migrations are gone. Mitigation: `seeded.tsv` three-way logic and config notes (4.6).
- **Upstream adds Arch assumptions.** Mitigation: the CI gates and the bump checklist; the seam is measured, not assumed.
- **Upstream patch conflicts.** Eleven small patches; everything else is a separate file or a build-time transform.
- **Sleep lock margin.** Without upstream's logind override the lock has five seconds, not fifteen, before suspend (4.2). Not measurable in the Phase 0 VM (no S3); measured on bare metal before Milestone B.
- **Pinned launcher versus moving agent CLIs.** `omarchy-agent` hard-codes each harness's unattended flag, and `mise up` moves the CLIs. A renamed flag breaks that agent's launch until the next bump. Accepted; the fix is a bump or a one-line local patch carried in `tinkero_rev`.
- **Fedora major upgrades.** A COPR only serves the releases it was built for. Mitigation: `tinkero-status` warns when the next chroot is missing; owning the specs makes a rebuild hours, not a wait.
- **GNOME contamination.** Phase 0 showed the session writes keys nobody had listed and that a snapshot at session start is already too late. Mitigation: a separate dconf database for the session (4.9), which contains every key by construction; the unit-based restore is the fallback; the test ends the session three different ways.
- **Lockout on the lock screen.** Delegating PAM wholly to the host stack loses upstream's faillock on a stock Fedora; wrapping it double counts where `with-faillock` is on. Mitigation: two variants chosen by `tinkero-pam-sync`, a drift check in `tinkero-status`, both validated in Phase 0 (4.8).
- **Packager cost and bus factor of one.** Roughly 25 specs, including CVE response for the Hyprland stack. Mitigation: the budget and exit criterion in 1.1; the exit is clean because removal is clean.
- **Single upstream.** If Omarchy changes direction, the pinned tree keeps working; the risk is losing new features, not the desktop.

Nothing here can prevent the machine from booting or logging in: GDM, GRUB, the kernel, PAM's `system-auth` and GNOME are untouched. The realistic worst case is a locked or broken Tinkero session, recovered from a TTY or by logging into GNOME.

## 10. Open questions

1. COPR project name and FAS username (a task for the author, blocking Phase 1 only).
2. **The Tinkero mark.** Branding is decided (4.13: no visible Omarchy name or logo; identifiers keep upstream's names; attribution stays). What is missing is the artwork: a monochrome glyph, an SVG and two ASCII renderings. A placeholder is used until then. A courtesy note to upstream about the project is still worth sending before the repo is promoted, but it no longer blocks anything.
3. **Confirm the maintenance budget and exit criterion** in 1.1; the numbers are a proposal.
4. Lock screen mechanism: decided by Phase 0, Quickshell lock with the two PAM variants (4.8).
5. Which of the hidden installers return first after v1, and whether through dnf, Flathub or upstream repositories (Signal and Spotify are the obvious candidates).
6. Repository default branch: rename `master` to `main` or not.

## 11. Decision log

Decisions from the 2026-09-16 and 2026-09-17 research session, then revision 2 (marked R2), made after the spec review and the upstream audit.

| Decision | Choice | Why |
|---|---|---|
| Base OS | Keep Fedora and Red Hat conventions; no Arch parts | Author's preference; SELinux, point releases, dnf |
| Approach | Vendor the real Omarchy tree at a pinned tag, patch the seams | Reimplementations go stale; upstream releases weekly |
| Overriding the research's "do not port" | Proceed, with a measured seam, a budget and an exit criterion (R2) | 1.1 |
| Delivery level | Mutable Fedora Workstation, own COPR, `tinkero` RPM | `dnf install` must keep working; bootc rejected for now |
| Display manager | Keep GDM, do not install SDDM | GDM handles the login keyring; avoids PAM friction |
| Scope | Desktop core: Hyprland, shell, themes, capture, agent harness, herdr, voxtype | The three priorities plus the look; skip Omarchy's app catalogue |
| Agent CLIs | mise, not RPM | Distro-neutral, self-updating with `mise up`, same as upstream |
| herdr and mise | Packaged in the COPR (R2) | Core features; upstream ships herdr as a package at the pinned tag; keeps both under `dnf upgrade` |
| Package specs | Fork from `agaspar/omedora-4` into an owned COPR, after a Phase 0 spike on omedora-4 itself (R2) | Proven builds; not blocked by a one-person beta; prove the desktop before owning 25 specs |
| Updates | `dnf upgrade` + `mise up`; tree bumps deliberate via `upstream.lock` | Low-maintenance requirement |
| Version pinning | RPM `Requires` generated from `upstream.lock`; no `dnf versionlock` (R2) | Tree and compositor move in one transaction; no per-machine state; versionlock would hold Hyprland back while upgrading the tree |
| COPR retention | Cannot be disabled by a non-admin (R2.1, found 2026-09-22); each release's RPM set is attached to its GitHub release and `tinkero-status` prints the downgrade command against it | Downgrade is the rollback path and must not depend on COPR's pruning |
| Menu customization | Build-time rewrite of the default JSONC (R2) | No system extension path upstream; merges cannot delete; hidden submenus leak through search |
| Provisioning | Replace `omarchy-provision-user` and `-first-run` with `tinkero-provision`; no `/etc/skel` (R2) | Upstream's chain rewrites shared GNOME state and creates an unencrypted keyring; skel is global and misses existing users |
| Config upgrades | Hash-tracked seeding plus packager-written config notes (R2) | Replaces migrations |
| Lock PAM file | RPM-owned `%ghost`, one of two shipped variants chosen by `tinkero-pam-sync` from the authselect profile; includes `password-auth`, not `system-auth` (R2) | Keeps upstream's lockout without double counting; keeps fingerprint out of the password service; clean removal |
| GNOME coexistence | Hard invariant; the session runs on its own dconf database via `DCONF_PROFILE` (R2.1, after Phase 0; was save/restore of three keys) | The session writes keys nobody listed, and a snapshot at session start loses the race; isolation covers every key by construction |
| Upstream user units | `[Install]` stripped at build; started by `tinkero-provision --session`; fcitx5 drop-in with a start limit (R2.1) | Phase 0: units enabled on `graphical-session.target` run under GNOME too; fcitx5 restarted 188 times with a notification each |
| Package elevation | `pkexec` inside a graphical session, `sudo` only without one (R2.1) | Phase 0: the agent cannot answer `sudo` in its own terminal; pkexec goes to the shell's polkit dialog, no sudoers or polkit rules |
| Power profiles | Require the virtual `ppd-service`, not `power-profiles-daemon` (R2.1) | Fedora 44 ships `tuned-ppd`, which conflicts |
| Agent guidance | One distro-neutral `host.md` guide added to the `omarchy` skill (R2: was `fedora.md` plus `maintenance.md`) | Agent must know the host; keeps the distro seam clean |
| Maintenance advisor | Deferred to a conditional Phase 5; `tinkero-status` is a manual command in v1 (R2) | Timer-to-unattended-agent is the riskiest new surface; no fetched text may reach an agent |
| Security posture | No SELinux policy changes, no setuid/polkit/sudoers additions, tarball pinned by commit and sha256, install from a tagged release with a plan prompt (R2) | Section 5 |
| Distro seam | `distro/fedora/` holds everything host-specific (R2) | Makes the cross-distro tagline honest at no cost |
| Architecture and GPU | x86_64 only; NVIDIA documented, not supported; RPM Fusion not enabled by the installer (R2) | Scope; enabling a third-party repo is host policy |
| Repo | Public, `github.com/dromeropa/tinkero`, `~/Projects/tinkero` locally | COPR builds from a public repo; base for others |
| Branding | No visible Omarchy name or logo; glyph, logos, labels and notifications rebranded by build-time replacement and a must-match substitution list; command names, paths and ids keep upstream's names; attribution kept in license files, README and About (R2, author's decision) | The marks are not covered by MIT; renaming identifiers would be a reimplementation |
| License | MIT | Compatible with Omarchy's MIT; author may change |
| Name | Tinkero, tin-KEH-ro | Coined; tinker plus a playful ending; explicitly not an "oma" name |
| Tagline | "a tinkerable desktop for Hyprland, bring your own distro" | Credits Hyprland; states the cross-distro ambition |
| Category | Desktop environment (Hyprland is the compositor) | Same relationship as GNOME to Mutter |
| Sequence | Phase 0 spike, then COPR, then the tree (R2: was "straight to the COPR") | The spike is two days and de-risks the least-proven parts; builds remain the long pole and start right after |

## 12. Repo layout

```
tinkero/
  README.md
  LICENSE                          MIT (compatible with Omarchy's MIT)
  upstream.lock
  install.sh
  .copr/Makefile                   COPR's make_srpm entry: fetch, verify, render the spec, build the SRPM
  tinkero.spec.in
  patches/                         the eleven patches against the pinned tag
  menu/overrides.jsonc             build-time menu edits
  menu/apply-overrides
  branding/                        mark (SVG, glyph source), logo.txt, icon.txt, strings.tsv, images.tsv,
                                   rebuild-font, render-wallpapers, rewrite-manifests
  bin/tinkero-provision
  bin/tinkero-status
  bin/tinkero-update
  config/                          Tinkero's seeded overrides (hypr/bindings.lua, ...)
  config-notes/<tag>.md            per-bump notes shown by tinkero-provision
  systemd/tinkero-gnome-restore.service
  systemd/tinkero-inhibit-power-key.service
  systemd/omarchy-fcitx5.service.d/tinkero.conf
  distro/fedora/dconf/profile/tinkero
  distro/fedora/
    specs/                         the COPR package specs
    replacements/                  Tinkero's own omarchy-* scripts
    pkgmap.tsv
    bin/tinkero-pam-sync           reads `authselect current`, so it is host-specific
    pam/omarchy-lock-password.wrapped
    pam/omarchy-lock-password.plain
    skills/host.md
  ci/                              the four gates, lint, VM smoke test
  .github/workflows/               CI, upstream watch, Qt watch
  docs/research/omarchy-research.md
  docs/research/arch-coupling-audit.md
  docs/spec-review.md
  docs/guides/phase-0-spike.md     the VM spike procedure
  docs/superpowers/specs/          this document
  docs/superpowers/plans/          implementation plans (Phase 2 roadmap, plan 2A)
  dev                              developer entry points (check, lock, payload, gates, baseline, spec)
  build/                           assemble, fetch-upstream, render-spec, drop.list
  tests/                           hermetic shell tests and the fixture tree generator
```

## 13. References

- `docs/research/omarchy-research.md` (sections 1 to 4 are the technical basis; 3.5 covers the existing ports; 4.6 is the recommendation this design overrides, see 1.1).
- `docs/research/arch-coupling-audit.md` (the classified seam at `v4.0.4`; authoritative for every upstream specific in this document).
- `docs/spec-review.md` (the review of revision 1; its finding ids are referenced in commit messages).
- Omarchy: https://github.com/omacom/omarchy (branch `quattro`, tag `v4.0.4`), packaging at https://github.com/omacom/omarchy-pkgs, manual at https://omarchy.org/manual/.
- Omedora and its COPR: https://github.com/AndrewGaspar/omedora, https://copr.fedorainfracloud.org/coprs/agaspar/omedora-4/.
- Hyprland Lua config: https://hypr.land/news/update55/.
- herdr: https://github.com/herdrdev/herdr. voxtype: https://voxtype.io/.
