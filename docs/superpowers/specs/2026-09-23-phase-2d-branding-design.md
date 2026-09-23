# Plan 2D design: branding

**Status:** design for plan 2D, derived from the Tinkero design spec (`2026-09-17-tinkero-design.md`, revision 2.1, section 4.13 and section 8 item 4a) and the audit's branding inventory (`docs/research/arch-coupling-audit.md`, section 11) on 2026-09-23. The master spec stays the binding authority; this document works the branding decision out to the level a plan needs, corrects the counts against the real `v4.0.4` tree, and records the decisions the master spec leaves open. Where the two disagree, this document says so under "Decisions" and the master spec is amended when the plan lands.
**Plan:** `docs/superpowers/plans/2026-09-23-phase-2d-branding.md`.
**Depends on:** plans 2A and 2C (on `master`). Plan 2E (issue #16) is in flight on its own branch and is not assumed to have landed; section 10 names the three points where 2D and 2E touch.

## 1. What 2D delivers

Milestone B's first line (spec, section 8): nothing on screen says or shows Omarchy, and About credits it. Everything a user sees in the graphical session is rebranded at build time; every identifier (command names, paths, plugin ids, window classes, PAM service names, the `omarchy` skill) keeps upstream's name. Seven deliverables, all under `branding/` except the fifth and the seventh:

1. **The mark and its placeholders.** `branding/mark.svg` (a monochrome glyph), `branding/wordmark.svg` (the wordmark the wallpapers are rendered from), `branding/icon.txt` and `branding/logo.txt` (the two ASCII renderings upstream's About screen, screensaver and presentation screens read). Until the real Tinkero mark exists (spec, open question 2), these are geometric placeholders: a block "T" and block-letter "TINKERO" (section 3).
2. **The font rebuild.** `branding/rebuild-font` puts the mark at `U+E900` of `default/fonts/omarchy/omarchy.ttf` and changes nothing else in the font (section 4).
3. **The substitution list.** `branding/strings.tsv`, applied by `branding/apply-strings`, five rows at `v4.0.4`, each with the count it must match or the build fails (section 5).
4. **The manifest rewrite.** `branding/rewrite-manifests` rebrands the plugin manifests' `author`, `name`, `displayName` and `description` without touching an id or a byte of formatting (section 6).
5. **The menu row.** `learn.omarchy` opens Tinkero's README with the label "Tinkero", through `menu/overrides.jsonc` (section 7).
6. **The wallpapers.** `branding/images.tsv` (one reviewed row per shipped wallpaper), `branding/inventory-images` (writes the rows), `branding/contact-sheet` (renders them for the person reviewing) and `branding/render-wallpapers` (applies the verdicts: renders the flat wordmark wallpapers anew in each theme's colours, deletes the illustrated ones) (section 8).
7. **The build step and the gate.** `build/assemble` step 3d runs the above; `ci/gate-branding` with `ci/allow/branding.allow` proves the result on the payload; `tinkero.spec.in`, `dev` and CI gain the two build tools (sections 9 and 10).

Not in 2D: the welcome toast (2E, already worded "Tinkero menu"), `host.md`'s paragraph on the name (2E), the seeding of `~/.config/omarchy/branding/{about,screensaver}.txt` from the replaced files (2E), the GDM session name (2A, done), the real artwork (a person's, any time; section 3 says what replacing the placeholders takes), the on-screen check itself (Milestone B needs an installable package, 2E and 2F).

## 2. The seen surface at `v4.0.4`, measured

The audit's inventory (section 11) was written from a partial look at the tree. Plan 2A's payload makes the whole surface measurable; every number below was taken from the real tree on 2026-09-23 and is what the plan's verification steps check.

| Surface | Measured at `v4.0.4` | Handling | Section |
|---|---|---|---|
| Logo glyph | `default/fonts/omarchy/omarchy.ttf`: 21 glyphs, family name `omarchy`, `U+E900` is the glyph named `omarchy` (5 contours, the full 0..1024 box; the 12 agent marks sit in 64..960). A GSUB ligature maps the letters o m a r c h y (empty glyphs) to that same glyph. Drawn by `shell/plugins/menu/BarWidget.qml` (`fontFamily: "omarchy"`, `text: "\ue900"`) and by 23 menu rows with `"iconFont":"omarchy"`, one of which (`update.omarchy`, now "Packages") uses `U+E900` | glyph replaced in place | 4 |
| ASCII logos | `logo.txt` (10 lines, 81 columns; read by `omarchy-show-logo`, which every floating-terminal presentation runs first) and `icon.txt` (26 lines, 54 columns; the About screen's logo, the size `omarchy-branding-about` renders images to). `omarchy-branding-about reset` and `omarchy-branding-screensaver reset` copy them into `~/.config/omarchy/branding/`; 2E seeds the same two files | files replaced | 3 |
| Image logos | `logo.svg` (the OMARCHY wordmark, 1215 by 285) and `icon.png` (300 by 300). No kept script reads either: their readers are the dropped `omarchy-plymouth-set` and upstream's README | replaced anyway; `icon.png` rendered from the mark | 3, 9 |
| Theme wallpapers | 92 files in 22 themes. **20** are flat wordmarks, not the audit's 18: the 18 named `backgrounds/omarchy.png` plus `flexoki-light/backgrounds/2-omarchy.png` and `lupine/backgrounds/06-omarchy.png`. All 20 are 3840 by 2160. Nineteen have exactly two colours, the wordmark in the theme's `accent` from `colors.toml` on the theme's `background` (catppuccin and lumon use a slightly darker shade than their `colors.toml` says); flexoki-light's is anti-aliased and drawn in the theme's `foreground` (`#100f0f`), not its `accent`. The wordmark spans 41% of the width and 17% of the height, centred. Four carry upstream's marks in illustrated form and cannot be regenerated: `rose-pine/backgrounds/3-omarchy-plants.png`, `tokyo-night/backgrounds/1-quattro.jpg` (release art with third-party marks), `5-oma-cityscape.jpg` and `6-oma.jpg` (the house mark). `tokyo-night/backgrounds/4-omakub.jpg` was opened by the audit and shows nothing branded. The other 67 have not been looked at | 20 regenerated, 4 deleted, 1 kept, 67 for the person's pass | 8 |
| About screen OS line | `etc/fastfetch/config.jsonc:74`: `echo \"Omarchy $version\"` (the file 2A relocates to `/usr/share/tinkero/fastfetch/`) | substitution list; this line is also the About screen's attribution | 5 |
| Plugin manifests | 37 files: 29 `shell/plugins/**/manifest.json` and 8 bar-widget `*.manifest.json` (the audit counted 28). **36** carry `"author": "Omarchy"`. **11 fields in 5 files** name Omarchy in `name`, `displayName` or `description`: the menu plugin (4), the `SystemUpdate` widget (4), and one description each in `agents`, `panels/dropbox` and `panels/tailscale`. `shell/shell.qml:1402` reads `displayName` into the widget picker | JSON transform | 6 |
| Menu | `learn.omarchy` (label "Omarchy", opens the Omarchy manual as a web app). `update.omarchy` is already "Packages" (2C) and keeps its `U+E900` icon, which the font rebuild rebrands | `replace` in `menu/overrides.jsonc` | 7 |
| Cheat sheet | `default/hypr/bindings/utilities.lua` lines 1 and 7, `"Omarchy menu"` twice | substitution list, count 2 | 5 |
| Shell strings | `shell/plugins/bar/widgets/SystemUpdate.qml:62` (`tooltipText: "Pending Omarchy Updates"`; the indicator never shows in Tinkero because `omarchy-update-available` always exits 1, rebranded anyway) and `shell/services/PluginRegistry.qml:632` (`"reserved for first-party Omarchy plugins"`, a console warning) | substitution list | 5 |
| Font README | `default/fonts/omarchy/README.md` lists `U+E900` as Omarchy; shipped in the payload | substitution list, so the shipped README describes the shipped font | 5 |
| Window rules | `default/hypr/apps/system.lua:7` matches a window titled "Omarchy" among others; `default/hypr/apps/omarchy-shell.lua:14` matches the dev gallery's title | allowlisted: they match titles, they do not display them | 10 |
| Dev gallery | `shell/plugins/dev-gallery/GalleryPanel.qml`: three strings (a window title, a heading, a label) in a developer tool | allowlisted | 10 |
| Chromium extensions | five files under `default/chromium/` (three extension manifests, two native-messaging hosts) say "installed by Omarchy" or "Omarchy ... host" in a description. Chromium and its extensions are a non-goal (spec, section 3); the files stay in the tree because `omarchy-install-chromium-copy-url` and `-ytdlp` are kept commands | allowlisted, not rewritten: rewriting would claim Tinkero installs them | 10, D7 |
| Comments | many files mention Omarchy in comment lines (five of them inside quotes, which a naive string scan would flag: `config/hypr/hyprland.lua`, `config/hypr/bindings.lua`, `default/hypr/input.lua`, `shell/plugins/notifications/Service.qml` and the menu's own first line) | the gate skips comment lines; nothing to allowlist | 10, D8 |
| Session name, welcome toast, `host.md` | done in 2A; 2E; 2E | not 2D | 10 |
| CLI `--help`, `# omarchy:summary=` lines, seeded config comments | terminal-only or user-owned | out of scope in v1, as the master spec says | |

The branding gate run against today's payload (2A to 2C, no branding) reports 49 files with the capitalised word in a string literal: the 36 manifests, the 4 files of the substitution list that the scan covers (the font README is Markdown), the menu, and the 8 that stay allowlisted. After 2D it reports those 8 and nothing else.

## 3. The mark and its placeholders

`branding/` holds the artwork as data the build reads. Nothing in the build knows whether the artwork is the placeholder or the real thing.

| File | What it is | Constraints |
|---|---|---|
| `mark.svg` | the glyph: what goes into the font at `U+E900`, the bar's menu button, the "Packages" row, `icon.png` | one SVG with a `viewBox`; `<path>` and the basic shapes (`rect`, `circle`, `ellipse`, `polygon`, `line`) are read; `fill="currentColor"`; monochrome, since the shell draws it in the theme's foreground colour |
| `wordmark.svg` | the wordmark: what the flat wallpapers are rendered from, and the new `logo.svg` | same rules; `currentColor` is replaced by the theme's accent before rendering |
| `icon.txt` | the About screen's logo (`~/.config/omarchy/branding/about.txt` once 2E seeds it) | at most 54 columns by 26 rows, the size `omarchy-branding-about` renders to |
| `logo.txt` | the screensaver and the presentation screens | at most 26 rows; upstream's is 81 columns wide, and the width is free (ttfx and `omarchy-show-logo` take what they get) |

**Placeholders (D2).** The real mark does not exist. The placeholders are geometry, generated from a grid so that nothing depends on a font being installed in the build chroot: `mark.svg` is a bold "T" (one path in a 1024 by 1024 box), `wordmark.svg` is "TINKERO" in block letters on a 5 by 7 cell grid (73 rectangles), `logo.txt` is the same grid at two columns a cell (7 lines, 82 columns) and `icon.txt` is the "T" at 54 by 26. The plan's first task gives the grid, the generator snippet and the sha256 of each file, so the placeholder is reproducible and its replacement is one commit.

**Replacing the placeholders** is a data change: drop in the real `mark.svg` and `wordmark.svg`, regenerate the two ASCII files with upstream's own tool (it is in the payload and needs only ImageMagick):

```bash
omarchy-transcode-ascii branding/mark.svg branding/icon.txt --width 54 --height 26 --mode block
omarchy-transcode-ascii branding/wordmark.svg branding/logo.txt --width 82 --height 10 --mode block
```

then `./dev gates` (the font, the wallpapers, `icon.png` and `logo.svg` are rendered from the SVGs at build time). `branding/README.md` says this, so the artwork's author needs no plan.

## 4. The font

`branding/rebuild-font IN.ttf MARK.svg OUT.ttf` (Python, `python3-fonttools`; D1):

- Loads the font, finds the glyph that `cmap` maps `U+E900` to (`omarchy` at `v4.0.4`), and **replaces that glyph's outline in place**. The glyph order, every other glyph, `hmtx` for every other glyph, the `cmap`, the `name` table (family `omarchy`, which `BarWidget.qml` and the menu's `iconFont` ask for) and the GSUB ligature are untouched. Because the ligature points at the glyph by name, typing "omarchy" in that font now shows the Tinkero mark, which is what a user who found that easter egg should see.
- The mark is scaled to fit, centred, into the 64..960 box that upstream's `omarchy-dev-font` uses for every agent mark, so the placeholder and the real mark land at the same optical size as the marks beside them in the menu. SVG y grows down and font y grows up, so the transform flips y; contours keep upstream's orientation (outer contours clockwise, verified by the signed area of the result against the agent marks).
- Cubic curves in the SVG are converted to TrueType quadratics (`Cu2QuPen`, one font unit of tolerance). The advance width is the em (1024) like every mark in the font; the left side bearing is the glyph's `xMin`.
- Fails when the font has no `U+E900`, when the SVG has no `viewBox` or draws nothing.

Why not upstream's `omarchy-dev-font`, which is standard library only: it appends glyphs (`add` refuses a taken code point) and would need a "replace" mode written against its hand-rolled table encoder; `fontTools` is in Fedora, is the tool the master spec names, and makes the rebuild twenty lines. The cost is one `BuildRequires` and one package on the developer's machine.

Verification the plan makes concrete: after the rebuild, for every code point except `U+E900` the compiled `glyf` entry is byte-identical to upstream's; the family name, the `cmap` and the presence of GSUB are unchanged; `U+E900` has the mark's contour count and its bounding box lies within 64..960.

## 5. The substitution list

`branding/strings.tsv`: `file<TAB>upstream string<TAB>replacement<TAB>count`, `file` relative to the tree as it is when step 3d runs, before step 4 relocates `etc/` (D9). Fixed-string matching, no escapes, no tabs inside a string. `branding/apply-strings TREE STRINGS.tsv` checks every row before writing anything: the file must exist and contain the upstream string exactly `count` times; otherwise it lists every problem and writes nothing, which is how an upstream rewording is caught at the bump instead of shipping the old name. Rows at `v4.0.4`:

| File | Upstream string | Replacement | Count |
|---|---|---|---|
| `default/hypr/bindings/utilities.lua` | `"Omarchy menu"` | `"Tinkero menu"` | 2 |
| `etc/fastfetch/config.jsonc` | `echo \"Omarchy $version\"` | `echo \"Tinkero $version, built on Omarchy\"` | 1 |
| `shell/plugins/bar/widgets/SystemUpdate.qml` | `"Pending Omarchy Updates"` | `"Pending Tinkero Updates"` | 1 |
| `shell/services/PluginRegistry.qml` | `reserved for first-party Omarchy plugins` | `reserved for first-party Tinkero plugins` | 1 |
| `default/fonts/omarchy/README.md` | `` `U+E900` — Omarchy `` | `` `U+E900` — Tinkero, from branding/mark.svg (the build replaces the upstream mark) `` | 1 |

The fastfetch row is also the About screen's attribution (D6): with 2B's `omarchy-version` the line reads "Tinkero 4.0.4-1.fc44, built on Omarchy". The README row's dash is upstream's list separator, matched and kept as is (D13).

## 6. The plugin manifests

`branding/rewrite-manifests TREE` (Python, standard library; D10). For every `shell/plugins/**/manifest.json` and `shell/plugins/**/*.manifest.json`:

- `"author": "Omarchy"` becomes `"Tinkero (from Omarchy)"` (the master spec's wording: attribution stays);
- in `name`, `displayName` and `description`, at the top level and under `barWidget`, the word Omarchy becomes Tinkero;
- **ids are never read**, and nothing else changes.

Upstream's manifests are not all formatted the way `json.dumps` would write them (`agents/manifest.json` keeps short arrays on one line), so the transform does not re-serialise. It parses the file to decide what changes, then replaces the JSON encoding of each old value in the file's text (the encoded value must occur exactly as many times as the fields that carry it: the `SystemUpdate` widget has the same value in `name` and `displayName`), parses the result and compares it with the intended object before writing. Formatting survives byte for byte; a manifest where the encoded value also appears somewhere unexpected fails the build instead of being half-rewritten. Running it twice is a no-op. Measured at `v4.0.4`: 37 manifests, 36 rewritten, 36 authors and 11 fields.

## 7. The menu

One `replace` row in `menu/overrides.jsonc` (D5): `learn.omarchy` keeps its id (an identifier: `omarchy menu summon learn.omarchy` addresses it, and 2C's `replace` keeps ids by construction, exactly as `update.omarchy` did), gets the label "Tinkero", the rebranded `U+E900` glyph in the `omarchy` icon font, and the action `omarchy-launch-browser https://github.com/dromeropa/tinkero#readme`: the README in the default browser, as the master spec says. `expect_rows` stays 258.

`omarchy-launch-browser` and not `omarchy-launch-webapp`: the web-app launcher accepts only Chrome, Brave, Edge, Opera, Vivaldi and Helium as the default browser and otherwise runs `chromium.desktop`, which a stock Fedora with Firefox does not have. 2C's `learn.fedora` row has that defect; the same edit switches it to `omarchy-launch-browser` (D5). Upstream's `learn.hyprland`, `learn.neovim` and `learn.bash` rows have it too and are left for the queue (section 11), since they are upstream rows and the fix is either a patch to the launcher's fallback or a decision to name Chromium in the name map.

## 8. The wallpapers

**The list.** `branding/images.tsv`: `path<TAB>sha256<TAB>verdict`, one row per file under `themes/*/backgrounds/`, sorted, `path` relative to the tree. Verdicts:

| Verdict | Meaning | At `v4.0.4` |
|---|---|---|
| `keep` | ships as is; the sha256 must still match, so an image that changed upstream is looked at again | 1 known (`4-omakub.jpg`) plus what the review finds |
| `regenerate` | a flat wordmark wallpaper: rendered anew from `wordmark.svg` in the theme's colours and deleted | 20 |
| `delete` | removed from the payload | 4 |
| `review` | nobody has looked at it; **the build refuses it** | 67 until the review |

**The tools.** `branding/inventory-images TREE IMAGES.tsv` rewrites the list from the tree: unchanged rows keep their verdict, new or changed images get `review`, rows whose file is gone are dropped; the diff after a bump is exactly the images that need a look. `branding/contact-sheet TREE OUT.png` renders every wallpaper on one labelled sheet (ImageMagick `montage`). `branding/render-wallpapers TREE IMAGES.tsv WORDMARK.svg` checks everything first (every file has a row with the right sha256, every row has a file, no `review`, every `regenerate` name contains `omarchy` and its theme has a `colors.toml` with six-digit `accent` and `background`) and only then acts: deletes the `delete` rows; for each `regenerate` row reads the source's pixel size, renders `wordmark.svg` in the accent on the background at 41% of the canvas width, centred (what upstream's files measure), writes it under the source's name with `omarchy` replaced by `tinkero` (`omarchy.png` to `tinkero.png`, `2-omarchy.png` to `2-tinkero.png`, so the rotation order is kept) and deletes the source. The regenerate rule is generic (D3): no per-theme data, and a 23rd theme with a flat wordmark is one row. flexoki-light's rendered wallpaper therefore uses its `accent` (a blue on cream) where upstream's used the `foreground`; that is the one theme whose regenerated wallpaper is not a like-for-like recolouring, accepted for the sake of one rule.

**The review (D4)** is a person's: the roadmap says the plan provides the sheet and the gate, not the judgements. The plan's wallpaper task ships the list with the 25 decided rows above and 67 `review` rows, and is not done until the operator has replaced every `review` with a verdict, working from the contact sheet. The build's refusal of `review` rows is the forcing function; that task's PR is red until the review is in. Every later bump repeats the loop only for new or changed images.

Deletion goes through the list, not `build/drop.list` (D15): the drop list is the Arch seam, the image list is the reviewed record, and one file should own each decision.

## 9. Build step, packaging, tools

`build/assemble` gains step 3d, placed immediately before the `# 4. Relocate` comment (so it lands whether or not 2E's step 3c is there yet, D14) and guarded on `branding/strings.tsv` existing under the root (so the assemble tests that build a private root without `branding/` are unaffected):

1. `rebuild-font` on `default/fonts/omarchy/omarchy.ttf` (written to a temporary name, then moved over the original);
2. `logo.txt`, `icon.txt` replaced by `branding/`'s; `logo.svg` replaced by `wordmark.svg`; `icon.png` rendered from `mark.svg` at 300 by 300 (D11). Each upstream file must exist first, so a rename is noticed;
3. `rewrite-manifests`;
4. `apply-strings`;
5. `render-wallpapers`.

Order matters once: the menu rewrite (3b) runs before the branding step, so the string scan sees the rewritten menu; the fastfetch substitution runs before step 4 relocates the file.

Packaging: `tinkero.spec.in` gains `BuildRequires: python3-fonttools ImageMagick` (Fedora 44 ships fontTools 4.62 and ImageMagick 7.1.2, whose `ImageMagick-libs` pulls in librsvg, so SVG rendering needs nothing more). No new `%files` line: the font, the tree and the themes are already covered. CI's tool line installs the same two packages; `./dev gates` on a developer's machine needs them too (`sudo dnf install python3-fonttools ImageMagick`). The hermetic tests that need a tool skip themselves with a visible `1..0 # skip` line (or `unittest.skip`) when it is missing, so `./dev check` stays runnable on a machine without them; CI installs both, so nothing is skipped there (D12).

## 10. The gate

`ci/gate-branding DEST IMAGES STRINGS ALLOW`, run by `./dev gates` and CI after the four existing gates. Four checks on the assembled payload:

1. **String literals.** In every `.qml`, `.js`, `.lua`, `.json`, `.jsonc` and `.desktop` file under `DEST`, after dropping comment lines (first non-blank characters `//`, `--` or `#`) and the two attribution phrases the design keeps on purpose (`built on Omarchy`, `from Omarchy`), no double- or single-quoted string literal contains the word `Omarchy` (case-sensitive, word-bounded: `omarchy`, `org.omarchy.*` and `OmarchyFoo` are not findings). Findings are file paths compared with `ci/allow/branding.allow` through `compare_with_allowlist`, so the allowlist may only shrink and a stale entry fails too (D8). At `v4.0.4` the allowlist has 8 entries: the five Chromium files, the two window-rule files and the dev gallery.
2. **Names.** No file under `usr/share/omarchy/themes/*/backgrounds/` is named `*omarchy*`.
3. **The image list against the payload.** Every wallpaper in the payload is a `keep` row whose sha256 matches, or a file named for a `regenerate` row (its name with `tinkero` in place of `omarchy`); no `delete` or `regenerate` source is present; no row is `review`. The master spec's wording, "a keep row", is read as "a reviewed row that allows the file", since a rendered file is exactly what a `regenerate` row produces; the plan's docs task rewrites item 4a to say so.
4. **The substitution list took effect.** For each row, the payload file (rows under `etc/` are looked up under `usr/share/tinkero/`) no longer contains the upstream string and does contain the replacement. The count itself was enforced by the build.

The gate is proven on the real payload in the plan: 49 findings before 2D, 8 (all allowed) after. If the review keeps all 67 unreviewed images, the payload has 88 wallpapers (20 rendered, 68 kept, 4 deleted); every `delete` the review adds lowers that by one, and the plan records the final numbers.

## 11. Decisions taken by this design

Each is a call the master spec leaves open, states in a form that cannot be built literally, or that measurement contradicted. Listed so the operator can veto any of them at the approval gate.

- **D1, the font is rebuilt with `python3-fonttools`, in place.** The master spec names fontTools; the roadmap allows it as the one exception to standard-library-only Python. The glyph is replaced under its existing name, so the GSUB ligature follows and nothing else in the font moves. Upstream's `omarchy-dev-font` was considered and rejected (section 4).
- **D2, the placeholder artwork is generated geometry, checked in.** A block "T" and block-letter "TINKERO" from a 5 by 7 grid, plus the two ASCII renderings drawn from the same grid, with sha256s in the plan. No font is needed in the build chroot, and the real mark replaces four files without a code change. The ASCII files are regenerated with upstream's `omarchy-transcode-ascii` rather than at build time, so the build never runs an upstream script (section 3).
- **D3, the regenerate rule is generic and finds 20 flat wordmarks, not 18.** Output name is the source's with `omarchy` replaced by `tinkero`; size is the source's; colours are the theme's `colors.toml` `accent` and `background` (two themes' upstream files used a background shade that differs from their `colors.toml`, and flexoki-light's used the `foreground` instead of the `accent`; the rendered ones follow the file's `accent` and `background`, which is what every other surface of the theme uses); the wordmark spans 41% of the width, centred.
- **D4, wallpaper rows nobody has looked at say `review` and the build refuses them.** The initial list has 25 decided rows (from the audit and this design's measurements) and 67 `review` rows; the wallpaper task is done only when the operator's pass has replaced them, and that task's PR stays red until then. The contact sheet is `branding/contact-sheet`; the montage command is also in the plan so it can be run before the task exists.
- **D5, `learn.omarchy` keeps its id and opens the README through `omarchy-launch-browser`; `learn.fedora` is switched to the same launcher.** The roadmap's "becomes `learn.tinkero` through `replace`" cannot be built: `replace` keeps ids, and the id is an identifier anyway. The browser launcher is used because `omarchy-launch-webapp` falls back to `chromium.desktop` on a stock Fedora. The `learn.fedora` fix touches a 2C row and is included because it is the same one-line edit in the same file.
- **D6, the About screen's OS line is the attribution:** "Tinkero <version>, built on Omarchy". The master spec asks for "built on Omarchy" with a link on the About screen; a TUI line carries the phrase, and the README carries the link.
- **D7, the five Chromium files are allowlisted, not rewritten.** Chromium is a non-goal and the strings are true only of upstream ("installed by Omarchy"). Dropping `default/chromium/` was rejected: two kept commands install from it.
- **D8, the gate skips comment lines and the two attribution phrases, and allowlists by file.** Five files mention upstream only in comments; the master spec's attribution wording ("Tinkero (from Omarchy)", "built on Omarchy") would otherwise be findings against itself. File-level entries match the other gates; a new string in an allowlisted file passes silently, which is accepted for a developer tool and two window rules.
- **D9, `strings.tsv` paths are tree paths before relocation** (`etc/fastfetch/config.jsonc`, not `usr/share/tinkero/...`), because the substitution runs inside the tree in step 3d; the gate maps `etc/` rows to their relocated place.
- **D10, the manifest rewrite replaces encoded values in the text and verifies by parsing** instead of re-serialising, because one upstream manifest is not in `json.dumps` form and a formatting-only diff against upstream is noise on every bump. Measured: 36 authors and 11 fields in 37 files.
- **D11, `icon.png` and `logo.svg` are replaced although nothing kept reads them:** `icon.png` rendered from `mark.svg` at upstream's 300 by 300, `logo.svg` a copy of `wordmark.svg`. One `magick` line and one `install` line, and the tree carries no upstream mark anywhere.
- **D12, the two build tools are BuildRequires and developer prerequisites; tests skip visibly without them.** `python3-fonttools` and `ImageMagick` on the build side, the same on a developer's machine for `./dev gates`; `./dev check` prints a skip line for the tests that need them and CI, which installs both, runs everything.
- **D13, the font README row keeps upstream's dash.** The row matches upstream's `- \`U+E900\` — Omarchy` list entry and rewrites it in the same shape; the dash is upstream's separator, not Tinkero prose.
- **D14, step 3d is anchored before step 4, not after 3c.** 2E adds 3c on its branch; anchoring on the relocation comment keeps the two plans mergeable in either order.
- **D15, wallpapers are deleted through `images.tsv`, not `build/drop.list`.** One file owns each decision: the drop list is the Arch seam, the image list is the reviewed record.

## 12. What can be verified now, and what cannot

Hermetic, in `./dev check` and CI: `apply-strings` (count mismatch leaves every file untouched and names every row; a second run fails; tab-separated fields), `rewrite-manifests` (author, the display fields, ids and formatting untouched, a value that repeats, a value that also appears elsewhere fails, idempotence), `rebuild-font` on a fixture font built with fontTools (only `U+E900` changes; family, cmap and the other glyph's bytes do not; a two-shape SVG; a missing `viewBox`), `inventory-images` (new, changed, gone, verdicts kept, a path with a space), `render-wallpapers` and `contact-sheet` against a fixture theme (skipped without ImageMagick), the gate's four checks on a fixture payload, and assemble step 3d against the fixture tree (skipped without the tools).

Measured against the real tree, in the plan's verification steps: the gate's 49 findings before and 8 after; 36 authors and 11 fields; 5 rows and 6 replacements; the 19 other mapped code points of the font byte-identical (20 of its 21 glyphs, counting the unmapped `.notdef`); 92 wallpapers in and 20 rendered at 3840 by 2160 with the theme's two colours as the two most frequent pixels, 4 deleted, the rest as the review decides (88 out if it keeps everything); the menu still at 258 rows; the SRPM builds in CI with the new BuildRequires.

Only on a running desktop, and therefore not proven by this plan: how the placeholder "T" reads in the bar's menu button at bar size and beside the "Packages" row; the About screen's layout with a 54 by 26 "T"; the screensaver with the block wordmark; each theme's wallpaper rotation showing `tinkero.png`. These are Milestone B's checklist lines and need the installable package (2E, 2F). ImageMagick is not installed on the planning machine, so the `magick` invocations in the plan were written from the ImageMagick 7 documentation and are first executed by CI; the plan says so where it matters.

## 13. Interfaces later plans rely on, and the seams with 2E

- **2E (in flight, not assumed landed):** (a) `tinkero-provision` seeds `~/.config/omarchy/branding/about.txt` and `screensaver.txt` from `$OMARCHY_PATH/icon.txt` and `logo.txt`, which 2D replaces in the tree; nothing in 2D depends on that seeding, and `omarchy-branding-about reset` works without it. (b) `build/assemble` step numbering: 2E adds 3c after 3b, 2D adds 3d before step 4 (D14). (c) The welcome toast and `host.md` already say Tinkero; 2D adds nothing there. If 2E lands first, its `tests/test-assemble.sh` count moves; 2D's assemble cases live in their own test file and change no shared count.
- **2F and Milestone B:** the on-screen check of section 12; `omarchy-theme-set` picks wallpapers by sorted file name, so `tinkero.png` sits where `omarchy.png` did in each rotation.
- **Bump checklist (Phase 3), additions:** run `branding/inventory-images` on the new tree and review every `review` row on the contact sheet; run `apply-strings` and read its report, then fix `strings.tsv` counts or rows; run `rewrite-manifests` and check its counts against the plugin diff; run the gate and read new string-literal findings before touching the allowlist; check that `U+E900` is still the logo glyph in the new font.
- **The artwork's author:** `branding/README.md` and section 3.
