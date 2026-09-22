# Phase 1: The COPR Package Set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Green builds in the COPR `dromero/tinkero` (chroot `fedora-44-x86_64`) for the 25 packages Fedora lacks and Tinkero needs, from specs this repo owns, submitted in dependency order by a tool and a workflow that will serve every later bump.

**Architecture:** Fork Omedora's packaging (25 spec files with sha256-pinned sources, an SRPM generator that fetches, verifies and vendors in COPR's networked step, and a dependency order) into `distro/fedora/specs/`, byte-identical except for the three recorded changes. `.copr/Makefile` learns to dispatch on the `spec=` argument COPR passes: the `tinkero` RPM keeps its existing path, every other spec goes to `srpm.sh`. `bin/tinkero-copr` registers each package as an SCM/`make_srpm` source pointing at this repo and builds them one at a time, because the Hyprland stack needs each `-devel` published before the next package builds. A manual `copr-build` workflow runs that tool with the COPR token held as a repository secret, so builds never depend on a workstation. CI lints every spec and builds one real SRPM on every push.

**Tech Stack:** RPM spec files, `rpmbuild -bs`, `spectool`, `cargo vendor` and `zig` (inside `srpm.sh`, in COPR only), `copr-cli`, GitHub Actions. Locally: bash and the existing test harness; ShellCheck is installed on this workstation. No `rpm-build`, `rpmlint`, `make` or `copr-cli` here: those steps run in CI or in COPR.

**Spec:** `docs/superpowers/specs/2026-09-17-tinkero-design.md` (sections 4.1, 4.11, 6, 7 "Phase 1"). Research: `docs/research/omarchy-research.md` section 3.3 (package availability). Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`.

## Global Constraints

- COPR project `dromero/tinkero`, chroot `fedora-44-x86_64` only. Its `auto_prune` cannot be disabled (spec 4.1); rollback is the release archive (4.11), not this plan's concern.
- The package set is exactly the 25 names in `distro/fedora/specs/build-order.txt`; the font package is named `tinkero-nerd-fonts` (the `tinkero` RPM already requires it by that name).
- Imported files are byte-identical to Omedora's at commit `9672f96fd49addfcc953a7c4ac3b7c9a5b45bca5` except: `tinkero-nerd-fonts.spec` (renamed and reworded, content given), `uwsm.spec` (two `Recommends:` lines removed), `srpm.sh` (self-source mode removed, header rewritten). A checksum listing of all 52 files is the acceptance test of the import.
- Every remote source keeps its sha256 pin; `srpm.sh` aborts on a mismatch. No package is built with network access in the mock phase.
- No new `Recommends:` on `wofi`, `nwg-panel`, `playerctl`, `whiptail` or `newt` (the second bar and launcher Phase 0 found pulled in).
- Builds are submitted only through `bin/tinkero-copr` (or the workflow that runs it), one package at a time, waiting for each. Triggering builds publishes to the user's COPR: the controller confirms with the user before the first trigger.
- Pushing branch `task/425e16e7` is allowed; never master; no PR; no branch changes. Attribution lines on every commit per the harness. No em dashes in Tinkero's own prose; text imported from Omedora (spec comments, `srpm.sh` comments) is kept as it is.
- Scripts start with `#!/bin/bash` and `set -euo pipefail`; tests use `tests/lib.sh`; ShellCheck clean with `-x -e SC1090,SC1091`.

## File Structure

| File | Responsibility |
|---|---|
| `distro/fedora/specs/<name>.spec`, `<name>.spec.sources` | the 25 specs and their sha256 pins |
| `distro/fedora/specs/macros.hyprland`, `herdr-libvt-only.patch` | local sources two specs need |
| `distro/fedora/specs/srpm.sh` | COPR's networked SRPM step for one spec |
| `distro/fedora/specs/build-order.txt` | dependency order (data) |
| `distro/fedora/specs/README.md` | provenance, layout, how to bump |
| `.copr/Makefile` | dispatch: `tinkero.spec` versus a package spec |
| `bin/tinkero-copr` | register and build in order (`order`, `register`, `build`, `all`) |
| `.github/workflows/copr-build.yml` | manual workflow running `tinkero-copr` with the `COPR_CONFIG` secret |
| `.github/workflows/ci.yml` | gains: `rpmdevtools`, spec parse and lint, one SRPM smoke build, ShellCheck over the new scripts |
| `tests/test-specs.sh`, `tests/test-copr.sh` | static checks on the set; the tool against a stub `copr-cli` |

Interfaces later plans rely on: `bin/tinkero-copr build <name>` (Phase 3's workflows call it after a bump); `distro/fedora/specs/build-order.txt` (the bump checklist reads it); the `copr-build` workflow's inputs `packages` and `command`.

---

### Task 1: Import the package set

**Files:**
- Create: 52 files under `distro/fedora/specs/` (25 `.spec`, 25 `.spec.sources`, `macros.hyprland`, `herdr-libvt-only.patch`), `distro/fedora/specs/build-order.txt`, `distro/fedora/specs/README.md`, `tests/test-specs.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test-specs.sh`:

```bash
#!/bin/bash
# Static checks on the COPR package set under distro/fedora/specs/ (no rpm tooling needed).
source "$(dirname "$0")/lib.sh"
D=$ROOT/distro/fedora/specs
mapfile -t order < <(grep -vE '^\s*(#|$)' "$D/build-order.txt")
assert_eq "${#order[@]}" 25 "build-order.txt lists 25 packages"
specs=("$D"/*.spec); assert_eq "${#specs[@]}" 25 "there are 25 spec files"
for s in "${specs[@]}"; do
  n=$(basename "$s" .spec)
  name=$(grep -m1 -E '^Name:' "$s" | awk '{print $2}')
  assert_eq "$name" "$n" "$n: Name matches the file name"
  printf '%s\n' "${order[@]}" | grep -qx "$n" || not_ok "$n is not in build-order.txt"
  assert_file "$s.sources" "$n: has a .sources pin file"
  grep -qE '^Release:\s+[0-9]+.*%\{\?dist\}' "$s" || not_ok "$n: Release must carry %{?dist}"
  # every remote source (not the vendor/zig-cache tarballs srpm.sh generates) has a sha256 pin:
  # names use spec macros, so compare counts, and require the pin lines to be well-formed
  urls=$(grep -E '^Source[0-9]*:' "$s" | grep -E '://|%\{[a-z_]*url\}' | grep -vcE 'vendor\.tar|zig-cache' || true)
  pins=$(grep -cvE '^\s*(#|$)' "$s.sources" || true)
  assert_eq "$pins" "$urls" "$n: one sha256 pin per remote source"
  bad=$(grep -vE '^\s*(#|$)' "$s.sources" | grep -vE '^[0-9a-f]{64}  \S+$' || true)
  [[ -z $bad ]] || not_ok "$n: malformed pin line" "$bad"
  # no dependency on the project we forked from, and no bar or launcher recommended in
  hits=$(grep -nE '^(Requires|BuildRequires|Recommends|Suggests|Provides|Obsoletes|Conflicts):.*(omedora|wofi|nwg-panel|playerctl|whiptail|newt)' "$s" || true)
  [[ -z $hits ]] || not_ok "$n: forbidden dependency line" "$hits"
done
ok "per-spec checks ran"
assert_file "$D/srpm.sh" "srpm.sh present"; assert_file "$D/macros.hyprland" "hyprland macros present"
assert_file "$D/herdr-libvt-only.patch" "herdr patch present"
if grep -q "omedora-self" "$D/srpm.sh"; then not_ok "srpm.sh still has the self-source mode"; else ok "srpm.sh has no self-source mode"; fi
finish
```

Run: `bash tests/test-specs.sh`. Expected: fails immediately (no `build-order.txt`).

- [ ] **Step 2: Fetch Omedora's packaging at the pinned commit**

```bash
t=$(mktemp -d)
git clone -q --depth 1 --branch omedora-4 --filter=blob:none --sparse https://github.com/AndrewGaspar/omedora.git "$t/omedora"
git -C "$t/omedora" sparse-checkout set omedora/packaging/copr >/dev/null
git -C "$t/omedora" rev-parse HEAD
```

Expected: `9672f96fd49addfcc953a7c4ac3b7c9a5b45bca5`. If the branch has moved past that commit, fetch it explicitly: `git -C "$t/omedora" fetch --depth 1 origin 9672f96fd49addfcc953a7c4ac3b7c9a5b45bca5 && git -C "$t/omedora" checkout -q 9672f96fd49addfcc953a7c4ac3b7c9a5b45bca5`.

- [ ] **Step 3: Copy the 24 unchanged spec pairs and the two local sources**

```bash
O=$t/omedora/omedora/packaging/copr
mkdir -p distro/fedora/specs
for s in quickshell mise tensaku ttfx herdr gpu-screen-recorder voxtype hyprland-preview-share-picker \
         glaze hyprland-protocols hyprutils hyprwayland-scanner hyprlang hyprgraphics hyprwire hyprcursor \
         aquamarine hyprtoolkit hyprland hyprland-guiutils hyprpicker hyprsunset xdg-desktop-portal-hyprland uwsm; do
  cp "$O/$s.spec" "$O/$s.spec.sources" distro/fedora/specs/
done
cp "$O/macros.hyprland" "$O/herdr-libvt-only.patch" distro/fedora/specs/
cp "$O/omedora-nerd-fonts.spec.sources" distro/fedora/specs/tinkero-nerd-fonts.spec.sources
sed -i '/^Recommends:     wofi$/d; /^Recommends:     \/usr\/bin\/whiptail$/d' distro/fedora/specs/uwsm.spec
```

- [ ] **Step 4: Write the font spec**

Create `distro/fedora/specs/tinkero-nerd-fonts.spec` (Omedora's `omedora-nerd-fonts.spec` with the package renamed, five wording lines changed):

```spec
# tinkero-nerd-fonts.spec: the patched Nerd Fonts the Tinkero shell needs (forked from omedora-nerd-fonts.spec).
#
# Fedora ships plain JetBrains Mono and Cascadia Code, but NOT the Nerd
# Font-patched variants that carry the icon glyphs waybar/terminal/prompt use.
# This packages the upstream patched archives as a normal RPM, so they land in
# the system font dir, fontconfig auto-indexes them, and `dnf remove` cleans
# them up — replacing the per-user source installer.
#
# noarch: fonts are just data files, identical on every CPU architecture.

Name:           tinkero-nerd-fonts
Version:        3.4.0
Release:        1%{?dist}
Summary:        CascadiaCode + JetBrainsMono Nerd Fonts for Tinkero

License:        MIT and OFL-1.1
URL:            https://github.com/ryanoasis/nerd-fonts

# Two upstream archives — one per font family. spectool -g downloads both.
Source0:        %{url}/releases/download/v%{version}/CascadiaCode.tar.xz
Source1:        %{url}/releases/download/v%{version}/JetBrainsMono.tar.xz

BuildArch:      noarch

# fontconfig owns the font cache + provides the file trigger that reindexes
# /usr/share/fonts when our files land.
Requires:       fontconfig

%description
The Nerd Font-patched CascadiaCode (CaskaydiaMono/Cove) and JetBrainsMono
families, providing the icon glyphs Tinkero's shell and terminal
prompt render. Bundles ryanoasis/nerd-fonts release archives.

%prep
# -c -T makes an empty build dir; we unpack the two .tar.xz archives by hand
# (they have no common top-level directory).
%setup -q -c -T
mkdir -p cascadia jetbrains
tar -xJf %{SOURCE0} -C cascadia
tar -xJf %{SOURCE1} -C jetbrains

%build
# Nothing to compile.

%install
fontdir=%{buildroot}%{_datadir}/fonts/tinkero-nerd-fonts
install -d "$fontdir"
# Ship the actual font files only (skip the archives' READMEs/licenses here;
# the license text is covered by the License: field).
find cascadia jetbrains \( -name '*.ttf' -o -name '*.otf' \) \
    -exec install -m 0644 -t "$fontdir" {} +

%files
%dir %{_datadir}/fonts/tinkero-nerd-fonts
%{_datadir}/fonts/tinkero-nerd-fonts/*

%changelog
* Fri May 29 2026 Tinkero <noreply@tinkero.invalid> - 3.4.0-1
- Package CascadiaCode + JetBrainsMono Nerd Fonts (ryanoasis v3.4.0).
```

- [ ] **Step 5: Write the order and the README**

Create `distro/fedora/specs/build-order.txt`:

```
# COPR build order for the Tinkero package set: one package per line, top to bottom.
# Each package's -devel must be published in the COPR before the next one builds, so
# bin/tinkero-copr submits them one at a time and waits. Lines starting with # are ignored.
# The Hyprland stack has deep intra-stack BuildRequires; the rest is order-free but
# listed first because it is quick and independent.
tinkero-nerd-fonts
mise
quickshell
uwsm
gpu-screen-recorder
hyprland-preview-share-picker
tensaku
ttfx
herdr
voxtype
# the Hyprland stack, in dependency order
glaze
hyprland-protocols
hyprutils
hyprwayland-scanner
hyprlang
hyprgraphics
hyprwire
hyprcursor
aquamarine
hyprtoolkit
hyprland
hyprland-guiutils
hyprpicker
hyprsunset
xdg-desktop-portal-hyprland
```

Create `distro/fedora/specs/README.md`:

```markdown
# The Tinkero package set

RPM specs for what Fedora lacks and Tinkero needs (design spec, section 4.1), built in
the COPR `dromero/tinkero` for `fedora-44-x86_64`.

## Provenance

Forked on 2026-09-22 from Omedora's packaging, `AndrewGaspar/omedora` branch `omedora-4`,
commit `9672f96fd49addfcc953a7c4ac3b7c9a5b45bca5`, directory `omedora/packaging/copr/`
(MIT licensed; see `../../../LICENSE` for Tinkero's own MIT terms). Changes at the fork:
`omedora-nerd-fonts` became `tinkero-nerd-fonts`; `uwsm` no longer recommends `wofi` or
`whiptail`; `srpm.sh` lost Omedora's self-source mode. The 24 other specs are byte-identical to
Omedora's; their comments still say "omedora" where they describe history.

## Layout

- `<name>.spec` and `<name>.spec.sources`: the spec and the sha256 pins of its remote
  sources (`sha256sum -c` format). `tests/test-specs.sh` checks that every remote source
  has a pin and that the file is well-formed.
- `srpm.sh`: what COPR runs (through `.copr/Makefile`) in its networked SRPM step:
  fetch the sources with `spectool`, verify them against the pins, vendor Rust crates
  (`*-vendor.tar.zst`) or Zig packages (`*-zig-cache.tar.zst`), then `rpmbuild -bs`.
- `build-order.txt`: the order `bin/tinkero-copr` submits builds in. The Hyprland stack
  has deep intra-stack BuildRequires; each `-devel` must be published before the next
  package builds.
- `macros.hyprland`, `herdr-libvt-only.patch`: local sources two specs need.

## Bumping a package

1. Change `Version:` (and any pinned commit macro) in the spec; add a changelog entry.
2. Download the new source tarball(s) with `spectool -g -R <spec>` into a scratch
   directory, compute `sha256sum`, and replace the lines in `<name>.spec.sources`.
3. `./dev check` (the static checks) and push: CI lints the spec and builds one SRPM.
4. Build on COPR: the `copr-build` workflow, or `bin/tinkero-copr build <name>` locally
   with a token in `~/.config/copr`. Dependents of a bumped library need rebuilding too.
```

- [ ] **Step 6: Verify the import byte for byte**

Run, from the repo root: `(cd distro/fedora/specs && sha256sum *.spec *.sources macros.hyprland herdr-libvt-only.patch | sort -k2) | diff - <(cat <<'SUMS'` followed by the listing below and `SUMS`, `)`; it must print nothing.

```
5bd6fe3261dac281e87ed4677836a4c835a085fd860add536f447862bde9f99a  aquamarine.spec
8159d80b4d8e99e0ece225aa3aedbd847650c52ddf9116ea3053c019ad7fa182  aquamarine.spec.sources
3ce706c84eb6dae59a72f9fdadc2df963cffff80279301eec96ba38d38ab4e8a  glaze.spec
e95c683eac8d10c12701cd77f8858ba8d3a7aa0ac26e1e8c5c494c7932fcf7f0  glaze.spec.sources
2ebf2e1425f3e92cfd04aeb95cb9daba75b859c683f40a425f59124fab09d198  gpu-screen-recorder.spec
bd106892fbaa31ddcdf168852150f38039502bdce427244fbec6504478f6f3e5  gpu-screen-recorder.spec.sources
4ff67dff3a6be918109bc0b3606c957fb820a7744ae69d97bb07d2f17f0de9ac  herdr-libvt-only.patch
f11fe7fee4b94143d74318a36ba86ff5877e7baa258be8b16d3944f1b4a84dc3  herdr.spec
c7f0131b942aca73c1a412dca94d07574f681702ead0fa22beef9bd0feab8552  herdr.spec.sources
5b70b9c0f647c34b1b233da53fe75b3935933f99e52e4fdc635bd77311fa05a1  hyprcursor.spec
d9b8fde57879f235c09449f153a691c6a4f90a640b05d716de7512027d34b0d8  hyprcursor.spec.sources
271e859211e5ed0741953081ca50a8b1fc4fc8c49d909b9f0c6c39c3c75aaaf5  hyprgraphics.spec
210e8978d1f82a1b6936c447f2521fc91f90fb76e51cf2e15e7bffcb574bd30c  hyprgraphics.spec.sources
3f8f71973698d0bb46e8b89bfc998a9b6b702bbdceae8596c13a9f5a2c9e42fa  hyprland-guiutils.spec
e3fe17568bc071f9ba1d2f07b9b5c082f7317dc9de7638f630664f0436a0d95a  hyprland-guiutils.spec.sources
e03f1f4e3edef2f5aa360b824884b0c77f1ec1193051633f7beebc90a47ca778  hyprland-preview-share-picker.spec
6df2614a215d844a3251676fe2474cfc507b671b4c3d7d5da824e8765fa94356  hyprland-preview-share-picker.spec.sources
1f2307f64db21cc1f9e8375970d17a9aa47a5647c19cfaf571583cd2f1419a90  hyprland-protocols.spec
48bc33b44e164ef9e074c47e8c7a9287a83fe33836f70ea5931d0952ccf8475c  hyprland-protocols.spec.sources
bc07a65cc2dd50e06f09e0f8f2ac031649d3fe9c28c24c216b06977adccd8774  hyprland.spec
d7d935eb02c289e32b9ec33e4575e007dd727dcc5acbb90ef7359726e95858e4  hyprland.spec.sources
53debc2c7a826277c62f3ec342fcd26fe6c6a5b7b2ce72d766567094cdbbbc20  hyprlang.spec
a6d7ea7efbad5d6435c2298ea055494e03bb5db0304e595e7f31555c7a99e1c4  hyprlang.spec.sources
0441ad26e5114b550957f5c06e05166f1634aa58686520f2c5206c4a36466230  hyprpicker.spec
5be32ab7166db85ac17ad2c1a1e29315fbb55946c6da5e49cd1eab5406555dee  hyprpicker.spec.sources
3cafaae8d6460110f461f492249a012406b653f0b6f2effda4d83d7a4075eb71  hyprsunset.spec
508e526ac90f6bec82075d91f1b3ad2d85f23b5b5467cdd755e4cb87bac50c10  hyprsunset.spec.sources
ea1cd455cfc8777d797bb237fe89e6af2443a6d8c073dfe44160c3fea4ac1f9f  hyprtoolkit.spec
173eee0ce476b4daccd1347481aab1703dcc3370ab39255d96eb99bf05e10fa4  hyprtoolkit.spec.sources
152ca171a6b72191e19bdfa2cf811e6b796153d1c839babdb188e19e7d3deb39  hyprutils.spec
94ecb918af3e572ab3c27ee63ba55692c3a3f39c9dc1a3e40ada6577c054f7ad  hyprutils.spec.sources
4b50934e1a8bdf5f358dac0c2077f528f799c45fdd445e2cef09f96d67bc6195  hyprwayland-scanner.spec
5f26c1e827141f4e608ca8a3890636aa9b56fb27c53cfde00fa2e3880fee8ff0  hyprwayland-scanner.spec.sources
2f4df8d1fd53a686fa2968535f3447f64ac331caa786822158169972347cdc9a  hyprwire.spec
05db5999f1fb906a40622236ef8fe39e0b316e5ad51cd1ccfa4810b85d58e03a  hyprwire.spec.sources
89560caa2b64491cce4eba94b6e9c8c038dde4eb386e2727191ae455659e62d8  macros.hyprland
7debbea99b8b5da4c2afb3090d62690eeac16e1095e694b78334bd2e8ba31ff8  mise.spec
6d8488202fe7bf920736516ea3376b46718c5ba77c154dcb7b3fd041338ec73a  mise.spec.sources
bfbda3d336e38a1ae82ae436f0ac2276df72844d9b45f8cec39e6097ce98af98  quickshell.spec
a550a80df5e6218a9a4144dd92c7443ad51d4b6e109dfd463f95790c42af025a  quickshell.spec.sources
abe59a80c9d7369f328c07fd896f6282f95c068018faeac7fb3f942d6c5e29ce  tensaku.spec
da97d1cbacad556ba5a8324e275d560f2b80c18e3a29597210107b775be4cd62  tensaku.spec.sources
bb73a867ec646a46cbf21832789e638aa2bcf764975d3f017569c7a4620427d4  tinkero-nerd-fonts.spec
701fc494ccdb72cfb692ed07983d5613f255325106f1be196a4189c15da384fd  tinkero-nerd-fonts.spec.sources
5588b32acac92503d20e25fbfe8e7bfbc6cbfabdbed31e19548eea4202fbc1a5  ttfx.spec
3e21fbf5e883d1b73f417c592de0b1ae40664424aac174cc307b2da7229b9fe4  ttfx.spec.sources
e2445cbd295952ef68b742ad55cd462b1f7eb455afbc94ff7efb93259e819ad3  uwsm.spec
75245b566b1f0e71ed9373d3ec7a2528b997d426dac32da04a8d1752edac24da  uwsm.spec.sources
afecfa255ce11c258008aa30a04bba9b3bcefbe1152b9a572ffab9e29f6eb66b  voxtype.spec
23f369814c9d135cc8560e2b553751d077386afc5b9a719ce4e04afac7e07527  voxtype.spec.sources
f33d703b0090cd960d31a3890e9bfdbc1c1a5b7a35ac17e6630fe870be70151b  xdg-desktop-portal-hyprland.spec
d79aac252a4ae190125143fdc2d255a976a344afcaee97ceb9651e535f12ae4e  xdg-desktop-portal-hyprland.spec.sources
```

Then `bash tests/test-specs.sh`: expected `1..82`, no `not ok`. Then `rm -rf "$t"`.

- [ ] **Step 7: Commit**

```bash
git add distro/fedora/specs tests/test-specs.sh
git commit -m "specs: import the 25-package set from Omedora at 9672f96 (font renamed, uwsm recommends dropped)"
```

---

### Task 2: SRPM generation and the Makefile dispatch, checked in CI

**Files:**
- Create: `distro/fedora/specs/srpm.sh`
- Replace: `.copr/Makefile`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `make -f .copr/Makefile srpm spec=<path> outdir=<dir>` builds the source RPM of any spec in the set (or of `tinkero.spec` when `spec` is empty or names it). `srpm.sh <spec-path> <outdir>` is what it calls.

- [ ] **Step 1: Write `srpm.sh`**

Create `distro/fedora/specs/srpm.sh` (`chmod +x`). It is Omedora's `.copr/srpm.sh` without the self-source block and with a new header; the fetch, pin-verify, cargo-vendor and zig-cache logic is unchanged:

```bash
#!/bin/bash
#
# COPR SRPM generation for the Tinkero package set (distro/fedora/specs/*.spec).
# Forked from Omedora's .copr/srpm.sh (AndrewGaspar/omedora, MIT, commit 9672f96);
# the self-source mode is gone (the tinkero RPM has its own path in .copr/Makefile).
# .copr/Makefile calls this for every spec that is not tinkero.spec:
#     srpm.sh <spec-path> <outdir>
#
# COPR's mock BUILD phase is OFFLINE, so everything that needs the network happens
# here in the SRPM step: fetching the declared sources, verifying them against the
# sha256 pins in <spec>.sources, and vendoring Rust crates or Zig packages.

set -euo pipefail

spec="${1:?usage: srpm.sh <spec-path> <outdir>}"
outdir="${2:?usage: srpm.sh <spec-path> <outdir>}"

# $spec may be a bare basename (COPR Subdirectory = the spec dir) or a
# repo-relative/absolute path. Resolve the directory holding the spec, its
# <spec>.sources pin file, and any local (non-URL) Source siblings.
spec_dir=$(cd -- "$(dirname -- "$spec")" && pwd)
spec_base=$(basename -- "$spec")

# Toolchain. COPR's SRPM step starts from a bare chroot. rpm-build gives
# rpmbuild; rpmdevtools gives spectool. No BuildRequires are needed here:
# `rpmbuild -bs` packages the sources, it does not compile. cargo is installed on
# demand below only for Rust (vendored) specs. keepcache=1 keeps the downloaded
# tooling RPMs in /var/cache/libdnf5 so repeat runs reuse them.
dnf install -y --setopt=keepcache=1 --setopt=install_weak_deps=False \
  rpm-build rpmdevtools >/dev/null

# Use the AMBIENT %_topdir, not a hardcoded ~/rpmbuild: COPR's source build runs
# in mock, which redefines %_topdir (e.g. /builddir/build). build-local.sh can
# assume ~/rpmbuild because a plain container leaves %_topdir at $HOME/rpmbuild;
# here we must honor whatever the chroot set. Create the tree at that location.
TOPDIR=$(rpm --eval %_topdir)
mkdir -p "$TOPDIR"/{SPECS,SOURCES,SRPMS,BUILD}
cp "$spec_dir/$spec_base" "$TOPDIR/SPECS/"

# Stage local (non-URL) Source siblings — spectool -g only fetches URL sources,
# so plain filenames (e.g. hyprland's macros.hyprland) are copied in by hand.
grep -iE '^Source[0-9]*:' "$spec_dir/$spec_base" | sed -E 's/^[^:]+:[[:space:]]*//' | while read -r src; do
  case "$src" in
    *://*) : ;;                                   # URL — spectool fetches it
    *) [[ -f "$spec_dir/$src" ]] && cp "$spec_dir/$src" "$TOPDIR/SOURCES/" ;;
  esac
done || true   # never trip set -e on a URL-only spec

# Stage local patches alongside local Sources.
grep -iE '^Patch[0-9]*:' "$spec_dir/$spec_base" | sed -E 's/^[^:]+:[[:space:]]*//' | while read -r patch_file; do
  [[ -f "$spec_dir/$patch_file" ]] && cp "$spec_dir/$patch_file" "$TOPDIR/SOURCES/"
done || true

# Fetch every URL SourceN declared in the spec into SOURCES/.
spectool -g -R "$TOPDIR/SPECS/$spec_base"

# INTEGRITY GATE: verify each fetched remote source against its committed sha256
# pin BEFORE packaging, so an upstream source that changed underneath the pin
# aborts here rather than silently flowing into the SRPM. Pins live in
# <spec>.sources ("<hash>  <fetched-basename>", `sha256sum -c` format). We do not
# pin the locally generated *-vendor.tar.* (cargo's per-crate checksums anchor it
# to the pinned Source0's Cargo.lock). See README.md in this directory.
sources_pin="$spec_dir/$spec_base.sources"
if [[ -f "$sources_pin" ]]; then
  echo "==> Verifying fetched sources against $(basename "$sources_pin")"
  pin_name=$(basename "$sources_pin")
  while read -r want_hash want_file; do
    [[ -z "$want_hash" || "$want_hash" == \#* ]] && continue
    got_path="$TOPDIR/SOURCES/$want_file"
    if [[ ! -f "$got_path" ]]; then
      echo "SOURCE PIN ERROR: pinned source not fetched: $want_file" >&2
      echo "  (declared in $pin_name but missing from SOURCES/)" >&2
      exit 1
    fi
    got_hash=$(sha256sum "$got_path" | awk '{print $1}')
    if [[ "$got_hash" != "$want_hash" ]]; then
      echo "SOURCE PIN MISMATCH: $want_file" >&2
      echo "  expected sha256: $want_hash" >&2
      echo "  got sha256:      $got_hash" >&2
      echo "  Upstream changed since pinned; verify + re-pin (see README.md). Aborting." >&2
      exit 1
    fi
    echo "    ok: $want_file"
  done < "$sources_pin"
else
  echo "==> No sources pin file ($(basename "$sources_pin")); skipping source verification" >&2
fi

# Regenerate the Rust cargo-vendor tarball for any *-vendor.tar.* SourceN, so
# COPR's offline build phase has the crate set. Deterministic from the pinned
# Source0 tarball's committed Cargo.lock (crates.io content is immutable). cargo
# isn't in the bare SRPM chroot, so install it on demand. Generic + guarded: act
# only for a *-vendor.tar.* SourceN not already in SOURCES/; non-Rust specs are
# untouched.
grep -iE '^Source[0-9]*:' "$spec_dir/$spec_base" | sed -E 's/^[^:]+:[[:space:]]*//' | while read -r src; do
  case "$src" in
    *-vendor.tar.*)
      command -v cargo >/dev/null 2>&1 || \
        dnf install -y --setopt=keepcache=1 --setopt=install_weak_deps=False cargo >/dev/null
      read -r nv_name nv_version < <(rpmspec -q --srpm --qf '%{name} %{version}\n' "$spec_dir/$spec_base")
      vendor_tar="$TOPDIR/SOURCES/${nv_name}-${nv_version}-vendor.tar.zst"
      [[ -f "$vendor_tar" ]] && continue   # already present
      echo "==> Generating vendor tarball: $(basename "$vendor_tar")"
      work=$(mktemp -d)
      # Source0 lives in SOURCES/ under its URL basename (what spectool fetched).
      src0=$(rpmspec -P "$spec_dir/$spec_base" | sed -nE 's/^Source0:[[:space:]]*//p' | head -n1)
      src0_file="$TOPDIR/SOURCES/$(basename "$src0")"
      tar -C "$work" -xf "$src0_file"
      crate_top=$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n1)
      # Keep the release lock immutable. 
      vendor_dir=vendor
      [[ -d "$crate_top/vendor/portable-pty" ]] && vendor_dir=cargo-vendor
      ( cd "$crate_top" && cargo vendor --locked "$vendor_dir" >/dev/null )
      # Reproducible tar (normalized metadata) so re-runs are byte-identical.
      tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        -C "$crate_top" -caf "$vendor_tar" "$vendor_dir"
      rm -rf "$work"
      ;;
  esac
done

# Herdr's vendored libghostty-vt uses Zig's package manager. Seal its global
# dependency cache in the networked SRPM phase when requested by Source3, using
# the exact Zig Source2 declared and checksum-pinned by the spec.
grep -iE '^Source[0-9]*:' "$spec_dir/$spec_base" | sed -E 's/^[^:]+:[[:space:]]*//' | while read -r src; do
  case "$src" in
    *-zig-cache.tar.*)
      read -r nv_name nv_version < <(rpmspec -q --srpm --qf '%{name} %{version}\n' "$spec_dir/$spec_base")
      zig_cache_tar="$TOPDIR/SOURCES/${nv_name}-${nv_version}-zig-cache.tar.zst"
      [[ -f "$zig_cache_tar" ]] && continue
      echo "==> Generating Zig dependency cache: $(basename "$zig_cache_tar")"
      work=$(mktemp -d)
      src0=$(rpmspec -P "$spec_dir/$spec_base" | sed -nE 's/^Source0:[[:space:]]*//p' | head -n1)
      src2=$(rpmspec -P "$spec_dir/$spec_base" | sed -nE 's/^Source2:[[:space:]]*//p' | head -n1)
      tar -C "$work" -xf "$TOPDIR/SOURCES/$(basename "$src0")"
      tar -C "$work" -xf "$TOPDIR/SOURCES/$(basename "$src2")"
      crate_top=$(find "$work" -mindepth 1 -maxdepth 1 -type d -name "${nv_name}-*" | head -n1)
      zig_top=$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'zig-*' | head -n1)
      patch -d "$crate_top" -p1 <"$spec_dir/herdr-libvt-only.patch"
      mkdir -p "$crate_top/zig-cache"
      # Execute the exact lib-vt graph once while network is available. Zig
      # resolves lazy packages only while running the graph. Keep only the
      # immutable package store; compiler state may embed temporary paths.
      ( cd "$crate_top/vendor/libghostty-vt" && \
        ZIG_GLOBAL_CACHE_DIR="$crate_top/zig-cache" "$zig_top/zig" build \
          -Demit-lib-vt -Doptimize=ReleaseFast -Dsimd=true \
          -Dtarget=x86_64-linux-gnu -Dversion-string=0.8.0 \
          -Demit-xcframework=false )
      find "$crate_top/zig-cache" -mindepth 1 -maxdepth 1 ! -name p \
        -exec rm -rf -- {} +
      tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        -C "$crate_top" -caf "$zig_cache_tar" zig-cache
      rm -rf "$work"
      ;;
  esac
done

# Build the source RPM and hand it to COPR.
mkdir -p "$outdir"
rpmbuild -bs "$TOPDIR/SPECS/$spec_base"
cp -v "$TOPDIR"/SRPMS/*.src.rpm "$outdir"/
```

- [ ] **Step 2: Replace `.copr/Makefile`**

Recipe lines start with a TAB. The `srpm` target dispatches on the spec's basename:

```make
# COPR "make_srpm" entry point. COPR runs, as root in a fresh chroot with network:
#   make -f <clone>/.copr/Makefile srpm outdir=<dir> spec=<path>
# Two kinds of package live in this repo:
#   * the tinkero RPM itself (spec= is empty or names tinkero.spec): rendered from
#     tinkero.spec.in and upstream.lock, sources fetched and verified by build/;
#   * the COPR package set under distro/fedora/specs/ (spec= names one of them):
#     handed to distro/fedora/specs/srpm.sh, which fetches, pin-verifies, vendors
#     and builds the source RPM.
TOP := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..
outdir ?= $(CURDIR)
spec ?= tinkero.spec

.PHONY: srpm srpm-tinkero srpm-package
srpm:
	@case "$(notdir $(spec))" in \
	  tinkero.spec|"") $(MAKE) -f $(lastword $(MAKEFILE_LIST)) srpm-tinkero outdir="$(outdir)" ;; \
	  *) $(MAKE) -f $(lastword $(MAKEFILE_LIST)) srpm-package outdir="$(outdir)" spec="$(spec)" ;; \
	esac

srpm-tinkero:
	dnf -y install git-core curl rpm-build
	cd $(TOP) && \
	  build/fetch-upstream >/dev/null && \
	  build/render-spec tinkero.spec && \
	  git archive --format=tar.gz -o .cache/tinkero-src.tar.gz HEAD
	cd $(TOP) && rpmbuild -bs tinkero.spec \
	  --define "_sourcedir $(abspath $(TOP))/.cache" \
	  --define "_srcrpmdir $(outdir)"

srpm-package:
	bash $(TOP)/distro/fedora/specs/srpm.sh "$(TOP)/distro/fedora/specs/$(notdir $(spec))" "$(outdir)"
```

Verify: `grep -cP '^\t' .copr/Makefile` prints `13`; `bash -n distro/fedora/specs/srpm.sh`; `shellcheck -x -e SC1090,SC1091 distro/fedora/specs/srpm.sh` prints nothing.

- [ ] **Step 3: CI**

In `.github/workflows/ci.yml`: add `rpmdevtools` to the Tools package list (after `rpm-build`); add `distro/fedora/specs/srpm.sh bin/tinkero-copr` at the end of the ShellCheck file list (the second file arrives in Task 3; ShellCheck fails on a missing file, so add it in Task 3 instead if you push in between); and after the step "Spec renders, parses and lints" insert:

```yaml
      - name: Package specs parse and lint
        run: |
          for s in distro/fedora/specs/*.spec; do rpmspec -P "$s" > /dev/null || exit 1; done
          rpmlint distro/fedora/specs/*.spec
      - name: One package SRPM builds the way COPR builds it (glaze, the smallest)
        run: |
          mkdir -p "$PWD/.cache/srpm-glaze"
          make -f .copr/Makefile srpm spec=distro/fedora/specs/glaze.spec outdir="$PWD/.cache/srpm-glaze"
          ls -l .cache/srpm-glaze/*.src.rpm
```

- [ ] **Step 4: Commit, push, make CI green**

```bash
git add distro/fedora/specs/srpm.sh .copr/Makefile .github/workflows/ci.yml
git commit -m "build: SRPM generation for the package set; .copr/Makefile dispatches on spec="
git push origin task/425e16e7
gh run watch "$(gh run list --branch task/425e16e7 --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

If `rpmlint` reports errors (not warnings) on the imported specs, fix the spec and record it under Deviations; warnings are recorded and left. If the glaze SRPM step fails, read the log: the likely causes are a missing tool in the SRPM chroot (add it to the `dnf install` line inside `srpm.sh`) or the `spectool` fetch; fix `srpm.sh`, never the pin. Stop and report after four red pushes.

---

### Task 3: The submit tool and the manual workflow

**Files:**
- Create: `bin/tinkero-copr` (`chmod +x`), `tests/test-copr.sh`, `.github/workflows/copr-build.yml`
- Modify: `.github/workflows/ci.yml` (add `bin/tinkero-copr` to the ShellCheck list if not done in Task 2)

- [ ] **Step 1: Write the failing test**

Create `tests/test-copr.sh`:

```bash
#!/bin/bash
# bin/tinkero-copr against a stub copr-cli that logs its argv and fails "add" for
# packages already registered.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin"; export LOG=$d/log
cat > "$d/bin/copr-cli" <<'S'
#!/bin/bash
echo "copr-cli $*" >> "$LOG"
# add-package-scm fails for a package listed in $EXISTING, edit succeeds for it
if [[ $1 == add-package-scm ]]; then
  for a in "$@"; do [[ $a == --name ]] && next=1 && continue; [[ ${next:-} == 1 ]] && { name=$a; break; }; done
  grep -qx "$name" "$EXISTING" 2>/dev/null && exit 1
fi
exit 0
S
chmod +x "$d/bin/copr-cli"; export PATH=$d/bin:$PATH EXISTING=$d/existing; : > "$EXISTING"
T=$ROOT/bin/tinkero-copr
assert_eq "$("$T" order | head -n1)" tinkero-nerd-fonts "order: first package"
assert_eq "$("$T" order | wc -l)" 25 "order: all 25"
assert_eq "$("$T" order hyprutils glaze | paste -sd' ')" "glaze hyprutils" "order: subset keeps canonical order"
"$T" build nope >/dev/null 2>&1; assert_eq "$?" 1 "unknown package is an error"
: > "$LOG"; TINKERO_COPR_PROJECT=me/proj "$T" register glaze >/dev/null
assert_contains "$(cat "$LOG")" "add-package-scm me/proj --name glaze --clone-url https://github.com/dromeropa/tinkero.git --commit master --subdir distro/fedora/specs --spec glaze.spec --type git --method make_srpm" "register: add with the SCM settings"
echo glaze > "$EXISTING"; : > "$LOG"; out=$("$T" register glaze)
assert_contains "$(cat "$LOG")" "edit-package-scm dromero/tinkero --name glaze" "register: falls back to edit when the package exists"
assert_contains "$out" "updated:    glaze" "and says so"
: > "$LOG"; TINKERO_COPR_COMMIT=task/x "$T" build glaze hyprutils >/dev/null
assert_eq "$(grep -c build-package "$LOG")" 2 "build: one build-package call per package"
assert_eq "$(grep build-package "$LOG" | head -n1)" "copr-cli build-package dromero/tinkero --name glaze" "build: in order, waiting (no --nowait)"
: > "$LOG"; out=$(TINKERO_COPR_DRY_RUN=1 "$T" build glaze)
assert_eq "$(wc -l < "$LOG")" 0 "dry run calls nothing"; assert_contains "$out" "copr-cli build-package dromero/tinkero --name glaze" "dry run prints the command"
"$T" >/dev/null 2>&1; assert_eq "$?" 2 "no command prints usage and exits 2"
rm -rf "$d"; finish
```

Run: `bash tests/test-copr.sh`. Expected: `not ok` (the tool does not exist).

- [ ] **Step 2: Write the tool**

Create `bin/tinkero-copr`:

```bash
#!/bin/bash
# tinkero-copr: register and build the Tinkero package set on COPR, in order.
#
#   tinkero-copr register [PKG...]   (re)register packages as SCM/make_srpm sources
#   tinkero-copr build [PKG...]      build one at a time, waiting for each (the Hyprland
#                                    stack needs each -devel published before the next)
#   tinkero-copr all [PKG...]        register, then build
#   tinkero-copr order [PKG...]      print the build order and exit
#
# Without PKG arguments every package in distro/fedora/specs/build-order.txt is
# used; with them, only those, still in canonical order. Environment:
#   TINKERO_COPR_PROJECT  owner/project      (default dromero/tinkero)
#   TINKERO_COPR_CLONE    git clone URL      (default https://github.com/dromeropa/tinkero.git)
#   TINKERO_COPR_COMMIT   branch or commit   (default master)
#   TINKERO_COPR_DRY_RUN  1 prints the copr-cli commands instead of running them
# Needs copr-cli with a token in ~/.config/copr (or COPR_CONFIG pointing at one).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${TINKERO_ROOT:-$(dirname "$here")}
order_file=$root/distro/fedora/specs/build-order.txt
project=${TINKERO_COPR_PROJECT:-dromero/tinkero}
clone=${TINKERO_COPR_CLONE:-https://github.com/dromeropa/tinkero.git}
commit=${TINKERO_COPR_COMMIT:-master}

die() { echo "error: $*" >&2; exit 1; }
run() {
  if [[ ${TINKERO_COPR_DRY_RUN:-0} == 1 ]]; then printf '%q ' "$@"; echo; else "$@"; fi
}

mapfile -t all < <(grep -vE '^\s*(#|$)' "$order_file")
(( ${#all[@]} )) || die "no packages in $order_file"
for p in "${all[@]}"; do
  [[ -f $root/distro/fedora/specs/$p.spec ]] || die "$p is in build-order.txt but distro/fedora/specs/$p.spec does not exist"
done

cmd=${1:-}; shift || true
if (( $# )); then
  declare -A want=()
  for p in "$@"; do
    printf '%s\n' "${all[@]}" | grep -qx "$p" || die "unknown package: $p (not in build-order.txt)"
    want[$p]=1
  done
  pkgs=(); for p in "${all[@]}"; do [[ -n ${want[$p]-} ]] && pkgs+=("$p"); done
else
  pkgs=("${all[@]}")
fi

register_one() {
  local name=$1
  local args=(--name "$name" --clone-url "$clone" --commit "$commit"
              --subdir distro/fedora/specs --spec "$name.spec"
              --type git --method make_srpm --timeout 18000 --webhook-rebuild off)
  # add fails when the package exists, edit fails when it does not: try both
  if run copr-cli add-package-scm "$project" "${args[@]}" 2>/dev/null; then echo "registered: $name"
  elif run copr-cli edit-package-scm "$project" "${args[@]}"; then echo "updated:    $name"
  else die "could not register $name"; fi
}
build_one() {
  echo "==> building $1 in $project (waits for the build to finish)"
  run copr-cli build-package "$project" --name "$1"
}

case $cmd in
  order)    printf '%s\n' "${pkgs[@]}" ;;
  register) for p in "${pkgs[@]}"; do register_one "$p"; done ;;
  build)    for p in "${pkgs[@]}"; do build_one "$p"; done ;;
  all)      for p in "${pkgs[@]}"; do register_one "$p"; done; for p in "${pkgs[@]}"; do build_one "$p"; done ;;
  *)        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
```

Run: `bash tests/test-copr.sh` (expect `1..12`, no `not ok`), `./dev check` (expect the totals `1..30 1..12 1..9 1..41 1..4 1..8 1..16 1..33 1..82`), `TINKERO_COPR_DRY_RUN=1 bin/tinkero-copr all` (prints 50 `copr-cli` lines, calls nothing).

- [ ] **Step 3: Write the workflow**

Create `.github/workflows/copr-build.yml`:

```yaml
name: copr-build
# Register and build packages of the Tinkero package set on COPR, in dependency
# order, one at a time. Manual only: builds cost COPR time and publish to the repo.
on:
  workflow_dispatch:
    inputs:
      packages:
        description: "Space-separated package names from distro/fedora/specs/build-order.txt, or 'all'"
        required: true
        default: all
      command:
        description: "register, build or all"
        required: true
        default: all
permissions:
  contents: read
concurrency:
  group: copr-build
  cancel-in-progress: false
defaults:
  run:
    shell: bash
jobs:
  copr:
    runs-on: ubuntu-latest
    container: fedora:44
    timeout-minutes: 360
    steps:
      - name: Tools
        run: dnf -y install git-core copr-cli
      - uses: actions/checkout@v4
      - name: COPR token
        run: |
          install -m 0600 /dev/null ~/.config/copr 2>/dev/null || { mkdir -p ~/.config; install -m 0600 /dev/null ~/.config/copr; }
          printf '%s\n' "$COPR_CONFIG" > ~/.config/copr
          copr-cli whoami
        env:
          COPR_CONFIG: ${{ secrets.COPR_CONFIG }}
      - name: Submit
        run: |
          pkgs=""; [[ "${{ inputs.packages }}" != all ]] && pkgs="${{ inputs.packages }}"
          # shellcheck disable=SC2086  # pkgs is a space-separated list by design
          TINKERO_COPR_COMMIT="${{ github.ref_name }}" bin/tinkero-copr "${{ inputs.command }}" $pkgs
```

Note: the `tinkero` RPM itself is not in `build-order.txt` and is not built by this plan; it is not installable until plans 2C to 2F land.

- [ ] **Step 4: Commit and push**

```bash
git add bin/tinkero-copr tests/test-copr.sh .github/workflows/copr-build.yml .github/workflows/ci.yml
git commit -m "build: tinkero-copr submits the package set in order; manual copr-build workflow"
git push origin task/425e16e7
```

CI must stay green (ShellCheck now covers the tool).

---

### Task 4: Register and build on COPR

Prerequisites, both the user's: the repository secret `COPR_CONFIG` holds the `[copr-cli]` block from https://copr.fedorainfracloud.org/api/ (expires 2027-03-21), and the user has confirmed that builds may be triggered. Each trigger publishes packages to `dromero/tinkero`. The workflow reads the specs from the branch it is run on, so pass `--ref task/425e16e7` until the branch is merged.

- [ ] **Step 1: The ten independent packages**

```bash
gh workflow run copr-build.yml --ref task/425e16e7 -f command=all \
  -f packages="tinkero-nerd-fonts mise quickshell uwsm gpu-screen-recorder hyprland-preview-share-picker tensaku ttfx herdr voxtype"
sleep 60; id=$(gh run list --workflow copr-build.yml --limit 1 --json databaseId -q '.[0].databaseId'); gh run watch "$id" --exit-status
```

The job waits for each build, so this can take an hour or more (the Rust packages vendor their crates in the SRPM step and compile in mock). On a failed package the job stops at that package. Read its COPR log: the build id is in the job output; the log is at `https://download.copr.fedorainfracloud.org/results/dromero/tinkero/fedora-44-x86_64/<id>-<name>/builder-live.log.gz` (SRPM-step failures are under `.../srpm-builds/<id>/builder-live.log.gz`). Fix the spec or `srpm.sh`, push, re-run the workflow with the remaining packages (they resume from any point: registration is idempotent).

- [ ] **Step 2: The Hyprland stack, in order**

```bash
gh workflow run copr-build.yml --ref task/425e16e7 -f command=all \
  -f packages="glaze hyprland-protocols hyprutils hyprwayland-scanner hyprlang hyprgraphics hyprwire hyprcursor aquamarine hyprtoolkit hyprland hyprland-guiutils hyprpicker hyprsunset xdg-desktop-portal-hyprland"
```

Same watch and recovery loop. `hyprland` alone takes long; the workflow's 6-hour limit should hold for the fifteen, but if it does not, split at `hyprland` and run two dispatches.

- [ ] **Step 3: Verify from a Fedora 44 host or container**

```bash
dnf -q repoquery --repofrompath=tinkero,https://download.copr.fedorainfracloud.org/results/dromero/tinkero/fedora-44-x86_64/ --repo=tinkero --qf '%{name} %{version}-%{release}\n' 2>/dev/null | sort
```

Expected: 25 packages (plus their subpackages such as `-devel`), with `hyprland 0.56.2`, `quickshell 0.3.0^20.git28771c7`, `uwsm 0.26.5`, `tinkero-nerd-fonts 3.4.0`. Then the milestone of spec section 7: on a clean Fedora 44 machine or VM, `sudo dnf copr enable dromero/tinkero && sudo dnf install hyprland quickshell uwsm mise herdr` succeeds and pulls no `nwg-panel`, `wofi`, `playerctl` or `newt`.

- [ ] **Step 4: Record**

Append to the "## Deviations" section of this plan every spec change made to get green, one line each with the reason, and commit them together with any spec fixes that are not yet committed:

```bash
git add distro/fedora/specs docs/superpowers/plans/2026-09-22-phase-1-copr-package-set.md
git commit -m "specs: fixes from the first COPR build of the set"
git push origin task/425e16e7
```

---

### Task 5: Documentation

- [ ] **Step 1: Spec and roadmap**

In `docs/superpowers/specs/2026-09-17-tinkero-design.md`, section 7, mark Phase 1 done with the date and the milestone result. In `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, add a "Phase 1 done" line under the COPR section, note that `herdr` is at `0.8.0^13` while upstream is at 0.9.1 (a bump for a later plan), and that the `voxtype` name-map row is now backed by a real package.

- [ ] **Step 2: Commit and push**

```bash
git add docs
git commit -m "docs: Phase 1 done, the package set builds in dromero/tinkero"
git push origin task/425e16e7
```

---

## Deviations

- Task 2, fix round 1: `distro/fedora/specs/srpm.sh`'s two `while read` loops
  that generate the vendor tarball and the Zig cache (the `*-vendor.tar.*`
  and `*-zig-cache.tar.*` case arms) were missing the `|| true` guard the
  brief's two earlier loops already had; under `set -euo pipefail` a spec
  with no `Source` lines would abort the pipeline silently. Appended
  `|| true   # never trip set -e on a source-less spec` after each `done`.
- Task 2, fix round 1: `srpm.sh`'s final `cp -v "$TOPDIR"/SRPMS/*.src.rpm
  "$outdir"/` copied every SRPM ever built into that rpmbuild tree, which
  persists across CI steps; a later package's outdir would pick up earlier
  packages' SRPMs too. Narrowed to `cp -v "$TOPDIR/SRPMS/${spec_base%.spec}"-*.src.rpm
  "$outdir"/`, relying on `tests/test-specs.sh` guaranteeing spec `Name`
  matches the spec's file name.
- Task 2, fix round 1: added a CI step exercising the Rust-vendoring path
  (`ttfx.spec`, one of the five vendored specs) in addition to the
  no-vendoring `glaze` SRPM smoke test, so CI covers the `cargo vendor`
  branch that COPR will also exercise.
- Task 3, fix round 1: `bin/tinkero-copr` function `register_one()` was
  suppressing `add-package-scm`'s stderr with `2>/dev/null`, so if it failed
  for a reason other than "already exists" (auth error, network, etc.), the
  operator only saw the message from `edit-package-scm`. Changed to capture
  `add-package-scm`'s output and print it if both calls fail, revealing the
  real cause. Also changed `run()` to print dry-run commands to stderr so
  they don't get captured by a command substitution.
- Task 3, fix round 1: `.github/workflows/copr-build.yml` COPR token step
  had an overly complex file creation line with a fallback mkdir. Simplified
  to a single `mkdir -p ~/.config && install` line and added a comment
  clarifying that `copr-cli whoami` only reads the config; the token is first
  validated by the API in the Submit step.
- Task 3, fix round 2: fix round 1 broke dry-run for `register` and `all`:
  the dry-run command printed by `run()` to stdout was captured by the
  `add_err=$(run copr-cli add-package-scm ... 2>&1)` substitution, making the
  code think the command succeeded. Reverted `run()` to print to stdout, and
  added a dry-run branch in `register_one()` that prints the command and
  returns early before attempting to capture output. Added tests for dry-run
  register and dry-run all.

## What this plan deliberately leaves out

- The `tinkero` RPM in the COPR: not until the tree is installable (plans 2C to 2F).
- The release archive on GitHub releases and the Qt-watch rebuild trigger: Phase 3.
- Bumping `herdr` to 0.9.1 and reviewing `voxtype`'s fork source: later, with the bump checklist.
- A second Fedora chroot: when Fedora 45 branches.
