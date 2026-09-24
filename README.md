# Tinkero

**A tinkerable desktop for Hyprland, bring your own distro.**

Tinkero brings the desktop experience of [Omarchy](https://omarchy.org) (Hyprland tiling, the Quickshell shell and its plugin system, themes, and an agent as a first-class citizen) to distributions that are not Arch, starting with Fedora, without any of the Arch parts. It vendors the distro-neutral part of Omarchy at a pinned release and replaces the Arch substrate with the host distro's own packaging.

It is pronounced tin-KEH-ro. It is deliberately not an "omakase" project: Omarchy is the chef's choice, Tinkero is the kit you cook with.

## Status

Build under way; the roadmap is [`docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`](docs/superpowers/plans/2026-09-17-phase-2-roadmap.md) and the contribution loop is [`docs/guides/workflow.md`](docs/guides/workflow.md). See [`docs/superpowers/specs/2026-09-17-tinkero-design.md`](docs/superpowers/specs/2026-09-17-tinkero-design.md) for the architecture and the decision log, [`docs/research/omarchy-research.md`](docs/research/omarchy-research.md) for the research on Omarchy it is based on, [`docs/research/arch-coupling-audit.md`](docs/research/arch-coupling-audit.md) for the classified audit of the pinned upstream tag, and [`docs/spec-review.md`](docs/spec-review.md) for the review that led to revision 2.

## Install

On Fedora 44 Workstation with GDM, as your own user:

    bash <(curl -fsSL https://raw.githubusercontent.com/dromeropa/tinkero/master/install.sh)

The script checks the host first (Fedora release, x86_64, GDM, no Hyprland from another repository), prints its plan and asks before each of its two stages: `sudo dnf copr enable dromero/tinkero` plus `sudo dnf install tinkero`, then `tinkero-provision`, which seeds Tinkero's configuration into your home directory without overwriting anything you already have. Log out and choose Tinkero at the login screen. `tinkero-provision --plan` shows what provisioning would do; `--reset <path>` restores a packaged default with a backup.

Until the first release is tagged, the URL above installs from `master`. Releases attach a pinned `install.sh`.

## Remove

`tinkero-provision --remove`, then `sudo dnf remove tinkero` and `sudo dnf copr remove dromero/tinkero`. Files you changed are listed and kept. Your GNOME session was never touched; logging into it is always a way back, and after a crash Hyprland starts in Safe Mode (`Super+M` leaves it).

## Principles

- Keep the host distro's conventions: dnf, RPM, SELinux enforcing, GDM, GRUB, firewalld, the stock kernel.
- Updates stay `tinkero-update`: `dnf upgrade`, `mise up`, `flatpak update`. Nothing rolls under you.
- Vendor upstream, do not rewrite it. Patches are shims, not surgery.
- The default agent is part of the desktop: it customizes it, builds plugins for it, and tells you when maintenance is due.

## Branding

Nothing on screen says or shows Omarchy: the mark, the wallpapers, the About screen and the menu are Tinkero's, generated at build time from `branding/` (a placeholder mark until the real one exists). Every command, path and plugin id keeps upstream's name, because they are identifiers, not branding. Tinkero is built on [Omarchy](https://omarchy.org) and says so in the About screen, in every plugin's author line and in this README; Omarchy's license ships in `/usr/share/licenses/tinkero/`.

## License

MIT. Omarchy, which Tinkero packages, is MIT licensed by its authors.
