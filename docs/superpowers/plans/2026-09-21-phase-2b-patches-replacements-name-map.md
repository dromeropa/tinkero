# Phase 2B: Patches, Replacements and the Package Name Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every kept upstream script correct on Fedora: the package wrappers work through a name map, the remaining Arch-specific scripts are patched or replaced, the menu's package guards answer from rpm and flatpak, and the arch-leak allowlist shrinks from 28 entries to the permanent comment-only ones plus what plans 2C and 2F own.

**Architecture:** Same mechanisms as plan 2A, fed with the real data. Replacements are Tinkero's own scripts under upstream names in `distro/fedora/replacements/`, sharing one sourced library installed at `/usr/share/tinkero/pkg.sh`. The name map `distro/fedora/pkgmap.tsv` (Arch name, kind, target) is the single translation table, used by the wrappers at run time and by the patched menu model, and a fourth gate requires a row for every name the payload uses. Patches are generated from exact string edits and checked with `git apply`; their content is given verbatim with checksums. Tests stay hermetic: the wrappers run against stub `rpm`, `dnf`, `flatpak`, `pkexec` and `sudo` on `PATH`, and the menu prelude is evaluated through `node` when it is available.

**Tech Stack:** bash, coreutils, `git apply`; `node` for one test (CI installs `nodejs`; the test skips itself locally when `node` is absent, and this workstation has it at `/usr/bin/node`).

**Spec:** `docs/superpowers/specs/2026-09-17-tinkero-design.md` (sections 4.3, 4.6, 6, 8). Data: `docs/research/arch-coupling-audit.md` (sections 4, 5, 7, 9, 13). Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`. Plan 2A (executed) built everything this plan extends: `dev`, `build/assemble`, the gates, the tests.

## Global Constraints

- Everything plan 2A's Global Constraints say still binds: pinned upstream, lock parsed not sourced, payload layout, no `etc/` beyond the two files, no sudoers, no setuid, patches with no fuzz, drop lines must match, replacements must shadow an upstream file, allowlists only shrink, no em dashes, `#!/bin/bash` and `set -euo pipefail` in executable scripts.
- **Elevation** (spec 4.3): `pkexec` when `WAYLAND_DISPLAY` or `DISPLAY` is set, `sudo` otherwise, nothing when already root. No sudoers or polkit rules.
- **Name map format** (spec 4.3): `arch-name<TAB>kind<TAB>target`, kinds `dnf`, `flatpak`, `none`; sorted by name under `LC_ALL=C`; one row for every literal package name the payload passes to `omarchy-pkg-add`, `-drop`, `-present` or `-missing`; enforced by `ci/gate-name-map`.
- **Unmapped or `none` names** make `omarchy-pkg-add` print how to install by hand and exit 1; `-present` treats them as not installed.
- **Decisions already recorded** (roadmap, audit 4.3/4.4/4.5, spec 4.3/4.6, all committed): Docker is deferred, not Arch-specific, so `omarchy-launch-docker-tui` and `applications/Docker.desktop` are dropped and only tmux and herdr are re-added to the bindings; OpenClaw's installer and picker case stay, its name-map row is `none`; the sshd pair is patched, not replaced; `omarchy-install-hermes-cli` and `omarchy-default-agent` are not patched; `omarchy-theme-set-gnome` is not replaced (the session's dconf database, spec 4.9, makes it harmless).
- Manifest corrections from Phase 0 (spec 6): `ppd-service` replaces `power-profiles-daemon`; `fcitx5` is a hard requirement.
- Files whose full new content is given below replace the existing file entirely. Patches and the name map are data and must be byte-identical (checksums given).
- Commit messages end with the attribution lines your harness specifies. Push this branch only at the end (Task 6); never master, no PR.

## File Structure

| File | Responsibility |
|---|---|
| `distro/fedora/pkgmap.tsv` | the name map (data) |
| `distro/fedora/lib/pkg.sh` | `pkg_map`, `pkg_installed`, `pkg_unmapped_notice`, `elevate`; installed to `/usr/share/tinkero/pkg.sh` |
| `distro/fedora/replacements/omarchy-pkg-{present,missing,add,drop}` | the package wrappers |
| `distro/fedora/replacements/*` (nine more) | AUR stubs, update/channel/version/hibernation one-liners |
| `patches/0002` to `0010`, `patches/series` | the patch set |
| `ci/gate-name-map` | the fourth gate |
| `build/assemble` | gains the library and map installation, a per-component `..` guard |
| `build/render-spec` | validates `TINKERO_BUILD_DATE` |
| `build/drop.list` | the 2B decisions |
| `tinkero.spec.in` | `ppd-service`, `fcitx5` |
| `tests/test-replacements.sh`, `tests/test-menu-guards.sh` | new tests |
| `tests/test-assemble.sh`, `tests/test-gates.sh`, `tests/test-render-spec.sh` | extended tests (full new content given) |
| `dev`, `.github/workflows/ci.yml` | run the new gate; install `nodejs` in CI |

Interfaces later plans rely on: `pkgmap.tsv` and `/usr/share/tinkero/pkg.sh` (2C's `tinkero-update` and 2E's `host.md` refer to them); `ci/gate-name-map DEST PKGMAP`; the allowlists after Task 6 (2C shrinks `dropped-refs.allow` to its permanent entries and removes the `omarchy-menu.jsonc` line from `arch-leak.allow`; 2F removes `omarchy-setup-security-fingerprint`).

---

### Task 1: Test hygiene and two guard refinements

The final re-review of plan 2A found three regression tests that could not tell their guard from an earlier failure, one fixture that a test corrupted without restoring, an over-broad `..` check, and one unvalidated splice in `render-spec`. Fix them first, so every later task builds on tests that mean what they say.

**Files:**
- Modify: `build/assemble` (one guard line), `build/render-spec` (one validation line)
- Replace: `tests/test-assemble.sh`, `tests/test-render-spec.sh`

- [ ] **Step 1: Replace the two test files**

`tests/test-assemble.sh` (it now also expects `assemble` to ship `pkg.sh` and `pkgmap.tsv`, which Task 2 adds to the real repo; the test builds its own private root, so it passes as soon as `assemble` has the step from Step 3 below):

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp); tb=$("$ROOT/tests/fixtures/make-tree.sh" "$d/src")
# a private repo root so the test controls drop.list, patches and replacements
r=$d/root; mkdir -p "$r"/{build,patches,distro/fedora/replacements,distro/fedora/lib,session,bin}
printf '# lib\n' > "$r/distro/fedora/lib/pkg.sh"; printf 'foot\tdnf\tfoot\n' > "$r/distro/fedora/pkgmap.tsv"
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
assert_file "$d/dest/usr/share/tinkero/pkg.sh" "package library shipped"
assert_file "$d/dest/usr/share/tinkero/pkgmap.tsv" "name map shipped"

# assert_fails cannot tell the guard from the pre-existing "matches nothing" failure,
# so these two pin the guard by its message.
echo '../outside' >> "$r/build/drop.list"
out=$(run "$d/dest6" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a drop line escaping the tree with .. fails the build"
assert_contains "$out" "must be a relative path inside the tree" "and names the guard, not a later failure"
sed -i '$d' "$r/build/drop.list"

echo '/etc' >> "$r/build/drop.list"
out=$(run "$d/dest7" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a drop line starting with / fails the build"
assert_contains "$out" "must be a relative path inside the tree" "and names the guard"
sed -i '$d' "$r/build/drop.list"

echo 'default/foo..bar' >> "$r/build/drop.list"
out=$(run "$d/dest10" 2>&1) && rc=0 || rc=$?
assert_contains "$out" "matches nothing" "a name that merely contains .. is not treated as an escape"
sed -i '$d' "$r/build/drop.list"

mkdir -p "$d/x"
tar -xzf "$tb" -C "$d/x"
ln -s omarchy-keep-me "$d/x/omarchy-fixture/bin/omarchy-alias"
tar -C "$d/x" -czf "$d/symlink-bin.tar.gz" omarchy-fixture
tb_symlink=$d/symlink-bin.tar.gz
run_symlink() { TINKERO_ROOT=$r "$ROOT/build/assemble" "$tb_symlink" "$1"; }
assert_fails "a symlink in upstream bin/ fails the build" run_symlink "$d/dest8"

echo 'bin/omarchy-renamed-upstream' >> "$r/build/drop.list"
assert_fails "a drop line matching nothing fails the build" run "$d/dest2"
sed -i '$d' "$r/build/drop.list"
printf '#!/bin/bash\n' > "$r/distro/fedora/replacements/omarchy-brand-new"
assert_fails "a replacement with no upstream namesake fails" run "$d/dest3"
echo omarchy-brand-new > "$r/distro/fedora/replacements.new"
run "$d/dest4" >/dev/null; assert_file "$d/dest4/usr/bin/omarchy-brand-new" "unless declared in replacements.new"
# destructive: corrupt the patch, then restore it, so a case added below still sees a working fixture
cp "$r/patches/0001-version.patch" "$d/patch.bak"
sed -i 's/pacman -Q omarchy/pacman -Q something-else/' "$r/patches/0001-version.patch"
out=$(run "$d/dest5" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a patch that no longer applies fails the build"
assert_contains "$out" "patch failed: 0001-version.patch" "and names the patch"
cp "$d/patch.bak" "$r/patches/0001-version.patch"
run "$d/dest9" >/dev/null 2>&1; assert_eq "$?" 0 "the fixture is intact again after the destructive case"
rm -rf "$d"; finish
```

`tests/test-render-spec.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/lib.sh"
d=$(mktmp)
cat > "$d/lock" <<'L'
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
tinkero_rev=3
L
reset_lock() {
  cat > "$d/lock" <<'L'
omarchy_tag=v4.0.4
omarchy_commit=c668141e9c42b13c80c9ca4ea108e11708c5e8a5
hyprland=0.56.2
quickshell=0.3.0^20.git28771c7
tinkero_rev=3
L
}
r() { TINKERO_LOCK=$d/lock TINKERO_BUILD_DATE='Thu Sep 17 2026' "$ROOT/build/render-spec" "$d/out.spec"; }
r >/dev/null; s=$(cat "$d/out.spec")
assert_contains "$s" "Version:        4.0.4" "version is the tag without v"
assert_contains "$s" "Release:        3%{?dist}" "release is tinkero_rev"
assert_contains "$s" "Requires:       (hyprland >= 0.56.2 with hyprland < 0.57)" "hyprland range is derived from the lock"
assert_contains "$s" "Requires:       quickshell = 0.3.0^20.git28771c7" "quickshell pin is verbatim"
assert_contains "$s" "tinkero-nerd-fonts" "the Nerd font from the COPR is a hard requirement"
assert_contains "$s" "ppd-service" "power profiles through the virtual provide, not power-profiles-daemon"
[[ $s != *power-profiles-daemon* ]] && ok "power-profiles-daemon is not required by name" || not_ok "power-profiles-daemon is not required by name"
assert_contains "$s" " fcitx5" "fcitx5 is a hard requirement"
assert_contains "$s" "Source0:        omarchy-c668141e9c42b13c80c9ca4ea108e11708c5e8a5.tar.gz" "source names the commit"
assert_eq "$(grep -c '@[A-Z_]*@' "$d/out.spec")" "0" "no placeholder left"
sed -i 's/^hyprland=.*/hyprland=0.56/' "$d/lock"
assert_fails "a malformed hyprland version is rejected" r

reset_lock
sed -i 's/^omarchy_commit=.*/omarchy_commit=abc/' "$d/lock"
assert_fails "a truncated omarchy_commit is rejected" r

reset_lock
sed -i 's/^quickshell=.*/quickshell=0.3|x/' "$d/lock"
out=$(r 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "a quickshell value with unsupported characters is rejected"
assert_contains "$out" "quickshell has characters that cannot appear in an RPM version" "by the validator, not by sed"

reset_lock
sed -i 's/^hyprland=.*/hyprland=0.09.1/' "$d/lock"
r >/dev/null; s2=$(cat "$d/out.spec")
assert_contains "$s2" "hyprland < 0.10" "a zero-padded minor is not read as octal"

TINKERO_LOCK=$d/lock TINKERO_BUILD_DATE='Thu|Sep' "$ROOT/build/render-spec" "$d/o2.spec" >/dev/null 2>&1; assert_eq "$?" 1 "a build date with unsupported characters is rejected"
rm -rf "$d"; finish
```

- [ ] **Step 2: Run them to see the new cases fail**

Run: `bash tests/test-assemble.sh; bash tests/test-render-spec.sh`
Expected: `not ok` on "a name that merely contains .. is not treated as an escape", "package library shipped", "name map shipped", "a build date with unsupported characters is rejected", "ppd-service" and "fcitx5" (Task 6 fixes the last two; leave them red until then) and "by the validator, not by sed".

- [ ] **Step 3: Refine the guard, validate the date, ship the two data files**

In `build/assemble`, replace the line

```bash
  [[ $line == /* || $line == *..* ]] && die "drop.list: '$line' must be a relative path inside the tree"
```

with

```bash
  # a ".." path component (not a name that merely contains "..") or an absolute path could leave the tree
  [[ $line == /* || $line == .. || $line == ../* || $line == */.. || $line == */../* ]] && die "drop.list: '$line' must be a relative path inside the tree"
```

and, right after the line that installs `upstream.lock` into `usr/share/tinkero/`, add

```bash
# The package wrappers' library and name map (distro/fedora, plan 2B).
install -Dm 0644 "$root/distro/fedora/lib/pkg.sh" "$dest/usr/share/tinkero/pkg.sh"
install -Dm 0644 "$root/distro/fedora/pkgmap.tsv" "$dest/usr/share/tinkero/pkgmap.tsv"
```

In `build/render-spec`, right after the `date=...` line, add

```bash
[[ $date =~ ^[A-Za-z0-9\ ]+$ ]] || die "TINKERO_BUILD_DATE must be letters, digits and spaces: $date"
```

- [ ] **Step 4: Run the tests**

Run: `bash tests/test-assemble.sh; bash tests/test-render-spec.sh`
Expected: `test-assemble.sh` reports `1..30` with no `not ok`; `test-render-spec.sh` reports `1..16` with exactly three `not ok` (the `ppd-service`, `power-profiles-daemon` and `fcitx5` cases), which Task 6 turns green. `./dev payload` fails from now until Task 2 (no `pkgmap.tsv` yet); that is expected.

- [ ] **Step 5: Commit**

```bash
git add build/assemble build/render-spec tests/test-assemble.sh tests/test-render-spec.sh
git commit -m "tests: pin guards by message, restore the patch fixture, per-component .. guard, validated build date"
```

---

### Task 2: The name map, its library and its gate

**Files:**
- Create: `distro/fedora/pkgmap.tsv`, `distro/fedora/lib/pkg.sh`, `ci/gate-name-map`
- Modify: `dev` (one line)
- Replace: `tests/test-gates.sh`

**Interfaces:**
- Produces: `pkg_map NAME` prints `kind<TAB>target` or returns 1; `pkg_installed NAME` returns 0 when the mapped package is installed (`rpm -q` for `dnf`, `flatpak info` for `flatpak`, never for `none`); `pkg_unmapped_notice NAME` prints the by-hand instruction to stderr; `elevate CMD...` runs as root per the elevation rule. Environment overrides for tests: `TINKERO_PKGMAP` (map path) and `TINKERO_PKG_LIB` (library path, read by the replacements). `ci/gate-name-map DEST PKGMAP` exits 0 when every used name has a row and the map is well-formed and sorted, 1 on findings, 2 on unusable inputs.

- [ ] **Step 1: Write the failing tests**

Replace `tests/test-gates.sh` (the last block is new):

```bash
#!/bin/bash
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

# fail loudly on a missing payload instead of silently passing
out=$("$ROOT/ci/gate-arch-leak" "$d/no-payload" "$d/allow-nopayload" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "2" "arch-leak fails loudly when there is no payload at DEST"
assert_contains "$out" "no payload at DEST" "and says so"

# dropped-refs
: > "$d/allow2"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop.list" "$d/allow2" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs fails on a call to a dropped command"
assert_contains "$out" "usr/bin/omarchy-caller:omarchy-snapshot" "reports path:command"
assert_contains "$out" "usr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set" "expands drop-list globs"
if [[ $out != *omarchy-snapshot-helper* ]]; then ok "does not match a longer command name"; else not_ok "does not match a longer command name" "$out"; fi
printf 'usr/bin/omarchy-caller:omarchy-snapshot\nusr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set\n' > "$d/allow2"
"$ROOT/ci/gate-dropped-refs" "$p" "$d/drop.list" "$d/allow2" >/dev/null 2>&1; assert_eq "$?" "0" "dropped-refs passes when allowlisted"

# dropped-refs edge cases: all-glob drop list
printf 'bin/omarchy-plymouth-*\n' > "$d/drop-glob.list"
: > "$d/allow3"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-glob.list" "$d/allow3" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "dropped-refs with all-glob drop list fails on a match"
assert_contains "$out" "usr/share/omarchy/default/menu.jsonc:omarchy-plymouth-set" "reports the finding"

# dropped-refs edge cases: no bin/ lines
printf 'migrations\n' > "$d/drop-nobin.list"
: > "$d/allow4"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-nobin.list" "$d/allow4" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "0" "dropped-refs with no bin/ lines passes"
assert_contains "$out" "PASS" "and reports PASS"

# dropped-refs edge case: drop list cannot be read
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/no-such-droplist" "$d/allow6" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "2" "dropped-refs fails loudly when the drop list cannot be read"
assert_contains "$out" "cannot read drop list" "and says so"

# dropped-refs edge case: unsupported glob character
printf 'bin/omarchy-fo?o\n' > "$d/drop-badglob.list"
out=$("$ROOT/ci/gate-dropped-refs" "$p" "$d/drop-badglob.list" "$d/allow7" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "2" "dropped-refs rejects an unsupported glob character"
assert_contains "$out" "unsupported glob" "and says so"

# single-copy
"$ROOT/ci/gate-single-copy" "$p" >/dev/null 2>&1; assert_eq "$?" "0" "single-copy passes on a correct layout"
rm "$p/usr/share/omarchy/bin/omarchy-clean"; cp "$p/usr/bin/omarchy-clean" "$p/usr/share/omarchy/bin/omarchy-clean"
"$ROOT/ci/gate-single-copy" "$p" >/dev/null 2>&1; assert_eq "$?" "1" "single-copy fails on a regular file in the tree bin/"

# single-copy edge case: no commands at all
mkdir -p "$d/empty-dest/usr/bin" "$d/empty-dest/usr/share/omarchy/bin"
out=$("$ROOT/ci/gate-single-copy" "$d/empty-dest" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" "1" "single-copy fails when there are no commands"
assert_contains "$out" "no commands in usr/share/omarchy/bin" "and says so"

# name-map
mkdir -p "$p/usr/share/omarchy/default"
printf '#!/bin/bash\nomarchy-pkg-add foot vim 2>/dev/null\n# omarchy-pkg-add commented out\n' > "$p/usr/bin/omarchy-installer"
printf 'foot\tdnf\tfoot\nvim\tdnf\tvim-enhanced\n' > "$d/map"
"$ROOT/ci/gate-name-map" "$p" "$d/map" >/dev/null 2>&1; assert_eq "$?" 0 "name-map passes when every used name has a row"
printf 'foot\tdnf\tfoot\n' > "$d/map2"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map2" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on a used name with no row"
assert_contains "$out" "  vim" "and names it"
[[ $out != *commented* ]] && ok "name-map ignores comment lines in scripts" || not_ok "name-map ignores comment lines in scripts" "$out"
printf 'vim\tdnf\tvim-enhanced\nfoot\tdnf\tfoot\n' > "$d/map3"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map3" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails when the map is not sorted"; assert_contains "$out" "not sorted" "and says so"
printf 'foot\tdnf\tfoot\nvim\tapt\tvim\n' > "$d/map4"
out=$("$ROOT/ci/gate-name-map" "$p" "$d/map4" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 1 "name-map fails on an unknown kind"; assert_contains "$out" "malformed" "and says so"
"$ROOT/ci/gate-name-map" "$p" "$d/nope" >/dev/null 2>&1; assert_eq "$?" 2 "name-map exits 2 on an unreadable map"
rm -rf "$d"; finish
```

Run: `bash tests/test-gates.sh`
Expected: `not ok` on the six name-map cases; `ci/gate-name-map: No such file`.

- [ ] **Step 2: Write the name map**

Create `distro/fedora/pkgmap.tsv` **with tabs, not spaces, between the fields**; sha256 `d6aecb866a74e5b46c58a6d5b1c28d9ce1a4960e08f537d8e1753d6c864a20ed`. The rows are every literal name the assembled `v4.0.4` payload passes to a package wrapper (extracted while writing this plan), sorted under `LC_ALL=C`. The `dnf` targets were checked against Fedora 44 with `dnf repoquery`; the Flathub ids were not checked and Step 5 does that.

```tsv
# Tinkero package name map: Arch package name (as upstream's scripts and menu guards use it),
# kind, target. kind: dnf (Fedora or Tinkero COPR package), flatpak (Flathub application id),
# none (no route yet: the wrappers explain how to install by hand). One row per name that the
# payload passes to omarchy-pkg-add/drop/present/missing; ci/gate-name-map enforces that.
# Keep the rows sorted by name. Tab-separated.
1password	none	-
1password-cli	none	-
alacritty	dnf	alacritty
bitwarden	flatpak	com.bitwarden.desktop
brave-bin	flatpak	com.brave.Browser
brave-origin-bin	none	-
composer	dnf	composer
cursor-bin	none	-
dropbox	none	-
dropbox-cli	none	-
firefox	dnf	firefox
foot	dnf	foot
fprintd	dnf	fprintd
fwupd	dnf	fwupd
ghostty	none	-
google-chrome	flatpak	com.google.Chrome
grok-bot	none	-
helix	dnf	helix
hermes-desktop	none	-
heroic-games-launcher-bin	none	-
kitty	dnf	kitty
libappindicator-gtk3	dnf	libappindicator-gtk3
libfprint	dnf	libfprint
libfprint-git	dnf	libfprint
libyaml	dnf	libyaml
lmstudio-bin	none	-
lutris	dnf	lutris
microsoft-edge-stable-bin	flatpak	com.microsoft.Edge
minecraft-launcher	none	-
nautilus-dropbox	none	-
nordvpn-bin	none	-
omarchy-emacs	none	-
omazed	none	-
once-bin	none	-
openai-codex-desktop	none	-
openclaw	none	-
openssh	dnf	openssh-server
pam-u2f	dnf	pam-u2f
perplexity	none	-
php	dnf	php
php-sqlite	dnf	php-pdo
python-gpgme	dnf	python3-gpg
retroarch	dnf	retroarch
rlwrap	dnf	rlwrap
signal-desktop	flatpak	org.signal.Signal
spotify	flatpak	com.spotify.Client
steam	none	-
sublime-text-4	none	-
symfony-cli	none	-
t3code-bin	none	-
tailscale	dnf	tailscale
usbutils	dnf	usbutils
vim	dnf	vim-enhanced
visual-studio-code-bin	flatpak	com.visualstudio.code
voxtype-bin	dnf	voxtype
wtype	dnf	wtype
xdebug	dnf	php-pecl-xdebug3
xpadneo-dkms	none	-
ydotool	dnf	ydotool
zed	flatpak	dev.zed.Zed
zen-browser-bin	flatpak	app.zen_browser.zen
```

If your editor turned the tabs into spaces, `sha256sum distro/fedora/pkgmap.tsv` will not match; `awk -F'\t' '!/^#/ && NF != 3' distro/fedora/pkgmap.tsv` must print nothing.

- [ ] **Step 3: Write the library and the gate**

Create `distro/fedora/lib/pkg.sh` (sourced, not executable):

```bash
# shellcheck shell=bash
# Sourced by the omarchy-pkg-* replacements (installed at /usr/share/tinkero/pkg.sh).
# The name map, /usr/share/tinkero/pkgmap.tsv, has one row per Arch package name
# that anything in the payload passes to a package wrapper:
#   arch-name <TAB> kind <TAB> target      kind is dnf, flatpak or none
TINKERO_PKGMAP=${TINKERO_PKGMAP:-/usr/share/tinkero/pkgmap.tsv}

# pkg_map ARCH-NAME: print "kind<TAB>target"; return 1 when the name has no row.
pkg_map() {
  local line
  line=$(awk -F'\t' -v n="$1" '$1 == n { print $2 "\t" $3; exit }' "$TINKERO_PKGMAP")
  [[ -n $line ]] || return 1
  printf '%s\n' "$line"
}

# pkg_installed ARCH-NAME: 0 when the mapped package is installed.
pkg_installed() {
  local kind target
  IFS=$'\t' read -r kind target < <(pkg_map "$1") || return 1
  case $kind in
    dnf)     rpm -q "$target" &>/dev/null ;;
    flatpak) flatpak info "$target" &>/dev/null ;;
    *)       return 1 ;;
  esac
}

# pkg_unmapped_notice ARCH-NAME: explain what to do by hand.
pkg_unmapped_notice() {
  cat >&2 <<EOF
Tinkero: no Fedora package is mapped for '$1'.
Install it by hand ('dnf search $1' or 'flatpak search $1'), and if that works,
add a row for it to $TINKERO_PKGMAP so the menu and the agent know about it.
EOF
}

# elevate CMD...: run as root. pkexec inside a graphical session (the shell's polkit
# dialog answers it, which an agent's terminal cannot); sudo over SSH or on a console.
elevate() {
  if (( EUID == 0 )); then "$@"
  elif [[ -n ${WAYLAND_DISPLAY:-} || -n ${DISPLAY:-} ]]; then pkexec "$@"
  else sudo "$@"
  fi
}
```

Create `ci/gate-name-map` (`chmod +x`):

```bash
#!/bin/bash
# gate-name-map DEST PKGMAP: every literal package name that the payload passes to
# omarchy-pkg-add, -drop, -present or -missing (in scripts and in the menu's guards)
# must have a row in the name map, and the map must be well-formed and sorted.
set -euo pipefail
export LC_ALL=C
[[ $# -eq 2 ]] || { echo "usage: gate-name-map DEST PKGMAP" >&2; exit 2; }
dest=$1; map=$2
[[ -d $dest/usr/bin ]] || { echo "FAIL: no payload at $dest (run ./dev payload first)"; exit 2; }
[[ -r $map ]] || { echo "FAIL: cannot read name map: $map"; exit 2; }
rc=0

# 1. The map itself: three tab-separated fields, a known kind, sorted, no duplicates.
rows=$(grep -vE '^\s*(#|$)' "$map" || true)
bad=$(awk -F'\t' 'NF != 3 || $2 !~ /^(dnf|flatpak|none)$/ || $1 == "" || $3 == "" { print NR": "$0 }' <<<"$rows")
if [[ -n $bad ]]; then echo "FAIL: malformed name map rows:"; printf '  %s\n' "${bad//$'\n'/$'\n'  }"; rc=1; fi
names=$(cut -f1 <<<"$rows")
if [[ $(sort -u <<<"$names") != "$(sort <<<"$names")" ]]; then echo "FAIL: duplicate names in the name map"; rc=1; fi
if [[ $(sort <<<"$names") != "$names" ]]; then echo "FAIL: name map is not sorted by name (LC_ALL=C sort)"; rc=1; fi

# 2. Names used by the payload: literal arguments on non-comment lines.
# Comment lines (shell # and JS //) are skipped, a trailing "2>/dev/null" is cut off, and a bare number is not a name.
used=$(grep -rhE "omarchy-pkg-(add|drop|present|missing) +[A-Za-z0-9._+@:-]" "$dest/usr/bin" "$dest/usr/share/omarchy" 2>/dev/null \
  | grep -vE '^\s*(#|//)' | sed -E 's/[0-9]+>.*$//' \
  | grep -oE "omarchy-pkg-(add|drop|present|missing)( +[A-Za-z0-9._+@:-]+)+" \
  | sed -E 's/^omarchy-pkg-(add|drop|present|missing) +//' | tr ' ' '\n' | grep -vE '^([0-9]+)?$' | sort -u || true)
missing=$(comm -23 <(printf '%s\n' "$used") <(sort <<<"$names"))
if [[ -n $missing ]]; then echo "FAIL: package names used by the payload with no row in $map:"; printf '  %s\n' "${missing//$'\n'/$'\n'  }"; rc=1; fi

[[ $rc -eq 0 ]] && echo "PASS: name map covers $(wc -l <<<"$used") package name(s) used by the payload"
exit $rc
```

In `dev`, inside `gates()`, after the `ci/gate-dropped-refs` line, add:

```bash
  ci/gate-name-map "$payload" distro/fedora/pkgmap.tsv || rc=1
```

- [ ] **Step 4: Run the tests and the gate on the real payload**

Run: `bash tests/test-gates.sh` (expect `1..33`, no `not ok`), then `./dev payload && ci/gate-name-map .cache/payload distro/fedora/pkgmap.tsv`.
Expected: `PASS: name map covers 61 package name(s) used by the payload`. A missing name means the payload differs from what this plan extracted; add a row (kind `none` if in doubt) and say so in your report.

- [ ] **Step 5: Check the Flathub ids**

Run, on a machine with Flathub configured (this workstation, if `flatpak remotes` lists `flathub`): for each `flatpak` row, `flatpak search --columns=application <id>` must list the id. Correct any id that does not resolve (the sha256 above then changes; record the new one in your report). If Flathub is not configured, record that the check was skipped.

- [ ] **Step 6: Commit**

```bash
git add distro/fedora/pkgmap.tsv distro/fedora/lib/pkg.sh ci/gate-name-map dev tests/test-gates.sh
git commit -m "build: package name map, wrapper library and the name-map gate"
```

---

### Task 3: The replacement scripts

**Files:**
- Create: 13 files under `distro/fedora/replacements/` (all `chmod +x`), `tests/test-replacements.sh`

**Interfaces:**
- Consumes: `pkg.sh` from Task 2.
- Produces: `omarchy-pkg-present NAMES...` (0 if all installed), `omarchy-pkg-missing NAMES...` (0 if any missing), `omarchy-pkg-add NAMES...` (installs what is missing, dnf through `elevate`, flatpak from Flathub; 1 if anything is unmapped, `none`, or still missing afterwards), `omarchy-pkg-drop NAMES...` (removes what is installed), and the nine one-liners. Every file carries upstream's `# omarchy:summary=` metadata line, which the `omarchy` CLI router reads.

- [ ] **Step 1: Write the failing test**

Create `tests/test-replacements.sh`:

```bash
#!/bin/bash
# The Fedora replacement wrappers, run against stub package tools on PATH.
# Each stub appends its argv to $LOG; rpm/flatpak answer from files the test writes.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
export TINKERO_PKG_LIB=$ROOT/distro/fedora/lib/pkg.sh TINKERO_PKGMAP=$d/map
printf 'foot\tdnf\tfoot\nvim\tdnf\tvim-enhanced\nsignal-desktop\tflatpak\torg.signal.Signal\nopenclaw\tnone\t-\n' > "$d/map"
# rpm -q NAME: installed if NAME is listed in $d/rpms; rpm -qa --qf: print $d/rpms lines
cat > "$d/bin/rpm" <<'S'
#!/bin/bash
echo "rpm $*" >> "$LOG"
case $1 in
  -q) grep -qx "$2" "${RPMS}" ;;
  -qa) [[ ${3:-} == *INSTALLTIME* ]] && printf '1700000000\n1800000000\n' || cat "${RPMS}" ;;
esac
S
cat > "$d/bin/flatpak" <<'S'
#!/bin/bash
echo "flatpak $*" >> "$LOG"
case $1 in
  info) grep -qx "$2" "${FLATPAKS}" ;;
  remotes) cat "${REMOTES}" ;;
  install|uninstall) exit 0 ;;
esac
S
printf '#!/bin/bash\necho "pkexec $*" >> "$LOG"; exec "$@"\n' > "$d/bin/pkexec"
printf '#!/bin/bash\necho "sudo $*" >> "$LOG"; exec "$@"\n' > "$d/bin/sudo"
printf '#!/bin/bash\necho "dnf $*" >> "$LOG"\n' > "$d/bin/dnf"
chmod +x "$d/bin"/*
export PATH=$d/bin:$PATH RPMS=$d/rpms FLATPAKS=$d/flatpaks REMOTES=$d/remotes
printf 'foot\n' > "$RPMS"; : > "$FLATPAKS"; printf 'fedora\nflathub\n' > "$REMOTES"
R=$ROOT/distro/fedora/replacements

# present / missing
"$R/omarchy-pkg-present" foot;        assert_eq "$?" 0 "present: mapped and installed"
"$R/omarchy-pkg-present" vim;         assert_eq "$?" 1 "present: mapped, not installed"
"$R/omarchy-pkg-present" foot vim;    assert_eq "$?" 1 "present: all names must be installed"
"$R/omarchy-pkg-present" nope;        assert_eq "$?" 1 "present: unmapped name is not installed"
"$R/omarchy-pkg-present" openclaw;    assert_eq "$?" 1 "present: kind none is never installed"
"$R/omarchy-pkg-missing" foot;        assert_eq "$?" 1 "missing: installed name is not missing"
"$R/omarchy-pkg-missing" foot vim;    assert_eq "$?" 0 "missing: any missing name suffices"

# add: dnf through pkexec inside a graphical session, sudo without one
: > "$LOG"; WAYLAND_DISPLAY=wayland-1 "$R/omarchy-pkg-add" vim >/dev/null 2>&1; rc=$?
assert_contains "$(cat "$LOG")" "pkexec dnf install -y vim-enhanced" "add: dnf target through pkexec in a session"
assert_eq "$rc" 1 "add: fails when the package is still not installed afterwards (stub dnf installs nothing)"
printf 'foot\nvim-enhanced\n' > "$RPMS"
: > "$LOG"; env -u WAYLAND_DISPLAY -u DISPLAY "$R/omarchy-pkg-add" vim >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "add: already installed is a no-op success"
assert_eq "$(cat "$LOG" | grep -c dnf)" 0 "add: no dnf call when nothing is missing"
printf 'foot\n' > "$RPMS"
: > "$LOG"; env -u WAYLAND_DISPLAY -u DISPLAY "$R/omarchy-pkg-add" vim >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "sudo dnf install -y vim-enhanced" "add: sudo outside a graphical session"
: > "$LOG"; out=$("$R/omarchy-pkg-add" openclaw 2>&1); rc=$?
assert_eq "$rc" 1 "add: kind none fails"
assert_contains "$out" "no Fedora package is mapped for 'openclaw'" "add: and explains how to install by hand"
out=$("$R/omarchy-pkg-add" nope 2>&1); assert_contains "$out" "no Fedora package is mapped for 'nope'" "add: unmapped name explains too"
: > "$LOG"; "$R/omarchy-pkg-add" signal-desktop >/dev/null 2>&1
assert_contains "$(cat "$LOG")" "flatpak install -y flathub org.signal.Signal" "add: flatpak target installs from flathub"
printf 'fedora\n' > "$REMOTES"; out=$("$R/omarchy-pkg-add" signal-desktop 2>&1); rc=$?
assert_eq "$rc" 1 "add: no flathub remote fails"; assert_contains "$out" "Flathub is not configured" "add: and says so"

# drop
printf 'foot\n' > "$RPMS"; printf 'org.signal.Signal\n' > "$FLATPAKS"
: > "$LOG"; WAYLAND_DISPLAY=w "$R/omarchy-pkg-drop" foot vim signal-desktop nope >/dev/null 2>&1; rc=$?
assert_eq "$rc" 0 "drop: succeeds"
assert_contains "$(cat "$LOG")" "pkexec dnf remove -y foot" "drop: removes only installed dnf targets"
assert_contains "$(cat "$LOG")" "flatpak uninstall -y org.signal.Signal" "drop: uninstalls installed flatpaks"
if grep "dnf remove" "$LOG" | grep -q vim-enhanced; then not_ok "drop: skips names that are not installed"; else ok "drop: skips names that are not installed"; fi

# the stubs and one-liners
"$R/omarchy-pkg-aur-accessible";      assert_eq "$?" 1 "aur-accessible: false"
"$R/omarchy-pkg-aur-add" x 2>/dev/null; assert_eq "$?" 1 "aur-add: fails"
"$R/omarchy-update-available";        assert_eq "$?" 1 "update-available: nothing to announce"
assert_eq "$("$R/omarchy-channel-current")" tinkero "channel-current"
assert_eq "$("$R/omarchy-version-channel")" tinkero "version-channel"
"$R/omarchy-channel-set" edge 2>/dev/null; assert_eq "$?" 1 "channel-set: refuses"
"$R/omarchy-hibernation-available";   assert_eq "$?" 1 "hibernation-available: false"
assert_eq "$(TZ=UTC "$R/omarchy-version-pkgs")" "2027-01-15 08:00" "version-pkgs: newest rpm install time"
rm -rf "$d"; finish
```

Run: `bash tests/test-replacements.sh`
Expected: 30 `not ok` (the scripts do not exist).

- [ ] **Step 2: Write the four package wrappers**

`distro/fedora/replacements/omarchy-pkg-present` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Returns true if all of the named packages are installed on the system

# shellcheck source=distro/fedora/lib/pkg.sh
source "${TINKERO_PKG_LIB:-/usr/share/tinkero/pkg.sh}"
for pkg in "$@"; do
  pkg_installed "$pkg" || exit 1
done
exit 0
```

`distro/fedora/replacements/omarchy-pkg-missing` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Returns true if any of the named packages are missing from the system

# shellcheck source=distro/fedora/lib/pkg.sh
source "${TINKERO_PKG_LIB:-/usr/share/tinkero/pkg.sh}"
for pkg in "$@"; do
  pkg_installed "$pkg" || exit 0
done
exit 1
```

`distro/fedora/replacements/omarchy-pkg-add` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Install the named packages if they are missing (Fedora: dnf or Flatpak through the name map)
# omarchy:args=<packages...>

set -uo pipefail
# shellcheck source=distro/fedora/lib/pkg.sh
source "${TINKERO_PKG_LIB:-/usr/share/tinkero/pkg.sh}"

dnf_targets=() flatpak_targets=() failed=0
for pkg in "$@"; do
  pkg_installed "$pkg" && continue
  if ! mapped=$(pkg_map "$pkg"); then pkg_unmapped_notice "$pkg"; failed=1; continue; fi
  IFS=$'\t' read -r kind target <<<"$mapped"
  case $kind in
    dnf)     dnf_targets+=("$target") ;;
    flatpak) flatpak_targets+=("$target") ;;
    *)       pkg_unmapped_notice "$pkg"; failed=1 ;;
  esac
done

if (( ${#dnf_targets[@]} )); then
  elevate dnf install -y "${dnf_targets[@]}" || failed=1
fi
if (( ${#flatpak_targets[@]} )); then
  if flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    flatpak install -y flathub "${flatpak_targets[@]}" || failed=1
  else
    echo "Tinkero: Flathub is not configured; add it with 'flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' and retry." >&2
    failed=1
  fi
fi

for pkg in "$@"; do
  if ! pkg_installed "$pkg"; then
    echo -e "\033[31mError: Package '$pkg' did not install\033[0m" >&2
    failed=1
  fi
done
exit $failed
```

`distro/fedora/replacements/omarchy-pkg-drop` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Remove the named packages if they are installed (Fedora: dnf or Flatpak through the name map)
# omarchy:args=<packages...>

set -uo pipefail
# shellcheck source=distro/fedora/lib/pkg.sh
source "${TINKERO_PKG_LIB:-/usr/share/tinkero/pkg.sh}"

dnf_targets=() flatpak_targets=()
for pkg in "$@"; do
  pkg_installed "$pkg" || continue
  IFS=$'\t' read -r kind target < <(pkg_map "$pkg")
  case $kind in
    dnf)     dnf_targets+=("$target") ;;
    flatpak) flatpak_targets+=("$target") ;;
  esac
done
rc=0
(( ${#dnf_targets[@]} )) && { elevate dnf remove -y "${dnf_targets[@]}" || rc=1; }
(( ${#flatpak_targets[@]} )) && { flatpak uninstall -y "${flatpak_targets[@]}" || rc=1; }
exit $rc
```

- [ ] **Step 3: Write the nine small replacements**

`distro/fedora/replacements/omarchy-pkg-aur-accessible` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Returns true if the AUR is up and available (never, on Fedora)

exit 1
```

`distro/fedora/replacements/omarchy-pkg-aur-add` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=No AUR on this host; always fails

echo "Tinkero: there is no AUR on Fedora. Use 'omarchy pkg add' with a name from the map, or install by hand." >&2
exit 1
```

`distro/fedora/replacements/omarchy-pkg-aur-install` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=No AUR on this host; always fails

echo "Tinkero: there is no AUR on Fedora. Use 'omarchy pkg add' with a name from the map, or install by hand." >&2
exit 1
```

`distro/fedora/replacements/omarchy-update-available` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Check whether Omarchy updates are available (Tinkero: never through this path)

# Updates arrive through dnf upgrade; nothing for the bar to announce here.
exit 1
```

`distro/fedora/replacements/omarchy-channel-current` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Print the active package channel

echo tinkero
```

`distro/fedora/replacements/omarchy-channel-set` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Set the package channel (Tinkero has none)
# omarchy:args=<stable|rc|edge|dev>

echo "Tinkero has no channels: the tree is pinned by upstream.lock and updated with dnf upgrade." >&2
exit 1
```

`distro/fedora/replacements/omarchy-version-channel` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Print the active mirror and package channel

echo tinkero
```

`distro/fedora/replacements/omarchy-version-pkgs` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Print when system packages were last upgraded

latest=$(rpm -qa --qf '%{INSTALLTIME}\n' 2>/dev/null | sort -n | tail -n1)
[[ -n $latest ]] || exit 1
date -d "@$latest" '+%Y-%m-%d %H:%M'
```

`distro/fedora/replacements/omarchy-hibernation-available` (`chmod +x`):

```bash
#!/bin/bash

# omarchy:summary=Check if hibernation is supported (Tinkero does not set it up)

exit 1
```

- [ ] **Step 4: Run the tests**

Run: `bash tests/test-replacements.sh` (expect `1..30`, no `not ok`), then `./dev check` (expect `1..30 1..9 1..33 1..4 1..16` with the three Task 6 cases still red, `1..30`).

- [ ] **Step 5: Commit**

```bash
git add distro/fedora/replacements tests/test-replacements.sh
git commit -m "build: Fedora replacements for the package wrappers and the update, channel, version and AUR stubs"
```

---

### Task 4: Patches 0002 to 0009

Eight patches, given verbatim with checksums. Write each with a quoted heredoc in one shell command (`cat > patches/NAME <<'EOF' ... EOF`), never through an editor that trims whitespace, then confirm `sha256sum` matches. If a checksum does not match, diff your file against the block here with `cat -A`; the usual cause is a lost trailing space on a context line. Each patch was generated from exact string edits against the pinned tree and verified with `git apply`.

**Files:**
- Create: `patches/0002-...` to `patches/0009-...`
- Replace: `patches/series`

- [ ] **Step 1: Write the eight patches**

`patches/0002-omarchy-debug-rpm-inventory.patch` (sha256 `4549de2192016253152b510b9e29d0dc664c7c7802819f73f09d5ecabbd2b740`):

```diff
Report the package inventory with rpm instead of pacman and expac.

--- a/bin/omarchy-debug
+++ b/bin/omarchy-debug
@@ -37,7 +37,7 @@
 cat > "$LOG_FILE" <<EOF
 Date: $(date)
 Hostname: $(hostname)
-Omarchy Package: $(pacman -Q omarchy-dev 2>/dev/null || pacman -Q omarchy 2>/dev/null || echo "unknown")
+Tinkero Package: $(rpm -q tinkero 2>/dev/null || echo "unknown")
 
 =========================================
 SYSTEM INFORMATION
@@ -57,7 +57,7 @@
 =========================================
 INSTALLED PACKAGES
 =========================================
-$({ expac -S '%n %v (%r)' $(pacman -Qqe) 2>/dev/null; comm -13 <(pacman -Sql | sort) <(pacman -Qqe | sort) | xargs -r expac -Q '%n %v (AUR)'; } | sort)
+$(rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE} (%{VENDOR})\n' 2>/dev/null | sort)
 EOF
 
 if [[ $PRINT_ONLY = "true" ]]; then
```

`patches/0003-omarchy-reinstall-configs-provision-reset.patch` (sha256 `0f5d0bcc9e3cc64a216ed82d6ffa658002b1c8e6b435e02c7593291c65355dd9`):

```diff
Reset configs through tinkero-provision: Tinkero ships no /etc/skel and drops the Limine and Plymouth refreshers.

--- a/bin/omarchy-reinstall-configs
+++ b/bin/omarchy-reinstall-configs
@@ -16,10 +16,8 @@
 # default in one pass: .bashrc, .config/**, .local/share/applications,
 # nautilus-python extensions, branding, hypr toggles, and migration markers.
 # Trailing dot copies dotfiles; the shell wouldn't glob them with /etc/skel/*.
-cp -af /etc/skel/. ~/
-
-omarchy-refresh-limine
-omarchy-refresh-plymouth
+# Tinkero: no /etc/skel; the seeded files and their hashes are tracked by tinkero-provision.
+tinkero-provision --reset-all
 
 if omarchy-cmd-present omarchy-nvim-refresh; then
   omarchy-nvim-refresh
```

`patches/0004-omarchy-remove-launcher-entry-rpm.patch` (sha256 `8c79fe4695294135629b3d574ec62d6a5748b73da0edac7db8e87a276adcaf3f`):

```diff
Find and remove the package owning a launcher entry with rpm and dnf.

--- a/bin/omarchy-remove-launcher-entry
+++ b/bin/omarchy-remove-launcher-entry
@@ -84,11 +84,11 @@
   exit 0
 fi
 
-if package_name="$(pacman -Qqo "$desktop_file" 2>/dev/null | head -1)" && [[ -n $package_name ]]; then
+if package_name="$(rpm -qf --qf '%{NAME}\n' "$desktop_file" 2>/dev/null | head -1)" && [[ -n $package_name ]]; then
   display_name="${entry_name:-$desktop_name}"
   quoted_package="$(printf '%q' "$package_name")"
   quoted_display="$(printf '%q' "$display_name")"
-  exec omarchy-launch-floating-terminal-with-presentation "echo Uninstalling $quoted_display...; sudo pacman -Rns $quoted_package"
+  exec omarchy-launch-floating-terminal-with-presentation "echo Uninstalling $quoted_display...; pkexec dnf remove -y $quoted_package"
 fi
 
 if omarchy-cmd-present flatpak && flatpak info "${desktop_file_name%.desktop}" >/dev/null 2>&1; then
```

`patches/0005-omarchy-remove-dev-env-pkg-drop.patch` (sha256 `5bdc6805edef7e31ae2fb796862181e12401f5543bd9d104e5724703fad7bc86`):

```diff
Remove development packages through the omarchy-pkg-drop wrapper instead of pacman.

--- a/bin/omarchy-remove-dev-env
+++ b/bin/omarchy-remove-dev-env
@@ -10,7 +10,7 @@
 fi
 
 remove_php() {
-  sudo pacman -Rns --noconfirm php composer php-sqlite xdebug 2>/dev/null || true
+  omarchy-pkg-drop php composer php-sqlite xdebug 2>/dev/null || true
 }
 
 case "$1" in
@@ -50,7 +50,7 @@
   ;;
 symfony)
   echo -e "Removing Symfony CLI...\n"
-  sudo pacman -Rns --noconfirm symfony-cli 2>/dev/null || true
+  omarchy-pkg-drop symfony-cli 2>/dev/null || true
   ;;
 python)
   echo -e "Removing Python...\n"
```

`patches/0006-omarchy-skill-host-guide.patch` (sha256 `9c4e80178f1ef09b055bf7418cc36055ee8e1ac9763d0bd856d5e72f274f3625`):

```diff
Point the omarchy skill's package idiom and fastfetch row at the Fedora host guide.

--- a/default/agents/skills/omarchy/SKILL.md
+++ b/default/agents/skills/omarchy/SKILL.md
@@ -146,7 +146,7 @@
 | `omarchy launch` | Launch apps | `omarchy launch browser` |
 | `omarchy capture` | Screenshots and recordings | `omarchy capture screenshot` |
 | `omarchy reminder` | Desktop notification reminders | `omarchy reminder 15 "Pickup Jack"` |
-| `omarchy pkg` | Package management | `omarchy pkg add <pkg>` |
+| `omarchy pkg` | Package management (Fedora: see `host.md`) | `omarchy pkg add <pkg>` |
 | `omarchy setup` | Interactive setup wizards | `omarchy setup security fingerprint` |
 | `omarchy update` | System updates | `omarchy update` |
 
@@ -172,7 +172,7 @@
 | App | Location |
 |-----|----------|
 | btop | `~/.config/btop/btop.conf` |
-| fastfetch | `/etc/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
+| fastfetch | `/usr/share/tinkero/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
 | lazygit | `~/.config/lazygit/config.yml` |
 | starship | `~/.config/starship.toml` |
 | git | `~/.config/git/config` |
@@ -253,7 +253,7 @@
 2. **Is it a config edit?** Edit in `~/.config/`, never `/usr/share/omarchy/`
 3. **Is it a theme customization?** Follow [`theming.md`](theming.md); create a NEW custom theme directory
 4. **Is it automation?** Follow [`hooks.md`](hooks.md); use `omarchy hook install` and the hook `.d` directories
-5. **Is it a package install?** Use `omarchy pkg add <pkgs...>` (or `omarchy pkg aur add <pkgs...>` for AUR-only packages)
+5. **Is it a package install?** Use `omarchy pkg add <pkgs...>`. There is no AUR on this host; if the name is unknown, `host.md` explains how packages are mapped
 6. **Is it built-in shell/plugin code?** Follow [`plugins.md`](plugins.md); clone it with `omarchy plugin clone`, never edit the packaged copy
 7. **Unsure if command exists?** Run `omarchy commands` (or `omarchy <group> --help` for one group)
 
```

`patches/0007-diagnose-crash-fedora-debuginfod.patch` (sha256 `bbac75eb8a17fc1f89b08685904bf7a7c34c14c6baaacec484bcb9a64cfc82bc`):

````diff
Symbolize crashes through Fedora's debuginfod server.

--- a/default/agents/skills/diagnose-crash/SKILL.md
+++ b/default/agents/skills/diagnose-crash/SKILL.md
@@ -53,13 +53,13 @@
 
 ## Symbolize when you can
 
-This is Arch, which runs a public debuginfod server:
+This is Fedora, which runs a public debuginfod server:
 
 ```bash
 core=$(mktemp -t crash-XXXXXX.core)
 trap 'rm -f "$core"' EXIT
 coredumpctl dump <pid> --output="$core"
-DEBUGINFOD_URLS="https://debuginfod.archlinux.org" \
+DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/" \
   gdb -q <executable> "$core" \
   -batch -ex 'set debuginfod enabled on' -ex 'bt'
 ```
````

`patches/0008-omarchy-launch-about-fastfetch-config.patch` (sha256 `0c555fb0086a90cbebf273e9cf4081e7c03148d179c4114b7dcfd7b596d7d5a1`):

```diff
Use Tinkero's relocated fastfetch config unless the user has their own.

--- a/bin/omarchy-launch-about
+++ b/bin/omarchy-launch-about
@@ -17,6 +17,12 @@
   [[ -f $HOME/.config/fastfetch/config.jsonc ]]
 }
 
+# Tinkero installs no /etc/fastfetch/config.jsonc (it would change fastfetch for
+# every session on the host); the shipped config lives under /usr/share/tinkero.
+fastfetch_args() {
+  custom_fastfetch_config || echo "-c /usr/share/tinkero/fastfetch/config.jsonc"
+}
+
 # wc -L counts display columns only in a UTF-8 locale. A session that never set
 # one counts every box-drawing and Nerd Font glyph in the About layout as
 # nothing, which measures the content narrower than it renders.
@@ -101,7 +107,7 @@
   # The guard character keeps command substitution from eating the trailing
   # break line, which provides the bottom padding row.
   local modules module_w module_h
-  modules=$(fastfetch --logo none | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'; printf X)
+  modules=$(fastfetch $(fastfetch_args) --logo none | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g'; printf X)
   modules=${modules%X}
   module_w=$(printf '%s' "$modules" | display_columns)
   module_h=$(printf '%s' "$modules" | wc -l)
@@ -158,7 +164,7 @@
     size=$(stty size)
     logo_stamp=$(stat -c %Y "$LOGO_FILE" 2>/dev/null)
     clear
-    fastfetch
+    fastfetch $(fastfetch_args)
     # A second pass picks up a fit that could not measure the window the first
     # time. Beyond that, a window that will not settle would be fitted again on
     # every repaint.
```

`patches/0009-sshd-firewalld.patch` (sha256 `da48b51b469b3e5fe56b8cb562311cd9fa6401b5a9bbb178448c68eda301268b`):

```diff
Open and close the SSH port with firewalld instead of ufw.

--- a/bin/omarchy-setup-security-sshd
+++ b/bin/omarchy-setup-security-sshd
@@ -16,7 +16,7 @@
   -h | --help)
     echo "Usage: omarchy-setup-security-sshd [--key=<public-key>]"
     echo
-    echo "Sets up the OpenSSH server, opens the SSH port in the UFW firewall,"
+    echo "Sets up the OpenSSH server, opens the SSH port in firewalld,"
     echo "and authorizes an SSH key (from GitHub, pasted, or passed via --key)."
     exit 0
     ;;
@@ -34,14 +34,14 @@
 }
 
 open_firewall() {
-  if omarchy-cmd-missing ufw; then
-    echo "UFW is not installed; skipping firewall rule."
+  if omarchy-cmd-missing firewall-cmd; then
+    echo "firewalld is not installed; skipping firewall rule."
     return
   fi
 
-  echo "Opening the SSH port in the firewall (rate limited against brute force)..."
-  sudo ufw limit 22/tcp comment "omarchy-sshd" >/dev/null
-  sudo ufw reload >/dev/null
+  echo "Opening the SSH port in the firewall..."
+  sudo firewall-cmd --permanent --add-service=ssh >/dev/null
+  sudo firewall-cmd --reload >/dev/null
 }
 
 valid_key() {
--- a/bin/omarchy-remove-security-sshd
+++ b/bin/omarchy-remove-security-sshd
@@ -12,10 +12,10 @@
 echo "Stopping and disabling the OpenSSH server..."
 sudo systemctl disable --now sshd.service 2>/dev/null || true
 
-if omarchy-cmd-present ufw; then
+if omarchy-cmd-present firewall-cmd; then
   echo "Closing the SSH port in the firewall..."
-  sudo ufw --force delete limit 22/tcp >/dev/null 2>&1 || true
-  sudo ufw reload >/dev/null
+  sudo firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1 || true
+  sudo firewall-cmd --reload >/dev/null
 fi
 
 if [[ -s $AUTHORIZED_KEYS ]]; then
```

- [ ] **Step 2: Write the series**

Replace `patches/series` with (patch 0010 is Task 5's, listed now so the order is final):

```
0001-omarchy-version-from-rpm.patch
0002-omarchy-debug-rpm-inventory.patch
0003-omarchy-reinstall-configs-provision-reset.patch
0004-omarchy-remove-launcher-entry-rpm.patch
0005-omarchy-remove-dev-env-pkg-drop.patch
0006-omarchy-skill-host-guide.patch
0007-diagnose-crash-fedora-debuginfod.patch
0008-omarchy-launch-about-fastfetch-config.patch
0009-sshd-firewalld.patch
0010-menu-package-guards-rpm.patch
```

Until Task 5 creates 0010, `build/assemble` will fail on the missing file; that is expected for this one commit.

- [ ] **Step 3: Verify the checksums**

Run: `cd patches && sha256sum 0002-* 0003-* 0004-* 0005-* 0006-* 0007-* 0008-* 0009-*`
Expected: exactly the eight values given above.

- [ ] **Step 4: Verify they apply, in order, to the real tree**

```bash
t=$(mktemp -d); tar -xzf .cache/omarchy-c668141e9c42b13c80c9ca4ea108e11708c5e8a5.tar.gz -C "$t" --strip-components=1
for p in 0001 0002 0003 0004 0005 0006 0007 0008 0009; do (cd "$t" && git apply -p1 "$OLDPWD"/patches/$p-*.patch) && echo "$p ok"; done
grep -c pacman "$t/bin/omarchy-debug" "$t/bin/omarchy-remove-launcher-entry" "$t/bin/omarchy-remove-dev-env"; rm -rf "$t"
```

Expected: nine `ok` lines, then `0` for each of the three files.

- [ ] **Step 5: Commit**

```bash
git add patches
git commit -m "build: patches 0002-0009 (inventory, reset, launcher removal, dev env, skills, About, sshd firewalld)"
```

---

### Task 5: The menu guard patch and its test

`shell/plugins/menu/MenuModel.js` builds one bash prelude per guard batch that shadows `omarchy-pkg-present` and `-missing` with functions answering from a `pacman` snapshot. The patch keeps the shadowing (one snapshot, not one rpm call per guard) but fills the set from `rpm -qa` and `flatpak list`, translated through the name map. The JS is a string literal with nested escaping, so the test evaluates it with `node` and runs the emitted bash against stubs.

**Files:**
- Create: `patches/0010-menu-package-guards-rpm.patch`, `tests/test-menu-guards.sh`
- Modify: `.github/workflows/ci.yml` (add `nodejs` to the Tools step)

- [ ] **Step 1: Write the failing test**

Create `tests/test-menu-guards.sh`:

```bash
#!/bin/bash
# The bash prelude that the patched MenuModel.js emits for the menu's package guards,
# evaluated through node (CI installs nodejs; locally the test is skipped without it).
source "$(dirname "$0")/lib.sh"
if ! command -v node >/dev/null; then ok "skipped: node is not installed"; finish; exit; fi
d=$(mktmp); mkdir -p "$d/bin"
# extract guardHelpers() from the patched file in the assembled payload, or from the patch itself
src=$ROOT/.cache/payload/usr/share/omarchy/shell/plugins/menu/MenuModel.js
if [[ ! -f $src ]]; then
  # no payload: take the new lines straight from the patch
  sed -n '/^+  \/\/ Tinkero: one rpm/,/^+    + .__omarchy_pkg_has/p' "$ROOT/patches/0010-menu-package-guards-rpm.patch" | sed 's/^+//' > "$d/body.js"
else
  sed -n '/^function guardHelpers() {/,/^}/p' "$src" | sed '1d;$d' > "$d/body.js"
fi
{ echo "function f(){"; cat "$d/body.js"; echo "}"; echo "process.stdout.write(f())"; } > "$d/gen.js"
node "$d/gen.js" > "$d/prelude.sh" || { not_ok "prelude generates"; finish; exit; }
ok "prelude generates from the JS"
printf '#!/bin/bash\nprintf "foot\\nhtop\\n"\n' > "$d/bin/rpm"
printf '#!/bin/bash\nprintf "org.signal.Signal\\n"\n' > "$d/bin/flatpak"
chmod +x "$d/bin"/*
printf '# c\nfoot\tdnf\tfoot\nsignal-desktop\tflatpak\torg.signal.Signal\nvim\tdnf\tvim-enhanced\nopenclaw\tnone\t-\n' > "$d/map"
sed "s|/usr/share/tinkero/pkgmap.tsv|$d/map|" "$d/prelude.sh" > "$d/p.sh"
q() { PATH=$d/bin:$PATH bash -c "source '$d/p.sh'; __omarchy_pkg_has $1"; }
q foot;           assert_eq "$?" 0 "dnf-mapped installed name is present"
q signal-desktop; assert_eq "$?" 0 "flatpak-mapped installed name is present"
q vim;            assert_eq "$?" 1 "dnf-mapped but not installed is absent"
q openclaw;       assert_eq "$?" 1 "kind none is absent"
q nope;           assert_eq "$?" 1 "unmapped is absent"
assert_eq "$(grep -c pacman "$d/prelude.sh")" 0 "no pacman left in the prelude"
rm -rf "$d"; finish
```

Run: `bash tests/test-menu-guards.sh`
Expected: `not ok - prelude generates` (no patch yet), or `ok - skipped` if `node` is missing (then install nothing; CI runs it).

- [ ] **Step 2: Write the patch**

`patches/0010-menu-package-guards-rpm.patch` (sha256 `a7216406e5a0c12e5b0e40425a64ee47684dcd5caacc2d6eb6e731d9959f8a8c`):

```diff
Evaluate the menu's package guards from rpm and flatpak through the Tinkero name map.

Upstream builds one pacman snapshot per guard batch and defines bash functions
that shadow omarchy-pkg-present and omarchy-pkg-missing. The batch keeps the
shadowing (one snapshot, not one rpm call per guard) but fills the set from
rpm and flatpak, translated back to the Arch names the guards use.

--- a/shell/plugins/menu/MenuModel.js
+++ b/shell/plugins/menu/MenuModel.js
@@ -396,26 +396,20 @@
 // them everywhere, including for no arguments at all (present is true of
 // nothing, missing is not).
 //
-// `pacman -Q` resolves a name through what installed packages provide, not
-// just what they are called -- with gvim installed it reports `vim` as
-// present -- so the set has to carry provides too, or `install.editor.vim`
-// comes back and offers to install what is already there. A version
-// constraint (`bash>=1`) is not a name any set can answer, so it goes to
-// pacman itself; no shipped guard writes one.
-//
-// `pacman -Qi` wraps a long list across continuation lines whenever COLUMNS
-// is set in the environment, which a login shell may well have done, so the
-// parser follows the indented lines rather than reading the first one and
-// dropping half of what is installed.
+// Tinkero: the guards keep using upstream's Arch package names. The set is
+// filled from one rpm snapshot and one flatpak snapshot, translated through
+// the name map, so a guard is true exactly when omarchy-pkg-present would be.
 function guardHelpers() {
-  return 'declare -A __omarchy_pkgs=()\n'
-    + 'mapfile -t __omarchy_pkg_names < <({ pacman -Qq; LC_ALL=C pacman -Qi'
-    + " | awk '/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, \"\") }"
-    + ' provides && $0 != "None" { n = split($0, p, " ");'
-    + ' for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }\'; } 2>/dev/null)\n'
-    + 'for __omarchy_pkg in "${__omarchy_pkg_names[@]}"; do __omarchy_pkgs[$__omarchy_pkg]=1; done\n'
-    + '__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; '
-    + '[[ $1 == *[\\<\\>=]* ]] && { pacman -Q "$1" &>/dev/null; return; }; return 1; }\n'
+  // Tinkero: one rpm and one flatpak snapshot, mapped back to the Arch names the
+  // guards use through /usr/share/tinkero/pkgmap.tsv (arch<TAB>kind<TAB>target).
+  return 'declare -A __omarchy_pkgs=() __tinkero_rpm=() __tinkero_flatpak=()\n'
+    + 'while IFS= read -r __p; do __tinkero_rpm[$__p]=1; done < <(rpm -qa --qf "%{NAME}\\n" 2>/dev/null)\n'
+    + 'while IFS= read -r __p; do __tinkero_flatpak[$__p]=1; done < <(flatpak list --columns=application 2>/dev/null)\n'
+    + 'while IFS=$\'\\t\' read -r __a __k __t; do [[ -z $__a || $__a == \\#* ]] && continue; '
+    + 'case $__k in dnf) [[ -n ${__tinkero_rpm[$__t]-} ]] && __omarchy_pkgs[$__a]=1 ;; '
+    + 'flatpak) [[ -n ${__tinkero_flatpak[$__t]-} ]] && __omarchy_pkgs[$__a]=1 ;; esac; '
+    + 'done < /usr/share/tinkero/pkgmap.tsv\n'
+    + '__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]]; }\n'
     + 'omarchy-pkg-present() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 1; done; return 0; }\n'
     + 'omarchy-pkg-missing() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 0; done; return 1; }\n'
     + 'omarchy-cmd-present() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 1; done; return 0; }\n'
```

- [ ] **Step 3: Verify and run**

Run: `sha256sum patches/0010-*` (must match), then `./dev payload` (all ten patches apply; expect `assembled 364 commands` once Task 6's drop list is in, `365` before it), then `bash tests/test-menu-guards.sh`.
Expected: `1..7`, no `not ok`; the assertion "no pacman left in the prelude" passes.

- [ ] **Step 4: CI installs node**

In `.github/workflows/ci.yml`, change the Tools step's package list to end with `make nodejs`, and add `ci/gate-name-map` after `ci/gate-single-copy` and `distro/fedora/lib/pkg.sh` after `distro/fedora/replacements/*` in the ShellCheck file list.

- [ ] **Step 5: Commit**

```bash
git add patches/0010-menu-package-guards-rpm.patch tests/test-menu-guards.sh .github/workflows/ci.yml
git commit -m "build: menu package guards answer from rpm and flatpak through the name map"
```

---

### Task 6: Drop list, manifest, baselines, CI

**Files:**
- Replace: `build/drop.list`
- Modify: `tinkero.spec.in` (one line)
- Regenerate: `ci/allow/arch-leak.allow`, `ci/allow/dropped-refs.allow`

- [ ] **Step 1: The drop list**

Replace `build/drop.list` with the following. Compared with plan 2A's: `bin/omarchy-install-openclaw-cli` is gone (kept, per the recorded decision) and the last block is new.

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

# --- plan 2B decisions (docs/superpowers/plans/2026-09-17-phase-2-roadmap.md)
# Docker is deferred, not Arch-specific: re-enabling means removing the docker lines above and
# here, adding a name-map row for the Docker package, and re-adding the Super+Shift+D binding.
bin/omarchy-launch-docker-tui
# creates files under the dropped migrations/ directory
bin/omarchy-dev-add-migration
applications/Docker.desktop
# a Hidden=true mask for an Arch-only autostart entry; inert on Fedora
config/autostart/limine-snapper-notify.desktop
```

- [ ] **Step 2: The manifest**

In `tinkero.spec.in`, change the line
`Requires:       power-profiles-daemon bluez NetworkManager udiskie socat inotify-tools jq gum git-core`
to
`Requires:       ppd-service bluez NetworkManager udiskie socat inotify-tools jq gum git-core fcitx5`

Run: `bash tests/test-render-spec.sh`. Expected: `1..16`, no `not ok`.

- [ ] **Step 3: Regenerate the baselines and read them**

Run: `./dev baseline`
Expected: `assembled 364 commands`, `WROTE: ci/allow/arch-leak.allow (8 entries)`, `WROTE: ci/allow/dropped-refs.allow (43 entries)`.

The eight arch-leak entries must be exactly: `usr/bin/omarchy-default-agent`, `usr/bin/omarchy-install-openclaw-cli`, `usr/bin/omarchy-setup-security-fingerprint`, `usr/share/omarchy/default/agents/skills/omarchy/hooks.md`, `usr/share/omarchy/default/fonts/omarchy/README.md`, `usr/share/omarchy/default/hypr/input.lua`, `usr/share/omarchy/default/omarchy/launcher.hides`, `usr/share/omarchy/default/omarchy/omarchy-menu.jsonc`. Anything else means a patch or replacement did not take; stop and report. The 43 dropped-refs entries are the menu (plan 2C), `applications.lua` and the two comment-only `env-bootstrap` lines, `omarchy-bar`, `omarchy-provision-user` (plan 2E), the zram config and `mise-work.sh` comments.

- [ ] **Step 4: Annotate the permanent entries**

Trailing comments are allowed on allowlist lines and survive the gate (they do not survive the next `./dev baseline`; that is fine, they are documentation). Append `   # comment only, permanent` to these arch-leak lines: `omarchy-default-agent`, `omarchy-install-openclaw-cli`, `hooks.md`, `fonts/omarchy/README.md`, `hypr/input.lua`, `launcher.hides`; append `   # plan 2F` to the fingerprint line and `   # learn.arch row; plan 2C` to the menu line. In dropped-refs, append `   # comment only, permanent` to the `omarchy-bar`, both `env-bootstrap`, the `90-omarchy.conf` and the `mise-work.sh` lines, `   # gated binding; returns with Docker` to the `applications.lua` line, and `   # plan 2E` to the `omarchy-provision-user` line.

- [ ] **Step 5: Everything green, then push**

Run: `./dev check` (expect `1..30 1..9 1..33 1..4 1..7 1..16 1..30`, no `not ok`) and `./dev gates` (four `PASS` lines).

```bash
git add build/drop.list tinkero.spec.in ci/allow
git commit -m "build: 2B drop-list decisions, manifest corrections, baselines after the patches and replacements"
git push origin task/425e16e7
gh run watch "$(gh run list --branch task/425e16e7 --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

Expected: the CI run is green, including the ShellCheck step over the new scripts and the `test-menu-guards.sh` run with `node`. If ShellCheck objects to a replacement, fix the script (not the check) and record the change under Deviations.

---

## Deviations

(empty at the time of writing)

## What this plan deliberately leaves out

- `omarchy-apply-lock`, `tinkero-pam-sync`, the fingerprint pair, the dconf profile and the session units: plan 2F.
- The menu rewrite that clears the 43 dropped-refs entries and the `learn.arch` arch-leak entry: plan 2C.
- `tinkero-provision` and `host.md` (which documents the name map for the agent): plan 2E.
- A `mise` kind in the name map, if OpenClaw or other CLIs turn out to install that way: roadmap research item.
