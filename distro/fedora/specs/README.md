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
