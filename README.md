# Tinkero

**A tinkerable desktop for Hyprland, bring your own distro.**

Tinkero brings the desktop experience of [Omarchy](https://omarchy.org) (Hyprland tiling, the Quickshell shell and its plugin system, themes, and an agent as a first-class citizen) to distributions that are not Arch, starting with Fedora, without any of the Arch parts. It vendors the distro-neutral part of Omarchy at a pinned release and replaces the Arch substrate with the host distro's own packaging.

It is pronounced tin-KEH-ro. It is deliberately not an "omakase" project: Omarchy is the chef's choice, Tinkero is the kit you cook with.

## Status

Build under way; the roadmap is [`docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`](docs/superpowers/plans/2026-09-17-phase-2-roadmap.md) and the contribution loop is [`docs/guides/workflow.md`](docs/guides/workflow.md). See [`docs/superpowers/specs/2026-09-17-tinkero-design.md`](docs/superpowers/specs/2026-09-17-tinkero-design.md) for the architecture and the decision log, [`docs/research/omarchy-research.md`](docs/research/omarchy-research.md) for the research on Omarchy it is based on, [`docs/research/arch-coupling-audit.md`](docs/research/arch-coupling-audit.md) for the classified audit of the pinned upstream tag, and [`docs/spec-review.md`](docs/spec-review.md) for the review that led to revision 2.

## Principles

- Keep the host distro's conventions: dnf, RPM, SELinux enforcing, GDM, GRUB, firewalld, the stock kernel.
- Updates stay `tinkero-update`: `dnf upgrade`, `mise up`, `flatpak update`. Nothing rolls under you.
- Vendor upstream, do not rewrite it. Patches are shims, not surgery.
- The default agent is part of the desktop: it customizes it, builds plugins for it, and tells you when maintenance is due.

## License

MIT. Omarchy, which Tinkero packages, is MIT licensed by its authors.
