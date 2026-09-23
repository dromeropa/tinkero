# Phase 2C: Menu Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **This plan runs through the issue loop** (`docs/guides/workflow.md`): one GitHub issue per task, dispatched only once Diego has applied `approved`, landed through a PR with green CI, in the order below.

**Goal:** The `tinkero` payload ships a default menu with no Arch-only, out-of-scope or dead rows, an Update entry that runs Fedora's package managers, and the two gate allowlists shrunk to their permanent entries.

**Architecture:** `menu/apply-overrides` (Python, stdlib) rewrites upstream's `default/omarchy/omarchy-menu.jsonc` during `build/assemble`, driven by `menu/overrides.jsonc` (delete by id prefix, delete rows that call a dropped command, replace, add). It works line by line, because every upstream row is one line keyed by its id, so upstream's comments and layout survive and the diff against upstream shows exactly Tinkero's rows. `bin/tinkero-update` is the script behind the new Update row. The first task moves the maintainer tool `tinkero-copr` out of `bin/`, which `assemble` would otherwise package.

**Tech Stack:** Python 3 standard library (`json`, `re`, `unittest`), bash, the existing `tests/lib.sh` harness and CI gates. No new dependencies beyond `python3` in the build environments.

**Spec:** `docs/superpowers/specs/2026-09-17-tinkero-design.md`, sections 4.4 (menu), 4.7 (maintenance model), 4.13 (branding, for what 2D adds later), 8 (gates). Audit: `docs/research/arch-coupling-audit.md` section 7. Roadmap: `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`. Design approved in conversation on 2026-09-23 with two amendments recorded here: `setup.default.agent.openclaw` stays (2B kept OpenClaw), and `tinkero-update` also runs `flatpak update`.

## Global Constraints

- Upstream tree pinned by `upstream.lock` at `v4.0.4`; every number in this plan is measured against that tag and changes with the tag (the bump checklist updates them).
- `build/assemble TARBALL DEST` is the whole of `%install`; new behaviour is a numbered step inside it, data over code (`menu/overrides.jsonc` is the data). Later plans (2D) add rows to the same file; the tool must not need changing for that.
- Gate allowlists (`ci/allow/*.allow`) only shrink; a stale entry fails the gate, so removing the menu's references and deleting their allowlist lines happen in the same task.
- Python from 2C on: standard library only, `python3 -m unittest`, no pytest. Scripts start with `#!/usr/bin/env python3` or `#!/bin/bash` and `set -euo pipefail`; ShellCheck clean with `-x -e SC1090,SC1091`.
- Tests never use the network and never run a real package manager; `tinkero-update` is tested against stubs on `PATH`.
- No em dashes in Tinkero's own prose. Attribution trailers on every commit per the session's rules. Land through a PR against the approved issue; never push master.
- Each task's PR includes its Deviations line in this plan's "## Deviations" section (empty line if nothing deviated is not needed; write one only when something did).

## Issue map

Filed 2026-09-23 as issues #1 to #6 in this order; each is `blocked by` the previous one because they share `tests/run`, `build/assemble` and the allowlists. The `approved` label is Diego's.

| # | Task | Size | Area | WHAT | WHERE | HOW TO VERIFY |
|---|---|---|---|---|---|---|
| #1 | Move `tinkero-copr` out of `bin/` | small | build | the maintainer tool must not be packaged; `assemble` installs every `bin/tinkero-*` | `build/tinkero-copr` (moved), `tests/test-copr.sh`, `.github/workflows/{copr-build,ci}.yml`, `distro/fedora/specs/README.md`, roadmap | `bash tests/test-copr.sh` 1..17 green; `TINKERO_COPR_DRY_RUN=1 build/tinkero-copr all \| grep -c '^copr-cli '` is 50; `ls bin/` is empty; `grep -rn 'bin/tinkero-copr' --exclude-dir=.git .` matches only the Phase 1 plan's history |
| #2 | `menu/apply-overrides` and its unit tests | medium | menu | the rewrite tool with the four rules and the failure cases | `menu/apply-overrides`, `tests/test_menu.py`, `tests/fixtures/menu/*`, `tests/run` | `python3 -m unittest discover -s tests -p 'test_*.py'` runs 14 tests green; `./dev check` still green; `diff` of fixture output against fixture input shows only deleted, replaced and added rows |
| #3 | `menu/overrides.jsonc` for `v4.0.4` | small | menu | the data: 28 delete prefixes, the `update.omarchy` replacement, the `learn.fedora` addition, `expect_rows` 258 | `menu/overrides.jsonc` | `python3 menu/apply-overrides .cache/tree/default/omarchy/omarchy-menu.jsonc menu/overrides.jsonc build/drop.list /tmp/out.jsonc` prints exactly `333 rows in, 75 deleted by prefix, 1 deleted for a dropped command, 1 replaced, 1 added, 258 rows out` and names `install.development.docker-dbs` |
| #4 | `bin/tinkero-update` | small | build | the script the Update row runs: dnf, mise, flatpak, each skipped when absent | `bin/tinkero-update`, `tests/test-update.sh`, `distro/fedora/replacements/omarchy-update` | `bash tests/test-update.sh` 1..6 green against stub `sudo`, `mise`, `flatpak` (order, skips, stop on dnf failure); ShellCheck clean |
| #5 | Assemble step, `%files`, allowlists | medium | build | the menu rewrite runs in `%install`; `tinkero-*` commands are packaged; both allowlists lose the menu entries | `build/assemble`, `tinkero.spec.in`, `.github/workflows/ci.yml`, `.copr/Makefile`, `ci/allow/dropped-refs.allow`, `ci/allow/arch-leak.allow`, `tests/test-assemble.sh`, `tests/fixtures/make-tree.sh` | `./dev gates` green with `dropped-refs.allow` at 7 entries and `arch-leak.allow` at 7; CI "Gates on the real upstream tree" green; `rpmspec -P tinkero.spec` green. Caveat: `python3` in the COPR mock chroot is proven only by the first `tinkero` RPM build in COPR (after 2F); `BuildRequires: python3` is the mechanism, CI's SRPM step cannot exercise it |
| #6 | Docs | small | docs | spec 4.4 and 4.7, roadmap, the README's update and status lines | `docs/superpowers/specs/2026-09-17-tinkero-design.md`, `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`, `README.md` | `./dev check` green; the reviewer checks each edit against the approved design (there is no mechanical check for prose beyond that) |

## File Structure

| File | Responsibility |
|---|---|
| `menu/apply-overrides` | the rewrite: parse the way `MenuModel.js` does, apply the rules line by line, verify the result |
| `menu/overrides.jsonc` | the data: what Tinkero deletes, replaces and adds, and the expected row count at the pinned tag |
| `tests/test_menu.py`, `tests/fixtures/menu/{menu.jsonc,overrides.jsonc,drop.list}` | unit tests of every rule and failure on a twelve-row menu |
| `bin/tinkero-update` | the Update row's script |
| `tests/test-update.sh` | `tinkero-update` against stubs |
| `build/tinkero-copr` | the maintainer tool (moved from `bin/`) |
| `build/assemble` | gains step "3b. Menu" between Replace and Relocate |
| `tinkero.spec.in` | `BuildRequires: python3`, `%{_bindir}/tinkero-*` |
| `ci/allow/*.allow` | shrink to the permanent entries |

Interfaces later plans rely on: `menu/overrides.jsonc` keys `delete`, `replace`, `add`, `expect_rows` (2D adds `learn.tinkero` through `add` and `replace`); `bin/tinkero-update` (2E's `host.md` names it; Phase 3's `tinkero-status` prints it); `build/tinkero-copr` (Phase 3's workflows call it).

---

### Task 1: Move `tinkero-copr` out of `bin/`

**Files:**
- Move: `bin/tinkero-copr` to `build/tinkero-copr`
- Modify: `build/tinkero-copr` (header comment path), `tests/test-copr.sh:20` (`T=$ROOT/build/tinkero-copr`), `.github/workflows/copr-build.yml` (the Submit step), `.github/workflows/ci.yml` (ShellCheck list), `distro/fedora/specs/README.md` (two mentions), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (the interface line)

**Why:** `build/assemble` step 6 installs every `$root/bin/tinkero-*` into `/usr/bin` of the payload. `tinkero-copr` is a maintainer tool that needs a COPR token; packaged, it would either ship in the RPM or (since `%files` will glob `tinkero-*` after Task 5) be installed on every user's machine.

- [ ] **Step 1: Move and repoint**

```bash
git mv bin/tinkero-copr build/tinkero-copr
sed -i 's|^# tinkero-copr: register|# build/tinkero-copr: register|' build/tinkero-copr
sed -i 's|^T=\$ROOT/bin/tinkero-copr|T=$ROOT/build/tinkero-copr|' tests/test-copr.sh
sed -i 's|bin/tinkero-copr "\$COMMAND"|build/tinkero-copr "$COMMAND"|' .github/workflows/copr-build.yml
sed -i 's|distro/fedora/specs/srpm.sh bin/tinkero-copr|distro/fedora/specs/srpm.sh build/tinkero-copr|' .github/workflows/ci.yml
sed -i 's|`bin/tinkero-copr|`build/tinkero-copr|g' distro/fedora/specs/README.md docs/superpowers/plans/2026-09-17-phase-2-roadmap.md
```

`build/tinkero-copr` computes `root` as the parent of its own directory (`root=${TINKERO_ROOT:-$(dirname "$here")}`), which is unchanged by the move: `build/` and `bin/` are both one level below the root.

- [ ] **Step 2: Verify**

Run: `bash tests/test-copr.sh` Expected: `1..17`, no `not ok`.
Run: `TINKERO_COPR_DRY_RUN=1 build/tinkero-copr all | grep -c '^copr-cli '` Expected: `50`.
Run: `ls bin/` Expected: empty (the directory may go; Task 4 recreates it). `git rm -r --cached bin` is not needed, git tracks files only.
Run: `grep -rn 'bin/tinkero-copr' --exclude-dir=.git .` Expected: matches only inside `docs/superpowers/plans/2026-09-22-phase-1-copr-package-set.md` (history; leave it).
Run: `shellcheck -x -e SC1090,SC1091 build/tinkero-copr tests/test-copr.sh` Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add -A bin build tests .github distro/fedora/specs/README.md docs
git commit -m "build: tinkero-copr lives in build/, not in the packaged bin/"
```

**Verification for the issue:** the four commands of Step 2, plus CI green on the PR.

---

### Task 2: `menu/apply-overrides` and its unit tests

**Files:**
- Create: `menu/apply-overrides`, `tests/test_menu.py`, `tests/fixtures/menu/menu.jsonc`, `tests/fixtures/menu/overrides.jsonc`, `tests/fixtures/menu/drop.list`
- Modify: `tests/run` (also runs the Python tests)

**Interfaces:**
- Produces: `menu/apply-overrides IN OVERRIDES DROPLIST OUT`, exit 0 and a summary line on stdout on success, exit 1 with `apply-overrides: <reason>` on stderr on any failure, OUT untouched on failure. Overrides keys: `delete` (list of id prefixes), `replace` (id to row), `add` (id to row), `expect_rows` (integer, optional).

- [ ] **Step 1: The fixtures**

`tests/fixtures/menu/menu.jsonc` (twelve rows, the shapes upstream uses: a comment header, one row per line, trailing commas, a glyph, a `when`, a `checked`, a `provider`, a leaf under a two-level submenu):

```jsonc
{
  // Fixture menu: the shapes upstream's file uses.
  "apps": {"icon":"󰀻","label":"Apps","provider":"apps"},
  "learn": {"icon":"󰧑","label":"Learn"},
  "learn.arch": {"icon":"󰣇","label":"Arch","action":"omarchy-launch-webapp 'https://wiki.archlinux.org/'"},
  "learn.hyprland": {"icon":"","label":"Hyprland","action":"omarchy-launch-webapp 'https://wiki.hypr.land/'"},
  "install": {"icon":"󰉉","label":"Install"},
  "install.gaming": {"icon":"","label":"Gaming"},
  "install.gaming.steam": {"icon":"","label":"Steam","action":"omarchy-install-gaming-steam"},
  "install.dev": {"icon":"","label":"Development"},
  "install.dev.docker-dbs": {"icon":"","label":"Docker DBs","when":"command -v docker","action":"omarchy-install-docker-dbs"},
  "update": {"icon":"","label":"Update","aliases":["refresh"]},
  "update.omarchy": {"icon":"","iconFont":"omarchy","label":"Omarchy","action":"omarchy-launch-floating-terminal-with-presentation omarchy-update"},
  "update.snap": {"icon":"","label":"Snapshot","checked":"omarchy-snapshot-enabled","action":"omarchy-snapshot create"},
}
```

(Twelve rows: `apps`, `learn`, `learn.arch`, `learn.hyprland`, `install`, `install.gaming`, `install.gaming.steam`, `install.dev`, `install.dev.docker-dbs`, `update`, `update.omarchy`, `update.snap`.)

`tests/fixtures/menu/overrides.jsonc`:

```jsonc
{
  // Fixture overrides: one of each rule.
  "delete": ["install.gaming", "learn.arch"],
  "replace": {
    "update.omarchy": {"icon":"","iconFont":"omarchy","label":"Packages","action":"omarchy-launch-floating-terminal-with-presentation tinkero-update"},
  },
  "add": {
    "learn.fedora": {"icon":"","label":"Fedora","action":"omarchy-launch-webapp 'https://docs.fedoraproject.org/'"},
  },
  "expect_rows": 9,
}
```

`tests/fixtures/menu/drop.list`:

```
# fixture drop list: two exact names and one glob
bin/omarchy-install-docker-dbs
bin/omarchy-snapshot
bin/omarchy-plymouth-*
```

Expected outcome on the fixture: `install.gaming` and `install.gaming.steam` deleted by prefix, `learn.arch` by prefix, `install.dev.docker-dbs` (its action is a dropped name) and `update.snap` (its action is `omarchy-snapshot create`; its `checked`, `omarchy-snapshot-enabled`, would not match on its own, because matching is on whole words) by dropped command, `update.omarchy` replaced, `learn.fedora` added: 12 in, 3 by prefix, 2 by dropped command, 1 replaced, 1 added, 8 rows out. The fixture's `expect_rows` is deliberately 9 so that one test can assert the mismatch message; the tests that expect success pass their own overrides file with the right count (see the test file).

- [ ] **Step 2: Write the failing tests**

`tests/test_menu.py`:

```python
#!/usr/bin/env python3
"""menu/apply-overrides against the twelve-row fixture menu: every rule and every failure."""
import json
import os
import re
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "menu", "apply-overrides")
FIX = os.path.join(ROOT, "tests", "fixtures", "menu")
MENU = os.path.join(FIX, "menu.jsonc")
DROP = os.path.join(FIX, "drop.list")


def strip_jsonc(raw):
    raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
    return re.sub(r",(\s*[}\]])", r"\1", raw)


def rows(path):
    with open(path, encoding="utf-8") as f:
        return json.loads(strip_jsonc(f.read()))


class ApplyOverrides(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="tinkero-menu.")
        self.out = os.path.join(self.tmp, "out.jsonc")

    def overrides(self, **changes):
        """The fixture overrides with expect_rows corrected (8) and any key replaced."""
        ov = rows(os.path.join(FIX, "overrides.jsonc"))
        ov["expect_rows"] = 8
        ov.update(changes)
        path = os.path.join(self.tmp, "overrides.jsonc")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(ov, f, ensure_ascii=False)
        return path

    def run_tool(self, overrides, menu=MENU, drop=DROP):
        return subprocess.run([TOOL, menu, overrides, drop, self.out],
                              capture_output=True, text=True)

    def test_summary_and_exit(self):
        r = self.run_tool(self.overrides())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("12 rows in, 3 deleted by prefix, 2 deleted for a dropped command, "
                      "1 replaced, 1 added, 8 rows out", r.stdout)

    def test_delete_by_prefix_takes_children(self):
        self.run_tool(self.overrides())
        out = rows(self.out)
        for gone in ("install.gaming", "install.gaming.steam", "learn.arch"):
            self.assertNotIn(gone, out)
        self.assertIn("install", out)

    def test_delete_rows_calling_dropped_commands_and_log_them(self):
        r = self.run_tool(self.overrides())
        out = rows(self.out)
        self.assertNotIn("install.dev.docker-dbs", out)   # action names an exact dropped name
        self.assertNotIn("update.snap", out)              # action names omarchy-snapshot
        self.assertIn("apply-overrides: deleted install.dev.docker-dbs (calls a dropped command)", r.stdout)
        self.assertIn("apply-overrides: deleted update.snap (calls a dropped command)", r.stdout)

    def test_dropped_match_is_whole_word(self):
        # omarchy-snapshot-enabled must not match the dropped omarchy-snapshot
        menu = os.path.join(self.tmp, "menu.jsonc")
        with open(MENU, encoding="utf-8") as f:
            text = f.read().replace('"action":"omarchy-snapshot create"', '"action":"true"')
        with open(menu, "w", encoding="utf-8") as f:
            f.write(text)
        r = self.run_tool(self.overrides(expect_rows=9), menu=menu)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("update.snap", rows(self.out))

    def test_dropped_glob(self):
        menu = os.path.join(self.tmp, "menu.jsonc")
        with open(MENU, encoding="utf-8") as f:
            text = f.read().replace('"action":"omarchy-snapshot create"', '"action":"omarchy-plymouth-set dark"')
        with open(menu, "w", encoding="utf-8") as f:
            f.write(text)
        r = self.run_tool(self.overrides(), menu=menu)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("update.snap", rows(self.out))

    def test_replace_writes_the_new_row_in_place(self):
        self.run_tool(self.overrides())
        out = rows(self.out)
        self.assertEqual(out["update.omarchy"]["label"], "Packages")
        self.assertEqual(out["update.omarchy"]["action"],
                         "omarchy-launch-floating-terminal-with-presentation tinkero-update")
        with open(self.out, encoding="utf-8") as f:
            lines = f.read().splitlines()
        idx = [i for i, l in enumerate(lines) if l.startswith('  "update.omarchy"')]
        self.assertEqual(len(idx), 1)
        self.assertTrue(lines[idx[0] - 1].startswith('  "update"'))   # still right after its parent

    def test_add_appends_a_tinkero_block(self):
        self.run_tool(self.overrides())
        out = rows(self.out)
        self.assertEqual(out["learn.fedora"]["label"], "Fedora")
        with open(self.out, encoding="utf-8") as f:
            text = f.read()
        self.assertIn("// Tinkero additions (menu/overrides.jsonc)", text)

    def test_only_rows_change(self):
        self.run_tool(self.overrides())
        with open(MENU, encoding="utf-8") as f:
            before = f.read().splitlines()
        with open(self.out, encoding="utf-8") as f:
            after = f.read().splitlines()
        removed = [l for l in before if l not in after]
        added = [l for l in after if l not in before]
        self.assertEqual(len(removed), 6)   # 5 deleted rows + the replaced row's old line
        self.assertTrue(all(l.lstrip().startswith('"') for l in removed))
        self.assertEqual(len([l for l in added if l.lstrip().startswith('"')]), 2)  # replaced + added
        self.assertIn("  // Fixture menu: the shapes upstream's file uses.", after)   # comments survive

    def test_output_parses_like_upstream(self):
        self.run_tool(self.overrides())
        self.assertEqual(len(rows(self.out)), 8)

    def test_unmatched_delete_prefix_fails(self):
        r = self.run_tool(self.overrides(delete=["install.gaming", "learn.arch", "install.windows"]))
        self.assertEqual(r.returncode, 1)
        self.assertIn("delete prefixes matching no row: ['install.windows']", r.stderr)
        self.assertFalse(os.path.exists(self.out))

    def test_replace_of_unknown_id_fails(self):
        r = self.run_tool(self.overrides(replace={"update.nope": {"label": "x"}}))
        self.assertEqual(r.returncode, 1)
        self.assertIn("replace ids not in upstream menu: ['update.nope']", r.stderr)

    def test_add_of_existing_id_fails(self):
        r = self.run_tool(self.overrides(add={"learn.hyprland": {"label": "x"}}))
        self.assertEqual(r.returncode, 1)
        self.assertIn("add ids already in upstream menu: ['learn.hyprland']", r.stderr)

    def test_orphan_fails(self):
        # deleting "learn" alone is fine (children go too); an add under a deleted parent is an orphan
        r = self.run_tool(self.overrides(delete=["install.gaming", "learn"],
                                         add={"learn.fedora": {"label": "Fedora", "action": "true"}}))
        self.assertEqual(r.returncode, 1)
        self.assertIn("orphan row learn.fedora: parent learn was deleted", r.stderr)

    def test_expect_rows_mismatch_fails(self):
        r = self.run_tool(os.path.join(FIX, "overrides.jsonc"))   # the fixture says 9, reality is 8
        self.assertEqual(r.returncode, 1)
        self.assertIn("expect_rows is 9 but the rewritten menu has 8 rows", r.stderr)
        self.assertFalse(os.path.exists(self.out))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' -v` Expected: every test errors (`menu/apply-overrides` does not exist).

- [ ] **Step 4: Write the tool**

`menu/apply-overrides` (mode 0755):

```python
#!/usr/bin/env python3
"""apply-overrides IN OVERRIDES DROPLIST OUT: rewrite upstream's default menu at build time.

Design spec 4.4. Line-oriented on purpose: every upstream row is one line keyed by its
id, so deleting, replacing and adding whole lines keeps upstream's comments and layout,
and a diff of OUT against IN shows exactly the rows Tinkero changed.

Rules, in this order:
  1. delete every row whose id equals a prefix in OVERRIDES "delete" or starts with "prefix."
  2. delete every row whose action, when or checked mentions a dropped command: the bin/
     lines of DROPLIST, "*" globs allowed, matched as whole words (the same rule as
     ci/gate-dropped-refs)
  3. replace the rows in "replace" (the id must exist upstream); append the rows in "add"
     (the id must not exist upstream) as a Tinkero block before the closing brace
  4. fail, leaving OUT untouched, on: a delete prefix that matched nothing, a replace id
     that does not exist or that rule 1 or 2 removed, an add id that exists, a row whose
     parent is gone (an orphan), an OUT that upstream's parser would reject, or a row
     count different from "expect_rows" when that key is present
"""
import json
import re
import sys

ROW = re.compile(r'^(\s*)"([a-z0-9.-]+)"\s*:\s*(\{.*\})\s*,?\s*$')


def strip_jsonc(raw):
    """Exact port of stripJsonc in shell/plugins/menu/MenuModel.js: full-line // comments
    and trailing commas. Nothing else is JSONC to upstream, so nothing else is to us."""
    raw = re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M)
    return re.sub(r',(\s*[}\]])', r'\1', raw)


def parse(text, what):
    try:
        data = json.loads(strip_jsonc(text))
    except json.JSONDecodeError as e:
        fail(f"{what} does not parse the way MenuModel.js parses it: {e}")
    if not isinstance(data, dict):
        fail(f"{what}: top level is not an object")
    return data


def fail(msg):
    sys.exit(f"apply-overrides: {msg}")


def dropped_pattern(droplist):
    names = []
    with open(droplist, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("bin/"):
                continue
            name = line[len("bin/"):]
            if re.search(r'[?\[]', name):
                fail(f"unsupported glob in drop list line: {line} (only * is supported)")
            names.append(re.escape(name).replace(r'\*', '[a-z0-9-]*'))
    if not names:
        return None
    return re.compile(r'(?:^|[^a-z0-9-])(?:%s)(?:[^a-z0-9-]|$)' % "|".join(names))


def row_line(indent, id_, row):
    return f'{indent}"{id_}": {json.dumps(row, ensure_ascii=False, separators=(",", ":"))},\n'


def main(argv):
    if len(argv) != 5:
        sys.exit("usage: apply-overrides IN OVERRIDES DROPLIST OUT")
    src, ov_path, droplist, out = argv[1:]
    with open(src, encoding="utf-8") as f:
        text = f.read()
    rows_in = parse(text, src)
    with open(ov_path, encoding="utf-8") as f:
        ov = parse(f.read(), ov_path)
    prefixes = ov.get("delete", [])
    replace = ov.get("replace", {})
    add = ov.get("add", {})
    expect = ov.get("expect_rows")
    dropped = dropped_pattern(droplist)

    lines = text.splitlines(keepends=True)
    ids_on_lines = {m.group(2) for m in map(ROW.match, lines) if m}
    if ids_on_lines != set(rows_in):
        odd = sorted(ids_on_lines ^ set(rows_in))
        fail(f"rows are not one per line, cannot rewrite safely: {odd[:5]}")

    kept, by_prefix, by_dropped, replaced = [], [], [], []
    hit = set()
    for line in lines:
        m = ROW.match(line)
        if not m:
            kept.append(line)
            continue
        indent, id_, _ = m.groups()
        pfx = next((p for p in prefixes if id_ == p or id_.startswith(p + ".")), None)
        if pfx is not None:
            hit.add(pfx)
            by_prefix.append(id_)
            continue
        row = rows_in[id_]
        fields = " ".join(str(row.get(k, "")) for k in ("action", "when", "checked"))
        if dropped and dropped.search(fields):
            by_dropped.append(id_)
            continue
        if id_ in replace:
            kept.append(row_line(indent, id_, replace[id_]))
            replaced.append(id_)
            continue
        kept.append(line)

    problems = []
    unused = sorted(set(prefixes) - hit)
    if unused:
        problems.append(f"delete prefixes matching no row: {unused}")
    not_found = sorted(set(replace) - set(rows_in))
    if not_found:
        problems.append(f"replace ids not in upstream menu: {not_found}")
    lost = sorted(set(replace) & (set(by_prefix) | set(by_dropped)))
    if lost:
        problems.append(f"replace ids that the delete rules removed: {lost}")
    dup = sorted(set(add) & set(rows_in))
    if dup:
        problems.append(f"add ids already in upstream menu: {dup}")

    if add:
        close = max(i for i, l in enumerate(kept) if l.strip() == "}")
        block = ["\n", "  // Tinkero additions (menu/overrides.jsonc)\n"]
        block += [row_line("  ", id_, row) for id_, row in add.items()]
        kept[close:close] = block

    result = "".join(kept)
    rows_out = parse(result, "the rewritten menu")
    for id_ in rows_out:
        parent = id_.rpartition(".")[0]
        if parent and parent not in rows_out:
            problems.append(f"orphan row {id_}: parent {parent} was deleted")
    if expect is not None and len(rows_out) != expect:
        problems.append(f"expect_rows is {expect} but the rewritten menu has {len(rows_out)} rows "
                        "(an upstream change; check the diff, then update expect_rows)")
    if problems:
        fail("; ".join(problems))

    with open(out, "w", encoding="utf-8") as f:
        f.write(result)
    for id_ in by_dropped:
        print(f"apply-overrides: deleted {id_} (calls a dropped command)")
    print(f"apply-overrides: {len(rows_in)} rows in, {len(by_prefix)} deleted by prefix, "
          f"{len(by_dropped)} deleted for a dropped command, {len(replaced)} replaced, "
          f"{len(add)} added, {len(rows_out)} rows out")


if __name__ == "__main__":
    main(sys.argv)
```

- [ ] **Step 5: `tests/run` runs the Python tests too**

Replace `tests/run` with:

```bash
#!/bin/bash
# Run every tests/test-*.sh and the Python tests (tests/test_*.py); exit non-zero if any fails.
cd "$(dirname "$0")/.." || exit 2
rc=0
for t in tests/test-*.sh; do
  echo "# $t"
  bash "$t" || rc=1
done
echo "# python3 -m unittest (tests/test_*.py)"
python3 -m unittest discover -s tests -p 'test_*.py' || rc=1
exit $rc
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' -v` Expected: `Ran 14 tests`, `OK`.
Run: `./dev check` Expected: every shell suite green as before, then the unittest line, exit 0.

- [ ] **Step 7: Commit**

```bash
git add menu tests/test_menu.py tests/fixtures/menu tests/run
git commit -m "menu: apply-overrides rewrites the default menu line by line, with tests"
```

**Verification for the issue:** Step 6's two commands, plus CI green on the PR (CI runs `./dev check`, so the container needs `python3`: Task 5 adds it to the tool install; until then CI's `fedora:44` image already carries `python3`, which the implementer confirms by the CI run and records under Deviations if it does not).

---

### Task 3: `menu/overrides.jsonc` for `v4.0.4`

**Files:**
- Create: `menu/overrides.jsonc`

- [ ] **Step 1: The data**

```jsonc
{
  // Tinkero's build-time edits to upstream's default menu (design spec 4.4, audit section 7),
  // applied by menu/apply-overrides during build/assemble. Rules:
  //   delete   id prefixes: the id itself and every "prefix." child
  //   replace  id -> whole row; the id must exist upstream (a rename fails the build)
  //   add      id -> whole row; the id must not exist upstream
  //   expect_rows  the row count after the rewrite at the pinned upstream tag; the bump
  //                checklist updates it after reading the upstream diff
  // Rows whose action, when or checked call a dropped command (build/drop.list) are deleted
  // without being listed here; the build log names them.
  "delete": [
    // Arch package machinery and the AUR
    "install.package", "install.aur", "remove.package",
    // upstream's app catalogue: web apps, gaming, the Windows VM, preinstalls, AI desktop apps, services
    "install.webapp", "install.gaming", "install.windows", "install.preinstalls", "install.ai", "install.service",
    "remove.webapp", "remove.gaming", "remove.windows", "remove.preinstalls", "remove.ai", "remove.service",
    // Emacs is an Omarchy-repo package
    "install.editor.emacs",
    // Omarchy's update channels and Plymouth (Fedora's boot stays as it is)
    "update.channel", "update.config.plymouth",
    // system policy Tinkero does not touch: direct boot, factory reset, passwordless sudo, FIDO2, sudoless docker, hybrid GPU
    "setup.direct-boot", "setup.reset", "setup.security.passwordless-sudo",
    "setup.security.fido2", "remove.security.fido2",
    "setup.security.sudoless-docker", "remove.security.sudoless-docker",
    "trigger.hardware.hybrid-gpu",
    // the lock-screen style switcher (upstream's PAM shape; plan 2F owns the lock screen)
    "style.unlock",
    // the Arch wiki link (learn.fedora is added below)
    "learn.arch",
  ],
  "replace": {
    // update.omarchy ran omarchy-update; Tinkero updates through dnf, mise and flatpak (spec 4.7)
    "update.omarchy": {"icon":"","iconFont":"omarchy","label":"Packages","action":"omarchy-launch-floating-terminal-with-presentation tinkero-update"},
  },
  "add": {
    "learn.fedora": {"icon":"","label":"Fedora","action":"omarchy-launch-webapp 'https://docs.fedoraproject.org/'"},
  },
  "expect_rows": 258,
}
```

The 28 prefixes are the audit's list minus `setup.default.agent.openclaw` (2B kept OpenClaw). The icon of `update.omarchy` is upstream's own glyph (the Omarchy mark in the `omarchy` icon font); 2D replaces the glyph in the font, not this row. The `learn.fedora` glyph is the Nerd Font Fedora logo, `U+F30A`.

- [ ] **Step 2: Verify against the real tree**

`./dev payload` needs the upstream tarball (`build/fetch-upstream` fetches and verifies it into `.cache/`; network, allowed outside tests). Then:

```bash
mkdir -p .cache/tree && tar -xzf .cache/omarchy-*.tar.gz -C .cache/tree --strip-components=1
python3 menu/apply-overrides .cache/tree/default/omarchy/omarchy-menu.jsonc menu/overrides.jsonc build/drop.list /tmp/tinkero-menu.jsonc
```

Expected, exactly:

```
apply-overrides: deleted install.development.docker-dbs (calls a dropped command)
apply-overrides: 333 rows in, 75 deleted by prefix, 1 deleted for a dropped command, 1 replaced, 1 added, 258 rows out
```

Then: `diff .cache/tree/default/omarchy/omarchy-menu.jsonc /tmp/tinkero-menu.jsonc | grep -c '^<'` Expected: `77` (76 deleted rows plus the replaced row's old line), and `diff ... | grep '^<' | grep -vc '^<\s*"'` Expected: `0` (no comment or brace was removed).

- [ ] **Step 3: Commit**

```bash
git add menu/overrides.jsonc
git commit -m "menu: overrides for v4.0.4 (28 prefixes, Packages update row, learn.fedora)"
```

**Verification for the issue:** Step 2's summary line and the two diff counts, verbatim, plus CI green.

---

### Task 4: `bin/tinkero-update`

**Files:**
- Create: `bin/tinkero-update`, `tests/test-update.sh`
- Modify: `distro/fedora/replacements/omarchy-update` (the message names `tinkero-update`)

- [ ] **Step 1: Write the failing test**

`tests/test-update.sh`:

```bash
#!/bin/bash
# bin/tinkero-update against stub sudo, mise and flatpak: order, skips, and stopping on failure.
source "$(dirname "$0")/lib.sh"
d=$(mktmp); mkdir -p "$d/bin" "$d/bin-nomise"; export LOG=$d/log
# shellcheck disable=SC2016  # the stubs log their own $* at run time
for s in sudo mise flatpak; do
  printf '#!/bin/bash\necho "%s $*" >> "$LOG"\n[[ ${FAIL_%s:-} == 1 ]] && exit 1\nexit 0\n' "$s" "$(tr a-z A-Z <<<"$s")" > "$d/bin/$s"
  chmod +x "$d/bin/$s"
done
cp "$d/bin/sudo" "$d/bin-nomise/sudo"   # a PATH with sudo only: no mise, no flatpak
T=$ROOT/bin/tinkero-update
: > "$LOG"; out=$(PATH=$d/bin:/usr/bin:/bin "$T" 2>&1); rc=$?
assert_eq "$rc" 0 "all three present: exit 0"
assert_eq "$(paste -sd'|' "$LOG")" "sudo dnf upgrade --refresh|mise up|flatpak update" "runs dnf, then mise, then flatpak"
: > "$LOG"; out=$(PATH=$d/bin-nomise:/usr/bin:/bin "$T" 2>&1); rc=$?
assert_eq "$rc" 0 "mise and flatpak absent: still exit 0"
assert_eq "$(paste -sd'|' "$LOG")" "sudo dnf upgrade --refresh" "only dnf ran"
assert_contains "$out" "mise not installed, skipped" "says mise was skipped"
: > "$LOG"; FAIL_SUDO=1 PATH=$d/bin:/usr/bin:/bin "$T" >/dev/null 2>&1; rc=$?
assert_eq "$rc:$(wc -l < "$LOG")" "1:1" "dnf failing stops the script before mise"
rm -rf "$d"; finish
```

(Six assertions: `1..6`.) The stubs put `/usr/bin:/bin` after the stub dir only so that `paste`, `wc` and bash builtins keep working; `dnf` itself is never on the stub `PATH`, and the script never calls it without `sudo`, so the real one cannot run.

Run: `bash tests/test-update.sh` Expected: fails (`bin/tinkero-update` missing).

- [ ] **Step 2: The script**

`bin/tinkero-update` (mode 0755):

```bash
#!/bin/bash
# tinkero-update: update everything Tinkero installs (design spec 4.7). The menu's
# Update > Packages row runs this in a floating terminal, so it is interactive on purpose.
#   sudo dnf upgrade --refresh   the RPMs, the COPR set included
#   mise up                      the tools mise manages (agent CLIs, optional extras)
#   flatpak update               the applications the menu installs as Flatpaks
# A missing mise or flatpak is skipped; a failing step stops the script.
set -euo pipefail
sudo dnf upgrade --refresh
if command -v mise >/dev/null 2>&1; then mise up; else echo "tinkero-update: mise not installed, skipped"; fi
if command -v flatpak >/dev/null 2>&1; then flatpak update; else echo "tinkero-update: flatpak not installed, skipped"; fi
```

And `distro/fedora/replacements/omarchy-update` becomes:

```bash
#!/bin/bash

# omarchy:summary=Explain how Tinkero is updated

echo "Tinkero updates through 'tinkero-update' (dnf, mise and flatpak); see tinkero-status."
```

- [ ] **Step 3: Verify**

Run: `bash tests/test-update.sh` Expected: `1..6`, no `not ok`.
Run: `./dev check` Expected: green (`tests/test-replacements.sh` may assert the old message; if it does, update that assertion to the new text and note it under Deviations).
Run: `shellcheck -x -e SC1090,SC1091 bin/tinkero-update tests/test-update.sh` Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add bin/tinkero-update tests/test-update.sh distro/fedora/replacements/omarchy-update
git commit -m "build: tinkero-update runs dnf, mise and flatpak; the Update row's script"
```

**Verification for the issue:** Step 3's three commands, plus CI green. No real package manager runs anywhere in the test.

---

### Task 5: Assemble step, `%files`, allowlists

**Files:**
- Modify: `build/assemble` (new step between 3 and 4), `tinkero.spec.in` (`BuildRequires`, `%files`), `.github/workflows/ci.yml` (tool install, ShellCheck list), `.copr/Makefile` (`srpm-tinkero` tool install), `ci/allow/dropped-refs.allow`, `ci/allow/arch-leak.allow`, `tests/fixtures/make-tree.sh`, `tests/test-assemble.sh`

- [ ] **Step 1: Fixture and failing tests**

In `tests/fixtures/make-tree.sh`, replace the line `echo '{}' > "$top/default/omarchy/omarchy-menu.jsonc"` with a three-row menu:

```bash
cat > "$top/default/omarchy/omarchy-menu.jsonc" <<'J'
{
  // fixture menu
  "learn": {"icon":"","label":"Learn"},
  "learn.arch": {"icon":"","label":"Arch","action":"omarchy-launch-webapp 'https://wiki.archlinux.org/'"},
  "update": {"icon":"","label":"Update"},
  "update.snap": {"icon":"","label":"Snapshot","action":"omarchy-snapshot create"},
}
J
```

`tests/test-assemble.sh` builds a fixture root `$r` (with `build/drop.list`, `patches/`, `distro/fedora/...`); read how it is built, then add to that root `menu/overrides.jsonc`:

```bash
mkdir -p "$r/menu"; cp "$ROOT/menu/apply-overrides" "$r/menu/"
cat > "$r/menu/overrides.jsonc" <<'J'
{"delete": ["learn.arch"], "expect_rows": 2}
J
```

(`update.snap` goes because the fixture drop list already drops `bin/omarchy-snapshot`, see `make-tree.sh`; that leaves `learn` and `update`.) Then add these cases after the existing "Replace" assertions:

```bash
# 3b. Menu: the default menu is rewritten in place, in the tree, before relocation
menu=$dest/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc
assert_file "$menu" "menu: still shipped at upstream's path"
assert_eq "$(grep -c '^\s*"' "$menu")" 2 "menu: two rows survive the fixture overrides"
assert_contains "$(cat "$menu")" "// fixture menu" "menu: upstream's comment survives"
if grep -q "learn.arch\|omarchy-snapshot" "$menu"; then not_ok "menu: deleted rows are gone"; else ok "menu: deleted rows are gone"; fi
assert_contains "$out" "apply-overrides: 4 rows in, 1 deleted by prefix, 1 deleted for a dropped command, 0 replaced, 0 added, 2 rows out" "menu: assemble logs the summary"
# a wrong expect_rows fails the build
sed -i 's/"expect_rows": 2/"expect_rows": 3/' "$r/menu/overrides.jsonc"
assert_fails "menu: expect_rows mismatch fails assemble" run "$d/dest-badmenu"
sed -i 's/"expect_rows": 3/"expect_rows": 2/' "$r/menu/overrides.jsonc"
```

`$out` is the captured stdout of the `run` that produced `$dest`; if the existing test does not capture it, capture it for this case (`out=$(run "$dest")`). Follow the file's existing pattern for restoring the fixture after a destructive case (the 2B review asked for it).

Run: `bash tests/test-assemble.sh` Expected: the new cases fail (no menu step yet; four rows survive).

- [ ] **Step 2: The assemble step**

In `build/assemble`, between step 3 (Replace) and step 4 (Relocate):

```bash
# 3b. Menu. Upstream's default menu, rewritten by menu/overrides.jsonc (design spec 4.4).
# Rows that call a dropped command go too, so the drop list and the menu cannot disagree.
menu=$tree/default/omarchy/omarchy-menu.jsonc
if [[ -f $root/menu/overrides.jsonc ]]; then
  python3 "$root/menu/apply-overrides" "$menu" "$root/menu/overrides.jsonc" "$root/build/drop.list" "$menu.tinkero" \
    || die "menu rewrite failed (see apply-overrides output above)"
  mv "$menu.tinkero" "$menu"
fi
```

- [ ] **Step 3: Packaging and CI**

`tinkero.spec.in`: `BuildRequires:  git-core python3` and, in `%files`, after `%{_bindir}/omarchy*`, add `%{_bindir}/tinkero-*`.

`.github/workflows/ci.yml`: add `python3` to the `dnf -y install` line of the Tools step (the image likely has it; naming it keeps the build explicit). Nothing else: the "Gates on the real upstream tree" step already runs `./dev gates`, which now includes the menu rewrite and will fail on stale allowlist entries until Step 4 is done.

`.copr/Makefile`, `srpm-tinkero`: `dnf -y install git-core curl rpm-build python3`. (The SRPM step does not run `assemble`; `BuildRequires` covers the mock phase. This line only keeps the two environments alike.)

- [ ] **Step 4: Shrink the allowlists**

`ci/allow/dropped-refs.allow`: delete every `usr/share/omarchy/default/omarchy/omarchy-menu.jsonc:*` line (36 lines). What stays, seven entries:

```
usr/bin/omarchy-bar:omarchy-migrate   # comment only, permanent
usr/bin/omarchy-provision-user:omarchy-provision-owner   # plan 2E
usr/share/omarchy/default/bash/env-bootstrap:omarchy-dev-link   # comment only, permanent
usr/share/omarchy/default/bash/env-bootstrap:omarchy-dev-unlink   # comment only, permanent
usr/share/omarchy/default/hypr/bindings/applications.lua:omarchy-launch-docker-tui   # gated binding; returns with Docker
usr/share/omarchy/default/systemd/zram-generator.conf.d/90-omarchy.conf:omarchy-hibernation-setup   # comment only, permanent
usr/share/omarchy/install/user/mise-work.sh:omarchy-provision-owner   # comment only, permanent
```

`ci/allow/arch-leak.allow`: delete the line `usr/share/omarchy/default/omarchy/omarchy-menu.jsonc   # learn.arch row; plan 2C`. Seven entries remain.

- [ ] **Step 5: Verify**

Run: `bash tests/test-assemble.sh` Expected: green, count grown by 6.
Run: `./dev check` Expected: green.
Run: `./dev gates` Expected: all four gates `PASS`; the assemble log contains the summary line from Task 3 (`258 rows out`).
Run: `grep -vc '^#' ci/allow/dropped-refs.allow` Expected: `7`. `grep -vc '^#' ci/allow/arch-leak.allow` Expected: `7`.
Run: `./dev spec && rpmspec -P tinkero.spec >/dev/null && rpmlint tinkero.spec` (in CI if `rpmspec` is not installed locally) Expected: green.

- [ ] **Step 6: Commit**

```bash
git add build/assemble tinkero.spec.in .github/workflows/ci.yml .copr/Makefile ci/allow tests/fixtures/make-tree.sh tests/test-assemble.sh
git commit -m "build: assemble rewrites the menu; tinkero-* commands are packaged; allowlists lose the menu rows"
```

**Verification for the issue:** Step 5's commands, CI green on the PR (the gates step against the real tree is the proof that the menu has no dropped-command references left). **Caveat, stated on the issue:** `python3` inside COPR's mock chroot for the `tinkero` RPM is provided by `BuildRequires: python3` and is exercised only by the first real `tinkero` build in COPR, which this plan does not run (the RPM is not installable before 2F). CI's SRPM step (`rpmbuild -bs`) does not run `%install`.

---

### Task 6: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-17-tinkero-design.md` (4.4, 4.7, the status line), `docs/superpowers/plans/2026-09-17-phase-2-roadmap.md` (2C row, a "What executing 2C added" section), `README.md` (the Principles line "Updates stay `dnf upgrade` and `mise up`. Nothing rolls under you." becomes "Updates stay `tinkero-update`: `dnf upgrade`, `mise up`, `flatpak update`. Nothing rolls under you."; the Status paragraph's first sentence becomes "Build under way; the roadmap is [`docs/superpowers/plans/2026-09-17-phase-2-roadmap.md`](docs/superpowers/plans/2026-09-17-phase-2-roadmap.md) and the contribution loop is [`docs/guides/workflow.md`](docs/guides/workflow.md).")

- [ ] **Step 1: Spec 4.4**

Append to the paragraph starting "So `menu/apply-overrides` rewrites":

```
- **add**: rows upstream lacks, appended as a Tinkero block; 2C adds `learn.fedora` (the Fedora docs) where `learn.arch` was.

The rewrite is line-oriented, because every upstream row is one line keyed by its id: upstream's comments and layout survive, and a diff against upstream shows exactly Tinkero's rows. `expect_rows` in `menu/overrides.jsonc` pins the row count at the pinned tag (258 at `v4.0.4`, from 333), so an upstream change to the menu fails the build until the bump checklist has looked at it. Done 2026-09-XX (plan 2C).
```

(Replace `XX` with the merge date of Task 5.) In the same section, change "`update.omarchy` becomes "Update (dnf + mise)" and runs `tinkero-update` in a floating terminal (`sudo dnf upgrade`, then `mise up`)" to "`update.omarchy` becomes "Packages" and runs `tinkero-update` in a floating terminal (4.7)".

- [ ] **Step 2: Spec 4.7**

Change "On every machine: `sudo dnf upgrade` and `mise up`. Nothing else, ever. The menu's Update entry runs exactly that." to:

```
On every machine: `sudo dnf upgrade --refresh`, `mise up`, and `flatpak update` when Flatpak is installed (the menu installs eleven applications as Flatpaks through the name map, so they update through the same entry). Nothing else, ever. `tinkero-update` is exactly that, and the menu's Update > Packages row runs it in a floating terminal.
```

Status line (line 4): append "; 2C (menu rewrite) done 2026-09-XX".

- [ ] **Step 3: Roadmap**

In the table, the 2C row's Status becomes `**done** 2026-09-XX: `2026-09-23-phase-2c-menu-rewrite.md`; first plan through the issue loop`. Add a section before "## What executing 2A added to the queue":

```
## What executing 2C added to the queue (2026-09-XX)

- **2D:** `learn.omarchy` becomes `learn.tinkero` through `replace` in `menu/overrides.jsonc` (label "Tinkero", the README as a web app or `omarchy-launch-webapp` on the repo); the `update.omarchy` row keeps upstream's glyph, which 2D's font work rebrands.
- **Bump checklist (Phase 3):** after a tag bump, run `apply-overrides` on the new tree, read the deleted-for-dropped-command lines and the row count, update `expect_rows`. A new upstream row that calls a dropped script is deleted automatically; a renamed id in `delete` or `replace` fails the build.
- **Permanent allowlist entries, final:** dropped-refs 7 (five comment-only, the Docker binding, `omarchy-provision-user` until 2E); arch-leak 7 (six comment-only, `omarchy-setup-security-fingerprint` until 2F).
- **Housekeeping done:** `tinkero-copr` moved to `build/`; `bin/` holds only packaged commands (`%{_bindir}/tinkero-*`).
```

- [ ] **Step 4: Verify and commit**

Run: `./dev check` Expected: green. Run: `grep -n "—" docs/superpowers/specs/2026-09-17-tinkero-design.md docs/superpowers/plans/2026-09-17-phase-2-roadmap.md | grep -v "^.*:.*Omedora"` Expected: no new em dashes in what you wrote.

```bash
git add docs README.md
git commit -m "docs: 2C done, the menu is rewritten at build time and tinkero-update exists"
```

**Verification for the issue:** `./dev check` green; the PR reviewer reads each edit against the approved design (spec 4.4/4.7 as written above). There is no mechanical verification of prose beyond that; the issue says so.

---

## Deviations

- **Tasks 2 to 6, 2026-09-23 (issue #13):** landed as one PR. Issue #13 superseded issues #2 to #6; the tasks were built serially on one branch, each as its own commit until the squash, each with its own implementer and reviewer.
- **Task 2:** the plan's JSON blocks lost every private-use glyph of the Basic Multilingual Plane when the plan was committed (the fixture rows read `"icon":""`). The fixture keeps the empty icons; no test reads them. The test file gains a `tearDown` that removes its temporary directories.
- **Task 3:** the same loss hit the `update.omarchy` replacement and the `learn.fedora` row. `menu/overrides.jsonc` carries the glyphs the prose names: U+E900 (upstream's own glyph, `omarchy` icon font) for `update.omarchy` and U+F30A (the Nerd Font Fedora logo) for `learn.fedora`. Copying the plan's block verbatim reproduces the defect; copy the file instead.
- **Task 4:** `tests/test-update.sh` builds the stub names with `tr '[:lower:]' '[:upper:]'`, not the plan's `tr a-z A-Z`, which ShellCheck flags (SC2018, SC2019) and CI would reject.
- **Task 5:** the plan's test snippet named `$dest`; the test's variable is `$d/dest`. `.gitignore` gains `__pycache__/`, which the Python tests leave under `tests/`. `rpmspec` and `rpmlint` were not installed on the build host; the spec renders locally and CI proves that it parses and lints. The `expect_rows` mismatch case asserts on the build's message (the file's idiom, count 37), not `assert_fails`; the assemble header names the menu inputs.
- **Task 6:** spec 4.4 said 77 of 333 entries go by prefix; the measured rewrite deletes 75 by prefix and one more by action, and the section says so now. Section 4.7 no longer counts the Flatpak rows (the plan said eleven; the name map has nine).

## What this plan deliberately leaves out

- Rebranding menu strings (`learn.omarchy`, "Omarchy" labels): 2D, through the same `replace` key.
- A system-level menu extension path upstream (the PR the spec mentions): Phase 4.
- Building the `tinkero` RPM in COPR: not until the tree is installable (2E, 2F).
