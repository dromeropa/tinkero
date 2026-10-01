# Phase 3B: Release Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan runs through the issue loop** (`docs/guides/workflow.md`): dispatched only once Diego has applied `approved`, landed through a PR with green CI, tasks built serially on one branch in the order below. Task 5 is post-merge and has its own issue, closed by hand.

**Goal:** Every release of Tinkero, which is one `tinkero` package version, has its binary RPM set and a pinned `install.sh` attached to a GitHub release cut by one dispatched workflow, so that a rollback still works after COPR has pruned the older builds.

**Architecture:** `build/tinkero-release` is one bash tool beside `build/tinkero-copr`, never packaged, whose subcommands are the steps of a release: `tag` and `list` read the lock and the COPR's published repository through dnf, `verify` checks that list against the specs and the lock at this commit, `fetch`, `pack`, `install-sh` and `notes` produce the four assets and the release's description. `.github/workflows/release.yml` is the thin, manually dispatched sequence of those calls, with `ci/check-rpm` and `./dev gates-at` on the downloaded `tinkero` RPM and one `gh release create` that also creates the tag. `tests/test-release.sh` runs every subcommand, and the workflow's own `run:` blocks, against stub `dnf`, `rpmspec`, `createrepo_c` and `gh`. The first release and the rollback drill close the plan after the merge.

**Tech Stack:** bash, awk, dnf 5 (`repoquery`, `download`, `--repofrompath`), `rpmspec`, `createrepo_c`, GNU tar, `sha256sum`, GitHub Actions (`workflow_dispatch`, `gh`, `actions/upload-artifact`), the existing `tests/lib.sh` harness; no Python in this plan.

**Spec:** `docs/superpowers/specs/2026-10-01-phase-3-maintenance-release-design.md` (the Phase 3 design, binding for this plan): section 3 (all of it), section 7 (the 3B row), section 9 (the parts about the release), and decisions D9, D10, D11, D12, D23 and D24 (the release half; the weekly half is plan 3C's). Master spec `docs/superpowers/specs/2026-09-17-tinkero-design.md` sections 4.1, 4.2 (Build, and the pin), 4.6 (`install.sh`), 4.11, 4.12, 8 (item 5) and 12. Plan 2E's design `docs/superpowers/specs/2026-09-23-phase-2e-provision-design.md`, decision D7 (the two `install.sh` variables). Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, section "Phase 3: maintenance and release". Placeholder issue: #11.

## Global Constraints

- Base: `master` at `95bb8d4` plus the commit that added the Phase 3 design; every count in this plan was measured on 2026-10-01. The COPR's repository answered `list`'s own query with 75 rows, 36 of them once `-debuginfo` and `-debugsource` are dropped, from 26 source packages (the 26 lines of `distro/fedora/specs/build-order.txt`), 244 MiB. The new test file's tallies (`1..70`, `1..150`, `1..188`) were measured in a prototype of this plan.
- Phase 3's plans land serially (3A, 3B, 3C, 3D): where a step shows a diff of a file another Phase 3 plan also edits (`.github/workflows/ci.yml`, `dev`, the roadmap, the master spec, `CLAUDE.md`, `README.md`), apply the change to the file as it is then, and read a tally as "N more than before".
- Plan 3A lands first and takes `tinkero_rev` to 3, so the first release is `v4.0.4-3`. The tests do not depend on that: they run against a private root with its own lock at `tinkero_rev=2`, the COPR's state on 2026-10-01, and the one assertion that reads the repository's own lock computes its expectation from it.
- Nothing packaged changes: no payload file, `tinkero.spec.in` and `tinkero_rev` are untouched (design D22). `build/tinkero-release` is a packager's tool like `build/tinkero-copr`.
- Data over code: the set is `distro/fedora/specs/build-order.txt` and what the COPR's repository serves, the pins are `upstream.lock`. `build/tinkero-release` carries no package list of its own.
- Gate allowlists under `ci/allow/` only shrink. This plan adds no entry and touches no gate.
- A token that comes from the network (a row of the repository's listing, the `smoke` input) is used only after it matched a fixed pattern, and one that fails its pattern is named by line number and never echoed (the rule of design D3, applied to the build tool: a package name is spliced into a dnf command line). The patterns are matched in the C locale: `build/tinkero-release` sets `LC_ALL=C` for itself, because under a collating UTF-8 locale bash's `[0-9]` and `[a-z]` admit the digits and letters of other scripts.
- Bash scripts start with `#!/bin/bash` and `set -euo pipefail`; a header comment gives usage and the script prints it with `sed -n 'A,Bp' "$0"`; ShellCheck clean with `-x -e SC1090,SC1091`; no `A && B || C` one-liners (SC2015); `# shellcheck disable=SC2016` above a line that carries a literal `$` on purpose. The lock is parsed with `lock_get` (`build/lib.sh`), never sourced.
- Tests: `tests/test-release.sh` sources `tests/lib.sh` and asserts on messages, not only on exit codes. No test uses the network or runs a real `dnf`, `rpmspec`, `createrepo_c`, `gh`, `rpm` or `curl`: each is a stub on `PATH`, written by the test into its temporary directory. `tar`, `sha256sum`, `awk`, `sed` and `sort` are the real ones. The seams are `TINKERO_ROOT`, `TINKERO_LOCK`, `TINKERO_COPR_PROJECT` and `TINKERO_RELEASE_REPO`. CI runs the suite as root in a container; nothing here has privilege logic, so nothing needs `TINKERO_EUID`.
- Test safety: a test deletes only its own `mktmp` directory, by the house idiom's last line (`rm -rf "$d"; finish`), and nothing else; no test exports `HOME` or reassigns a variable that a later `rm` expands; a command under test that needs a home directory gets `HOME="$d/home"` on its own command line; a script that deletes deletes only a path it created itself and guards the variable (`${var:?}`). `build/tinkero-release` deletes nothing at all: it has no cleanup trap and no scratch directory, and no assertion depends on a deletion having happened.
- The new script is added to the ShellCheck step of `.github/workflows/ci.yml`.
- One commit per task, messages in the style of `git log` on master (`build: ...`, `ci: ...`, `docs: ...`). Attribution trailers on every commit per the session's rules. No em dashes in Tinkero's own prose.
- Land through a PR against the approved issue; never push `master`. `copr-build` is never triggered by this plan's code issue, and `release` is dispatched only by Task 5's issue.
- Each task's PR includes its Deviations line in this plan's "## Deviations" section when anything deviated.
- "Not measured at planning time" marks an expected output that was derived by reasoning: the planning session ran under a no-delete rule and executed only the new test file, and its machine has no `rpmspec`, `createrepo_c` or `rpmbuild` and was not allowed to run `dnf` or `gh`. The implementer measures those.

## Issue map

To be filed as two issues, with the other Phase 3 plans' issues superseding placeholder #11 (which is then closed with a comment naming them). Tasks 1 to 4 are one orchestrated issue, built serially on one branch because they share `build/tinkero-release`, `tests/test-release.sh` and `.github/workflows/ci.yml`, and land as one PR. Task 5 is a post-merge issue, closed by hand (workflow guide, adaptation 1): it is `blocked by` the first issue and by plan 3A's post-merge issue (the COPR build of `tinkero` 4.0.4-3), because the release workflow can only run once it is on `master` and `verify` stops a release whose package was merged and not built. The `approved` label is Diego's.

| Task | Size | Area | WHAT | WHERE | HOW TO VERIFY |
|---|---|---|---|---|---|
| 1 `build/tinkero-release`: `tag`, `list`, `verify` | medium | build | the release tag from the lock; the COPR's newest binary packages as a five-column list; the check of that list against the build order, the specs and the lock's pins, every mismatch one `FAIL:` line | `build/tinkero-release`, `tests/test-release.sh` | `bash tests/test-release.sh` at `1..70`; ShellCheck clean |
| 2 `fetch`, `pack`, `install-sh`, `notes` | medium | build | download exactly the listed packages; the tarball that is a dnf repository, `RPMS.txt`, `SHA256SUMS`; the pinned `install.sh`; the release's description | `build/tinkero-release`, `tests/test-release.sh` | `bash tests/test-release.sh` at `1..150` |
| 3 The `release` workflow | small | ci | `release.yml` (dispatch only, `contents: write`, inputs `smoke` and `dry_run`); the tool in CI's ShellCheck list; CI asks every spec what `verify` asks | `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `tests/test-release.sh` | `bash tests/test-release.sh` at `1..188`; CI green, its spec step printing 25 `name version-release` lines |
| 4 Docs | small | docs | the release guide; master spec 4.6, 4.11, 4.12, 8, 11, 12 and the status line; the roadmap row and queue; the workflow guide; `CLAUDE.md`. The README's install line is Task 5's (design 3.4: once the first release exists) | `docs/guides/release.md`, `docs/**`, `CLAUDE.md` | `./dev check` green; no em dash added; every quoted string replaced once |
| 5 The first release and the rollback drill (post-merge) | medium | ci | a `dry_run` dispatch, the release `v4.0.4-3`, the drill on a VM, the README's install line | none in the code PR (a record on the issue, one small docs PR: `README.md`, one roadmap line) | the release exists with four assets on the dispatched commit; the record of every expected line; closed by hand |

After Tasks 1 to 4, `./dev check` runs one more test file, `tests/test-release.sh`, at `1..188`. No existing test file changes; their tallies are whatever they were before this plan (in CI at `95bb8d4`: test-assemble `1..70`, test-branding-render `1..34`, test-branding `1..14`, test-check-rpm `1..16`, test-copr `1..21`, test-fastfetch-fedora `1..3`, test-fetch `1..9`, test-gates `1..94`, test-install `1..34`, test-launch-webapp `1..41`, test-lock `1..4`, test-menu-guards `1..8`, test-pam-sync `1..75`, test-provision `1..189`, test-render-spec `1..25`, test-replacements `1..54`, test-session-end `1..35`, test-specs `1..88`, test-theme-set-browser `1..15`, test-update `1..6`, Python `Ran 45 tests`; plan 3A moves some of these before this plan lands).

## File Structure

| File | Responsibility |
|---|---|
| `build/tinkero-release` | the release, subcommand by subcommand: `tag`, `list`, `verify LIST`, `fetch LIST DEST`, `pack DEST OUT`, `install-sh OUT`, `notes OUT SMOKE_URL` (design 3.2; D9, D11, D12, D24) |
| `tests/test-release.sh` | every subcommand against stub `dnf`, `rpmspec` and `createrepo_c` on the COPR's real listing of 2026-10-01; the workflow's `run:` blocks against those and a stub `gh`; the workflow file's fixed properties |
| `.github/workflows/release.yml` | the dispatched release: refusals, `list`, `verify`, `fetch`, `ci/check-rpm`, `./dev gates-at`, `pack`, `install-sh`, `notes`, then the artifact (dry run) or `gh release create` (design 3.3, D10, D23) |
| `.github/workflows/ci.yml` | ShellCheck on the new tool; the spec step also runs the `rpmspec` query `verify` depends on, for every spec |
| `docs/guides/release.md` | the operator's procedure: when, the order, the dry run, the release, what stops one, the assets, the rollback and its drill |
| `CLAUDE.md`, `docs/guides/workflow.md`, the master spec, the roadmap | say what the code now does (Task 4) |
| `README.md` | the install line becomes the release URL once the first release exists (Task 5's docs PR) |

Interfaces later plans rely on:

- Plan 3C, the weekly workflow: `build/tinkero-release list` (stdout: `name<TAB>version<TAB>release<TAB>arch<TAB>source`, sorted, one binary package per line; exit 1 with an `error:` line on stderr when dnf fails, the repository is empty or a row is not a package row) and `build/tinkero-release verify LIST` (exit 0 and one `PASS:` line; exit 1 and one `FAIL: <package>: ...` line per mismatch on stdout; exit 2 on usage). Both need dnf 5; `verify` needs `rpmspec` (`rpm-build`, `rpmdevtools`).
- Plan 3C, the bump checklist's last stage: `docs/guides/release.md`, section 2.
- Plan 3A's `tinkero-status --rollback`: the asset `tinkero-<version>-<rev>.fc<N>-rpms.tar` at `https://github.com/dromeropa/tinkero/releases/download/<tag>/`, extracting to one directory of the same name without `.tar` that is a dnf repository; release tags of the shape `^v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$`.
- Plan 3D: the `smoke` input of the `release` workflow is where its run's record is named.
- Fedora 45: the asset's name carries `.fc<N>`; one set per lock.

## Review Focus

Input classes and failure modes the design implies and does not spell out; each has its tests in the task named.

1. **Names and versions that do not split where a naive parse splits them.** `hyprland-preview-share-picker` and `tinkero-nerd-fonts` (hyphens in the name, and a second package whose name starts with `tinkero-`), `0.3.0^20.git28771c7` (a caret), `xdg-desktop-portal-hyprland` (an epoch, `1:1.4.1`, that neither the file name nor the source RPM's name carries). The source's name, version and release are split from the right, the `tinkero` RPM is found by its exact file name, and the workflow's glob is `tinkero-[0-9]*`: Task 1 (`list`, `verify`), Task 2 (`pack`), Task 3 (the glob).
2. **The COPR holding more than the commit describes.** Superseded builds (both builds of `quickshell` and of `tinkero` were still there on 2026-10-01), a subpackage left over from an older build of a source, a package `build-order.txt` no longer lists. `list` takes the newest build only, `fetch` asks for each package by full version and release, and `verify` names a leftover and a stray: Tasks 1 and 2.
3. **A merge that is ahead of its build.** A spec bumped and not built, `tinkero_rev` bumped and `tinkero` not rebuilt (the state of `master` between plan 3A's merge and its COPR build), a new package never built. `verify` reports every one of them in one run, each with the package and both values, before it exits 1: Task 1.
4. **Rows and inputs that are not what they claim to be.** dnf failing, an empty answer, a row with a field outside RPM's alphabet or a name that would read as an option, a list edited by hand with a duplicate line, a `smoke` input carrying Markdown or shell text. Each is refused, named without being echoed, and never reaches dnf or the release's page: Tasks 1, 2 and 3.
5. **The script and the release moving under the tool.** `install.sh` whose `TINKERO_REF` line no longer says `master` (master spec, open question 6: the default branch may be renamed), a second `TINKERO_FEDORA=` line, a rewritten script that does not parse; a release cut twice, a tag pushed by hand, GitHub not answering the question "does it exist"; `SHA256SUMS` after either subcommand is run again. Nothing is written, the dispatch is refused, the checksums keep one line per file: Tasks 2 and 3.

---

### Task 1: `build/tinkero-release`: `tag`, `list`, `verify`

**Files:**
- Create: `build/tinkero-release` (mode 0755), `tests/test-release.sh`
- Test: `tests/test-release.sh`

**Interfaces:**
- Consumes: `build/lib.sh` (`lock_get`, `die`); `upstream.lock` (`omarchy_tag`, `tinkero_rev`, `fedora`, `hyprland`, `quickshell`, `quickshell_release`); `distro/fedora/specs/build-order.txt` and the `<name>.spec` files beside it; `dnf` 5 and `rpmspec` on `PATH`.
- Produces:
  - `build/tinkero-release tag`: prints `<omarchy_tag>-<tinkero_rev>` (`v4.0.4-3`). Exit 1 when the lock's `omarchy_tag` is not `vMAJOR.MINOR.PATCH`, or `tinkero_rev` or `fedora` is not an integer.
  - `build/tinkero-release list`: prints the COPR's newest binary packages, sorted, one per line, `name<TAB>version<TAB>release<TAB>arch<TAB>source`, where `release` carries the dist tag (`2.fc44`) and `source` is the source package's `name-version-release` (`tinkero-4.0.4-2.fc44`). Exit 1, with an `error:` line on stderr and nothing on stdout, when dnf fails, the repository is empty, or a row is not a package row.
  - `build/tinkero-release verify LIST`: exit 0 and the line `PASS: <n> packages from <m> sources match the specs and the lock at <tag>`; exit 1 and one `FAIL: <package>: ...` line on stdout per mismatch, all of them before the exit; exit 1 with an `error:` line when LIST is missing or malformed.
  - Any other invocation: usage on stderr, exit 2. `-h` and `--help`: usage on stdout, exit 0.
  - Environment: `TINKERO_COPR_PROJECT` (default `dromero/tinkero`), `TINKERO_RELEASE_REPO` (default `https://download.copr.fedorainfracloud.org/results/<project>/fedora-<N>-x86_64/`), `TINKERO_ROOT`, `TINKERO_LOCK`.
  - Task 2 adds four subcommands to the same file; Task 3's workflow and plan 3C's weekly job call these three.

What `verify` checks, in the design's order (3.2), with what this plan adds to make each checkable:

1. Each package of `build-order.txt` is the source of at least one line of LIST. And the reverse, which the design's second check implies (a source with no spec cannot equal its spec): a source in LIST that `build-order.txt` does not list is a mismatch, so a package the set dropped is not archived for ever.
2. Each source's version and release equal its spec's: `rpmspec -q --srpm --define "dist .fc<fedora>" --queryformat '%{version}-%{release}\n' distro/fedora/specs/<name>.spec`; for `tinkero`, the lock's `<tag without v>-<tinkero_rev>.fc<fedora>`. When LIST holds packages from two builds of one source (a subpackage the newer build stopped producing), each build is compared, so the older one is named.
3. The lock's pins hold for the binary packages the `tinkero` RPM requires: `hyprland`'s version is at least the lock's `hyprland` and below its next minor; `quickshell`'s version equals the lock's `quickshell` and its release's leading integer is at least `quickshell_release` (a floor, not an equality: plan 3C's Qt rebuild raises the spec's `Release:` without touching the lock).

- [ ] **Step 1: Write the failing test**

`tests/test-release.sh` (new). The stubs for `dnf download` and `createrepo_c` are written here and first used by Task 2, so that Tasks 2 and 3 only append cases. The fixture is the COPR's real listing: `rows` expands the 26 lines below into the 75 rows the query printed on 2026-10-01 (compared byte for byte with that output at planning time).

```bash
#!/bin/bash
# build/tinkero-release against stub dnf, rpmspec and createrepo_c; tar and sha256sum are the
# real ones. The repository rows are the COPR's own, as `list`'s query printed them on
# 2026-10-01: 75 rows, 36 without the debug packages, from 26 sources. Nothing is fetched.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
R=$ROOT/build/tinkero-release

# One source per line: name, version, release, then the binary packages built from it (x86_64
# unless marked). rows prints them the way dnf prints `list`'s query format: name, version,
# release, arch and sourcerpm, tab-separated, sorted by name.
rows() {
  local src ver rel bins b arch
  while read -r src ver rel bins; do
    for b in $bins; do
      arch=x86_64
      if [[ $b == *:* ]]; then arch=${b#*:}; b=${b%:*}; fi
      printf '%s\t%s\t%s\t%s\t%s-%s-%s.src.rpm\n' "$b" "$ver" "$rel" "$arch" "$src" "$ver" "$rel"
    done
  done <<'F' | LC_ALL=C sort
aquamarine 0.14.0 1.fc44 aquamarine aquamarine-debuginfo aquamarine-debugsource aquamarine-devel
glaze 7.8.2 1.fc44 glaze-devel:noarch
gpu-screen-recorder 5.14.1 1.fc44 gpu-screen-recorder gpu-screen-recorder-debuginfo gpu-screen-recorder-debugsource
herdr 0.8.0^13.git0766aa5 1.fc44 herdr herdr-debuginfo herdr-debugsource
hyprcursor 0.1.13 2.fc44 hyprcursor hyprcursor-debuginfo hyprcursor-debugsource hyprcursor-devel
hyprgraphics 0.5.1 2.fc44 hyprgraphics hyprgraphics-debuginfo hyprgraphics-debugsource hyprgraphics-devel
hyprland 0.56.2 1.fc44 hyprland hyprland-debugsource hyprland-devel hyprland-no-session hyprland-no-session-debuginfo hyprland-uwsm
hyprland-guiutils 0.2.2 1.fc44 hyprland-guiutils hyprland-guiutils-debuginfo hyprland-guiutils-debugsource
hyprland-preview-share-picker 0.2.1 1.fc44 hyprland-preview-share-picker hyprland-preview-share-picker-debuginfo hyprland-preview-share-picker-debugsource
hyprland-protocols 0.7.0 1.fc44 hyprland-protocols-devel:noarch
hyprlang 0.6.8 2.fc44 hyprlang hyprlang-debuginfo hyprlang-debugsource hyprlang-devel
hyprpicker 0.4.7 2.fc44 hyprpicker hyprpicker-debuginfo hyprpicker-debugsource
hyprsunset 0.4.0 1.fc44 hyprsunset hyprsunset-debuginfo hyprsunset-debugsource
hyprtoolkit 0.5.4 2.fc44 hyprtoolkit hyprtoolkit-debuginfo hyprtoolkit-debugsource hyprtoolkit-devel
hyprutils 0.14.0 1.fc44 hyprutils hyprutils-debuginfo hyprutils-debugsource hyprutils-devel
hyprwayland-scanner 0.4.6 1.fc44 hyprwayland-scanner-debugsource hyprwayland-scanner-devel hyprwayland-scanner-devel-debuginfo
hyprwire 0.3.1 2.fc44 hyprwire hyprwire-debuginfo hyprwire-debugsource hyprwire-devel hyprwire-devel-debuginfo
mise 2026.9.5 1.fc44 mise
quickshell 0.3.0^20.git28771c7 2.fc44 quickshell quickshell-debuginfo quickshell-debugsource
tensaku 0.26.6 1.fc44 tensaku tensaku-debuginfo tensaku-debugsource
tinkero 4.0.4 2.fc44 tinkero:noarch
tinkero-nerd-fonts 3.4.0 1.fc44 tinkero-nerd-fonts:noarch
ttfx 0.3.2 1.fc44 ttfx ttfx-debuginfo ttfx-debugsource
uwsm 0.26.5 1.fc44 uwsm:noarch
voxtype 1.0.1 1.fc44 voxtype
xdg-desktop-portal-hyprland 1.4.1 1.fc44 xdg-desktop-portal-hyprland xdg-desktop-portal-hyprland-debuginfo xdg-desktop-portal-hyprland-debugsource
F
}

# Stubs. dnf: `repoquery` prints the file $REPOQUERY; `download` (Task 2) writes
# DESTDIR/<spec>.rpm for every package spec except $DNF_SKIP, and the stray file $DNF_EXTRA.
cat > "$d/bin/dnf" <<'S'
#!/bin/bash
echo "dnf $*" >> "$LOG"
if [[ ${DNF_FAIL:-0} == 1 ]]; then echo "dnf: cannot reach the repository" >&2; exit 1; fi
sub=; dest=; specs=()
for a in "$@"; do
  case $a in
    --destdir=*) dest=${a#--destdir=} ;;
    -*) ;;
    repoquery|download) if [[ -z $sub ]]; then sub=$a; else specs+=("$a"); fi ;;
    *) specs+=("$a") ;;
  esac
done
case $sub in
  repoquery) cat "$REPOQUERY" ;;
  download)
    mkdir -p "$dest"
    for s in "${specs[@]}"; do [[ $s == "${DNF_SKIP:-}" ]] || echo "rpm $s" > "$dest/$s.rpm"; done
    [[ -z ${DNF_EXTRA:-} ]] || echo stray > "$dest/$DNF_EXTRA" ;;
  *) exit 1 ;;
esac
S
# rpmspec: prints Version-Release of the spec it is given, with %{?dist} from --define "dist X".
cat > "$d/bin/rpmspec" <<'S'
#!/bin/bash
echo "rpmspec $*" >> "$LOG"
dist=; spec=
while (($#)); do
  case $1 in
    --define) dist=${2#dist }; shift ;;
    *.spec) spec=$1 ;;
  esac
  shift
done
[[ -f $spec ]] || { echo "rpmspec: cannot open $spec" >&2; exit 1; }
if grep -q '^BROKEN' "$spec"; then echo "rpmspec: parse error" >&2; exit 1; fi
v=$(sed -n 's/^Version:[[:space:]]*//p' "$spec"); r=$(sed -n 's/^Release:[[:space:]]*//p' "$spec")
echo "$v-${r/'%{?dist}'/$dist}"
S
# createrepo_c: makes DIR/repodata/repomd.xml, as the real one makes DIR a repository.
cat > "$d/bin/createrepo_c" <<'S'
#!/bin/bash
echo "createrepo_c $*" >> "$LOG"
[[ ${CREATEREPO_FAIL:-0} == 1 ]] && exit 1
mkdir -p "$1/repodata" && echo '<repomd/>' > "$1/repodata/repomd.xml"
S
chmod +x "$d/bin"/*
rows > "$d/repoquery"
export PATH=$d/bin:$PATH REPOQUERY=$d/repoquery
unset TINKERO_COPR_PROJECT TINKERO_RELEASE_REPO TINKERO_LOCK

# A private root: the lock, the build order and one spec per source, all as the COPR had them.
r=$d/root; S=$r/distro/fedora/specs; mkdir -p "$S"
fresh_root() {
  local src ver rel
  cat > "$r/upstream.lock" <<'L'
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
quickshell_release=2
fedora=44
tinkero_rev=2
L
  echo "# one package per line" > "$S/build-order.txt"
  while IFS=$'\t' read -r _ ver rel _ src; do
    src=${src%.src.rpm}; src=${src%"-$ver-$rel"}
    grep -qx "$src" "$S/build-order.txt" && continue
    echo "$src" >> "$S/build-order.txt"
    [[ $src == tinkero ]] || printf 'Name: %s\nVersion: %s\nRelease: %s%%{?dist}\n' "$src" "$ver" "${rel%.fc44}" > "$S/$src.spec"
  done < "$REPOQUERY"
  cp "$ROOT/install.sh" "$r/install.sh"
}
fresh_root
export TINKERO_ROOT=$r
run() { : > "$LOG"; out=$("$R" "$@" 2>&1) && rc=0 || rc=$?; }

# The fixture is the real listing: 75 rows, 26 sources, 25 of them with a spec of their own.
assert_eq "$(wc -l < "$REPOQUERY")" 75 "fixture: the 75 rows the COPR listed on 2026-10-01"
assert_eq "$(grep -cvE '^\s*(#|$)' "$S/build-order.txt")" 26 "fixture: 26 sources in the build order"

# tag
run tag
assert_eq "$rc" 0 "tag: exit 0"; assert_eq "$out" "v4.0.4-2" "tag: <omarchy_tag>-<tinkero_rev>"
assert_eq "$(TINKERO_ROOT=$ROOT "$R" tag)" "$(sed -n 's/^omarchy_tag=//p' "$ROOT/upstream.lock")-$(sed -n 's/^tinkero_rev=//p' "$ROOT/upstream.lock")" "tag: the repository's own lock gives its own tag"
sed 's/^omarchy_tag=.*/omarchy_tag=v4.0/' "$r/upstream.lock" > "$d/lock-short"
TINKERO_LOCK=$d/lock-short run tag
assert_eq "$rc" 1 "tag: a two-part upstream tag is refused (tinkero-status --rollback would not find the release)"
assert_contains "$out" "omarchy_tag must be vMAJOR.MINOR.PATCH" "tag: and says why"
sed 's/^tinkero_rev=.*/tinkero_rev=2a/' "$r/upstream.lock" > "$d/lock-rev"
TINKERO_LOCK=$d/lock-rev run tag
assert_eq "$rc" 1 "tag: a tinkero_rev that is not an integer is refused"
assert_contains "$out" "tinkero_rev must be an integer" "tag: and says why"

# list
run list; list=$out
assert_eq "$rc" 0 "list: exit 0"
assert_eq "$(wc -l <<<"$list")" 36 "list: 36 binary packages"
assert_eq "$(grep -cE -- $'-debug(info|source)\t' <<<"$list")" 0 "list: no -debuginfo or -debugsource package"
assert_eq "$(head -n1 <<<"$list")" $'aquamarine\t0.14.0\t1.fc44\tx86_64\taquamarine-0.14.0-1.fc44' "list: name, version, release, arch, source"
assert_contains "$list" $'hyprland-preview-share-picker\t0.2.1\t1.fc44\tx86_64\thyprland-preview-share-picker-0.2.1-1.fc44' "list: a name with hyphens keeps its source whole"
assert_contains "$list" $'hyprland-uwsm\t0.56.2\t1.fc44\tx86_64\thyprland-0.56.2-1.fc44' "list: a subpackage carries its source, not its own name"
assert_contains "$list" $'herdr\t0.8.0^13.git0766aa5\t1.fc44\tx86_64\therdr-0.8.0^13.git0766aa5-1.fc44' "list: a snapshot version with a caret passes"
assert_contains "$list" $'tinkero\t4.0.4\t2.fc44\tnoarch\ttinkero-4.0.4-2.fc44' "list: the desktop package is in the set"
assert_eq "$(cut -f5 <<<"$list" | sort -u | wc -l)" 26 "list: from 26 sources"
assert_eq "$list" "$(LC_ALL=C sort <<<"$list")" "list: sorted"
assert_contains "$(cat "$LOG")" "dnf -q repoquery --repofrompath=tinkero-release,https://download.copr.fedorainfracloud.org/results/dromero/tinkero/fedora-44-x86_64/ --repo=tinkero-release --latest-limit=1 --arch=x86_64,noarch --queryformat" "list: one repoquery of the COPR's own repository, newest builds only"
assert_contains "$(cat "$LOG")" $'%{name}\t%{version}\t%{release}\t%{arch}\t%{sourcerpm}' "list: the query format carries real tabs (dnf5 prints \\t as two characters)"
TINKERO_COPR_PROJECT=me/proj run list
assert_contains "$(cat "$LOG")" "--repofrompath=tinkero-release,https://download.copr.fedorainfracloud.org/results/me/proj/fedora-44-x86_64/" "list: TINKERO_COPR_PROJECT names the project"
TINKERO_RELEASE_REPO=file:///srv/repo run list
assert_contains "$(cat "$LOG")" "--repofrompath=tinkero-release,file:///srv/repo " "list: TINKERO_RELEASE_REPO replaces the URL"
DNF_FAIL=1 run list
assert_eq "$rc" 1 "list: dnf failing is a failure"
assert_contains "$out" "dnf repoquery failed" "list: and says so"
REPOQUERY=/dev/null run list
assert_eq "$rc" 1 "list: an empty repository is a failure, not an empty release"
assert_contains "$out" "no packages" "list: and says so"
{ rows; printf 'tinkero\t4.0.4\t2.fc44\tsrc\t\n'; } > "$d/with-src"
REPOQUERY=$d/with-src run list
assert_eq "$rc" 1 "list: a row that is not a binary package of the query fails"
assert_contains "$out" "line 76" "list: and names the line"
# shellcheck disable=SC2016  # the text must reach the tool unexpanded
{ rows; printf 'evil\t1.0\t1.fc44\tx86_64\t$(touch x)-1.0-1.fc44.src.rpm\n'; } > "$d/with-junk"
REPOQUERY=$d/with-junk run list
assert_eq "$rc" 1 "list: a field outside the package-name alphabet fails"
if grep -qF 'touch' <<<"$out"; then not_ok "list: the offending text is not echoed"; else ok "list: the offending text is not echoed"; fi

# verify
printf '%s\n' "$list" > "$d/list"
run verify "$d/list"
assert_eq "$rc" 0 "verify: the COPR's set matches its own specs and lock"
assert_eq "$out" "PASS: 36 packages from 26 sources match the specs and the lock at v4.0.4-2" "verify: and says so in one line"
assert_eq "$(grep -c '^rpmspec ' "$LOG")" 25 "verify: one rpmspec call per spec file (tinkero comes from the lock)"
assert_contains "$(cat "$LOG")" "rpmspec -q --srpm --define dist .fc44 --queryformat %{version}-%{release}\\n $S/hyprcursor.spec" "verify: rpmspec is asked for the source package with dist set from the lock"

# every mismatch is reported before the exit: a spec bumped but not built, a package listed but
# never built, and a tinkero_rev merged ahead of its COPR build
sed -i 's/^Release: 2/Release: 3/' "$S/hyprcursor.spec"
echo newpkg >> "$S/build-order.txt"; printf 'Name: newpkg\nVersion: 1.0\nRelease: 1%%{?dist}\n' > "$S/newpkg.spec"
sed -i 's/^tinkero_rev=2/tinkero_rev=3/' "$r/upstream.lock"
run verify "$d/list"
assert_eq "$rc" 1 "verify: mismatches exit 1"
assert_contains "$out" "FAIL: hyprcursor: the COPR has 0.1.13-2.fc44, its spec says 0.1.13-3.fc44" "verify: a spec merged but not built names the package and both values"
assert_contains "$out" "FAIL: newpkg: build-order.txt lists it, the COPR has no package built from it" "verify: a package never built is named"
assert_contains "$out" "FAIL: tinkero: the COPR has 4.0.4-2.fc44, the lock says 4.0.4-3.fc44" "verify: a tinkero_rev ahead of the COPR build is named"
assert_eq "$(grep -c '^FAIL: ' <<<"$out")" 3 "verify: three mismatches, three lines"
if grep -q '^PASS' <<<"$out"; then not_ok "verify: no PASS line beside a FAIL"; else ok "verify: no PASS line beside a FAIL"; fi
fresh_root

# the lock's pins (spec 8, item 5)
pin_case() {   # NAME FIELD VALUE: the list with one field of one package's rows replaced
  awk -F'\t' -v OFS='\t' -v n="$1" -v f="$2" -v v="$3" '$1 == n { $f = v } { print }' "$d/list" > "$d/list-pin"
  run verify "$d/list-pin"
}
sed -i 's/^Version: 0.56.2/Version: 0.57.0/' "$S/hyprland.spec"
awk -F'\t' -v OFS='\t' '$5 == "hyprland-0.56.2-1.fc44" { $2 = "0.57.0"; $5 = "hyprland-0.57.0-1.fc44" } { print }' "$d/list" > "$d/list-pin"
run verify "$d/list-pin"
assert_eq "$rc" 1 "verify: a Hyprland of the next minor fails though its spec agrees"
assert_eq "$out" "FAIL: hyprland: the COPR has 0.57.0, the lock wants at least 0.56.2 and below 0.57" "verify: and names the range"
fresh_root
pin_case hyprland 2 0.56.1
assert_contains "$out" "FAIL: hyprland: the COPR has 0.56.1, the lock wants at least 0.56.2 and below 0.57" "verify: a Hyprland below the pin fails"
sed -i 's/^Version: 0.56.2/Version: 0.56.10/' "$S/hyprland.spec"
awk -F'\t' -v OFS='\t' '$5 == "hyprland-0.56.2-1.fc44" { $2 = "0.56.10"; $5 = "hyprland-0.56.10-1.fc44" } { print }' "$d/list" > "$d/list-pin"
run verify "$d/list-pin"
assert_eq "$rc" 0 "verify: a later patch release of the pinned minor passes (0.56.10 is above 0.56.2)"
fresh_root
pin_case quickshell 2 0.3.1
assert_contains "$out" "FAIL: quickshell: the COPR has version 0.3.1, the lock wants 0.3.0^20.git28771c7" "verify: another Quickshell version fails"
pin_case quickshell 3 1.fc44
assert_contains "$out" "FAIL: quickshell: the COPR has release 1.fc44, the lock wants at least 2" "verify: a Quickshell release below the floor fails"
sed -i 's/^Release: 2/Release: 3/' "$S/quickshell.spec"
awk -F'\t' -v OFS='\t' '$5 ~ /^quickshell-/ { $3 = "3.fc44"; $5 = "quickshell-0.3.0^20.git28771c7-3.fc44" } { print }' "$d/list" > "$d/list-pin"
run verify "$d/list-pin"
assert_eq "$rc" 0 "verify: a Quickshell rebuilt past the floor passes (the floor is not an equality)"
fresh_root
grep -v $'^hyprland\t' "$d/list" > "$d/list-pin"
run verify "$d/list-pin"
assert_contains "$out" "FAIL: hyprland: the lock pins it, the list has no package of that name" "verify: a set without the pinned package fails"

# what the COPR holds that this commit does not describe
{ cat "$d/list"; printf 'stray\t1.0\t1.fc44\tx86_64\tstray-1.0-1.fc44\n'; } > "$d/list-stray"
run verify "$d/list-stray"
assert_eq "$rc" 1 "verify: a package the build order does not list fails"
assert_contains "$out" "FAIL: stray: the COPR has stray-1.0-1.fc44, build-order.txt does not list it" "verify: and names it"
{ cat "$d/list"; printf 'hyprland-old-plugin\t0.56.1\t1.fc44\tx86_64\thyprland-0.56.1-1.fc44\n'; } > "$d/list-old"
run verify "$d/list-old"
assert_eq "$rc" 1 "verify: a subpackage left over from an older build fails"
assert_contains "$out" "FAIL: hyprland: the COPR has 0.56.1-1.fc44, its spec says 0.56.2-1.fc44" "verify: and names the older build"
echo BROKEN >> "$S/voxtype.spec"
run verify "$d/list"
assert_contains "$out" "FAIL: voxtype: rpmspec could not read distro/fedora/specs/voxtype.spec" "verify: a spec rpmspec cannot read is a mismatch, not a crash"
fresh_root

# a LIST that is not a list
printf 'tinkero\t4.0.4\t2.fc44\tnoarch\n' > "$d/list-short"
run verify "$d/list-short"
assert_eq "$rc" 1 "verify: a line with four fields is refused"
assert_contains "$out" "line 1 is not name<TAB>version<TAB>release<TAB>arch<TAB>source" "verify: and names the line"
{ cat "$d/list"; printf -- '--installroot=/x\t1\t1.fc44\tx86_64\tx-1-1.fc44\n'; } > "$d/list-opt"
run verify "$d/list-opt"
assert_eq "$rc" 1 "verify: a name that would read as an option is refused"
assert_contains "$out" "line 37 is not name<TAB>version<TAB>release<TAB>arch<TAB>source" "verify: by the list check, before any comparison"
{ cat "$d/list"; sed -n '1p' "$d/list"; } > "$d/list-dup"
run verify "$d/list-dup"
assert_contains "$out" "line 37 lists aquamarine.x86_64 a second time" "verify: a package listed twice is refused"
run verify "$d/nope"
assert_eq "$rc" 1 "verify: a missing LIST is a failure"; assert_contains "$out" "no such list" "verify: and says so"

# Patterns are matched in the C locale whatever the caller's is: under a collating UTF-8 locale
# bash's [0-9] admits the digits of other scripts. These cases run under such a locale when one
# is installed and under the caller's own when none is (CI's container); either way the refusal
# is all that is printed.
loc=$(locale -a 2>/dev/null | grep -m1 -E '^[a-z]{2}_[A-Z]{2}\.(utf8|UTF-8)$' || true)
locenv=(); if [[ -n $loc ]]; then locenv=(LC_ALL="$loc"); fi
five=$(printf '\xd9\xa5')      # U+0665, a digit that is not ASCII
run_loc() { : > "$LOG"; out=$(env "${locenv[@]}" "$R" "$@" 2>&1) && rc=0 || rc=$?; }
sed "s/^omarchy_tag=.*/omarchy_tag=v4.0.$five/" "$r/upstream.lock" > "$d/lock-digit"
TINKERO_LOCK=$d/lock-digit run_loc tag
assert_eq "$rc" 1 "tag: a digit of another script in the lock's tag is refused, whatever the caller's locale"
assert_contains "$out" "omarchy_tag must be vMAJOR.MINOR.PATCH" "tag: and says why"
{ cat "$d/list"; printf 'odd\t1.%s\t1.fc44\tx86_64\todd-1.%s-1.fc44\n' "$five" "$five"; } > "$d/list-digit"
run_loc verify "$d/list-digit"
assert_eq "$out" "error: $d/list-digit: line 37 is not name<TAB>version<TAB>release<TAB>arch<TAB>source" "verify: a row with such a digit is refused by line number, not echoed, and nothing else is printed"

# usage
run; assert_eq "$rc" 2 "no subcommand: usage, exit 2"
assert_contains "$out" "tinkero-release verify LIST" "usage: names the subcommands"
run frobnicate; assert_eq "$rc" 2 "an unknown subcommand: exit 2"
run verify; assert_eq "$rc" 2 "verify without LIST: exit 2"
run --help; assert_eq "$rc" 0 "--help: exit 0"
assert_contains "$out" "TINKERO_RELEASE_REPO" "--help: names the environment"
rm -rf "$d"; finish
```

- [ ] **Step 2: Run it to see it fail**

Run: `bash tests/test-release.sh`
Expected: `1..70`, exit 1, 64 `not ok` (there is no `build/tinkero-release` yet). The six that pass without the tool are the two fixture checks (1, 2) and four absence checks (12, 19, 31, 41).

- [ ] **Step 3: `build/tinkero-release`**

The query is the design's (3.2), with one thing the design's text cannot show: dnf 5 (measured on 5.4.3) expands `\n` in a `--queryformat` argument but prints `\t` as the two characters backslash and t. So the separators are passed as real characters: the argument is written `$'%{name}\t%{version}\t%{release}\t%{arch}\t%{sourcerpm}\n'`, which bash turns into real tabs and a real newline before dnf sees it. `%{release}` carries the dist tag and `%{sourcerpm}` is a file name (`tinkero-4.0.4-2.fc44.src.rpm`); the fifth column is that name without `.src.rpm`.

```bash
#!/bin/bash
# tinkero-release: the release archive (Phase 3 design, section 3). A release is one tinkero
# package version, tagged <omarchy_tag>-<tinkero_rev>, with the newest build of every other
# package of the set. The release workflow runs these subcommands in order.
#
#   tinkero-release tag           print the release tag from the lock (v4.0.4-3)
#   tinkero-release list          print the COPR's newest binary packages, one per line:
#                                 name<TAB>version<TAB>release<TAB>arch<TAB>source
#   tinkero-release verify LIST   check LIST against the specs and the lock at this commit;
#                                 every mismatch is one FAIL line
#
# Exit status: 0 done, 1 a failure or a mismatch, 2 usage. Environment:
#   TINKERO_COPR_PROJECT  owner/project      (default dromero/tinkero)
#   TINKERO_RELEASE_REPO  the repository URL (default: the project's fedora-<N>-x86_64 results
#                                            on download.copr.fedorainfracloud.org)
#   TINKERO_ROOT          the checkout       (default: the directory above this script)
#   TINKERO_LOCK          the lock           (default: $TINKERO_ROOT/upstream.lock)
# Needs dnf 5 and rpmspec. Never packaged.
set -euo pipefail
# Every pattern below is matched in the C locale: under a collating UTF-8 locale bash's [0-9]
# and [a-z] admit the digits and letters of other scripts, and these patterns guard what
# reaches a command line, a tag and the release's page.
export LC_ALL=C
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${TINKERO_ROOT:-$(dirname "$here")}
# shellcheck source=build/lib.sh
source "$here/lib.sh"
lock=${TINKERO_LOCK:-$root/upstream.lock}
project=${TINKERO_COPR_PROJECT:-dromero/tinkero}
specs=$root/distro/fedora/specs

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }
bad_usage() { usage >&2; exit 2; }

cmd=${1:-}
case $cmd in
  -h|--help) usage; exit 0 ;;
  tag|list) [[ $# -eq 1 ]] || bad_usage ;;
  verify) [[ $# -eq 2 ]] || bad_usage ;;
  *) bad_usage ;;
esac

# The lock, parsed and checked: every value below is spliced into a file name, a URL or a tag.
tag=$(lock_get omarchy_tag "$lock"); rev=$(lock_get tinkero_rev "$lock"); fedora=$(lock_get fedora "$lock")
# Three parts, because tinkero-status --rollback looks for release tags of exactly this shape.
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "omarchy_tag must be vMAJOR.MINOR.PATCH to name a release: $tag"
[[ $rev =~ ^[0-9]+$ ]] || die "tinkero_rev must be an integer: $rev"
[[ $fedora =~ ^[0-9]+$ ]] || die "fedora must be an integer: $fedora"
release_tag=$tag-$rev                # the git tag and the release's name: v4.0.4-3
vr=${tag#v}-$rev.fc$fedora           # the tinkero RPM's version-release: 4.0.4-3.fc44
repo=${TINKERO_RELEASE_REPO:-https://download.copr.fedorainfracloud.org/results/$project/fedora-$fedora-x86_64/}

# check_list WHAT [FILE]: every line of FILE (default: standard input) is name, version,
# release, arch, source, tab-separated, each field from the alphabet RPM allows, no package
# twice. A bad line is named by number and never echoed: the rows come from the network, and a
# name is spliced into a dnf command line. WHAT names the rows in the message.
check_list() {
  awk -F'\t' -v what="$1" '
    function bad(msg) { printf "error: %s: line %d %s\n", what, NR, msg > "/dev/stderr"; rc = 1 }
    NF != 5 || $1 !~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/ || $2 !~ /^[A-Za-z0-9._+~^]+$/ ||
      $3 !~ /^[A-Za-z0-9._+~^]+$/ || $4 !~ /^(x86_64|noarch)$/ ||
      $5 !~ /^[A-Za-z0-9][A-Za-z0-9._+~^-]*-[A-Za-z0-9._+~^]+-[A-Za-z0-9._+~^]+$/ {
        bad("is not name<TAB>version<TAB>release<TAB>arch<TAB>source"); next }
    seen[$1 "." $4]++ { bad("lists " $1 "." $4 " a second time") }
    END { if (NR == 0) { print "error: " what ": no packages" > "/dev/stderr"; rc = 1 }; exit rc }
  ' "${2:--}"
}

cmd_list() {
  local raw out
  # dnf5 (measured on 5.4.3) expands \n in a query format but prints \t as the two characters,
  # so the separators here are real tabs and a real newline: $'...' makes them.
  raw=$(dnf -q repoquery "--repofrompath=tinkero-release,$repo" --repo=tinkero-release \
        --latest-limit=1 --arch=x86_64,noarch \
        --queryformat $'%{name}\t%{version}\t%{release}\t%{arch}\t%{sourcerpm}\n') || die "dnf repoquery failed for $repo"
  [[ -n $raw ]] || die "no packages in $repo"
  # Drop the debug packages (design D11); the fifth column becomes the source package's
  # name-version-release, which is its file name without .src.rpm.
  out=$(awk -F'\t' -v OFS='\t' '
    $1 ~ /-debug(info|source)$/ { next }
    NF != 5 || $5 !~ /\.src\.rpm$/ {
      printf "error: dnf repoquery: line %d is not a binary package with a source RPM\n", NR > "/dev/stderr"; exit 1 }
    { sub(/\.src\.rpm$/, "", $5); print }
  ' <<<"$raw" | LC_ALL=C sort) || exit 1
  [[ -n $out ]] || die "no packages in $repo"
  check_list "dnf repoquery" <<<"$out" || exit 1
  printf '%s\n' "$out"
}

cmd_verify() {
  local list=$1 rc=0 name version release source s_name s_vr p want got hypr hypr_next qs qs_rel
  local -A built=() listed=() bin_version=() bin_release=()
  [[ -f $list ]] || die "no such list: $list"
  check_list "$list" "$list" || exit 1
  [[ -f $specs/build-order.txt ]] || die "no build order: $specs/build-order.txt"
  fail() { echo "FAIL: $*"; rc=1; }

  # What the list holds: for every source, the version-release of each build it has packages
  # from (one, unless a newer build stopped producing a subpackage and the old one lingers).
  while IFS=$'\t' read -r name version release _ source; do
    s_vr=${source#"${source%-*-*}"-}; s_name=${source%-*-*}      # parsed from the right
    [[ " ${built[$s_name]-} " == *" $s_vr "* ]] || built[$s_name]+=" $s_vr"
    bin_version[$name]=$version; bin_release[$name]=$release
  done < "$list"

  # 1. Every package of the build order is the source of at least one line, and
  # 2. its version and release are the ones its spec (for tinkero, the lock) gives at this commit.
  while read -r p; do
    listed[$p]=1
    if [[ -z ${built[$p]-} ]]; then fail "$p: build-order.txt lists it, the COPR has no package built from it"; continue; fi
    if [[ $p == tinkero ]]; then
      want=$vr
    elif ! want=$(rpmspec -q --srpm --define "dist .fc$fedora" --queryformat '%{version}-%{release}\n' "$specs/$p.spec") || [[ -z $want ]]; then
      fail "$p: rpmspec could not read distro/fedora/specs/$p.spec"; continue
    fi
    want=${want%%$'\n'*}
    for got in ${built[$p]}; do
      if [[ $got != "$want" ]]; then
        if [[ $p == tinkero ]]; then fail "$p: the COPR has $got, the lock says $want"; else fail "$p: the COPR has $got, its spec says $want"; fi
      fi
    done
  done < <(grep -vE '^\s*(#|$)' "$specs/build-order.txt")
  while read -r s_name; do
    [[ -n ${listed[$s_name]-} ]] || fail "$s_name: the COPR has $s_name-${built[$s_name]# }, build-order.txt does not list it"
  done < <(printf '%s\n' "${!built[@]}" | LC_ALL=C sort)

  # 3. The lock's pins (spec 8, item 5): what the tinkero RPM requires must be in the set.
  hypr=$(lock_get hyprland "$lock"); qs=$(lock_get quickshell "$lock"); qs_rel=$(lock_get quickshell_release "$lock")
  [[ $hypr =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || die "hyprland must be MAJOR.MINOR.PATCH: $hypr"
  hypr_next="${BASH_REMATCH[1]}.$(( 10#${BASH_REMATCH[2]} + 1 ))"
  [[ $qs_rel =~ ^[0-9]+$ ]] || die "quickshell_release must be an integer: $qs_rel"
  at_least() { printf '%s\n%s\n' "$2" "$1" | sort -C -V; }     # $1 >= $2 in version order
  if [[ -z ${bin_version[hyprland]-} ]]; then
    fail "hyprland: the lock pins it, the list has no package of that name"
  elif ! at_least "${bin_version[hyprland]}" "$hypr" || at_least "${bin_version[hyprland]}" "$hypr_next"; then
    fail "hyprland: the COPR has ${bin_version[hyprland]}, the lock wants at least $hypr and below $hypr_next"
  fi
  if [[ -z ${bin_version[quickshell]-} ]]; then
    fail "quickshell: the lock pins it, the list has no package of that name"
  else
    [[ ${bin_version[quickshell]} == "$qs" ]] || fail "quickshell: the COPR has version ${bin_version[quickshell]}, the lock wants $qs"
    got=${bin_release[quickshell]%%.*}
    if [[ ! $got =~ ^[0-9]+$ ]] || (( 10#$got < 10#$qs_rel )); then
      fail "quickshell: the COPR has release ${bin_release[quickshell]}, the lock wants at least $qs_rel"
    fi
  fi

  if ((rc == 0)); then echo "PASS: $(wc -l < "$list") packages from ${#built[@]} sources match the specs and the lock at $release_tag"; fi
  return $rc
}

case $cmd in
  tag)    echo "$release_tag" ;;
  list)   cmd_list ;;
  verify) cmd_verify "$2" ;;
esac
```

`chmod +x build/tinkero-release`.

`export LC_ALL=C` is there for the patterns, not for the messages. Measured while planning, under `en_AU.utf8`: bash's `[[ v4.0.X =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]` matches when X is U+0665, a digit of another script, and does not under `C`; gawk's and `grep -E`'s bracket ranges, and bash's glob ranges, do not match it under either. So the lock's values and the `smoke` input (Task 2), which bash matches, are the ones the export protects; `check_list`, which is awk, refuses such a row in any locale. The test runs its locale cases (the lock's tag and a list row here, the `smoke` URL in Task 2) under a collating UTF-8 locale when `locale -a` lists one and under the caller's own locale when none is installed, as in CI's container, where the cases still pass and prove only the refusal.

- [ ] **Step 4: Run the tests and ShellCheck**

Run: `bash tests/test-release.sh` Expected: `1..70`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 build/tinkero-release tests/test-release.sh` Expected: no output.
Run: `build/tinkero-release tag` Expected: `v4.0.4-3` (the repository's lock after plan 3A; `v4.0.4-2` before it).
Run: `build/tinkero-release; echo $?` Expected: the usage text (seventeen lines, from `tinkero-release: the release archive` to `Needs dnf 5 and rpmspec. Never packaged.`) on stderr, then `2`.
Run: `./dev check` Expected: green; `tests/test-release.sh` is the one new line of files, every other tally as before. Not measured at planning time (the planning session ran under a no-delete rule and did not execute tests that delete files); the implementer measures it.

- [ ] **Step 5: First contact with the real repository (where the session has network and dnf 5)**

Run: `mkdir -p .cache; build/tinkero-release list > .cache/release-list.tsv; wc -l < .cache/release-list.tsv; cut -f5 .cache/release-list.tsv | sort -u | wc -l`
Expected: `36` and `26`, the figures of 2026-10-01 (they move when the set does). Not measured at planning time through the tool (the planning session was not allowed to run dnf; the same query, run by hand on 2026-10-01, printed the 75 rows the fixture holds); the implementer measures it. A session without network skips this step and says so on the issue: Task 5 is then the first contact.
Run (needs `rpmspec`, from `rpm-build` and `rpmdevtools`): `build/tinkero-release verify .cache/release-list.tsv; echo $?`
Expected, when plan 3A has merged and its COPR build has not happened yet: the single line `FAIL: tinkero: the COPR has 4.0.4-2.fc44, the lock says 4.0.4-3.fc44`, then `1`. Once `tinkero` 4.0.4-3 is built: `PASS: 36 packages from 26 sources match the specs and the lock at v4.0.4-3`, then `0`. Not measured at planning time (no `rpmspec` on the planning machine); the implementer measures it, and Task 3 puts the same `rpmspec` query into CI.

- [ ] **Step 6: Commit**

```bash
git add build/tinkero-release tests/test-release.sh
git commit -m "build: tinkero-release tag, list and verify (plan 3B; the release's set, checked against the specs and the lock)"
```

**Verification for the issue:** `bash tests/test-release.sh` at `1..70` with no `not ok`; ShellCheck clean; `build/tinkero-release tag` prints the lock's tag; Step 5's output when the session could run it.

---

### Task 2: `fetch`, `pack`, `install-sh`, `notes`

**Files:**
- Modify: `build/tinkero-release` (the header's subcommand list and tool list, the argument check, four functions, the dispatch), `tests/test-release.sh` (one block of cases before the last line)
- Test: `tests/test-release.sh`

**Interfaces:**
- Consumes: Task 1's `check_list`, the lock values (`release_tag`, `vr`, `fedora`, `repo`) and the stubs the test file already writes; the repository's `install.sh` with its two lines `TINKERO_REF=${TINKERO_REF:-master}` and `TINKERO_FEDORA=<N>` (2E design, D7); `dnf download`, `createrepo_c`, GNU `tar`, `sha256sum`.
- Produces:
  - `build/tinkero-release fetch LIST DEST`: one `dnf download --repofrompath=tinkero-release,<repo URL> --repo=tinkero-release --destdir=DEST` of every listed package as `name-version-release.arch`; then DEST must hold `name-version-release.arch.rpm` for every line and nothing else. Prints `fetched <n> packages into DEST`. Exit 1 naming each missing file and each stray one.
  - `build/tinkero-release pack DEST OUT`: `createrepo_c DEST`; writes `OUT/tinkero-<version>-<rev>.fc<N>-rpms.tar` (one top-level directory of the same name without `.tar`, holding the RPMs and `repodata/`), `OUT/RPMS.txt` (first line `Tinkero <tag> for Fedora <N>: <n> packages, <m> MiB`, then name, version-release and arch per package) and the tarball's line in `OUT/SHA256SUMS`. Prints the tarball's path. Exit 1 when DEST lacks `tinkero-<version>-<rev>.fc<N>.noarch.rpm`, holds anything that is not an RPM, or `createrepo_c` fails.
  - `build/tinkero-release install-sh OUT`: writes `OUT/install.sh` (mode 0755): the repository's `install.sh` with `TINKERO_REF=${TINKERO_REF:-master}` rewritten to `TINKERO_REF=${TINKERO_REF:-<tag>}` and `TINKERO_FEDORA=<N>` rewritten to the lock's `fedora`; adds its line to `OUT/SHA256SUMS`. Prints the path. Exit 1, writing nothing, unless each of the two lines is in the script exactly once and the result passes `bash -n`.
  - `build/tinkero-release notes OUT SMOKE_URL`: writes `OUT/NOTES.md` from the tag, the lock's Fedora release, SMOKE_URL and `OUT/RPMS.txt`. Prints the path. Exit 1 unless SMOKE_URL matches `^https://github\.com/dromeropa/tinkero/[A-Za-z0-9/#?=&_.%-]+$`, has no `.` or `..` path segment (a URL that a browser would resolve outside the repository is not a record in it), and `OUT/RPMS.txt` exists. `NOTES.md` is not an asset.
  - Task 3's workflow calls the four in this order and uploads `OUT`'s tarball, `install.sh`, `SHA256SUMS` and `RPMS.txt`.

Two things here are not in the design's table of subcommands (3.2); both are recorded under "## Deviations" by this task's PR. `notes` is a subcommand because the release's description (the tag, the smoke URL, the package table, the way back: design 3.3) and the check of the `smoke` input are more than a line of YAML, and the YAML is to stay thin. `install-sh` also writes its line into `OUT/SHA256SUMS`, because design 3.4 has `SHA256SUMS` cover the tarball and `install.sh` while 3.2 has `pack` write it before `install.sh` exists: each of the two subcommands owns its own line, in either order, any number of times.

`TINKERO_REF` keeps its `${TINKERO_REF:-...}` form (it is the script's one environment seam, 2E design D7 and issue #20); `TINKERO_FEDORA` is a plain pin.

- [ ] **Step 1: The failing tests**

In `tests/test-release.sh`, insert this block before the last line (`rm -rf "$d"; finish`):

```bash
# fetch: exactly the listed packages, by full name-version-release.arch
run fetch "$d/list" "$d/rpms"
assert_eq "$rc" 0 "fetch: exit 0"
assert_contains "$out" "fetched 36 packages into $d/rpms" "fetch: says what it did"
assert_eq "$(find "$d/rpms" -type f -name '*.rpm' | wc -l)" 36 "fetch: 36 files in DEST"
assert_file "$d/rpms/tinkero-4.0.4-2.fc44.noarch.rpm" "fetch: files are name-version-release.arch.rpm"
assert_eq "$(grep -c '^dnf ' "$LOG")" 1 "fetch: one dnf call"
assert_contains "$(cat "$LOG")" "dnf download --repofrompath=tinkero-release,https://download.copr.fedorainfracloud.org/results/dromero/tinkero/fedora-44-x86_64/ --repo=tinkero-release --destdir=$d/rpms aquamarine-0.14.0-1.fc44.x86_64 aquamarine-devel-0.14.0-1.fc44.x86_64 " "fetch: dnf download from the same repository, into DEST"
assert_contains "$(cat "$LOG")" " quickshell-0.3.0^20.git28771c7-2.fc44.x86_64 " "fetch: a package is asked for by its full version and release, so a superseded build cannot come instead"
DNF_SKIP=voxtype-1.0.1-1.fc44.x86_64 run fetch "$d/list" "$d/rpms-short"
assert_eq "$rc" 1 "fetch: a listed package that did not arrive is a failure"
assert_contains "$out" "voxtype-1.0.1-1.fc44.x86_64.rpm did not arrive" "fetch: and names the file"
DNF_EXTRA='quickshell-0.3.0^20.git28771c7-1.fc44.x86_64.rpm' run fetch "$d/list" "$d/rpms-extra"
assert_eq "$rc" 1 "fetch: a file in DEST that is not on the list is a failure"
assert_contains "$out" "quickshell-0.3.0^20.git28771c7-1.fc44.x86_64.rpm is in $d/rpms-extra but not on the list" "fetch: and names the file"
DNF_FAIL=1 run fetch "$d/list" "$d/rpms-fail"
assert_eq "$rc" 1 "fetch: dnf failing is a failure"; assert_contains "$out" "dnf download failed" "fetch: and says so"
run fetch "$d/list-opt" "$d/rpms-opt"
assert_eq "$rc" 1 "fetch: a list with an option-like name is refused"
assert_eq "$(grep -c '^dnf ' "$LOG")" 0 "fetch: before dnf is ever called"
assert_no_path "$d/rpms-opt" "fetch: and before DEST is created"
run fetch "$d/list"; assert_eq "$rc" 2 "fetch without DEST: exit 2"

# pack: DEST becomes a dnf repository inside one tarball, with the list and the checksum
T=$d/out/tinkero-4.0.4-2.fc44-rpms.tar
run pack "$d/rpms" "$d/out"
assert_eq "$rc" 0 "pack: exit 0"
assert_eq "$out" "$T" "pack: prints the tarball's path"
assert_contains "$(cat "$LOG")" "createrepo_c $d/rpms" "pack: createrepo_c on DEST"
members=$(tar -tf "$T")
assert_eq "$(grep -cv '^tinkero-4.0.4-2.fc44-rpms/' <<<"$members")" 0 "pack: one top-level directory, named as the tarball without .tar"
assert_eq "$(grep -c '\.rpm$' <<<"$members")" 36 "pack: the 36 RPMs"
assert_contains "$members" "tinkero-4.0.4-2.fc44-rpms/repodata/repomd.xml" "pack: and repodata/"
mkdir -p "$d/x"; tar -xf "$T" -C "$d/x"
assert_file "$d/x/tinkero-4.0.4-2.fc44-rpms/hyprland-0.56.2-1.fc44.x86_64.rpm" "pack: extracts to the directory the rollback command points dnf at"
assert_eq "$(sed -n 1p "$d/out/RPMS.txt")" "Tinkero v4.0.4-2 for Fedora 44: 36 packages, 0 MiB" "pack: RPMS.txt opens with the release and the totals"
assert_eq "$(wc -l < "$d/out/RPMS.txt")" 37 "pack: then one line per package"
assert_eq "$(awk '$1 == "herdr" { print $1, $2, $3 }' "$d/out/RPMS.txt")" "herdr 0.8.0^13.git0766aa5-1.fc44 x86_64" "pack: name, version-release, arch"
assert_eq "$(awk '$1 == "hyprland-preview-share-picker" { print $2, $3 }' "$d/out/RPMS.txt")" "0.2.1-1.fc44 x86_64" "pack: a hyphenated name is split from the right"
assert_eq "$(cd "$d/out" && sha256sum -c SHA256SUMS 2>&1)" "tinkero-4.0.4-2.fc44-rpms.tar: OK" "pack: SHA256SUMS carries the tarball's sum"
run pack "$d/rpms" "$d/out"
assert_eq "$rc" 0 "pack: a second run over the same DEST (repodata/ already there) is fine"
assert_eq "$(wc -l < "$d/out/SHA256SUMS")" 1 "pack: and leaves one line for the tarball, not two"
sed 's/^tinkero_rev=2/tinkero_rev=3/' "$r/upstream.lock" > "$d/lock-3"
TINKERO_LOCK=$d/lock-3 run pack "$d/rpms" "$d/out-3"
assert_eq "$rc" 1 "pack: a DEST without the tinkero RPM the lock names is refused"
assert_contains "$out" "has no tinkero-4.0.4-3.fc44.noarch.rpm" "pack: and names the file the tarball would be named after"
cp -r "$d/rpms" "$d/rpms-stray"; echo x > "$d/rpms-stray/list.tsv"
run pack "$d/rpms-stray" "$d/out-stray"
assert_eq "$rc" 1 "pack: a DEST holding anything but RPMs is refused"
assert_contains "$out" "not an RPM: list.tsv" "pack: and names it"
CREATEREPO_FAIL=1 run pack "$d/rpms" "$d/out-fail"
assert_eq "$rc" 1 "pack: createrepo_c failing is a failure"; assert_contains "$out" "createrepo_c failed" "pack: and says so"
assert_no_path "$d/out-fail/tinkero-4.0.4-2.fc44-rpms.tar" "pack: and no tarball is written"
run pack "$d/rpms"; assert_eq "$rc" 2 "pack without OUT: exit 2"

# install-sh: the repository's install.sh, pinned
run install-sh "$d/out"
assert_eq "$rc" 0 "install-sh: exit 0"
assert_eq "$out" "$d/out/install.sh" "install-sh: prints the path"
# shellcheck disable=SC2016  # the literal line of install.sh
assert_eq "$(grep -c '^TINKERO_REF=' "$d/out/install.sh") $(grep -cxF 'TINKERO_REF=${TINKERO_REF:-v4.0.4-2}' "$d/out/install.sh")" "1 1" "install-sh: TINKERO_REF defaults to the release tag"
assert_eq "$(grep -cx 'TINKERO_FEDORA=44' "$d/out/install.sh")" 1 "install-sh: TINKERO_FEDORA is the lock's fedora"
# with the repository's own Fedora release in the lock (the fixture's is the COPR's of 2026-10-01),
# the rewrite changes the TINKERO_REF line and nothing else, whatever release the repository is on
sed "s/^fedora=.*/fedora=$(sed -n 's/^fedora=//p' "$ROOT/upstream.lock")/" "$r/upstream.lock" > "$d/lock-own"
TINKERO_LOCK=$d/lock-own "$R" install-sh "$d/out-own" >/dev/null
assert_eq "$(diff "$ROOT/install.sh" "$d/out-own/install.sh" | grep -c '^[<>]')" 2 "install-sh: one line differs from the repository's install.sh, the rest is byte for byte"
assert_contains "$(bash "$d/out/install.sh" --help)" "bash install.sh [--yes]" "install-sh: the result runs"
assert_eq "$(cd "$d/out" && sha256sum -c SHA256SUMS 2>&1 | paste -sd'|')" "install.sh: OK|tinkero-4.0.4-2.fc44-rpms.tar: OK" "install-sh: SHA256SUMS now covers both files"
run install-sh "$d/out"; run pack "$d/rpms" "$d/out"
assert_eq "$(wc -l < "$d/out/SHA256SUMS")" 2 "SHA256SUMS: re-running either subcommand keeps one line per file"
sed 's/^fedora=44/fedora=45/' "$r/upstream.lock" > "$d/lock-45"
TINKERO_LOCK=$d/lock-45 run install-sh "$d/out-45"
assert_eq "$(grep -cx 'TINKERO_FEDORA=45' "$d/out-45/install.sh")" 1 "install-sh: a lock for another Fedora release rewrites the pin"
sed -i 's/:-master}$/:-main}/' "$r/install.sh"
run install-sh "$d/out-main"
assert_eq "$rc" 1 "install-sh: a TINKERO_REF line that is not the expected one is refused"
assert_contains "$out" "must be in install.sh exactly once, found 0" "install-sh: and says what it looked for"
assert_no_path "$d/out-main/install.sh" "install-sh: and nothing is written"
cp "$ROOT/install.sh" "$r/install.sh"; grep -x 'TINKERO_REF=.*' "$ROOT/install.sh" >> "$r/install.sh"
run install-sh "$d/out-ref2"
assert_eq "$rc" 1 "install-sh: two TINKERO_REF lines are refused"
assert_contains "$out" "must be in install.sh exactly once, found 2" "install-sh: and counts them"
cp "$ROOT/install.sh" "$r/install.sh"; echo 'TINKERO_FEDORA=45' >> "$r/install.sh"
run install-sh "$d/out-two"
assert_eq "$rc" 1 "install-sh: two TINKERO_FEDORA lines are refused"
assert_contains "$out" "a line TINKERO_FEDORA=<N> must be in install.sh exactly once, found 2" "install-sh: and counts them"
cp "$ROOT/install.sh" "$r/install.sh"; echo 'if true; then' >> "$r/install.sh"
run install-sh "$d/out-broken"
assert_eq "$rc" 1 "install-sh: a result that does not pass bash -n is refused"
assert_contains "$out" "does not parse" "install-sh: and says so"
assert_no_path "$d/out-broken/install.sh" "install-sh: and nothing is written"
cp "$ROOT/install.sh" "$r/install.sh"
run install-sh; assert_eq "$rc" 2 "install-sh without OUT: exit 2"

# notes: the release's description, from local facts and one checked URL
before=$(cd "$d/out" && sha256sum SHA256SUMS RPMS.txt install.sh ./*.tar)
run notes "$d/out" "https://github.com/dromeropa/tinkero/issues/60#issuecomment-4301122334"
assert_eq "$rc" 0 "notes: exit 0"
assert_eq "$out" "$d/out/NOTES.md" "notes: prints the path"
notes=$(cat "$d/out/NOTES.md")
assert_contains "$notes" "Tinkero v4.0.4-2 for Fedora 44" "notes: the tag and the Fedora release"
assert_contains "$notes" "bash <(curl -fsSL https://github.com/dromeropa/tinkero/releases/download/v4.0.4-2/install.sh)" "notes: the pinned install line"
assert_contains "$notes" "https://github.com/dromeropa/tinkero/issues/60#issuecomment-4301122334" "notes: the smoke record"
assert_contains "$notes" 'tinkero-status --rollback' "notes: the way back"
assert_contains "$notes" "tinkero-4.0.4-2.fc44-rpms.tar" "notes: the tarball by name"
assert_contains "$notes" "$(sed -n 2p "$d/out/RPMS.txt")" "notes: the package table"
assert_eq "$(cd "$d/out" && sha256sum SHA256SUMS RPMS.txt install.sh ./*.tar)" "$before" "notes: changes no asset"
run notes "$d/out" "https://example.com/dromeropa/tinkero/issues/60"
assert_eq "$rc" 1 "notes: a smoke URL outside the repository is refused"
assert_contains "$out" "must be a URL under https://github.com/dromeropa/tinkero/" "notes: and says what is wanted"
run notes "$d/out" "https://github.com/dromeropa/tinkero/../../other/repo/issues/60"
assert_eq "$rc" 1 "notes: a URL that climbs out of the repository with /../ is refused"
run notes "$d/out" "https://github.com/dromeropa/tinkero/./issues/60"
assert_eq "$rc" 1 "notes: a /./ segment is refused too"
run notes "$d/out" "https://github.com/dromeropa/tinkero-fork/issues/60"
assert_eq "$rc" 1 "notes: a repository whose name only starts the same is refused"
run notes "$d/out" 'https://github.com/dromeropa/tinkero/issues/60) [x](https://evil.example'
assert_eq "$rc" 1 "notes: a URL carrying Markdown is refused"
if grep -qF 'evil.example' <<<"$out"; then not_ok "notes: the refused text is not echoed"; else ok "notes: the refused text is not echoed"; fi
run notes "$d/out-45" "https://github.com/dromeropa/tinkero/issues/60"
assert_eq "$rc" 1 "notes: an OUT that pack has not filled is refused"; assert_contains "$out" "run pack first" "notes: and says so"
run notes "$d/out"; assert_eq "$rc" 2 "notes without SMOKE_URL: exit 2"
run_loc notes "$d/out" "https://github.com/dromeropa/tinkero/issues/6$five"
assert_eq "$rc" 1 "notes: a smoke URL with a digit of another script is refused, whatever the caller's locale"
assert_eq "$out" "error: notes: the smoke record must be a URL under https://github.com/dromeropa/tinkero/ (the issue or comment recording the VM smoke run)" "notes: not echoed, and nothing else is printed"
```

Run: `bash tests/test-release.sh`
Expected: `1..150`, exit 1, 68 `not ok`, the first of them `not ok 71 - fetch: exit 0`; cases 1 to 70 stay green. (Twelve of the new cases pass before the code exists: the four subcommands answer with the usage text and exit 2, which satisfies the "exit 2" and "nothing was written" assertions.)

- [ ] **Step 2: The four subcommands**

In `build/tinkero-release`:

```diff
--- a/build/tinkero-release
+++ b/build/tinkero-release
@@ -3,11 +3,18 @@
 # package version, tagged <omarchy_tag>-<tinkero_rev>, with the newest build of every other
 # package of the set. The release workflow runs these subcommands in order.
 #
-#   tinkero-release tag           print the release tag from the lock (v4.0.4-3)
-#   tinkero-release list          print the COPR's newest binary packages, one per line:
-#                                 name<TAB>version<TAB>release<TAB>arch<TAB>source
-#   tinkero-release verify LIST   check LIST against the specs and the lock at this commit;
-#                                 every mismatch is one FAIL line
+#   tinkero-release tag                  print the release tag from the lock (v4.0.4-3)
+#   tinkero-release list                 print the COPR's newest binary packages, one per line:
+#                                        name<TAB>version<TAB>release<TAB>arch<TAB>source
+#   tinkero-release verify LIST          check LIST against the specs and the lock at this
+#                                        commit; every mismatch is one FAIL line
+#   tinkero-release fetch LIST DEST      download exactly the listed packages into DEST
+#   tinkero-release pack DEST OUT        make DEST a dnf repository; write into OUT the tarball
+#                                        tinkero-<version>-<rev>.fc<N>-rpms.tar, RPMS.txt and
+#                                        SHA256SUMS
+#   tinkero-release install-sh OUT       write OUT/install.sh, pinned to the tag and to the
+#                                        lock's Fedora release, and add it to OUT/SHA256SUMS
+#   tinkero-release notes OUT SMOKE_URL  write OUT/NOTES.md, the release's description
 #
 # Exit status: 0 done, 1 a failure or a mismatch, 2 usage. Environment:
 #   TINKERO_COPR_PROJECT  owner/project      (default dromero/tinkero)
@@ -15,7 +22,7 @@
 #                                            on download.copr.fedorainfracloud.org)
 #   TINKERO_ROOT          the checkout       (default: the directory above this script)
 #   TINKERO_LOCK          the lock           (default: $TINKERO_ROOT/upstream.lock)
-# Needs dnf 5 and rpmspec. Never packaged.
+# Needs dnf 5, rpmspec, createrepo_c, tar and sha256sum. Never packaged.
 set -euo pipefail
 # Every pattern below is matched in the C locale: under a collating UTF-8 locale bash's [0-9]
 # and [a-z] admit the digits and letters of other scripts, and these patterns guard what
@@ -28,15 +35,17 @@
 lock=${TINKERO_LOCK:-$root/upstream.lock}
 project=${TINKERO_COPR_PROJECT:-dromero/tinkero}
 specs=$root/distro/fedora/specs
+site=https://github.com/dromeropa/tinkero
 
-usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }
+usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; }
 bad_usage() { usage >&2; exit 2; }
 
 cmd=${1:-}
 case $cmd in
   -h|--help) usage; exit 0 ;;
   tag|list) [[ $# -eq 1 ]] || bad_usage ;;
-  verify) [[ $# -eq 2 ]] || bad_usage ;;
+  verify|install-sh) [[ $# -eq 2 ]] || bad_usage ;;
+  fetch|pack|notes) [[ $# -eq 3 ]] || bad_usage ;;
   *) bad_usage ;;
 esac
 
@@ -49,6 +58,7 @@
 release_tag=$tag-$rev                # the git tag and the release's name: v4.0.4-3
 vr=${tag#v}-$rev.fc$fedora           # the tinkero RPM's version-release: 4.0.4-3.fc44
 repo=${TINKERO_RELEASE_REPO:-https://download.copr.fedorainfracloud.org/results/$project/fedora-$fedora-x86_64/}
+base=tinkero-$vr-rpms                # the tarball without .tar, and the directory inside it
 
 # check_list WHAT [FILE]: every line of FILE (default: standard input) is name, version,
 # release, arch, source, tab-separated, each field from the alphabet RPM allows, no package
@@ -149,8 +159,116 @@
   return $rc
 }
 
+cmd_fetch() {
+  local list=$1 dest=$2 rc=0 name version release arch f
+  local -a pkgs=()
+  local -A want=()
+  [[ -f $list ]] || die "no such list: $list"
+  check_list "$list" "$list" || exit 1
+  while IFS=$'\t' read -r name version release arch _; do
+    pkgs+=("$name-$version-$release.$arch"); want[$name-$version-$release.$arch.rpm]=1
+  done < "$list"
+  mkdir -p "$dest"
+  # Each package by its full name-version-release.arch: the COPR keeps superseded builds until
+  # it prunes them, and a bare name could resolve to any of them.
+  dnf download "--repofrompath=tinkero-release,$repo" --repo=tinkero-release "--destdir=$dest" "${pkgs[@]}" >&2 || die "dnf download failed for $repo"
+  # Exactly the listed packages: every file arrived, and DEST holds nothing else.
+  for f in "${pkgs[@]}"; do
+    [[ -f $dest/$f.rpm ]] || { echo "error: fetch: $f.rpm did not arrive in $dest" >&2; rc=1; }
+  done
+  while read -r f; do
+    [[ -n ${want[$f]-} ]] || { echo "error: fetch: $f is in $dest but not on the list" >&2; rc=1; }
+  done < <(find "$dest" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
+  ((rc == 0)) || exit 1
+  echo "fetched ${#pkgs[@]} packages into $dest"
+}
+
+# sum_line OUT FILE: write FILE's line into OUT/SHA256SUMS, keeping the lines of other files.
+# pack and install-sh each add their own asset, in either order, any number of times.
+sum_line() {
+  local out=$1 file=$2 sums=$1/SHA256SUMS lines=""
+  if [[ -f $sums ]]; then lines=$(awk -v f="$file" '$2 != f' "$sums"); fi
+  lines=$(printf '%s\n%s\n' "$lines" "$(cd "$out" && sha256sum "$file")" | grep . | LC_ALL=C sort -k2)
+  printf '%s\n' "$lines" > "$sums"
+}
+
+cmd_pack() {
+  local dest=$1 out=$2 f b nvr nv n=0 bytes=0 rows=""
+  [[ -d $dest ]] || die "no such directory: $dest"
+  [[ -f $dest/tinkero-$vr.noarch.rpm ]] || die "pack: $dest has no tinkero-$vr.noarch.rpm, the package the release is named after"
+  while read -r f; do
+    case $f in
+      *.rpm) ;;
+      repodata) ;;      # a second run: createrepo_c rewrites it
+      *) die "pack: $dest holds something that is not an RPM: $f" ;;
+    esac
+    [[ $f == repodata ]] && continue
+    # name-version-release.arch.rpm, split from the right: names have hyphens, versions do not
+    b=${f%.rpm}; nvr=${b%.*}; nv=${nvr%-*}
+    rows+=$(printf '%-42s %-30s %s' "${nv%-*}" "${nv##*-}-${nvr##*-}" "${b##*.}")$'\n'
+    n=$((n + 1)); bytes=$((bytes + $(stat -c %s "$dest/$f")))
+  done < <(find "$dest" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
+  createrepo_c "$dest" >&2 || die "createrepo_c failed on $dest"
+  [[ -f $dest/repodata/repomd.xml ]] || die "createrepo_c left no repodata/repomd.xml in $dest"
+  mkdir -p "$out"
+  printf 'Tinkero %s for Fedora %s: %d packages, %d MiB\n%s' "$release_tag" "$fedora" "$n" "$(( (bytes + 524288) / 1048576 ))" "$rows" > "$out/RPMS.txt"
+  # One top-level directory, named as the tarball: what tinkero-status --rollback extracts into
+  # $HOME and hands to dnf as --repofrompath. Not compressed: RPMs already are.
+  tar -C "$dest" --sort=name --owner=0 --group=0 --numeric-owner --transform "s,^\.,$base," -cf "$out/$base.tar" .
+  sum_line "$out" "$base.tar"
+  echo "$out/$base.tar"
+}
+
+cmd_install_sh() {
+  local out=$1 src=$root/install.sh n text
+  [[ -f $src ]] || die "no install.sh in $root"
+  # Each of the two lines exactly once, or the script has changed under this rewrite (2E design, D7).
+  # shellcheck disable=SC2016  # the literal line of install.sh
+  n=$(grep -cxF 'TINKERO_REF=${TINKERO_REF:-master}' "$src" || true)
+  [[ $n == 1 ]] || die "install-sh: the line TINKERO_REF=\${TINKERO_REF:-master} must be in install.sh exactly once, found $n"
+  n=$(grep -cxE 'TINKERO_FEDORA=[0-9]+' "$src" || true)
+  [[ $n == 1 ]] || die "install-sh: a line TINKERO_FEDORA=<N> must be in install.sh exactly once, found $n"
+  text=$(awk -v ref="$release_tag" -v fedora="$fedora" '
+    $0 == "TINKERO_REF=${TINKERO_REF:-master}" { print "TINKERO_REF=${TINKERO_REF:-" ref "}"; next }
+    /^TINKERO_FEDORA=[0-9]+$/ { print "TINKERO_FEDORA=" fedora; next }
+    { print }
+  ' "$src")
+  bash -n <<<"$text" || die "install-sh: the rewritten install.sh does not parse; nothing was written"
+  mkdir -p "$out"
+  printf '%s\n' "$text" > "$out/install.sh"
+  chmod 0755 "$out/install.sh"
+  sum_line "$out" install.sh
+  echo "$out/install.sh"
+}
+
+cmd_notes() {
+  local out=$1 smoke=$2 url='^https://github\.com/dromeropa/tinkero/[A-Za-z0-9/#?=&_.%-]+$' dots='/\.\.?([/#?]|$)'
+  # The one value that comes from outside: it is written into Markdown, so it must be a plain
+  # URL of this repository, with no . or .. segment that would lead out of it, and when it is
+  # not, it is not echoed either.
+  if [[ ! $smoke =~ $url || $smoke =~ $dots ]]; then
+    die "notes: the smoke record must be a URL under $site/ (the issue or comment recording the VM smoke run)"
+  fi
+  [[ -f $out/RPMS.txt ]] || die "notes: no $out/RPMS.txt; run pack first"
+  # shellcheck disable=SC2016  # the backticks are Markdown
+  {
+    printf 'Tinkero %s for Fedora %s: the `tinkero` package %s with the newest build of every other package of the set, as the COPR served them when the release was cut.\n\n' "$release_tag" "$fedora" "$vr"
+    printf 'Install, on Fedora %s Workstation with GDM, as your own user:\n\n' "$fedora"
+    printf '    bash <(curl -fsSL %s/releases/download/%s/install.sh)\n\n' "$site" "$release_tag"
+    printf 'VM smoke record for this build: %s\n\n' "$smoke"
+    printf 'The way back from this release is `tinkero-status --rollback`: it prints the downgrade to the release before this one. This release'"'"'s own tarball is what a later release goes back to.\n\n'
+    printf 'Assets: `%s.tar` is the binary RPM set as a dnf repository (extract it and point `--repofrompath` at the directory); `install.sh` is pinned to this tag and to Fedora %s; `SHA256SUMS` covers both; `RPMS.txt` is the list below.\n\n' "$base" "$fedora"
+    printf '```\n'; cat "$out/RPMS.txt"; printf '```\n'
+  } > "$out/NOTES.md"
+  echo "$out/NOTES.md"
+}
+
 case $cmd in
-  tag)    echo "$release_tag" ;;
-  list)   cmd_list ;;
-  verify) cmd_verify "$2" ;;
+  tag)        echo "$release_tag" ;;
+  list)       cmd_list ;;
+  verify)     cmd_verify "$2" ;;
+  fetch)      cmd_fetch "$2" "$3" ;;
+  pack)       cmd_pack "$2" "$3" ;;
+  install-sh) cmd_install_sh "$2" ;;
+  notes)      cmd_notes "$2" "$3" ;;
 esac
```

`dnf download` is given every package by its full `name-version-release.arch`, never by name: the COPR keeps superseded builds until it prunes them. The file dnf writes has no epoch in its name, and neither has the spec it is asked with (`xdg-desktop-portal-hyprland-1.4.1-1.fc44.x86_64` for a package whose epoch is 1); dnf matches a spec without an epoch against any epoch. Not measured at planning time (the planning session was not allowed to run dnf); Task 5's dry run is the first real `dnf download`, and `fetch`'s own check names the file if it did not arrive.

- [ ] **Step 3: Run the tests and ShellCheck**

Run: `bash tests/test-release.sh` Expected: `1..150`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 build/tinkero-release tests/test-release.sh` Expected: no output.
Run: `build/tinkero-release --help | wc -l` Expected: `24`.
Run: `build/tinkero-release install-sh .cache/release-try && diff install.sh .cache/release-try/install.sh`
Expected: `.cache/release-try/install.sh`, then a diff of exactly one line, `TINKERO_REF=${TINKERO_REF:-master}` becoming `TINKERO_REF=${TINKERO_REF:-v4.0.4-3}` (the repository's own `install.sh` and lock, after plan 3A; `.cache/` is ignored by git, and the directory is left where it is).
Run: `./dev check` Expected: green, `tests/test-release.sh` at `1..150`. Not measured at planning time (the planning session ran under a no-delete rule and did not execute tests that delete files); the implementer measures it.

- [ ] **Step 4: Commit**

```bash
git add build/tinkero-release tests/test-release.sh
git commit -m "build: tinkero-release fetch, pack, install-sh and notes (plan 3B; the four assets and the release's description)"
```

**Verification for the issue:** `bash tests/test-release.sh` at `1..150` with no `not ok`; ShellCheck clean; Step 3's one-line diff of the repository's own `install.sh`.

---

### Task 3: The `release` workflow

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `.github/workflows/ci.yml` (the ShellCheck list, the spec step), `tests/test-release.sh` (one block of cases before the last line)
- Test: `tests/test-release.sh`

**Interfaces:**
- Consumes: Tasks 1 and 2's seven subcommands; `ci/check-rpm RPM DIR` and `./dev gates-at DIR` (plan 2F, Task 5); the `fedora:44` container and the "inputs through `env:`" idiom of `copr-build.yml`.
- Produces: the workflow `release`, `workflow_dispatch` only, `permissions: contents: write`. Inputs: `smoke` (required; the URL of the issue or comment recording the VM smoke run for this build) and `dry_run` (boolean, default false). It refuses any ref but `refs/heads/master`, a `smoke` that does not start with `https://github.com/dromeropa/tinkero/`, a tag that already has a release, and a tag that exists without one. On a dry run it uploads `.cache/release/out` as the artifact `release-dry-run` (kept 7 days; an upload that finds no file fails the run) and creates nothing; otherwise it runs `gh release create <tag> --target "$GITHUB_SHA" --title "Tinkero <tag>" --notes-file NOTES.md` with the tarball, `install.sh`, `SHA256SUMS` and `RPMS.txt`. Task 5 dispatches it: `gh workflow run release --ref master -f smoke=<URL> [-f dry_run=true]`.

The workflow cannot run before it is on `master` (workflow guide, adaptation 1), so this task's proof is hermetic: the test extracts each step's `run:` block from the YAML by the step's name and runs it with `bash --noprofile --norc -eo pipefail`, which is how the runner runs it, against the stubs. What is left to shell in the YAML and is not in `build/tinkero-release` is the first step's four refusals (they need `gh` and the dispatch's ref) and one `gh release create`; both are executed by the test. Task 5 is the proof on GitHub.

The refusal of a tag that exists without a release is not in design 3.3's list of steps. It follows from D10 ("nobody pushes a tag by hand"): `gh release create --target` does not move an existing tag, so a hand-pushed tag would put the release on a commit nobody verified. `git/matching-refs` matches by prefix (`v4.0.4-2` also returns `v4.0.4-20`), hence the exact comparison.

- [ ] **Step 1: The failing tests**

In `tests/test-release.sh`, insert this block before the last line (`rm -rf "$d"; finish`):

```bash
# The release workflow (.github/workflows/release.yml): its own shell, run step by step against
# the stubs above and a stub gh, and the properties the design fixes for it.
Y=$ROOT/.github/workflows/release.yml
# gh: `api .../releases` prints $GH_RELEASES, `api .../git/matching-refs/tags/X` prints $GH_TAGS,
# one per line, as the workflow's --jq filters would.
cat > "$d/bin/gh" <<'S'
#!/bin/bash
echo "gh $*" >> "$LOG"
if [[ ${GH_FAIL:-0} == 1 ]]; then echo "gh: HTTP 502" >&2; exit 1; fi
case "$*" in
  *"/git/matching-refs/tags/"*) [[ -z ${GH_TAGS:-} ]] || printf '%s\n' $GH_TAGS ;;
  *"/releases "*) [[ -z ${GH_RELEASES:-} ]] || printf '%s\n' $GH_RELEASES ;;
esac
S
chmod +x "$d/bin/gh"
step() {   # NAME: the run block of the step of that name
  awk -v name="$1" '
    $0 == "      - name: " name { found = 1; next }
    found && /^      - / { exit }
    found && /^        run: \|$/ { body = 1; next }
    found && body && /^          / { print substr($0, 11) }
  ' "$Y"
}
run_step() {   # NAME: run it as the runner would (bash -eo pipefail), in the checkout, with the job's environment
  : > "$LOG"; step "$1" > "$d/step.sh"
  out=$(cd "$ROOT" && GITHUB_REF=${REF:-refs/heads/master} GITHUB_SHA=0123abc GH_REPO=dromeropa/tinkero W=$d/wf \
        SMOKE=${SMOKE-https://github.com/dromeropa/tinkero/issues/60} bash --noprofile --norc -eo pipefail "$d/step.sh" 2>&1) && rc=0 || rc=$?
}
for s in "Refusals" "The set the COPR serves, checked against this commit" "Download" \
         "The COPR's tinkero RPM passes what CI checks on its own build" "Pack" "Release"; do
  step "$s" > "$d/step.sh"
  if [[ -s $d/step.sh ]] && bash -n "$d/step.sh"; then ok "workflow: step '$s' has a run block that parses"; else not_ok "workflow: step '$s' has a run block that parses"; fi
done

run_step Refusals
assert_eq "$rc" 0 "workflow: master, a smoke URL of this repository, no such release and no such tag: go"
assert_contains "$out" "releasing v4.0.4-2 from 0123abc" "workflow: and says what it releases"
REF=refs/heads/task/x run_step Refusals
assert_eq "$rc" 1 "workflow: any ref but master is refused"
assert_contains "$out" "dispatch from master, not from refs/heads/task/x" "workflow: and says so"
assert_eq "$(grep -c '^gh ' "$LOG")" 0 "workflow: before anything is asked of GitHub"
SMOKE=https://example.com/issues/60 run_step Refusals
assert_eq "$rc" 1 "workflow: a smoke URL outside the repository is refused at the first step"
assert_contains "$out" "smoke must be a URL under https://github.com/dromeropa/tinkero/" "workflow: and says so"
GH_RELEASES="v4.0.4-1 v4.0.4-2" run_step Refusals
assert_eq "$rc" 1 "workflow: a tag that is already released is refused"
assert_contains "$out" "v4.0.4-2 is already released" "workflow: and says so"
GH_RELEASES="v4.0.4-1 v4.0.4-20" run_step Refusals
assert_eq "$rc" 0 "workflow: another release whose tag only starts the same does not refuse"
GH_TAGS="refs/tags/v4.0.4-2" run_step Refusals
assert_eq "$rc" 1 "workflow: a tag pushed by hand, without a release, is refused"
assert_contains "$out" "the tag v4.0.4-2 exists without a release" "workflow: and says so"
GH_TAGS="refs/tags/v4.0.4-20" run_step Refusals
assert_eq "$rc" 0 "workflow: a longer tag that the prefix query also returns does not refuse"
GH_FAIL=1 run_step Refusals
assert_eq "$rc" 1 "workflow: GitHub not answering is a failure, not 'no such release'"

# the steps in order, on the stub repository: list and verify, fetch, pack, release
run_step "The set the COPR serves, checked against this commit"
assert_eq "$rc" 0 "workflow: list and verify pass"; assert_contains "$out" "PASS: 36 packages from 26 sources" "workflow: verify's line is in the log"
run_step "Download"
assert_eq "$rc" 0 "workflow: fetch passes"
# shellcheck disable=SC2016  # $W is the step's own text
glob=$(step "The COPR's tinkero RPM passes what CI checks on its own build" | sed -n 's|^ci/check-rpm "\$W"/rpms/\([^ ]*\) .*|\1|p')
assert_eq "$(cd "$d/wf/rpms" && compgen -G "$glob")" "tinkero-4.0.4-2.fc44.noarch.rpm" "workflow: the glob the check-rpm step gives names the tinkero RPM alone, not tinkero-nerd-fonts"
run_step "Pack"
assert_eq "$rc" 0 "workflow: pack, install-sh, notes and the checksum check pass"
assert_contains "$out" "install.sh: OK" "workflow: sha256sum -c ran over the assets"
assert_contains "$(cat "$d/wf/out/NOTES.md")" "https://github.com/dromeropa/tinkero/issues/60" "workflow: the smoke input reaches the notes"
# shellcheck disable=SC2016  # the text must reach the step unexpanded
SMOKE='https://github.com/dromeropa/tinkero/issues/60 "$(id)"' run_step "Pack"
assert_eq "$rc" 1 "workflow: a smoke input with shell text in it stops at notes"
run_step "Release"
assert_eq "$rc" 0 "workflow: the release step runs"
assert_eq "$(grep '^gh ' "$LOG")" "gh release create v4.0.4-2 --target 0123abc --title Tinkero v4.0.4-2 --notes-file $d/wf/out/NOTES.md $d/wf/out/tinkero-4.0.4-2.fc44-rpms.tar $d/wf/out/install.sh $d/wf/out/SHA256SUMS $d/wf/out/RPMS.txt" "workflow: one gh release create, at the dispatched commit, with the notes and the four assets"

# what the design fixes about the file itself
assert_eq "$(awk '/^on:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on && /^  [a-z_]+:/ { print $1 }' "$Y")" "workflow_dispatch:" "workflow: dispatched by hand, no other trigger"
assert_eq "$(awk '/^permissions:/ { p = 1; next } p && /^[^ ]/ { p = 0 } p { print $1, $2 }' "$Y")" "contents: write" "workflow: contents: write and nothing else"
assert_eq "$(grep -c "^    container: fedora:$(sed -n 's/^fedora=//p' "$ROOT/upstream.lock")\$" "$Y")" 1 "workflow: the container is the lock's Fedora release"
# shellcheck disable=SC2016  # GitHub's expression syntax, not the shell's
assert_eq "$(grep -F '${{' "$Y" | grep -cvE '^ +(if|SMOKE|GH_TOKEN|GH_REPO): ')" 0 "workflow: no expression is spliced into a script (inputs arrive through env)"
assert_eq "$(grep -oE 'build/tinkero-release [a-z-]+|ci/check-rpm|\./dev gates-at|sha256sum -c|gh release create' "$Y" | sed 's/^build\/tinkero-release //' | paste -sd' ')" \
  "tag list verify fetch ci/check-rpm ./dev gates-at pack install-sh notes sha256sum -c tag gh release create" "workflow: the design's order, list to release"
# shellcheck disable=SC2016
assert_eq "$(grep -A1 -xF '      - name: Release' "$Y" | tail -n1)" '        if: ${{ !inputs.dry_run }}' "workflow: a dry run creates no release"
# shellcheck disable=SC2016
assert_eq "$(grep -A1 -xF '      - name: Dry run, the assets as a workflow artifact' "$Y" | tail -n1)" '        if: ${{ inputs.dry_run }}' "workflow: a dry run uploads the assets instead"
assert_eq "$(awk '/^      - name: Dry run, the assets as a workflow artifact$/ { s = 1; next } s && /^      - / { s = 0 } s' "$Y" | grep -c '^          if-no-files-found: error$')" 1 "workflow: an upload that finds no file fails the dry run"
```

Run: `bash tests/test-release.sh`
Expected: `1..188`, exit 1, 29 `not ok`, all of them among cases 151 to 188 (there is no `release.yml`); cases 1 to 150 stay green. (Nine of the new cases pass without the file because an empty step script exits 0; the six "has a run block that parses" cases are what keeps an empty or renamed step from passing.)

- [ ] **Step 2: `.github/workflows/release.yml`**

```yaml
name: release
# Cut a release: archive the RPM set the COPR serves and attach it, with a pinned install.sh,
# to a GitHub release whose tag this workflow creates (Phase 3 design, 3.3). Manual only, from
# master, after copr-build and the VM smoke test: docs/guides/release.md is the procedure.
# Every decision is in build/tinkero-release; tests/test-release.sh runs the steps below
# against stubs, by name, so a renamed step fails the test.
on:
  workflow_dispatch:
    inputs:
      smoke:
        description: "URL of the issue or comment recording the VM smoke run for this build (https://github.com/dromeropa/tinkero/...)"
        required: true
      dry_run:
        description: "Do everything except create the release; upload the assets as a workflow artifact"
        type: boolean
        default: false
permissions:
  contents: write
concurrency:
  group: release
  cancel-in-progress: false
defaults:
  run:
    shell: bash
jobs:
  release:
    runs-on: ubuntu-latest
    # The lock's fedora, as in ci: tests/test-release.sh fails when the two differ.
    container: fedora:44
    timeout-minutes: 30
    env:
      # the input reaches the shell through the environment, never spliced into a script
      SMOKE: ${{ inputs.smoke }}
      GH_TOKEN: ${{ github.token }}
      GH_REPO: ${{ github.repository }}
      W: .cache/release
    steps:
      - name: Tools
        run: dnf -y install git-core gh rpm-build rpmdevtools createrepo_c cpio diffutils findutils tar
      - uses: actions/checkout@v4
      - name: Trust the workspace
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"
      - name: Refusals
        run: |
          [[ $GITHUB_REF == refs/heads/master ]] || { echo "release: dispatch from master, not from $GITHUB_REF" >&2; exit 1; }
          [[ $SMOKE == https://github.com/dromeropa/tinkero/* ]] || { echo "release: smoke must be a URL under https://github.com/dromeropa/tinkero/" >&2; exit 1; }
          tag=$(build/tinkero-release tag)
          releases=$(gh api --paginate "repos/$GH_REPO/releases" --jq '.[].tag_name')
          refs=$(gh api --paginate "repos/$GH_REPO/git/matching-refs/tags/$tag" --jq '.[].ref')
          if grep -qxF "$tag" <<<"$releases"; then echo "release: $tag is already released" >&2; exit 1; fi
          if grep -qxF "refs/tags/$tag" <<<"$refs"; then echo "release: the tag $tag exists without a release; the workflow creates its own tag, and removing that one is the operator's act (docs/guides/release.md, section 5)" >&2; exit 1; fi
          echo "releasing $tag from $GITHUB_SHA"
      - name: The set the COPR serves, checked against this commit
        run: |
          mkdir -p "$W"
          build/tinkero-release list > "$W/list.tsv"
          build/tinkero-release verify "$W/list.tsv"
      - name: Download
        run: |
          build/tinkero-release fetch "$W/list.tsv" "$W/rpms"
      - name: The COPR's tinkero RPM passes what CI checks on its own build
        run: |
          # [0-9]: tinkero-nerd-fonts-*.noarch.rpm is in the same directory
          ci/check-rpm "$W"/rpms/tinkero-[0-9]*.noarch.rpm "$W/payload"
          ./dev gates-at "$W/payload"
      - name: Pack
        run: |
          build/tinkero-release pack "$W/rpms" "$W/out"
          build/tinkero-release install-sh "$W/out"
          build/tinkero-release notes "$W/out" "$SMOKE"
          ( cd "$W/out" && sha256sum -c SHA256SUMS )
      - name: Dry run, the assets as a workflow artifact
        if: ${{ inputs.dry_run }}
        uses: actions/upload-artifact@v4
        with:
          name: release-dry-run
          path: .cache/release/out
          if-no-files-found: error
          retention-days: 7
      - name: Release
        if: ${{ !inputs.dry_run }}
        run: |
          tag=$(build/tinkero-release tag)
          gh release create "$tag" --target "$GITHUB_SHA" --title "Tinkero $tag" --notes-file "$W/out/NOTES.md" \
            "$W"/out/tinkero-*-rpms.tar "$W/out/install.sh" "$W/out/SHA256SUMS" "$W/out/RPMS.txt"
```

Notes for the reader of the YAML:

- `inputs.smoke` is the only free text. It reaches the scripts as `$SMOKE`, quoted, never as a `${{ }}` expression inside a `run:` block; the test fails if any expression appears outside `if:` and the three `env:` lines.
- `GH_REPO` lets `gh` work without a git remote; `GH_TOKEN` is the job's own token, which `contents: write` lets create the release and its tag. No secret is used: the COPR's repository is public.
- The Tools step installs what the steps call: `gh`; `rpm-build` and `rpmdevtools` for `rpmspec` (as `ci`); `createrepo_c`; `cpio` for `ci/check-rpm`; `diffutils` and `findutils` for the gates. dnf 5 with `repoquery` and `download` is in the image. If plan 3A's `ci/check-rpm` or a gate has gained a tool by the time this lands, add it here too.
- `tinkero-[0-9]*.noarch.rpm`: the download directory also holds `tinkero-nerd-fonts-*.noarch.rpm`. The test takes this glob from the YAML's own text and expands it against the downloaded set.
- `if-no-files-found: error`: the action's default only warns, and a dry run with no artifact would be green. The action also leaves out hidden files by default; the path given here starts inside `.cache`, and whether that counts cannot be measured before the workflow is on `master`. If Task 5's dry run fails at this step with nothing found, the fix is `include-hidden-files: true`.
- The message for a tag without a release does not tell the reader to delete it: removing a remote tag is the operator's act (the guide, section 5).
- The artifact's `path` is written out (`.cache/release/out`, the value of `W` plus `/out`): `with:` is not shell, and `$W` would not expand there.

- [ ] **Step 3: CI**

In `.github/workflows/ci.yml`, the tool joins the ShellCheck list, and the step that parses every spec also asks each one the question `verify` asks, so that a spec `rpmspec -q` cannot answer in this container fails the PR and not the release:

```diff
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -30,7 +30,7 @@
           branding/render-wallpapers branding/inventory-images branding/contact-sheet
           tests/run tests/lib.sh tests/test-*.sh tests/fixtures/make-tree.sh install.sh tests/fixtures/make-payload.sh
           distro/fedora/replacements/* distro/fedora/lib/pkg.sh
-          distro/fedora/specs/srpm.sh build/tinkero-copr bin/tinkero-* distro/fedora/bin/*
+          distro/fedora/specs/srpm.sh build/tinkero-copr build/tinkero-release bin/tinkero-* distro/fedora/bin/*
       - name: Unit tests
         # TINKERO_PAM_REAL=1: tests/test_pam_real.py must run (the job is root in a container);
         # a missing prerequisite fails the job instead of skipping it.
@@ -48,6 +48,9 @@
         run: |
           for s in distro/fedora/specs/*.spec; do rpmspec -P "$s" > /dev/null || exit 1; done
           rpmlint distro/fedora/specs/*.spec
+          # what `build/tinkero-release verify` asks of each spec (plan 3B): one name and one
+          # version-release per spec, the dist tag from the lock
+          for s in distro/fedora/specs/*.spec; do rpmspec -q --srpm --define "dist .fc$(sed -n 's/^fedora=//p' upstream.lock)" --queryformat '%{name} %{version}-%{release}\n' "$s" || exit 1; done
       - name: One package SRPM builds the way COPR builds it (glaze, the smallest)
         run: |
           mkdir -p "$PWD/.cache/srpm-glaze"
```

- [ ] **Step 4: Run the tests, ShellCheck, and read the workflow**

Run: `bash tests/test-release.sh` Expected: `1..188`, no `not ok`.
Run: `shellcheck -x -e SC1090,SC1091 build/tinkero-release tests/test-release.sh` Expected: no output.
Run: `./dev check` Expected: green, `tests/test-release.sh` at `1..188`, every other tally as before this plan. Not measured at planning time (the planning session ran under a no-delete rule and did not execute tests that delete files); the implementer measures it.
On the pushed branch, CI's step "Package specs parse and lint" ends with 25 lines, one per spec in glob order, each `<name> <version>-<release>`, beginning `aquamarine 0.14.0-1.fc44`, `glaze 7.8.2-1.fc44`, `gpu-screen-recorder 5.14.1-1.fc44`, `herdr 0.8.0^13.git0766aa5-1.fc44` and ending `xdg-desktop-portal-hyprland 1.4.1-1.fc44`: the names and versions of the COPR's source packages on 2026-10-01, with no epoch. Not measured at planning time (no `rpmspec` on the planning machine; derived from each spec's `Version:` and `Release:` lines); the implementer reads it in the CI log. A spec that fails there needs a macro package: add it to the Tools step of both `ci.yml` and `release.yml`, and say so in the Deviations line.

Then read `release.yml` once more against design 3.3, line by line, since nothing can run it yet:

- the only trigger is `workflow_dispatch`; `permissions` is `contents: write` and nothing else; the container is `fedora:44`;
- the steps come in the design's order: refusals, `list`, `verify`, `fetch`, `ci/check-rpm` and `./dev gates-at`, `pack`, `install-sh`, `notes`, then the artifact or the release;
- the Release step carries `if: ${{ !inputs.dry_run }}` and the artifact step `if: ${{ inputs.dry_run }}`;
- `gh release create` has `--target "$GITHUB_SHA"` and exactly four asset paths.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/release.yml .github/workflows/ci.yml tests/test-release.sh
git commit -m "ci: the release workflow (dispatch only, creates its own tag); ShellCheck and the spec query for tinkero-release (plan 3B)"
```

**Verification for the issue:** `bash tests/test-release.sh` at `1..188` with no `not ok`; CI green on the branch, its spec step printing the 25 lines; the read of Step 4. The workflow's first run is Task 5.

---

### Task 4: Docs

**Files:**
- Create: `docs/guides/release.md`
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` (the status line, 4.6, 4.11, 4.12, section 8 item 5, the decision log's "COPR retention" row, section 12), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (the 3B row, a "What executing 3B added to the queue" section), `docs/guides/workflow.md` ("Where the build is", "Rules for agent sessions"), `CLAUDE.md` (one sentence)

**Interfaces:**
- Consumes: every earlier task's facts (the subcommands, the messages, the asset names).
- Produces: the guide Task 5 follows and plan 3C's bump checklist points at; a master spec that says what the code now does.

`README.md` is not edited here. Design 3.4 moves its install line to the release URL "once the first release exists", and until then that URL answers 404: the change is in Task 5's `docs:` PR.

Every edit below is an exact replacement: find the quoted text, which was in the file exactly once on 2026-10-01 (checked with `grep -cF`), and replace it with the block that follows. Plan 3A lands before this plan and edits some of the same documents; every quote below was checked against plan 3A's Docs task as drafted, and each is still in its file exactly once after 3A's edits. Where a quoted string is nevertheless no longer there word for word, apply the change to the sentence as it then reads and say so in the Deviations line. `2026-10-XX` is the date the branch is pushed.

- [ ] **Step 1: The release guide**

Create `docs/guides/release.md` with exactly this content:

````markdown
# Cutting a release

A release is one `tinkero` package version together with the newest build of every other package of the set, as the COPR serves them when the release is cut. Its git tag is `<omarchy_tag>-<tinkero_rev>` from `upstream.lock` (`v4.0.4-3`), the string `tinkero-provision` writes to `~/.local/state/tinkero/release`. The design is `docs/superpowers/specs/2026-10-01-phase-3-maintenance-release-design.md`, section 3, and spec 4.11.

A COPR build reaches users before its release exists. The release is not the publication: it is the archive and the pinned installer. COPR prunes superseded builds and only its administrators can turn that off, so a rollback that must still work next month needs the old RPMs somewhere else, and that place is the GitHub release.

The tool is `build/tinkero-release`; the workflow is `.github/workflows/release.yml`, dispatched by hand. The workflow creates the git tag by creating the release. Nobody pushes a tag by hand.

## 1. When

- Every `tinkero` version that was built in the COPR and passed the smoke test gets a release. `tinkero_rev` goes up whenever the package's content or dependencies change (spec 4.12), so every such change is a release.
- A change to the set that should be a point to roll back to (a Hyprland point release, a `herdr` bump) bumps `tinkero_rev` in the same PR and becomes a release that way.
- A Quickshell rebuild for a new Qt does not need one: the build it replaces cannot be installed beside the new Qt anyway.
- A release is cut once. A mistake is fixed forward: bump `tinkero_rev`, build, smoke, release. The workflow refuses a tag that exists.
- An agent session dispatches `release` only when its issue says so, as with `copr-build`.

## 2. The order

- [ ] **Merged.** The PR is on `master` and CI is green there.
- [ ] **Built.** `copr-build` ran from `master` for every package the PR changed, in build order, and for `tinkero` last:

      gh workflow run copr-build --ref master -f packages=tinkero -f command=build

- [ ] **Nothing since.** No commit that changes a package was merged after that build. The tag lands on the commit the workflow is dispatched at, and the checks compare versions, not content. Take the run that built `tinkero`, which is not always the newest run (a later build of another package would hide the commits merged before it):

      gh run list --workflow copr-build --status success --limit 10 --json databaseId,headSha,createdAt
      gh run view <id> --log | grep -c '==> building tinkero in'      # 1 for the run that built it
      built=<that run's headSha>
      git fetch origin && git log --oneline "$built"..origin/master

  Docs, tests, CI and `build/` tooling in that list are fine. A change to the payload, a patch, a replacement or a spec without a `tinkero_rev` or `Release:` bump is not: bump, build again, start over.
- [ ] **Smoke.** The VM smoke test passed against the COPR's build, and an issue or a comment in this repository records it: `./dev vm-smoke` once plan 3D has landed (`docs/guides/vm-smoke.md`), or a manual pass of `docs/guides/phase-2f-vm-check.md` on the same package version (design D23). Keep the record's URL: it is the `smoke` input.
- [ ] **Dry run** (section 3), then **the release** (section 4).

## 3. The dry run

On a Fedora machine with the checkout, no token needed (the COPR's repository is public; `verify` needs `rpmspec`, from `rpm-build` and `rpmdevtools`):

    mkdir -p .cache
    build/tinkero-release tag
    build/tinkero-release list > .cache/release-list.tsv
    build/tinkero-release verify .cache/release-list.tsv

`list` prints one line per binary package, `name<TAB>version<TAB>release<TAB>arch<TAB>source`, the newest build of each, without `-debuginfo` and `-debugsource`. `verify` prints one `PASS:` line, or one `FAIL:` line per mismatch (section 5). dnf caches the repository's metadata: a `list` taken minutes after a COPR build can still show the build before it, in which case `dnf clean metadata` and list again. The workflow's container always starts empty.

On GitHub, the whole workflow without the last step:

    gh workflow run release --ref master -f smoke=<URL of the smoke record> -f dry_run=true
    run=$(gh run list --workflow release --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run watch "$run"
    gh run download "$run" -n release-dry-run -D .cache/release-dry-run

`gh run list` straight after `gh workflow run` can still show the run before, or none: wait until the new run is listed (its `createdAt` is now) before taking its id.

Read, in `.cache/release-dry-run`:

- [ ] `sha256sum -c SHA256SUMS` prints `OK` for `install.sh` and for the tarball.
- [ ] `RPMS.txt` opens with the tag, the Fedora release, the package count and the size, and lists what you expect to ship: `tinkero` at the version being released, `hyprland` and `quickshell` at the lock's pins.
- [ ] `diff <(git show origin/master:install.sh) install.sh` shows one line, `TINKERO_REF=${TINKERO_REF:-<tag>}`.
- [ ] `tar -tf tinkero-*-rpms.tar` shows one top-level directory, named as the tarball without `.tar`, holding the RPMs and `repodata/`.
- [ ] `NOTES.md` is what the release page will say.
- [ ] In the run's log: `verify`'s `PASS:` line, `ci/check-rpm`'s `PASS:` line for the COPR's `tinkero` RPM, and the gates' `PASS:` lines for its payload.

## 4. The release

    gh workflow run release --ref master -f smoke=<URL of the smoke record>
    gh run watch "$(gh run list --workflow release --limit 1 --json databaseId --jq '.[0].databaseId')"
    gh release view "$(build/tinkero-release tag)"

The workflow, in order: refuses (section 5); `list` and `verify`; `fetch`; `ci/check-rpm` and `./dev gates-at` on the downloaded `tinkero` RPM; `pack`, `install-sh`, `notes`; `gh release create <tag> --target <the dispatched commit>` with the four assets.

| Asset | Content |
|---|---|
| `tinkero-<version>-<rev>.fc<N>-rpms.tar` | the binary RPM set as a dnf repository: one directory of the same name, holding the RPMs and `repodata/` |
| `install.sh` | the repository's `install.sh` with `TINKERO_REF` defaulting to the tag and `TINKERO_FEDORA` set to the lock's `fedora` |
| `SHA256SUMS` | the checksums of the two files above |
| `RPMS.txt` | the package list: name, version-release, architecture |

`https://github.com/dromeropa/tinkero/releases/latest/download/install.sh` always serves the newest release's installer. It is the README's install line from the first release on.

## 5. What stops a release

The workflow's first step refuses, before anything is downloaded:

| Message | Why |
|---|---|
| `release: dispatch from master, not from <ref>` | a release is cut from `master` only |
| `release: smoke must be a URL under https://github.com/dromeropa/tinkero/` | the smoke record must be an issue or a comment of this repository |
| `release: <tag> is already released` | a release is cut once; bump `tinkero_rev` for the next |
| `release: the tag <tag> exists without a release` | somebody pushed the tag by hand. Removing a remote tag is the operator's act, never an agent session's: a session that meets this message stops and reports it; Diego removes the tag (`git push origin :refs/tags/<tag>`), and the workflow is dispatched again |

`verify` prints every mismatch between the COPR and the commit, then stops the run:

| Line | Means | Do |
|---|---|---|
| `FAIL: <pkg>: the COPR has X, its spec says Y` | a spec was merged and not built | `copr-build` for `<pkg>`, then the smoke test again |
| `FAIL: tinkero: the COPR has X, the lock says Y` | the tag or `tinkero_rev` moved and `tinkero` was not rebuilt | `copr-build` for `tinkero`, then the smoke test |
| `FAIL: <pkg>: build-order.txt lists it, the COPR has no package built from it` | a new package was never built | `copr-build` for `<pkg>` |
| `FAIL: <pkg>: the COPR has <source>, build-order.txt does not list it` | the COPR still serves a package the set dropped | delete the package in the COPR project, wait for the repository to regenerate |
| `FAIL: hyprland: the COPR has V, the lock wants at least A and below B` | the lock check (spec 8, item 5): the `tinkero` RPM could not be installed beside this Hyprland | fix the lock or the spec, in a PR |
| `FAIL: quickshell: the COPR has version V, the lock wants W` or `has release R, the lock wants at least N` | the same, for Quickshell | the same |
| `FAIL: <pkg>: the lock pins it, the list has no package of that name` | the pinned package is missing from the COPR | build it |
| `FAIL: <pkg>: rpmspec could not read distro/fedora/specs/<pkg>.spec` | the spec does not parse where the workflow runs | read rpmspec's own message above the line |

`fetch` stops when a listed file did not arrive or when the download directory holds a file that is not on the list; `pack` when the directory lacks the `tinkero` RPM the lock names; `install-sh` when `install.sh` no longer has exactly one `TINKERO_REF=${TINKERO_REF:-master}` line and one `TINKERO_FEDORA=<N>` line, or when the rewritten script does not parse.

## 6. Rolling back, and the drill

On a machine, `tinkero-status --rollback` prints the way back to the release before the installed one. By hand it is, with `<prev>` the tag to go back to and `<file>` its tarball's name:

    # log into GNOME first: your GNOME session is untouched
    sudo dnf downgrade tinkero hyprland quickshell     # enough while the COPR still has the older builds
    # once it has pruned them:
    curl -fLO https://github.com/dromeropa/tinkero/releases/download/<prev>/<file>.tar
    curl -fLO https://github.com/dromeropa/tinkero/releases/download/<prev>/SHA256SUMS
    sha256sum -c --ignore-missing SHA256SUMS
    tar -xf <file>.tar -C "$HOME"
    sudo dnf downgrade --repofrompath=tinkero-rollback,"$HOME/<file>" tinkero hyprland quickshell

The downgrade is resolved inside the extracted repository, so the older `hyprutils`, `aquamarine` and the rest come with the three named packages.

**The drill** proves that command on a VM or a second machine, never on the machine you work on. It needs two releases to move between:

- [ ] Install the newer release (`install.sh` from its release page), log into Tinkero once, log out, log into GNOME.
- [ ] Disable the COPR for the test (`sudo dnf copr disable dromero/tinkero`), so that only the archive can answer.
- [ ] Run the archive commands above for the older release. Record the transaction dnf prints: which packages it downgrades, whether it asks for `--allowerasing`, whether `gpgcheck` passes with the COPR's key already in the RPM keyring.
- [ ] `rpm -q tinkero hyprland quickshell` shows the older release's versions; log into Tinkero; `tinkero-status` runs.
- [ ] Record the exact command that worked on the drill's issue. If it differs from what `tinkero-status --rollback` prints, open an issue to correct the text.

While only one release exists there is nothing to downgrade to. The drill then checks what can be checked: the tarball is a repository dnf accepts, and a `dnf reinstall` of the three packages from it passes `gpgcheck` (the first release's issue has the steps). The real downgrade waits for the second release.
````

- [ ] **Step 2: The master spec**

In `docs/superpowers/specs/2026-09-17-tinkero-design.md`:

**1.** The status line. Replace

````text
. Fedora 44 x86_64 is the first target.
````

with

````text
; 3B (the release archive) done 2026-10-XX (plan: 2026-10-01-phase-3b-release-archive.md), the first release and the rollback drill being its post-merge issue. Fedora 44 x86_64 is the first target.
````

**2.** 4.6, the first paragraph (the release URL of the Phase 3 design, 3.4). Replace

````text
It is fetched from a **tagged release URL**, not a branch, and is run as the desktop user, never as root.
````

with

````text
It is fetched from a **tagged release URL**, not a branch, and is run as the desktop user, never as root. The URL is `https://github.com/dromeropa/tinkero/releases/latest/download/install.sh`: every release carries its own `install.sh` as an asset, pinned to the release's tag and Fedora release (4.11; plan 3B).
````

**3.** 4.6, the paragraph on plan 2E's two details. Replace

````text
pinned to the lock's `fedora` key by a test and rewritten by the release workflow together with `TINKERO_REF`.
````

with

````text
pinned to the lock's `fedora` key by a test and rewritten at release time, together with `TINKERO_REF`, by `build/tinkero-release install-sh`, which fails unless each of the two lines is in the script exactly once and the result parses (Phase 3 design, 3.2).
````

**4.** 4.11, the rollback paragraph: the archive's form (D9 to D12). The quote stops at the comma: the clause that follows it ("so `tinkero-status` ... can print a `dnf downgrade` command that points at those files, and a rollback works even after COPR has pruned the build") is plan 3A's to amend and stays as 3A left it, so the paragraph says what `--rollback` prints once. Replace

````text
The old RPMs come from the **release archive**, not from the COPR: the release process (Phase 3's workflow) downloads the RPM set of every tagged release from the COPR and attaches it to the matching GitHub release,
````

with

````text
The old RPMs come from the **release archive**, not from the COPR. A release is one `tinkero` package version with the newest build of every other package of the set; its git tag is `<omarchy_tag>-<tinkero_rev>` (`v4.0.4-3`), created by the manually dispatched `release` workflow and never pushed by hand (Phase 3 design, D9 and D10; the procedure is `docs/guides/release.md`). `build/tinkero-release` reads the set from the COPR's published repository with dnf (the binary packages, the newest build of each, no sources and no debuginfo: D12), checks it against the specs and the lock at the released commit, and attaches it to the GitHub release as one tarball that is a dnf repository, `tinkero-<version>-<rev>.fc<N>-rpms.tar` (D11), beside the pinned `install.sh`, `SHA256SUMS` and `RPMS.txt`,
````

**5.** 4.12, the `hyprland` bullet (the lock check moves from CI to the release, D24). Replace

````text
CI fails if the COPR's Hyprland does not satisfy the lock.
````

with

````text
`build/tinkero-release verify` fails, and the release with it, if the COPR's Hyprland does not satisfy the lock (section 8, item 5).
````

**6.** 4.12, the `tinkero_rev` bullet (D9): append to its last sentence. Replace

````text
(issue #48, after #46's PAM and Quickshell change shipped as a second `4.0.4-1`).
````

with

````text
(issue #48, after #46's PAM and Quickshell change shipped as a second `4.0.4-1`). A `tinkero` package version is also what a release is: `<omarchy_tag>-<tinkero_rev>` is the release's tag (4.11), so a change to the set that should be a point to roll back to bumps `tinkero_rev` too (Phase 3 design, D9).
````

**7.** Section 11, the "COPR retention" row, its Choice cell. Replace

````text
each release's RPM set is attached to its GitHub release and `tinkero-status` prints the downgrade command against it
````

with

````text
each release (a `tinkero` package version, tagged `<omarchy_tag>-<tinkero_rev>` by the `release` workflow) carries its binary RPM set as one tarball that is a dnf repository, read from the COPR's published repository and checked against the specs and the lock, and `tinkero-status --rollback` prints the downgrade command against it (Phase 3 design, D9 to D12)
````

**8.** Section 8, item 5 (D24: say only that the release runs the lock check; plan 3C adds the weekly half). Replace

````text
a JSONC parse of the built menu, and a lock check (COPR's Hyprland and Quickshell satisfy `upstream.lock`).
````

with

````text
a JSONC parse of the built menu. The lock check (COPR's Hyprland and Quickshell satisfy `upstream.lock`) is not a push check, because a COPR build is post-merge and the check would fail between the merge of a spec bump and its build: `build/tinkero-release verify` runs it when a release is cut (Phase 3 design, D24).
````

**9.** Section 12, the workflows line. Replace

````text
  .github/workflows/               CI, upstream watch, Qt watch
````

with

````text
  .github/workflows/               CI, copr-build, release, upstream watch, Qt watch
````

**10.** Section 12, the `build/` line. Replace

````text
  build/                           assemble, fetch-upstream, render-spec, drop.list
````

with

````text
  build/                           assemble, fetch-upstream, render-spec, drop.list, tinkero-copr,
                                   tinkero-release (the release archive, 4.11)
````

**11.** Section 12, the guides: add a line after the spike guide's. Replace

````text
  docs/guides/phase-0-spike.md     the VM spike procedure
````

with

````text
  docs/guides/phase-0-spike.md     the VM spike procedure
  docs/guides/release.md           cutting a release, its assets, the rollback drill
````

Section 8's item 6 and section 4.7 are plan 3D's and 3C's to amend, and 4.1's sentence that the weekly workflow "triggers the rebuild" is 3C's (design D14): leave them.

- [ ] **Step 3: The roadmap**

In `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (the row keeps its first three cells; only the Status cell changes):

**1.** The 3B row's Status cell. Replace

````text
**planned** 2026-10-01: `2026-10-01-phase-3b-release-archive.md`; awaiting approval. One orchestrated issue; the first release and the rollback drill are a post-merge issue
````

with

````text
**done** 2026-10-XX: `2026-10-01-phase-3b-release-archive.md`; the first release (`v4.0.4-3`) and the rollback drill are its post-merge issue
````

**2.** A new section, immediately above the heading quoted here. That is the place for every "## What executing 3X added to the queue" section of Phase 3, so that they read in order below "## What planning Phase 3 added to the queue": planning, 3A, 3B, 3C, 3D. Plan 3A's section is already there, directly above this heading; this one goes between it and the heading. Replace

````text
## What the first real assembly found (inputs to 2B and 2C)
````

with

````text
## What executing 3B added to the queue (2026-10-XX)

- **Post-merge (this plan's own issue):** the first release, `v4.0.4-3` (Task 5): a `dry_run` dispatch, the real dispatch with its `smoke` record, the drill on the one release that exists, and the README's install line, which moves to the release URL only then (design 3.4). It is `blocked by` the code issue and by 3A's post-merge issue (the COPR build of `tinkero` 4.0.4-3).
- **3C, the weekly workflow:** the lock check is `build/tinkero-release list > LIST` then `build/tinkero-release verify LIST`: exit 0 and one `PASS:` line, or exit 1 and one `FAIL:` line per mismatch. The job needs `rpm-build` and `rpmdevtools` (for `rpmspec`) beside dnf. `verify` also fails on a spec that was merged and not yet built, so a weekly run between a spec bump's merge and its COPR build is red, and that is the signal.
- **3C, the bump checklist:** its last stage is `docs/guides/release.md`, section 2 (built, nothing since, smoke, dry run, release). A package dropped from `build-order.txt` must also be deleted from the COPR project, or `verify` refuses the release.
- **`tinkero-status --rollback` (3A):** the asset it names is `tinkero-<version>-<rev>.fc<N>-rpms.tar`, and the tarball extracts to one directory of that name without `.tar`. Task 5's drill records the command that worked; a difference from the printed text is a follow-up issue.
- **The rollback drill between two releases:** its own issue, filed by Task 5, blocked until a second release exists (the next `tinkero_rev` or the first bump). It is the only proof that dnf5 downgrades the dependencies without `--allowerasing`.
- **Fedora 45:** the tarball's name carries `.fc<N>`, so two sets can sit on one release, but `build/tinkero-release` packs one set per lock and `releases/latest/download/install.sh` serves one Fedora release. Part of the Fedora 45 issue.
- **Not built, by decision:** source RPMs and debuginfo in the archive (design D11); a check that `master` has no payload change since the COPR build (the guide's "Nothing since" step makes the operator look; `verify` compares versions, not content); replacing or deleting a release (a mistake is fixed forward with the next `tinkero_rev`).

## What the first real assembly found (inputs to 2B and 2C)
````

- [ ] **Step 4: The workflow guide and `CLAUDE.md`**

In `docs/guides/workflow.md`:

**1.** "Where the build is": a new last bullet of that section, directly above the blank line before the heading quoted here. Replace

````text
## The loop
````

with

````text
- 3B (the release archive) landed 2026-10-XX: `build/tinkero-release`, the `release` workflow and
  `docs/guides/release.md`. The first release (`v4.0.4-3`) and the rollback drill are its
  post-merge issue.

## The loop
````

**2.** "Rules for agent sessions": a new bullet after the `copr-build` one. Replace

````text
- `copr-build` publishes to the user's COPR: trigger it only when the issue says so.
````

with

````text
- `copr-build` publishes to the user's COPR: trigger it only when the issue says so.
- `release` creates a git tag and a GitHub release: dispatch it only when the issue says so, and
  only with a `smoke` URL whose record you have read (`docs/guides/release.md`).
````

Then, in the same section, take 3B out of the sentence plan 3A left in the Phase 3 bullet. When that bullet ends with the first line below (3A's wording), change it to the second; when the line is not there, there is nothing to change:

````text
  issues of 3B, 3C and 3D await approval.
````

````text
  issues of 3C and 3D await approval.
````

In `CLAUDE.md`:

**1.** The conventions paragraph: `release` joins `copr-build`. Replace

````text
publishes to the user's COPR and is triggered only when an issue says so.
````

with

````text
publishes to the user's COPR and is triggered only when an issue says so, and so is `release`
(a tag and a GitHub release; `docs/guides/release.md`).
````

- [ ] **Step 5: Verify and commit**

Run: `./dev check` Expected: green (no test reads these documents). Not measured at planning time (the planning session ran under a no-delete rule and did not execute tests that delete files); the implementer measures it.
Run: `git add docs CLAUDE.md`, then `git diff --cached -U0 -- docs CLAUDE.md | grep '^+' | grep -c "$(printf '\xe2\x80\x94')"` Expected: `0` (no em dash added; staged first, because an unstaged diff does not show the new guide, and the `printf` spells the character so that this plan does not contain one).
Run: `grep -c 'tinkero-release' docs/superpowers/specs/2026-09-17-tinkero-design.md` Expected: `5` (4.6, 4.11, 4.12, section 8 and section 12, one line each; read as "5 more than before" if plan 3A's edits already named the tool).
Run: `grep -c 'releases/latest/download/install.sh' docs/guides/release.md docs/superpowers/specs/2026-09-17-tinkero-design.md README.md` Expected: `1`, `1` and `0` (the README keeps the `master` URL until Task 5).
Run: `grep -c '^## What executing 3[AB] added to the queue' docs/superpowers/plans/2026-09-17-phase-2-roadmap.md; grep -n '^## What' docs/superpowers/plans/2026-09-17-phase-2-roadmap.md | sed -n '1,4p'` Expected: `2`, then the headings in the order planning Phase 3, executing 3A, executing 3B, the first real assembly.

```bash
git commit -m "docs: 3B done, the release archive; the release guide, spec amendments (D9 to D12, D24), roadmap queue"
```

**Verification for the issue:** the five commands, CI green, and the reviewer reads each edit against the Phase 3 design's decisions D9 to D12, D23 and D24. The `2026-10-XX` placeholders become the date the branch is pushed; the merge date is the operator's.

---

### Task 5: The first release and the rollback drill (post-merge, closed by hand)

**Files:** none in the code PR. This task's deliverables are the release `v4.0.4-3`, a record on its issue, and one small `docs:` PR (`README.md`'s install line, one roadmap line).

**Interfaces:**
- Consumes: Tasks 1 to 4 on `master`; the COPR build of `tinkero` 4.0.4-3, which is plan 3A's post-merge issue; a smoke record for that build, which is plan 3D's first run or a manual pass of `docs/guides/phase-2f-vm-check.md` on 4.0.4-3 (design D23). The #37 check was made on an earlier build and cannot be cited. A Fedora 44 VM for the drill, never a machine somebody works on.
- Produces: the first GitHub release, tag `v4.0.4-3`, with four assets; the proof that the workflow, real `dnf download`, real `rpmspec` and real `createrepo_c` do what the stubs assumed; the half of the rollback drill one release allows; the issue for the other half.

Dispatch this issue only after the code PR has merged and plan 3A's post-merge issue is closed. `release` creates a tag and a public release, and this issue is the one that says to dispatch it. A failure at any step is a new issue against the task that owns the cause; its fix lands through the loop, and this issue stays open and resumes at the step that failed. One refusal is never worked around by the session: if the workflow says the tag exists without a release, the session stops and reports it, because removing a remote tag is the operator's act (the guide, section 5).

**Decided for the drill:** only one release exists when this task runs, so there is nothing to downgrade to. This task runs the archive path against that one release (Step 4: the tarball is a repository dnf accepts, a `dnf reinstall` from it passes `gpgcheck`, and dnf's answer to the printed downgrade command is recorded), and files the real downgrade between two releases as its own issue, blocked until a second release exists. This task does not wait for it.

- [ ] **Step 1: Preconditions**

On a Fedora 44 machine with the checkout at `master`, `dnf` 5, `rpm-build` and `rpmdevtools`:

Run: `build/tinkero-release tag` Expected: `v4.0.4-3`.
Run: `mkdir -p .cache && build/tinkero-release list > .cache/release-list.tsv && build/tinkero-release verify .cache/release-list.tsv`
Expected: `PASS: 36 packages from 26 sources match the specs and the lock at v4.0.4-3` (the counts of 2026-10-01; they move with the set). `FAIL: tinkero: the COPR has 4.0.4-2.fc44, the lock says 4.0.4-3.fc44` means plan 3A's build has not happened: stop, this issue is blocked by it. Not measured at planning time (no dnf run and no `rpmspec` in the planning session); if the code issue's session skipped Task 1's Step 5, this is the tool's first contact with real dnf and real `rpmspec`: record anything that differs.
Run: `grep -c "$(printf 'xdg-desktop-portal-hyprland\t1.4.1\t')" .cache/release-list.tsv` Expected: `1` (the package with an epoch is listed without it).

Then the guide's section 2: the "Nothing since" commands, taken from the `copr-build` run that built `tinkero` 4.0.4-3 (not simply the newest run), and the smoke record. Open the record and read it: it must name `tinkero` 4.0.4-3 and a pass. Its URL is `SMOKE` below.

- [ ] **Step 2: The dry run**

```bash
gh workflow run release --ref master -f smoke="$SMOKE" -f dry_run=true
run=$(gh run list --workflow release --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run"
gh run download "$run" -n release-dry-run -D .cache/release-dry-run
```

`gh run list` straight after `gh workflow run` can still show the run before, or none: wait until the new run is listed before taking its id (the same holds in Step 3).

Expected: the run is green and the step "Release" is skipped. In the log: `releasing v4.0.4-3 from <the commit>`; `verify`'s `PASS:` line; `fetched 36 packages into .cache/release/rpms`; `PASS: rpm tinkero-4.0.4-3.fc44.noarch.rpm ...` from `ci/check-rpm`, then the gates' `PASS:` lines as CI prints them; `install.sh: OK` and `tinkero-4.0.4-3.fc44-rpms.tar: OK`. This is the first real `dnf download` (36 files, among them `xdg-desktop-portal-hyprland-1.4.1-1.fc44.x86_64.rpm`, asked for without its epoch), the first real `createrepo_c` and the first `gh` call of the tool chain: none was measured at planning time. If the step "Dry run, the assets as a workflow artifact" fails because it found no file, the action has treated the path under `.cache` as hidden: the fix is `include-hidden-files: true` on that step, in a PR against the code issue's task, and the dry run is repeated.

In `.cache/release-dry-run`, the guide's section 3 checklist, with these values:

Run: `sha256sum -c SHA256SUMS` Expected: `install.sh: OK` and `tinkero-4.0.4-3.fc44-rpms.tar: OK`.
Run: `head -n1 RPMS.txt; wc -l < RPMS.txt` Expected: `Tinkero v4.0.4-3 for Fedora 44: 36 packages, 244 MiB` (the size of 2026-10-01, give or take the new `tinkero` build) and `37`.
Run: `diff <(git show origin/master:install.sh) install.sh` Expected: one changed line, `TINKERO_REF=${TINKERO_REF:-v4.0.4-3}`.
Run: `tar -tf tinkero-4.0.4-3.fc44-rpms.tar | grep -c '\.rpm$'; tar -tf tinkero-4.0.4-3.fc44-rpms.tar | grep -cv '^tinkero-4.0.4-3.fc44-rpms/'; tar -tf tinkero-4.0.4-3.fc44-rpms.tar | grep -c '/repodata/repomd.xml$'` Expected: `36`, `0`, `1`.
Read `NOTES.md`: the tag, the install line for `v4.0.4-3`, the smoke URL, the package list.

- [ ] **Step 3: The release**

```bash
gh workflow run release --ref master -f smoke="$SMOKE"
gh run watch "$(gh run list --workflow release --limit 1 --json databaseId --jq '.[0].databaseId')"
gh release view v4.0.4-3 --json tagName,targetCommitish,publishedAt,url,assets --jq '.tagName, .targetCommitish, .publishedAt, .url, (.assets[] | "\(.name) \(.size)")'
git ls-remote --tags origin v4.0.4-3
```

Expected: a green run; the release `v4.0.4-3`, titled `Tinkero v4.0.4-3`, on the commit that was dispatched (the `ls-remote` line and `targetCommitish` agree with `git rev-parse origin/master` as it was at the dispatch); four assets, `tinkero-4.0.4-3.fc44-rpms.tar`, `install.sh`, `SHA256SUMS`, `RPMS.txt`; the release page shows the notes.

Run: `curl -fsSL https://github.com/dromeropa/tinkero/releases/latest/download/install.sh | grep -c '^TINKERO_REF=\${TINKERO_REF:-v4.0.4-3}$'` Expected: `1` (the README's URL serves the pinned script).
Run: `gh workflow run release --ref master -f smoke="$SMOKE" -f dry_run=true`, then watch it. Expected: the run fails at the step "Refusals" with `release: v4.0.4-3 is already released`. That is the proof of the refusal; nothing else runs.

- [ ] **Step 4: The drill, on the one release that exists**

On a clean Fedora 44 Workstation VM (a clone of the 2F check's checkpoint, or plan 3D's base once it exists):

1. Install with the released script: `bash <(curl -fsSL https://github.com/dromeropa/tinkero/releases/latest/download/install.sh)`. Record `rpm -q tinkero hyprland quickshell`. Expected: `tinkero-4.0.4-3.fc44.noarch` and the lock's Hyprland and Quickshell.
2. Fetch and check the archive:

   ```bash
   cd "$HOME"
   curl -fLO https://github.com/dromeropa/tinkero/releases/download/v4.0.4-3/tinkero-4.0.4-3.fc44-rpms.tar
   curl -fLO https://github.com/dromeropa/tinkero/releases/download/v4.0.4-3/SHA256SUMS
   sha256sum -c --ignore-missing SHA256SUMS
   tar -xf tinkero-4.0.4-3.fc44-rpms.tar -C "$HOME"
   ```

   Expected: `tinkero-4.0.4-3.fc44-rpms.tar: OK`, and the directory `$HOME/tinkero-4.0.4-3.fc44-rpms`.
3. The tarball is a repository: `dnf -q repoquery --repofrompath=tinkero-rollback,"$HOME/tinkero-4.0.4-3.fc44-rpms" --repo=tinkero-rollback --queryformat '%{name}\n' | wc -l`. Expected: `36`.
4. A transaction from the archive alone, which is what proves `gpgcheck` for a `--repofrompath` repository (design 3.4): `sudo dnf copr disable dromero/tinkero`, then `sudo dnf reinstall --repofrompath=tinkero-rollback,"$HOME/tinkero-4.0.4-3.fc44-rpms" tinkero hyprland quickshell`, then `sudo dnf copr enable dromero/tinkero`. Record what dnf prints about the repository and the signatures, and the exact command that completed (as written, or with which extra option).
5. dnf's answer to the command `tinkero-status --rollback` prints, changing nothing: `sudo dnf downgrade --assumeno --repofrompath=tinkero-rollback,"$HOME/tinkero-4.0.4-3.fc44-rpms" tinkero hyprland quickshell`. Record the output verbatim. With one release the archive holds nothing older; what matters is how dnf 5 treats a package that has no older build (a skip, or an error for the whole command) and whether it offers the COPR's leftover `tinkero` 4.0.4-2 while that is still there: the printed text names three packages, and after most releases only one of them has an older build.
6. `tinkero-status --rollback; echo $?`. Expected: it says there is no release before `v4.0.4-3`, then `0` (design 2.5).

- [ ] **Step 5: The README's install line and the roadmap line**

Now that `v4.0.4-3` exists and Step 3 has shown that the release URL serves its `install.sh`, the README's install line becomes that URL (design 3.4). In a small PR that refers to this issue (`docs:` only, `Refs #N`, since the issue is closed by hand), two exact replacements in `README.md`, each quoted string being in the file exactly once on 2026-10-01:

**1.** The Install section's command (Phase 3 design, 3.4: "once the first release exists"). Replace

````text
    bash <(curl -fsSL https://raw.githubusercontent.com/dromeropa/tinkero/master/install.sh)
````

with

````text
    bash <(curl -fsSL https://github.com/dromeropa/tinkero/releases/latest/download/install.sh)
````

**2.** The Install section's last paragraph. Replace

````text
Until the first release is tagged, the URL above installs from `master`. Releases attach a pinned `install.sh`.
````

with

````text
That URL serves the `install.sh` of the newest [release](https://github.com/dromeropa/tinkero/releases), pinned to its tag and to the Fedora release it was built for. Each release also carries its RPM set as one tarball that is a dnf repository: `tinkero-status --rollback` prints how to go back to the release before the one installed, even after the COPR has pruned the older builds.
````

In the same PR, under the roadmap's "What executing 3B added to the queue", add one line with the date, the release's URL and the drill's verdict.

Run: `grep -c 'releases/latest/download/install.sh' README.md; grep -c 'raw.githubusercontent.com' README.md` Expected: `1` and `0`.

- [ ] **Step 6: Record, follow up, close**

Comment on the issue with: the tag and the commit it is on; the asset list with sizes (Step 3's output); the URLs of the dry run and of the release run; the dry run's values (Step 2); the drill's six results, with the reinstall command that completed and the downgrade's output verbatim. Then:

- file the issue "Rollback drill between two releases" (`size:medium`, `area:ci`, `blocked`): its body is the drill of `docs/guides/release.md`, section 6; it is blocked until a second release exists (the next `tinkero_rev`, or the first bump) and it is the only proof that dnf 5 downgrades the dependencies without `--allowerasing`;
- if Step 4 showed that the text `tinkero-status --rollback` prints must change (an option the `--repofrompath` command needs, or a three-package downgrade that fails when one of them has no older build), file an issue against `bin/tinkero-status` (`size:small`, `area:build`) with the command that worked.

Close this issue by hand.

**Verification for the issue:** the comment of Step 6 with every expected line present, the merged `docs:` PR, and the follow-up issue's number.

---

## Deviations

Filled by the PR that implements Tasks 1 to 4 (and by Task 5's issue for its own), per task, when anything deviated from this plan.

Built into the plan itself, for the operator to accept or veto at approval, are six deviations from the Phase 3 design and one addition to the brief. Each is kept as written unless the approval says otherwise:

- Task 1, `verify` checks more than design 3.2 lists: it also fails on a source the COPR serves that `build-order.txt` does not list, and when a list holds packages from two builds of one source it compares each build with the spec. Reason: the design's second check cannot be made for a source with no spec, and failing closed keeps a package the set dropped, or a subpackage left over from an older build, out of the archive. Cost: a dropped package must be deleted from the COPR before the next release, and plan 3C's weekly run is red until it is.
- Task 2, `build/tinkero-release notes OUT SMOKE_URL` is a seventh subcommand, not in design 3.2's table. Reason: the release's description and the check of the `smoke` input are more than a line of YAML, and design 3.3 keeps every decision in the tested tool.
- Task 2, `install-sh` also writes its line into `OUT/SHA256SUMS`. Reason: design 3.4 has the file cover the tarball and `install.sh`, while 3.2 has `pack` write it before `install.sh` exists.
- Task 3, the workflow refuses two things design 3.3 does not list: a tag that exists without a release, and a `smoke` input with the wrong prefix at the first step (the full pattern is checked again by `notes`). Reason: `gh release create --target` does not move an existing tag, so a hand-pushed tag would put the release on a commit nobody verified (D10); and a mistyped URL should not cost a 244 MiB download.
- Task 3, CI gains one line the design does not mention: the spec step runs `rpmspec -q --srpm` on every spec. Reason: it is the query `verify` depends on, and the PR is the only place it can be measured before the first release.
- Task 5, the rollback drill runs on the one release that exists: the archive path against that release (a repository query, a real `dnf reinstall` from it, `dnf downgrade --assumeno` recorded verbatim), with the downgrade between two releases filed as its own blocked issue. Reason: design 3.4's drill needs two releases to move between, and the first release should not wait for the second.
- Task 4, an addition nobody asked for: `CLAUDE.md` and the workflow guide's "Rules for agent sessions" say that `release` is dispatched only when an issue says so. Reason: the workflow creates a public tag that is never replaced (D10), plan 3C's checklist ends in "the release" and an agent session will read it, and the `copr-build` rule is the precedent.

The README's install line is not among them: it changes in Task 5, once the first release exists, as design 3.4 says.

## What this plan deliberately leaves out

- `tinkero-status --rollback` and its text (plan 3A); this plan fixes only the asset's name and layout, and Task 5 records the command that worked.
- The weekly run of `list` and `verify` (plan 3C), the bump checklist that ends in a release (plan 3C), the smoke test whose record the `smoke` input names (plan 3D).
- The real downgrade between two releases: its own issue, filed by Task 5, blocked until a second release exists.
- Source RPMs and debuginfo in the archive (design D11); loose RPMs as assets beside the tarball.
- A staging COPR, and any check that `master` has no payload change since the COPR build: `verify` compares versions, the guide's "Nothing since" step makes the operator look, and spec 4.12's rule stays a review point (roadmap, "Not built, by decision").
- Replacing, editing or deleting a release, and deleting a tag. The workflow refuses an existing tag; a mistake is fixed forward with the next `tinkero_rev`; removing a hand-pushed tag is the operator's act.
- A second Fedora release: one set per lock, one `install.sh` behind `releases/latest`. Part of the Fedora 45 issue.
- Signing the tarball or the checksums. The RPMs inside carry the COPR's signatures; `SHA256SUMS` guards the download, not the origin.
- `--refresh` or any cache option on the dnf calls: the workflow's container starts with no cache, and the guide says what to do on a developer's machine.
- Any change to `install.sh`, to `tests/test-install.sh` or to any existing test file.

## Planning review record (2026-10-01)

Prototyped in a sandboxed copy of the repository (read-only file system outside the copy, no network, `rm` a no-op), task by task, test first. Every code block of Tasks 1 to 4 is the prototype's file or the prototype's diff, expanded into this document by a script, not retyped.

Measured there:

- `tests/test-release.sh`: Task 1 `1..70` (64 `not ok` before the tool existed), Task 2 `1..150` (68 `not ok` against Task 1's tool), Task 3 `1..188` (29 `not ok` without `release.yml`); green after each task. `shellcheck -x -e SC1090,SC1091` and `bash -n` clean on `build/tinkero-release` and `tests/test-release.sh` after each task.
- The fixture: `rows` in the test expands to output byte-identical (`cmp`) to what `list`'s own query printed against the COPR on 2026-10-01 (75 rows); `list` reduces it to 36 lines from 26 sources.
- The whole chain by hand against the stubs: `list`, `verify`, `fetch`, `pack`, `install-sh`, `notes`; the tarball's members (one top-level directory, 36 RPMs, `repodata/`), `RPMS.txt`, a two-line `SHA256SUMS` that `sha256sum -c` accepts, a one-line diff of `install.sh`, `NOTES.md`. `install-sh` was also run against the prototype's own root: one changed line.
- The workflow's shell: each step's `run:` block extracted from the YAML and run under `bash --noprofile --norc -eo pipefail` with the stubs (refusals, list and verify, fetch, pack, release).
- Mutations of the tool and the workflow, each run against the test: the duplicate check, the upper bound of the Hyprland range, the stray-tag refusal, `--latest-limit=1`, the split from the right, the debug filter, the smoke pattern, the checksum merge, `bash -n`, the workflow's glob, the `.`/`..` segment check, `if-no-files-found`, the list check in `verify`, and the `LC_ALL=C` export each failed at least one case. "Exactly once" relaxed to "at least once" failed none at first, which showed that two `TINKERO_REF` lines were not tested; that case was added.
- The locale: under `en_AU.utf8`, bash's `[[ =~ ]]` with `[0-9]` matches U+0665 and under `C` it does not; gawk 5.3.2's and `grep -E`'s ranges and bash's glob ranges do not match it in either. Without the export, the tag and `smoke` cases fail under that locale and the list-row case still passes (awk is immune). With a `locale` that lists no UTF-8 locale and the caller in the POSIX locale, which is CI's situation, the whole file is green at `1..188` with no `setlocale` warning; there the locale cases prove the refusal only.
- The Docs task: every quoted string was in its file exactly once (`grep -cF`), and the replacements were applied to the prototype's copies by a script that asserts it; no em dash added. The quotes were also read against plan 3A's Docs task as drafted: each is still there once after 3A's edits.

Not measured at planning time, and why:

- `./dev check` and every pre-existing test file: the planning session ran under a no-delete rule and executed only the new test file. The plan changes no existing test.
- Real `dnf repoquery` and `dnf download` (the session was not allowed to run dnf): `list`'s row count through the tool, and that `dnf download` accepts a `name-version-release.arch` spec for a package with an epoch. The query itself was run by hand by the planning orchestrator (design, section 11). Task 1's Step 5 and Task 5 measure them.
- Real `rpmspec -q --srpm` on the 25 specs (not installed): the 25 expected lines of Task 3 are derived from the specs' `Version:` and `Release:` lines. CI on the code PR measures it.
- Real `createrepo_c`, the size of the real tarball, `gh`, `actions/upload-artifact` (whether a path under `.cache` counts as hidden) and the workflow on GitHub (not installed, not allowed, not on `master`): Task 5.
- The rollback itself (design 3.4): Task 5 for one release, the follow-up issue for two.

**Review.** An independent review of this plan against the design, the briefs and the prototype found 0 Critical, 2 Important and 10 Minor, all applied: (1) the README's install line moves from Task 4 to Task 5's `docs:` PR, as design 3.4 orders it, with no interim sentences; (2) the 4.11 quote stops before the clause plan 3A amends, every "What executing 3X added to the queue" section goes immediately above "What the first real assembly found", and Task 4 takes 3B out of 3A's "await approval" sentence; (3) "## Deviations" lists all six built-in deviations and the addition, with reasons; (4) the test takes the check-rpm glob from the YAML's own text; (5) the option-like row in `verify` is asserted on its message; (6) the artifact step has `if-no-files-found: error`, with the hidden-files fix named in Task 5; (7) `mkdir -p .cache` before the three redirections; (8) the em dash check runs on the staged diff, so it sees the new guide; (9) `notes` refuses `.` and `..` path segments, with tests; (10) the guide takes "Nothing since" from the run that built `tinkero` and says to wait for a new run to be listed; (11) the `install.sh` diff case uses the repository's own Fedora release, so it survives the Fedora 45 bump; (12) removing a hand-pushed tag is the operator's act in the message, the guide and Task 5. A finding from plan 3A's review that applies here was applied too: the tool sets `LC_ALL=C`, with locale cases in the test.
