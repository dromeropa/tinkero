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
