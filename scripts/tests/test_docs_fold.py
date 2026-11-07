"""Tests for tooling/docs/fold.py: GAP and CHANGELOG-LEGACY fragments (#612). Synthetic files in a temporary directory."""
import contextlib
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "docs"))

import fold  # noqa: E402

COLS = "| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |\n|---|---|---|---|---|---|---|---|---|\n"


def gap_row(n, gap="same", h1="a"):
    return f"| GAP-{n} | F{n} | L | ref | S | LOT-1 | {gap} | port: x | {h1} |"


CHANGELOG = """# Changelog

| # | Section | Résumé (FR) | Lot / PR | Preuve legacy |
|---|---|---|---|---|
| 1 | T | Un. | LOT-1 | p1 |
| 2 | UX | Deux. | LOT-2 | p2 |

Points non corrigés.
"""


def gap_text():
    rows_nav = "\n".join([gap_row("001"), gap_row("002", "UX change", "b")])
    rows_read = "\n".join([gap_row("050", "new", "a"), gap_row("229", "UX change", "b·needed")])
    return f"""# Gap

## Navigation

{COLS}{rows_nav}

## Reader

{COLS}{rows_read}

## Counts

| Gap | Rows |
|---|---|
| stale | 0 |

## Convergence classification (H.1)

### GAP rows of type `ported with changes`, `UX change` or `new` (0)

| H.1 | Rows | Count |
|---|---|---|
| stale | 000 | 0 |

Closing text.
"""


def cl_frag(section="T", summary="Résumé."):
    return f"| {section} | {summary} | LOT-9 #9 | `F.swift:1` |\n"


def gap_frag(n, section="Reader", gap="UX change", h1="b"):
    return f"Section: {section}\n{gap_row(n, gap, h1)}\n"


class FoldTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.layout = fold.Layout(self.tmp)
        (self.tmp / "docs" / "migration").mkdir(parents=True)
        self.layout.changelog.write_text(CHANGELOG, encoding="utf-8")
        self.layout.gap.write_text(gap_text(), encoding="utf-8")
        self.layout.changelog_dir.mkdir()
        self.layout.gap_dir.mkdir()
        (self.layout.gap_dir / "README.md").write_text("# format\n", encoding="utf-8")
        fold.fold(self.layout)  # first fold generates the tallies of the hand-written file
        self.base_cl, self.base_gap = self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8")

    def put(self, directory, name, text):
        (directory / name).write_text(text, encoding="utf-8")

    def run_main(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = fold.main(list(argv), self.layout)
        return code, out.getvalue()

    def test_first_fold_generates_tallies_and_check_passes(self):
        self.assertIn("| UX change | 2 |", self.base_gap)
        self.assertIn("| **Total** | **4** |", self.base_gap)
        self.assertIn("(3)", self.base_gap)
        self.assertIn("| a | 050 | 1 |", self.base_gap)
        self.assertIn("| b·needed | 229 | 1 |", self.base_gap)
        self.assertEqual(self.run_main("--check")[0], 0)

    def test_two_fragments_are_folded_in_order_and_tallies_follow(self):
        self.put(self.layout.changelog_dir, "612.md", cl_frag("UX"))
        self.put(self.layout.changelog_dir, "590.md", cl_frag("T"))
        self.put(self.layout.gap_dir, "GAP-612.md", gap_frag("612", "Reader", "UX change", "b·operator"))
        self.put(self.layout.gap_dir, "GAP-590.md", gap_frag("590", "Navigation", "new", "a"))
        self.assertEqual(self.run_main("--check")[0], 0, "pending fragments do not break the tally check")
        code, out = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("folded 4 fragment(s)", out)
        cl = self.layout.changelog.read_text(encoding="utf-8").split("\n")
        rows = [c for c in cl if c.startswith("| ") and c[2].isdigit()]
        self.assertEqual([r.split(" | ")[0] for r in rows], ["| 1", "| 2", "| 590", "| 612"])
        self.assertIn("| 612 | UX | Résumé. | LOT-9 #9 | `F.swift:1` |", cl)
        gap = self.layout.gap.read_text(encoding="utf-8").split("\n")
        ids = [l.split(" | ")[0] for l in gap if l.startswith("| GAP-")]
        self.assertEqual(ids, ["| GAP-001", "| GAP-002", "| GAP-590", "| GAP-050", "| GAP-229", "| GAP-612"])
        self.assertIn("| **Total** | **6** |", gap)
        self.assertIn("| a | 050, 590 | 2 |", gap)
        self.assertIn("| b·operator | 612 | 1 |", gap)
        self.assertEqual(list(self.layout.changelog_dir.glob("[0-9]*.md")), [])
        self.assertEqual([p.name for p in self.layout.gap_dir.iterdir()], ["README.md"])
        self.assertEqual(self.run_main("--check")[0], 0)

    def test_fold_is_idempotent_and_order_independent(self):
        self.put(self.layout.gap_dir, "GAP-612.md", gap_frag("612"))
        self.put(self.layout.gap_dir, "GAP-590.md", gap_frag("590"))
        fold.fold(self.layout)
        once = self.layout.gap.read_text(encoding="utf-8"), self.layout.changelog.read_text(encoding="utf-8")
        code, out = self.run_main()
        self.assertIn("folded 0 fragment(s)", out)
        self.assertEqual((self.layout.gap.read_text(encoding="utf-8"), self.layout.changelog.read_text(encoding="utf-8")), once)
        # the same fragments arriving one at a time give the same file
        self.layout.gap.write_text(self.base_gap, encoding="utf-8")
        for n in ("590", "612"):
            self.put(self.layout.gap_dir, f"GAP-{n}.md", gap_frag(n))
            fold.fold(self.layout)
        self.assertEqual(self.layout.gap.read_text(encoding="utf-8"), once[0])

    def test_duplicate_id_between_fragment_and_row_fails_check_and_fold(self):
        self.put(self.layout.gap_dir, "GAP-229.md", gap_frag("229"))
        self.put(self.layout.changelog_dir, "2.md", cl_frag())
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("GAP-229.md: GAP-229 is already a row", out)
        self.assertIn("2.md: #2 is already a row", out)
        before = self.layout.gap.read_text(encoding="utf-8")
        code, out = self.run_main()
        self.assertEqual(code, 1)
        self.assertEqual(self.layout.gap.read_text(encoding="utf-8"), before, "nothing written on error")
        self.assertTrue((self.layout.gap_dir / "GAP-229.md").exists())

    def test_duplicate_id_inside_a_shared_file_fails_check(self):
        text = self.layout.gap.read_text(encoding="utf-8")
        self.layout.gap.write_text(text.replace(gap_row("002", "UX change", "b"), gap_row("001")), encoding="utf-8")
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("GAP-001 appears more than once", out)

    def test_row_id_must_match_file_name(self):
        self.put(self.layout.gap_dir, "GAP-700.md", gap_frag("701"))
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("the row is GAP-701, the file name says GAP-700", out)

    def test_malformed_fragments_fail_check(self):
        bad = {
            "GAP-1.md": ("gap_dir", "no section line\n" + gap_row("1") + "\n", "two lines"),
            "GAP-2.md": ("gap_dir", gap_frag("2", "Nowhere"), 'no GAP section "Nowhere"'),
            "GAP-3.md": ("gap_dir", gap_frag("3", gap="maybe"), 'Gap column "maybe"'),
            "GAP-4.md": ("gap_dir", gap_frag("4", h1="z"), 'H.1 column "z"'),
            "GAP-5.md": ("gap_dir", "Section: Reader\n| GAP-5 | too | few |\n", "9 cells"),
            "notes.md": ("gap_dir", gap_frag("6"), "is named GAP-<issue>.md"),
            "10.md": ("changelog_dir", "| T | only | three |\n", "4 non-empty cells"),
            "11.md": ("changelog_dir", cl_frag("XX"), "4 non-empty cells"),
            "12.md": ("changelog_dir", cl_frag() + cl_frag(), "one table row"),
            "x.md": ("changelog_dir", cl_frag(), "is named <issue>.md"),
        }
        for name, (where, text, _) in bad.items():
            self.put(getattr(self.layout, where), name, text)
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        for name, (_, _, msg) in bad.items():
            self.assertIn(msg, out, name)
        self.assertEqual(self.run_main()[0], 1, "fold refuses a malformed fragment")

    def test_stale_tallies_fail_check(self):
        self.layout.gap.write_text(self.base_gap.replace("| **Total** | **4** |", "| **Total** | **3** |"), encoding="utf-8")
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("not the generated one", out)

    def test_unsorted_changelog_fails_check(self):
        self.layout.changelog.write_text(self.base_cl.replace("| 1 | T |", "| 3 | T |"), encoding="utf-8")
        code, out = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("not in number order", out)

    def test_pipe_in_a_code_span_must_be_escaped(self):
        self.put(self.layout.changelog_dir, "9.md", "| T | a `x\\|y` b | LOT-9 | p |\n")
        self.assertEqual(self.run_main("--check")[0], 0)
        fold.fold(self.layout)
        self.assertIn("`x\\|y`", self.layout.changelog.read_text(encoding="utf-8"))


class RepositoryFilesTest(unittest.TestCase):
    def test_committed_files_pass_the_check(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = fold.main(["--check"], fold.Layout(REPO))
        self.assertEqual(code, 0, out.getvalue())

    def test_a_fragment_folds_into_a_copy_of_the_real_files(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        for rel in ("docs/CHANGELOG-LEGACY.md", "docs/migration/GAP-LEGACY-VS-SWIFT.md"):
            (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, tmp / rel)
        layout = fold.Layout(tmp)
        layout.changelog_dir.mkdir()
        layout.gap_dir.mkdir()
        (layout.changelog_dir / "9999.md").write_text(cl_frag(), encoding="utf-8")
        (layout.gap_dir / "GAP-9999.md").write_text(gap_frag("9999", "Reader"), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(fold.main([], layout), 0)
            self.assertEqual(fold.main(["--check"], layout), 0)
        self.assertIn("| GAP-9999 |", layout.gap.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
