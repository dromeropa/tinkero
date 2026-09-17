# Tinkero design spec: critical review

**Reviewed:** `docs/superpowers/specs/2026-09-17-tinkero-design.md` (209 lines, the only specification document in the repo; there is no `docs/spec.md` or `docs/design.md`, and `master` is the only other branch and is identical).
**Read alongside:** `docs/research/omarchy-research.md`, `README.md`, `upstream.lock`.
**Review date:** 2026-09-17.
**Citation style:** `spec §4.3 L68` means section 4.3, line 68 of the spec file; `research §3.2 L258` likewise for the research doc.

**Basis of this review.** The first pass was a desk review of the documents in this repo. A second pass (same day, at the author's request) verified the open upstream questions against a shallow clone of `omacom/omarchy` at tag `v4.0.4` (commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5`), plus `dnf repoquery` on a Fedora 44 host, the COPR API and the herdr GitHub releases. The tree was read, never executed. Results are in section 8, and each affected finding carries a **Verified** note. Citations of the form `upstream path:line` refer to that clone. One consequence worth knowing up front: the research doc studied branch `quattro` HEAD, not the tag the spec pins, and they differ in ways that matter (script count, agent roster, skill directories, the Claude browser-extension hook).

**Disposition.** This review is of spec revision 1 (commit `d4c01c7`); line citations refer to that revision. Spec revision 2 and `docs/research/arch-coupling-audit.md` were written in response. How each finding was handled is in the table at the end of this document (section 11).

---

## 1. Verdict

The spec is a good *architecture decision record* and a weak *build specification*. The shape (vendor the pinned tree, replace the Arch substrate, keep the patch set tiny, push differences into shims, a menu extension and skill guides) is coherent, well argued, and grounded in a genuinely careful research doc. The decision log (§9) is the strongest part.

A developer could start Phase 2a (the COPR) from it today. They could not build Phase 2b or Phase 3 without a follow-up conversation, for four reasons:

1. **The shim inventory is asserted, not derived.** "Everything else in `bin/` ships unmodified" (spec L79) covers more than 420 of the 444 scripts at the pinned tag, none of them audited, and the research doc already names Arch-coupled pieces that the shim table misses (findings B1 to B3).
2. **The pinning mechanism contradicts the maintenance promise.** `dnf versionlock` on each machine is incompatible with "Weekly: `sudo dnf upgrade` and `mise up`. Nothing else" as soon as `upstream.lock` is bumped (finding B4).
3. **The config lifecycle is missing.** Migrations are a non-goal, but nothing replaces them, and the first user of the system is an *existing* user whom `/etc/skel` does not reach (finding B5).
4. **There is no security section at all**, in a design whose headline feature is an agent launched in permission-bypass mode from a timer-driven notification, installed by `curl | bash` (finding B6).

Verification against the pinned tag (section 8) added two more: the system-level menu extension that §4.4 relies on does not exist upstream (H10), and upstream's own first-run provisioning will fire at first login and rewrite shared user state, including GNOME's, unless Tinkero neutralises it (H11). It also cleared one suspected blocker (B2).

There is also one framing problem: the research doc the spec cites as its basis concludes "**Do not port the Omarchy desktop to Fedora**" (research §4.6 L413), and the spec never says why that recommendation was overruled or what answers its three objections (finding H1).

None of this is fatal. Most of it is a day or two of spec work plus one classified audit of the upstream tree, for which B3 now has the first-cut numbers. Section 9 lists the questions that block implementation; section 10 proposes the order to fix things in.

### Findings at a glance

| ID | Severity | Finding | Spec location |
|---|---|---|---|
| B1 | Blocker | Menu package guards bypass the `omarchy-pkg-present` shim (`pacman -Q` snapshot in `MenuModel.js`) | §4.3 L68, §4.4 |
| B2 | ~~Blocker~~ Low (resolved by verification) | `$OMARCHY_PATH/bin` is first on `PATH`; harmless if Tinkero keeps upstream's symlink layout, which the spec should state | §4.2 L49-50, §4.3 |
| B3 | Blocker | "Everything else ships unmodified" is unaudited; known coupled scripts are missing from the table | §4.3 L79 |
| B4 | Blocker | `dnf versionlock` contradicts "dnf upgrade, nothing else" and duplicates what RPM `Requires` does better | §4.6 L96, §4.7, §7 L162 |
| B5 | Blocker | No config lifecycle: existing users, non-overwrite seeding, tree bumps without migrations | §3 L28, §4.2 L51, §4.6 L98 |
| B6 | Blocker | No security/threat model (unattended agent, prompt injection via upstream notes, `curl \| bash`, mutable tag) | whole doc |
| B7 | Blocker | `mise` has no install path; Fedora does not package it and the COPR list omits it | §4.1 L41-43 |
| H1 | High | Spec overrules its own research's recommendation without rebuttal | §10 L205 |
| H2 | High | "Hyprland requirement" of an upstream release is not machine-derivable | §4.7 L110, L114 |
| H3 | High | `tinkero-status` runs as a user timer but needs root for `ausearch` | §4.7 L110-112 |
| H4 | High | Quickshell/Qt private-ABI coupling makes Fedora Qt updates a recurring rebuild chore | §7 L166 |
| H5 | High | GNOME coexistence is the safety net but is never specified or tested | §7 L169 |
| H6 | High | "Downgrade a package" recovery probably is not available from a COPR | §7 L169 |
| H7 | High | No dependency manifest; §4.1 lists packages Tinkero does not use and omits ones it needs | §4.1 L39-41 |
| H8 | High | No test or acceptance strategy beyond manual milestones; goal 2 (plugins) has no milestone | §6 |
| H9 | High | `upstream.lock` is underspecified as a "contract" (no commit SHA, not shipped, dual source of truth) | §4.8 |
| H10 | High | The menu has no system-level extension path; §4.4's mechanism does not exist upstream (found by verification) | §4.4 L83 |
| H11 | High | Upstream's first-run provisioning runs automatically at first login and rewrites shared user state (found by verification) | §4.6 L98 |
| M1-M12 | Medium | Build mechanics, PAM ownership, install flow, herdr, roster, uninstall, portability claim, etc. | various |
| L1-L7 | Low | Phase numbering, RPM Fusion rationale, naming, minor wording | various |

---

## 2. Blockers

### B1. The menu's package guards do not go through the shim

Spec §4.3 L68 shims `omarchy-pkg-present` to `rpm -q` with a name map, and §4.4 relies on the menu's `when`/`checked`/`disabled` guards. But the research doc says those guards are "evaluated from one `pacman -Q` snapshot in `shell/plugins/menu/MenuModel.js`" (research §3.2 L258), and lists "The menu's package guards need a `pacman -Q` to `rpm -qa` shim" as a required item (research §4.1 L348). That is a patch to QML/JS inside `shell/`, not a replacement script, and it is absent from the spec's shim table, which claims to be "the whole patch set" (L62).

Consequences: on Fedora `pacman` does not exist, so either every `installed`-style guard evaluates false (Install entries never show as installed, Remove entries never appear) or the menu model errors at load. Either way Milestone B ("menu ... work", L156) cannot be met by the spec as written.

**Verified (confirmed, and worse than the research suggests).** `guardHelpers()` in `upstream shell/plugins/menu/MenuModel.js:410-423` builds the package set from `pacman -Qq` plus `pacman -Qi` provides, and then *defines bash functions named `omarchy-pkg-present` and `omarchy-pkg-missing`* for the guard batch. Those functions shadow the real commands, so the spec's `/usr/bin/omarchy-pkg-present` shim is never reached from the menu. With no `pacman`, the set is empty: every `present` guard is false and every `missing` guard true. The default menu has 333 entries, 90 under `install.*` and 59 under `remove.*`, with 64 package-guard uses. `MenuModel.js` is the only file under `shell/` that touches pacman, so this is one contained patch.

**Needed:** add the `MenuModel.js` patch to §4.3; specify what it emits (a name-mapped `rpm -qa --qf '%{NAME}\n'` translated *back* into Arch names, since the menu JSONC guards use Arch names); note that this is a true patch and therefore a rebase cost on every tag bump.

### B2. PATH precedence can silently defeat every shim (resolved by verification; now Low)

**Verified (risk does not materialise if upstream's layout is kept).** `upstream docs/file-layout.md:56-57` maps `bin/omarchy-*` to `/usr/bin/omarchy-*` "and symlinks in /usr/share/omarchy/bin/". `upstream default/hypr/envs.lua:30-36` does prepend `$OMARCHY_PATH/bin`, and `bin/omarchy-provision-user` does the same, but with the tree's `bin/` being symlinks to `/usr/bin` there is only one copy of each script. The remaining action is small: the spec should state this layout (it is option (a)/(b) below with symlinks), build the symlinks *after* shims are swapped in, and keep the build-time assertion. The original analysis is kept for the record.

Spec §4.2 installs the tree at `/usr/share/omarchy` (L49) *and* "the `omarchy-*` commands on `PATH` (`/usr/bin`)" (L50). The research doc records that `default/hypr/envs.lua` "puts `$OMARCHY_PATH/bin` first on `PATH`" (research §1.3 L60). If `/usr/share/omarchy/bin/` exists in the installed tree with upstream's original scripts, then inside the Hyprland session the original `omarchy-pkg-add` (pacman) shadows the shimmed `/usr/bin/omarchy-pkg-add` (dnf). Every keybinding and shell IPC call runs inside that environment.

The spec never says which of these layouts it means:

- (a) scripts live only in `/usr/bin`, and `/usr/share/omarchy/bin` is absent or a symlink to `/usr/bin`;
- (b) scripts live in `/usr/share/omarchy/bin` (shims overwrite originals in place during `%install`) and `/usr/bin/omarchy-*` are symlinks;
- (c) both exist independently (broken).

**Needed:** pick (b) or (a) explicitly, say how upstream's own PKGBUILD lays it out (the research doc does not record this), and add a build-time assertion that no script name exists in two places with different content.

### B3. "Everything else in `bin/` ships unmodified" is an unaudited claim

Upstream has 458 `bin/omarchy-*` scripts at `quattro` HEAD (research §1.7 L132); **at the pinned tag `v4.0.4` the count is 444**, 38 of them `omarchy-install-*` (the research says 40). The shim table covers about 20 by name. The research doc itself lists Arch-coupled items that the table does not mention:

- **`omarchy-install-chromium-claude`**, which per the research `omarchy-default-agent` runs automatically when the chosen agent is `claude` (research §2.3 L175, §3.4 L327). **Verified: not applicable at the pinned tag.** The script does not exist at `v4.0.4` and `omarchy-default-agent` has no browser hook there; it arrived on `quattro` afterwards (the HEAD commit the research studied is the "claude-browser-extension" merge, research §0 L9). It becomes a Milestone A hazard at the first lock bump, so it belongs in the bump checklist rather than the initial shim table.
- **The `omarchy-install-*` scripts** (38 at the pinned tag, 40 at HEAD; research §1.7 L136, §3.2 L258). The spec's last table row marks "`omarchy-install-*` for Arch-only apps" as "not installed" (L77) without enumerating which are Arch-only, which are remapped, and which ship as-is. Removing a script while its menu entry or keybinding remains produces a dead entry; the menu extension (§4.4) has to be kept in lockstep with this list, and nothing says so.
- **`omarchy-install-hermes-cli`** gates on `omarchy-pkg-present hermes-desktop`; **`omarchy-install-openclaw-cli`** installs a pacman package (research §2.2 L171, §3.4 L326).
- **`omarchy-webapp-install`** (research §1.7 L136), **`omarchy-launch-webapp`** (research §1.2 L34) and the web-app keybindings (research §1.4 L80). Web apps are a non-goal (spec L29), but the bindings ship in `default/hypr/bindings/applications.lua`. The spec should say whether the seeded user config sets `omarchy_preinstalled_bindings = false` (research §1.3 L51) or leaves a dozen chords bound to commands that fail.
- **`omarchy-provision-first-run`** is run from `autostart.lua` on every session start (research §1.2 L35). What it executes on Fedora, given that `install/` is "not installed ... beyond what `tinkero-provision` reuses" (spec L58), is undefined. **Verified: it runs the whole upstream user-provisioning chain; this became finding H11.**
- **`omarchy-migrate-notify`** is in upstream's enabled-units list (research §1.2 L36). The spec's list (L98) silently drops it, which is correct, but the unit file still ships from `default/systemd/user/` (L55) and the omission should be deliberate and stated.
- **Firmware update, snapshot, Limine, plymouth, `mkinitcpio`, `yay`, `expac`** callers anywhere else in `bin/`, `shell/`, `default/` and the menu JSONC.

**Verified: first-cut audit numbers at `v4.0.4`.** Grepping for `pacman|yay|paru|expac|makepkg|limine|mkinitcpio|snapper|ufw|pkgs.omarchy.org|archlinux|checkupdates|paccache|pactree`:

| Directory | Files with direct hits |
|---|---|
| `bin/` | 50 of 444 |
| `shell/` | 1 (`plugins/menu/MenuModel.js`, see B1) |
| `default/` | 12 (pacman confs, Limine conf, the libalpm hook, `omarchy-migrate-notify.service`, the menu JSONC, two skill files, `launcher.hides`, the icon-font `README.md`, a comment in `input.lua`) |
| `config/` | 1 (a sample hook) |
| `install/user/` | 0 direct (but see H11: the scripts there call coupled commands) |

Separately, 66 `bin/` scripts (10 of which are also in the 50) call the `omarchy-pkg-*` wrappers and so depend on the shims and the name map being right. Of the 50 direct-hit scripts, **31 are not covered by any row of the spec's shim table**: `omarchy-pkg-missing`, `omarchy-pkg-remove`, `omarchy-pkg-drop`, `omarchy-reinstall-pkgs`, `omarchy-reinstall-configs` (calls `omarchy-refresh-limine`), `omarchy-refresh-pacman`, `omarchy-refresh-limine`, `omarchy-update-available`, `omarchy-update-keyring`, `omarchy-update-pkg-prune`, `omarchy-update-restart`, `omarchy-version`, `omarchy-version-pkgs`, `omarchy-migrate`, `omarchy-upgrade-to-quattro`, `omarchy-provision-owner`, `omarchy-snapshot`, `omarchy-system-factory-reset`, `omarchy-system-factory-reset-finish`, `omarchy-hibernation-{available,setup,remove}`, `omarchy-setup-security-fingerprint` (runs `sudo pacman -S ... libfprint-git fprintd`), `omarchy-setup-security-sshd`, `omarchy-remove-security-sshd`, `omarchy-remove-service-sunshine`, `omarchy-remove-launcher-entry`, `omarchy-remove-dev-env`, `omarchy-upload-log`, `omarchy-dev-pkg-test`, `omarchy-default-agent` (comment only, harmless). `omarchy-pkg-missing` and `omarchy-pkg-remove` are the important omissions: the first is the mirror of `omarchy-pkg-present` and is used by guards and installers, the second backs the whole `remove.*` menu. So the seam is about 2.5 times the size the spec's table implies, though most of the additions are *drop* or *hide*, not *patch*. This grep is a first cut, not the classified audit; that is still needed.

**Needed (this is the single most valuable pre-implementation task):** a scripted audit of the pinned tree, committed as `docs/research/arch-coupling-audit.md`, that greps `bin/`, `shell/`, `default/`, `config/` and `install/user/` for `pacman|yay|paru|expac|makepkg|limine|mkinitcpio|snapper|ufw|pkgs\.omarchy\.org|archlinux` and classifies every hit as *shim*, *patch*, *drop*, *hide in menu*, or *harmless*. The same grep then becomes a CI gate on the built RPM (see H8). Until it exists, the size of Phase 2b is unknown, and the "kept tiny" claim in the §4.3 heading is a hope.

### B4. `dnf versionlock` contradicts the maintenance model, and RPM already has a better tool

The spec's hard constraint is that updates stay `dnf upgrade` plus `mise up` (L17) and "Weekly ... Nothing else" (L106). The pinning mechanism is `dnf versionlock add hyprland quickshell` executed per machine by `install.sh` (L96, L162, decision log L192). Walk through a lock bump:

1. The author bumps `upstream.lock` to a tag that needs Hyprland 0.57; the COPR rebuilds `tinkero` and `hyprland`.
2. On every machine, `dnf upgrade` upgrades `tinkero` (new Lua config) and **holds `hyprland` at 0.56.2** because of the local versionlock.
3. The desktop now runs a new config against an old compositor, which is exactly the failure the lock was meant to prevent, inverted. Recovery needs a manual unlock/relock on each machine ("unlock and bump", L107), or a rerun of `install.sh`, which §4.6 only vaguely allows ("safe to rerun after upgrades", L94).

Other problems with the mechanism:

- It locks only two packages. The Hyprland stack is a dozen ABI-coupled libraries (L41). A COPR rebuild of `aquamarine` or `hyprutils` with a soname bump either breaks the locked `hyprland` or blocks the whole `dnf upgrade` transaction.
- The author owns the COPR. A versionlock protects against a repository the user does not control; here the only party who can push a surprising Hyprland is the author.
- `upstream.lock` says `quickshell=0.3.0` (L124) but the package version is `0.3.0^20.git28771c7` (research §3.3 L283); the versionlock pattern that matches is unspecified.
- It is per-machine state outside RPM, so it is not removed by `dnf remove tinkero` and is invisible to anyone else who installs Tinkero.

**Recommended replacement:** express the pin as RPM metadata in `tinkero.spec`, generated from `upstream.lock` at SRPM time, for example `Requires: hyprland >= 0.56.2, hyprland < 0.57` and `Requires: quickshell = 0.3.0^20.git28771c7` (or a `Provides: quickshell(commit) = 28771c7` handshake). Then a tree bump and a compositor bump land in the *same* dnf transaction or not at all, no machine-local state exists, the "whether the versionlock holds" check in `tinkero-status` disappears, and the promise on L106 becomes true. If versionlock is kept anyway, the spec must define who updates it on a bump and how.

### B5. The config lifecycle is missing

Three separate gaps that compound:

**(a) The first user is an existing user.** `/etc/skel` seeding (L51) only affects accounts created after the RPM is installed. The author's account, and every realistic early adopter's, already exists. So `tinkero-provision`'s "seeds `~/.config` from the packaged defaults without overwriting existing files" (L98) is the real path, and it is one sentence. Unspecified: what happens when `~/.config/alacritty/`, `kitty/`, `tmux/`, `nvim/`, `starship.toml`, `foot/`, `btop/`, `git/`, or `~/.bashrc` already exist (partial Omarchy config layered on a foreign one is likely worse than either); whether the granularity is per file or per directory; whether there is a dry-run or a plan display (Omedora "shows a plan and asks", research §3.5 L334); whether a backup is taken; how `~/.bashrc` integration happens at all (research §4.4 L397 step 4 shows it is a manual choice upstream).

**(b) `/etc/skel` is global.** On a multi-user machine, every new account, including ones that will only ever use GNOME, gets Omarchy's shell rc, Hyprland and terminal configs. That is a surprising side effect for something that promises to keep the host's conventions (README L15). Consider not touching `/etc/skel` at all and making `tinkero-provision` the only seeding path; it is needed anyway, and one path is easier to reason about than two.

**(c) Tree bumps without migrations.** "No migrations" is a non-goal (L28), and the research doc explains why (121 pacman-shaped scripts, research §4.1 L352). But upstream uses migrations to fix up *user* config when defaults change shape, and back-fills new skills the same way (research §2.5 L206). After a lock bump, files under `~/.config` seeded from the old tag are never touched again. The spec's only nod is that `tinkero-status` reports "any config migration notes" (L110) with no definition of where those notes come from, who writes them, or what format they take. This is the hidden hard problem of the vendoring approach: the tree is pinned, but user state is not versioned against it.

**Needed:** a short "Config lifecycle" section that defines: the seeding algorithm and conflict policy; a recorded `seeded_from_tag` marker in `~/.local/state/tinkero/`; what `tinkero-provision` does on rerun after a bump (re-link skills, report files whose packaged default changed since the seeded tag, never overwrite); and the release-bump checklist item "read upstream `migrations/` added between old and new tag, classify as config-only / Arch-only, write the config-only ones into `maintenance.md` notes".

### B6. There is no security or threat model

The spec has no security section. The design includes, by intent:

- **An agent launched in permission-bypass mode by design.** `omarchy-agent` uses each harness's "don't stop to ask" flag (`--dangerously-skip-permissions`, `--yolo`, `--allow-all`, `bypassPermissions`; research §2.3 L178-193). That is upstream's choice and the author may want it, but the spec should state the accepted risk, particularly because Tinkero *adds a new trigger*:
- **A timer-driven path from untrusted text to that agent.** §4.7 L110-112: a weekly timer runs `tinkero-status`, which fetches the newest upstream tag "with that release's ... config migration notes", and on anything actionable sends a notification whose click "launches the default agent with the maintenance skill". If release-note text from GitHub flows into the prompt, this is a prompt-injection channel from a third-party repository into an unattended agent with shell access, and `maintenance.md` explicitly authorises some actions "unattended" (L112). **Needed:** `tinkero-status` output passed to the agent must be structured facts generated locally (versions, booleans, counts), never fetched prose; fetched text is shown to the human only.
- **`curl | bash` as the install entry point** (L100), from a branch head, enabling a third-party COPR and RPM Fusion and running `sudo`. No pinning to a tag, no checksum, no "show plan and confirm" step. For a project meant as "a base others can build on" (L19) this needs at least: install from a tagged release URL, print the plan, require confirmation unless `--yes`.
- **A mutable supply-chain pin.** `upstream.lock` pins `omarchy_tag=v4.0.4` (L121). Git tags are mutable; the lock records a commit for Quickshell (L123) but not for Omarchy itself. **Needed:** add `omarchy_commit=` and a tarball `sha256=`, verified in `tinkero.spec`.
- **Trust boundary of the `tinkero` RPM.** It installs ~460 third-party scripts into `/usr/bin` as root-owned files that user sessions execute, plus a PAM service file. The spec should say that patches are reviewed per bump and how (diff of upstream between tags is the review artifact).
- **SELinux posture.** "SELinux enforcing" is a stated goal (L11), but the only treatment is "check denials" (L89) and "budget a day" (L164). State the rule: Tinkero ships no policy module and never sets permissive domains or booleans; if the lock screen cannot authenticate under the targeted policy, that is a stop-and-redesign event, not a `setsebool`.
- **Privacy notes worth one line each:** the usage collector reads agent OAuth credentials and transcripts under `~/.claude` (research §2.6 L223); voxtype is a dictation tool, so it captures microphone audio and presumably fetches a speech model (neither document describes its data handling; check before shipping it by default).

### B7. `mise` has no install path

§4.1 L43 and §4.6 L98 make mise the delivery mechanism for herdr and every agent CLI, and "`mise up`" is half of the maintenance contract (L17). But mise is not in Fedora main (research §3.3 L294: "mise-bin ... no"), and the spec's COPR package list (L41) does not include it; the research names `omedora-4`, `b00ga/mise`, or the upstream installer as options (research §3.4 L317). Milestone A depends on it.

**Needed:** decide (package `mise` in the Tinkero COPR, which keeps it under `dnf upgrade`, is the consistent answer; mise also publishes its own RPM repo, which is a lower-effort alternative), add it to §4.1 and Phase 2a, and make it a `Requires:` of `tinkero`.

---

## 3. High-severity findings

### H1. The spec overrules its research without saying why

Spec §10 L205 cites research "4.6 ... the recommendation that led here". Research §4.6 L413 says: "**Do not port the Omarchy desktop to Fedora.** Either migrate to Omarchy, or stay on Fedora and take only the agent layer", and calls the middle path "the worst option" for three reasons (L417-419): the porter becomes the maintainer of every seam; the Hyprland stack on Fedora lives in one-person COPRs; and a port gets Omarchy's churn without Omarchy's rollback.

Tinkero is that middle path, with the one-person COPR now being the author's. That can be a perfectly good decision (owning the specs, pinning rather than tracking, GNOME as fallback are real answers to two of the three objections), but the spec must *make the argument*. As written, a reader who follows the reference finds the project's own research arguing against the project. This matters beyond rhetoric: the "low maintenance" hard constraint (L17) is precisely what the research says the port cannot deliver, and the spec's maintenance model (§4.7) undercounts the work (see H4 and section 6).

**Needed:** a short §1.1 "Why this overrides the research recommendation", answering each objection, with an explicit statement of the maintenance budget the author accepts (hours per month, and the abandon criteria if it is exceeded). Also fix the wording on L205.

### H2. An upstream release's "Hyprland requirement" cannot be derived mechanically

`tinkero-status` reports the newest upstream tag "with that release's Hyprland requirement" (L110); the GitHub Actions workflow opens an issue "with its Hyprland requirement" (L114); Phase 3's milestone depends on it (L157). But the research doc established that "The Omarchy tree carries no version guard ... the only version string in the tree is a test comment" (research §1.1 L27), and that upstream's own x86_64 Hyprland is simply whatever Arch `extra` ships (same paragraph).

So there is no field to read. Candidate proxies, all imperfect: `pkgver` in `omarchy-pkgs/pkgbuilds/hyprland/PKGBUILD` (aarch64-only recipe) at the commit nearest the tag; the Arch `extra` version on the tag date; release-note text. **Needed:** choose a proxy, accept that it is heuristic, and have the tooling say "upstream was built against Hyprland X (heuristic)" rather than "requires". Same for Quickshell: the `quickshell-git` pinned commit in `omarchy-pkgs` is a better-defined signal and should be tracked explicitly.

### H3. `tinkero-status` privilege model is inconsistent

§4.7 L112 runs `tinkero-status` from "a weekly systemd **user** timer". Its report (L110) includes "SELinux denials in the last seven days", and `fedora.md` (L89) names `ausearch -m AVC`, which reads `/var/log/audit/audit.log` and needs root. A user unit cannot do this non-interactively. Options: read setroubleshoot messages from the journal if the user is in `wheel`/`adm` or `systemd-journal`; split into a root system timer that writes a world-readable report plus a user notifier; or drop the check from the timer and leave it to the interactive run. Also unspecified: exit codes, a machine-readable mode (`--json`) for the agent, what counts as "actionable" (L112), network-failure behaviour, and whether the timer should fire at all when the user is logged into GNOME rather than Tinkero (the notification action calls `omarchy-agent` via `uwsm-app`, which assumes the Tinkero session).

### H4. Quickshell against Fedora's Qt is a recurring rebuild obligation

§7 L166 treats Quickshell only as "0.2.1 is too old; build the pinned commit". The larger risk is unmentioned: Quickshell is built against Qt private APIs (confirmed below), so a build is tied to the exact Qt version it was compiled against, and Fedora ships Qt minor-version updates inside a stable release. Each such update means either `dnf upgrade` is blocked by the COPR package's exact-version Qt dependency until the author rebuilds, or (if the dependency is loose) the shell breaks at runtime. Because bar, launcher, notifications, polkit agent *and lock screen* are one Quickshell process (spec L23), a broken Quickshell is a broken desktop, and a crash while locked leaves the session locked until a TTY login.

This directly contradicts "nothing under it is rolling" (L107): Fedora's Qt is. **Verified (confirmed with evidence).** On a Fedora 44 host, `dnf repoquery --requires quickshell` lists `libQt6Core.so.6(Qt_6.10_PRIVATE_API)`, and the same for `Gui`, `Qml`, `Quick` and `WaylandClient`, with a second build requiring `Qt_6.11_PRIVATE_API`. Fedora 44's repos carry both `qt6-qtbase-6.10.2-2.fc44` and `6.11.2-2.fc44`, and Fedora's own `quickshell` went from release `-1` to `-5` across that change. So Fedora 44 has *already* shipped a Qt minor bump inside the release, Quickshell had to be rebuilt for it, and RPM's generated symbol-version requires mean the failure mode for a stale COPR build is a blocked `dnf upgrade` (good) rather than a broken shell. The rebuild obligation on the author is real and has a precedent four months into the release.

**Needed:** add it to §7; have the weekly workflow detect a Qt version change in `updates-testing`/`updates` for the target Fedora and trigger a Quickshell rebuild (COPR can also auto-rebuild on a schedule); state the expected user-visible behaviour (upgrade held back, never a broken shell), which means the RPM must carry the strict Qt requirement.

### H5. GNOME coexistence is the safety net, and it is unspecified

§7 L169 rests the whole risk posture on "GNOME stays installed, and a broken Tinkero session is fixed by logging into GNOME". Nothing in the spec protects the GNOME session from Tinkero. Shared state that both sessions read: `~/.bashrc` and shell rc; `~/.config/gtk-3.0`, `gtk-4.0`, dconf/gsettings (theme switching fans out widely, research §1.6 L128); `mimeapps.list` and default-application choices; fcitx5 and input-method environment; `~/.config/environment.d` if anything lands there; fontconfig; `QT_QPA_PLATFORMTHEME`. `omarchy-theme-set` changing GTK colour scheme or icon theme would restyle GNOME too.

**Verified (confirmed).** `omarchy-theme-set` calls `omarchy-theme-set-gnome` on every theme switch, which runs `gsettings set org.gnome.desktop.interface color-scheme / gtk-theme / icon-theme` (`upstream bin/omarchy-theme-set-gnome:21-33`). Those are the same dconf keys the GNOME session reads, so every Tinkero theme change restyles GNOME. It also rewrites VS Code, VSCodium and Cursor `settings.json`, Obsidian vaults and browser theming unless per-app skip toggles are set. First-run provisioning does more of the same (H11).

**Needed:** an explicit invariant ("the GNOME session must be unaffected by installing, using, and removing Tinkero") plus an acceptance test for it, and an audit item: which paths `omarchy-theme-set` and `tinkero-provision` write that GNOME also reads. Session-scoped environment belongs in uwsm's `env.d` (already used, L53), not in user dotfiles.

### H6. "Downgrade a package" may not be possible from a COPR

L169 lists "downgrading or unlocking a package" as the recovery. COPR prunes superseded builds from the repository after a retention period by default, so the previous `hyprland` or `tinkero` RPM may not be available to downgrade to, and `dnf history undo` fails the same way. The research doc already flagged that a port "gets Omarchy's churn without Omarchy's rollback" (research §4.6 L419); the spec's answer is thinner than it looks. **Needed:** verify the COPR's retention setting and either disable pruning for the project, keep the last N builds attached to GitHub releases, or recommend keeping the dnf package cache (`keepcache=1`) for the Tinkero repo. State the actual rollback procedure in the spec.

**Verified (partly).** The COPR API reports `auto_prune: true` for `agaspar/omedora-4`, and it is a per-project setting (whether on is COPR's default for new projects was not checked); with it on, superseded builds are removed from the repo after COPR's retention window (14 days by this reviewer's recollection; the COPR documentation page could not be fetched to confirm the number). The Tinkero COPR project should turn `auto_prune` off, or accept that rollback past the window needs locally cached RPMs.

### H7. There is no authoritative dependency manifest

§4.1 L39 is a list of things "Fedora main already carries", not a list of what Tinkero requires, and the two are mixed up:

- It includes packages Tinkero explicitly does not use: `sddm` (not installed, L96), `plymouth` (theme not installed, L58), `snapper` (non-goal, L28), and the v3-era stack `mako`, `swaybg`, `waybar`, `wofi`, `cliphist` that Quattro replaced with the Quickshell shell (research §0 L18). `satty` is in the COPR list (L41) although v4 uses `tensaku` (research §1.5 L114).
- It omits packages the research found necessary: `gtk4-layer-shell`, `polkit`, `gnome-keyring`, `udiskie`, `brightnessctl`, `ddcutil`, `pamixer`, `power-profiles-daemon`, `socat`, `inotify-tools`, `qrencode`, `imv`, `mpv`, `tesseract-langpack-eng`, `qt6-qtsvg`, `lua`, `nautilus-python`, `fcitx5-gtk/qt`, `plocate` (research §4.3 L368-374), and `mise` (B7).
- `chromium` is listed, but web apps and the Chromium fork are non-goals (L29), and Fedora's default browser is Firefox. What does `Super+Shift+B` launch? Unspecified.

**Needed:** one table that *is* the `Requires:`/`Recommends:` list of `tinkero.spec`: package, source (Fedora / COPR / mise / Flatpak), hard or weak dependency, and which feature needs it. Weak dependencies matter: "pulls the whole stack as dependencies" (L96) will drag in three terminals and nautilus unless `Recommends:` is used deliberately.

### H8. No test or acceptance strategy

The only verification in the spec is five manual milestones (§6). For a project whose central risk is "an upstream bump silently reintroduces an Arch assumption", that is thin. There is no mention of CI for the RPM, of upstream's own test suite (`./test/all`, research §2.5 L212), or of how a lock bump is validated before it reaches the author's daily machine. Also, goal 2 ("Plugins", L14) and the agent-creates-plugins half of goal 3 (L15) have **no milestone at all**; Milestone B (L156) lists bar, menu, lock, screenshots and so on, but not `omarchy plugin add/clone/validate` or "the agent builds a working bar widget".

**Needed, in rough order of value:**

1. A CI "Arch-leak gate": build the RPM in mock, then grep the installed payload for the B3 pattern list against an allowlist. Fails the bump PR when upstream adds a new pacman call.
2. A consistency check: every command referenced by the effective menu (upstream JSONC plus the Tinkero extension) and by `default/hypr/bindings/*.lua` exists in the payload.
3. `shellcheck` on `shims/`, `bin/tinkero-*`, `install.sh`; `rpmlint` on specs.
4. A scripted VM smoke test (Fedora 44 cloud/Workstation image): install, provision a fresh user, start the session headless, assert `hyprctl configerrors` is empty and `omarchy-shell shell ping` answers (both from research §4.4 L401), assert zero AVC denials.
5. Written acceptance criteria per milestone, including plugin workflow and the GNOME-unaffected invariant (H5), and an idempotency test for `install.sh` (run twice, diff system state).

### H9. `upstream.lock` is called a contract but is not specified as one

§4.8 calls it "the contract every other piece checks". Gaps: no Omarchy commit SHA or tarball checksum (B6); no statement of format (it is shell-sourceable `key=value` today; say so, and say who parses it: spec file via macro at SRPM time, `install.sh`, `tinkero-status`, the workflow); **not shipped to the machine**, although `tinkero-status` compares installed versions against it (L110) and `install.sh` reads it (L96) when invoked via `curl | bash` with no checkout (it must be packaged, e.g. `/usr/share/tinkero/upstream.lock`); `hyprland=0.56.2` duplicates the `Version:` in `specs/hyprland.spec`, giving two sources of truth with no rule for which wins; `fedora=44` has no defined semantics (does `install.sh` refuse on 45? does it select the chroot?); no field for the Tinkero patch-set revision, so two builds of the same tag with different shims are indistinguishable. The RPM's own version scheme (`4.0.4^tinkeroN`? `Epoch`?) is also undefined, as is whether `tinkero` `Conflicts:` with Omedora's `omedora` package, which owns the same `/usr/share/omarchy` path (research §3.5 L334).

### H10. The system-level menu extension that §4.4 depends on does not exist upstream

Found by verification. §4.4 L83 says "Tinkero ships a system-level extension file" and that "Users' own extension files layer on top". At `v4.0.4` the menu loads exactly two JSONC sources: `defaultMenuPath` (`$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc`) and `userMenuPath` (`$HOME/.config/omarchy/extensions/omarchy-menu.jsonc`), each through one `FileView` (`upstream shell/plugins/menu/Menu.qml:50-51, 922-939`). There is no system-level extension lookup. The approach is still right, but the mechanism has to be chosen, and each option has a cost the spec currently claims to avoid:

- **Patch `Menu.qml`** to add a third source between default and user (about 15 lines of QML, mirroring the existing `FileView`). Clean layering, but it is a true patch to a busy upstream file, so it adds rebase cost, contrary to "avoids patching upstream JSON and survives every upstream release" (L83).
- **Rewrite the default JSONC at RPM build time** (apply Tinkero's overrides to `default/omarchy/omarchy-menu.jsonc` with a script in `%prep`). No QML patch and nothing to conflict textually, but hidden ids silently stop matching when upstream renames an entry, so it needs the H8 consistency check.
- **Seed the user file from `tinkero-provision`.** No patch, but it occupies the user's own extension file, collides with existing user content, and cannot be updated on a lock bump without merging.

Recommend the second, with the first offered upstream as a PR (a system extension path is generally useful to any port). With 90 `install.*` and 59 `remove.*` entries in the default menu (B1), the override file is also larger than §4.4 implies; it should hide by subtree where the merge semantics allow.

### H11. Upstream's first-run provisioning fires automatically and rewrites shared user state

Found by verification. §4.6 L98 describes `tinkero-provision` as the user-stage mechanism and L58 says `install/` is not installed "beyond what `tinkero-provision` reuses". But upstream's `default/hypr/autostart.lua` runs `omarchy-provision-first-run` at every session start (research §1.2 L35), and unless the marker `first-run-user` exists it runs the whole chain (`upstream bin/omarchy-provision-first-run:40-100`), starting with `omarchy-provision-user`. On an existing Fedora account, that chain would:

- `rmdir ~/Templates ~/Public ~/Desktop` and repoint those XDG user dirs at `$HOME` (`upstream bin/omarchy-provision-user:105-109`). These are GNOME's directories; `rmdir` only removes them if empty, but the XDG remap applies regardless.
- Set the default browser to `chromium.desktop` and the `mailto:` handler to `HEY.desktop` (`:119-120` of the same script), overriding the user's Firefox default in GNOME too.
- Run `gsettings set org.gnome.desktop.interface ...` for GTK theme, colour scheme, icon theme and primary paste (`install/user/first-run/gnome-theme.sh`, `gtk-primary-paste.sh`); see H5.
- Create an **unencrypted, never-locking `Default_keyring`** and make it the default keyring if no default is set (`install/user/default-keyring.sh`). An existing GNOME user normally has a default already, so it is a no-op for them, but a fresh account would store secrets in a passwordless keyring. That contradicts the spec's reason for keeping GDM ("GDM handles the login keyring", L164, L187) and is a security regression relative to stock Fedora.
- Run Chromium extension installers, ASUS/Dell/Framework hardware fixes, `git.sh`, `xcompose.sh`, `mise-work.sh`, install three `post-update` hooks (Voxtype invitation, fingerprint setup, agent setup), and send welcome and Wi-Fi/update notifications that point at `omarchy update`.
- Retry at every login if any step fails (`first-run will retry next login`), which on Fedora is likely, since several steps assume Arch.

If `install/` is not shipped, the same autostart line fails noisily at each login instead. Either way the spec must decide: `tinkero-provision` has to either mark `first-run-user` and `finalize-user` done (via `omarchy-done mark`) before the first session, or Tinkero has to replace `omarchy-provision-first-run` and `omarchy-provision-user` with its own versions and list them in §4.3. The second is safer, because the marker approach is one missed step away from running the upstream chain. Each upstream step then needs an explicit keep / adapt / drop decision in the spec; the keyring, default-browser, XDG-dirs and gsettings steps are the ones to drop or make opt-in.

---

## 4. Medium-severity findings

**M1. RPM build mechanics are described in a way COPR does not allow.** "`tinkero.spec` fetches the upstream Omarchy tag ... as a source tarball at build time" (L47). COPR/mock builds have no network during `rpmbuild`; sources are fetched when the SRPM is produced. Specify the COPR build method (SCM with `make srpm` is the natural fit, since it can read `upstream.lock`, download and checksum the tarball, and template the spec), and how "triggers COPR rebuilds when `upstream.lock` changes" (L114) authenticates (COPR webhook versus API token in GitHub secrets). Also say which packages rebuild on a lock change; only `tinkero` follows from the lock, the Hyprland stack follows from its own spec files.

**M2. The lock-screen PAM file should be RPM-owned, not script-written.** §4.3 L76 patches `omarchy-apply-lock` to write `/etc/pam.d/omarchy-lock-password`, and `install.sh` runs it under sudo (L96). A file written by a script is unowned, survives uninstall, and needs the bespoke "matches the template" check (L110). Ship the password service file in the RPM as `%config`; then `rpm -V tinkero` is the check and removal is clean. Only the fingerprint variant is dynamic, and there the spec is ambiguous: "only if `fprintd-list` shows enrolments" (L76), but for which user, given the script runs as root in the system stage? **Verified: upstream already resolves this** (`upstream bin/omarchy-apply-lock:15-19` uses `OMARCHY_INSTALL_USER`, then `SUDO_USER`, then `PKEXEC_UID`), so the patch only needs to keep that logic. Upstream's file is Arch-shaped as the spec expects (`pam_unix` stack written inline, `account include system-local-login`, which does not exist on Fedora). Note that the companion `omarchy-setup-security-fingerprint` runs `sudo pacman -S` directly and is missing from the shim table (B3). Also state the risk honestly in §7: the lock surface is a Quickshell `WlSessionLock` client authenticating via PAM from an unprivileged user process under SELinux; "budget a day" (L164) is plausible but there is no fallback named if it does not work (a candidate is `hyprlock`, which the research found only in the older `solopasha/hyprland` COPR, research §3.3 L301, so it would be one more spec to own).

**M3. Install flow underspecified.** §4.6: who invokes which stage (one script run as the user that calls `sudo` for stage one, or two invocations)? What does "idempotent, safe to rerun after upgrades" (L94) do concretely on rerun? What preflight checks exist (Fedora version equals `upstream.lock`, x86_64, Workstation with GDM present, SELinux mode, not-root for the user stage, existing Hyprland install from another COPR such as `solopasha/hyprland` or `omedora-4`, which would conflict)? What happens on partial failure? "about ten minutes" (L100) is unsupported. `flatpak install` targets (L69) assume a Flathub remote; Fedora Workstation may have only the Fedora remote or filtered Flathub, so specify whether `install.sh` adds it.

**M4. herdr via mise is asserted "exactly as Omarchy does it" (L43), but upstream does not.** **Verified:** at `v4.0.4` herdr is line 52 of `install/omarchy-base.packages`, a pacman package, and is not in `install/user/mise.sh`. herdr v0.9.1 does publish a `herdr-linux-x86_64` release binary, so a mise `github:` backend is feasible. The session-PATH concern below is largely answered: `upstream default/uwsm/env.d/10-omarchy` runs `mise activate bash --shims` when mise is present, so mise-installed tools are on the graphical session's `PATH` (that file also hardcodes `/usr/share/omarchy/default/bash/env-bootstrap`, which is fine for Tinkero's layout). The research says Omarchy builds herdr from source as a pacman package and lists it in base packages (research §2.4 L200). So the mise backend for herdr (`github:herdrdev/herdr` release binaries? `cargo:`?) is a Tinkero decision that nobody has verified, and the `Super+Ctrl+Return` binding (Milestone B) needs `herdr` on the *graphical session's* `PATH`, which means `~/.local/bin` stubs or mise shims must be in the uwsm environment, not only in interactive bash. Specify both. The research lists existing herdr RPM recipes (`omedora-4`, `rikatz/herdr`); packaging it in the COPR is the lower-risk option and keeps a core feature off a lazy network install.

**M5. The agent roster in the spec does not match the pinned tag.** **Verified:** `upstream install/user/mise.sh` at `v4.0.4` creates stubs for `codex`, `claude`, `crush`, `gemini`, `gh`, `copilot`, `opencode`, `playwright`, `pi`, `omp`, `grok`, `cursor-agent`, `ghui`, `hunk`, `muse`, and calls `omarchy-install-hermes-cli`; there is no `agy` and no `ori`. Likewise the skill fan-out at the tag covers five directories, not the six the spec lists on L98: `~/.gemini/config/skills` is absent from `bin/omarchy-provision-user` at `v4.0.4`. Both are symptoms of the spec being written from the research's HEAD reading rather than from the tag it pins. L43 lists `agy` and `ori`; the research says `agy` was renamed from `gemini` *after* v4.0.4 and `ori` was added *after* v4.0.4 (research §2.2 L171). Since the roster comes from the vendored tree, the spec should not enumerate it at all, only say "whatever `install/user/mise.sh` at the pinned tag creates". Note also that `hermes` is not a plain mise stub (pipx backend, research L171) and `openclaw` is a pacman package; both need a line in the shim table or the menu-hide list.

**M6. The package name map is a core artifact with no home.** Three shims depend on "a name map (Arch name to Fedora name)" (L68-69). §5's repo layout has no file for it. Define the path, the format (TSV: arch name, target kind `dnf|flatpak|mise|none`, target name), the initial contents (the research §3.3 table is most of it), and behaviour for privilege elevation (`sudo` in a terminal versus `pkexec` without one, which is what the upstream skill teaches, research §2.5 L208).

**M7. "Patch" versus "shim" is blurred.** §4.3's heading says "the whole patch set", the table mixes replacement scripts, in-place text patches (`SKILL.md`, `omarchy-agent-crash`, `omarchy-debug`, `omarchy-apply-lock`) and deletions, and §5 has separate `patches/` and `shims/` directories. Add a column: *replace / patch / drop*. Only "patch" rows carry rebase cost, and that count is the metric to keep small. With B1 added, the true patches are about six: the two `SKILL.md` files (L74, L75), `omarchy-agent-crash`, `omarchy-debug`, `omarchy-apply-lock`, and `MenuModel.js`.

**M8. No uninstall or rollback section.** What `dnf remove tinkero` leaves behind: the COPR and RPM Fusion repos, the versionlock entries, the script-written PAM file, `/etc/skel` content already copied into new users' homes, enabled user units pointing at removed files, skill symlinks in six harness directories (dangling), mise stubs in `~/.local/bin`. A `tinkero-provision --remove` plus a documented system teardown is cheap and is part of "nothing here can brick the machine".

**M9. The cross-distro claim is contradicted by the design.** Phase 4 says for Debian/Ubuntu "the tree and shims are the same, only the package substrate changes" (L158). The shims are `rpm -q`, `dnf install`, authselect-shaped PAM, Fedora's debuginfod URL, `rpm -qa` in `omarchy-debug`, and a skill guide literally named `fedora.md` wired into `SKILL.md` (L75). None of that is the same on Debian. Either soften the claim, or introduce the seam now while it is free: `distro/fedora/{shims,pkgmap.tsv,skills/host.md,pam/}` with the skill pointing at a neutral `host.md`. Given the tagline is "bring your own distro" (L3), the second is more honest, but it must not delay Phase 2.

**M10. Branding and trademark are treated as a patch-size question only.** Open question 2 (L174) frames keeping "Omarchy" strings as a matter of patch-set size. A *public* project that ships a desktop presenting the Omarchy name, logo font (`omarchy.ttf`, L56) and screensaver branding to users is also a trademark and attribution question. MIT covers the code, not the marks. Check upstream's stance before the repo attracts users, and record the answer in the decision log. Also check that every COPR package meets COPR's licensing rules (the voxtype model download and any bundled binaries are the ones to look at).

**M11. Hardware and architecture scope is unstated.** x86_64 only is implied by the COPR chroot (L155) but is not listed in non-goals. NVIDIA appears only as a line in `fedora.md` (L89). State: x86_64 only; NVIDIA is documented-but-unsupported or supported; minimum GPU expectations for the Quickshell shell; HiDPI and multi-monitor are "as upstream".

**M12. `fedora.md` guidance conflicts with the core skill rule.** L89 tells the agent to "run `restorecon -R` after copying into `/usr`", while the `omarchy` skill's first rule is never to modify `/usr/share/omarchy` and to write only under `~/.config` (research §2.5 L208; spec L49 endorses this). RPM labels its own files, so the agent has no reason to copy anything into `/usr`. Drop that line or restrict it to a human-run troubleshooting note. More generally, the two skill guides are described by a sentence each; `maintenance.md`'s safe/unsafe action table is the actual specification of unattended agent behaviour and deserves to be written out in the spec (it is a policy decision, not documentation).

---

## 5. Low-severity findings

- **L1. Phase numbering.** §6 starts at "Phase 2a"; "Phase 1" is referenced (L153) but never defined in this document (it is the research's "agent layer under GNOME first" suggestion, research §4.6 L423-425). Either define Phase 1 in a sentence or renumber.
- **L2. RPM Fusion is enabled unconditionally with no rationale** (L96). The only stated use is NVIDIA (L89). Enabling a third-party repo is a host-policy change; make it conditional on NVIDIA hardware or on an explicit flag, or state what else needs it (codecs for `gpu-screen-recorder`?).
- **L3. GDM will show extra sessions.** The `hyprland` package ships its own session files, so GDM will list "Hyprland" (and possibly a uwsm variant) beside "Tinkero". Harmless, but say whether they are hidden; a user who picks plain "Hyprland" gets a session without the uwsm environment and a confusing half-working desktop.
- **L4. `OMARCHY_PATH` export is redundant by the spec's own account** (L49 says it defaults to `/usr/share/omarchy`; L53 exports it anyway). Fine to keep for explicitness; say so.
- **L5. "Not installed: `install/` beyond what `tinkero-provision` reuses"** (L58) is not a list. Enumerate (`install/user/mise.sh`, `install/user/theme.sh`, ...).
- **L6. Open question 4 (default branch name)** is not a design question; decide and delete. Open question 1 (FAS account) is a task, not a question.
- **L7. "A pinned tree does not rot"** (L107) is true of the tree and false of its environment (Qt, PipeWire, portals, agent CLI flags in the unattended-launch table, which upstream changes between releases as harnesses rename their flags; research §2.3). Worth one honest sentence in §7: a pinned `omarchy-agent` may stop launching an agent whose CLI changed under `mise up`.

---

## 6. Scope, MVP and gold-plating

**Scope coherence: good.** The non-goals (§3) are sharp and the "desktop core" boundary (decision log L188) matches the three goals. Two edges are fuzzy: the browser/web-app story (H7, B3) and how much of `install/` is reused (L5).

**MVP definition: implicit and slightly mis-ordered.** The real MVP is Milestones A and B on the author's one machine. The spec never says so, and it sequences four weeks of plumbing before the first moment the author learns whether the desktop even runs well under Fedora + SELinux + GDM. The research doc's Path A assembly (research §4.4) offers a nearly free de-risking step that the spec skips: **enable the existing `agaspar/omedora-4` COPR in a VM, check out the tree with `OMARCHY_PATH` exported, and try to reach Milestones A/B by hand before forking a single spec.** One or two days; it validates the lock-screen PAM, SELinux, GDM-session and Quickshell questions, produces the B3 audit as a by-product, and turns "budget a day" guesses into facts. Decision log L201 ("COPR first, builds are the long pole") is reasonable for the *author's time*, but COPR builds run unattended; the spike can proceed in parallel. Recommend adding it as "Phase 2.0, spike".

**Under-scoped:** Phase 2a. "Fork ~25 specs and get green builds" reads as mechanical, but it makes the author the Fedora packager of the entire Hyprland stack, including CVE response, Fedora mass-rebuild fallout, and the Qt coupling (H4). The realistic recurring cost is not "weekly: nothing" (L106) but "a few hours a month, spiky around Qt updates, Hyprland releases and Fedora branch points". Say that, and set the abandon criteria (H1). A middle option deserves a line in the decision log: consume `omedora-4` for the compositor stack initially and fork only when it lags, which is the opposite of the "not blocked by a one-person beta" rationale (L190) but defers 80% of Phase 2a until the desktop is proven.

**Candidates to cut or defer from the first release:**

| Item | Where | Why defer |
|---|---|---|
| `tinkero-status` COPR-next-chroot check, `mise outdated`, pending-dnf-updates report | §4.7 L110 | dnf and mise already report these; keep only the checks nobody else makes (lock drift, new upstream tag, AVC denials, PAM drift) |
| Notification-to-agent maintenance advisor | §4.7 L112 | Attractive, but it is the riskiest new surface (B6) and depends on H2/H3 being solved. Ship `tinkero-status` as a manual command first |
| `dnf versionlock` | §4.6 | Replace with RPM requires (B4); removes code from `install.sh` and `tinkero-status` |
| `/etc/skel` seeding | §4.2 L51 | `tinkero-provision` is needed anyway; one path (B5b) |
| Remapping AI desktop apps to Flatpak | §4.4, open question 3 | Hide them all in v1; add back on demand |
| `satty`, and the v3-era packages in §4.1 | L39-41 | Not used by the v4 tree (H7) |
| Cross-distro anything | Phase 4 | Keep the ambition in the tagline; keep the seam cheap (M9); do no other work |

**Not gold-plated, keep:** the menu-extension approach (§4.4) is the best idea in the document. Verification showed that upstream has no system-level extension path, so the delivery mechanism needs a decision; see H10.

---

## 7. Section-by-section notes

| Spec section | Assessment |
|---|---|
| Header, §1 Problem and goals | Clear and well motivated. Goals are not phrased as testable outcomes; goal 2 and half of goal 3 never reappear in milestones (H8). "Low maintenance" is the hard constraint and is never quantified (H1). |
| §2 One paragraph | Accurate summary. "Does not rewrite any of that" is slightly too strong once B1 (a QML/JS patch) is counted. |
| §3 Non-goals | Strong. Add: non-x86_64, NVIDIA support level, multi-user machines, SELinux policy changes, SDDM. "Hidden or remapped" (L29) needs the list. |
| §4.1 COPR | Right approach; list is not a manifest (H7); `mise` missing (B7); Qt coupling missing (H4); retention/rollback missing (H6). |
| §4.2 RPM | Build mechanics wrong for COPR (M1); bin layout should be stated, upstream uses symlinks (B2); skel is global (B5b); versioning and conflicts undefined (H9). |
| §4.3 Shims | Incomplete by the research's own inventory (B1, B3); needs replace/patch/drop column (M7) and the name map (M6). |
| §4.4 Menu extension | Best idea in the doc; the system-level path it assumes does not exist upstream (H10). Must be kept in lockstep with dropped scripts (B3). |
| §4.5 Skill guides | One-sentence descriptions of what are really policy documents; one instruction conflicts with the core skill (M12). Missing: how skills are re-linked after a tree bump adds a new skill (upstream used migrations for this, research §2.5 L206). |
| §4.6 Install flow | Underspecified (M3); upstream first-run chain not neutralised (H11); skill-directory list does not match the tag (M5); versionlock (B4); PAM ownership (M2); existing-user seeding (B5a); `curl \| bash` hygiene (B6). |
| §4.7 Maintenance model | The promise on L106 is contradicted by B4 and undercounted per H4 and section 6; status tool privilege and data-source problems (H2, H3); agent trigger is a security surface (B6). |
| §4.8 `upstream.lock` | Not yet a contract (H9). |
| §5 Repo layout | Missing: name map, PAM template, uwsm env file, session file, tests/CI, `Makefile`/`.copr` for SRPM generation, audit doc. |
| §6 Phases | Phase 1 undefined (L1); no spike (section 6); milestones lack acceptance criteria and a plugin milestone (H8). |
| §7 Risks | Good list, optimistic mitigations. Missing risks: Qt coupling (H4), config drift (B5c), unaudited scripts (B3), COPR retention (H6), GNOME contamination (H5), agent security (B6), agent CLI flag drift under a pinned launcher (L7), bus factor of one. "Nothing here can brick the machine" is true for boot, but a PAM or lock-screen failure can still lock the user out of a running session. |
| §8 Open questions | Two of four are not design questions (L6). The real open questions are in section 9 below. |
| §9 Decision log | Strongest section. Add rows for: overriding research §4.6 (H1), pin mechanism (B4), herdr delivery (M4), mise delivery (B7), skel versus provision (B5b). |
| §10 References | L205's description of research §4.6 should be corrected (H1). |

---

## 8. Upstream verification results

Checked on 2026-09-17 against `omacom/omarchy` tag `v4.0.4` (commit `c668141`), a Fedora 44 host (`dnf5 5.4.3.0`), the COPR API and GitHub. The tree was read only; nothing from it was executed.

| # | Question | Result | Effect |
|---|---|---|---|
| 1 | `bin/` versus `/usr/bin` layout; does `envs.lua` prepend `$OMARCHY_PATH/bin`? | Scripts install to `/usr/bin` with symlinks in `/usr/share/omarchy/bin/` (`docs/file-layout.md:56-57`); `envs.lua:30-36` does prepend the tree's `bin/` | **B2 cleared**, downgraded to Low: state the layout in the spec |
| 2 | `pacman` usage in `MenuModel.js` and elsewhere in `shell/` | Confirmed; the guard batch defines bash functions that shadow `omarchy-pkg-present`/`-missing` (`MenuModel.js:410-423`). Only file in `shell/` that touches pacman | **B1 confirmed and sharpened** |
| 3 | Grep-based Arch-coupling audit | 50 of 444 `bin/` scripts have direct hits, 31 of them outside the spec's shim table; 66 more depend on the `omarchy-pkg-*` wrappers; 1 file in `shell/`, 12 in `default/`, 1 in `config/` | **B3 confirmed**; first-cut numbers added. Classification still to do |
| 4 | What `omarchy-provision-first-run` runs | The full user-provisioning chain, automatically at first login, retried on failure; rewrites XDG dirs, default browser, mailto, gsettings, default keyring | **New finding H11** |
| 5 | System-level menu extension path | Does not exist; only the default file and `~/.config/omarchy/extensions/omarchy-menu.jsonc` are loaded (`Menu.qml:50-51`) | **New finding H10** |
| 6 | What `omarchy-theme-set` writes outside Omarchy's own state | `gsettings` GTK theme, colour scheme and icon theme on every switch; VS Code family `settings.json`; Obsidian vaults; browser theming | **H5 confirmed** |
| 7 | Quickshell and Qt private APIs; has F44 shipped a Qt minor bump? | Yes to both: `quickshell` requires `libQt6*.so.6(Qt_6.10_PRIVATE_API)` / `(Qt_6.11_PRIVATE_API)`; F44 carries `qt6-qtbase` 6.10.2 and 6.11.2; Fedora's `quickshell` was rebuilt `-1` to `-5`. The `omedora-4` spec itself was not read | **H4 confirmed**; failure mode is a blocked upgrade, not a broken shell |
| 8 | COPR retention | `auto_prune: true` on `omedora-4` via the API; per-project toggle; platform default and exact window not confirmed (docs page returned 404) | **H6 confirmed in substance**; disable `auto_prune` on the Tinkero project |
| 9 | herdr release binaries | v0.9.1 (2026-09-16) ships `herdr-linux-x86_64` and `herdr-linux-aarch64`. At `v4.0.4` herdr is a pacman base package, not a mise stub | **M4 confirmed**; mise `github:` backend feasible |
| 10 | Upstream stance on name and logo | Nothing in `LICENSE`, `README.md`, `docs/` or `manual/` at the tag mentions trademarks; MIT only. No statement found either way | **M10 still open**; needs a question to upstream, not a grep |
| 11 | dnf5 versionlock | Present on Fedora 44: `dnf5 versionlock add/exclude/clear/delete/list` | B4's feasibility is not in doubt; its design objection stands |

Side discoveries: the research doc describes `quattro` HEAD, and the pinned tag differs from it in script count (444 versus 458), agent roster (no `agy`, no `ori`), skill directories (no `~/.gemini/config/skills`) and the Claude browser-extension hook (absent at the tag). The spec should be re-read against the tag wherever it quotes the research for specifics (B3, M5). `omarchy-setup-security-fingerprint` installs packages with `sudo pacman -S` directly rather than through the wrappers, which is the pattern the CI gate in H8 exists to catch.

Still unverified: the Qt dependency form in the `omedora-4` Quickshell spec; COPR's exact prune window; whether the lock screen authenticates under SELinux targeted policy (needs a running system, not a reading); upstream's trademark position.

---

## 9. Top open questions that block implementation

Ordered by how much downstream work each one gates.

1. **What is the real size of the seam, classified?** The first-cut audit (B3, section 8) puts it at about 50 scripts plus one QML/JS patch, against roughly 20 in the spec. Each hit still needs a *replace / patch / drop / hide* decision, and H10 (menu mechanism) and H11 (first-run chain: keep, adapt or drop each step) need design answers before Phase 2b can be planned.
2. **Pin by `dnf versionlock` or by RPM `Requires`?** (B4) This decides the content of `install.sh`, `tinkero-status`, `upstream.lock` semantics, and whether the "dnf upgrade, nothing else" promise is true.
3. **What is the seeding and upgrade policy for user config, for an existing user with existing dotfiles?** (B5) Conflict policy, skel or not, what a tree bump does to already-seeded files, where "config migration notes" come from.
4. **What may the agent do unattended, triggered by what, fed with which data?** (B6) Decide the threat model; decide whether the timer-to-agent advisor is in v1 at all.
5. **How are `mise` and `herdr` delivered?** (B7, M4) COPR package, vendor repo, or upstream installer; and how their binaries reach the graphical session's `PATH`.
6. **Does the author accept the true maintenance cost, and what is the exit criterion?** (H1, H4, section 6) Own all ~25 specs from day one, or consume `omedora-4` until the desktop is proven? What monthly time budget triggers "abandon and take only the agent layer", the research's fallback?
7. **What is the rollback procedure, concretely?** (H5, H6) GNOME-unaffected invariant, COPR retention, previous-build availability.
8. **What is the authoritative dependency manifest?** (H7) Hard versus weak requires; default browser; which of three terminals.
9. **How is a lock bump validated before it reaches the daily machine?** (H8) CI gate plus VM smoke test, or manual.
10. **Is Omarchy branding kept in a public derivative?** (M10) Needs an answer before the repo is promoted, not before code is written.

## 10. Suggested order of work

1. **Spike (1 to 2 days, parallel with FAS/COPR account setup):** VM, `omedora-4` COPR, hand-assembled tree per research §4.4, reach Milestones A and B by hand, record every deviation. Produces the audit (question 1) and real data for the PAM, SELinux, GDM and GNOME-coexistence questions.
2. **Spec revision 2:** add sections for Security, Config lifecycle, Testing and acceptance, Uninstall and rollback, Dependency manifest; rewrite §4.3 from the audit with the replace/patch/drop column; replace versionlock; fix `upstream.lock`; add the "why we overrule the research" rationale and the maintenance budget; renumber phases.
3. **Then** write the Phase 2a and 2b implementation plans. Phase 3's advisor stays out of scope until questions 4 and H2/H3 have answers.

---

## 11. Disposition in spec revision 2

Section numbers are those of revision 2.

| Finding | Handling in revision 2 |
|---|---|
| B1 menu guards | `MenuModel.js` patch, §4.3 |
| B2 PATH layout | upstream's symlink layout stated in §4.2, enforced by the single-copy CI gate |
| B3 unaudited scripts | classified audit committed; §4.3 derived from it; Arch-leak gate in §8 |
| B4 versionlock | replaced by RPM `Requires` generated from the lock, §4.2 |
| B5 config lifecycle | `tinkero-provision`, hash-tracked seeding, config notes, no `/etc/skel`, §4.6 |
| B6 security | new §5; installer hygiene (tagged URL, plan, confirmation) in §4.6; advisor deferred to a conditional Phase 5 |
| B7 mise | packaged in the COPR, §4.1 |
| H1 research override | new §1.1 with budget and exit criterion (budget awaits the author's confirmation) |
| H2 Hyprland requirement | `tinkero-status` reports tag and date only, heuristic labelled, §4.7 |
| H3 status privileges | manual command in v1; AVC check only under `sudo`, §4.7 |
| H4 Qt coupling | §4.1 "The Qt obligation", weekly Qt watch in §4.7, risk in §9 |
| H5 GNOME coexistence | invariant and mechanism in §4.9, acceptance test in §8 |
| H6 COPR retention | `auto_prune` off, §4.1; rollback procedure in §4.11 |
| H7 dependency manifest | new §6 |
| H8 testing | new §8: four gates, lint, VM smoke test, milestones A to D including plugins |
| H9 `upstream.lock` | §4.12; commit, rev and the full Quickshell snapshot version added to the file, sha256 pending the first fetch |
| H10 menu extension path | build-time rewrite, §4.4 |
| H11 first-run chain | both scripts replaced; per-step verdicts in the audit §6, summarised in spec §4.6 |
| M1 build mechanics | COPR SCM with `make srpm`, §4.2 |
| M2 PAM ownership | RPM-owned file, one of two variants chosen from the authselect profile so that lockout is kept and failures are counted once, §4.8; the fingerprint setup and removal scripts are replaced with authselect-based versions, §4.3 |
| M3 install flow | preflight, plan, stages, tagged URL, §4.6 |
| M4 herdr | packaged in the COPR, §4.1 |
| M5 roster | not enumerated beyond the tag's own list, §4.1; five skill directories, §4.5 |
| M6 name map | `distro/fedora/pkgmap.tsv`, format and CI gate, §4.3 |
| M7 patch versus shim | separate tables, §4.3 |
| M8 uninstall | §4.11 |
| M9 cross-distro claim | `distro/` seam, claim corrected, §4.10 |
| M10 branding | decided by the author: no visible Omarchy name or logo, identifiers keep upstream's names, attribution kept; §4.13 and the audit §11. Only the Tinkero artwork is outstanding |
| M11 hardware scope | non-goals, §3 |
| M12 skill guidance conflict | single `host.md`, no copying into `/usr`, §4.5 |
| L1 to L7 | phases renumbered (§7); RPM Fusion not enabled (§3, §4.6); extra GDM session documented (§4.2); `install/` handling stated (§4.2); open questions pruned (§10); pinned-launcher risk added (§9). L4 (redundant `OMARCHY_PATH` export) is moot: upstream's env file is shipped as is |

Not resolvable on paper and carried forward: the lock screen under SELinux (Phase 0; see `docs/guides/phase-0-spike.md`), the Tinkero artwork, the author's confirmation of the maintenance budget.
