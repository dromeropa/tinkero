# Phase 3 design: maintenance and release

**Status:** design for Phase 3, derived from the Tinkero design spec (`2026-09-17-tinkero-design.md`, revision 2.1) on 2026-10-01. The master spec stays the binding authority; this document works out sections 4.7, 4.11, 4.12, 7 and 8 to the level a plan needs and records the decisions the master spec leaves open. Where the two disagree, this document says so under "Decisions" and the master spec is amended when the plan that owns the change lands.
**Plans:** `docs/superpowers/plans/2026-10-01-phase-3a-tinkero-status.md`, `2026-10-01-phase-3b-release-archive.md`, `2026-10-01-phase-3c-bump-procedure-and-watches.md`, `2026-10-01-phase-3d-vm-smoke-test.md`.
**Scope source:** placeholder issue #11 (its body; the thread's comments are this design and the plan writers' briefs, kept there when the first planning session was interrupted), spec sections 4.7, 4.11, 7 (Phase 3) and 8 (item 6, Milestone D), and every "Phase 3" and "Bump checklist" line of `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, left there by Phase 1 and plans 2C to 2F.
**Depends on:** Phase 2 complete on `master` at `95bb8d4` (2A to 2F, the first COPR build of `tinkero`, the VM check re-run #37 passed 2026-09-29). Phase 3 adds no capability to the desktop: it is the plumbing that keeps a pinned tree current and makes a bad update reversible.

## 1. What Phase 3 delivers

The spec's Phase 3 line names four things; the roadmap's queue adds the fifth:

1. **`tinkero-status`** (spec 4.7): one command that reports what needs the user's or the packager's attention, as text or `--json`, with the exit status the spec fixes. Section 2.
2. **The release archive** (spec 4.11, roadmap "What creating the COPR project added"): every release's RPM set is downloaded from the COPR and attached to a GitHub release, with a pinned `install.sh`, because COPR's `auto_prune` cannot be turned off; `tinkero-status --rollback` prints the downgrade against it. Section 3.
3. **The bump checklist as a procedure** (spec 4.7, audit section 10, and the checklist lines plans 2C to 2F left in the roadmap): one guide in execution order, a report tool that produces the diffs the guide reads, and the checklist as the body of every bump issue. Exercised once for real when upstream tags a release after `v4.0.4`. Section 4.
4. **The weekly workflow** (spec 4.7): upstream watch, Qt watch, the gates and the lock check on a schedule. Section 5.
5. **The VM smoke test** (spec 8, item 6; roadmap "What executing 2F added"): sections 1, 3 and 4 of `docs/guides/phase-2f-vm-check.md`, plus the install and removal around them, as one unattended command. Section 6.

Added by this design, each argued under Decisions: a Fedora library for `tinkero-status` behind the distro seam (D2); validation of every token that comes from the network (D3); a release defined as a `tinkero` package version, cut by a dispatched workflow (D9, D10); the archive as one tarball that is a dnf repository (D11); the Qt watch opening an issue instead of rebuilding (D14); the smoke test as a release gate run from the packager's host (D17).

Not in Phase 3: the maintenance advisor (Phase 5; Phase 3 gives it `tinkero-status --json`); support for a second Fedora release (the lock's `fedora` key is single valued, and Fedora 45 Beta exists as this is written, so the twice-yearly duty of spec 4.7 arrives during Phase 3: it is its own issue, see section 10); a staging COPR (a COPR build still publishes to users before the smoke test runs, as today); source RPMs and debuginfo in the archive (D11); a smoke job on GitHub-hosted runners (D17); bare-metal checks (suspend-to-lock, fingerprint, the speaker tuning).

## 2. `tinkero-status`

### 2.1 Shape

`bin/tinkero-status`, bash, packaged by the existing `bin/tinkero-*` loop of `build/assemble` and the `%{_bindir}/tinkero-*` line of `%files`. It is the framework and the two host-neutral checks (`upstream`, `provision`). The checks that call `rpm`, `dnf`, the COPR, PAM or the audit log live in `distro/fedora/lib/status.sh`, installed to `/usr/share/tinkero/status.sh` beside `pkg.sh` and sourced at start (D2, spec 4.10). The library defines one function per check, `check_<id>`; the framework calls the functions that exist, in the fixed order of 2.2, and reports a check whose function is missing as `skipped` ("not implemented for this host").

Invocations:

| Invocation | Does |
|---|---|
| `tinkero-status` | runs every check, prints the text report |
| `tinkero-status --json` | the same run as one JSON document on stdout, nothing else on stdout |
| `tinkero-status --rollback` | prints how to go back to the release before the installed one (2.5); runs no checks |
| `tinkero-status -h`, `--help` | usage, exit 0; an unknown option is exit 2 with usage on stderr |

A check function calls `result STATUS SUMMARY [FIX]` exactly once and may call `datum KEY VALUE` any number of times (strings, for the JSON `data` object). `STATUS` is one of:

| Status | Meaning | Effect on the exit status |
|---|---|---|
| `ok` | checked, nothing to do | none |
| `info` | a fact worth a line, nothing to do | none |
| `action` | something a command fixes; `FIX` names it | 1 |
| `skipped` | not checked, and the summary says why and how to get it checked | none |
| `failed` | the check could not run (no network, a tool missing, output it does not understand) | 2 |

### 2.2 The checks

In report order. "Lock" is `/usr/share/tinkero/upstream.lock`, parsed, never sourced.

| Id | Reports | Reads | Rules |
|---|---|---|---|
| `versions` | installed `tinkero`, `hyprland`, `quickshell` against the lock; the host's Fedora release against the lock's `fedora` | `rpm -q --qf`, the lock, `/etc/os-release` | `action` when a package is missing, Hyprland is outside `[hyprland, next minor)`, Quickshell's version differs from `quickshell` or its release is below `quickshell_release`, or `VERSION_ID` differs from `fedora`; fix `tinkero-update`. RPM already enforces the pins (spec 4.2), so this is `ok` on any host nobody forced; the line is still the first thing a bug report needs |
| `qt` | whether a Quickshell rebuild is pending (spec 4.1) | `rpm -q --requires quickshell` for the `Qt_6.N_PRIVATE_API` it was built against; `dnf -q repoquery --latest-limit=1 --queryformat '%{version}\n' qt6-qtbase` for the Qt minor Fedora offers; `dnf -q repoquery --upgrades quickshell` | `ok` when the two minors agree. When Fedora's is newer: `action` with fix `tinkero-update` if a Quickshell upgrade is available, otherwise `action` "Fedora offers Qt 6.M, the COPR's quickshell is built for Qt 6.N; dnf holds Qt back until it is rebuilt" with the packager's fix (section 5). `failed` when dnf fails (D5) |
| `upstream` | newest upstream release against `omarchy_tag` | `curl` of `<upstream API>/releases/latest`, `jq` for `tag_name` and `published_at` | the tag must match `^v[0-9]+\.[0-9]+\.[0-9]+$` and the date `^[0-9]{4}-[0-9]{2}-[0-9]{2}`, else `failed` (D3). `action` when the tag sorts after the pin (`sort -V`), naming tag and date (Milestone D); else `ok`. No Hyprland requirement is claimed or guessed (D4) |
| `chroot` | whether the COPR serves the next Fedora release | `curl` of the COPR project API (`chroot_repos`), `curl` of Fedora's `releases.json` | `ok` when `fedora-<N+1>-x86_64` is a chroot; `action` when it is not and `releases.json` lists version `<N+1>` exactly (a final release, not "45 Beta"): "do not upgrade this machine to Fedora N+1 yet"; `info` when it is not and N+1 is not released (D8) |
| `package` | `rpm -V tinkero` | `rpm` | `ok` on no output; `info` when every line is a `c` (configuration) file, counting them; `action` otherwise, fix `sudo dnf reinstall tinkero` |
| `pam` | lock-screen PAM drift (spec 4.8) | `tinkero-pam-sync --check` | exit 0 is `ok`, exit 1 is `action` with its one line and fix `sudo tinkero-pam-sync`, anything else is `failed`. Both PAM files are `%ghost`, so `rpm -V` never sees them (2F design D9) |
| `provision` | provisioning state (spec 4.6) | `~/.local/state/tinkero/{seeded.tsv,release,done/}`, `tinkero-provision --plan`, `/usr/share/tinkero/config-notes/<tag>.md` | `skipped` as root (D7). `action`, fix `tinkero-provision`, when there is no state, when `release` differs from `<omarchy_tag>-<tinkero_rev>`, when the plan has `seed`, `update` or `delete` decisions, or when the tag has notes and `done/notes-<tag>` is missing. Conflicts, moved defaults and orphans are counted in the summary and never raise the status (D6) |
| `selinux` | AVC denials in the last seven days | `ausearch -m AVC -ts week-ago` | `skipped` unless root, with `sudo tinkero-status` as the way to get it (spec 4.7: never imply zero). As root: `action` when a denial's `comm` is one of the desktop's processes (a list in the library: `quickshell`, `qs`, `Hyprland`, `hypr*`, `omarchy-*`, `tinkero-*`, `uwsm*`), fix `sudo ausearch -m AVC -ts week-ago`; else `ok` with the total |

### 2.3 Output

Text, one line per check, the fix on its own indented line, a header and a footer:

```
tinkero-status: Tinkero v4.0.4-3 on Fedora 44
ok       versions   tinkero 4.0.4-3.fc44, hyprland 0.56.2-1.fc44, quickshell 0.3.0^20.git28771c7-2.fc44
ok       qt         quickshell is built for Qt 6.11, which is what Fedora offers
action   upstream   v4.0.5 (2026-10-06) is newer than the pinned v4.0.4
         fix: packager: docs/guides/bump-checklist.md
info     chroot     Fedora 45 is not released; the COPR has no chroot for it yet
ok       package    rpm -V tinkero: clean
ok       pam        current: wrapped
ok       provision  provisioned for v4.0.4-3; 0 pending, 2 conflicts, 0 moved defaults
skipped  selinux    needs root: sudo tinkero-status
tinkero-status: 1 to act on, 0 failed, 1 skipped
```

`--json`, built with `jq -n` so every string is escaped by jq, never by hand:

```json
{"schema": 1, "release": "v4.0.4-3", "fedora": "44", "exit": 1,
 "checks": [{"id": "upstream", "status": "action", "summary": "v4.0.5 (2026-10-06) is newer than the pinned v4.0.4",
             "fix": "packager: docs/guides/bump-checklist.md", "data": {"pinned": "v4.0.4", "newest": "v4.0.5", "date": "2026-10-06"}}]}
```

`schema` is 1 and changes whenever a consumer would have to change (spec 4.7). `fix` is `null` when there is none. Every summary is a template filled with local facts or with network tokens that passed their pattern (D3); no check copies a line of fetched text into its output.

### 2.4 Exit status

0 when no check is `action` or `failed`; 1 when at least one is `action` and none `failed`; 2 when any is `failed`, because a report with a hole must not read as a complete one (D6). The JSON carries every check's own status, so a consumer that wants "actionable despite a failed network check" reads the list.

### 2.5 `--rollback`

Spec 4.11's rollback, printed for this machine. The installed release is `<omarchy_tag>-<tinkero_rev>` from the lock (the tag form of 3.1). The mode fetches `<releases API>/releases?per_page=100`, keeps the `tag_name` values matching `^v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$`, and takes the newest that sorts before the installed one (D13). It prints, with `<prev>` that tag and `<N>` the lock's `fedora`:

```
tinkero-status: the release before v4.0.4-3 is v4.0.4-2. To go back to it:
  1. Log into GNOME (your GNOME session is untouched).
  2. sudo dnf downgrade tinkero hyprland quickshell
     This is enough while the COPR still has the older builds. If dnf has nothing to downgrade to:
  3. curl -fLO https://github.com/dromeropa/tinkero/releases/download/v4.0.4-2/tinkero-4.0.4-2.fc44-rpms.tar
     tar -xf tinkero-4.0.4-2.fc44-rpms.tar -C "$HOME"
     sudo dnf downgrade --repofrompath=tinkero-rollback,"$HOME/tinkero-4.0.4-2.fc44-rpms" tinkero hyprland quickshell
```

With no earlier release it says so and exits 0; when the list cannot be fetched it points at the releases page and exits 2.

### 2.6 Seams and tests

`TINKERO_SHARE` (default `/usr/share/tinkero`), `TINKERO_LOCK` (default `$TINKERO_SHARE/upstream.lock`), `TINKERO_STATUS_LIB` (default `$TINKERO_SHARE/status.sh`), `TINKERO_EUID` (the existing convention), `TINKERO_OS_RELEASE`, `XDG_STATE_HOME`, and four URLs: `TINKERO_UPSTREAM_API` (default `https://api.github.com/repos/omacom/omarchy`), `TINKERO_RELEASES_API` (default `https://api.github.com/repos/dromeropa/tinkero`), `TINKERO_COPR_API` (default `https://copr.fedorainfracloud.org/api_3/project?ownername=dromero&projectname=tinkero`), `TINKERO_FEDORA_RELEASES` (default `https://fedoraproject.org/releases.json`). Every external command (`rpm`, `dnf`, `curl`, `ausearch`, `tinkero-pam-sync`, `tinkero-provision`) is a stub on `PATH` in `tests/test-status.sh`; `jq` is the real one (a hard requirement of the package, spec 6, added to CI's tool list by plan 3A, and a skip line in `./dev check` on a developer machine without it). Milestone D's first half, "after a simulated upstream tag, `tinkero-status` exits 1 and names it", is a test case, and on a real machine is `TINKERO_UPSTREAM_API=file:///path/to/fixture tinkero-status`.

`tinkero.spec.in` gains `Requires: curl`. Adding `tinkero-status` and `status.sh` changes the package's content, so plan 3A bumps `tinkero_rev` to 3 (spec 4.12, D22).

## 3. The release archive

### 3.1 What a release is

A release is one `tinkero` package version, together with the newest build of every other package of the set at that moment. Its git tag is `v<Version>-<Release>` of the `tinkero` RPM without the dist tag, which is `<omarchy_tag>-<tinkero_rev>` from the lock: `v4.0.4-2` today. `tinkero-provision` already writes the same string to `~/.local/state/tinkero/release`. A change to the set that should be a rollback point (a Hyprland point release, a `herdr` bump) bumps `tinkero_rev` and becomes a release; a Quickshell rebuild for Qt does not need one, because the build it replaces cannot be installed beside the new Qt anyway (D9).

The order of events is spec 4.7's: the PR merges; the operator dispatches `copr-build`; the VM smoke test (section 6) passes against the COPR's build; the operator dispatches `release`. A COPR build therefore reaches users before its release exists; the release is the archive and the pinned installer, not the publication.

### 3.2 `build/tinkero-release`

Bash, beside `build/tinkero-copr`, never packaged. Subcommands:

| Subcommand | Does |
|---|---|
| `tag` | prints the release tag from the lock |
| `list` | prints the COPR's newest binary packages, one per line: `name<TAB>version<TAB>release<TAB>arch<TAB>source`, where `source` is the source package's `name-version-release`. From `dnf -q repoquery --repofrompath=tinkero-release,<repo URL> --repo=tinkero-release --latest-limit=1 --arch=x86_64,noarch --queryformat ...`, without the `-debuginfo` and `-debugsource` packages (D11, D12) |
| `verify LIST` | checks a list against the repository at this commit and exits 1 naming every mismatch: (1) each package of `distro/fedora/specs/build-order.txt` is the source of at least one line; (2) each source's version and release equal its spec's (`rpmspec -q --srpm` with `dist` set to `.fc<fedora>`; for `tinkero`, the lock's `<tag without v>-<tinkero_rev>.fc<fedora>`), so a spec that was merged but never built stops the release; (3) the lock's pins hold: Hyprland inside `[hyprland, next minor)`, Quickshell's version equal to `quickshell` and its release at least `quickshell_release` (spec 8, item 5: the lock check; D24) |
| `fetch LIST DEST` | `dnf download` of exactly the listed packages into `DEST`, then a check that every listed file is there |
| `pack DEST OUT` | `createrepo_c DEST`; writes `OUT/tinkero-<version>-<rev>.fc<N>-rpms.tar` (one top-level directory of the same name without `.tar`, holding the RPMs and `repodata/`), `OUT/RPMS.txt` (the list, human readable) and `OUT/SHA256SUMS` |
| `install-sh OUT` | writes `OUT/install.sh`: the repository's `install.sh` with `TINKERO_REF=${TINKERO_REF:-master}` rewritten to the release tag and `TINKERO_FEDORA=<N>` rewritten to the lock's `fedora` (2E design D7). Each of the two lines must match exactly once, and the result must pass `bash -n`, or the command fails |

Environment: `TINKERO_COPR_PROJECT` (default `dromero/tinkero`, as `tinkero-copr`), `TINKERO_RELEASE_REPO` (default `https://download.copr.fedorainfracloud.org/results/<project>/fedora-<N>-x86_64/`), `TINKERO_ROOT`, `TINKERO_LOCK`. `tests/test-release.sh` runs every subcommand against stub `dnf`, `rpmspec` and `createrepo_c`; `tar` and `sha256sum` are the real ones.

Measured on 2026-10-01 with `list`'s own query: the COPR repository holds 107 packages in 1278 MiB with sources, debuginfo and the superseded builds; the binary set `list` selects is 36 packages (from the 26 sources of `build-order.txt`) in 244 MiB, under GitHub's 2 GiB limit for one release asset.

### 3.3 The `release` workflow

`.github/workflows/release.yml`, `workflow_dispatch` only, `permissions: contents: write`, in the `fedora:44` container like `ci`. Inputs: `smoke` (required: the URL of the issue or comment recording the VM smoke run for this build; it must start with `https://github.com/dromeropa/tinkero/`) and `dry_run` (default false: do everything except create the release, and upload the assets as a workflow artifact). Steps: refuse any ref but `master`; `tag=$(build/tinkero-release tag)`; refuse when that release already exists; `list`, `verify`, `fetch`; `ci/check-rpm` on the downloaded `tinkero` RPM and `./dev gates-at` on its payload (2F left both for this); `pack`; `install-sh`; then `gh release create "$tag" --target "$GITHUB_SHA"` with the tarball, `install.sh`, `SHA256SUMS` and `RPMS.txt`, and notes generated locally (the tag, the smoke URL, the package table, `tinkero-status --rollback` as the way back). The workflow creates the git tag by creating the release; nobody pushes a tag by hand (D10).

The YAML stays thin: every decision is in `build/tinkero-release`, which is what the tests cover. The workflow itself can only be proven after the merge (workflow guide, adaptation 1), so its first run is the plan's last issue: a `dry_run` dispatch, then the first real release, then the rollback drill of 3.4.

### 3.4 Assets and the rollback

| Asset | Content |
|---|---|
| `tinkero-<version>-<rev>.fc<N>-rpms.tar` | the binary RPM set as a dnf repository |
| `install.sh` | pinned to the tag and the Fedora release |
| `SHA256SUMS` | of the two files above |
| `RPMS.txt` | the package list |

The README's install line becomes `bash <(curl -fsSL https://github.com/dromeropa/tinkero/releases/latest/download/install.sh)` once the first release exists, which is spec 4.6's "fetched from a tagged release URL".

The rollback command of 2.5 resolves the downgrade inside the extracted repository, so the older `hyprutils`, `aquamarine` and the rest come with the three named packages. Two things about it cannot be proven without a host that has two releases to move between, and are the rollback drill's job: that dnf5 downgrades the dependencies it needs to without `--allowerasing`, and that the COPR's signing key, already in the RPM keyring from the install, satisfies `gpgcheck` for a `--repofrompath` repository. The drill records the command that worked; if it differs, `tinkero-status --rollback` is corrected in a follow-up issue.

## 4. The bump procedure

### 4.1 `build/bump-report`

`build/bump-report OLD NEW`, each argument an upstream tarball or an unpacked tree. It prints one section per row of `build/bump-watch.tsv` (`section<TAB>kind<TAB>argument`), each headed `== <section> (<n>)` and listing `A`, `D` or `M` and a path. Kinds:

| Kind | Reports |
|---|---|
| `paths` | files added, removed or changed under the path or glob |
| `added` | files added under the path |
| `grep` | files that match the ERE in `NEW` and are new or changed |
| `menu-ids` | row ids added or removed in the menu file |
| `patch-targets` | files that a patch in `patches/series` touches and that changed upstream: the rebases to expect |
| `replaced` | upstream's own versions of the scripts under `distro/fedora/replacements/` that changed: behaviour the replacement may need to follow |

The first watch list, one row per line the checklist has carried since 2B:

| Section | Kind | Argument | From |
|---|---|---|---|
| provisioning chain | `paths` | `install/user`, `bin/omarchy-provision-user`, `bin/omarchy-provision-first-run` | audit 10, items 2 and 3 |
| seeded configuration | `paths` | `config`, `applications` | 2E queue |
| agent skills | `paths` | `default/agents` | audit 10, item 3 |
| menu rows | `menu-ids` | `default/omarchy/omarchy-menu.jsonc` | audit 10, item 4; 2C queue |
| migrations | `added` | `migrations` | audit 10, item 5 |
| user units | `paths` | `default/systemd/user` | 2F queue |
| patched files | `patch-targets` | | spec 4.7 |
| replaced scripts | `replaced` | | spec 4.3 |
| privilege | `grep` | `\b(sudo|pkexec)\b` over `bin` and `install` | spec 5, rule 2 |

It exits 0 when it ran and 2 on bad arguments; it is a report, not a gate. What the gates already find on the assembled payload (new Arch tokens, references to dropped commands, unmapped package names, branding, wallpapers, unit properties) is not repeated here. `tests/test-bump-report.sh` runs it on two fixture trees.

### 4.2 The guide

`docs/guides/bump-checklist.md` is the procedure in the order it is executed, every step a checkbox with its command and what to read in the output. The audit's section 10 and the roadmap's checklist lines are folded into it, and section 10 becomes a pointer. Its stages:

1. **Lock.** Keep the old tarball's path, set `omarchy_tag` and `omarchy_commit`, remove `omarchy_sha256`, `./dev lock`, set `tinkero_rev=1`.
2. **Report.** `build/bump-report`, and for each section the decision it asks for: a keep, adapt or drop row in the audit's section 6 for each new provisioning step; `provision/skip.list` for a new file shared with GNOME; `config-notes/<tag>.md` from the config-only migrations; `provision/session-units.list` and a `PartOf` drop-in for a new unit; the read-in-full of everything the privilege section names.
3. **Assemble until the gates pass.** `build/drop.list`; the patches in `patches/series` order, 0011 included; the replacements; `menu/apply-overrides` and `expect_rows`; branding (`inventory-images`, the contact sheet's `review` rows, `apply-strings`' report, `rewrite-manifests`' counts, the gate, `U+E900`); `ci/gate-session-units`; the name map. `./dev check` and `./dev gates` green; an allowlist grows only with a recorded reason.
4. **Provisioning.** `tinkero-provision --plan` on the real payload; the new `seed` count into the 2E design's section 8.
5. **The package set.** The Hyprland and Quickshell pins in the lock from what upstream built the tag against; `quickshell-pam-acct-mgmt.patch` rebased onto the new snapshot, or dropped once upstream calls `pam_acct_mgmt`; each spec's version against its upstream; `build-order.txt`.
6. **Docs.** The audit's counts and sections, the master spec's counts, the roadmap.
7. **After the merge.** `copr-build` for the changed packages in order, then `tinkero`; the VM smoke test; the release; `dnf upgrade` on a second machine and `tinkero-provision`'s report there (Milestone D).

A closing section lists the known items for the first bump past `v4.0.4`: the audit's section 10 item 6 (`omarchy-install-chromium-claude` and its hook, the `gemini` to `agy` rename, the `ori` stub, `~/.gemini/config/skills`), `herdr` from `0.8.0^13.git0766aa5` to 0.9.1, and whether upstream `voxtype` builds without Omedora's fork.

The checkbox part sits between two marker comments, so that the upstream watch (section 5) can lift it into the bump issue's body. That is workflow guide adaptation 2, "one plan-first issue with the bump checklist as its body", made mechanical (D15, D16).

### 4.3 The first real bump

Milestone D's second half. Upstream's newest release is still `v4.0.4` (checked 2026-09-30), so the bump cannot be planned as tasks with code now. It is one `size:large` issue, filed with the others and blocked by them and by upstream; the watch comments on it when the tag appears. Done means: the guide was followed end to end and corrected where it was wrong, CI passed, the release was cut, and a second machine took tree and pins in one transaction.

## 5. The weekly workflow

`.github/workflows/weekly.yml`: `schedule` (Mondays) and `workflow_dispatch`, two jobs in the `fedora:44` container.

**`gates`** (`contents: read`): `./dev check`, `./dev gates`, then `build/tinkero-release list` and `verify` on the result. The first two catch what a floating container and a moving Fedora break while nobody pushes; the third is the lock check of spec 8, item 5, which cannot run on a push because COPR builds are post-merge (D24).

**`watch`** (`issues: write`): two scripts, each tested against a stub `gh`.

- `ci/watch-upstream` reads upstream's newest release tag with `gh api`, applies the pattern of 2.2, and compares it with the lock. When it is newer: if an open issue is titled exactly `Bump upstream to <tag>`, nothing; if another open issue's title starts with `Bump upstream to `, one comment on it naming the tag, unless a comment already names it; otherwise `gh issue create` with that title, labels `size:large` and `area:build`, and a body made of a fixed header and the guide's checklist. The tag is the only fetched token that reaches the issue (D15).
- `ci/watch-qt` compares Fedora's Qt minor with the one the COPR's Quickshell requires, by the same two `dnf repoquery` calls as 2.2 but against the repositories rather than the installed package. When they differ and no open issue has the title, it opens `Rebuild quickshell for Qt <6.M>` with labels `size:small` and `area:specs`; the body says to bump `Release:` in `distro/fedora/specs/quickshell.spec` and dispatch `copr-build` for `quickshell` after the merge (D14).

Neither script applies `approved`. For D14's one-line fix to be one line, `tests/test-specs.sh` stops requiring `quickshell.spec`'s `Release:` to equal the lock's `quickshell_release` and requires it to be at least that; spec 4.12's sentence is amended with it. A test also pins the workflow's container image to the lock's `fedora`. GitHub disables a scheduled workflow after sixty days without repository activity; the guide says how to re-enable it.

## 6. The VM smoke test

### 6.1 What it checks

One command, `./dev vm-smoke`, which runs `ci/vm-smoke/run`. It covers spec 8's item 6 and the automatable sections of the 2F guide:

| Stage | Source | Checks |
|---|---|---|
| `base` | guide 1 | builds the base domain once, unattended (6.2) |
| `baseline` | guide 2 | a clone boots into GNOME; the canary key and the dark appearance are set; snapshot `0-baseline` |
| `install` | spec 8.6, guide 2, 2E queue | `install.sh --yes` from the checkout, which is what proves dnf5's `%{from_repo}` tag and `dnf copr enable -y`; the guide's post-install checks (PAM file owner, variant, label, the tally entry, the seeded dconf database); the snapshot diff is clean |
| `users` | spec 8.6 | a second account with dotfiles already in place: `tinkero-provision --plan` reports them as conflicts and a run leaves them byte for byte |
| `session` | spec 8.6, guide 3 | after a reboot, in the Tinkero session: `hyprctl configerrors` is empty, `omarchy-shell shell ping` answers, the menu model loads, `DCONF_PROFILE`, the listed units, no `[Install]` in the package's units, the inhibitor, the canary key, the tally file, the power key leaves the VM running; `tinkero-status` exits 0 or 1 |
| `lock` | guide 3 | rounds 1, 2, 4 and 5: first-try unlock, two failures counted once each and cleared, on `wrapped` and then on `plain` after `authselect enable-feature with-faillock`; no AVC since boot; round 3 (ten failures and the two-minute wait) only with `--lockout` |
| `gnome` | guide 4, spec 8 | the three cycles (menu logout, `loginctl terminate-session`, a killed compositor), with lingering on: each GNOME snapshot diffs clean against the baseline, no service still carries `DCONF_PROFILE`, no Tinkero unit is active |
| `reinstall` | spec 8.6 | a second `install.sh --yes` changes nothing: no transaction, `current: wrapped`, an all-`current` plan |
| `remove` | guide 6 | `tinkero-provision --remove`, `dnf remove`: no PAM files, no session database, the snapshot diff is clean |

### 6.2 The base

`ci/vm-smoke/run base` builds `tinkero-smoke-base-f<N>` from the Fedora Cloud Base image, pinned by URL and sha256 in `ci/vm-smoke/image.lock`, with `virt-install --import --cloud-init`: the user-data (`ci/vm-smoke/cloud-init.yaml`) creates the two accounts with known passwords, installs an SSH key generated for this host under `~/.cache/tinkero-smoke/`, gives the test account password-less `sudo`, installs the Workstation environment group, enables GDM with a timed login, upgrades and powers off. The base is never booted again; each run clones it (`virt-clone`), as the guide clones its clean checkpoint. The Workstation ISO is not used: its installer needs a person, and it hung at "finalization" in #27 (D18).

### 6.3 The driver and the guest script

`ci/vm-smoke/run [--stages LIST] [--keep] [--lockout]` is the host side: `virsh` and `virt-clone` under `qemu:///session`, SSH through the guide's passt port forward, `virsh send-key` for the power key and for typing at the lock screen (the passwords are lower-case letters and digits so that every character is one key). It copies `ci/vm-smoke/guest` and the checkout's `install.sh` into the VM and runs the guest script's subcommands over SSH.

`ci/vm-smoke/guest` is the guest side: `snap NAME` (the guide's `snap.sh`), `check STAGE` (the assertions of 6.1's table for that stage), and the session controls. It prints TAP lines, so its logic is what `tests/test-vm-smoke.sh` runs against stub commands; the driver is tested in a dry-run mode that prints its `virsh` and `ssh` commands (`TINKERO_SMOKE_DRY_RUN=1`, as `tinkero-copr` does).

Sessions are started by GDM itself: the base has a five-second timed login, and the driver sets which session comes next through AccountsService before it ends the current one, so the Tinkero session is entered through GDM and uwsm exactly as a user enters it, and the user manager survives between sessions, which is the hard case of spec 4.9. Commands that must see the session's environment run through `systemd-run --user --wait --pipe`.

Graphics are the guide's: `--video virtio,accel3d=yes --graphics spice,gl.enable=yes,listen=none`, with `TINKERO_SMOKE_RENDERNODE` for an Optimus host. Nobody needs to watch; `virt-viewer --attach tinkero-smoke` shows it.

Results go to `.cache/vm-smoke/<UTC timestamp>/`: `report.tap`, the snapshots and their diffs, the install log, the journal excerpts. Exit 0 when every line is `ok`, 1 when any is not, 2 when the VM could not be built or reached. `--stages` re-runs chosen stages on the kept clone; `--keep` leaves it for a look.

### 6.4 What stays manual

The Milestone B lines that need eyes (guide 5); the fingerprint reader; anything bare metal. `docs/guides/vm-smoke.md` says how to run the test and what it does not cover, and the 2F guide gains a pointer to it and stays the manual fallback.

### 6.5 Where it runs, and what that leaves unproven

On the packager's host, after the COPR build and before the release (D17). The release workflow's `smoke` input is where its record is named. No agent session has libvirt, so the driver is written without a VM to run it on: the plan's hermetic tests cover the guest script's logic and the driver's command sequence, and the first run on the operator's host is the plan's last issue, recorded by hand with every correction, as #27 and #37 were for the guide. Three mechanisms are unproven until then, and each has its fallback: the cloud image base (fallback: the guide's clean checkpoint with SSH enabled by hand, named by `TINKERO_SMOKE_BASE`), the timed login with the AccountsService session switch (fallback: the `gnome` stage is dropped from the automatic run and stays the guide's section 4), and typing at the lock through `virsh send-key` (fallback: the `lock` stage stays the guide's section 3). A stage that falls back is removed from the default `--stages` list with the reason in the guide, so the rest still runs unattended.

## 7. Plans and order

| Plan | Delivers | Issues |
|---|---|---|
| **3A** `tinkero-status` | `bin/tinkero-status`, `distro/fedora/lib/status.sh`, `tests/test-status.sh`, packaging, `tinkero_rev` 3, docs | one orchestrated issue; the COPR build of `tinkero` 4.0.4-3 and the first run on an installed host, post-merge, by hand |
| **3B** release archive | `build/tinkero-release`, `tests/test-release.sh`, `release.yml`, `docs/guides/release.md`, docs | one orchestrated issue; the first release and the rollback drill, post-merge, by hand |
| **3C** bump procedure and watches | `build/bump-report`, `build/bump-watch.tsv`, `docs/guides/bump-checklist.md`, `ci/watch-upstream`, `ci/watch-qt`, `weekly.yml`, the relaxed Quickshell release test, docs | one orchestrated issue; the first weekly run, post-merge, by hand; the first real bump, `size:large`, blocked |
| **3D** VM smoke test | `ci/vm-smoke/{run,guest,cloud-init.yaml,image.lock}`, `tests/test-vm-smoke.sh`, `./dev vm-smoke`, `docs/guides/vm-smoke.md`, docs | one orchestrated issue; the first run on the operator's host, by hand |

3A, 3B and 3D do not depend on each other's code; 3C needs 3B's `list` and `verify`. All four edit `.github/workflows/ci.yml`'s ShellCheck list and the same documents, so they land serially, 3A, 3B, 3C, 3D (workflow guide, adaptation 3, applied across the phase); 3D may be built in parallel with 3B or 3C if its branch is rebased before its PR merges. The first release needs 3B and a smoke record (3D's first run, or a manual pass of the 2F guide for the same package version). Because 3A lands first and takes `tinkero_rev` to 3, that release is `v4.0.4-3`: it also needs the COPR build of `tinkero` 4.0.4-3, which is 3A's post-merge issue (workflow guide, adaptation 1), and the #37 check, made on an earlier build, cannot be its smoke record. The first real bump needs all four.

Milestone D maps to: a test in 3A (the simulated tag), and the first real bump issue (the rest).

## 8. Decisions taken by this design

Each is a call the master spec leaves open or states in a form that cannot be built literally. They are listed so the operator can veto any of them at the approval gate; each says how to reverse it.

- **D1, Phase 3 is four plans and one bump issue.** The spec lists four deliverables as one phase; they share no code, and the workflow guide lands a plan's tasks serially. Four plans keep each PR reviewable. Reversal: merge the issue bodies into one.
- **D2, `tinkero-status` is a host-neutral framework plus `distro/fedora/lib/status.sh`.** Spec 4.10 puts "`tinkero-status`'s framework" on the neutral side of the seam, and six of the eight checks call `rpm`, `dnf`, the COPR or PAM. Reversal: inline the library.
- **D3, a token from the network is printed only after it matches a fixed pattern.** Spec 4.7 has `tinkero-status` report the newest upstream tag, and spec 5 rule 1 has it emit "locally computed facts only"; a tag name is text its author chose. The rule that satisfies both: tags and dates must match the patterns of 2.2 and 2.5, everything else fetched is reduced to a boolean or a number, and nothing that fails its pattern is echoed, even in the error. The same rule governs the issue the upstream watch opens. Reversal: none wanted; Phase 5's precondition depends on it.
- **D4, no Hyprland heuristic.** Spec 4.7 allows reporting what upstream's packaging repository built against, labelled as a heuristic. It would mean fetching and parsing a second repository for a number the bump checklist reads anyway. Reversal: a ninth check.
- **D5, "held back" is the Qt comparison, asked of `dnf repoquery`.** Spec 4.7 wants "whether `dnf upgrade` is currently holding anything back", which can only be read from `dnf upgrade`'s prose. The symptom the spec cares about has an exact cause, the Qt private API version, and both sides of it are queryable with a query format Tinkero chooses. Ordinary pending upgrades are dnf's and GNOME Software's to report (spec-review's cut list says the same). Reversal: add a check that parses `dnf upgrade --assumeno`.
- **D6, exit 2 outranks exit 1, and standing choices are not actionable.** The spec gives the three codes but not their precedence. A conflict or a moved default is the user's own file kept on purpose; counting it as actionable would make exit 1 permanent on every machine with a pre-existing `foot.ini`. A newer upstream tag is actionable because Milestone D says so. Reversal: one word per row of 2.2.
- **D7, `tinkero-status` never elevates and never drops privileges.** Spec 4.7 runs the SELinux check "only when run with `sudo`", and `tinkero-provision` refuses to run as root. So the user's run skips `selinux` and says how to get it, and root's run skips `provision`. Reversal: have root's run call `runuser -u "$SUDO_USER"` for the provisioning check.
- **D8, the chroot check is actionable only once Fedora N+1 is released.** Spec 4.7 reports "whether the COPR has a chroot for the next Fedora release"; for most of a cycle there is no next release to have a chroot for. Fedora's own `releases.json` answers that with one fetch reduced to a boolean. Reversal: make a missing chroot `info` always.
- **D9, a release is a `tinkero` package version.** Spec 4.11 says "every tagged release" without saying what is tagged. `<omarchy_tag>-<tinkero_rev>` is already the package's identity (spec 4.12, issue #48) and already what `tinkero-provision` records. Reversal: a separate release counter in the lock.
- **D10, the release is a dispatched workflow that creates its own tag.** It matches `copr-build` (an operator's decision, from `master`), and a tag derived from the lock cannot be mistyped. Reversal: trigger on a pushed tag and have the workflow check the name.
- **D11, the archive is one tarball that is a dnf repository, without sources or debuginfo.** Spec 4.11 has the downgrade "point at those files". A release's assets are a flat list, which cannot hold `repodata/`, and a downgrade of three packages drags a dozen dependencies whose file names the user cannot be asked to type. Sources are reproducible from the tag (every source is pinned by sha256); debuginfo is five times the size of the set. Reversal: attach the loose RPMs too.
- **D12, the set is read from the COPR's published repository with dnf.** The roadmap says "downloads each tagged release's RPM set from the COPR"; `copr-cli download-build` needs build ids and a token. The repository is public, and what dnf resolves from it is by definition what users get. `verify` ties it to the released commit. Reversal: walk `copr-cli get-package --with-latest-succeeded-build`.
- **D13, the previous release is found on GitHub, not recorded in the lock.** A lock key would have to be right before the COPR build, which means a preflight and a rebuild when it is wrong; dnf's history is output to parse. The release list is where releases are recorded, and its tags pass D3's pattern. Rolling back needs the network anyway. Reversal: a `previous_release` key.
- **D14, the Qt watch opens an issue; it does not rebuild.** Spec 4.7 has the workflow "trigger a COPR rebuild". A rebuild without a `Release:` bump has the same NVR as the build users have, and dnf never replaces a package with itself (issue #48), so the held-back upgrade would stay held. The bump is a commit, and a workflow that pushes to `master` is against the workflow guide. With the test relaxed to a floor it is a one-line `size:small` issue. Reversal: have the workflow open the PR itself.
- **D15, the upstream watch keeps one bump issue open and writes only the tag into it.** Upstream releases weekly and bumps are monthly or less; one issue per tag would be noise. Section 5 has the rule. Release notes are never copied (D3): an agent session is later dispatched on that issue. Reversal: one issue per tag.
- **D16, the checklist is a guide and a report tool, and the audit points at it.** The checklist today is six places (audit 10 and five roadmap sections), some stale (`docs/config-notes/`, `tinkero-provision --check`). Reversal: none wanted.
- **D17, the smoke test runs on the packager's host and gates the release, not the push.** Spec 8 lists it under "CI on every push". It installs from the COPR, whose builds are post-merge (workflow guide, adaptation 1), so it cannot be a PR check; it needs a VM with GL, which the 2F runs had through the host's GPU and a hosted runner does not offer; and a run is half an hour against a multi-gigabyte image. Spec 4.7's actual requirement, that it pass "before the COPR build is tagged for release", is met by the `smoke` input. Reversal: the driver takes its whole configuration from the environment, so a `vm-smoke.yml` on a runner with KVM is one file once software rendering is shown to carry the session.
- **D18, the base comes from the Cloud image and cloud-init.** Section 6.2. It is Workstation's package set on the Cloud image's disk layout, not a Workstation install; the differences that matter to the checks (GDM, SELinux enforcing, authselect's `local` profile) are asserted by the `baseline` stage. Reversal: `TINKERO_SMOKE_BASE`.
- **D19, the test account has password-less `sudo`.** `install.sh` calls `sudo` itself, and nothing can answer its prompt. It is the one place the VM differs from a stock host on purpose; the lock screen and polkit do not use sudoers, so the PAM rounds are unaffected. Reversal: none available without a terminal.
- **D20, sessions go through GDM's timed login, and the lock is typed with `virsh send-key`.** Section 6.3. Starting Hyprland from an SSH shell would skip GDM and uwsm, which are half of what 2F wired. Reversal: the fallbacks of 6.5.
- **D21, the first real bump is an issue, not plan tasks.** Section 4.3.
- **D22, `tinkero_rev` goes to 3 with plan 3A.** Spec 4.12: the package's content changes. 3B, 3C and 3D add nothing to the payload.
- **D23, the first release may cite a manual VM check.** If 3B lands before 3D's first run, the `smoke` input names a manual pass of the 2F guide for the package version being released. Reversal: block the first release on 3D.
- **D24, the lock check runs weekly and at release.** Spec 8 item 5 lists it under lint on every push, where it would fail between the merge of a spec bump and its COPR build. Reversal: a CI step that warns without failing.

## 9. What can be verified now, and what cannot

Hermetic, in `./dev check` and CI: every check of `tinkero-status`, its three output modes and its exit status, against stubs and a temporary state directory (`tests/test-status.sh`); `tinkero-release` end to end against stub `dnf`, `rpmspec` and `createrepo_c` (`tests/test-release.sh`); `bump-report` on fixture trees (`tests/test-bump-report.sh`); the two watches against a stub `gh` and `dnf` (`tests/test-watch.sh`); the smoke test's guest script against stubs and its driver in dry-run mode (`tests/test-vm-smoke.sh`); `assemble` and `check-rpm` carrying the two new payload files.

In CI only: the binary RPM carries `tinkero-status` and `status.sh`; ShellCheck on every new script.

Only after the merge, recorded on an issue and closed by hand: the COPR build of `tinkero` 4.0.4-3; the `release` workflow (a dry run, then the first release); the `weekly` workflow's first dispatch; the rollback drill.

Only on the operator's host: the smoke test's first run, and with it the three unproven mechanisms of 6.5. Only on a real installed machine: `tinkero-status` against real `dnf` and `rpm` output, and the `selinux` check under `sudo` (3A's post-merge issue is the first contact with all three; the smoke test's `session` stage then repeats the unprivileged run for every release). Only when upstream tags: the first real bump, and Milestone D.

## 10. Interfaces later work relies on

- Phase 5, the advisor: `tinkero-status --json`, `schema` 1, and D3's guarantee about what its strings can contain.
- Phase 4, a second distro: `check_<id>` functions in a `distro/<name>/lib/status.sh`; `tinkero-release` and the smoke test's base are Fedora's and would move under `distro/fedora/` when a second one exists.
- Fedora 45: the `chroot` check names the day it matters. Building the set for a second chroot, a lock whose `fedora` accepts two releases, and `install.sh`'s pin are not designed here; the release asset's name already carries the Fedora release so that two sets can sit on one release.
- Every later bump: `build/bump-report`, the guide, and the issue the watch opens.

## 11. Planning review record (2026-10-01)

Facts measured while writing, 2026-09-30: upstream's newest release is `v4.0.4` (2026-09-15), and its tags include pre-releases such as `v4.0.0-beta3`, which is why the patterns of 2.2 are anchored; the COPR project API returns `chroot_repos` with the one chroot and `auto_prune: true`, and has no public endpoint listing the chroots COPR offers (which is why D8 asks Fedora instead); Fedora's `releases.json` lists "45 Beta" and no "45"; the COPR repository's content and size are in 3.2, and it still holds both builds of `quickshell` and of `tinkero`, which is why `list` takes `--latest-limit=1`; dnf5 5.4.3 has every `repoquery` and `download` option sections 2 and 3 use. The per-task and final review findings of the plans are recorded in each plan's own review record.

The planning session that wrote this design was interrupted before its plans existed; the design and the plan writers' briefs were kept on issue #11 and the work was resumed from there on 2026-10-01. On resumption the design was checked against `master` at `95bb8d4` and its measured facts were taken again (upstream's newest release, the COPR project API, Fedora's `releases.json`, the COPR repository's listing). What changed: the archive's size in 3.2 is the figure `list`'s own query gives (36 binary packages, not "about 50"); 3A gained a post-merge issue for the COPR build of `tinkero` 4.0.4-3 and the first run on an installed host, because the first release is `v4.0.4-3` and `verify` stops a release whose spec was merged but never built (section 7); and two facts were added for the plans: dnf5 5.4.3 expands `\n` in a `--queryformat` but prints `\t` as two characters, so `list` and the `qt` check pass a real tab; and the COPR's `quickshell` requires `libQt6Gui.so.6(Qt_6.11_PRIVATE_API)(64bit)` (and the same for Qml, Quick and WaylandClient) while Fedora 44 offers `qt6-qtbase` 6.11.2, so the `qt` check's two sides are both readable as 2.2 says.
