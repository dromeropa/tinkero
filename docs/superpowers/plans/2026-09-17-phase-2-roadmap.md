# Phase 2 roadmap: the tree

Phase 2 of the design spec (section 7) is six independent subsystems. One plan each, because each produces something that works and can be tested on its own, and because a plan written far ahead of the code it depends on goes stale. 2A is written in full. The others are scoped here, with their interfaces fixed, and are written when the plan before them has been executed.

**Spec:** `docs/superpowers/specs/2026-09-17-tinkero-design.md`. **Audit:** `docs/research/arch-coupling-audit.md`.

| Plan | Delivers | Depends on | Blocked by Phase 0? | Status |
|---|---|---|---|---|
| **2A** build skeleton, payload assembly, CI gates | `./dev gates` green on the real `v4.0.4` tree; SRPM builds in CI | nothing | no | **done** 2026-09-17: `2026-09-17-phase-2a-build-skeleton-and-gates.md`; CI green on the branch |
| **2B** patches, replacements, name map | patches 0002 to 0010, 13 replacements, `distro/fedora/pkgmap.tsv` (71 rows), `ci/gate-name-map`; `arch-leak.allow` at 8 entries (6 permanent, 1 for 2C, 1 for 2F) | 2A | no | **done** 2026-09-22: `2026-09-21-phase-2b-patches-replacements-name-map.md`; CI green |
| **2C** menu rewrite | `menu/apply-overrides`, `menu/overrides.jsonc`, `tinkero-update`; `dropped-refs.allow` down to comment-only entries | 2A, and 2B's drop decisions | no | **done** 2026-09-23: `2026-09-23-phase-2c-menu-rewrite.md`; first plan through the issue loop |
| **2D** branding | font rebuild, wallpaper rendering, manifest rewrite, `branding/strings.tsv` and `images.tsv`, the branding gate | 2A, 2C (menu labels) | no | **done** 2026-09-24: `2026-09-23-phase-2d-branding.md`; design `2026-09-23-phase-2d-branding-design.md`; the placeholder mark ships until the real one exists |
| **2E** provisioning and install | `tinkero-provision` with `seeded.tsv`, the two provisioning wrappers, `install.sh`, `host.md`, config overrides | 2A, 2B | no | **done** 2026-09-23: `2026-09-23-phase-2e-provision-and-install.md`; design `specs/2026-09-23-phase-2e-provision-design.md` |
| **2F** session integration | lock-screen PAM variants and `tinkero-pam-sync`, the dconf profile and `DCONF_PROFILE` export, `[Install]` stripping and session-started units with the fcitx5 drop-in, `tinkero-inhibit-power-key`, `omarchy-apply-lock` patch, fingerprint replacements | 2A, 2E | no longer: Phase 0 is done (GO, 2026-09-21) | to write; its VM check re-runs the Phase 0 GNOME cycle with the dconf profile |

Milestones A, B and C of the spec (section 8) need 2A to 2F and the Phase 1 COPR. Nothing before 2F needs a running desktop: every plan up to 2E is verified by unit tests against a fixture tree and by the gates against the real tree.

## Order and parallelism

2A first. Then 2B and 2C can run in parallel (different files; they meet only in `build/drop.list` and the two allowlists, which both may only shrink). 2D after 2C. 2E after 2B. 2F last.

## Interfaces fixed by 2A that the later plans build on

- `build/assemble TARBALL DEST` is the whole of `%install`. Later plans add **numbered steps inside it** (menu rewrite and branding go between "Replace" and "Relocate"; Tinkero's own files are installed at the end) and add their outputs to `%files` in `tinkero.spec.in`. They do not add logic to the spec file.
- Data over code: what is dropped is `build/drop.list`; what is patched is `patches/series`; what is replaced is a file in `distro/fedora/replacements/`. A later plan that needs a new kind of input adds a data file and one loop to `assemble`, with a fixture-based test in `tests/test-assemble.sh`.
- Tests: `tests/test-<area>.sh` using `tests/lib.sh`; the fixture generator `tests/fixtures/make-tree.sh` grows a file whenever a new behaviour needs one. No test may use the network.
- Gates compare findings with `ci/allow/<gate>.allow` through `compare_with_allowlist`; allowlists only shrink. A plan is done when the entries it owns are gone.
- Python is allowed from 2C on (JSONC, fonts and manifests are not shell jobs): standard library only plus `python3-fonttools` for the font, tests with `python3 -m unittest`, no pytest.

## What the first real assembly found (inputs to 2B and 2C)

Running the 2A prototype against the real tree while writing the plan produced 28 arch-leak findings and 50 dropped-reference findings. Most are exactly the audit's work list. These were not in the audit and need a decision in 2B:

1. **`omarchy-launch-docker-tui` calls `omarchy-sudo-docker`**, which the audit drops. Decided 2026-09-21: drop the launcher and `applications/Docker.desktop` too; the seeded `bindings.lua` re-adds only tmux and herdr. Docker is *deferred*, not Arch-specific: re-enabling is a drop-list edit, one name-map row and one binding (audit, section 4.3).
2. **`omarchy-default-agent` has an `openclaw)` case.** Decided 2026-09-21: keep it, and keep `omarchy-install-openclaw-cli` (un-dropped). OpenClaw itself is not Arch-specific; only upstream's delivery is. The name-map row `openclaw none` makes the picker explain "install by hand". **Research item:** find OpenClaw's install route on Fedora (npm, pipx, a binary release?) and flip the row's kind; if it is a mise-installable tool, the name map may need a `mise` kind.
3. **`omarchy-reinstall` and `omarchy-launch-battlenet`** were only reachable from dropped commands; 2A's drop list already removes them, with `default/applications/battlenet.desktop`.
4. **`omarchy-bar` and `default/bash/env-bootstrap`** mention dropped commands only in comments. They stay on the dropped-refs allowlist permanently, each with a trailing `# comment only` note, added when 2C makes the list final.
5. **The tree's `version` file says `4.0.0.alpha` at tag `v4.0.4`**, so `omarchy-version` is patched to ask RPM, not to read that file (2A, Task 6).
6. **The "every `omarchy-*` token resolves to a file" gate of spec section 8 is not workable**: on the untouched upstream tree it reports 110 false positives (PAM service names, CSS ids, window classes, unit names). 2A replaces it with the narrower dropped-reference gate, which has none. The spec and audit are updated to match.

## What Phase 0 added (2026-09-21, `docs/research/phase-0-findings.md`)

- **2F:** the GNOME invariant is met by a separate dconf profile for the session, not by save/restore (spec 4.9); the five upstream user units get their `[Install]` stripped at build and are started by `tinkero-provision --session`; `omarchy-fcitx5.service.d/tinkero.conf` adds a condition and a start limit; the autostart restore entry is gone.
- **2B:** `omarchy-pkg-add` and `omarchy-pkg-drop` use `pkexec` inside a graphical session (spec 4.3): an agent cannot answer `sudo` in its own terminal.
- **2B, `tinkero.spec.in`:** require `ppd-service` instead of `power-profiles-daemon` (Fedora 44 ships `tuned-ppd`); add `fcitx5` to the hard requirements.
- **Phase 1 (done):** drop the `Recommends: nwg-panel wofi playerctl newt` that the omedora-4 specs carry. Done for `wofi` and `newt` (the two `uwsm` lines); `nwg-panel` and `playerctl` come from Fedora's `Supplements: hyprland`, see the Phase 1 section below.
- **2E:** seed the Tinkero dconf database from GNOME's at provisioning; `--reset dconf`; removal deletes it. README and `host.md` explain Hyprland Safe Mode after a crash.
- **Bare metal, later:** suspend-to-lock timing; a dead-menu-entry pass (2C removes most by construction).

## What executing 2B added to the queue (2026-09-22)

- **2C:** the 43 dropped-refs entries are almost all menu rows; the `learn.arch` arch-leak entry too. Both allowlists carry trailing comments naming the owner.
- **2E:** `omarchy-reinstall-configs` now calls `tinkero-provision --reset-all` (patch 0003) and fails fast with exit 127 until 2E delivers it; `host.md` documents the name map (`/usr/share/tinkero/pkgmap.tsv`, kinds dnf/flatpak/none, how to add a row).
- **First host with Flathub:** verify the eleven `flatpak` rows with `flatpak search`; consider flatpak rows for steam, minecraft-launcher, heroic, sublime-text-4 (now `none`).
- **Phase 1 (done):** the `voxtype dnf voxtype` row assumes the COPR package. It builds.
- **Research:** OpenClaw's Fedora install route (row is `none`); if it is a mise tool, the map may need a `mise` kind.
- **Gate limits, accepted:** `gate-name-map` counts a trailing `# omarchy-pkg-add x` comment as a use (a visible false positive, never a silent miss) and cannot follow shell variables (the Ollama trio is listed by hand).
- **Process:** CI runs the suite as root; any new elevation logic must respect the `TINKERO_EUID` seam. Tests are ShellCheck-ed in CI: avoid `A && ok || not_ok` one-liners and put `# shellcheck disable=SC2016` above printf lines that write literal `$*` into stub scripts.

## What creating the COPR project added (2026-09-22)

- **Phase 3 (workflow):** COPR's `auto_prune` cannot be disabled by a normal user, so the release workflow must download each tagged release's RPM set from the COPR and attach it to the GitHub release; `tinkero-status` prints the `dnf downgrade` command against those files (spec 4.11).

## What executing Phase 1 added to the queue (2026-09-22)

- **Phase 1 done:** the 25 packages build in `dromero/tinkero` (chroot `fedora-44-x86_64`); `build/tinkero-copr` and the manual `copr-build` workflow are the only submission path; CI lints every spec and smoke-builds two SRPMs.
- **After the merge to master:** the COPR packages are registered against branch `task/425e16e7`; run the `copr-build` workflow once from master with `command=register` and `packages=all` so the SCM source points at master. The workflow's `push` trigger (limited to its own file, job skipped) exists only so GitHub lists the workflow before it is on master; it can be removed then.
- **Plan that ships the `tinkero` RPM and `install.sh` (2E or 2F):** add `Conflicts: nwg-panel` to `tinkero.spec.in` and re-run the Phase 1 depsolve check (`dnf install --assumeno` against the COPR): Fedora's `nwg-panel` declares `Supplements: hyprland`, which is why the milestone install still lists `nwg-panel` and `playerctl` under weak dependencies (spec 6). Not a spec fix: no `Recommends:` of ours names them.
- **Bump checklist (Phase 3):** `herdr` is packaged at `0.8.0^13.git0766aa5` (Omedora's pin) while upstream is at 0.9.1; the first real bump should take it. `voxtype 1.0.1` builds from Omedora's fork source; review whether upstream's own release builds before bumping.
- **Name map:** the `voxtype dnf voxtype` row is now backed by a real package.
- **COPR operations:** the import queue can hold a build in `importing` for 40 minutes; nothing to fix, just do not read it as a hang. A full run of the set takes about four hours (two dispatches, `voxtype` and `hyprland` are the long builds).

## What executing 2E added to the queue (2026-09-23)

- **2F:** append `tinkero-inhibit-power-key.service` to `provision/session-units.list`; export `DCONF_PROFILE=tinkero` from uwsm's `env.d` (the profile file and the seeded database exist); the VM check proves `dconf load` under the profile wrote `~/.config/dconf/tinkero` and that the listed units start from `tinkero-provision --session`. Stripping `[Install]` at build time also covers `omarchy-speaker-tuning.service` (copied from the tree into `~/.config/systemd/user` by `omarchy-audio-tuning on`, started by the list from then on, design D4) and `omarchy-tailscale-receive.service` (inert without `/usr/bin/tailscale`); on a matching laptop the VM check confirms the tuning no longer starts under GNOME. 2F's first COPR build issue also re-runs the depsolve for `Conflicts: nwg-panel`.
- **Phase 3:** `tinkero-status` reads `~/.local/state/tinkero/{seeded.tsv,release,done/}` and `tinkero-provision --plan`; the release workflow rewrites `TINKERO_REF` and `TINKERO_FEDORA` in `install.sh` (both in the `${VAR:-value}` form) and attaches it to the release; the VM smoke test runs `install.sh --yes` and confirms dnf5's `%{from_repo}` tag and `dnf copr enable -y`.
- **Bump checklist:** after a tag bump, diff `config/`, `applications/` and `install/user/**` against the previous tag (audit section 10, item 2); update `provision/skip.list` if a new shared-with-GNOME file appears; write `config-notes/<tag>.md` from the config-only migrations; re-run `tinkero-provision --plan` on the real payload and record the new `seed` count in the design's section 8.
- **Not seeded, by decision:** the nautilus-python extensions (D12); Chromium's profile and flags (D1).
- **Permanent allowlist entries, final:** dropped-refs 6 (five comment-only, the Docker binding); arch-leak 7 (six comment-only, `omarchy-setup-security-fingerprint` until 2F).

## What executing 2C added to the queue (2026-09-23)

- **2D:** `learn.omarchy` becomes `learn.tinkero` through `replace` in `menu/overrides.jsonc` (label "Tinkero", the README as a web app or `omarchy-launch-webapp` on the repo); the `update.omarchy` row keeps upstream's glyph, which 2D's font work rebrands.
- **Bump checklist (Phase 3):** after a tag bump, run `apply-overrides` on the new tree, read the deleted-for-dropped-command lines and the row count, update `expect_rows`. A new upstream row that calls a dropped script is deleted automatically; a renamed id in `delete` or `replace` fails the build.
- **Permanent allowlist entries, final:** dropped-refs 7 (five comment-only, the Docker binding, `omarchy-provision-user` until 2E); arch-leak 7 (six comment-only, `omarchy-setup-security-fingerprint` until 2F).
- **Housekeeping done:** `tinkero-copr` moved to `build/`; `bin/` holds only packaged commands (`%{_bindir}/tinkero-*`).

## What executing 2D added to the queue (2026-09-24)

- **The mark:** `branding/mark.svg` and `wordmark.svg` are a generated placeholder; the real artwork replaces them per `branding/README.md` (two files, two commands). The two ASCII renderings are regenerated with upstream's `omarchy-transcode-ascii`.
- **Milestone B (2F):** the on-screen lines this plan could not check: the mark in the bar's menu button and beside the Packages row, the About screen with the 54 by 26 logo and its "built on Omarchy" line, the screensaver, each theme's rotation showing `tinkero.png` where `omarchy.png` was.
- **2F or bare metal:** upstream's `learn.hyprland`, `learn.neovim` and `learn.bash` rows use `omarchy-launch-webapp`, which runs `chromium.desktop` unless the default browser is Chrome-like; on a stock Fedora with Firefox those rows do nothing. Decide between a patch to the launcher's fallback and a name-map row for Chromium. 2D switched Tinkero's two Learn rows to `omarchy-launch-browser`.
- **Bump checklist (Phase 3):** `branding/inventory-images` on the new tree, then review every `review` row on `branding/contact-sheet`'s output; read `apply-strings`' report and fix `strings.tsv`; read `rewrite-manifests`' counts against the plugin diff; run the gate and read new string-literal findings before touching `ci/allow/branding.allow`; check that `U+E900` is still the logo glyph.
- **Developer machines:** `./dev gates` needs `python3-fonttools` and `ImageMagick`; `./dev check` prints a skip line for the two test files that need them.
- **Measured, not as the audit said:** 20 flat wordmark wallpapers, not 18; 36 branded manifests in 37 files, not 28; 11 branded display fields, not 4; five Chromium files and five comment-only mentions the audit did not list.
- **Diego's wallpaper pass:** done 2026-09-24: lumon's two Severance-branded wallpapers deleted as third-party marks, the other 65 kept; `92 wallpapers: 66 kept, 20 regenerated, 6 deleted`, 86 in the payload.
- **Memory for the contact sheet:** about 3.3 GiB and seven minutes for the 92-image montage even with the script's limits; a smaller sheet (thumbnails first) is worth doing if the bump loop makes it routine.

## What executing 2A added to the queue

From the task reviews and the final review of 2A. Each is owned by the plan named.

- **2C:** the arch-leak entry for `omarchy-menu.jsonc` is caused by the `learn.arch` row (an Arch wiki web-app link, line 43), which the audit's delete list did not cover. It is on the list now (audit, section 7); 2C must delete it.
- **2B (decided):** drop `config/autostart/limine-snapper-notify.desktop` and `bin/omarchy-dev-add-migration`; keep the other `omarchy-dev-*` tools (`omarchy-dev-font` is what plan 2D's glyph work will use).
- **2B:** `omarchy-version` now prints `VERSION-RELEASE` with the dist tag (`4.0.4-1.fc44`), and the About screen shows it. Decide whether the About line wants the bare tag.
- **Phase 1 (done):** the COPR's font package must be named `tinkero-nerd-fonts` (the spec template requires it by that name), or the template line is renamed then. It is named `tinkero-nerd-fonts`.
- **First plan that ships a `bin/tinkero-*` command (2C, `tinkero-update`):** add `%{_bindir}/tinkero-*` to `%files`. It cannot be added earlier, because an unmatched glob fails `rpmbuild`.
- **2B, first task (test hygiene, found by the final re-review):** three regression tests do not pin the guard they were written for, because `assert_fails` discards output and the command fails for another reason even without the guard: the two drop-line escape cases in `tests/test-assemble.sh` and the `quickshell=0.3|x` case in `tests/test-render-spec.sh`. Assert on the `die` message instead (the idiom is already used throughout `tests/test-gates.sh`). Also, `tests/test-assemble.sh` mutates one shared fixture root and its last case corrupts the patch without restoring it, so a case appended at the end passes for the wrong reason; restore the fixture after each destructive case. Smaller: the drop-line guard's `*..*` also refuses a legitimate name containing `..`; `gate-single-copy` exits 1 where the other bad-input paths exit 2; `render-spec` still splices `TINKERO_BUILD_DATE` unvalidated.
- **Whenever convenient:** `assert_fails` checks only the exit status, not the message; `gate-dropped-refs` would mis-split a payload path containing a colon; CI discards the SRPM it builds (uploading it is a 125 MB artifact); `actions/checkout@v4` is a mutable tag.
- **Permanent allowlist entries** (comment-only mentions; they stay when 2B and 2C are done): arch-leak: `omarchy-default-agent`, `hooks.md`, `fonts/omarchy/README.md`, `hypr/input.lua`, `launcher.hides`. Dropped-refs: `omarchy-bar`, two in `default/bash/env-bootstrap`, `default/systemd/zram-generator.conf.d/90-omarchy.conf`, `install/user/mise-work.sh`, `omarchy-provision-user` (until 2E replaces it), and the comment lines of `omarchy-launch-docker-tui` and `omarchy-default-agent` (until 2B settles them).

## Scope notes per plan

**2B.** One task per patch or replacement family, each with a fixture case in `tests/test-assemble.sh` or its own `tests/test-replacements.sh` that runs the replacement against stub `rpm`/`dnf`/`flatpak` commands on `PATH` (no real package manager in tests). `pkgmap.tsv` format: `arch-name<TAB>kind<TAB>target`, kinds `dnf`, `flatpak`, `none`. The `MenuModel.js` patch reads a reverse index generated at build time from `pkgmap.tsv` into `/usr/share/tinkero/pkgmap.reverse.tsv`. The name-map gate extracts literal arguments of `omarchy-pkg-add|drop|present|missing` from the payload and requires a row for each.

**2C.** `menu/apply-overrides IN.jsonc OVERRIDES.jsonc DROPLIST OUT.jsonc` in Python: strip comments, delete by id prefix, delete rows whose `action`, `when` or `checked` names a dropped command, apply replacements, write JSONC that upstream's own parser (`stripJsonc` plus `JSON.parse`) accepts. Unit tests on a ten-row fixture menu; then the real menu must go from 333 rows to the expected count with the 76 prefix deletions of the audit, section 7, plus whatever 2B's decisions add.

**2D.** Needs the placeholder mark first (`branding/mark.svg`, a "T" glyph, a text wordmark). `images.tsv` is filled in by a person; the plan provides the contact-sheet command and the gate, not the judgements.

**2E.** `tinkero-provision` is the largest single program in the project. Its tests run against a temporary `HOME` and a fixture `/usr/share/omarchy`; the three-way `seeded.tsv` logic (spec 4.6) is table-tested: one row per case, including deleted-by-user and removed-upstream.

**2F.** Written from `phase-0-findings.md`. If Phase 0 says the Quickshell lock cannot authenticate under SELinux, 2F becomes "package and bind `hyprlock`" instead.
