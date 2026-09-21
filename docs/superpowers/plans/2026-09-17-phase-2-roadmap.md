# Phase 2 roadmap: the tree

Phase 2 of the design spec (section 7) is six independent subsystems. One plan each, because each produces something that works and can be tested on its own, and because a plan written far ahead of the code it depends on goes stale. 2A is written in full. The others are scoped here, with their interfaces fixed, and are written when the plan before them has been executed.

**Spec:** `docs/superpowers/specs/2026-09-17-tinkero-design.md`. **Audit:** `docs/research/arch-coupling-audit.md`.

| Plan | Delivers | Depends on | Blocked by Phase 0? | Status |
|---|---|---|---|---|
| **2A** build skeleton, payload assembly, CI gates | `./dev gates` green on the real `v4.0.4` tree; SRPM builds in CI | nothing | no | **done** 2026-09-17: `2026-09-17-phase-2a-build-skeleton-and-gates.md`; CI green on the branch |
| **2B** patches, replacements, name map | the remaining patches and replacement scripts; `distro/fedora/pkgmap.tsv`; the name-map gate; `arch-leak.allow` down to its five permanent entries | 2A | no, except `omarchy-apply-lock` and the fingerprint pair, which wait for 2F | to write |
| **2C** menu rewrite | `menu/apply-overrides`, `menu/overrides.jsonc`, `tinkero-update`; `dropped-refs.allow` down to comment-only entries | 2A, and 2B's drop decisions | no | to write |
| **2D** branding | font rebuild, wallpaper rendering, manifest rewrite, `branding/strings.tsv` and `images.tsv`, the branding gate | 2A, 2C (menu labels) | no, but needs the placeholder mark and one human pass over 92 wallpapers | to write |
| **2E** provisioning and install | `tinkero-provision` with `seeded.tsv`, the two provisioning wrappers, `install.sh`, `host.md`, config overrides | 2A, 2B | no | to write |
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

1. **`omarchy-launch-docker-tui` calls `omarchy-sudo-docker`**, which the audit drops. Recommendation: drop `omarchy-launch-docker-tui` as well and do not re-add the `Super+Shift+D` binding; Docker is a non-goal, and the seeded `bindings.lua` then re-adds only tmux and herdr. (Update the design spec, section 4.6, and the audit, section 7, when this is decided.)
2. **`omarchy-default-agent` still has an `openclaw)` case** that names the dropped `omarchy-install-openclaw-cli` (line 35). The menu row is deleted, but `omarchy-default-agent openclaw` from a terminal would fail confusingly. Recommendation: a one-line patch removing the case and the name from the usage strings. That makes twelve patches, not eleven.
3. **`omarchy-reinstall` and `omarchy-launch-battlenet`** were only reachable from dropped commands; 2A's drop list already removes them, with `default/applications/battlenet.desktop`.
4. **`omarchy-bar` and `default/bash/env-bootstrap`** mention dropped commands only in comments. They stay on the dropped-refs allowlist permanently, each with a trailing `# comment only` note, added when 2C makes the list final.
5. **The tree's `version` file says `4.0.0.alpha` at tag `v4.0.4`**, so `omarchy-version` is patched to ask RPM, not to read that file (2A, Task 6).
6. **The "every `omarchy-*` token resolves to a file" gate of spec section 8 is not workable**: on the untouched upstream tree it reports 110 false positives (PAM service names, CSS ids, window classes, unit names). 2A replaces it with the narrower dropped-reference gate, which has none. The spec and audit are updated to match.

## What Phase 0 added (2026-09-21, `docs/research/phase-0-findings.md`)

- **2F:** the GNOME invariant is met by a separate dconf profile for the session, not by save/restore (spec 4.9); the five upstream user units get their `[Install]` stripped at build and are started by `tinkero-provision --session`; `omarchy-fcitx5.service.d/tinkero.conf` adds a condition and a start limit; the autostart restore entry is gone.
- **2B:** `omarchy-pkg-add` and `omarchy-pkg-drop` use `pkexec` inside a graphical session (spec 4.3): an agent cannot answer `sudo` in its own terminal.
- **2B, `tinkero.spec.in`:** require `ppd-service` instead of `power-profiles-daemon` (Fedora 44 ships `tuned-ppd`); add `fcitx5` to the hard requirements.
- **Phase 1:** drop the `Recommends: nwg-panel wofi playerctl newt` that the omedora-4 specs carry.
- **2E:** seed the Tinkero dconf database from GNOME's at provisioning; `--reset dconf`; removal deletes it. README and `host.md` explain Hyprland Safe Mode after a crash.
- **Bare metal, later:** suspend-to-lock timing; a dead-menu-entry pass (2C removes most by construction).

## What executing 2A added to the queue

From the task reviews and the final review of 2A. Each is owned by the plan named.

- **2C:** the arch-leak entry for `omarchy-menu.jsonc` is caused by the `learn.arch` row (an Arch wiki web-app link, line 43), which the audit's delete list did not cover. It is on the list now (audit, section 7); 2C must delete it.
- **2B, needs an audit verdict first:** `config/autostart/limine-snapper-notify.desktop` (a `Hidden=true` mask for an Arch-only autostart entry; inert, invisible to the content-based gate), `bin/omarchy-dev-add-migration` and the other `omarchy-dev-*` developer scripts that still ship while `migrations/` is dropped.
- **2B:** `omarchy-version` now prints `VERSION-RELEASE` with the dist tag (`4.0.4-1.fc44`), and the About screen shows it. Decide whether the About line wants the bare tag.
- **Phase 1:** the COPR's font package must be named `tinkero-nerd-fonts` (the spec template requires it by that name), or the template line is renamed then.
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
