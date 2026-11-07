"""AQ shapes of an operator-owned topic: one test per position of `verify_aq_own` (synthetic values only).

Each position is checked on its own: the clean fixture passes, and the same fixture with that one position left
real (or any non-alias) is reported, through `Anonymizer.findings` too (what `check` runs)."""
import json
import os
import sys
import unittest
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402

POST_URL = ("https://forum.hardware.fr/hfr/own-category/own-subcategory/own-topic-subject-sujet_9900001_1.htm"
            "#t9910000001")
BODY = {"alerte_qualitay_id": "-1", "nom": A.OWN_ALERT_TITLE, "topic_id": "9900001", "topic_titre": A.OWN_SUBJECT,
        "pseudo": "user1", "post_id": "9910000001", "post_url": POST_URL, "commentaire": "post de user1"}
XML = ('<?xml version="1.0" encoding="utf-8"?>\n<alertes><alerte id="9920001" nom="x x" pseudoInitiateur="user1" '
       'date="01-01-2000" postsIds="9910000001"/></alertes>')


def meta(body=None, url="https://aq.super-h.fr/api/addAlerte.php", date=A.OWN_HTTP_DATE):
    doc = {"id": "T", "method": "POST", "url": url, "final_url": url, "date": date}
    if body is not None:
        doc["request_body"] = urllib.parse.urlencode(body, quote_via=urllib.parse.quote)
    return json.dumps(doc, indent=2)


FULL = {"alert id": ["alert id not an alias"], "postsIds": ["postsIds not aliases"], "alert date": ["alert date not an alias"]}


class AQOwnTests(unittest.TestCase):
    def reasons(self, text, own_list=False):
        return [r for _l, _c, r in A.verify_aq_own(text, own_list=own_list)]

    def both(self, text):
        """The reasons of verify_aq_own, which `Anonymizer.findings` (what `check` runs) must report the same."""
        direct = self.reasons(text)
        via = [r for _l, _c, r in A.Anonymizer(A.Config()).findings(text) if "AQ own-topic" in r]
        self.assertEqual(sorted(via), sorted(direct))
        return direct

    def test_clean_shapes_pass(self):
        self.assertEqual(A.verify_aq_own(meta(BODY)), [])
        self.assertEqual(A.verify_aq_own(XML), [])
        self.assertEqual(A.verify_aq_own(meta(url="https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=9900001")), [])
        anon = A.Anonymizer(A.Config(pseudos=["Zorglub"]))
        for text in (meta(BODY), XML):
            self.assertFalse([f for f in anon.findings(text) if "AQ own-topic" in f[2]])

    def test_each_body_position(self):
        real = {"topic_id": ("654321", "topic_id not an alias"), "post_id": ("8765432", "post_id not an alias"),
                "topic_titre": ("Real title", "topic_titre not an alias"),
                "nom": ("Real alert title", "nom (alert title) not a placeholder"),
                "pseudo": ("realone", "pseudo not an alias"), "commentaire": ("post de realone", "commentaire not an alias"),
                "alerte_qualitay_id": ("12", "alerte_qualitay_id is not the create marker -1")}
        for key, (value, reason) in real.items():
            with self.subTest(key=key):
                self.assertEqual(self.both(meta(dict(BODY, **{key: value}))), ["AQ own-topic check: " + reason])
        reason = "AQ own-topic check: post_url (category, slug, topic or message id) not an alias"
        for url in (POST_URL.replace("own-category", "Catqq"), POST_URL.replace("own-subcategory", "Subqq"),
                    POST_URL.replace("own-topic-subject", "real-slug"), POST_URL.replace("sujet_9900001", "sujet_654321"),
                    POST_URL.replace("#t9910000001", "#t8765432")):
            with self.subTest(url=url):
                self.assertEqual(self.both(meta(dict(BODY, post_url=url))), [reason])

    def test_body_shape(self):
        pre = "AQ own-topic check: "
        self.assertEqual(self.both(meta(list(BODY.items()) + [("pseudo", "user1")])), [pre + "duplicate field in the body"])
        self.assertEqual(self.both(meta(dict(BODY, extra="1"))), [pre + "unknown field in the body (extra)"])
        short = {k: v for k, v in BODY.items() if k != "commentaire"}
        self.assertEqual(sorted(self.both(meta(short))), sorted([pre + "field missing from the body (commentaire)", pre + "commentaire not an alias"]))

    def test_http_date(self):
        self.assertIn("AQ own-topic check: HTTP date not an alias", self.both(meta(BODY, date="Mon, 03 Mar 2031 10:11:12 GMT")))
        self.assertTrue(self.both(meta(url="https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=9900001",
                                          date="Mon, 03 Mar 2031 10:11:12 GMT")))

    def test_other_hosts_and_other_topics_are_not_checked(self):
        self.assertEqual(A.verify_aq_own(meta(BODY, url="https://example.org/x")), [])
        self.assertEqual(A.verify_aq_own(meta(url="https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=8680",
                                              date="Mon, 03 Mar 2031 10:11:12 GMT")), [])

    def test_each_list_position(self):
        for old, new, reason in (('id="9920001"', 'id="13999"', "alert id"),
                                 ('postsIds="9910000001"', 'postsIds="8765432"', "postsIds"),
                                 ('postsIds="9910000001"', 'postsIds="9910000001,8765432"', "postsIds"),
                                 ('date="01-01-2000"', 'date="04-04-2031"', "alert date")):
            with self.subTest(reason=reason, new=new):
                self.assertEqual(self.reasons(XML.replace(old, new), own_list=True),
                                 ["AQ own-topic check: " + full for full in FULL[reason]])

    def test_own_list_fails_closed_on_anything_else(self):
        for text in (meta(BODY), "<html>not an AQ list</html>", '<?xml version="1.0"?><alertes><alerte id="1"'):
            with self.subTest(text=text[:20]):
                self.assertEqual(len(A.verify_aq_own(text, own_list=True)), 1)

    def test_own_list_is_strict_whatever_its_ids(self):
        """A list whose meta names a fake topic (`check --corpus`) must hold only aliases, even real-looking ids."""
        real = XML.replace('id="9920001"', 'id="13999"').replace('postsIds="9910000001"', 'postsIds="8765432"') \
                  .replace('date="01-01-2000"', 'date="04-04-2031"')
        self.assertEqual(A.verify_aq_own(real), [])  # alone, nothing says it is an own list
        self.assertEqual(len(A.verify_aq_own(real, own_list=True)), 3)
        self.assertEqual(A.verify_aq_own(XML, own_list=True), [])

    def test_corpus_check_applies_it_through_the_meta(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            url = "https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=9900001"
            with open(os.path.join(tmp, "T.meta.json"), "w") as fh:
                fh.write(meta(url=url).replace('"id": "T"', '"id": "T", "file": "T-list.xml"'))
            real = XML.replace('postsIds="9910000001"', 'postsIds="8765432"')
            with open(os.path.join(tmp, "T-list.xml"), "w") as fh:
                fh.write(real)
            self.assertEqual(A._own_aq_list_files(tmp), {os.path.join(tmp, "T-list.xml")})
            self.assertEqual(A.main(["check", "--quiet", "--corpus", tmp]), 1)
            with open(os.path.join(tmp, "T-list.xml"), "w") as fh:
                fh.write(XML)
            self.assertEqual(A.main(["check", "--quiet", "--corpus", tmp]), 0)

if __name__ == "__main__":
    unittest.main()
