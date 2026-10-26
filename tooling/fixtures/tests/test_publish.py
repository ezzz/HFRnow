"""Tests for publish.py (finding 6: the raw -> corpus step lives in the repo). Synthetic captures only."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402
import publish as P  # noqa: E402

OPERATOR = "Zorglub"
TOPIC = ('<td class="messCase1"><div><b class="s2">Alpha Membre</b></div></td>'
         '<div id="para1"><p>Bonjour Bravo</p></div>')
LIST = '<td class="sujetCase6 cBackCouleurTab2 ">Bravo</td>'
MP = ('<td class="messCase1"><div><b class="s2">Delta</b></div></td>'
      '<td class="messCase1"><div><b class="s2">Charlie</b></div></td>'
      '<div id="para9"><p>private words</p></div>')


class PublishTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.raw, self.dest = os.path.join(tmp.name, "raw"), os.path.join(tmp.name, "corpus")
        os.makedirs(self.raw)
        self.cfg = os.path.join(tmp.name, "local.json")
        with open(self.cfg, "w") as fh:
            json.dump({"pseudos": [OPERATOR]}, fh)
        self.manifest = os.path.join(tmp.name, "corpus.json")
        caps = [{"raw": "T1a", "id": "T1", "slug": "topic", "ext": "html", "private": False},
                {"raw": "L1", "id": "L1", "slug": "list", "ext": "html", "private": False},
                {"raw": "M1", "id": "M1", "slug": "mp", "ext": "html", "private": True},
                {"raw": "W1", "id": "W1", "slug": "redirect", "ext": None, "private": False}]
        with open(self.manifest, "w") as fh:
            json.dump({"captures": caps}, fh)
        self.capture("T1a", TOPIC, {"url": "https://forum.hardware.fr/forum2.php?post=1",
                                    "final_url": "https://forum.hardware.fr/hfr/Discussions/alpha-membre-sujet_1_1.htm",
                                    "status": 200, "set_cookie_names": ["md_user"], "headers_only": "dropped"})
        self.capture("L1", LIST, {"url": "/forum1.php"})
        self.capture("M1", MP, {"url": "/forum2.php?cat=prive&dest=Charlie", "note": "MP with Charlie"})
        self.capture("W1", None, {"method": "POST", "url": "/bddpost.php", "status": 302})
        with open(os.path.join(self.raw, "W1.request.txt"), "w") as fh:
            fh.write("POST /bddpost.php\nContent-Type: x\n\npseudo=%s&dest=Charlie&hash_check=REDACTED\n\n"
                     "pseudo=\"%s\"\n" % (OPERATOR, OPERATOR))

    def capture(self, rid, page, meta):
        if page is not None:
            with open(os.path.join(self.raw, rid + ".html"), "w", encoding="utf-8") as fh:
                fh.write(page)
        with open(os.path.join(self.raw, rid + ".meta.json"), "w", encoding="utf-8") as fh:
            json.dump(dict(meta, id=rid), fh)

    def run_publish(self, *ids):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            rc = P.main(["--config", self.cfg, "--raw", self.raw, "--dest", self.dest, "--manifest", self.manifest]
                        + list(ids))
        return rc, out.getvalue()

    def read(self, name):
        with open(os.path.join(self.dest, name), encoding="utf-8") as fh:
            return fh.read()

    def test_publish_writes_pages_and_metas(self):
        rc, out = self.run_publish()
        self.assertEqual(rc, 0, out)
        self.assertEqual(sorted(os.listdir(self.dest)), [
            "L1-list.html", "L1.meta.json", "M1-mp.html", "M1.meta.json", "T1-topic.html", "T1.meta.json",
            "W1.meta.json"])
        for secret in ("Alpha", "Bravo", "Charlie", OPERATOR, "private words"):
            self.assertNotIn(secret, out)
        topic, meta = self.read("T1-topic.html"), json.loads(self.read("T1.meta.json"))
        self.assertIn('<b class="s2">user2</b>', topic)
        # Bravo is a member in L1 only: still replaced in T1's free text (corpus-wide names).
        self.assertIn("Bonjour user3", topic)
        self.assertEqual(meta["id"], "T1")
        self.assertEqual(meta["file"], "T1-topic.html")
        self.assertFalse(meta["private"])
        self.assertNotIn("headers_only", meta)
        self.assertTrue(meta["final_url"].endswith("/hfr/Discussions/user2-sujet_1_1.htm"))  # same alias as page
        mp, mp_meta = self.read("M1-mp.html"), json.loads(self.read("M1.meta.json"))
        self.assertIn(A.PRIVATE_PLACEHOLDER, mp)
        self.assertTrue(mp_meta["private"])
        self.assertIn('<b class="s2">user3</b>', mp)  # Charlie is the second member of M1
        self.assertEqual(mp_meta["url"], "/forum2.php?cat=prive&dest=user3")  # same alias in the meta
        self.assertEqual(mp_meta["note"], "MP with user3")
        w1 = json.loads(self.read("W1.meta.json"))
        self.assertNotIn("file", w1)
        self.assertEqual(w1["request_body"], "pseudo=user1&dest=user2&hash_check=REDACTED")
        self.assertEqual(A.main(["check", "--quiet", "--corpus", self.dest]), 0)

    def test_publish_subset_and_unknown_id(self):
        rc, _out = self.run_publish("L1")
        self.assertEqual(rc, 0)
        self.assertEqual(sorted(os.listdir(self.dest)), ["L1-list.html", "L1.meta.json"])
        rc, _out = self.run_publish("NOPE")
        self.assertEqual(rc, 2)

    def test_publish_refuses_a_capture_that_still_leaks(self):
        # A member position the anonymizer does not know: the verifier blocks the write.
        saved = A.DISCOVER
        A.DISCOVER = tuple(d for d in saved if d[0] != "list author")
        try:
            rc, out = self.run_publish("L1")
        finally:
            A.DISCOVER = saved
        self.assertEqual(rc, 1)
        self.assertIn("structural check", out)
        self.assertNotIn("Bravo", out)
        self.assertFalse(os.path.exists(os.path.join(self.dest, "L1-list.html")))


if __name__ == "__main__":
    unittest.main()
