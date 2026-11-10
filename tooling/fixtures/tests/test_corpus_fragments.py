"""Tests for the corpus manifest layout (#773): one `corpus.d/<batch>.json` per capture batch. Synthetic data only."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import publish as P  # noqa: E402


def entry(raw, cid=None, ext="html"):
    return {"raw": raw, "id": cid or raw, "slug": "s-" + raw.lower(), "ext": ext, "private": False}


class LoadManifestTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = os.path.join(tmp.name, "corpus.d")
        os.makedirs(self.dir)

    def write(self, name, captures, **extra):
        with open(os.path.join(self.dir, name), "w") as fh:
            json.dump({"captures": captures, **extra}, fh)

    def test_fragments_are_read_in_file_name_order(self):
        self.write("20-second.json", [entry("B1")])
        self.write("10-first.json", [entry("A1"), entry("A2")])
        self.assertEqual([e["id"] for e in P.load_manifest(self.dir)], ["A1", "A2", "B1"])

    def test_other_files_are_ignored(self):
        self.write("a.json", [entry("A1")])
        with open(os.path.join(self.dir, "README.md"), "w") as fh:
            fh.write("not a fragment")
        self.assertEqual([e["id"] for e in P.load_manifest(self.dir)], ["A1"])

    def test_a_single_file_still_loads(self):
        self.write("a.json", [entry("A1")])
        self.assertEqual([e["id"] for e in P.load_manifest(os.path.join(self.dir, "a.json"))], ["A1"])

    def test_same_id_in_two_fragments_names_both_files(self):
        self.write("a.json", [entry("A1", "X1")])
        self.write("b.json", [entry("B1", "X1")])
        with self.assertRaises(ValueError) as ctx:
            P.load_manifest(self.dir)
        for part in ("X1", "a.json", "b.json"):
            self.assertIn(part, str(ctx.exception))

    def test_same_raw_in_two_fragments_is_refused(self):
        self.write("a.json", [entry("A1", "X1")])
        self.write("b.json", [entry("A1", "X2")])
        with self.assertRaises(ValueError) as ctx:
            P.load_manifest(self.dir)
        self.assertIn("A1", str(ctx.exception))

    def test_same_id_twice_in_one_fragment_is_refused(self):
        self.write("a.json", [entry("A1", "X1"), entry("A2", "X1")])
        with self.assertRaises(ValueError):
            P.load_manifest(self.dir)

    def test_fragment_without_captures_names_the_file(self):
        with open(os.path.join(self.dir, "bad.json"), "w") as fh:
            json.dump({"note": "x"}, fh)
        with self.assertRaises(ValueError) as ctx:
            P.load_manifest(self.dir)
        self.assertIn("bad.json", str(ctx.exception))

    def test_malformed_json_names_the_file(self):
        with open(os.path.join(self.dir, "bad.json"), "w") as fh:
            fh.write("{")
        with self.assertRaises(ValueError) as ctx:
            P.load_manifest(self.dir)
        self.assertIn("bad.json", str(ctx.exception))

    def test_entry_missing_a_key_names_the_file(self):
        self.write("a.json", [{"raw": "A1", "id": "A1"}])
        with self.assertRaises(ValueError) as ctx:
            P.load_manifest(self.dir)
        self.assertIn("a.json", str(ctx.exception))

    def test_captures_of_the_wrong_shape_name_the_file(self):
        for body in ('{"captures": null}', '{"captures": {"a": 1}}', '{"captures": ["R1"]}', '[1]'):
            with open(os.path.join(self.dir, "bad.json"), "w") as fh:
                fh.write(body)
            with self.assertRaises(ValueError, msg=body) as ctx:
                P.load_manifest(self.dir)
            self.assertIn("bad.json", str(ctx.exception))

    def test_non_utf8_fragment_names_the_file(self):
        with open(os.path.join(self.dir, "bad.json"), "wb") as fh:
            fh.write(b"\xff\xfe{")
        with self.assertRaises(ValueError) as ctx:
            P.load_manifest(self.dir)
        self.assertIn("bad.json", str(ctx.exception))

    def test_empty_directory_is_an_error(self):
        with self.assertRaises(ValueError):
            P.load_manifest(self.dir)

    def test_missing_path_is_an_error_not_an_empty_corpus(self):
        with self.assertRaises((ValueError, OSError)):
            P.load_manifest(os.path.join(self.dir, "nope"))


class CommittedLayoutTests(unittest.TestCase):
    def test_default_manifest_is_the_fragment_directory(self):
        self.assertTrue(os.path.isdir(P.DEFAULT_MANIFEST), P.DEFAULT_MANIFEST)
        self.assertTrue(P.DEFAULT_MANIFEST.rstrip(os.sep).endswith("corpus.d"))

    def test_committed_fragments_load_with_unique_ids(self):
        entries = P.load_manifest(P.DEFAULT_MANIFEST)
        self.assertGreater(len(entries), 300)
        self.assertEqual(len({e["id"] for e in entries}), len(entries))

    def test_the_single_file_manifest_is_gone(self):
        self.assertFalse(os.path.exists(os.path.join(os.path.dirname(P.DEFAULT_MANIFEST), "corpus.json")))


if __name__ == "__main__":
    unittest.main()
