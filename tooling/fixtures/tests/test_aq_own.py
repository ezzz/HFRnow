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


LOCAL_URL = "http://192.0.2.1:8574/api/addAlerte.php"
LOCAL_LIST_URL = "http://192.0.2.1:8574/api/getAlertesByTopic.php?topic_id=700001"
LOCAL_POST_URL = "https://forum.hardware.fr/hfr/Discussions/Societe/aq-local-topic-sujet_700001_1.htm#t700101"
LOCAL_BODY = {"alerte_qualitay_id": "-1", "nom": "AQ local test", "topic_id": "700001", "topic_titre": "AQ local topic",
              "pseudo": "user3", "post_id": "700101", "post_url": LOCAL_POST_URL, "commentaire": "post de user3"}
LOCAL_DATE = "Sat, 07 Nov 2026 13:02:15 GMT"
LOCAL_XML = ('<?xml version="1.0" encoding="utf-8"?>\n<alertes><alerte id="13636" nom="x x x" pseudoInitiateur="user3" '
             'date="07-11-2026" postsIds="700102,700101"/></alertes>\n')


def local_meta(body=None, get=False, **extra):
    url = LOCAL_LIST_URL if get else LOCAL_URL
    ctype = "text/xml;charset=UTF-8" if get else "text/plain;charset=UTF-8"
    doc = {"id": "T53", "account": "anon", "method": "GET" if get else "POST", "url_template": url[len("http://192.0.2.1:8574"):],
           "url": url, "final_url": url, "status": 200, "content_type": ctype, "date": LOCAL_DATE, "redirects": [],
           "set_cookie_names": [], "origin": "local-instance", "note": A.AQ_LOCAL_NOTE, "private": False, "file": "T53-a.txt",
           "response_headers": {"Host": "192.0.2.1:8574", "Date": LOCAL_DATE, "Connection": "close",
                                "X-Powered-By": "PHP/8.5.12", "Content-type": ctype, "Pragma": "no-cache"}}
    if not get:
        doc["request_fields"] = sorted(LOCAL_BODY)
        doc["request_body"] = urllib.parse.urlencode(body or LOCAL_BODY, quote_via=urllib.parse.quote)
    doc.update(extra)
    return doc


def meta_only(**extra):
    doc = local_meta(status=403, content_type="text/html; charset=UTF-8", body_length=0, **extra)
    del doc["file"]
    doc["response_headers"].update({"Content-type": "text/html; charset=UTF-8", "Content-Length": "0"})
    del doc["response_headers"]["Pragma"]
    return doc


class AQLocalTests(unittest.TestCase):
    """`origin: local-instance` files: planted values on the local host, one per position (#586 review, finding 3)."""

    def reasons(self, doc):
        """The reasons `check` gives for this meta, through `Anonymizer.findings`."""
        return [r for _l, _c, r in A.Anonymizer(A.Config()).findings(json.dumps(doc, indent=2)) if "AQ local" in r]

    def test_clean_metas_pass(self):
        self.assertEqual(self.reasons(local_meta()), [])
        self.assertEqual(self.reasons(local_meta(get=True)), [])
        self.assertEqual(self.reasons(meta_only()), [])

    def test_a_real_value_in_the_request_body_fails(self):
        real_url = "https://forum.hardware.fr/hfr/Hardware/hfr/real-topic-sujet_123456_1.htm#t7654321"
        for field, value, reason in (("topic_id", "123456", "topic_id not a local id"),
                                     ("post_id", "7654321", "post_id not a local id"),
                                     ("topic_titre", "A real topic title", "topic_titre not a local value"),
                                     ("nom", "A real alert title", "nom not a local value"),
                                     ("post_url", real_url, "post_url not a local value"),
                                     ("commentaire", "free text by a member", "commentaire not the legacy text"),
                                     ("alerte_qualitay_id", "12345", "alerte_qualitay_id not a local value"),
                                     ("pseudo", "Realname", "pseudo not an alias")):
            with self.subTest(field=field):
                reasons = self.reasons(local_meta(dict(LOCAL_BODY, **{field: value})))
                self.assertIn("AQ local check: " + reason, reasons)

    def test_the_body_holds_exactly_the_create_fields(self):
        body = dict(LOCAL_BODY, extra="value")
        self.assertIn("AQ local check: the body does not hold exactly the create fields", self.reasons(local_meta(body)))

    def test_origin_cannot_be_another_value_or_dropped(self):
        self.assertIn("AQ local check: origin is not local-instance", self.reasons(local_meta(origin="live")))
        doc = local_meta()
        del doc["origin"]
        self.assertIn("AQ local check: key missing (origin)", self.reasons(doc))

    def test_a_local_mark_on_another_host_fails(self):
        for url in ("https://aq.super-h.fr/api/addAlerte.php", "https://forum.hardware.fr/bddpost.php",
                    "http://192.0.2.1:8574/other.php"):
            with self.subTest(url=url):
                self.assertIn("AQ local check: url not on the local host, or another path", self.reasons(local_meta(url=url)))

    def test_every_other_position_is_closed(self):
        for doc, reason in ((local_meta(note="a real note"), "note not a local value"),
                            (local_meta(status=500), "status not a local value"),
                            (local_meta(set_cookie_names=["md_user"]), "set_cookie_names not a local value"),
                            (local_meta(account="user1"), "account not a local value"),
                            (local_meta(extra="value"), "unknown key (extra)"),
                            (local_meta(body_length=3), "unknown key (body_length)"),
                            (dict(meta_only(), file="x.txt"), "unknown key (body_length)")):
            with self.subTest(reason=reason):
                self.assertIn("AQ local check: " + reason, self.reasons(doc))

    def test_response_headers_are_closed(self):
        good = local_meta()["response_headers"]
        for change, reason in (({"Set-Cookie": "a=b"}, "unknown response header (Set-Cookie)"),
                               ({"Host": "aq.super-h.fr"}, "Host header not the local host"),
                               ({"Date": "Sun, 08 Nov 2026 13:02:15 GMT"}, "Date or Content-type header does not follow the meta"),
                               ({"X-Powered-By": "a real server"}, "Connection or X-Powered-By header not a local value"),
                               ({"Pragma": "free text"}, "Cache-Control or Pragma header not a local value")):
            with self.subTest(reason=reason):
                self.assertIn("AQ local check: " + reason, self.reasons(local_meta(response_headers=dict(good, **change))))
        without = {k: v for k, v in good.items() if k != "Host"}
        self.assertIn("AQ local check: response header missing (Host)", self.reasons(local_meta(response_headers=without)))

    def test_body_length_follows_content_length(self):
        doc = meta_only()
        doc["response_headers"]["Content-Length"] = "7"
        self.assertIn("AQ local check: Content-Length header does not follow body_length", self.reasons(doc))
        doc = meta_only()
        doc["body_length"] = "0"
        self.assertIn("AQ local check: body_length not a size", self.reasons(doc))

    def test_a_list_or_code_of_the_run_passes(self):
        self.assertEqual(A.verify_aq_local_answer(LOCAL_XML, local_meta(get=True)), [])
        for code in ("1", "-2", "-4"):
            self.assertEqual(A.verify_aq_local_answer(code, local_meta()), [])

    def test_a_planted_answer_fails(self):
        doc = local_meta(get=True)
        for old, new, reason in (('id="13636"', 'id="13642"', "alert id not a local value"),
                                 ('postsIds="700102,700101"', 'postsIds="7654321"', "postsIds not local ids"),
                                 ('date="07-11-2026"', 'date="04-04-2024"', "alert date is not the day of the run"),
                                 ('<alertes>', '<alertes>free text', "answer is not a list"),
                                 (' postsIds=', ' comment="free text" postsIds=', "alert of an unknown shape")):
            with self.subTest(reason=reason):
                reasons = [r for _l, _c, r in A.verify_aq_local_answer(LOCAL_XML.replace(old, new), doc)]
                self.assertEqual(reasons, ["AQ local check: " + reason])
        self.assertEqual(len(A.verify_aq_local_answer("free text", local_meta())), 1)

    def test_a_comment_or_an_instruction_in_a_list_fails(self):
        doc = local_meta(get=True)
        for plant in ("<!-- free text -->", "<?note free text?>", "<!DOCTYPE alertes>"):
            with self.subTest(plant=plant):
                text = LOCAL_XML.replace("<alertes>", plant + "<alertes>")
                reasons = [r for _l, _c, r in A.verify_aq_local_answer(text, doc)]
                self.assertEqual(reasons, ["AQ local check: answer holds a comment or an instruction"])

    def test_an_instruction_named_like_the_prolog_fails(self):
        text = LOCAL_XML.replace(LOCAL_XML[:LOCAL_XML.index("?>") + 2], "<?xml-note free text?>")
        reasons = [r for _l, _c, r in A.verify_aq_local_answer(text, local_meta(get=True))]
        self.assertEqual(reasons, ["AQ local check: answer holds a comment or an instruction"])

    def test_a_malformed_date_is_a_finding_that_prints_no_value(self):
        doc = dict(local_meta(get=True), date="planted value")
        reasons = [r for _l, _c, r in A.verify_aq_local_answer(LOCAL_XML, doc)]
        self.assertEqual(reasons, ["AQ local check: meta date is not a date"])

    def test_corpus_check_applies_it_through_the_meta(self):
        """A real id or title in a local capture fails `check --corpus`, the step CI runs."""
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            def write(name, text):
                with open(os.path.join(tmp, name), "w") as fh:
                    fh.write(text)
            write("T53.meta.json", json.dumps(local_meta(), indent=2))
            write("T53-a.txt", "1")
            write("T54.meta.json", json.dumps(local_meta(get=True, id="T54", file="T54-l.xml"), indent=2))
            write("T54-l.xml", LOCAL_XML)
            self.assertEqual(A.main(["check", "--quiet", "--corpus", tmp]), 0)
            write("T54-l.xml", LOCAL_XML.replace('id="13636"', 'id="13642"'))
            self.assertEqual(A.main(["check", "--quiet", "--corpus", tmp]), 1)
            write("T54-l.xml", LOCAL_XML)
            write("T53.meta.json", json.dumps(local_meta(dict(LOCAL_BODY, topic_titre="A real topic title")), indent=2))
            self.assertEqual(A.main(["check", "--quiet", "--corpus", tmp]), 1)


if __name__ == "__main__":
    unittest.main()
