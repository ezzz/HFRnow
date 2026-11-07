"""Tests for tooling/docs/ledger.py: the PR-body ledger and its steward (#620). Synthetic files in a temporary directory."""
import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "docs"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import fold  # noqa: E402
import ledger  # noqa: E402
import test_docs_fold as base  # noqa: E402  (the synthetic CHANGELOG and GAP files)

CL = "| T | Résumé. | LOT-9 | `F.swift:1` |"
NEW = base.gap_row("700", "UX change", "b")
EDIT = base.gap_row("001", "UX change", "b")  # GAP-001 is `same`/`a` in the synthetic file


def body(*blocks, issue="Closes #700"):
    return f"{issue}\nClaim: x/y\n\nProblem.\n\n### Ledger\n\n" + "\n\n".join(f"```{k}\n{t}\n```" for k, t in blocks) + "\n\n### Tests\n\nnone\n"


BODIES = [
    {"number": 701, "body": body(("changelog", CL), issue="Closes #700")},
    {"number": 702, "body": body(("gap-new", f"Section: Reader\n{NEW}"), issue="Refs #700")},
    {"number": 703, "body": body(("gap-edit", f"GAP-001\n{EDIT}"), issue="Closes #703")},
]


def issue_obj(pr, labels=("ledger",), merged=True):
    return {"number": pr["number"], "body": pr["body"], "labels": [{"name": n} for n in labels],
            "pull_request": {"merged_at": "2026-11-07T00:00:00Z" if merged else None}}


class ParseTest(unittest.TestCase):
    def test_each_kind_parses(self):
        for pr in BODIES:
            self.assertEqual(ledger.check_body(pr["body"]), 1)

    def test_section_ends_at_next_heading(self):
        self.assertEqual(len(ledger.parse_body(BODIES[0]["body"])), 1)

    def test_malformed_blocks_are_refused(self):
        bad = [
            "no section at all",
            "### Ledger\n\nprose only\n",
            "### Ledger\n\n```other\nx\n```\n",
            "### Ledger\n\n```changelog\n| Q | a | b | c |\n```\n",
            "### Ledger\n\n```changelog\n| T | a | b |\n```\n",
            "### Ledger\n\n```gap-new\n" + NEW + "\n```\n",
            "### Ledger\n\n```gap-new\nSection: Reader\n" + base.gap_row("1", "bogus") + "\n```\n",
            "### Ledger\n\n```gap-edit\nGAP-002\n" + EDIT + "\n```\n",
            "### Ledger\n\n```changelog\n" + CL + "\n",
        ]
        for text in bad:
            with self.subTest(text=text[:40]), self.assertRaises(ledger.LedgerError):
                ledger.check_body(text)

    def test_issue_number_falls_back_to_the_pr(self):
        self.assertEqual(ledger.issue_number("Refs #12\n", 5), 12)
        self.assertEqual(ledger.issue_number("Direct-PR: typo", 5), 5)


class GuardTest(unittest.TestCase):
    def test_ledger_files_are_refused_from_a_feature_branch(self):
        changed = ["App/x.swift", "docs/CHANGELOG-LEGACY.md", "docs/migration/GAP-LEGACY-VS-SWIFT.md",
                   "docs/changelog-legacy.d/9.md", "docs/migration/gap.d/GAP-9.md"]
        self.assertEqual(ledger.guard(changed, "feat/x"), changed[1:])

    def test_readmes_and_the_steward_branch_pass(self):
        self.assertEqual(ledger.guard(["docs/changelog-legacy.d/README.md", "docs/migration/gap.d/README.md"], "feat/x"), [])
        self.assertEqual(ledger.guard(["docs/CHANGELOG-LEGACY.md"], "docs/ledger-2026-11-07"), [])

    def test_cli_guard_uses_git_diff(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        run = lambda *a: __import__("subprocess").run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=tmp, check=True, capture_output=True)  # noqa: E731
        run("init", "-q", "-b", "main")
        (tmp / "docs").mkdir()
        (tmp / "docs" / "CHANGELOG-LEGACY.md").write_text("a")
        run("add", ".")
        run("commit", "-qm", "base")
        run("switch", "-qc", "feat")
        (tmp / "docs" / "CHANGELOG-LEGACY.md").write_text("b")
        run("commit", "-qam", "edit")
        cwd = os.getcwd()
        os.chdir(tmp)
        self.addCleanup(os.chdir, cwd)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.main(["guard", "--base", "main", "--head-ref", "feat"]), 1)
            self.assertEqual(ledger.main(["guard", "--base", "main", "--head-ref", "docs/ledger-x"]), 0)


class StewardTest(unittest.TestCase):
    def setUp(self):
        env = mock.patch.dict(os.environ)
        env.start()
        self.addCleanup(env.stop)
        os.environ.pop("GITHUB_ACTIONS", None)
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.layout = fold.Layout(self.tmp)
        (self.tmp / "docs" / "migration").mkdir(parents=True)
        self.layout.changelog.write_text(base.CHANGELOG, encoding="utf-8")
        self.layout.gap.write_text(base.gap_text(), encoding="utf-8")
        self.layout.changelog_dir.mkdir()
        self.layout.gap_dir.mkdir()
        fold.fold(self.layout)  # generated tallies, as on dev-swift

    def run_main(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ledger.main(list(argv), self.layout)
        return code, out.getvalue()

    def test_a_batch_of_three_folds_and_passes_the_check(self):
        lines = ledger.plan(BODIES, self.layout, write=True)
        self.assertEqual(len(lines), 3)
        self.assertEqual(fold.check(self.layout)[0], [])
        cl, gap = self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8")
        self.assertIn("| 700 | T | Résumé. | LOT-9 | `F.swift:1` |", cl)
        self.assertIn("| GAP-700 |", gap)
        self.assertIn(EDIT, gap)  # GAP-001 changed in place
        self.assertEqual(fold.fragments(self.layout.gap_dir) + fold.fragments(self.layout.changelog_dir), [])
        self.assertIn("| UX change | 4 |", gap)  # the tallies follow both the new row and the edit

    def test_dry_run_changes_nothing(self):
        before = (self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8"))
        lines = ledger.plan(BODIES, self.layout)
        self.assertEqual(len(lines), 3)
        self.assertEqual((self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8")), before)
        self.assertEqual(fold.fragments(self.layout.gap_dir), [])

    def test_folding_twice_is_a_no_op(self):
        ledger.plan(BODIES, self.layout, write=True)
        once = (self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8"))
        again = ledger.plan(BODIES, self.layout, write=True)
        self.assertEqual((self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8")), once)
        self.assertTrue(any("already folded" in l for l in again))

    def test_a_clash_with_other_text_is_an_error(self):
        ledger.plan(BODIES[:2], self.layout, write=True)
        other = {"number": 710, "body": body(("changelog", CL.replace("Résumé", "Autre")), issue="Closes #700")}
        with self.assertRaises(ledger.LedgerError):
            ledger.plan([other], self.layout, write=True)
        gap_clash = {"number": 711, "body": body(("gap-new", f"Section: Reader\n{NEW.replace('F700', 'Z')}"), issue="Closes #1")}
        with self.assertRaises(ledger.LedgerError):
            ledger.plan([gap_clash], self.layout, write=True)

    def test_edit_of_a_missing_row_and_a_malformed_body_name_the_pr(self):
        miss = {"number": 720, "body": body(("gap-edit", f"GAP-999\n{base.gap_row('999')}"))}
        with self.assertRaisesRegex(ledger.LedgerError, "#720"):
            ledger.plan([miss], self.layout, write=True)
        with self.assertRaisesRegex(ledger.LedgerError, "#721"):
            ledger.plan([{"number": 721, "body": "### Ledger\n\nprose"}], self.layout, write=True)

    def test_pending_selects_merged_ledger_prs_not_done(self):
        issues = [issue_obj(BODIES[0]), issue_obj(BODIES[1], labels=("ledger", "ledger: done")),
                  issue_obj(BODIES[2], merged=False), {"number": 9, "body": "x", "labels": [{"name": "ledger"}]}]
        self.assertEqual([p["number"] for p in ledger.pending(issues)], [701])

    def test_cli_fold_from_json_dry_run_then_apply(self):
        path = self.tmp / "issues.json"
        path.write_text(json.dumps([issue_obj(p) for p in BODIES]), encoding="utf-8")
        code, out = self.run_main("fold", "--from-json", str(path))
        self.assertEqual((code, "dry run for PRs 701 702 703" in out), (0, True))
        self.assertNotIn("| GAP-700 |", self.layout.gap.read_text(encoding="utf-8"))
        code, out = self.run_main("fold", "--apply", "--from-json", str(path))
        self.assertEqual(code, 0, out)
        self.assertIn("| GAP-700 |", self.layout.gap.read_text(encoding="utf-8"))

    def test_done_is_a_dry_run_without_apply(self):
        with mock.patch.object(ledger, "gh") as gh:
            code, out = self.run_main("done", "701")
        self.assertEqual((code, gh.called, "would relabel #701" in out), (0, False, True))
        with mock.patch.object(ledger, "gh") as gh:
            self.run_main("done", "701", "--apply")
        self.assertEqual(gh.call_count, 2)


if __name__ == "__main__":
    unittest.main()
