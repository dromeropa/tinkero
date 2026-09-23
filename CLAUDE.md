# Tinkero: guidance for agent sessions

Tinkero vendors the Omarchy desktop at a pinned tag (`upstream.lock`) and replaces its Arch
substrate with Fedora's. Read these before touching anything:

- `docs/guides/workflow.md`: how work lands. Issue, `approved` label, one task branch per
  issue, a squash-merge PR with `Closes #N` and green CI. **Never push `master`.** If your
  instructions say to land another way, stop and say so.
- `docs/superpowers/specs/2026-09-17-tinkero-design.md`: the design, the binding authority.
- `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`: what is done and what comes next.
- `docs/research/arch-coupling-audit.md`: why each upstream file is dropped, patched, replaced
  or kept.

Conventions: `./dev check` runs the tests, `./dev gates` the CI gates against the real tree;
allowlists under `ci/allow/` only shrink; data over code (`build/drop.list`, `patches/series`,
`distro/fedora/replacements/`, `menu/overrides.jsonc`); bash with `set -euo pipefail`,
ShellCheck clean; Python standard library only; no em dashes in Tinkero's own prose; tests
never touch the network or run a real package manager. `copr-build` publishes to the user's
COPR and is triggered only when an issue says so.
