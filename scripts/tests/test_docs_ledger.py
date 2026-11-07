"""Tests for tooling/docs/ledger.py: the PR-body ledger and its steward (#620). Synthetic files in a temporary directory."""
import contextlib
import io
import json
import os
import shutil
import subprocess
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
REAL = json.loads((Path(__file__).resolve().parent / "ledger_real_bodies.json").read_text(encoding="utf-8"))  # #590, #604, #607


def body(*blocks, issue="Closes #700"):
    return f"{issue}\nClaim: x/y\n\nProblem.\n\n### Ledger\n\n" + "\n\n".join(f"```{k}\n{t}\n```" for k, t in blocks) + "\n\n### Tests\n\nnone\n"


BODIES = [
    {"number": 701, "body": body(("changelog", CL), issue="Closes #700")},
    {"number": 702, "body": body(("gap-new", f"Section: Reader\n{NEW}"), issue="Refs #700")},
    {"number": 703, "body": body(("gap-edit", "GAP-001\nGap: UX change\nH.1: b\nSwiftHFR final: Nouveau \\| pipe"), issue="Closes #703")},
]


def issue_obj(pr, labels=("ledger",), merged=True):
    return {"number": pr["number"], "body": pr["body"], "labels": [{"name": n} for n in labels],
            "pull_request": {"merged_at": "2026-11-07T00:00:00Z" if merged else None}}


class ParseTest(unittest.TestCase):
    def test_each_kind_parses(self):
        for pr in BODIES:
            self.assertEqual(ledger.check_body(pr["body"], pr["number"]), 1)
        self.assertEqual(ledger.check_body(body(("ledger-note", "Edit by hand: line 277.")), 5), 1)

    def test_malformed_blocks_are_refused_with_the_block_named(self):
        bad = [
            ("no section at all", "no `### Ledger`"),
            ("### Ledger\n\nNone: nothing to write.\n", "no block"),
            ("### Ledger\n\n```other\nx\n```\n", "unknown kind"),
            ("### Ledger\n\n```changelog\n| Q | a | b | c |\n```\n", "changelog block 1"),
            ("### Ledger\n\n```changelog\n| T | a | b |\n```\n", "4 non-empty cells"),
            ("### Ledger\n\n```gap-new\n" + NEW + "\n```\n", "gap-new block 1"),
            ("### Ledger\n\n```gap-new\nSection: Reader\n" + base.gap_row("1", "bogus") + "\n```\n", "Gap column"),
            ("### Ledger\n\n```gap-edit\nGAP-001 status ported\n```\n", "alone on the first line"),
            ("### Ledger\n\n```gap-edit\nGAP-001\nColour: red\n```\n", "expected `<Column>: <text>`"),
            ("### Ledger\n\n```gap-edit\nGAP-001\nGap: new\nGap: same\n```\n", "twice"),
            ("### Ledger\n\n```gap-edit\nGAP-001\nGap: new\n```\n\n```gap-edit\nGAP-001\nH.1: a\n```\n", "two blocks"),
            ("### Ledger\n\n```changelog\n" + CL + "\n", "unclosed"),
        ]
        for text, why in bad:
            with self.subTest(text=text[:40]), self.assertRaisesRegex(ledger.LedgerError, why):
                ledger.check_body(text, 5)

    def test_a_new_id_is_the_issue_or_the_pr(self):
        text = body(("gap-new", f"Section: Reader\n{NEW}"), issue="Closes #700")
        self.assertEqual(ledger.check_body(text, 701), 1)  # issue
        self.assertEqual(ledger.check_body(text.replace("#700", "#12"), 700), 1)  # PR
        with self.assertRaisesRegex(ledger.LedgerError, "id of a new row"):
            ledger.check_body(text.replace("#700", "#12"), 701)

    def test_label_and_section_must_agree(self):
        text = BODIES[0]["body"]
        self.assertIn("ok", ledger.check_pr(text, ["ledger"], 701))
        self.assertEqual(ledger.check_pr("Closes #1\n", ["type: chore"]), "ledger: no entry")
        with self.assertRaisesRegex(ledger.LedgerError, "lacks the label"):
            ledger.check_pr(text, ["type: chore"], 701)
        with self.assertRaisesRegex(ledger.LedgerError, "no `### Ledger` section"):
            ledger.check_pr("Closes #1\n", ["ledger"])

    def test_crlf_bodies_parse(self):
        crlf = BODIES[0]["body"].replace("\n", "\r\n")
        self.assertEqual(ledger.check_body(crlf, 701), 1)
        self.assertEqual(ledger.check_pr(crlf, ["ledger"], 701), "ledger body: 1 block(s) ok")

    def test_issue_number_falls_back_to_the_pr(self):
        self.assertEqual(ledger.issue_number("Refs #12\n", 5), 12)
        self.assertEqual(ledger.issue_number("Direct-PR: typo", 5), 5)


class GuardTest(unittest.TestCase):
    def test_ledger_files_are_refused_from_a_feature_branch(self):
        changed = ["App/x.swift", "docs/CHANGELOG-LEGACY.md", "docs/migration/GAP-LEGACY-VS-SWIFT.md",
                   "docs/changelog-legacy.d/9.md", "docs/migration/gap.d/GAP-9.md"]
        self.assertEqual(ledger.guard(changed, "feat/x"), changed[1:])

    def test_readmes_pass_from_a_feature_branch(self):
        self.assertEqual(ledger.guard(["docs/changelog-legacy.d/README.md", "docs/migration/gap.d/README.md"], "feat/x"), [])

    def test_the_steward_branch_may_only_touch_ledger_paths(self):
        ok = ["docs/CHANGELOG-LEGACY.md", "docs/migration/gap.d/GAP-9.md", "docs/changelog-legacy.d/9.md"]
        self.assertEqual(ledger.guard(ok, "docs/ledger-2026-11-07"), [])
        self.assertEqual(ledger.guard(ok + ["App/x.swift", "tooling/docs/ledger.py"], "docs/ledger-evil"), ["App/x.swift", "tooling/docs/ledger.py"])

    def test_cli_guard_uses_git_diff_without_rename_detection(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)

        def run(*a):
            subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=tmp, check=True, capture_output=True)
        run("init", "-q", "-b", "main")
        (tmp / "docs").mkdir()
        (tmp / "docs" / "CHANGELOG-LEGACY.md").write_text("a\nb\nc\nd\n")
        run("add", ".")
        run("commit", "-qm", "base")
        run("switch", "-qc", "feat")
        run("mv", "docs/CHANGELOG-LEGACY.md", "docs/elsewhere.md")  # a rename away must still list the ledger path
        run("commit", "-qam", "rename")
        cwd = os.getcwd()
        os.chdir(tmp)
        self.addCleanup(os.chdir, cwd)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(ledger.main(["guard", "--base", "main", "--head-ref", "feat"]), 1)
            self.assertEqual(ledger.main(["guard", "--base", "main", "--head-ref", "docs/ledger-x"]), 1)  # docs/elsewhere.md is not a ledger path


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

    def files(self):
        return self.layout.changelog.read_text(encoding="utf-8"), self.layout.gap.read_text(encoding="utf-8")

    def run_main(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ledger.main(list(argv), self.layout)
        return code, out.getvalue()

    def test_a_batch_of_three_folds_and_passes_the_check(self):
        res = ledger.plan(BODIES, self.layout, write=True)
        self.assertEqual((res.folded, res.skipped), ([701, 702, 703], []))
        self.assertEqual(fold.check(self.layout)[0], [])
        cl, gap = self.files()
        self.assertIn("| 701 | T | Résumé. | LOT-9 | `F.swift:1` |", cl)  # the # is the PR number
        self.assertIn("| GAP-700 |", gap)
        self.assertIn("| Nouveau \\| pipe |", gap)
        self.assertEqual(fold.fragments(self.layout.gap_dir) + fold.fragments(self.layout.changelog_dir), [])

    def test_an_edit_changes_only_the_named_cells(self):
        pr = {"number": 710, "body": body(("gap-edit", "GAP-002\nSwiftHFR final: Autre\nLot / PR: LOT-5"), issue="Closes #710")}
        ledger.plan([pr], self.layout, write=True)
        row = next(l for l in self.files()[1].split("\n") if l.startswith("| GAP-002 |"))
        self.assertEqual(fold.cells(row), ["GAP-002", "F002", "L", "ref", "Autre", "LOT-5", "UX change", "port: x", "b"])

    def test_an_edit_that_breaks_the_row_skips_the_pr(self):
        pr = {"number": 711, "body": body(("gap-edit", "GAP-002\nGap: nonsense"), issue="Closes #711")}
        res = ledger.plan([pr], self.layout, write=True)
        self.assertEqual((res.folded, len(res.skipped)), ([], 1))
        self.assertIn("not valid", res.skipped[0][1])

    def test_dry_run_changes_nothing(self):
        before = self.files()
        res = ledger.plan(BODIES, self.layout)
        self.assertEqual(len(res.folded), 3)
        self.assertEqual(self.files(), before)
        self.assertEqual(fold.fragments(self.layout.gap_dir), [])

    def test_folding_twice_is_a_no_op(self):
        ledger.plan(BODIES, self.layout, write=True)
        once = self.files()
        again = ledger.plan(BODIES, self.layout, write=True)
        self.assertEqual(self.files(), once)
        self.assertTrue(any("already folded" in l for l in again.lines))
        self.assertEqual(again.skipped, [])

    def test_two_prs_on_one_issue_both_fold(self):
        a = {"number": 901, "body": body(("changelog", CL), issue="Refs #900")}
        b = {"number": 902, "body": body(("changelog", CL.replace("Résumé", "Suite")), issue="Refs #900")}
        res = ledger.plan([a, b], self.layout, write=True)
        self.assertEqual((res.folded, res.skipped), ([901, 902], []))
        cl = self.files()[0]
        self.assertIn("| 901 | T | Résumé.", cl)
        self.assertIn("| 902 | T | Suite.", cl)

    def test_a_bad_pr_is_skipped_and_the_others_still_fold(self):
        bad = {"number": 700, "body": body(("gap-edit", "GAP-999\nGap: new"), issue="Closes #700")}
        res = ledger.plan([bad] + BODIES, self.layout, write=True)
        self.assertEqual(res.folded, [701, 702, 703])
        self.assertEqual([n for n, _ in res.skipped], [700])
        self.assertIn("GAP-999 is not a row", res.skipped[0][1])
        self.assertNotIn("#700: #700", res.skipped[0][1])
        self.assertEqual(fold.check(self.layout)[0], [])

    def test_an_unknown_section_skips_only_its_pr(self):
        typo = {"number": 740, "body": body(("gap-new", f"Section: Readr\n{base.gap_row('740', 'new', 'a')}"), issue="Closes #740")}
        res = ledger.plan([typo] + BODIES[:1], self.layout, write=True)
        self.assertEqual((res.folded, [n for n, _ in res.skipped]), ([701], [740]))
        self.assertIn('no GAP section "Readr"', res.skipped[0][1])

    def test_a_failing_write_leaves_the_tree_untouched(self):
        before = self.files()
        with mock.patch.object(fold, "check", return_value=(["boom"], [])), self.assertRaises(ledger.LedgerError):
            ledger.plan(BODIES, self.layout, write=True)
        self.assertEqual(self.files(), before)
        self.assertEqual(fold.fragments(self.layout.changelog_dir) + fold.fragments(self.layout.gap_dir), [])

    def test_a_skipped_pr_writes_nothing_of_itself(self):
        half = {"number": 720, "body": body(("changelog", CL), ("gap-edit", "GAP-999\nGap: new"), issue="Closes #720")}
        res = ledger.plan([half], self.layout, write=True)
        self.assertEqual((res.folded, len(res.skipped)), ([], 1))
        self.assertEqual(fold.fragments(self.layout.changelog_dir), [])
        self.assertNotIn("| 720 |", self.files()[0])

    def test_a_clash_with_other_text_skips_the_pr(self):
        ledger.plan(BODIES[:2], self.layout, write=True)
        other = {"number": 701, "body": body(("changelog", CL.replace("Résumé", "Autre")), issue="Closes #700")}
        res = ledger.plan([other], self.layout, write=True)
        self.assertEqual([n for n, _ in res.skipped], [701])
        gap_clash = {"number": 711, "body": body(("gap-new", f"Section: Reader\n{NEW.replace('F700', 'Z')}"), issue="Closes #700")}
        self.assertEqual(len(ledger.plan([gap_clash], self.layout, write=True).skipped), 1)

    def test_ledger_notes_are_listed_never_folded(self):
        pr = {"number": 730, "body": body(("ledger-note", "H.1 decision 2, line ~277: replace the sentence."), ("changelog", CL), issue="Closes #730")}
        res = ledger.plan([pr], self.layout, write=True)
        self.assertEqual(res.folded, [730])
        self.assertEqual(res.notes, [(730, "H.1 decision 2, line ~277: replace the sentence.")])

    def test_pending_selects_merged_ledger_prs_not_done(self):
        issues = [issue_obj(BODIES[0]), issue_obj(BODIES[1], labels=("ledger", "ledger: done")),
                  issue_obj(BODIES[2], merged=False), {"number": 9, "body": "x", "labels": [{"name": "ledger"}]}]
        self.assertEqual([p["number"] for p in ledger.pending(issues)], [701])
        self.assertEqual([p["number"] for p in ledger.pending(issues, [702, 701])], [701, 702])  # --prs: whatever the label
        with self.assertRaises(ledger.LedgerError):
            ledger.pending(issues, [703])  # not merged
        with self.assertRaises(ledger.LedgerError):
            ledger.pending(issues, [999])

    def test_cli_fold_prs_dry_run_apply_and_exit_codes(self):
        path = self.tmp / "issues.json"
        bad = {"number": 700, "body": "### Ledger\n\nprose"}
        path.write_text(json.dumps([issue_obj(p) for p in BODIES + [bad]]), encoding="utf-8")
        code, out = self.run_main("fold", "--from-json", str(path))
        self.assertEqual((code, "folded 3, skipped 1" in out, "SKIPPED PR #700" in out), (0, True, True))
        self.assertNotIn("| GAP-700 |", self.files()[1])
        self.assertEqual(self.run_main("fold", "--from-json", str(path), "--strict")[0], 1)
        code, out = self.run_main("fold", "--apply", "--prs", "701,702", "--from-json", str(path))
        self.assertEqual(code, 0, out)
        self.assertIn("| GAP-700 |", self.files()[1])
        self.assertNotIn("Nouveau", self.files()[1])  # 703 was not asked for
        only_bad = self.run_main("fold", "--prs", "700", "--from-json", str(path))
        self.assertEqual(only_bad[0], 1)  # nothing folded although a PR was pending

    def test_commit_needs_apply_and_a_clean_origin_tree(self):
        self.assertEqual(self.run_main("fold", "--commit")[0], 1)
        with mock.patch.object(ledger, "git", side_effect=lambda *a, **k: " M x" if a[0] == "status" else "abc"):
            with self.assertRaisesRegex(ledger.LedgerError, "not clean"):
                ledger.precheck_commit()
        with mock.patch.object(ledger, "git", side_effect=lambda *a, **k: "" if a[0] == "status" else str(a)):
            with self.assertRaisesRegex(ledger.LedgerError, "not origin/dev-swift"):
                ledger.precheck_commit()

    def test_done_is_idempotent_and_continues_after_an_error(self):
        def issue(n, labels, merged=True):
            return json.dumps({"number": n, "labels": [{"name": x} for x in labels], "pull_request": {"merged_at": "x" if merged else None}})
        calls = []

        def fake(*args):
            calls.append(args)
            if args[0].endswith("/issues/1"):
                return issue(1, ["ledger: done"])  # already done
            if args[0].endswith("/issues/2"):
                return issue(2, [], merged=False)
            if args[0].endswith("/issues/3"):
                return issue(3, ["ledger"])
            if args[-1].endswith("/labels/ledger"):
                raise ledger.LedgerError("gh api: HTTP 404")  # removed by someone else
            return ""
        with mock.patch.object(ledger, "gh", side_effect=fake):
            code, out = self.run_main("done", "1", "2", "3")
            self.assertEqual((code, "#1: already done" in out, "#3: would relabel" in out), (1, True, True))
            self.assertFalse([c for c in calls if c[0] == "-X"])  # a dry run writes nothing
            code, out = self.run_main("done", "3", "--apply")
        self.assertEqual((code, "relabelled" in out), (0, True))


class RealBodiesTest(unittest.TestCase):
    """The ledger sections of #590, #604 and #607 as merged, folded into copies of the real files."""

    def test_real_bodies_fold_or_are_reported(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        for rel in ("docs/CHANGELOG-LEGACY.md", "docs/migration/GAP-LEGACY-VS-SWIFT.md"):
            (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / rel, tmp / rel)
        layout = fold.Layout(tmp)
        prs = ledger.pending(REAL, [590, 604, 607])
        res = ledger.plan(prs, layout, write=True)
        self.assertEqual(res.folded, [604, 607])  # #590 writes prose where cells go: reported, never fatal
        self.assertEqual([n for n, _ in res.skipped], [590])
        self.assertIn("gap-edit block 2", res.skipped[0][1])
        self.assertEqual(fold.check(layout)[0], [])
        gap = layout.gap.read_text(encoding="utf-8")
        self.assertIn("| GAP-596 |", gap)
        self.assertIn("Catalogue, favourites (synced) and insert", gap)  # #604's edit of GAP-087


if __name__ == "__main__":
    unittest.main()
