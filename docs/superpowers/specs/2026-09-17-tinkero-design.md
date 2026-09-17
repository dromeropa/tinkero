# Tinkero design spec

**Tagline:** a tinkerable desktop for Hyprland, bring your own distro.
**Status:** design agreed 2026-09-17, no code yet. Fedora 44 is the first target.
**Pronunciation:** tin-KEH-ro.

This document records what Tinkero is, why it is shaped the way it is, and every decision made in the research session that produced it. It is the input to the implementation plan. The research it rests on is `docs/research/omarchy-research.md`, a primary-source study of Omarchy at branch `quattro` (commit `2fbac0c`, tag v4.0.4 for the stable comparison).

## 1. Problem and goals

The author runs Fedora and wants to keep the Fedora and Red Hat base: dnf, RPM, SELinux enforcing, point releases, the stock kernel, GRUB, firewalld. They want three things Omarchy does well, without any of the Arch parts:

1. **Tiling.** Hyprland with Omarchy's keybindings and workflow, the terminal setup, and herdr as the session layer for agents.
2. **Plugins.** The ability to build their own bar widgets, panels and services for their workflows, with the connections between them. In Omarchy this is the Quickshell shell's plugin system, which is not Arch-specific at all.
3. **The agent as a first-class citizen.** Choose one agent as the default, launch it unattended from a keybinding, let it create plugins, edit configuration and customize the desktop through skills, plus dictation. The Omarchy workflow for this is the model.

They also like the look, and they have one hard constraint: **low maintenance.** Updates must stay `dnf upgrade` plus `mise up`, `dnf install` must keep working, and nothing should require weekly tinkering to stay current.

Tinkero is also meant as a base others can build on, eventually installable over any distro as an alternative desktop experience. It is explicitly not an "omakase" project: the idea is the opposite of chef's choice, a kit you assemble yourself.

## 2. What it is, in one paragraph

Hyprland is the compositor and does the heavy lifting of window management. Tinkero is the desktop environment around it: the Quickshell shell (bar, launcher, menu, notifications, OSD, lock, idle, wallpaper, polkit), the session wiring, the keybinding and theme system, the tooling, and the agent harness. Tinkero does not rewrite any of that. It vendors the distro-neutral part of Omarchy at a pinned tag and replaces Omarchy's Arch substrate (installer, migrations, pacman wrappers, Limine, snapper, ufw, kernel, pacman hooks) with the Fedora substrate: a COPR for the packages Fedora lacks, an RPM for the tree, and Fedora-native shims.

## 3. Non-goals

- Not a distribution, not an ISO, not an installer for a fresh machine. It installs on top of an existing Fedora Workstation.
- Not a port of Omarchy's Arch machinery. No `omarchy update`, no migrations, no channels, no Limine or snapper integration, no custom kernel, no ufw.
- Not Omarchy's app catalogue. No Chromium micro-fork, no web apps, no gaming, no Windows VM, no Docker setup. The Install menu entries that assume pacman are hidden or remapped.
- Not bootc or image mode, at least for now. The author wants `dnf install` to keep working on the host.
- Not a reimplementation. Reimplementations of Omarchy go stale in months because upstream releases weekly; the only porting pattern that has held up is vendoring the real tree and patching the seams (Omedora on Fedora, zicochaos/omarchy-nix on NixOS).

## 4. Architecture

Four pieces, all delivered from one public repo, `github.com/dromeropa/tinkero`.

### 4.1 Fedora package substrate (a COPR)

Fedora main already carries most of what Omarchy needs at current versions: sddm, plymouth, xdg-desktop-portal-gtk, grim, slurp, wl-clipboard, wtype, tesseract, zbar, mako, swaybg, waybar, wofi, cliphist, foot, alacritty, kitty, nautilus, pipewire, wireplumber, fcitx5, xdg-terminal-exec, the Qt 6 modules, jetbrains-mono-fonts, fontawesome-fonts-all, yaru-icon-theme, zoxide, eza, fd-find, ripgrep, fzf, bat, btop, gum, jq, tmux, snapper, chromium, neovim. Those stay on Fedora's update path.

The COPR carries what Fedora lacks: Hyprland (>= 0.56, Lua config) with hyprutils, hyprlang, hyprcursor, hyprgraphics, hyprwire, hyprtoolkit, aquamarine, hyprland-protocols, hyprwayland-scanner, glaze; hyprland-guiutils; hyprland-preview-share-picker; hyprpicker; hyprsunset; xdg-desktop-portal-hyprland; quickshell at the commit Omarchy pins; uwsm; gpu-screen-recorder; satty; voxtype; tensaku; ttfx; a Nerd-patched JetBrains Mono. RPM specs are forked from the `agaspar/omedora-4` COPR, which already builds all of these for fedora-44-x86_64, so Tinkero owns its recipes and is not blocked by anyone else's release pace. The COPR project is `<fas-user>/tinkero`, created by the author (FAS account pending).

herdr, the agent CLIs (claude, codex, opencode, agy, copilot, crush, grok, pi, omp, ori, hermes, muse, cursor-agent), and optionally starship, lazygit and lazydocker are **not packaged**. They are installed through mise, exactly as Omarchy does it, and updated with `mise up`.

### 4.2 The `tinkero` RPM (vendored Omarchy tree plus shims)

`tinkero.spec` fetches the upstream Omarchy tag named in `upstream.lock` as a source tarball at build time, applies the patch set, and installs:

- the tree at `/usr/share/omarchy` (upstream's own path; `OMARCHY_PATH` defaults to it, and the `omarchy` skill teaches the agent that this directory is package-owned and read-only, which is exactly right under RPM);
- the `omarchy-*` commands on `PATH` (`/usr/bin`), so the CLI router, keybindings and shell IPC work unchanged;
- `/etc/skel` defaults from `config/` and `default/`, so new users are seeded the way upstream intends;
- the wayland session file installed as `/usr/share/wayland-sessions/tinkero.desktop` with `Name=Tinkero` and `Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop`;
- `/usr/share/uwsm/env.d/10-omarchy` exporting `OMARCHY_PATH`;
- the shims (4.3), the menu extension (4.4), the skill guides (4.5), the `tinkero-*` scripts (4.6, 4.7);
- the user systemd units from `default/systemd/user/`;
- the `omarchy.ttf` icon font and fontconfig snippet.

Not installed: `install/` beyond what `tinkero-provision` reuses, `migrations/`, `default/libalpm/hooks/`, `default/pacman/`, `default/limine/`, `default/snapper/`, the plymouth theme, the sddm theme.

The upstream tree is never copied into this repo. The repo holds only `upstream.lock`, the spec, the patches, and Tinkero's own files.

### 4.3 Shims (the whole patch set, kept tiny)

Each is a replacement script or a small patch, listed so the plan can enumerate them:

| Upstream | Tinkero behaviour |
|---|---|
| `omarchy-pkg-present <pkg>` | `rpm -q` against a name map (Arch name to Fedora name) |
| `omarchy-pkg-add`, `omarchy-pkg-install`, `omarchy-install-app`, `omarchy-tui-install` | map to `dnf install` or `flatpak install` via the same name map; unknown names print what to install by hand |
| `omarchy-pkg-aur-*`, `omarchy-update-aur-pkgs`, `omarchy-update-orphan-pkgs`, `omarchy-update-pacman*`, `omarchy-update-system-pkgs*` | exit 0 with a one-line notice |
| `omarchy-update` | prints "Tinkero updates through dnf upgrade and mise up; see tinkero-status" and exits |
| `omarchy-debug` | package inventory section uses `rpm -qa` |
| `omarchy-channel-*`, `omarchy-version-channel` | report "tinkero" |
| `bin/omarchy-agent-crash` and `default/agents/skills/diagnose-crash/SKILL.md` | debuginfod URL becomes `https://debuginfod.fedoraproject.org/` |
| `default/agents/skills/omarchy/SKILL.md` | package idiom line points at `fedora.md`; `/usr/share/omarchy` wording stays (still true) |
| `bin/omarchy-apply-lock` | writes a Fedora-shaped `/etc/pam.d/omarchy-lock-password` using `auth include system-auth` / `account include system-auth`, and the fingerprint variant only if `fprintd-list` shows enrolments |
| `omarchy-plymouth-*`, `omarchy-refresh-sddm`, `omarchy-install-*` for Arch-only apps | not installed |

Everything else in `bin/` ships unmodified.

### 4.4 Menu extension, not menu patches

Omarchy's menu is JSONC data with per-entry `when`, `checked`, `disabled` guards, and user extensions in `~/.config/omarchy/extensions/omarchy-menu.jsonc` override entries by id. Tinkero ships a system-level extension file that hides the Install submenus that only make sense on Arch (gaming, Windows VM, web apps, Docker databases, the Chromium fork) and remaps the ones worth keeping (AI desktop apps, editors, dictation) to Flatpak or dnf targets. Users' own extension files layer on top. This avoids patching upstream JSON and survives every upstream release.

### 4.5 Skill guides for the agent

The `omarchy` skill loads topic guides on demand from the same directory as `SKILL.md`. Tinkero adds two, symlinked into the harness skill directories by the same loop upstream uses:

- `fedora.md`: the host is Fedora; use `dnf` and `flatpak`, never `pacman`; PAM is `authselect`-managed; check SELinux denials with `ausearch -m AVC -ts recent`; run `restorecon -R` after copying into `/usr`; RPM Fusion for NVIDIA (`akmod-nvidia`); `firewall-cmd` not `ufw`; podman is the container default.
- `maintenance.md`: how to read `tinkero-status` output and what the safe action for each finding is (see 4.7).

### 4.6 Install flow

`install.sh` is the single entry point, idempotent, safe to rerun after upgrades, in two stages.

System stage (sudo): enable the Tinkero COPR and RPM Fusion; `dnf install tinkero` (pulls the whole stack as dependencies); `dnf versionlock add hyprland quickshell` at the versions in `upstream.lock`; run `omarchy-apply-lock` to write the PAM file; verify the GDM session entry is present. GDM is kept as the display manager; SDDM is not installed.

User stage (no sudo, run as the desktop user): `tinkero-provision`, which seeds `~/.config` from the packaged defaults without overwriting existing files, creates the mise stubs (upstream `install/user/mise.sh` and `omarchy-mise-install`), symlinks the skills into `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills`, `~/.gemini/config/skills`, `~/.hermes/skills` (upstream's loop from `omarchy-provision-user`), installs herdr through mise, enables the user units (`omarchy-crash-watch`, `omarchy-sleep-lock`, `omarchy-recover-internal-monitor`, `omarchy-fcitx5`, `bt-agent`, plus `tinkero-status.timer`), and runs the first `omarchy-theme-set`.

A second machine is the same one-line `curl | bash`, about ten minutes. Log out, pick "Tinkero" at GDM.

### 4.7 Maintenance model

Recurring work, by design:

- Weekly: `sudo dnf upgrade` and `mise up`. Nothing else.
- When wanted (monthly or less): bump `upstream.lock` to a newer Omarchy tag, rebase the patch set, unlock and bump Hyprland and Quickshell if that release moved. A pinned tree does not rot; nothing under it is rolling.
- Twice a year: Fedora major upgrade. Add the new chroot to the COPR (or wait for it) before upgrading.

`tinkero-status` prints a plain report: installed Hyprland and Quickshell versus `upstream.lock` and whether the versionlock holds; newest upstream Omarchy tag versus the pinned one, with that release's Hyprland requirement and any config migration notes; whether the COPR has a chroot for the next Fedora release; `mise outdated`; SELinux denials in the last seven days; whether the lock PAM file matches the template; pending dnf updates touching the desktop stack.

`maintenance.md` teaches the agent what each finding means and which actions are safe unattended (run `mise up`, report) versus which need a human (bump the lock, edit PAM). A weekly systemd user timer runs `tinkero-status`; if anything is actionable it sends one notification whose click launches the default agent with the maintenance skill, reusing Omarchy's crash-watch pattern (`omarchy-notification-send --exec omarchy-agent-prompt ...`).

The GitHub Actions workflow in the repo runs weekly: checks upstream tags, opens an issue when a new Omarchy release appears with its Hyprland requirement, and triggers COPR rebuilds when `upstream.lock` changes.

### 4.8 `upstream.lock`

The contract every other piece checks. Seed values at design time:

```
omarchy_tag=v4.0.4
hyprland=0.56.2
quickshell_commit=28771c7c74b42e20afca0b1b63980cb46515537c
quickshell=0.3.0
fedora=44
```

## 5. Repo layout

```
tinkero/
  README.md
  LICENSE                       MIT (compatible with Omarchy's MIT)
  upstream.lock
  install.sh
  specs/                        RPM specs: tinkero.spec + the COPR package specs
  patches/                      the shim patch set against the pinned tag
  shims/                        replacement omarchy-* scripts
  menu/omarchy-menu.jsonc       system-level menu extension
  skills/fedora.md
  skills/maintenance.md
  bin/tinkero-status
  bin/tinkero-provision
  systemd/tinkero-status.{service,timer}
  .github/workflows/            upstream watch, COPR trigger
  docs/research/omarchy-research.md
  docs/superpowers/specs/       this document
  docs/superpowers/plans/       implementation plans
```

## 6. Phases

The author chose to go straight to phase 2 rather than first setting up the agent layer under GNOME. Rationale: the tree ships the agent layer anyway, and the COPR builds are the long pole, so start them first. Phase 1's outcome becomes the first milestone inside phase 2.

- **Phase 2a, packages.** Create the COPR; fork the hypr stack, quickshell, uwsm, gpu-screen-recorder, satty, voxtype, tensaku, ttfx and nerd-font specs from omedora-4; get green builds for fedora-44-x86_64. Milestone: `dnf install hyprland quickshell uwsm` from the Tinkero COPR on a Fedora 44 machine.
- **Phase 2b, the tree.** `tinkero.spec`, shims, patch set, session file, PAM template, menu extension, `tinkero-provision`, `install.sh`. Milestone A: `Super+Shift+Ctrl+A` launches the default agent and the `omarchy` skill works, in a Tinkero session. Milestone B: bar, menu, notifications, lock screen, screenshots, clipboard and theme switching work; herdr opens on `Super+Ctrl+Return`; voxtype dictates on F9.
- **Phase 3, maintenance.** `tinkero-status`, the two skill guides, the timer, the GitHub Actions workflow, the versionlock. Milestone: the agent answers "anything needed?" correctly after a simulated upstream tag bump.
- **Phase 4, base for others.** Second-machine install test, documentation, then evaluate other distros (Debian and Ubuntu via a PPA or `.deb` set; the tree and shims are the same, only the package substrate changes).

## 7. Risks and mitigations

- **Hyprland currency.** Omarchy tracks new Hyprland releases within weeks and its Lua config is written against a specific version. Mitigation: `dnf versionlock` on hyprland and quickshell, bumped together with `upstream.lock`; the weekly workflow makes the drift visible.
- **Fedora major upgrades.** A COPR only serves the releases it was built for. Mitigation: `tinkero-status` warns when the next chroot is missing; owning the specs means a rebuild is hours, not waiting on someone else.
- **Lock screen PAM under SELinux.** Budget a day. GDM handles the login keyring, which removes the SDDM keyring problem entirely.
- **Upstream patch conflicts.** Keep the patch set tiny; push everything possible into shims (separate files), the menu extension and skill guides, none of which conflict with upstream changes.
- **Quickshell version.** Fedora main's 0.2.1 is very likely too old for the shell; build the pinned commit in the COPR.
- **Single upstream.** If Omarchy changes direction, the pinned tree keeps working indefinitely; the risk is losing new features, not losing the desktop.

Nothing here can brick the machine: GNOME stays installed, and a broken Tinkero session is fixed by logging into GNOME and downgrading or unlocking a package.

## 8. Open questions

- COPR project name and FAS username (author creating the account).
- Whether to keep Omarchy's `Super+Space` menu naming ("Omarchy menu") or rebrand visible strings to Tinkero; default is to leave upstream strings alone to keep the patch set small.
- Which AI desktop apps to remap to Flatpak in the menu extension versus drop.
- Whether the repo's default branch should be `main` (GitHub created `master`).

## 9. Decision log

All decisions from the 2026-09-16 and 2026-09-17 research session.

| Decision | Choice | Why |
|---|---|---|
| Base OS | Keep Fedora and Red Hat conventions; no Arch parts | Author's preference; SELinux, point releases, dnf |
| Approach | Vendor the real Omarchy tree at a pinned tag, patch the seams | Reimplementations go stale; upstream releases weekly |
| Delivery level | "Level 2": mutable Fedora Workstation, own COPR, `tinkero` RPM | `dnf install` must keep working; bootc rejected for now |
| Display manager | Keep GDM, do not install SDDM | GDM handles the login keyring; avoids PAM friction |
| Scope | Desktop core: Hyprland, shell, themes, capture, agent harness, herdr, voxtype | The three priorities plus the look; skip Omarchy's app catalogue |
| Agent CLIs and herdr | mise, not RPM | Distro-neutral, self-updating with `mise up`, same as upstream |
| Package specs | Fork from `agaspar/omedora-4` COPR into an owned COPR | Proven builds; not blocked by a one-person beta |
| Updates | `dnf upgrade` + `mise up`; tree bumps deliberate via `upstream.lock` | Low-maintenance requirement |
| Version pinning | `dnf versionlock` hyprland and quickshell | Prevents a COPR bump from breaking the pinned Lua config |
| Menu customization | Extension JSONC, not patches | Survives upstream updates |
| Agent guidance | `fedora.md` and `maintenance.md` guides added to the `omarchy` skill | Agent must know it is on Fedora; maintenance advisor |
| Advisor delivery | Weekly timer, notification, click launches default agent | Reuses Omarchy's crash-watch pattern |
| Repo | Public, `github.com/dromeropa/tinkero`, `~/Projects/tinkero` locally | COPR builds from a public repo; base for others |
| License | MIT | Compatible with Omarchy's MIT; author may change |
| Name | Tinkero, tin-KEH-ro | Coined; tinker plus a playful ending; explicitly not an "oma" name |
| Tagline | "a tinkerable desktop for Hyprland, bring your own distro" | Credits Hyprland; states the cross-distro ambition |
| Category | Desktop environment (Hyprland is the compositor) | Same relationship as GNOME to Mutter |
| Sequence | Straight to phase 2, COPR first | Builds are the long pole; the agent layer ships with the tree |

## 10. References

- `docs/research/omarchy-research.md` in this repo (sections 1 to 4 are the technical basis; 3.5 covers the existing ports; 4.6 is the recommendation that led here).
- Omarchy: https://github.com/omacom/omarchy (branch `quattro`), packaging at https://github.com/omacom/omarchy-pkgs, manual at https://omarchy.org/manual/.
- Omedora and its COPR: https://github.com/AndrewGaspar/omedora, https://copr.fedorainfracloud.org/coprs/agaspar/omedora-4/.
- Hyprland Lua config: https://hypr.land/news/update55/.
- herdr: https://github.com/herdrdev/herdr. voxtype: https://voxtype.io/.
