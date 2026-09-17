# Phase 2A: Build Skeleton, Payload Assembly and CI Gates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: executed 2026-09-17.** The repository is now the source of truth: the code blocks below are what was dispatched, and they differ from the landed files where review found defects in this plan (see "Deviations" and "Review findings that changed the code" at the end). Do not re-execute this plan; read it for the design and the interfaces.

**Goal:** Turn the pinned upstream tarball into a verified Tinkero payload directory with one command, and guard that payload with gates that fail when an Arch assumption or a reference to a removed command gets through.

**Architecture:** Everything the RPM's `%install` does lives in one script, `build/assemble TARBALL DEST`, so it runs and is tested without `rpmbuild`; the spec file only calls it. Three gates inspect the assembled payload. Two of them compare their findings with a checked-in allowlist that may only shrink: today's findings are the work queue of plans 2B and 2C, and the gates stop anything new from joining it. Tests are hermetic (a generated fixture tree, no network); a separate `./dev gates` run exercises the real upstream tarball.

**Tech Stack:** bash, coreutils, `git apply` (patches), `curl`, `sha256sum`. No test framework, no `make`, no Python: a stock Fedora Workstation has none of `make`, `patch`, `bats`, `shellcheck` or `rpm-build`, and this plan must be runnable there. ShellCheck, rpmlint and `rpmspec` run in CI only (Task 7).

**Spec:** `docs/superpowers/specs/2026-09-17-tinkero-design.md` (sections 4.2, 4.3, 4.12, 8). Supporting data: `docs/research/arch-coupling-audit.md` (sections 4 to 6, 8, 12). Roadmap for the rest of Phase 2: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`.

## Global Constraints

- Upstream is pinned by `upstream.lock`: `omarchy_tag=v4.0.4`, `omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5`. A build without a matching `omarchy_sha256` must fail.
- `upstream.lock` is parsed, never sourced.
- The upstream tree is never committed to this repo. It lives in `.cache/` (git-ignored).
- Payload layout is upstream's own: commands are real files in `/usr/bin`; `/usr/share/omarchy/bin/` holds only symlinks to them. The Hyprland session puts `/usr/share/omarchy/bin` first on `PATH`, so there must be exactly one copy of each command.
- Nothing from upstream's `etc/` reaches the payload except `etc/fastfetch/config.jsonc` (relocated to `/usr/share/tinkero/fastfetch/`) and `etc/mise/conf.d/omarchy.toml`.
- No sudoers files, no setuid files, no system services in the payload.
- Patches apply with no fuzz. A `build/drop.list` line that matches nothing fails the build. A replacement script with no upstream namesake fails the build unless listed in `distro/fedora/replacements.new`. These three rules are how an upstream rename is noticed at a bump.
- Allowlists under `ci/allow/` may only shrink. Never add a line by hand; fix the finding, or discuss it.
- No em dashes in any file. Commit messages end with the attribution lines your harness specifies.
- Scripts start with `#!/bin/bash` and `set -euo pipefail` (test files use `set -u` via `tests/lib.sh`).

## File Structure

| File | Responsibility |
|---|---|
| `dev` | developer entry points: `check`, `lock`, `payload`, `gates`, `baseline`, `spec`, `clean` |
| `build/lib.sh` | `lock_get KEY [FILE]`, `die` |
| `build/fetch-upstream` | download the tarball for `omarchy_commit`, verify or record its sha256, print its path |
| `build/assemble` | tarball in, payload directory out: drop, patch, replace, relocate, lay out |
| `build/drop.list` | data: what is deleted from the tree |
| `build/render-spec` | `tinkero.spec.in` + `upstream.lock` to `tinkero.spec` |
| `patches/series`, `patches/*.patch` | the patch set, applied in series order |
| `distro/fedora/replacements/*` | Tinkero's own scripts under upstream names |
| `distro/fedora/replacements.new` | names allowed to have no upstream namesake (created when first needed) |
| `session/tinkero.desktop` | the GDM session entry |
| `ci/lib-gate.sh` | `compare_with_allowlist FOUND ALLOW WHAT` |
| `ci/gate-arch-leak`, `ci/gate-dropped-refs`, `ci/gate-single-copy` | the three gates |
| `ci/allow/*.allow` | generated baselines |
| `tinkero.spec.in`, `.copr/Makefile` | RPM spec template and COPR's `make_srpm` entry point |
| `tests/lib.sh`, `tests/run`, `tests/test-*.sh`, `tests/fixtures/make-tree.sh` | test harness, tests, fixture generator |
| `.github/workflows/ci.yml` | CI |

Interfaces other plans rely on: `build/assemble TARBALL DEST` (exit 0 and a populated DEST, or non-zero with `error: ...` on stderr); `lock_get`; `compare_with_allowlist`; the payload paths listed under Global Constraints; `./dev gates` exit status.

---

### Task 1: Test harness and the lock parser

**Files:**
- Create: `tests/lib.sh`, `tests/run`, `tests/test-lock.sh`, `build/lib.sh`, `dev`, `.gitignore`

**Interfaces:**
- Produces: `tests/lib.sh` helpers `ok`, `not_ok`, `assert_eq ACTUAL EXPECTED DESC`, `assert_file PATH [DESC]`, `assert_no_path PATH [DESC]`, `assert_symlink PATH TARGET [DESC]`, `assert_contains HAYSTACK NEEDLE DESC`, `assert_fails DESC CMD...`, `mktmp`, `finish`, and the variable `ROOT` (repo root). `build/lib.sh`: `lock_get KEY [FILE]` prints the value or returns 1; `die MSG...` prints `error: MSG` to stderr and exits 1. `./dev check` runs all tests.

- [ ] **Step 1: Write the harness**

Create `tests/lib.sh`:

```bash
# Minimal test helpers. Source from a test file; call `finish` last.
set -u
T_FAILS=0; T_COUNT=0
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ok()      { T_COUNT=$((T_COUNT+1)); echo "ok $T_COUNT - $1"; }
not_ok()  { T_COUNT=$((T_COUNT+1)); T_FAILS=$((T_FAILS+1)); echo "not ok $T_COUNT - $1"; [[ -n ${2:-} ]] && echo "#   $2"; return 0; }
assert_eq()      { [[ "$1" == "$2" ]] && ok "$3" || not_ok "$3" "expected '$2', got '$1'"; }
assert_file()    { [[ -f "$1" ]] && ok "${2:-file exists: $1}" || not_ok "${2:-file exists: $1}" "missing $1"; }
assert_no_path() { [[ ! -e "$1" && ! -L "$1" ]] && ok "${2:-path absent: $1}" || not_ok "${2:-path absent: $1}" "present $1"; }
assert_symlink() { [[ -L "$1" && "$(readlink "$1")" == "$2" ]] && ok "${3:-symlink $1}" || not_ok "${3:-symlink $1}" "want -> $2, got $(readlink "$1" 2>/dev/null || echo none)"; }
assert_contains(){ grep -qF -- "$2" <<<"$1" && ok "$3" || not_ok "$3" "output lacks '$2': $1"; }
# The description variable is deliberately odd: the command under test is often a shell
# function of the caller that reads the caller's own variables (a plain `local d` would shadow them).
assert_fails()   { local _t_desc=$1; shift; if "$@" >/dev/null 2>&1; then not_ok "$_t_desc" "command succeeded"; else ok "$_t_desc"; fi; }
mktmp()   { mktemp -d "${TMPDIR:-/tmp}/tinkero-test.XXXXXX"; }
finish()  { echo "1..$T_COUNT"; [[ $T_FAILS -eq 0 ]]; }
```

Create `tests/run` and make it executable (`chmod +x tests/run`):

```bash
#!/bin/bash
# Run every tests/test-*.sh; exit non-zero if any fails.
cd "$(dirname "$0")/.." || exit 2
rc=0
for t in tests/test-*.sh; do
  echo "# $t"
  bash "$t" || rc=1
done
exit $rc
```

- [ ] **Step 2: Write the failing test**

Create `tests/test-lock.sh`:

```bash
source "$(dirname "$0")/lib.sh"; source "$ROOT/build/lib.sh"
d=$(mktmp); printf '# c\nomarchy_tag=v1.2.3\nquickshell=0.3.0^20.gitabc\n' > "$d/l"
assert_eq "$(lock_get omarchy_tag "$d/l")" "v1.2.3" "reads a plain value"
assert_eq "$(lock_get quickshell "$d/l")" "0.3.0^20.gitabc" "keeps special characters verbatim"
assert_fails "missing key is an error" lock_get nope "$d/l"
printf 'x=$(touch %s/pwned)\n' "$d" >> "$d/l"; lock_get x "$d/l" >/dev/null
assert_no_path "$d/pwned" "lock values are never executed"
rm -rf "$d"; finish
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `bash tests/test-lock.sh`
Expected: fails with `build/lib.sh: No such file or directory`.

- [ ] **Step 4: Implement**

Create `build/lib.sh`:

```bash
# Shared helpers for build/ and ci/ scripts. Source, do not execute.

# lock_get KEY [FILE]: print the value of KEY from upstream.lock.
# The lock is parsed, never sourced, so nothing in it can execute.
lock_get() {
  local key=$1 file=${2:-${TINKERO_LOCK:-upstream.lock}} line
  if ! line=$(grep -E "^${key}=" "$file" | tail -n1) || [[ -z $line ]]; then
    echo "lock: no key '$key' in $file" >&2
    return 1
  fi
  printf '%s\n' "${line#*=}"
}

die() { echo "error: $*" >&2; exit 1; }
```

- [ ] **Step 5: Run the test**

Run: `bash tests/test-lock.sh`
Expected: four `ok` lines, `1..4`, exit status 0.

- [ ] **Step 6: Add the entry point and ignore file**

Create `dev` (`chmod +x dev`). It names scripts that later tasks create; only `./dev check` works after this task.

```bash
#!/bin/bash
# Developer entry points. Nothing here needs root, make or rpmbuild.
#   ./dev check      unit tests (hermetic, no network)
#   ./dev lock       first fetch: record omarchy_sha256 in upstream.lock
#   ./dev payload    fetch (verified) and assemble the real payload into .cache/payload
#   ./dev gates      assemble, then run the CI gates against the real payload
#   ./dev baseline   assemble, then rewrite the allowlists from the findings (review the diff!)
#   ./dev spec       render tinkero.spec from the template and the lock
#   ./dev clean
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
payload=.cache/payload; allow=ci/allow

assemble() {
  local tarball
  tarball=$(build/fetch-upstream)      # separate statement, so a failed fetch stops the script
  rm -rf "$payload"
  build/assemble "$tarball" "$payload"
}
gates() {
  local rc=0
  ci/gate-single-copy "$payload" || rc=1
  ci/gate-arch-leak "$payload" "$allow/arch-leak.allow" || rc=1
  ci/gate-dropped-refs "$payload" build/drop.list "$allow/dropped-refs.allow" || rc=1
  return $rc
}

case ${1:-} in
  check)    tests/run ;;
  lock)     build/fetch-upstream --record ;;
  payload)  assemble ;;
  gates)    assemble; gates ;;
  baseline) assemble; mkdir -p "$allow"; TINKERO_GATE_WRITE=1 gates ;;
  spec)     build/render-spec ;;
  clean)    rm -rf .cache tinkero.spec ;;
  *)        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
```

Create `.gitignore`:

```
.cache/
tinkero.spec
```

- [ ] **Step 7: Verify and commit**

Run: `./dev check` (expect exit 0) and `./dev` (expect the usage text, exit 2).

```bash
git add tests/lib.sh tests/run tests/test-lock.sh build/lib.sh dev .gitignore
git commit -m "build: test harness, lock parser, dev entry point"
```

---

### Task 2: Fixture tree and the verified fetch

**Files:**
- Create: `tests/fixtures/make-tree.sh`, `tests/test-fetch.sh`, `build/fetch-upstream`

**Interfaces:**
- Consumes: `lock_get`, `die`, the test helpers.
- Produces: `tests/fixtures/make-tree.sh OUTDIR` prints the path of a tarball with one top-level directory that mimics the upstream layout. `build/fetch-upstream [--record]` prints the cached tarball path. Environment overrides used by tests and CI: `TINKERO_LOCK`, `TINKERO_CACHE`, `TINKERO_UPSTREAM_URL`, `TINKERO_ROOT`.

- [ ] **Step 1: Write the fixture generator**

Create `tests/fixtures/make-tree.sh` (`chmod +x`). Every later test builds on this tree, so its contents are deliberate: a script to keep, one to patch, one to replace, two to drop (one by glob), one that calls a dropped command, an `etc/` with a sudoers file that must never ship.

```bash
#!/bin/bash
# make-tree.sh OUTDIR: build a tiny stand-in for the upstream tree and tar it
# the way GitHub does (one top-level directory). Prints the tarball path.
set -euo pipefail
out=$1; top=$out/omarchy-fixture
mkdir -p "$top"/{bin,shell/plugins/menu,migrations,etc/fastfetch,etc/mise/conf.d,etc/sudoers.d} \
         "$top"/default/{pacman,uwsm/env.d,systemd/user,fonts/omarchy,fontconfig/conf.avail,omarchy}
mk() { printf '#!/bin/bash\n%s\n' "$2" > "$top/bin/$1"; chmod 755 "$top/bin/$1"; }
mk omarchy-keep-me      'echo kept'
mk omarchy-version      'pacman -Q omarchy'
mk omarchy-update       'sudo pacman -Syu'
mk omarchy-snapshot     'snapper create'
mk omarchy-plymouth-set 'plymouth-set-default-theme'
mk omarchy-calls-dropped 'omarchy-snapshot create'
echo 4.0.0.alpha > "$top/version"
echo 'MIT' > "$top/LICENSE"
echo '[options]' > "$top/default/pacman/pacman.conf"
echo 'export OMARCHY_PATH=/usr/share/omarchy' > "$top/default/uwsm/env.d/10-omarchy"
printf '[Service]\nExecStart=/usr/bin/omarchy-keep-me\n' > "$top/default/systemd/user/omarchy-keep.service"
printf '[Service]\nExecStart=/usr/bin/omarchy-migrate-notify\n' > "$top/default/systemd/user/omarchy-migrate-notify.service"
echo font > "$top/default/fonts/omarchy/omarchy.ttf"
echo '<fontconfig/>' > "$top/default/fontconfig/conf.avail/50-omarchy.conf"
echo '{}' > "$top/default/omarchy/omarchy-menu.jsonc"
echo '{"text":"Omarchy"}' > "$top/etc/fastfetch/config.jsonc"
echo '[tool_alias]' > "$top/etc/mise/conf.d/omarchy.toml"
echo '%wheel ALL=(root) NOPASSWD: ALL' > "$top/etc/sudoers.d/omarchy-dns"
echo 'migration' > "$top/migrations/1.sh"
tar -C "$out" -czf "$out/fixture.tar.gz" omarchy-fixture
echo "$out/fixture.tar.gz"
```

- [ ] **Step 2: Write the failing test**

Create `tests/test-fetch.sh`:

```bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src")
c=0123456789abcdef0123456789abcdef01234567
printf 'omarchy_tag=v0\nomarchy_commit=%s\n' "$c" > "$d/lock"
f() { TINKERO_LOCK=$d/lock TINKERO_CACHE=$d/cache TINKERO_UPSTREAM_URL="file://$tb" "$ROOT/build/fetch-upstream" "$@"; }
assert_fails "refuses to build without a recorded checksum" f
out=$(f --record 2>/dev/null)
assert_eq "$out" "$d/cache/omarchy-$c.tar.gz" "--record fetches and prints the path"
assert_eq "$(grep -c '^omarchy_sha256=' "$d/lock")" "1" "--record writes the checksum once"
assert_eq "$(f)" "$d/cache/omarchy-$c.tar.gz" "verifies against the recorded checksum"
sed -i 's/^omarchy_sha256=.*/omarchy_sha256=deadbeef/' "$d/lock"
assert_fails "checksum mismatch fails" f
assert_no_path "$d/cache/omarchy-$c.tar.gz" "and removes the bad download"
printf 'omarchy_commit=v4.0.4\n' > "$d/lock"
assert_fails "a tag is not accepted as a commit id" f
rm -rf "$d"; finish
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `bash tests/test-fetch.sh`
Expected: `not ok` lines, because `build/fetch-upstream` does not exist (note that `assert_fails` cases pass for the wrong reason at this point; that is fine, the positive cases fail).

- [ ] **Step 4: Implement**

Create `build/fetch-upstream` (`chmod +x`):

```bash
#!/bin/bash
# fetch-upstream [--record]: download the upstream tarball for omarchy_commit
# into .cache/ and verify it against omarchy_sha256 in upstream.lock.
# --record writes the checksum into the lock when it has none (first fetch only).
# Prints the tarball path on success.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${TINKERO_ROOT:-$(dirname "$here")}
# shellcheck source=build/lib.sh
source "$here/lib.sh"
lock=${TINKERO_LOCK:-$root/upstream.lock}
record=0; [[ ${1:-} == --record ]] && record=1

commit=$(lock_get omarchy_commit "$lock")
[[ $commit =~ ^[0-9a-f]{40}$ ]] || die "omarchy_commit is not a full commit id: $commit"
url=${TINKERO_UPSTREAM_URL:-https://github.com/omacom/omarchy/archive/$commit.tar.gz}
out=${TINKERO_CACHE:-$root/.cache}/omarchy-$commit.tar.gz
mkdir -p "$(dirname "$out")"
[[ -f $out ]] || curl -fsSL --retry 3 -o "$out.part" "$url" && { [[ -f $out.part ]] && mv "$out.part" "$out"; true; }
[[ -f $out ]] || die "download failed: $url"

actual=$(sha256sum "$out" | cut -d' ' -f1)
if want=$(lock_get omarchy_sha256 "$lock" 2>/dev/null); then
  [[ $actual == "$want" ]] || { rm -f "$out"; die "checksum mismatch for $url: lock has $want, got $actual (cached file removed)"; }
elif (( record )); then
  sed -i "/^omarchy_commit=/a omarchy_sha256=$actual" "$lock"
  echo "recorded omarchy_sha256=$actual in $lock" >&2
else
  die "upstream.lock has no omarchy_sha256; run './dev lock' once and commit the result"
fi
echo "$out"
```

- [ ] **Step 5: Run the tests**

Run: `./dev check`
Expected: `test-fetch.sh` reports `1..7` with no `not ok`; exit 0.

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures/make-tree.sh tests/test-fetch.sh build/fetch-upstream
git commit -m "build: fixture tree and checksum-verified upstream fetch"
```

---

### Task 3: `build/assemble`

**Files:**
- Create: `build/assemble`, `session/tinkero.desktop`, `tests/test-assemble.sh`

**Interfaces:**
- Consumes: `die`, the fixture tarball, `build/drop.list`, `patches/series`, `distro/fedora/replacements/`, `distro/fedora/replacements.new`, `session/tinkero.desktop`, `upstream.lock`, all resolved under `TINKERO_ROOT` (default: the repo root).
- Produces: `build/assemble TARBALL DEST`. DEST must be empty or absent. On success DEST contains `usr/bin/omarchy-*` (real files), `usr/share/omarchy/` (the tree, `bin/` as symlinks), `usr/share/tinkero/{upstream.lock,fastfetch/config.jsonc}`, `usr/share/wayland-sessions/tinkero.desktop`, `usr/share/uwsm/env.d/10-omarchy`, `usr/share/fonts/omarchy/omarchy.ttf`, `usr/share/fontconfig/conf.avail/50-omarchy.conf`, `usr/lib/systemd/user/*`, `usr/share/licenses/tinkero/LICENSE.omarchy`, `etc/mise/conf.d/omarchy.toml`. Any `bin/tinkero-*` in the repo root is installed to `usr/bin` (none exist yet).

- [ ] **Step 1: Write the session file**

Create `session/tinkero.desktop`. It is upstream's `default/wayland-sessions/omarchy.desktop` with `Name` and `Comment` changed:

```ini
[Desktop Entry]
Name=Tinkero
Comment=Tinkero Hyprland session managed by uwsm
Exec=uwsm start -g -1 -e -D Hyprland hyprland.desktop
TryExec=uwsm
Type=Application
```

- [ ] **Step 2: Write the failing test**

Create `tests/test-assemble.sh`. The test builds a private repo root so that it controls the drop list, the patch and the replacement:

```bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src")
# a private repo root so the test controls drop.list, patches and replacements
r=$d/root; mkdir -p "$r"/{build,patches,distro/fedora/replacements,session,bin}
cp "$ROOT/session/tinkero.desktop" "$r/session/"
printf 'omarchy_tag=v0\n' > "$r/upstream.lock"
printf '# comment\nmigrations\ndefault/pacman\nbin/omarchy-snapshot\nbin/omarchy-plymouth-*\ndefault/systemd/user/omarchy-migrate-notify.service\n' > "$r/build/drop.list"
cat > "$r/patches/0001-version.patch" <<'P'
--- a/bin/omarchy-version
+++ b/bin/omarchy-version
@@ -1,2 +1,2 @@
 #!/bin/bash
-pacman -Q omarchy
+rpm -q tinkero
P
echo 0001-version.patch > "$r/patches/series"
printf '#!/bin/bash\necho "dnf upgrade"\n' > "$r/distro/fedora/replacements/omarchy-update"
run() { TINKERO_ROOT=$r "$ROOT/build/assemble" "$tb" "$1"; }

run "$d/dest" >/dev/null
o=$d/dest/usr/share/omarchy
assert_file "$d/dest/usr/bin/omarchy-keep-me" "commands land in /usr/bin"
assert_symlink "$o/bin/omarchy-keep-me" /usr/bin/omarchy-keep-me "tree bin/ holds symlinks"
assert_no_path "$d/dest/usr/bin/omarchy-snapshot" "dropped script is gone"
assert_no_path "$o/bin/omarchy-plymouth-set" "dropped glob is gone"
assert_no_path "$o/migrations" "dropped directory is gone"
assert_no_path "$o/etc" "upstream etc/ is not shipped"
assert_no_path "$d/dest/etc/sudoers.d" "no sudoers reach the payload"
assert_file "$d/dest/usr/share/tinkero/fastfetch/config.jsonc" "fastfetch config is relocated"
assert_file "$d/dest/etc/mise/conf.d/omarchy.toml" "mise alias is kept"
assert_eq "$(tail -n1 "$d/dest/usr/bin/omarchy-version")" "rpm -q tinkero" "patch applied"
assert_eq "$(tail -n1 "$d/dest/usr/bin/omarchy-update")" 'echo "dnf upgrade"' "replacement installed"
assert_file "$d/dest/usr/share/wayland-sessions/tinkero.desktop" "session file installed"
assert_file "$d/dest/usr/lib/systemd/user/omarchy-keep.service" "user units installed"
assert_no_path "$d/dest/usr/lib/systemd/user/omarchy-migrate-notify.service" "dropped unit not installed"
assert_file "$d/dest/usr/share/licenses/tinkero/LICENSE.omarchy" "upstream license shipped"
assert_file "$d/dest/usr/share/tinkero/upstream.lock" "lock shipped"

echo 'bin/omarchy-renamed-upstream' >> "$r/build/drop.list"
assert_fails "a drop line matching nothing fails the build" run "$d/dest2"
sed -i '$d' "$r/build/drop.list"
printf '#!/bin/bash\n' > "$r/distro/fedora/replacements/omarchy-brand-new"
assert_fails "a replacement with no upstream namesake fails" run "$d/dest3"
echo omarchy-brand-new > "$r/distro/fedora/replacements.new"
run "$d/dest4" >/dev/null; assert_file "$d/dest4/usr/bin/omarchy-brand-new" "unless declared in replacements.new"
sed -i 's/pacman -Q omarchy/pacman -Q something-else/' "$r/patches/0001-version.patch"
assert_fails "a patch that no longer applies fails the build" run "$d/dest5"
rm -rf "$d"; finish
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `bash tests/test-assemble.sh`
Expected: `not ok` on the positive assertions; `build/assemble: No such file or directory`.

- [ ] **Step 4: Implement**

Create `build/assemble` (`chmod +x`):

```bash
#!/bin/bash
# assemble TARBALL DEST: turn the upstream tarball into the tinkero payload
# under DEST (a DESTDIR-style root). This is the whole of the RPM's %install,
# kept outside the spec so it can be run and tested without rpmbuild.
#
# Inputs, relative to the repo root (override the root with TINKERO_ROOT):
#   build/drop.list                      paths to delete from the tree
#   patches/series + patches/*.patch     applied with git apply -p1 (strict, no fuzz)
#   distro/fedora/replacements/*         copied over bin/<same name>
#   distro/fedora/replacements.new       names allowed to have no upstream file
#   session/tinkero.desktop              the GDM session entry
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${TINKERO_ROOT:-$(dirname "$here")}
# shellcheck source=build/lib.sh
source "$here/lib.sh"

[[ $# -eq 2 ]] || die "usage: assemble TARBALL DEST"
tarball=$1; dest=$2
[[ -f $tarball ]] || die "no such tarball: $tarball"
[[ ! -e $dest || -z $(ls -A "$dest" 2>/dev/null) ]] || die "DEST must be empty: $dest"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
tree=$work/tree; mkdir -p "$tree"
tar -xzf "$tarball" -C "$tree" --strip-components=1
[[ -d $tree/bin && -f $tree/version ]] || die "tarball does not look like the Omarchy tree"

# 1. Drop. Every line must match something, so an upstream rename is noticed.
while IFS= read -r line; do
  [[ -z $line || $line == \#* ]] && continue
  matches=()
  # shellcheck disable=SC2231  # unquoted on purpose: $line may be a glob
  for m in "$tree"/$line; do
    [[ -e $m || -L $m ]] && matches+=( "$m" )
  done
  (( ${#matches[@]} )) || die "drop.list: '$line' matches nothing in the tree"
  rm -rf -- "${matches[@]}"
done < "$root/build/drop.list"

# 2. Patch. No fuzz: a patch that no longer applies cleanly must be looked at.
if [[ -f $root/patches/series ]]; then
  while IFS= read -r p; do
    [[ -z $p || $p == \#* ]] && continue
    # git apply has no fuzz and needs no repository; it is strict about context.
    ( cd "$tree" && git apply -p1 "$root/patches/$p" ) || die "patch failed: $p"
  done < "$root/patches/series"
fi

# 3. Replace. A replacement must shadow an upstream file unless declared new.
repl=$root/distro/fedora/replacements
if [[ -d $repl ]]; then
  for f in "$repl"/*; do
    [[ -f $f ]] || continue
    name=$(basename "$f")
    if [[ ! -f $tree/bin/$name ]] && ! grep -qxF "$name" "$root/distro/fedora/replacements.new" 2>/dev/null; then
      die "replacement '$name' has no upstream file (renamed upstream? else add it to replacements.new)"
    fi
    install -m 0755 "$f" "$tree/bin/$name"
  done
fi

# 4. Relocate the two etc/ files Tinkero keeps, then drop the rest of etc/.
install -Dm 0644 "$tree/etc/fastfetch/config.jsonc" "$dest/usr/share/tinkero/fastfetch/config.jsonc"
install -Dm 0644 "$tree/etc/mise/conf.d/omarchy.toml" "$dest/etc/mise/conf.d/omarchy.toml"
rm -rf "$tree/etc"

# 5. System files that live outside the tree.
install -Dm 0644 "$tree/default/uwsm/env.d/10-omarchy" "$dest/usr/share/uwsm/env.d/10-omarchy"
install -Dm 0644 "$root/session/tinkero.desktop" "$dest/usr/share/wayland-sessions/tinkero.desktop"
install -Dm 0644 "$tree/default/fonts/omarchy/omarchy.ttf" "$dest/usr/share/fonts/omarchy/omarchy.ttf"
install -Dm 0644 "$tree/default/fontconfig/conf.avail/50-omarchy.conf" "$dest/usr/share/fontconfig/conf.avail/50-omarchy.conf"
mkdir -p "$dest/usr/lib/systemd/user"
cp -a "$tree/default/systemd/user/." "$dest/usr/lib/systemd/user/"
install -Dm 0644 "$tree/LICENSE" "$dest/usr/share/licenses/tinkero/LICENSE.omarchy"
install -Dm 0644 "${TINKERO_LOCK:-$root/upstream.lock}" "$dest/usr/share/tinkero/upstream.lock"

# 6. The tree, with upstream's own layout: commands in /usr/bin, symlinks in the tree.
mkdir -p "$dest/usr/bin" "$dest/usr/share/omarchy"
cp -a "$tree/." "$dest/usr/share/omarchy/"
for f in "$dest/usr/share/omarchy/bin"/*; do
  name=$(basename "$f")
  mv "$f" "$dest/usr/bin/$name"
  ln -s "/usr/bin/$name" "$f"
done
for f in "$root"/bin/tinkero-*; do
  [[ -f $f ]] && install -m 0755 "$f" "$dest/usr/bin/$(basename "$f")"
done
echo "assembled $(ls "$dest/usr/bin" | wc -l) commands into $dest"
```

- [ ] **Step 5: Run the tests**

Run: `./dev check`
Expected: `test-assemble.sh` reports `1..20` with no `not ok`.

- [ ] **Step 6: Commit**

```bash
git add build/assemble session/tinkero.desktop tests/test-assemble.sh
git commit -m "build: assemble the payload from the upstream tarball"
```

---

### Task 4: The gates

**Files:**
- Create: `ci/lib-gate.sh`, `ci/gate-arch-leak`, `ci/gate-dropped-refs`, `ci/gate-single-copy`, `tests/test-gates.sh`

**Interfaces:**
- Produces: `compare_with_allowlist FOUND_FILE ALLOW_FILE WHAT` (returns 1 on a finding that is not allowed **or** an allowed entry that was not found; with `TINKERO_GATE_WRITE=1` rewrites ALLOW_FILE instead). `ci/gate-arch-leak DEST ALLOW` (findings: paths relative to DEST). `ci/gate-dropped-refs DEST DROPLIST ALLOW` (findings: `path:command`). `ci/gate-single-copy DEST`. Allowlist lines may carry a trailing `# comment`.

Why `gate-dropped-refs` and not a general "every `omarchy-*` word resolves to a file" check: on the pristine upstream tree that general check reports 110 false positives (PAM service names, CSS ids, window classes, unit names). Asking the narrower question, "does anything still name a command we deleted", has no false positives and is the question that matters.

- [ ] **Step 1: Write the failing test**

Create `tests/test-gates.sh`:

```bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); p=$d/dest
mkdir -p "$p/usr/bin" "$p/usr/share/omarchy/bin" "$p/usr/share/omarchy/default"
printf '#!/bin/bash\nsudo pacman -Syu\n' > "$p/usr/bin/omarchy-leaky"
printf '#!/bin/bash\necho fine\n'        > "$p/usr/bin/omarchy-clean"
printf '#!/bin/bash\nomarchy-snapshot create\nomarchy-snapshot-helper\n' > "$p/usr/bin/omarchy-caller"
printf '{"action":"omarchy-plymouth-set x"}\n' > "$p/usr/share/omarchy/default/menu.jsonc"
for n in omarchy-leaky omarchy-clean omarchy-caller; do ln -s "/usr/bin/$n" "$p/usr/share/omarchy/bin/$n"; done
printf 'bin/omarchy-snapshot\nbin/omarchy-plymouth-*\nmigrations\n' > "$d/drop.list"

# arch-leak
: > "$d/allow"
out=$("$ROOT/ci/gate-arch-leak" "$p" "$d/allow" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "arch-leak fails on an unlisted file"
assert_contains "$out" "usr/bin/omarchy-leaky" "arch-leak names the file"
printf 'usr/bin/omarchy-leaky   # replaced in plan 2B\n' > "$d/allow"
"$ROOT/ci/gate-arch-leak" "$p" "$d/allow" >/dev/null 2>&1; assert_eq "$?" "0" "arch-leak passes when allowlisted (trailing comment ok)"
echo 'usr/bin/omarchy-gone' >> "$d/allow"
out=$("$ROOT/ci/gate-arch-leak" "$p" "$d/allow" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "arch-leak fails on a stale allowlist entry"
assert_contains "$out" "stale" "and says so"

# dropped-refs
: > "$d/allow2"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop.list" "$d/allow2" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs fails on a call to a dropped command"
assert_contains "$out" "usr/bin/omarchy-caller:omarchy-snapshot" "reports path:command"
assert_contains "$out" "usr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set" "expands drop-list globs"
[[ $out != *omarchy-snapshot-helper* ]] && ok "does not match a longer command name" || not_ok "does not match a longer command name" "$out"
printf 'usr/bin/omarchy-caller:omarchy-snapshot\nusr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set\n' > "$d/allow2"
"$ROOT/ci/gate-dropped-refs" "$p" "$d/drop.list" "$d/allow2" >/dev/null 2>&1; assert_eq "$?" "0" "dropped-refs passes when allowlisted"

# single-copy
"$ROOT/ci/gate-single-copy" "$p" >/dev/null 2>&1; assert_eq "$?" "0" "single-copy passes on a correct layout"
rm "$p/usr/share/omarchy/bin/omarchy-clean"; cp "$p/usr/bin/omarchy-clean" "$p/usr/share/omarchy/bin/omarchy-clean"
"$ROOT/ci/gate-single-copy" "$p" >/dev/null 2>&1; assert_eq "$?" "1" "single-copy fails on a regular file in the tree bin/"
rm -rf "$d"; finish
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-gates.sh`
Expected: `not ok` lines; `ci/gate-arch-leak: No such file or directory`.

- [ ] **Step 3: Implement the shared comparison**

Create `ci/lib-gate.sh`:

```bash
# compare_with_allowlist FOUND_FILE ALLOW_FILE WHAT
# FOUND_FILE: sorted unique findings, one per line. ALLOW_FILE: allowed findings,
# '#' comments and blank lines ignored. Fails on findings that are not allowed
# AND on allowed entries that were not found, so the allowlist can only shrink.
# With TINKERO_GATE_WRITE=1 it rewrites ALLOW_FILE from the findings instead.
compare_with_allowlist() {
  local found=$1 allow=$2 what=$3 rc=0 tmp
  if [[ ${TINKERO_GATE_WRITE:-0} == 1 ]]; then
    { echo "# Baseline written by './dev baseline'. Entries may only be removed, never added by hand."
      echo "# Each one is work owed by a later plan; see docs/superpowers/plans/."
      cat "$found"; } > "$allow"
    echo "WROTE: $allow ($(wc -l < "$found") entries)"; return 0
  fi
  tmp=$(mktemp)
  grep -vE '^\s*(#|$)' "$allow" 2>/dev/null | sed 's/[[:space:]]*#.*$//' | sort -u > "$tmp" || true
  local extra stale
  extra=$(comm -23 "$found" "$tmp"); stale=$(comm -13 "$found" "$tmp")
  if [[ -n $extra ]]; then
    echo "FAIL: $what not on the allowlist ($allow):"; sed 's/^/  /' <<<"$extra"; rc=1
  fi
  if [[ -n $stale ]]; then
    echo "FAIL: stale allowlist entries (no longer found; delete them from $allow):"; sed 's/^/  /' <<<"$stale"; rc=1
  fi
  rm -f "$tmp"
  [[ $rc -eq 0 ]] && echo "PASS: $what ($(wc -l < "$found") allowed finding(s))"
  return $rc
}
```

- [ ] **Step 4: Implement the three gates**

Create `ci/gate-arch-leak` (`chmod +x`). The pattern is tier 1 of the audit, section 1:

```bash
#!/bin/bash
# gate-arch-leak DEST ALLOW: no file in the payload may name an Arch tool
# unless it is on the allowlist. Findings are paths relative to DEST.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); # shellcheck source=ci/lib-gate.sh
source "$here/lib-gate.sh"
[[ $# -eq 2 ]] || { echo "usage: gate-arch-leak DEST ALLOW" >&2; exit 2; }
dest=$1; allow=$2
pattern='pacman|\byay\b|\bparu\b|expac|makepkg|limine|mkinitcpio|snapper|\bufw\b|pkgs\.omarchy\.org|archlinux|checkupdates|paccache|pactree'
found=$(mktemp); trap 'rm -f "$found"' EXIT
( cd "$dest" && grep -rIlE "$pattern" . 2>/dev/null | sed 's|^\./||' | sort -u ) > "$found" || true
compare_with_allowlist "$found" "$allow" "files naming Arch tooling"
```

Create `ci/gate-dropped-refs` (`chmod +x`). The boundary `[^a-z0-9-]` on both sides is what keeps `omarchy-update` from matching inside `omarchy-update-available`:

```bash
#!/bin/bash
# gate-dropped-refs DEST DROPLIST ALLOW: nothing in the payload may still call a
# command that build/drop.list removed. Findings are "path:command".
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); # shellcheck source=ci/lib-gate.sh
source "$here/lib-gate.sh"
[[ $# -eq 3 ]] || { echo "usage: gate-dropped-refs DEST DROPLIST ALLOW" >&2; exit 2; }
dest=$1; droplist=$2; allow=$3
found=$(mktemp); trap 'rm -f "$found"' EXIT
# Dropped command names = bin/ lines of the drop list that no longer exist in the payload.
# Globs are expanded against what is NOT there by listing names from the line itself when
# it has no glob, and by skipping glob lines (their members are caught by name below).
names=$(grep -E '^bin/' "$droplist" | grep -v '[*?[]' | sed 's|^bin/||' | sort -u)
globs=$(grep -E '^bin/' "$droplist" | grep '[*?[]' | sed 's|^bin/||' || true)
: > "$found"
if [[ -n $names ]]; then
  alt=$(paste -sd'|' <<<"$names")
  ( cd "$dest" && grep -rIoHE "(^|[^a-z0-9-])($alt)([^a-z0-9-]|\$)" . 2>/dev/null \
      | sed -E 's|^\./||; s/^([^:]+):[^a-z]*([a-z0-9-]+).*$/\1:\2/' ) >> "$found" || true
fi
while IFS= read -r g; do
  [[ -z $g ]] && continue
  re=${g//\*/[a-z0-9-]*}
  ( cd "$dest" && grep -rIoHE "(^|[^a-z0-9-])($re)([^a-z0-9-]|\$)" . 2>/dev/null \
      | sed -E 's|^\./||; s/^([^:]+):[^a-z]*([a-z0-9-]+).*$/\1:\2/' ) >> "$found" || true
done <<<"$globs"
sort -u -o "$found" "$found"
compare_with_allowlist "$found" "$allow" "references to dropped commands"
```

Create `ci/gate-single-copy` (`chmod +x`):

```bash
#!/bin/bash
# gate-single-copy DEST: /usr/share/omarchy/bin must contain only symlinks into
# /usr/bin, each resolving to a file in the payload.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: gate-single-copy DEST" >&2; exit 2; }
dest=$1; rc=0
for f in "$dest/usr/share/omarchy/bin"/*; do
  name=$(basename "$f")
  if [[ ! -L $f ]]; then echo "FAIL: not a symlink: usr/share/omarchy/bin/$name"; rc=1; continue; fi
  if [[ $(readlink "$f") != "/usr/bin/$name" ]]; then echo "FAIL: wrong target for $name: $(readlink "$f")"; rc=1; fi
  if [[ ! -f $dest/usr/bin/$name ]]; then echo "FAIL: symlink target missing from payload: usr/bin/$name"; rc=1; fi
done
[[ $rc -eq 0 ]] && echo "PASS: single copy of every command"
exit $rc
```

- [ ] **Step 5: Run the tests**

Run: `./dev check`
Expected: `test-gates.sh` reports `1..12` with no `not ok`.

- [ ] **Step 6: Commit**

```bash
git add ci/lib-gate.sh ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy tests/test-gates.sh
git commit -m "ci: arch-leak, dropped-reference and single-copy gates"
```

---

### Task 5: Spec template, renderer and the COPR entry point

**Files:**
- Create: `tinkero.spec.in`, `build/render-spec`, `tests/test-render-spec.sh`, `.copr/Makefile`
- Modify: `upstream.lock` (nothing to change by hand; it must already contain `tinkero_rev` and the full `quickshell` version, which it does)

**Interfaces:**
- Consumes: `lock_get`, `die`.
- Produces: `build/render-spec [OUT]` writes the spec (default `tinkero.spec`, git-ignored) and prints its path. Placeholders: `@VERSION@ @RELEASE@ @TAG@ @COMMIT@ @HYPRLAND@ @HYPRLAND_NEXT@ @QUICKSHELL@ @DATE@`. `TINKERO_BUILD_DATE` overrides the changelog date for reproducible tests.

- [ ] **Step 1: Write the failing test**

Create `tests/test-render-spec.sh`:

```bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp)
cat > "$d/lock" <<'L'
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
tinkero_rev=3
L
r() { TINKERO_LOCK=$d/lock TINKERO_BUILD_DATE='Thu Sep 17 2026' "$ROOT/build/render-spec" "$d/out.spec"; }
r >/dev/null; s=$(cat "$d/out.spec")
assert_contains "$s" "Version:        4.0.4" "version is the tag without v"
assert_contains "$s" "Release:        3%{?dist}" "release is tinkero_rev"
assert_contains "$s" "Requires:       (hyprland >= 0.56.2 with hyprland < 0.57)" "hyprland range is derived from the lock"
assert_contains "$s" "Requires:       quickshell = 0.3.0^20.git28771c7" "quickshell pin is verbatim"
assert_contains "$s" "Source0:        omarchy-c668141e9c42b13c80c9ca4ea108e11708c5e8a5.tar.gz" "source names the commit"
assert_eq "$(grep -c '@[A-Z_]*@' "$d/out.spec")" "0" "no placeholder left"
sed -i 's/^hyprland=.*/hyprland=0.56/' "$d/lock"
assert_fails "a malformed hyprland version is rejected" r
rm -rf "$d"; finish
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/test-render-spec.sh`
Expected: `not ok` lines; `build/render-spec: No such file or directory`.

- [ ] **Step 3: Write the template**

Create `tinkero.spec.in`. The `Requires:` list is the hard-requirements table of the design spec, section 6; `herdr` and `mise` come from the Tinkero COPR, which does not exist until Phase 1, so this spec renders and parses now but only builds installable RPMs later. `%install` is one line on purpose.

```spec
# Generated from tinkero.spec.in by build/render-spec. Do not edit tinkero.spec.
Name:           tinkero
Version:        @VERSION@
Release:        @RELEASE@%{?dist}
Summary:        A tinkerable desktop for Hyprland, built on the Omarchy tree
License:        MIT
URL:            https://github.com/dromeropa/tinkero
Source0:        omarchy-@COMMIT@.tar.gz
Source1:        tinkero-src.tar.gz
BuildArch:      noarch
BuildRequires:  git-core

# The pin (design spec 4.2): tree and compositor move in one transaction.
Requires:       (hyprland >= @HYPRLAND@ with hyprland < @HYPRLAND_NEXT@)
Requires:       quickshell = @QUICKSHELL@
Conflicts:      omedora
Conflicts:      omedora-settings

# Hard requirements (design spec 6). Weak ones are added with the features that use them.
Requires:       uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprland-guiutils hyprsunset hyprpicker lua
Requires:       qt6-qtwayland qt6-qtmultimedia qt6-qtimageformats qt6-qtsvg gtk4-layer-shell
Requires:       fontawesome-fonts-all yaru-icon-theme
Requires:       polkit gnome-keyring pipewire wireplumber pipewire-pulseaudio pamixer brightnessctl
Requires:       power-profiles-daemon bluez NetworkManager udiskie socat inotify-tools jq gum git-core
Requires:       foot xdg-terminal-exec tmux herdr mise
Requires:       grim slurp wl-clipboard wtype tensaku hyprland-preview-share-picker ttfx

%description
Tinkero is the desktop around the Hyprland compositor: the Quickshell shell,
session wiring, keybindings, themes, tooling and agent harness of Omarchy
(upstream tag @TAG@), with the Arch substrate replaced by Fedora's.
Built on Omarchy, https://github.com/omacom/omarchy, MIT licensed.

%prep
%setup -q -c -T -a 1

%build

%install
TINKERO_ROOT=$PWD TINKERO_LOCK=$PWD/upstream.lock build/assemble %{SOURCE0} %{buildroot}

%files
%license %{_datadir}/licenses/tinkero/LICENSE.omarchy
%{_bindir}/omarchy*
%{_datadir}/omarchy
%{_datadir}/tinkero
%{_datadir}/uwsm/env.d/10-omarchy
%{_datadir}/wayland-sessions/tinkero.desktop
%{_datadir}/fonts/omarchy
%{_datadir}/fontconfig/conf.avail/50-omarchy.conf
%{_prefix}/lib/systemd/user/*
%config(noreplace) %{_sysconfdir}/mise/conf.d/omarchy.toml

%changelog
* @DATE@ Tinkero <noreply@tinkero.invalid> - @VERSION@-@RELEASE@
- Built from upstream.lock: @TAG@ (@COMMIT@)
```

- [ ] **Step 4: Implement the renderer**

Create `build/render-spec` (`chmod +x`):

```bash
#!/bin/bash
# render-spec [OUT]: fill tinkero.spec.in from upstream.lock. Default OUT: tinkero.spec
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${TINKERO_ROOT:-$(dirname "$here")}
# shellcheck source=build/lib.sh
source "$here/lib.sh"
lock=${TINKERO_LOCK:-$root/upstream.lock}
out=${1:-$root/tinkero.spec}

tag=$(lock_get omarchy_tag "$lock");        commit=$(lock_get omarchy_commit "$lock")
hypr=$(lock_get hyprland "$lock");          qs=$(lock_get quickshell "$lock")
rev=$(lock_get tinkero_rev "$lock")
[[ $tag =~ ^v[0-9]+(\.[0-9]+)+$ ]]   || die "omarchy_tag must look like v4.0.4: $tag"
[[ $hypr =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || die "hyprland must be MAJOR.MINOR.PATCH: $hypr"
next="${BASH_REMATCH[1]}.$(( BASH_REMATCH[2] + 1 ))"
[[ $rev =~ ^[0-9]+$ ]] || die "tinkero_rev must be an integer: $rev"
date=${TINKERO_BUILD_DATE:-$(LC_ALL=C date -u '+%a %b %d %Y')}

sed -e "s|@VERSION@|${tag#v}|g" -e "s|@RELEASE@|$rev|g" -e "s|@TAG@|$tag|g" \
    -e "s|@COMMIT@|$commit|g" -e "s|@HYPRLAND@|$hypr|g" -e "s|@HYPRLAND_NEXT@|$next|g" \
    -e "s|@QUICKSHELL@|$qs|g" -e "s|@DATE@|$date|g" "$root/tinkero.spec.in" > "$out"
if grep -n '@[A-Z_]*@' "$out"; then die "unfilled placeholder in $out"; fi
echo "$out"
```

- [ ] **Step 5: Run the tests**

Run: `./dev check`
Expected: `test-render-spec.sh` reports `1..7` with no `not ok`. Then `./dev spec && grep -n '^Requires:       (hyprland' tinkero.spec` prints `Requires:       (hyprland >= 0.56.2 with hyprland < 0.57)`.

- [ ] **Step 6: Add COPR's entry point**

Create `.copr/Makefile`. COPR's `make_srpm` method runs it as root in a fresh chroot with network access. It cannot be exercised on a stock workstation (no `make`, no `rpm-build`); Task 7 runs it in CI. Recipe lines must start with a TAB.

```make
# COPR "make_srpm" entry point. COPR runs, as root in a fresh chroot with network:
#   make -f <clone>/.copr/Makefile srpm outdir=<dir> spec=<path>
TOP := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..

.PHONY: srpm
srpm:
	dnf -y install git-core curl rpm-build
	cd $(TOP) && \
	  build/fetch-upstream >/dev/null && \
	  build/render-spec tinkero.spec && \
	  git archive --format=tar.gz -o .cache/tinkero-src.tar.gz HEAD
	cd $(TOP) && rpmbuild -bs tinkero.spec \
	  --define "_sourcedir $(abspath $(TOP))/.cache" \
	  --define "_srcrpmdir $(outdir)"
```

- [ ] **Step 7: Commit**

```bash
git add tinkero.spec.in build/render-spec tests/test-render-spec.sh .copr/Makefile
git commit -m "build: spec template rendered from upstream.lock, COPR make_srpm entry"
```

---

### Task 6: Real data: the drop list, the first patch, the first replacement, the baselines

This task needs the network once (about 125 MB). Everything before it was hermetic.

**Files:**
- Create: `build/drop.list`, `patches/series`, `patches/0001-omarchy-version-from-rpm.patch`, `distro/fedora/replacements/omarchy-update`, `ci/allow/arch-leak.allow`, `ci/allow/dropped-refs.allow`
- Modify: `upstream.lock` (gains `omarchy_sha256=`, written by `./dev lock`)

**Interfaces:**
- Produces: a green `./dev gates` on the real tree, and the two baselines that plans 2B and 2C shrink to their permanent minimum.

- [ ] **Step 1: Write the drop list**

Create `build/drop.list`. The verdicts are the audit's (sections 4 to 6); the last block was found by running the dropped-reference gate on the real tree while this plan was being written.

```
# build/drop.list: paths removed from the upstream tree before anything else.
# One path or glob per line, relative to the tree root. Every line must match
# something at the pinned tag, or the build fails (that is how a rename is noticed).
# Verdicts come from docs/research/arch-coupling-audit.md.

# --- not part of a desktop payload
.github
.gitignore
.editorconfig
.luarc.json
AGENTS.md
CLAUDE.md
README.md
agents
docs
manual
test

# --- Arch machinery (audit sections 4.2, 5)
migrations
default/pacman
default/limine
default/libalpm
default/snapper
default/plymouth
default/sddm
default/wayland-sessions
default/systemd/user/omarchy-migrate-notify.service
config/omarchy/hooks/pre-refresh-pacman.d

# --- upstream installer and first-run chain (audit section 6); tinkero-provision replaces it
install/config
install/hardware
install/helpers
install/login
install/post-install
install/provisioning
install/omarchy-base.packages
install/omarchy-other.packages
install/user/all.sh
install/user/chromium.sh
install/user/default-keyring.sh
install/user/first-run/enable-user-units.sh
install/user/first-run/gnome-theme.sh
install/user/first-run/gtk-primary-paste.sh
install/user/first-run/install-voxtype.hook
install/user/first-run/setup-agent.hook
install/user/first-run/setup-fingerprint.hook
install/user/first-run/welcome.sh
install/user/first-run/wifi.sh

# --- commands (audit section 4)
bin/omarchy-dev-link
bin/omarchy-dev-pkg-test
bin/omarchy-dev-status
bin/omarchy-dev-unlink
bin/omarchy-hibernation-remove
bin/omarchy-hibernation-setup
bin/omarchy-install-docker-dbs
bin/omarchy-install-gaming-battlenet
bin/omarchy-install-gaming-geforce-now
bin/omarchy-install-gaming-gpu-lib32
bin/omarchy-install-gaming-heroic
bin/omarchy-install-gaming-lutris
bin/omarchy-install-gaming-retroarch
bin/omarchy-install-gaming-steam
bin/omarchy-install-gaming-xbox-cloud
bin/omarchy-install-gaming-xbox-controllers
bin/omarchy-install-openclaw-cli
bin/omarchy-install-preinstalls
bin/omarchy-install-service-sunshine
bin/omarchy-migrate
bin/omarchy-migrate-notify
bin/omarchy-pkg-install
bin/omarchy-pkg-remove
bin/omarchy-plymouth-current
bin/omarchy-plymouth-list
bin/omarchy-plymouth-preview
bin/omarchy-plymouth-reset
bin/omarchy-plymouth-set
bin/omarchy-plymouth-set-by-theme
bin/omarchy-plymouth-switcher
bin/omarchy-provision-owner
bin/omarchy-refresh-limine
bin/omarchy-refresh-pacman
bin/omarchy-refresh-plymouth
bin/omarchy-refresh-sddm
bin/omarchy-reinstall-pkgs
bin/omarchy-remove-gaming-battlenet
bin/omarchy-remove-gaming-geforce-now
bin/omarchy-remove-gaming-heroic
bin/omarchy-remove-gaming-lutris
bin/omarchy-remove-gaming-minecraft
bin/omarchy-remove-gaming-retroarch
bin/omarchy-remove-gaming-steam
bin/omarchy-remove-gaming-xbox-cloud
bin/omarchy-remove-gaming-xbox-controllers
bin/omarchy-remove-preinstalls
bin/omarchy-remove-security-fido2
bin/omarchy-remove-security-sudoless-docker
bin/omarchy-remove-service-sunshine
bin/omarchy-setup-direct-boot
bin/omarchy-setup-security-fido2
bin/omarchy-setup-security-sudoless-docker
bin/omarchy-snapshot
bin/omarchy-sudo-docker
bin/omarchy-sudo-passwordless
bin/omarchy-system-factory-reset
bin/omarchy-system-factory-reset-finish
bin/omarchy-toggle-hybrid-gpu
bin/omarchy-update-analyze-logs
bin/omarchy-update-aur-pkgs
bin/omarchy-update-confirm
bin/omarchy-update-dev
bin/omarchy-update-keyring
bin/omarchy-update-lock
bin/omarchy-update-orphan-pkgs
bin/omarchy-update-pacman-guard
bin/omarchy-update-pkg-prune
bin/omarchy-update-requires-free-space
bin/omarchy-update-restart
bin/omarchy-update-status
bin/omarchy-update-stay-awake
bin/omarchy-update-system-pkgs
bin/omarchy-update-system-pkgs-when-conflicted
bin/omarchy-update-user-notify
bin/omarchy-upgrade-to-quattro
bin/omarchy-upload-log
bin/omarchy-windows-vm

# --- found by the dropped-reference gate: only reachable from things dropped above
bin/omarchy-reinstall
bin/omarchy-launch-battlenet
default/applications/battlenet.desktop
```

- [ ] **Step 2: Record the checksum**

`upstream.lock` must look like this before the step (it does at the time of writing):

```
# The contract every Tinkero component checks. Bump deliberately; see the design spec, section 4.12.
# Format: shell-sourceable key=value, no quoting, no expansion.
# omarchy_sha256 is added by `make lock` when the tarball is first fetched (Phase 2); builds fail without it.
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
quickshell_commit=28771c7c74b42e20afca0b1b63980cb46515537c
fedora=44
tinkero_rev=1
```

Run: `./dev lock`
Expected: stderr says `recorded omarchy_sha256=<64 hex digits> in .../upstream.lock`, stdout prints `.cache/omarchy-c668141e9c42b13c80c9ca4ea108e11708c5e8a5.tar.gz`. `git diff upstream.lock` shows exactly one added line after `omarchy_commit=`. Also delete the now-stale comment line `# omarchy_sha256 is added by ...` from the file header.

- [ ] **Step 3: First assembly, no patches yet**

Run: `: > patches/series` (after `mkdir -p patches`), then `./dev payload`.
Expected: `assembled 365 commands into .cache/payload`. If a drop line matches nothing, the error names it: compare with `ls` in a scratch unpack of the tarball and fix the line, do not delete it blindly.

- [ ] **Step 4: Add the first patch**

`omarchy-version` asks pacman for the package version. The tree's own `version` file cannot be used instead: at `v4.0.4` it still reads `4.0.0.alpha`. Create `patches/0001-omarchy-version-from-rpm.patch` exactly as below (text before the first `---` line is a description; `git apply` ignores it):

```diff
Read the version from the tinkero RPM instead of pacman.

The tree's own version file is not usable: at v4.0.4 it still says 4.0.0.alpha.

--- a/bin/omarchy-version
+++ b/bin/omarchy-version
@@ -17,11 +17,8 @@
   exit 0
 fi
 
-# The edge channel installs omarchy-dev instead of omarchy, so check both.
-for package in omarchy-dev omarchy; do
-  version=$(pacman -Q "$package" 2>/dev/null | awk '{ print $2 }')
-  [[ -n $version ]] && break
-done
+# Tinkero: the tree belongs to the tinkero RPM, whose version is the upstream tag.
+version=$(rpm -q --qf '%{VERSION}-%{RELEASE}' tinkero 2>/dev/null) || version=""
 
 [[ -n $version ]] || exit 1
 
```

Three context lines in that patch consist of a single space (they stand for empty lines in the script). If your editor strips trailing whitespace the patch becomes corrupt; in that case generate it with the recipe at the end of this step instead of pasting, and check it with `git apply --check` from a scratch unpack of the tarball.

Create `patches/series`:

```
0001-omarchy-version-from-rpm.patch
```

How patches are made, for every later one: unpack the cached tarball twice (`mkdir -p /tmp/p/a /tmp/p/b && for d in a b; do tar -xzf .cache/omarchy-*.tar.gz -C /tmp/p/$d --strip-components=1; done`), edit under `/tmp/p/b`, then `cd /tmp/p && diff -u a/bin/NAME b/bin/NAME | sed -E 's/^(---|\+\+\+) ([ab]\/[^\t]+).*/\1 \2/'`. Never hand-count hunk headers.

- [ ] **Step 5: Add the first replacement**

Create `distro/fedora/replacements/omarchy-update` (mode does not matter in the repo; `assemble` installs it 0755). The `# omarchy:summary=` line is upstream's metadata convention, which the `omarchy` CLI router reads:

```bash
#!/bin/bash

# omarchy:summary=Explain how Tinkero is updated

echo "Tinkero updates through 'sudo dnf upgrade' and 'mise up'; see tinkero-status."
```

- [ ] **Step 6: Verify both on the real tree**

Run: `./dev payload && sed -n '20,21p' .cache/payload/usr/bin/omarchy-version && tail -n1 .cache/payload/usr/bin/omarchy-update`
Expected:

```
# Tinkero: the tree belongs to the tinkero RPM, whose version is the upstream tag.
version=$(rpm -q --qf '%{VERSION}-%{RELEASE}' tinkero 2>/dev/null) || version=""
echo "Tinkero updates through 'sudo dnf upgrade' and 'mise up'; see tinkero-status."
```

- [ ] **Step 7: Write the baselines and read them**

Run: `./dev baseline`
Expected: `WROTE: ci/allow/arch-leak.allow (28 entries)` and `WROTE: ci/allow/dropped-refs.allow (50 entries)`. Small differences in the counts are possible if this plan's drop list was edited; large ones are not.

Read both files. Every line must be explainable from the audit: `arch-leak` holds the scripts that 2B patches or replaces (the `omarchy-pkg-*` family, `omarchy-debug`, `omarchy-channel-*`, `MenuModel.js`, ...) plus five comment-only hits the audit allowlists permanently (`omarchy-default-agent`, `hooks.md`, `fonts/omarchy/README.md`, `input.lua`, `launcher.hides`); `dropped-refs` is dominated by `omarchy-menu.jsonc` (plan 2C) and by scripts that 2B replaces (`omarchy-channel-set`, `omarchy-reinstall-configs`, `omarchy-provision-user`). A line you cannot explain is a finding: stop and report it rather than committing it.

- [ ] **Step 8: Gates are green, and they bite**

Run: `./dev gates` and expect three `PASS` lines, exit 0.
Then prove the gate works on real data: `echo 'usr/bin/omarchy-never-existed' >> ci/allow/arch-leak.allow && ./dev gates; echo rc=$?` must print a `stale allowlist entries` failure and `rc=1`. Undo with `git checkout ci/allow/arch-leak.allow` (after the commit below) or `sed -i '$d' ci/allow/arch-leak.allow`.

- [ ] **Step 9: Commit**

```bash
git add build/drop.list patches distro/fedora/replacements ci/allow upstream.lock
git commit -m "build: real drop list, first patch and replacement, gate baselines for v4.0.4"
```

---

### Task 7: CI

Nothing in this task can be run on a stock workstation (ShellCheck, rpmlint, `rpmspec`, `make` and `rpm-build` are absent), and none of it was run while writing this plan. Expect to iterate: push the branch, read the job log, fix, repeat. Two things are likely to need a touch: ShellCheck findings in the scripts above, and rpmlint's opinion of the spec. Fix the scripts rather than silencing a check, except for the two source-following codes already excluded below.

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow**

`git` is installed before `actions/checkout` so that the checkout is a real clone: `.copr/Makefile` uses `git archive`.

```yaml
name: ci
on:
  push:
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    container: fedora:44
    steps:
      - name: Tools
        run: dnf -y install git-core curl diffutils findutils ShellCheck rpmlint rpm-build make
      - uses: actions/checkout@v4
      - name: Trust the workspace
        run: git config --global --add safe.directory "$GITHUB_WORKSPACE"
      - name: ShellCheck
        run: >
          shellcheck -x -e SC1090,SC1091
          dev build/assemble build/fetch-upstream build/render-spec build/lib.sh
          ci/gate-arch-leak ci/gate-dropped-refs ci/gate-single-copy ci/lib-gate.sh
          tests/run tests/lib.sh tests/test-*.sh tests/fixtures/make-tree.sh
          distro/fedora/replacements/*
      - name: Unit tests
        run: ./dev check
      - name: Gates on the real upstream tree
        run: ./dev gates
      - name: Spec renders, parses and lints
        run: |
          ./dev spec
          rpmspec -P tinkero.spec > /dev/null
          rpmlint tinkero.spec
      - name: SRPM builds the way COPR builds it
        run: |
          mkdir -p "$PWD/.cache/srpm"
          make -f .copr/Makefile srpm outdir="$PWD/.cache/srpm"
          ls -l .cache/srpm/*.src.rpm
```

- [ ] **Step 2: Push and iterate until green**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: shellcheck, unit tests, real-tree gates, spec lint, SRPM build"
git push -u origin HEAD
gh run watch
```

Expected end state: every step green. If `rpmbuild -bs` complains that `Source1` is missing, check that `.cache/tinkero-src.tar.gz` was written before `rpmbuild` ran and that `_sourcedir` points at `.cache`.

- [ ] **Step 3: Record what CI taught**

If any script changed to satisfy ShellCheck, re-run `./dev check && ./dev gates` locally, commit, and add one line per change to the "Deviations" section at the bottom of this plan file so that plans 2B onward start from what is true.

---

## Deviations

- `build/assemble`: `rm -rf "$tree/etc"` became `rm -rf "${tree:?}/etc"` (ShellCheck SC2115: guard against the var ever being empty and expanding to `/etc`).
- `build/assemble`: the final `ls "$dest/usr/bin" | wc -l` became `find "$dest/usr/bin" -mindepth 1 -maxdepth 1 | wc -l` (ShellCheck SC2012).
- `build/lib.sh`, `ci/lib-gate.sh`, `tests/lib.sh`: added a leading `# shellcheck shell=bash` directive; these files are meant to be sourced, not executed, so they have no shebang and ShellCheck otherwise cannot tell what dialect to check them as (SC2148).
- `ci/lib-gate.sh`: the two `sed 's/^/  /' <<<"$var"` indent helpers became `echo "  ${var//$'\n'/$'\n'  }"` (ShellCheck SC2001, pure bash instead of a sed subprocess, same output).
- `tests/lib.sh`: the `ROOT` variable is set here but only read by scripts that source this file (`tests/test-lock.sh` uses `$ROOT/build/lib.sh`), so ShellCheck flags it as unused in isolation; added `# shellcheck disable=SC2034` with a reason (SC2034).
- `tests/lib.sh` and `tests/test-gates.sh`: the `assert_*` one-liners and one inline check used the `cond && ok ... || not_ok ...` pattern; rewritten as `if/then/else` (ShellCheck SC2015: the `||` branch could in principle also run if `ok` itself failed).
- `tests/test-assemble.sh`, `tests/test-fetch.sh`, `tests/test-gates.sh`, `tests/test-lock.sh`, `tests/test-render-spec.sh`: added a `#!/bin/bash` shebang; they are only ever run via `bash "$t"` from `tests/run`, so the shebang is inert, but ShellCheck needs one to know the dialect when the file is a scan target on its own (SC2148).
- `tests/test-lock.sh`: added `# shellcheck disable=SC2016` with a reason above the line that intentionally single-quotes `$(touch %s/pwned)` so it stays literal text for the lock parser to (correctly) not execute (SC2016).
- CI workflow tested locally against a `fedora:44` container (docker) before each push, since none of ShellCheck/rpmlint/rpmspec/make/rpm-build exist on this workstation; the SRPM `git archive` step only works from a real git clone or checkout, not from a git worktree whose `.git` is a pointer file to a host path outside the container mount (a local-testing artifact only, not relevant to `actions/checkout@v4` in CI).

## Review findings that changed the code

Task reviews and the final review found defects in this plan's own code, fixed on the branch:

- `ci/gate-dropped-refs`: the `names=` pipeline needed `|| true`; without it a drop list with no plain `bin/` line killed the gate silently (Task 4).
- `tinkero.spec.in`: the Nerd font was missing from the hard requirements; added as `tinkero-nerd-fonts`, a name the Phase 1 COPR must honour (Task 5).
- The patch must keep its three single-space context lines; verify patches with `cat -A`, never by eye (Task 6).
- ShellCheck fixes across `build/`, `ci/` and `tests/` (Task 7, listed under Deviations).
- Final review wave: `dev` usage range; a plain download block in `fetch-upstream`; `assemble` refuses drop lines that leave the tree and symlinks in upstream `bin/`; gates exit 2 on a missing payload, an unreadable drop list or an unsupported glob, and fail on an empty `bin/`; `LC_ALL=C` in the gates; `render-spec` validates `omarchy_commit` and `quickshell` and no longer reads a zero-padded minor as octal; `outdir` default in `.copr/Makefile`; workflow permissions, concurrency, bash shell and timeout.

## What this plan deliberately leaves out

- The other ten patches and twenty replacement scripts, the package name map and its gate: plan 2B.
- The menu rewrite: plan 2C. Branding (font, wallpapers, manifests, strings): plan 2D. `tinkero-provision`, `install.sh`, `host.md`: plan 2E.
- The lock-screen PAM files, `tinkero-pam-sync`, the GNOME restore and power-key units: plan 2F, written after the Phase 0 findings exist.
- `%files` entries, weak dependencies and scriptlets for any of the above: each plan adds its own.
