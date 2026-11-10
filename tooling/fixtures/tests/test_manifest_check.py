"""Tests for manifest_check.py (#773): corpus.json ids and MANIFEST.md capture ids must agree. Synthetic data only."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import manifest_check as M  # noqa: E402

MANIFEST = """# Capture corpus

| Store | Files |
|---|---|
| Store | `a.plist` |

## Captures

| Id | File | Covers | Row | Lots |
|---|---|---|---|---|
| R01 | `R01-home.html` | Home | R01 | 021 |
| R05a | `R05a-list.html` | List | R05 | 022 |
| R08-1 | `R08-1-x.html` | Own topics | R08 | 022 |
| T11, T11h | meta only | Image host | — | 056 |
| T20, T21, T24 | meta only | Redirects | E26 | 056 |
| `R99` | `R99-y.html` | Backticked id | R99 | 001 |
| (oracles) | `../M2/` | Pointer to the legacy oracles, not a capture | — | 002 |
| (oracles) | `../M3/` | A second pointer | — | 003 |

Prose after the table mentions T99 and R98 and must not count.

## Not captured

| Rows | Why |
|---|---|
| R33, poll voted by the account itself | Not reachable |
"""
IDS = ["R01", "R05a", "R08-1", "T11", "T11h", "T20", "T21", "T24", "R99"]


class ManifestIdsTests(unittest.TestCase):
    def test_grouped_rows_count_and_headers_are_ignored(self):
        self.assertEqual(M.manifest_ids(MANIFEST), IDS)

    def test_other_tables_and_prose_are_ignored(self):
        ids = M.manifest_ids(MANIFEST)
        for ignored in ("Store", "Id", "Rows", "T99", "R98", "R33", "(oracles)"):
            self.assertNotIn(ignored, ids)

    def test_no_capture_table_is_an_error(self):
        with self.assertRaises(ValueError):
            M.manifest_ids("# Nothing\n\n| Store | Files |\n|---|---|\n| X | y |\n")

    def test_capture_table_ends_at_first_non_table_line(self):
        text = "| Id | File |\n|---|---|\n| A1 | x |\n\n| B1 | y |\n"
        self.assertEqual(M.manifest_ids(text), ["A1"])


class CheckTests(unittest.TestCase):
    def test_consistent(self):
        self.assertEqual(M.problems(IDS, M.manifest_ids(MANIFEST)), [])

    def test_corpus_id_without_manifest_row(self):
        out = M.problems(IDS + ["R77"], M.manifest_ids(MANIFEST))
        self.assertEqual(len(out), 1)
        self.assertIn("R77", out[0])
        self.assertIn("MANIFEST", out[0])

    def test_manifest_id_missing_from_corpus(self):
        out = M.problems([i for i in IDS if i != "T21"], M.manifest_ids(MANIFEST))
        self.assertEqual(len(out), 1)
        self.assertIn("T21", out[0])
        self.assertIn("corpus", out[0])

    def test_duplicate_manifest_id(self):
        out = M.problems(IDS, M.manifest_ids(MANIFEST) + ["R01"])
        self.assertEqual(len(out), 1)
        self.assertIn("R01", out[0])
        self.assertIn("twice", out[0])

    def test_duplicate_corpus_id(self):
        out = M.problems(IDS + ["R01"], M.manifest_ids(MANIFEST))
        self.assertEqual(len(out), 1)
        self.assertIn("R01", out[0])

    def test_problems_are_sorted_for_stable_output(self):
        out = M.problems(["B", "A"], ["C"])
        self.assertEqual([o.split()[0] for o in out], sorted(o.split()[0] for o in out))


class MainTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.manifest = os.path.join(tmp.name, "MANIFEST.md")
        self.corpus = os.path.join(tmp.name, "corpus.json")
        with open(self.manifest, "w") as fh:
            fh.write(MANIFEST)

    def write_corpus(self, ids):
        caps = [{"raw": i, "id": i, "slug": "s", "ext": "html", "private": False} for i in ids]
        with open(self.corpus, "w") as fh:
            json.dump({"captures": caps}, fh)

    def run_main(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = M.main(["--corpus", self.corpus, "--manifest", self.manifest])
        return code, out.getvalue() + err.getvalue()

    def test_ok(self):
        self.write_corpus(IDS)
        code, _ = self.run_main()
        self.assertEqual(code, 0)

    def test_failure_names_the_ids(self):
        self.write_corpus(IDS + ["R77"])
        code, text = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("R77", text)

    def test_manifest_without_capture_table_is_a_fail_line_not_a_traceback(self):
        self.write_corpus(IDS)
        with open(self.manifest, "w") as fh:
            fh.write("# Nothing here\n")
        code, text = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("FAIL", text)

    def test_unreadable_corpus_is_a_fail_line(self):
        code, text = self.run_main()  # corpus file never written
        self.assertEqual(code, 1)
        self.assertIn("FAIL", text)

    def test_default_corpus_follows_the_publish_layout(self):
        import publish
        self.assertEqual(M.DEFAULT_CORPUS, publish.DEFAULT_MANIFEST)

    def test_committed_corpus_and_manifest_agree(self):
        """The real files. This is how CI runs the check: the `fixture-tooling` job's unittest step (a separate workflow step would edit ci.yml and start the macOS jobs)."""
        self.assertEqual(M.main([]), 0)


if __name__ == "__main__":
    unittest.main()
