# How work lands in Tinkero

From 2026-09-23 the build runs through an issue loop with two human gates. This page is the
contract for people and for agent sessions alike. The design is in
`docs/superpowers/specs/2026-09-17-tinkero-design.md`; the plan sequence is in
`docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`.

## Where the build is

- Baseline: plans 2A and 2B and Phase 1 (the 25-package COPR set) landed on `master` at
  `fd68ce4` on 2026-09-23, as one fast-forward from the branch they grew on. That branch
  predates the loop; nothing is retro-fitted onto it.
- Done since: 2C (menu rewrite, 2026-09-23), 2E (provisioning and install, 2026-09-23) and 2D
  (branding, 2026-09-24).
- Then 2F (session integration, which makes the `tinkero` RPM installable), Phase 3
  (maintenance), each planned when the one before it has landed.

## The loop

1. **Plan.** A plan document under `docs/superpowers/plans/` is written from the spec
   (brainstorm, then the writing-plans skill). Each task is written so that its heading,
   Files block and final verification step lift straight into an issue.
2. **Issues.** One GitHub issue per task, body in three parts: **WHAT** (the change),
   **WHERE** (files or modules), **HOW TO VERIFY** (a command, test or behaviour that proves
   it is done). Dependencies are written as `blocked by #N` in the body. Issues carry a
   `size:*` and an `area:*` label from the vocabulary below.
3. **Approve.** Nothing is dispatched until Diego applies the `approved` label. A plan's
   issues are normally approved as a batch, in order.
4. **Dispatch.** A session is dispatched against one approved issue and works on its own
   task branch. Inside the session the plan's task is executed the usual way (implementer,
   task review, fix rounds, the Deviations line).
5. **Land.** A squash-merge PR whose description says `Closes #N`. The PR merges only with
   green CI. There is no direct push to `master`, by anyone, ever.

## Four adaptations for this repository

- **COPR builds are post-merge.** The 26 packages are registered against `master`, and a
  COPR build publishes to the user-facing repository, so it cannot be a PR check. An issue
  whose deliverable is "package X builds in COPR" (a spec bump, the first `tinkero` RPM)
  has two-stage verification: CI proves the spec parses, lints and produces an SRPM; the
  COPR build (`copr-build` workflow from `master`) is run after the merge and recorded on
  the issue, which is then closed by hand, not by `Closes #N`.
- **`upstream.lock` bumps are never `size:small`.** A tag bump touches `build/drop.list`,
  `patches/`, `distro/fedora/replacements/`, both allowlists and `menu/overrides.jsonc` at
  once, and its failures show only when `assemble` runs against the new tree. It is one
  plan-first issue with the bump checklist (audit, section 10) as its body.
- **Issues inside one plan land serially.** A plan's tasks share `tests/run`,
  `build/assemble`, the shrink-only allowlists and the plan's Deviations section. They are
  filed with `blocked by`, approved in order, and each lands before the next is dispatched.
  Different plans may run in parallel only where the roadmap says they are independent.
- **Squash-merge collapses the fix rounds.** The record of what a task's review found and
  how it was fixed therefore lives in the plan's `## Deviations` section (and the PR). A
  Deviations line, when anything deviated, is part of every task's definition of done.

## Labels

| Label | Meaning |
|---|---|
| `size:small` | one or two files, complete spec in the plan: cheap implementer, strong reviewer |
| `size:medium` | several files with integration concerns: standard implementer, strong reviewer |
| `size:large` | design judgement or a bump: plan-first lane, most capable models |
| `area:build` | `build/`, `.copr/`, `tinkero.spec.in`, `bin/tinkero-*`, the tree assembly |
| `area:specs` | `distro/fedora/specs/`, the COPR package set |
| `area:menu` | `menu/`, the default menu rewrite |
| `area:branding` | fonts, logos, wallpapers, `branding/` |
| `area:provision` | `tinkero-provision`, `install.sh`, dotfile handling |
| `area:session` | PAM, dconf profile, user units, the session file |
| `area:docs` | the spec, plans, guides, README |
| `area:ci` | `.github/workflows/`, `ci/` gates, `tests/run` |
| `approved` | Diego's yes to build; only he applies it |
| `blocked` | waits on another issue (the body names it) |

## Rules for agent sessions

- Work only on the issue you were dispatched for, on its task branch.
- Land through a PR against that issue (`Closes #N` in the description) and never push
  `master`. A session told to land any other way should stop and say so; it must not
  invent a workaround.
- `copr-build` publishes to the user's COPR: trigger it only when the issue says so.
- Commit trailers as the session's rules give them. No em dashes in Tinkero's prose.
- Never modify the `approved` label.
