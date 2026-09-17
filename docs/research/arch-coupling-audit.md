# Arch-coupling audit of Omarchy v4.0.4

Audit date: 2026-09-17. Subject: `omacom/omarchy` tag `v4.0.4`, commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`, read from a shallow clone. Nothing from the tree was executed.

Purpose: size and classify the seam between the distro-neutral Omarchy tree and its Arch substrate, so that the Tinkero spec's patch and replacement tables (design spec §4.3), menu overrides (§4.4) and provisioning (§4.6) are derived rather than asserted. This is the audit called for by finding B3 of `docs/spec-review.md`.

This document describes the **pinned tag**. `docs/research/omarchy-research.md` describes `quattro` HEAD one day later; where the two disagree (script count, agent roster, skill directories, the Claude browser-extension hook), this document wins for anything Tinkero builds against `v4.0.4`.

## 1. Method

Tier 1 pattern, `grep -rlE` over `bin/`, `shell/`, `default/`, `config/`, `install/user/`:

```
pacman|\byay\b|\bparu\b|expac|makepkg|limine|mkinitcpio|snapper|\bufw\b|pkgs\.omarchy\.org|archlinux|checkupdates|paccache|pactree
```

Tier 2 pattern over `bin/` only, for host-policy coupling that is not package tooling:

```
sddm|plymouth|\bdocker\b|/boot/|locale-gen|\bAUR\b
```

Tier 3 pattern over `bin/`, for scripts that write system configuration by hand (added after review, because tiers 1 and 2 missed the security scripts that `sed` PAM files):

```
(sudo|pkexec|as_root)[^|]*(tee|sed -i|install|cp|rm|mv|ln)[^|]* /etc/|/etc/pam\.d|/etc/sudoers
```

Counts for tiers 2 and 3 are given net of files already caught by an earlier tier.

Then: every `omarchy-install-*` script was classified by the installer it calls; the default menu (`default/omarchy/omarchy-menu.jsonc`) was parsed and grouped by id prefix; the first-run and user-provisioning chain was read end to end; and the commands bound in `default/hypr/bindings/*.lua` were cross-checked against everything marked *drop*.

Limits: a grep audit finds named tools, not assumptions (a script that expects `/etc/pacman.d` to exist without naming pacman would be missed). Scripts that only call the `omarchy-pkg-*` wrappers are coupled *through* the wrappers and are correct once the replacement wrappers and the name map are correct; they are counted, not listed. The CI gate in §8 exists to catch what this pass missed and what upstream adds later.

## 2. Verdict vocabulary

| Verdict | Meaning | Cost on a tag bump |
|---|---|---|
| **replace** | Tinkero ships its own script under the same name | none unless upstream changes the script's contract |
| **patch** | Small diff against the upstream file | rebase; this is the number to keep small |
| **drop** | Not installed | none; needs its menu entries and bindings removed too |
| **hide** | Script ships (harmless or unreachable) but its menu entry is removed | none |
| **keep** | Ships unmodified; the hit is a comment, a portable tool, or reachable only through a replaced wrapper | none |

## 3. Totals

| Area | Files | Tier 1 hits | Notes |
|---|---|---|---|
| `bin/` | 444 | 50 | 38 are `omarchy-install-*`; 66 scripts call the `omarchy-pkg-*` wrappers (10 of them are also among the 50) |
| `bin/` tier 2 only | | 19 (34 raw, 15 already in tier 1) | plymouth, sddm, docker, direct boot, Windows VM, the `omarchy` dispatcher |
| `bin/` tier 3 only | | 11 (18 raw, 7 already in tier 1 or 2) | hand edits of `/etc/pam.d`, sudoers, `/etc/supergfxd.conf`, browser policy, `/etc/omarchy.conf` |
| `shell/` | | 1 | `plugins/menu/MenuModel.js` |
| `default/` | | 12 | 5 are Arch-only payload that is not installed |
| `config/` | | 1 | a sample hook |
| `install/user/` | 22 | 0 | coupled indirectly; see §6 |

Resulting patch set (the rebase cost): **11 small patches**, listed in §9. Everything else is replace, drop, hide or keep.

## 4. `bin/` classification

### 4.1 Package plumbing

| Script | Callers in tree | Verdict | Tinkero behaviour |
|---|---|---|---|
| `omarchy-pkg-present` | 6 + menu guards | replace | `rpm -q` through the name map; true only if all named packages resolve and are installed |
| `omarchy-pkg-missing` | 7 + menu guards | replace | mirror of `-present`. **Not in spec rev 1** |
| `omarchy-pkg-add` | 39 | replace | name map, then `dnf install -y` or `flatpak install -y`; unmapped names print the manual instruction and exit 1 |
| `omarchy-pkg-drop` | 20 | replace | name map, then `dnf remove -y` / `flatpak uninstall -y`. **Not in spec rev 1** |
| `omarchy-pkg-install` | 1 (menu) | drop | fuzzy TUI over the Arch repos; menu entry `install.package` removed |
| `omarchy-pkg-remove` | 1 (menu) | drop | fuzzy TUI over pacman's database; menu entry `remove.package` removed. **Not in spec rev 1** |
| `omarchy-pkg-aur-accessible`, `omarchy-pkg-aur-add`, `omarchy-pkg-aur-install` | 1, 2, 1 | replace (stub) | exit 1 with "no AUR on this host"; `-accessible` returns false so callers take their non-AUR branch |
| `omarchy-reinstall-pkgs` | 1 | drop | reinstalls the Arch base list |
| `omarchy-dev-pkg-test` | 1 | drop | builds a pacman package from a checkout |

### 4.2 Update, channel, version

| Script | Verdict | Tinkero behaviour |
|---|---|---|
| `omarchy-update` | replace | prints "Tinkero updates through `dnf upgrade` and `mise up`; see `tinkero-status`", exit 0 |
| `omarchy-update-available` | replace | exit 1 (nothing available), so the bar's update indicator stays off. **Not in spec rev 1** |
| `omarchy-update-system-pkgs`, `-system-pkgs-when-conflicted`, `-aur-pkgs`, `-orphan-pkgs`, `-keyring`, `-pkg-prune`, `-pacman-guard`, `-restart` | drop | only reachable from `omarchy-update` |
| `omarchy-update-confirm`, `-analyze-logs`, `-lock`, `-requires-free-space`, `-status`, `-stay-awake`, `-user-notify`, `-dev` | drop | same; no tier 1 hit but dead without `omarchy-update` |
| `omarchy-update-mise`, `omarchy-update-firmware`, `omarchy-update-time` | keep | `mise up`, `fwupdmgr`, `timedatectl`; portable. Menu entries `update.firmware`, `update.time` stay. `omarchy-update-firmware:14` copies `fwupdx64.efi` to `/boot/EFI/arch/` when `/usr/lib/fwupd/efi/fwupdx64.efi` exists; Fedora ships that file under a different path, so the branch does not run, but it is on the allowlist with this note rather than assumed portable |
| `omarchy-channel-current`, `omarchy-channel-set`, `omarchy-version-channel` | replace | print `tinkero`; `-set` refuses |
| `omarchy-version` | patch | one line reads the pacman package version; read `/usr/share/omarchy/version` and append the Tinkero RPM release |
| `omarchy-version-pkgs` | replace | last `dnf` transaction time from `dnf history` |
| `omarchy-migrate`, `omarchy-upgrade-to-quattro` | drop | migrations are a non-goal; `omarchy-migrate-notify.service` is dropped with them |
| `omarchy-refresh-pacman`, `omarchy-refresh-limine` | drop | |
| `omarchy-reinstall-configs` | patch | upstream's body is `cp -af /etc/skel/. ~/` (line 19) followed by `omarchy-refresh-limine` and `omarchy-refresh-plymouth` (lines 21-22). Tinkero ships no `/etc/skel` and drops both refresh scripts, so all three lines are replaced by one call to `tinkero-provision --reset-all`, keeping the command name the `omarchy` skill documents as the rollback |
| `omarchy-upload-log` | drop | uploads to `logs.omarchy.org`; Tinkero must not send a Fedora user's logs to Omarchy's service |
| `omarchy-debug` | patch | package inventory via `rpm -qa --qf`, Omarchy package line via `rpm -q tinkero` |

### 4.3 System, boot, security

| Script | Verdict | Reason |
|---|---|---|
| `omarchy-snapshot` | drop | snapper + Limine |
| `omarchy-system-factory-reset`, `-finish`, `omarchy-provision-owner` | drop | ISO-installed Arch machines only; destructive |
| `omarchy-hibernation-setup`, `-remove` | drop | `mkinitcpio` and Limine resume hooks |
| `omarchy-hibernation-available` | replace (stub) | returns false, so the `system.hibernate` menu row hides itself through its own guard. Upstream's test would also come out false on Fedora, but it names `mkinitcpio` paths and would trip the Arch-leak gate; a two-line stub is cheaper than an allowlist entry |
| `omarchy-setup-direct-boot` | drop | UKI/EFI boot entries for Arch |
| `omarchy-plymouth-*` (7), `omarchy-refresh-plymouth`, `omarchy-refresh-sddm` | drop | spec rev 1 already drops plymouth and sddm theming; outside their own family they are reachable only from the menu (`style.unlock`, `update.config.plymouth`), and `omarchy-theme-set` does not call them |
| `omarchy-setup-security-fingerprint` | replace | upstream runs `sudo pacman -S libfprint-git fprintd usbutils` directly and inserts `pam_fprintd.so` into `/etc/pam.d/sudo` and `polkit-1` with `sed -i`, which authselect owns on Fedora. Tinkero version: `dnf install fprintd fprintd-pam`, `fprintd-enroll`, `authselect enable-feature with-fingerprint`, then `omarchy-apply-lock` |
| `omarchy-remove-security-fingerprint` | replace | upstream `sed -i`s the same PAM files (lines 11-19), removes the lock fingerprint file and drops the packages. Tinkero version: `authselect disable-feature with-fingerprint`, `omarchy-apply-lock` (which removes the fingerprint PAM file when no enrolment remains), `omarchy-pkg-drop fprintd-pam`. Reachable from `remove.security.fingerprint` as soon as `fprintd` is installed, so it cannot ship as is. **Found by tier 3** |
| `omarchy-setup-security-fido2`, `omarchy-remove-security-fido2` | drop (v1) | insert and delete `pam_u2f.so` lines in `/etc/pam.d/sudo` and `polkit-1` with `sed -i`. The Fedora-native route is `authselect enable-feature with-pam-u2f`; until that replacement is written, the scripts and their menu entries are removed |
| `omarchy-sudo-passwordless` | drop | writes a sudoers drop-in; Tinkero adds no sudoers entries (spec section 5) |
| `omarchy-toggle-hybrid-gpu` | drop | writes `/etc/supergfxd.conf` and a systemd drop-in for `supergfxd`, which Fedora does not package; its menu row is hardware-guarded but the script cannot work |
| `omarchy-dev-link`, `omarchy-dev-unlink`, `omarchy-dev-status` | drop | write `/etc/omarchy.conf` so that `OMARCHY_PATH` points at a checkout in a home directory. Under RPM the tree is package-owned; a root-level redirect of it is developer tooling for upstream's workflow and a needless privileged surface here |
| `omarchy-remove-browser` | keep | removes browser policy files under `/etc/opt/*/policies` and `/etc/brave` that `omarchy-theme-set-browser-policy` may have written; paths are distro-neutral and the action is user-invoked |
| `omarchy-setup-security-sshd`, `omarchy-remove-security-sshd` | replace | `firewall-cmd --add-service=ssh` instead of `ufw`; otherwise the same |
| `omarchy-apply-lock` | patch | upstream writes the password PAM file inline (an Arch-shaped stack with its own `pam_faillock` lines and `account include system-local-login`). Tinkero's password file is RPM-owned (spec §4.8), so the patch reduces the script to managing the fingerprint file; upstream's target-user logic (lines 15-19) is kept |
| `omarchy-install-service-sunshine`, `omarchy-remove-service-sunshine` | drop | ufw rules plus AUR package |
| `omarchy-windows-vm`, `omarchy-sudo-docker`, `omarchy-setup-security-sudoless-docker`, `omarchy-remove-security-sudoless-docker`, `omarchy-install-docker-dbs` | drop | Docker and the Windows VM are non-goals |
| `omarchy-launch-docker-tui` | keep | launches `lazydocker` if present; its `Super+Shift+D` binding is inside the preinstalled-bindings gate (§7) |
| `omarchy` (the CLI dispatcher) | keep | tier 2 hit on its group descriptions only. `omarchy help` will still list groups whose commands are all dropped (plymouth, windows, hibernation, snapshot, games); cosmetic, accepted, not worth a patch |

### 4.4 The `omarchy-install-*` family (38 scripts)

All but six go through `omarchy-pkg-add`, so the *script* is portable and the question is whether the *package* has a Fedora answer in the name map.

| Group | Scripts | Verdict |
|---|---|---|
| Generic installers | `install-app`, `install-and-launch`, `install-terminal`, `install-font`, `install-browser`, `install-editor-helix`, `install-editor-vscode`, `install-editor-zed` | keep; works through the name map. `install-browser` also calls `omarchy-pkg-aur-add` for AUR-only browsers, which the stub refuses cleanly |
| `install-editor-emacs` | AUR only | hide |
| Dev environments | `install-dev-env` (mise plus a few `omarchy-pkg-add` calls) | keep; name map needs the handful of `-devel` packages it asks for |
| Agent CLIs | `install-hermes-cli` | patch: drop the `omarchy-pkg-present hermes-desktop` hand-over branch, keep the pipx/mise path. The branch would already evaluate false through the replaced `omarchy-pkg-present`; it is removed anyway so that the script does not depend on a name-map row for a package Tinkero never offers |
| | `install-openclaw-cli` | drop; pacman package. Remove `openclaw` from the agent picker |
| AI desktop apps | `install-ai-chatgpt`, `-hermes`, `-openclaw`, `-t3-code` | hide in v1 (decision: no Flatpak remapping in the first release) |
| Chromium helpers | `install-chromium-copy-url`, `-google-account`, `-ytdlp` | keep, but not run automatically (see §6); they write native-messaging hosts under `~/.config/chromium`, harmless without Chromium |
| Services | `install-service-1password`, `-dropbox`, `-nordvpn`, `-once`, `-signal`, `-spotify`, `-tailscale` | hide in v1. `signal` and `spotify` have Flathub ids and are the first candidates to bring back |
| Gaming (9) | `install-gaming-*`, and the matching `omarchy-remove-gaming-*` | drop; non-goal. `retroarch` also calls pacman directly; the Xbox controller pair writes udev and modprobe files under `/etc` |
| `install-preinstalls` | reinstalls Omarchy's default app set | drop |

### 4.5 Remaining tier 1 hits

| Script | Verdict | Note |
|---|---|---|
| `omarchy-default-agent` | keep | the only hit is a comment about OpenClaw. At `v4.0.4` it has **no** Claude browser-extension hook; that arrived later on `quattro` and must be reviewed at the first lock bump |
| `omarchy-remove-launcher-entry` | patch | the launcher's "remove this app" action; lines 87-91 find the owning package with `pacman -Qqo` and remove it with `sudo pacman -Rns`. Becomes `rpm -qf` and `sudo dnf remove`. Reachable from the app launcher, so it cannot be left as is |
| `omarchy-remove-dev-env` | patch | two direct `sudo pacman -Rns --noconfirm ...` calls (lines 13, 53) for the PHP and Symfony environments; become `omarchy-pkg-drop` |

## 5. `shell/`, `default/`, `config/`

| File | Verdict | Note |
|---|---|---|
| `shell/plugins/menu/MenuModel.js` | **patch** | `guardHelpers()` (lines 410-423) builds the installed-package set from `pacman -Qq`/`-Qi` and defines bash functions `omarchy-pkg-present`/`-missing` that shadow the real commands for every `when`/`checked` guard. Replace the set builder with `rpm -qa --qf '%{NAME}\n'` plus `rpm -qa --provides`, mapped back to Arch names through the name map's reverse index. 64 guards depend on it |
| `default/pacman/*` (3), `default/limine/limine.conf`, `default/libalpm/hooks/00-omarchy-update-guard.hook` | drop | Arch payload |
| `default/systemd/user/omarchy-migrate-notify.service` | drop | |
| `default/omarchy/omarchy-menu.jsonc` | rewritten at build time | see §7 |
| `default/omarchy/launcher.hides` | keep | list of `.desktop` ids to hide from the app launcher; Arch ids simply never match |
| `default/agents/skills/omarchy/hooks.md` | keep | documents the `pre-refresh-pacman` hook; harmless, and the hook never fires |
| `default/agents/skills/diagnose-crash/SKILL.md` | patch | lines 56-64: "This is Arch, which runs a public debuginfod server" and `DEBUGINFOD_URLS="https://debuginfod.archlinux.org"` become Fedora's. The "recent package updates" step (line 40) names no tool; the host guide tells the agent to use `dnf history` |
| `default/agents/skills/omarchy/SKILL.md` | patch | package idiom points at the host guide. No tier 1 hit because it teaches `omarchy pkg add`, which is the wrapper |
| `default/fonts/omarchy/README.md`, `default/hypr/input.lua` | keep | an AUR URL in a README; a comment |
| `config/omarchy/hooks/pre-refresh-pacman.d/add-custom-repo.sample` | drop | not seeded |

## 6. First-run and user provisioning

`default/hypr/autostart.lua:7` runs `omarchy-provision-first-run` on every session start. Without the done-marker `first-run-user` it runs `omarchy-provision-user` and then the first-run steps, and retries at every login until all succeed. Tinkero **replaces both scripts** (design decision 2026-09-17); the table is the keep/adapt/drop list its replacements implement.

| Upstream step (source) | What it does | Verdict for Tinkero |
|---|---|---|
| Skill symlinks (`omarchy-provision-user:87-103`) | links every skill into `~/.agents`, `~/.claude`, `~/.codex`, `~/.pi/agent`, `~/.hermes` (five dirs at this tag; no `~/.gemini`) | keep, verbatim loop |
| XDG dirs (`:105-109`) | points TEMPLATES, PUBLICSHARE, DESKTOP at `$HOME`, `rmdir`s the three directories | **drop**: these are GNOME's directories |
| GTK bookmarks (`:110-114`) | adds Downloads, Projects, Pictures, Videos to `~/.config/gtk-3.0/bookmarks` | drop; shared with GNOME's Files |
| `install/user/theme.sh` | first `omarchy-theme-set` | keep |
| `install/user/chromium.sh` | installs two Chromium native-messaging helpers | drop from the automatic chain |
| `install/user/git.sh`, `install/user/xcompose.sh` | `git config --global` aliases and identity; writes `~/.XCompose` | adapt: these are commands, not file copies, so the seeding rules do not cover them. `git.sh` runs only when `~/.gitconfig` and `~/.config/git/config` are both absent; `xcompose.sh` only when `~/.XCompose` is absent |
| `install/user/mise-work.sh` | `~/Work` with a mise config | keep (`omarchy-agent` starts in `~/Work`) |
| `install/user/hardware/*` (5) | ASUS, Dell XPS, Framework 13 audio, nouveau cursor fixes; each self-detects | keep; they are no-ops on other hardware and only touch user-level PipeWire/Hyprland config |
| `install/user/default-keyring.sh` | creates an **unencrypted, never-locking** `Default_keyring` and makes it default if no default exists | **drop**: GDM's PAM stack unlocks the login keyring, which is the reason the spec keeps GDM |
| `install/user/mise.sh` | 15 lazy agent stubs plus `omarchy-install-hermes-cli`; sets `upgrade.auto_prune false` | keep |
| Default browser `chromium.desktop`, `mailto` to `HEY.desktop` (`:119-120`) | | **drop**: global to the account, affects GNOME |
| `omarchy-refresh-applications` | copies Omarchy's `.desktop` launchers (web apps, TUIs) into `~/.local/share/applications` | adapt: TUI launchers only; web-app launchers are a non-goal and would appear in GNOME's overview |
| post-update hooks: voxtype invitation, fingerprint setup, agent setup (`omarchy-provision-first-run:70-75`) | installed as `post-update` hooks, which fire after `omarchy-update`. With `omarchy-update` stubbed they **never fire** | adapt: `tinkero-provision` sends the "Set your default agent" notification itself on first session; the other two are left to the menu |
| `install/user/first-run/enable-user-units.sh` | enables six user units including `omarchy-migrate-notify` | adapt: the five kept units plus nothing else (the status timer is not in v1) |
| `install/user/first-run/gnome-theme.sh`, `gtk-primary-paste.sh` | `gsettings set org.gnome.desktop.interface ...` | **drop**; see the theme note below |
| `install/user/first-run/audio-tuning.sh` | speaker EQ presets for known laptops | keep |
| `install/user/first-run/welcome.sh`, `wifi.sh` | welcome toast; "connect Wi-Fi, then run updates" toast that points at `omarchy update` | adapt: Tinkero welcome toast only |

**Theme switching writes shared GNOME state.** `omarchy-theme-set` calls `omarchy-theme-set-gnome` (lines 21-33), which sets `color-scheme`, `gtk-theme` and `icon-theme` in dconf on every switch. GTK apps inside the Tinkero session need those keys to follow the theme, and the GNOME session reads the same keys. Verdict: **replace `omarchy-theme-set-gnome`** with a version that saves the three pre-existing values to `~/.local/state/tinkero/gnome-interface.saved` the first time it runs in a login session, and ship a `graphical-session.target`-bound user unit whose `ExecStop` restores them at Tinkero logout. `omarchy-theme-set-vscode`, `-obsidian` and `-browser` edit application settings that are equally visible from GNOME; they stay enabled (that is the feature) and are documented, with upstream's existing skip toggles (`omarchy-toggle-enabled skip-vscode-theme-changes` and friends) as the opt-out.

## 7. Menu and keybindings

The default menu has 333 entries: `install` 91, `setup` 66, `remove` 60, `trigger` 47, `update` 28, `style` 21, `learn` 10, `system` 8, `apps` 1, `about` 1.

Two facts about the merge decide the mechanism (`MenuModel.js:65-95`, `:254-270`, `:312-326`):

1. The user file is merged field by field over the default, keyed by id. **An entry cannot be deleted by a merge**, only overridden.
2. Overriding a submenu with `"when": "false"` hides that row, but visibility of a *leaf* depends only on its own `when`, and search matches any visible leaf. So `install.gaming.steam` stays reachable from search even when `install.gaming` is hidden.

Therefore the overrides are applied by **rewriting the default JSONC at RPM build time**, deleting ids by prefix, rather than by shipping an extension file. There is no system-level extension path upstream in any case (`Menu.qml:50-51` loads exactly two sources). The user's own `~/.config/omarchy/extensions/omarchy-menu.jsonc` keeps working untouched.

Build-time menu edits (`menu/overrides.jsonc`, applied by `menu/apply-overrides`):

| Operation | Ids |
|---|---|
| delete prefix | `install.package`, `install.aur`, `install.webapp`, `install.gaming`, `install.windows`, `install.preinstalls`, `install.ai` (v1), `install.service` (v1), `install.editor.emacs`, `remove.package`, `remove.webapp`, `remove.gaming`, `remove.windows`, `remove.preinstalls`, `remove.ai`, `remove.service`, `update.omarchy`, `update.channel`, `update.config.plymouth`, `setup.direct-boot`, `setup.reset`, `style.unlock`, `setup.default.agent.openclaw`, `setup.security.fido2`, `remove.security.fido2`, `setup.security.passwordless-sudo`, `setup.security.sudoless-docker`, `remove.security.sudoless-docker`, `trigger.hardware.hybrid-gpu` |
| delete ids whose action names a dropped script | computed at build time from the drop list, so a new upstream entry that calls a dropped script fails the build instead of shipping dead |
| replace | `update.omarchy` is re-added as "Update (dnf + mise)" running `omarchy-launch-floating-terminal-with-presentation tinkero-update`, a four-line script: `sudo dnf upgrade`, `mise up` |
| keep | `install.tui`, `install.style`, `install.development`, `install.editor` (minus emacs), `install.terminal`, `install.browser`, and their `remove.*` mirrors, all through the name map |

The prefix list removes 76 of the 333 entries (counted against the `v4.0.4` file); deletion by action removes whatever else still points at a dropped script.

**Keybindings.** Every command bound in `default/hypr/bindings/*.lua` survives the drop list except none: the only bound command that touches a dropped area is `omarchy-launch-docker-tui`, which is kept. The web-app and third-party-app chords (`Super+Shift+{M,G,O,W,/}` and the web-app set) all sit inside `if o.preinstalled_bindings_enabled()` (`applications.lua:10`). The essential bindings (terminal, browser, file manager, editor) are declared before that gate (lines 2-8) and are unaffected. Inside the gate (lines 10-34), three are host-neutral and have their program available: tmux (`Super+Alt+Return`, line 12), **herdr (`Super+Ctrl+Return`, line 13)** and the Docker TUI (`Super+Shift+D`, line 16). The gate has two switches (`default/hypr/helpers.lua:84-89`): the Lua global `omarchy_preinstalled_bindings`, which has to be set in `hyprland.lua` before the defaults load, and the marker file `~/.local/state/omarchy/preinstalls-removed`. Tinkero uses the marker: `tinkero-provision` creates it, no upstream config file is forked, and its only other readers are the two `preinstalls` menu rows, which are deleted. The seeded `bindings.lua` re-adds exactly those three. A fourth terminal program in the gate, the `cliamp` music TUI (`Super+Shift+Alt+M`, line 15), is left out because `cliamp` exists only in Omarchy's package repo and Tinkero's COPR does not build it; it is the first candidate if the COPR grows. `omarchy-launch-browser` uses `xdg-settings get default-web-browser`, so it launches Firefox on a stock Fedora without changes; `omarchy-launch-webapp` falls back to Chromium and is unreachable once the web-app chords and menu entries are gone.

## 8. CI gate derived from this audit

Run against the *installed payload* of the built `tinkero` RPM (not the source tree):

1. **Arch-leak gate.** The tier 1 grep over the payload must match only the allowlist: the comment-only hits in §4.5 and §5 (`omarchy-default-agent`, `launcher.hides`, `hooks.md`, `fonts/omarchy/README.md`, `input.lua`). Any new file fails the build; the fix is a row in this audit.
2. **Dangling-command gate.** Every `omarchy-*` and `tinkero-*` token in the built menu JSONC, in `default/hypr/**/*.lua`, in `shell/**/*.qml|js`, and in the kept scripts resolves to a file in the payload.
3. **Name-map gate.** Every literal package name passed to `omarchy-pkg-add`, `-drop`, `-present`, `-missing` in the payload (including menu guards) has a row in `pkgmap.tsv`, even if the row's target is `none`.
4. **Single-copy gate.** No script name exists as a regular file in both `/usr/bin` and `/usr/share/omarchy/bin`; the latter holds only symlinks (upstream's layout, `docs/file-layout.md:56-57`).
5. **Branding gate.** See §11 and the design spec §4.13: no capitalised "Omarchy" in a string literal outside the allowlist, no `*omarchy*` file under any theme's `backgrounds/`, no wallpaper without a reviewed keep row in `branding/images.tsv`, and every `branding/strings.tsv` row matched its expected count.

## 9. The patch set

Eleven files carry a diff against upstream and therefore a rebase cost on each bump. All but the first are under ten changed lines.

1. `shell/plugins/menu/MenuModel.js` (package snapshot; about 15 lines)
2. `bin/omarchy-apply-lock` (PAM shape)
3. `bin/omarchy-debug` (inventory)
4. `bin/omarchy-version` (line 22, version source)
5. `bin/omarchy-reinstall-configs` (line 21)
6. `bin/omarchy-install-hermes-cli` (the `hermes-desktop` branch, line 40)
7. `bin/omarchy-remove-launcher-entry` (lines 87-91)
8. `bin/omarchy-remove-dev-env` (lines 13, 53)
9. `default/agents/skills/omarchy/SKILL.md` (package idiom, lines 149 and 256, points at the host guide; line 175 names the relocated fastfetch default)
10. `default/agents/skills/diagnose-crash/SKILL.md` (lines 56-64)
11. `bin/omarchy-launch-about` (its two `fastfetch` calls, lines 104 and 161, get `-c /usr/share/tinkero/fastfetch/config.jsonc` unless the script's own `custom_fastfetch_config` test, lines 16-18, finds a user config, which `-c` would otherwise override; see §12)

Spec rev 1 also listed `bin/omarchy-agent-crash` as needing a debuginfod patch. At `v4.0.4` that script contains no debuginfod URL (it only builds the prompt and names the skill path), so it ships unmodified.

Replacements (Tinkero's own files under upstream names, no rebase): 21 scripts, listed in §4 and §6 (thirteen package, update, channel and version scripts in §4.1-4.2, counting each name; `omarchy-hibernation-available`; the two fingerprint and two sshd scripts; `omarchy-theme-set-gnome`; the two provisioning scripts). Dropped: about 85 scripts. Kept unmodified: about 330 of 444.

## 10. Bump checklist additions

When `upstream.lock` moves to a new tag, before anything else:

1. Re-run the tier 1 and tier 2 greps on the new tag and diff the file lists against this document.
2. Diff `install/user/**`, `bin/omarchy-provision-user` and `bin/omarchy-provision-first-run` between tags; every new step needs a keep/adapt/drop row in §6.
3. Diff `install/user/mise.sh` (roster) and the skill loop (directories).
4. Diff `default/omarchy/omarchy-menu.jsonc` ids; the build's dangling-command gate reports new entries that call dropped scripts.
5. Read `migrations/` added between the tags and classify each as Arch-only or config-only; config-only ones become entries in `docs/config-notes/<tag>.md`, which `tinkero-provision --check` reports.
6. Known item for the first bump past `v4.0.4`: `omarchy-install-chromium-claude` and the hook that calls it from `omarchy-default-agent` (writes to `/usr/share/chromium/extensions` via `pkexec`); the `gemini` to `agy` rename; the added `ori` stub; the `~/.gemini/config/skills` directory.

## 11. Branding inventory

Added 2026-09-17 after the decision that nothing a user sees should say or show Omarchy (design spec §4.13). Survey of `v4.0.4` for the capitalised name and the logo in places that reach the screen. Identifiers (command names, paths, plugin ids, window classes, PAM service names) are out of scope by that decision and are not listed.

| Surface | Where | Count | Handling |
|---|---|---|---|
| Logo glyph `U+E900` | `default/fonts/omarchy/omarchy.ttf`; drawn by `shell/plugins/menu/BarWidget.qml` (the bar's menu button) and referenced from the menu JSONC through `"iconFont":"omarchy"` (23 rows use that font, most for agent logos at `U+E901` and up) | 1 glyph | rebuild the font with Tinkero's mark in that code point |
| ASCII logos | `/logo.txt`, `/icon.txt`. `omarchy-show-logo` reads `$OMARCHY_PATH/logo.txt` directly; `omarchy-launch-about` and `omarchy-screensaver` read the user copies `~/.config/omarchy/branding/{about,screensaver}.txt`, which `omarchy-branding-about` and `omarchy-branding-screensaver` reset from the root files | 2 files | replace the files; seed the user copies from them |
| **Theme wallpapers** | 92 background images across 22 themes. 18 themes ship `backgrounds/omarchy.png`: the OMARCHY wordmark, large, in the theme's accent colour on its flat background colour (`accent` and `background` in the theme's `colors.toml`). Three more are named for it: `flexoki-light/backgrounds/2-omarchy.png`, `lupine/backgrounds/06-omarchy.png`, and `rose-pine/backgrounds/3-omarchy-plants.png` (the wordmark inside an illustration). Branding also hides under other names: `tokyo-night/backgrounds/6-oma.jpg` and `5-oma-cityscape.jpg` both show an upstream house mark (a glowing circle, square and diamond; not the logo in `logo.svg`, but plainly somebody else's mark), and `1-quattro.jpg` is upstream's release artwork, which additionally shows third-party marks (Audi, Michelin, Castrol) that a public derivative has no reason to redistribute as its wallpaper. All are ordinary entries in the wallpaper rotation (`omarchy-theme-bg-next`). Found in review; a text grep cannot see any of this, and **only 6 of the 92 images were opened for this audit** (`4-omakub.jpg` was one of them and shows nothing branded), so the rest need one pass by eye. No theme is left empty by the deletions; `flexoki-light` comes closest, going from two wallpapers to one plus the regenerated wordmark | at least 24 | the 18 flat ones are regenerated from the Tinkero wordmark and the theme's colours; illustrated ones and logo or release art are deleted; every wallpaper gets a reviewed row in `branding/images.tsv` |
| About screen OS line | `etc/fastfetch/config.jsonc:74`, `echo \"Omarchy $version\"`. The audit's original scope did not include `etc/` (see §12) | 1 | substitution list, on the relocated file |
| Plugin manifests | `"author": "Omarchy"` in 28 `manifest.json` files under `shell/plugins/`; `shell/plugins/menu/manifest.json` also has `name`, `displayName` and `description` naming Omarchy. `shell/shell.qml:1402` reads `displayName` into widget metadata, so at least that one can reach the screen | 28 files | JSON transform at build time; ids unchanged |
| Image logos | `/logo.svg`, `/icon.png` | 2 files | replace |
| Menu labels | `learn.omarchy` and `update.omarchy`, both `"label":"Omarchy"` | 2 | menu rewrite (§7) |
| Keybinding descriptions | `default/hypr/bindings/utilities.lua:1` and `:7`, `"Omarchy menu"` | 2 | substitution list |
| Shell strings | `shell/plugins/bar/widgets/SystemUpdate.qml:62` tooltip; `shell/services/PluginRegistry.qml:632` error text | 2 | substitution list |
| Notifications | the welcome toast in `install/user/first-run/welcome.sh`; "Pending Omarchy Migrations" in `omarchy-migrate-notify` | 2 | first is Tinkero's own, second is dropped |
| Session file | `default/wayland-sessions/omarchy.desktop` `Name=` and `Comment=` | 1 file | Tinkero ships its own |
| Dev gallery | `shell/plugins/dev-gallery/GalleryPanel.qml` titles, matched by a window rule in `default/hypr/apps/omarchy-shell.lua:14` | 3 | allowlisted: a developer tool, and the title is matched by the window rule |
| Window-rule regex | `default/hypr/apps/system.lua:7` matches a window titled "Omarchy" among others | 1 | allowlisted: it matches a title, it does not display one |
| Seeded config comments | header comments in `config/hypr/*.lua`, `config/kitty/kitty.conf`, `config/herdr/config.toml` and the sample hooks | 10 files | left as is: comments in files the user owns, pointing at upstream's documentation |
| CLI help and usage text | 122 of 444 scripts mention the name, almost all in `# omarchy:summary=` metadata and usage strings | | out of scope for v1 (terminal-only, tied to the command names) |

So the graphical surface is one glyph, four logo files, at least 24 wallpapers, 28 plugin manifests and ten strings. None of it needs a positional patch: files are replaced, images and manifests are generated, and strings go through a count-checked substitution list.

Bump checklist addition: after the greps in §10, run the branding gate on the new tag (literal scan, `backgrounds/*omarchy*` filename check, wallpapers without an `images.tsv` row) and review new hits before updating `branding/strings.tsv`. New themes are the likeliest source of a new branded image.

## 12. The `etc/` payload

Added 2026-09-17. The original method (§1) did not look at the tree's top-level `etc/` directory, which upstream's `omarchy-settings` package installs into `/etc`. It holds 40 files and is almost entirely host policy.

| Files | Verdict | Note |
|---|---|---|
| `sudoers.d/omarchy-dns`, `omarchy-theme-browser`, `omarchy-tzupdate` (`%wheel NOPASSWD` for three commands), `omarchy-passwd-tries` | drop | Tinkero adds no sudoers entries. The three commands still work and ask for a password |
| `security/faillock.conf` (`deny = 10`) | drop | replaces a file owned by Fedora's `pam`; the lock screen's own lockout is handled in its PAM file (spec §4.8) |
| `nsswitch.conf` | drop | replaces a file authselect owns |
| `sysctl.d/*` (2), `systemd/system.conf.d/*` (2), `systemd/user.conf.d/*`, `systemd/oomd.conf.d/*`, `systemd/resolved.conf.d/*` (2), `systemd/system/*.d/*` (4), `tmpfiles.d/*` (2), `sysusers.d/*`, `modprobe.d/*`, `NetworkManager/conf.d/*`, `gnupg/dirmngr.conf`, `cups/*` (2), `docker/daemon.json` | drop | system tuning and services; host policy |
| `systemd/logind.conf.d/10-ignore-power-button.conf` | drop, behaviour replaced | the shell's power menu expects the power key not to power off (`XF86PowerOff` is bound to it in `default/hypr/bindings/utilities.lua:9`). Tinkero gets that with a user unit holding a `handle-power-key` inhibitor lock for the session, without touching `/etc`; logind's polkit default grants it to the active session |
| `systemd/logind.conf.d/20-inhibit-delay.conf` (`InhibitDelayMaxSec=15`) | drop, **not** replaced | gives `omarchy-sleep-lock`'s delay inhibitor fifteen seconds instead of logind's five to get the lock screen up before suspend; upstream's comment says five is not enough. There is no unprivileged equivalent, so Tinkero accepts the shorter margin and Phase 0 measures it |
| `limine-entry-tool.d/*` (2), `mkinitcpio.conf.d/*` (2), `plymouth/plymouthd.conf`, `sddm.conf.d/*` (2) | drop | Arch boot and SDDM |
| `profile.d/omarchy.sh` | drop | sources `default/bash/env-bootstrap` for every login shell on the host; the uwsm env file already does it for the Tinkero session |
| `xdg/kitty/kitty.conf` | drop | system-wide kitty defaults would affect kitty under GNOME; kitty is optional |
| `mise/conf.d/omarchy.toml` | keep | a `cursor-agent` tool alias; inert unless that tool is installed |
| `fastfetch/config.jsonc` | keep, relocated | drives the About screen and calls `omarchy-version` (patched), `omarchy-version-channel` and `omarchy-version-pkgs` (replaced), and `omarchy-version-branch` and `omarchy-theme-current` (both keep: no tier 1 to 3 hit, nothing host-specific). Installed to `/usr/share/tinkero/fastfetch/`, not `/etc/fastfetch/`, so that `fastfetch` elsewhere on the host is unchanged; `omarchy-launch-about` is patched to point at it |

The tier 1 to 3 greps should be run over `etc/` as well at each bump, and the CI gates already see whatever of it reaches the payload.
