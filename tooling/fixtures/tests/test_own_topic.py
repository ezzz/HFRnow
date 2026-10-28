"""Operator-owned public topics: one test per replaced position (synthetic topic 123456, messages 7000001+).

Each test checks both layers on its own:
- the independent verifier (`verify_own_topic`) reports the position when the page names the fake topic id but
  keeps the real value there;
- the anonymizer replaces the value and its output passes every check, with and without the config.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402

TOPIC = "123456"
MSG = "7000001"
FAKE_TOPIC = str(A.OWN_TOPIC_FIRST)
FAKE_MSG = str(A.OWN_MESSAGE_FIRST)
SUBJECT = "Vends velo rouge Qzwx"
HEAD = '<input type="hidden" name="post" value="%s" />' % TOPIC
# (test id, verifier label, fragment, values that must disappear, text the output must contain)
CASES = (
    ("message_id_param", "own-topic message id",
     '<a href="/message.php?config=hfr.inc&amp;cat=6&amp;post=%s&amp;numreponse=%s">e</a>' % (TOPIC, MSG), [MSG],
     ["numreponse=" + FAKE_MSG]),
    ("message_id_js", "own-topic message id (JS)",
     "<a onclick=\"quoter('hardwarefr','6',%s,%s)\">q</a><a onclick=\"edit_in('hfr.inc','6',%s,%s,'')\">e</a>"
     % (TOPIC, MSG, TOPIC, MSG), [MSG], [",%s)" % FAKE_MSG, ",%s,'')" % FAKE_MSG]),
    ("date", "own-topic date", "<div>Posté le 02-03-2024&nbsp;à&nbsp;21:21:09</div>", ["02-03-2024", "21:21:09"],
     ["01-01-2000&nbsp;à&nbsp;00:00:00"]),
    ("slug", "own-topic slug", '<a href="/hfr/AchatsVentes/Divers/vends-velo-rouge-sujet_%s_1.htm">p</a>' % TOPIC,
     ["vends-velo-rouge", TOPIC], ["/own-topic-subject-sujet_%s_1.htm" % FAKE_TOPIC]),
    ("subject", "own-topic subject", '<input type="text" name="sujet" value="%s" />' % SUBJECT, [SUBJECT, "Qzwx"],
     ['value="Own topic subject"']),
    ("description", "own-topic description",
     '<meta name="Description" content="Vends un velo Qzwx, Paris [...]" />', ["Qzwx", "Paris"],
     ['content="Own topic text removed."']),
    ("title", "own-topic title", "<title>[Qzwx] velo rouge - Divers - Achats - FORUM HardWare.fr</title>", ["Qzwx"],
     ["<title>Own topic subject - Divers"]),
    ("message_text", "message text not replaced",
     '<div id="para%s"><p>Velo Qzwx, prix 100</p></div>' % MSG, ["Qzwx"], ["Own topic text removed."]),
    ("form_review", "form review text not replaced",
     '<table><tr class="reponse"><td class="messCase1bis" width="160">user1</td><td>Velo Qzwx<br />dispo</td></tr>'
     '</table>', ["Qzwx"], ["<td>Own topic text removed.</td>"]),
    ("text_area", "text area not replaced",
     '<textarea name="content_form" id="content_form">Velo Qzwx\r\n\r\nprix</textarea>', ["Qzwx", "prix"],
     [">Text removed.\r\n\r\nText removed.</textarea>"]),
    ("list_title", "own-topic list title",
     '<td class="sujetCase3"><a href="/forum2.php?config=hfr.inc&amp;cat=6&amp;post=%s&amp;page=1" class="cCatTopic" '
     'title="Sujet n°%s">Vends velo Qzwx Operatorname</a></td><td class="sujetCase4"><a href="/forum2.php?config=hfr.inc'
     '&amp;cat=6&amp;post=%s&amp;page=2" class="cCatTopic">2</a></td>' % (TOPIC, TOPIC, TOPIC),
     ["Qzwx", "Operatorname", TOPIC], [">Own topic subject</a>", 'page=2" class="cCatTopic">2</a>']),
    ("related_topics", "related topics not replaced",
     '<table class="main" id="sujetrelatif"><tr><th>Sujets relatifs</th></tr><tr><td>'
     '<a class="cLink" href="/hfr/AchatsVentes/Divers/velo-qzwx-sujet_123450_1.htm">[Vends] velo Qzwx</a></td></tr>'
     '</table>', ["Qzwx", "123450"], ['href="/forum1.php?config=hfr.inc">Related topic</a>']),
)
BODY_CASES = (
    ("posted_text", "own-topic posted text", "post=%s&content_form=Velo+Qzwx%%0D%%0Aprix&x=1" % TOPIC, ["Qzwx", "prix"],
     ["content_form=Text+removed.%0D%0AText+removed.&"]),
    ("posted_subject", "own-topic posted subject", "post=%s&sujet=Vends+velo+Qzwx&x=1" % TOPIC, ["Qzwx"],
     ["sujet=Own+topic+subject&"]),
    ("http_date", "own-topic HTTP date", "post=%s Tue, 27 Oct 2026 21:04:39 GMT" % TOPIC, ["27 Oct 2026"],
     [A.OWN_HTTP_DATE]),
)
CONFIG = A.Config(pseudos=["Operatorname"], own_topics=[int(TOPIC)])


def page(fragment):
    return "<html><head></head><body>%s%s</body></html>" % (HEAD, fragment)


def fake(text):
    """The page as a verifier would see it if only the topic id had been aliased."""
    return text.replace(TOPIC, FAKE_TOPIC)


class OwnTopicPositionTests(unittest.TestCase):
    def test_each_position(self):
        for cid, label, fragment, gone, kept in CASES:
            with self.subTest(cid):
                raw = page(fragment)
                reasons = [r for _l, _c, r in A.verify_own_topic(fake(raw))]
                self.assertTrue(any(label in r for r in reasons), (cid, reasons))
                out = A.Anonymizer(CONFIG).anonymize(raw)
                for g in gone:
                    self.assertNotIn(g, out, cid)
                for k in kept:
                    self.assertIn(k, out, cid)
                self.assertEqual(A.verify_own_topic(out), [], cid)
                self.assertEqual(A.Anonymizer(CONFIG).findings(out), [], cid)

    def test_each_body_position(self):
        for cid, label, body, gone, kept in BODY_CASES:
            with self.subTest(cid):
                reasons = [r for _l, _c, r in A.verify_own_topic(fake(body))]
                self.assertTrue(any(label in r for r in reasons), (cid, reasons))
                anon = A.Anonymizer(CONFIG)
                anon.anonymize(page(""))  # the request body and meta use the tables of their page
                out = anon.redact_text(body)
                for g in gone:
                    self.assertNotIn(g, out, cid)
                for k in kept:
                    self.assertIn(k, out, cid)
                self.assertEqual(A.verify_own_topic(out), [], cid)


class OwnTopicScopeTests(unittest.TestCase):
    def test_other_topics_untouched(self):
        raw = ('<input type="hidden" name="post" value="654321" /><div id="para%s"><p>Velo 02-03-2024</p></div>'
               '<input type="text" name="sujet" value="%s" />' % (MSG, SUBJECT))
        out = A.Anonymizer(CONFIG).anonymize(raw)
        self.assertIn("Velo 02-03-2024", out)
        self.assertIn(MSG, out)
        self.assertIn(SUBJECT, out)
        self.assertEqual(A.verify_own_topic(out), [])

    def test_ids_consistent_across_files(self):
        other = "7000009"
        anon = A.Anonymizer(CONFIG, own_ids={MSG, other})
        first = anon.anonymize(page('<a href="?numreponse=%s">a</a>' % other))
        second = anon.anonymize('<meta http-equiv="Refresh" content="1; url=/hfr/x/y-sujet_%s_1.htm#t%s" />'
                                % (TOPIC, other))
        self.assertIn("numreponse=%d" % (A.OWN_MESSAGE_FIRST + 1), first)
        self.assertIn("#t%d" % (A.OWN_MESSAGE_FIRST + 1), second)

    def test_config_check_reports_the_real_topic_id(self):
        reasons = [r for _l, _c, r in A.Anonymizer(CONFIG).findings("<p>%s</p>" % TOPIC)]
        self.assertIn("operator-owned topic id", reasons)

    def test_line_breaks_kept(self):
        self.assertEqual(A._own_lines("a\r\n\r\nb\nc"), "Text removed.\r\n\r\nText removed.\nText removed.")


if __name__ == "__main__":
    unittest.main()
