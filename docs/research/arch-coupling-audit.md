# Arch-coupling audit of Omarchy v4.0.4

Audit date: 2026-09-17. Subject: `omacom/omarchy` tag `v4.0.4`, commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`, read from a shallow clone. Nothing from the tree was executed.

Purpose: size and classify the seam between the distro-neutral Omarchy tree and its Arch substrate, so that the Tinkero spec's shim table (design spec §4.3), menu overrides (§4.4) and provisioning (§4.6) are derived rather than asserted. This is the audit called for by finding B3 of `docs/spec-review.md`.

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

Then: every `omarchy-install-*` script was classified by the installer it calls; the default menu (`default/omarchy/omarchy-menu.jsonc`) was parsed and grouped by id prefix; the first-run and user-provisioning chain was read end to end; and the commands bound in `default/hypr/bindings/*.lua` were cross-checked against everything marked *drop*.

Limits: a grep audit finds named tools, not assumptions (a script that expects `/etc/pacman.d` to exist without naming pacman would be missed). Scripts that only call the `omarchy-pkg-*` wrappers are coupled *through* the wrappers and are correct once the shims and the name map are correct; they are counted, not listed. The CI gate in §8 exists to catch what this pass missed and what upstream adds later.

## 2. Verdict vocabulary

| Verdict | Meaning | Cost on a tag bump |
|---|---|---|
| **replace** | Tinkero ships its own script under the same name | none unless upstream changes the script's contract |
| **patch** | Small diff against the upstream file | rebase; this is the number to keep small |
| **drop** | Not installed | none; needs its menu entries and bindings removed too |
| **hide** | Script ships (harmless or unreachable) but its menu entry is removed | none |
| **keep** | Ships unmodified; the hit is a comment, a portable tool, or reachable only through a shim | none |

## 3. Totals

| Area | Files | Tier 1 hits | Notes |
|---|---|---|---|
| `bin/` | 444 | 50 | 38 are `omarchy-install-*`; 66 scripts call the `omarchy-pkg-*` wrappers (10 of them are also among the 50) |
| `bin/` tier 2 only | | 19 | plymouth, sddm, docker, direct boot, Windows VM |
| `shell/` | | 1 | `plugins/menu/MenuModel.js` |
| `default/` | | 12 | 5 are Arch-only payload that is not installed |
| `config/` | | 1 | a sample hook |
| `install/user/` | 22 | 0 | coupled indirectly; see §6 |

Resulting patch set (the rebase cost): **10 small patches**, listed in §9. Everything else is replace, drop, hide or keep.

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
| `omarchy-update-mise`, `omarchy-update-firmware`, `omarchy-update-time` | keep | `mise up`, `fwupdmgr`, `timedatectl`; portable. Menu entries `update.firmware`, `update.time` stay |
| `omarchy-channel-current`, `omarchy-channel-set`, `omarchy-version-channel` | replace | print `tinkero`; `-set` refuses |
| `omarchy-version` | patch | one line reads the pacman package version; read `/usr/share/omarchy/version` and append the Tinkero RPM release |
| `omarchy-version-pkgs` | replace | last `dnf` transaction time from `dnf history` |
| `omarchy-migrate`, `omarchy-upgrade-to-quattro` | drop | migrations are a non-goal; `omarchy-migrate-notify.service` is dropped with them |
| `omarchy-refresh-pacman`, `omarchy-refresh-limine` | drop | |
| `omarchy-reinstall-configs` | patch | remove the `omarchy-refresh-limine` call (line 21); otherwise the documented "reset my configs" rollback works as upstream |
| `omarchy-upload-log` | drop | uploads to `logs.omarchy.org`; Tinkero must not send a Fedora user's logs to Omarchy's service |
| `omarchy-debug` | patch | package inventory via `rpm -qa --qf`, Omarchy package line via `rpm -q tinkero` |

### 4.3 System, boot, security

| Script | Verdict | Reason |
|---|---|---|
| `omarchy-snapshot` | drop | snapper + Limine |
| `omarchy-system-factory-reset`, `-finish`, `omarchy-provision-owner` | drop | ISO-installed Arch machines only; destructive |
| `omarchy-hibernation-setup`, `-remove` | drop | `mkinitcpio` and Limine resume hooks |
| `omarchy-hibernation-available` | replace (stub) | returns false, so the `system.hibernate` menu row hides itself through its own guard |
| `omarchy-setup-direct-boot` | drop | UKI/EFI boot entries for Arch |
| `omarchy-plymouth-*` (7), `omarchy-refresh-plymouth`, `omarchy-refresh-sddm` | drop | spec rev 1 already drops plymouth and sddm theming; outside their own family they are reachable only from the menu (`style.unlock`, `update.config.plymouth`), and `omarchy-theme-set` does not call them |
| `omarchy-setup-security-fingerprint` | replace | upstream runs `sudo pacman -S libfprint-git fprintd usbutils` directly. Tinkero version: `dnf install fprintd fprintd-pam`, `fprintd-enroll`, `authselect enable-feature with-fingerprint`, then `omarchy-apply-lock` |
| `omarchy-setup-security-sshd`, `omarchy-remove-security-sshd` | replace | `firewall-cmd --add-service=ssh` instead of `ufw`; otherwise the same |
| `omarchy-apply-lock` | patch | write Fedora-shaped PAM (`auth`/`account include system-auth`); keep upstream's target-user logic (lines 15-19) |
| `omarchy-install-service-sunshine`, `omarchy-remove-service-sunshine` | drop | ufw rules plus AUR package |
| `omarchy-windows-vm`, `omarchy-sudo-docker`, `omarchy-setup-security-sudoless-docker`, `omarchy-remove-security-sudoless-docker`, `omarchy-install-docker-dbs` | drop | Docker and the Windows VM are non-goals |
| `omarchy-launch-docker-tui` | keep | launches `lazydocker` if present; its `Super+Shift+D` binding is inside the preinstalled-bindings gate (§7) |
| `omarchy-dev-link` | keep | only mentions sddm in a comment path; developer tool |

### 4.4 The `omarchy-install-*` family (38 scripts)

All but six go through `omarchy-pkg-add`, so the *script* is portable and the question is whether the *package* has a Fedora answer in the name map.

| Group | Scripts | Verdict |
|---|---|---|
| Generic installers | `install-app`, `install-and-launch`, `install-terminal`, `install-font`, `install-browser`, `install-editor-helix`, `install-editor-vscode`, `install-editor-zed` | keep; works through the name map. `install-browser` also calls `omarchy-pkg-aur-add` for AUR-only browsers, which the stub refuses cleanly |
| `install-editor-emacs` | AUR only | hide |
| Dev environments | `install-dev-env` (mise plus a few `omarchy-pkg-add` calls) | keep; name map needs the handful of `-devel` packages it asks for |
| Agent CLIs | `install-hermes-cli` | patch: drop the `omarchy-pkg-present hermes-desktop` hand-over branch, keep the pipx/mise path |
| | `install-openclaw-cli` | drop; pacman package. Remove `openclaw` from the agent picker |
| AI desktop apps | `install-ai-chatgpt`, `-hermes`, `-openclaw`, `-t3-code` | hide in v1 (decision: no Flatpak remapping in the first release) |
| Chromium helpers | `install-chromium-copy-url`, `-google-account`, `-ytdlp` | keep, but not run automatically (see §6); they write native-messaging hosts under `~/.config/chromium`, harmless without Chromium |
| Services | `install-service-1password`, `-dropbox`, `-nordvpn`, `-once`, `-signal`, `-spotify`, `-tailscale` | hide in v1. `signal` and `spotify` have Flathub ids and are the first candidates to bring back |
| Gaming (9) | `install-gaming-*` | drop; non-goal. `retroarch` also calls pacman directly |
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
| `install/user/git.sh`, `xcompose.sh` | git aliases and identity prompts; `~/.XCompose` | adapt: only when the target file does not exist |
| `install/user/mise-work.sh` | `~/Work` with a mise config | keep (`omarchy-agent` starts in `~/Work`) |
| `install/user/hardware/*` (5) | ASUS, Dell XPS, Framework 13 audio, nouveau cursor fixes; each self-detects | keep; they are no-ops on other hardware and only touch user-level PipeWire/Hyprland config |
| `install/user/default-keyring.sh` | creates an **unencrypted, never-locking** `Default_keyring` and makes it default if no default exists | **drop**: GDM's PAM stack unlocks the login keyring, which is the reason the spec keeps GDM |
| `install/user/mise.sh` | 15 lazy agent stubs plus `omarchy-install-hermes-cli`; sets `upgrade.auto_prune false` | keep |
| Default browser `chromium.desktop`, `mailto` to `HEY.desktop` (`:119-120`) | | **drop**: global to the account, affects GNOME |
| `omarchy-refresh-applications` | copies Omarchy's `.desktop` launchers (web apps, TUIs) into `~/.local/share/applications` | adapt: TUI launchers only; web-app launchers are a non-goal and would appear in GNOME's overview |
| post-update hooks: voxtype invitation, fingerprint setup, agent setup (`omarchy-provision-first-run:70-75`) | installed as `post-update` hooks, which fire after `omarchy-update`. With `omarchy-update` stubbed they **never fire** | adapt: `tinkero-provision` sends the "Set your default agent" notification itself on first session; the other two are left to the menu |
| `enable-user-units.sh` | enables six user units including `omarchy-migrate-notify` | adapt: the five kept units plus nothing else (the status timer is not in v1) |
| `gnome-theme.sh`, `gtk-primary-paste.sh` | `gsettings set org.gnome.desktop.interface ...` | **drop**; see the theme note below |
| `audio-tuning.sh` | speaker EQ presets for known laptops | keep |
| `welcome.sh`, `wifi.sh` | welcome toast; "connect Wi-Fi, then run updates" toast that points at `omarchy update` | adapt: Tinkero welcome toast only |

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
| delete prefix | `install.package`, `install.aur`, `install.webapp`, `install.gaming`, `install.windows`, `install.preinstalls`, `install.ai` (v1), `install.service` (v1), `install.editor.emacs`, `remove.package`, `remove.webapp`, `remove.gaming`, `remove.windows`, `remove.preinstalls`, `remove.ai`, `remove.service`, `update.omarchy`, `update.channel`, `update.config.plymouth`, `setup.direct-boot`, `setup.reset`, `style.unlock` |
| delete ids whose action names a dropped script | computed at build time from the drop list, so a new upstream entry that calls a dropped script fails the build instead of shipping dead |
| replace | `update.omarchy` is re-added as "Update (dnf + mise)" running `omarchy-launch-floating-terminal-with-presentation tinkero-update`, a four-line script: `sudo dnf upgrade`, `mise up` |
| keep | `install.tui`, `install.style`, `install.development`, `install.editor` (minus emacs), `install.terminal`, `install.browser`, and their `remove.*` mirrors, all through the name map |

That removes roughly 95 of the 151 install/remove entries and about 10 others.

**Keybindings.** Every command bound in `default/hypr/bindings/*.lua` survives the drop list except none: the only bound command that touches a dropped area is `omarchy-launch-docker-tui`, which is kept. The web-app and third-party-app chords (`Super+Shift+{M,G,O,W,/}` and the web-app set) all sit inside `if o.preinstalled_bindings_enabled()` (`applications.lua:10`). Tinkero's seeded `~/.config/hypr/bindings.lua` sets `omarchy_preinstalled_bindings = false` and re-adds the four that make sense on any host (browser, file manager, editor, Docker TUI). `omarchy-launch-browser` uses `xdg-settings get default-web-browser`, so it launches Firefox on a stock Fedora without changes; `omarchy-launch-webapp` falls back to Chromium and is unreachable once the web-app chords and menu entries are gone.

## 8. CI gate derived from this audit

Run against the *installed payload* of the built `tinkero` RPM (not the source tree):

1. **Arch-leak gate.** The tier 1 grep over the payload must match only the allowlist: the comment-only hits in §4.5 and §5 (`omarchy-default-agent`, `launcher.hides`, `hooks.md`, `fonts/omarchy/README.md`, `input.lua`). Any new file fails the build; the fix is a row in this audit.
2. **Dangling-command gate.** Every `omarchy-*` and `tinkero-*` token in the built menu JSONC, in `default/hypr/**/*.lua`, in `shell/**/*.qml|js`, and in the kept scripts resolves to a file in the payload.
3. **Name-map gate.** Every literal package name passed to `omarchy-pkg-add`, `-drop`, `-present`, `-missing` in the payload (including menu guards) has a row in `pkgmap.tsv`, even if the row's target is `none`.
4. **Single-copy gate.** No script name exists as a regular file in both `/usr/bin` and `/usr/share/omarchy/bin`; the latter holds only symlinks (upstream's layout, `docs/file-layout.md:56-57`).

## 9. The patch set

Ten files carry a diff against upstream and therefore a rebase cost on each bump. All but the first are under ten changed lines.

1. `shell/plugins/menu/MenuModel.js` (package snapshot; about 15 lines)
2. `bin/omarchy-apply-lock` (PAM shape)
3. `bin/omarchy-debug` (inventory)
4. `bin/omarchy-version` (line 22, version source)
5. `bin/omarchy-reinstall-configs` (line 21)
6. `bin/omarchy-install-hermes-cli` (the `hermes-desktop` branch, line 40)
7. `bin/omarchy-remove-launcher-entry` (lines 87-91)
8. `bin/omarchy-remove-dev-env` (lines 13, 53)
9. `default/agents/skills/omarchy/SKILL.md` (package idiom, lines 149 and 256, points at the host guide)
10. `default/agents/skills/diagnose-crash/SKILL.md` (lines 56-64)

Spec rev 1 also listed `bin/omarchy-agent-crash` as needing a debuginfod patch. At `v4.0.4` that script contains no debuginfod URL (it only builds the prompt and names the skill path), so it ships unmodified.

Replacements (Tinkero's own files under upstream names, no rebase): 21 scripts, listed in §4 and §6. Dropped: about 75 scripts. Kept unmodified: about 340 of 444.

## 10. Bump checklist additions

When `upstream.lock` moves to a new tag, before anything else:

1. Re-run the tier 1 and tier 2 greps on the new tag and diff the file lists against this document.
2. Diff `install/user/**`, `bin/omarchy-provision-user` and `bin/omarchy-provision-first-run` between tags; every new step needs a keep/adapt/drop row in §6.
3. Diff `install/user/mise.sh` (roster) and the skill loop (directories).
4. Diff `default/omarchy/omarchy-menu.jsonc` ids; the build's dangling-command gate reports new entries that call dropped scripts.
5. Read `migrations/` added between the tags and classify each as Arch-only or config-only; config-only ones become entries in `docs/config-notes/<tag>.md`, which `tinkero-provision --check` reports.
6. Known item for the first bump past `v4.0.4`: `omarchy-install-chromium-claude` and the hook that calls it from `omarchy-default-agent` (writes to `/usr/share/chromium/extensions` via `pkexec`); the `gemini` to `agy` rename; the added `ori` stub; the `~/.gemini/config/skills` directory.
