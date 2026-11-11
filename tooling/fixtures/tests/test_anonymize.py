"""Tests for anonymize.py. All HTML here is synthetic: no real pseudo, cookie or token."""
import contextlib
import io
import os
import re
import sys
import tempfile
import unittest
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402

REAL1, REAL2, OTHER = "Zorglub", "Frobnitz", "Quuxbar"
CFG = A.Config(pseudos=[REAL1, REAL2], emails=["me@example.org"], profile_ids=[4242, 4343])


def obf(prefix, text):
    """Build an obfuscated class token the way HFR does."""
    return prefix + A.encode_payload(text)


def post(name):
    """A post author cell the way topic and MP pages print it."""
    return '<td class="messCase1" width="180"><div><b class="s2">%s</b></div></td>' % name


def mp_row(subject, pages=""):
    """An MP list row the way R13u1 prints it: subject in the title cell, page links in the next one."""
    return ('<tr><td scope="row" class="sujetCase3" ondblclick="location.href=\'/m\'"><a href="/m" class="cCatTopic" '
            'title="Sujet n°1">%s</a></td><td class="sujetCase4">%s</td></tr>' % (subject, pages))


def _ids(html):
    """The markup with member ids masked: the anonymizer aliases them."""
    return re.sub(r"(id_user=|mesdiscussions-)\d+", r"\1N", html)


def anon(html, private=False):
    return A.Anonymizer(CFG).anonymize(html, private=private)


def leaks(html, private=False):
    return A.Anonymizer(CFG).findings(html, private=private)


class CodecTests(unittest.TestCase):
    def test_round_trip(self):
        url = "/message.php?config=hfr.inc&cat=13&post=1&numreponse=7&hash_check=abc"
        self.assertEqual(A.decode_payload(A.encode_payload(url)), url)

    def test_alphabet_known_vector(self):
        # 'h' = 0x68 -> nibbles 6 and 8 -> "0A12B34C56D78E9F"[6]='4', [8]='5' (worked by hand)
        self.assertEqual(A.encode_payload("h"), "45")
        self.assertEqual(A.decode_payload("45"), "h")

    def test_non_printable_payload_is_not_decoded(self):
        self.assertIsNone(A.decode_payload("00"))  # byte 0x00
        self.assertIsNone(A.decode_payload("ZZ"))
        self.assertIsNone(A.decode_payload("0A1"))  # odd length

    def test_prefix_lengths(self):
        self.assertEqual([len(p) for p in A.PREFIXES], [20, 18, 12])

    def test_each_prefix_is_found_and_decoded(self):
        url = "/forum2.php?config=hfr.inc&cat=13&post=1234&page=2"
        for prefix in A.PREFIXES:
            html = '<div class="%s"></div>' % obf(prefix, url)
            toks = list(A.iter_tokens(html))
            self.assertEqual(len(toks), 1, prefix)
            self.assertEqual(toks[0][1], prefix)
            self.assertEqual(toks[0][3], url)

    def test_legacy_guard_short_strings_not_decoded(self):
        # prefix + payload must be longer than 20 characters (ObjCMessageActionsBuilder.m:80-89)
        html = '<a class="%s">' % obf("md_cryptlink", "ab")
        self.assertIsNone(list(A.iter_tokens(html))[0][3])


class RedactionTests(unittest.TestCase):
    def test_pseudo_variants(self):
        variants = [
            REAL1, REAL1.upper(), REAL1.lower(),
            urllib.parse.quote(REAL1), "".join("&#%d;" % ord(c) for c in REAL1),
            "".join("&#x%x;" % ord(c) for c in REAL1),
            REAL1[:3] + "&#" + str(ord(REAL1[3])) + ";" + REAL1[4:],
            REAL1.replace("o", "%6F"),
        ]
        for v in variants:
            html = '%s <a href="/x?pseudo=%s">v</a>' % (post(v), v)
            out = anon(html)
            self.assertNotIn(v, out, v)
            self.assertEqual(out.count("user1"), 2, v)
            self.assertEqual(leaks(out), [], v)

    def test_special_character_pseudo_forms(self):
        cfg = A.Config(pseudos=["A&B o'c", "Zoé"])
        a = A.Anonymizer(cfg)
        for v in ["A&amp;B o&#039;c", "A%26B+o%27c", "A&B&nbsp;o&apos;c", "Zo%C3%A9", "Zo&eacute;", "Zo&#233;", "Zo%E9"]:
            out = a.anonymize("<i>%s</i>" % v)
            self.assertRegex(out, r"<i>user[12]</i>", v)

    def test_operator_pseudo_in_script_and_comment(self):
        # Round-3 review: raw segments (script bodies, comments) get operator pseudos replaced too.
        html = '<script>var who = "%s";</script><!-- by %s --><p>x</p>' % (REAL1, REAL2)
        out = anon(html)
        self.assertEqual(out, '<script>var who = "user1";</script><!-- by user2 --><p>x</p>')

    def test_pseudo_order_gives_user_numbers(self):
        out = anon("%s then %s" % (REAL2, REAL1))
        self.assertEqual(out, "user2 then user1")

    def test_other_members_consistent_within_file(self):
        html = (post('<a href="/hfr/profil-9001.htm">%s</a>' % OTHER) +
                '<b class="s1"><a class="Topic">%s a écrit :</a></b>' % OTHER.lower())
        out = anon(html)
        self.assertNotIn(OTHER.lower(), out.lower())
        self.assertEqual(out.count("user3"), 2)
        self.assertEqual(leaks(out), [])

    def test_two_other_members_numbered_in_document_order(self):
        html = post("Aaaa") + post("Bbbb") + post("Aaaa")
        self.assertEqual(anon(html), post("user3") + post("user4") + post("user3"))

    def test_hash_check_everywhere(self):
        sample = "sample-value-one"
        html = ('<input type="hidden" name="hash_check" value="%s" />'
                '<input value=\'%s\' name=hash_check type=hidden>'
                '<a href="/modo/x.php?cat=1&amp;hash_check=%s&amp;p=2">x</a>'
                '<script>var h = "hash_check=%s"; var o = {hash_check: \'%s\'};</script>'
                % ((sample,) * 5))
        out = anon(html)
        self.assertNotIn(sample, out)
        self.assertIn("p=2", out)  # neighbouring parameters survive
        self.assertEqual(leaks(out), [])

    def test_hash_check_in_obfuscated_url_is_redacted_and_still_encoded(self):
        sample = "sample-value-two"
        url = "/message.php?config=hfr.inc&cat=13&post=1&numreponse=5&hash_check=%s&pseudo=%s" % (sample, REAL1)
        html = '<td class="%s">x</td>' % obf("md_noclass_cryptlink", url)
        out = anon(html)
        tok = list(A.iter_tokens(out))
        self.assertEqual(len(tok), 1)
        self.assertEqual(tok[0][1], "md_noclass_cryptlink")  # same prefix kept
        decoded = tok[0][3]
        self.assertIsNotNone(decoded)
        self.assertIn("hash_check=REDACTED", decoded)
        self.assertIn("pseudo=user1", decoded)
        self.assertIn("numreponse=5", decoded)
        self.assertNotIn(sample, out)

    def test_pseudo_only_in_obfuscated_url_other_member(self):
        url = "/message.php?config=hfr.inc&cat=prive&dest=%s&p=1&subcat=" % OTHER
        out = anon('<a class="%s">x</a>' % obf("md_blank_cryptlink", url))
        decoded = list(A.iter_tokens(out))[0][3]
        self.assertIn("dest=user3", decoded)

    def test_cookies_and_session_ids(self):
        html = ("Set-Cookie: md_user=%s; path=/\nCookie: md_pass=s3cr3tvalue; PHPSESSID=abc123def456\n"
                "<script>document.cookie='sessid=zzz999';</script>" % REAL1)
        out = anon(html)
        for secret in ("s3cr3tvalue", "abc123def456", "zzz999", REAL1):
            self.assertNotIn(secret, out)
        self.assertIn("md_pass=REDACTED", out)
        self.assertEqual(leaks(out), [])

    def test_hidden_token_inputs(self):
        html = ('<input type="hidden" name="csrf_x" value="short" />'
                '<input type="hidden" name="whatever" value="Ab12Cd34Ef56Gh78Ij90Kl12" />'
                '<input type="hidden" name="cat" value="13" />')
        out = anon(html)
        self.assertEqual(out.count("REDACTED"), 2)
        self.assertIn('name="cat" value="13"', out)

    def test_emails_and_ips(self):
        html = "mail me@example.org or other.person+tag@mail.example.com from 203.0.113.77 retina logo@2x.png v1.2.3.4x"
        out = anon(html)
        self.assertNotIn("me@example.org", out)
        self.assertNotIn("other.person", out)
        self.assertNotIn("203.0.113.77", out)
        self.assertIn("logo@2x.png", out)
        self.assertEqual(leaks(out), [])

    def test_profile_ids(self):
        html = '<a href="/hfr/profil-4242.htm">a</a><a href="/hfr/profil-7777.htm">b</a><a href="/hfr/profil-4242.htm">c</a>'
        out = anon(html)
        self.assertEqual(out.count("profil-900001.htm"), 2)
        self.assertIn("profil-910001.htm", out)
        self.assertNotIn("4242", out)
        self.assertNotIn("7777", out)

    def test_private_mp_list_subjects(self):
        html = (mp_row("Weekend chez Paul") + mp_row("fixture-test-1") + mp_row(A.MPSTORAGE_SUBJECT)
                + '<tr><td class="sujetCase4"><a href="/d" class="cCatTopic">12</a></td></tr>')
        self.assertTrue(leaks(html, private=True))
        self.assertFalse(leaks(html))  # public topic titles are not private
        out = anon(html, private=True)
        self.assertNotIn("Paul", out)
        for kept in ("fixture-test-1", "a2bcc09b796b8c6fab77058ff8446c34", ">12<", ">Private subject<"):
            self.assertIn(kept, out)
        self.assertEqual(leaks(out, private=True), [])

    def test_private_digit_only_subject_is_replaced_page_number_kept(self):
        # Live R13u1: three MP subjects were digits only and were kept as if they were page numbers.
        # The title cell (sujetCase3) decides, not the content; the page links (sujetCase4) stay.
        html = mp_row("12345") + mp_row("2024", pages='<a href="/p2" class="cCatTopic">2</a>')
        out = anon(html, private=True)
        self.assertNotIn("12345", out)
        self.assertNotIn(">2024<", out)
        self.assertEqual(out.count(">Private subject<"), 2)
        self.assertIn('<a href="/p2" class="cCatTopic">2</a>', out)
        self.assertEqual(leaks(out, private=True), [])

    def test_check_private_flags_digit_only_subject(self):
        reasons = [r for _l, _c, r in leaks(mp_row("1234"), private=True)]
        self.assertIn("private MP subject not replaced", reasons)
        self.assertIn("structural check: private MP subject not aliased", reasons)
        page_link = '<tr><td class="sujetCase4"><a href="/p2" class="cCatTopic">2</a></td></tr>'
        self.assertEqual(leaks(page_link, private=True), [])

    def test_structural_verifier_flags_any_kept_subject_in_private_file(self):
        # Independent of SUBJECT_RE / KEEP_SUBJECT_RE: only the placeholder, fixture threads and MPStorage pass.
        for subject in ("1234", "Weekend chez Paul", "fixture-test-1 Paul"):
            self.assertTrue(A.verify_structure(mp_row(subject), private=True), subject)
            self.assertEqual(A.verify_structure(mp_row(subject)), [], subject)
        for subject in (A.PRIVATE_SUBJECT, "fixture-test-2", A.MPSTORAGE_SUBJECT):
            self.assertEqual(A.verify_structure(mp_row(subject), private=True), [], subject)

    def test_zero_width_variant_shares_alias(self):
        # Live R21: the author block prints the pseudo with U+200B, the MP link without it.
        html = (post("Quu\u200bxbar") + ' <a href="/message.php?cat=prive&dest=Quuxbar">mp</a> ' + post("Other"))
        out = anon(html)
        self.assertIn('<b class="s2">user3\u200b</b>', out.replace("user3\u200b", "user3\u200b"))
        self.assertIn("dest=user3", out)
        self.assertIn('<b class="s2">user4</b>', out)
        self.assertNotIn("Quu", out)
        self.assertEqual(leaks(out), [])
        # A real operator pseudo split by a zero-width joiner is still caught and mapped.
        out = anon(post("Zorg\u200dlub"))
        self.assertNotIn("Zorg", out)
        self.assertIn("user1", out)

    def test_url_encoded_entity_pseudo(self):
        cfg = A.Config(pseudos=["d'Artagnan"])
        html = '<a href="/message.php?dest=d%26%23039%3BArtagnan">x</a> d&#039;Artagnan'
        out = A.Anonymizer(cfg).anonymize(html)
        self.assertNotIn("Artagnan", out)
        other = '<a href="/message.php?cat=prive&dest=d%26%23039%3BArtagnan">x</a>'
        out = A.Anonymizer(A.Config()).anonymize(other)
        self.assertNotIn("Artagnan", out)
        self.assertEqual(A.Anonymizer(A.Config()).findings(out), [])

    def test_live_cookie_names_and_logout_token(self):
        html = ('Set-Cookie: md_passs=FAKE-passs-value; md_id=5550001\n'
                '<a href="/unlog.php?config=hardwarefr.inc&codehex=FAKE-codehex-value">out</a>')
        self.assertTrue(leaks(html))
        out = anon(html)
        for secret in ("FAKE-passs-value", "5550001", "FAKE-codehex-value"):
            self.assertNotIn(secret, out)
        self.assertIn("codehex=REDACTED", out)
        self.assertEqual(leaks(out), [])

    def test_operator_id_as_bare_number(self):
        cfg = A.Config(pseudos=[REAL1], profile_ids=[None, 1234567])
        html = '[quotemsg=2666649,1,1234567] <a href="/hfr/profil-1234567.htm">x</a> 112345678'
        self.assertTrue(A.Anonymizer(cfg).findings(html))
        out = A.Anonymizer(cfg).anonymize(html)
        self.assertIn("[quotemsg=2666649,1,900002]", out)
        self.assertIn("profil-900002.htm", out)
        self.assertIn("112345678", out)  # longer numbers are not touched
        self.assertEqual(A.Anonymizer(cfg).findings(out), [])

    def test_personal_profile_fields(self):
        html = ('<input type="text" name="email" value="me@example.org"><input type="text" name="custom_ville" value="Lyon">'
                '<select name="byear"><option value="1980">1980</option><option value="1985" selected="selected">1985</option></select>'
                '<select name="online"><option value="1" selected>yes</option></select>')
        self.assertTrue(leaks(html))
        out = anon(html)
        self.assertNotIn("Lyon", out)
        self.assertNotIn('value="1985" selected', out)
        self.assertIn('<option value="1" selected>', out)  # non-personal select kept
        self.assertEqual(leaks(out), [])

    def test_idempotent(self):
        html = post(REAL1) + '<a href="/profil-4242.htm">x</a><input name="hash_check" value="abcdefabcdefabcdefabcdef">'
        once = anon(html)
        self.assertEqual(anon(once), once)


class PrivateTests(unittest.TestCase):
    PAGE = ('<table class="messagetable"><tr><td><div id="para555"><p>secret words'
            '<div class="citation">nested <div>deep</div></div></p></div><div id="after">keep</div></td></tr></table>')

    def test_private_replaces_balanced_body(self):
        out = anon(self.PAGE, private=True)
        self.assertNotIn("secret words", out)
        self.assertNotIn("deep", out)
        self.assertIn(A.PRIVATE_PLACEHOLDER, out)
        self.assertIn('<div id="after">keep</div>', out)
        self.assertEqual(leaks(out, private=True), [])

    def test_without_flag_body_kept(self):
        self.assertIn("secret words", anon(self.PAGE))

    def test_check_private_flags_unreplaced_body(self):
        self.assertTrue(any("private" in r for _l, _c, r in leaks(self.PAGE, private=True)))


def storage_page(document, title=True, header=True, second="other words"):
    """An MPStorage thread page shaped like live R60a: <title>, topic header, JSON first post, then a reply."""
    q = document.replace('"', "&#034;")
    return (('<html><head><title>%s - Messages privés - FORUM HardWare.fr</title></head><body>' % A.MPSTORAGE_SUBJECT
             if title else '<html><head><title>Messages privés</title></head><body>')
            + ('<table><tr><th scope="col" class="padding">&nbsp;Sujet : <h3>%s</h3></th></tr></table>'
               % (A.MPSTORAGE_SUBJECT if header else "Weekend"))
            + '<table class="messagetable"><tr><td><div id="para1980000001"><p>%s<div style="clear: both;"> </div>'
              '</p></div></td></tr></table>' % q
            + '<table class="messagetable"><tr><td><div id="para1980000002"><p>%s</p></div></td></tr></table>'
              '</body></html>' % second)


class MPStorageTests(unittest.TestCase):
    EMPTY = ('{"data":[{"version":"0.1","blacklist":{"list":[],"sourceName":"iOS","lastUpdate":1700000000001},'
             '"mpFlags":{"list":[],"sourceName":"iOS","lastUpdate":1700000000001},'
             '"bookmarks":{"list":[],"sourceName":"iOS","lastUpdate":1700000000001},"sourceName":"iOS",'
             '"lastUpdate":1700000000001}],"sourceName":"iOS","lastUpdate":1700000000001}')

    def reasons(self, html):
        return [r for _l, _c, r in leaks(html, private=True)]

    def test_storage_first_post_kept_exactly_other_bodies_replaced(self):
        page = storage_page(self.EMPTY)
        out = anon(page, private=True)
        first = page[page.index('<div id="para1980000001">'):page.index('<div id="para1980000002">')]
        self.assertIn(first, out)
        self.assertNotIn("other words", out)
        self.assertEqual(out.count(A.PRIVATE_PLACEHOLDER), 1)
        self.assertEqual(leaks(out, private=True), [])

    def test_ordinary_mp_with_json_body_is_replaced(self):
        out = anon(storage_page(self.EMPTY, title=False, header=False), private=True)
        self.assertNotIn("lastUpdate", out)
        self.assertEqual(out.count(A.PRIVATE_PLACEHOLDER), 2)

    def test_check_does_not_trust_the_header_alone(self):
        # The verifier finds the thread by its <title>, not by the header the anonymizer reads.
        out = anon(storage_page(self.EMPTY, title=False), private=True)
        self.assertIn("lastUpdate", out)
        self.assertIn("private message body not replaced", self.reasons(out))

    def test_pseudo_in_document_stops_the_run(self):
        doc = self.EMPTY.replace('"blacklist":{"list":[]', '"blacklist":{"list":["Quuxbar"]')
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page(doc), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page(doc)))

    def test_unknown_key_stops_the_run(self):
        doc = self.EMPTY.replace('"lastUpdate":1700000000001}],', '"lastUpdate":1700000000001,"Quuxbar":1}],')
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page(doc), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page(doc)))

    def test_unknown_source_name_stops_the_run(self):
        doc = self.EMPTY.replace('"sourceName":"iOS"', '"sourceName":"Quuxbar"', 1)
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page(doc), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page(doc)))

    def test_numeric_ids_in_a_list_stop_the_run(self):
        # Fail closed: a bare number in a list may be a member or topic id, so it is not vouched for.
        doc = self.EMPTY.replace('"blacklist":{"list":[]', '"blacklist":{"list":[555123]')
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page(doc), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page(doc)))

    def test_fast_reply_subject_constant_kept(self):
        # Live R60a: the fast-reply form repeats MP_NAME in a hidden `sujet`; 32 hex chars, but a public constant.
        page = storage_page(self.EMPTY) + '<input type="hidden" name="sujet" value="%s" />' % A.MPSTORAGE_SUBJECT
        out = anon(page, private=True)
        self.assertIn('name="sujet" value="%s"' % A.MPSTORAGE_SUBJECT, out)
        self.assertEqual(leaks(out, private=True), [])
        other = '<input type="hidden" name="sujet" value="0123456789abcdef0123456789abcdef" />'
        self.assertIn('value="REDACTED"', anon(other))

    def form_page(self, textarea, review, subject=A.MPSTORAGE_SUBJECT):
        """The storage thread's edit form shaped like live R60b: subject input, content_form, review cell."""
        return ('<form name="hop"><input type="text" name="sujet" value="%s" />'
                '<textarea cols="75" name="content_form" id="content_form">%s</textarea></form>'
                '<table><tr class="reponse"><th colspan="2">Sujet : %s</th></tr><tr class="reponse">'
                '<td class="messCase1bis" width="160" valign="top">user1</td>\n\t\t\t<td>%s<div style="clear: both;"> </div></td>'
                '</tr></table>' % (subject, textarea.replace('"', "&#034;"), subject, review.replace('"', "&#034;")))

    def test_form_copies_kept_when_clean(self):
        out = anon(self.form_page(self.EMPTY, self.EMPTY), private=True)
        self.assertEqual(out.count("lastUpdate"), 2 * self.EMPTY.count("lastUpdate"))
        self.assertEqual(leaks(out, private=True), [])

    def test_pseudo_in_form_copies_stops_the_run(self):
        # CodeRabbit on #259: the textarea and the review cell are copies of the document outside the `para` body.
        bad = self.EMPTY.replace('"blacklist":{"list":[]', '"blacklist":{"list":["Quuxbar"]')
        for page in (self.form_page(bad, self.EMPTY), self.form_page(self.EMPTY, bad)):
            with self.assertRaises(A.MPStorageDocumentError):
                anon(page, private=True)
            self.assertIn("MPStorage document copy not vouched for", self.reasons(page))

    def test_form_copies_checked_whatever_the_attribute_order_and_quotes(self):
        # CodeRabbit on #259: `value` before `name`, single-quoted `content_form`.
        bad = self.EMPTY.replace('"blacklist":{"list":[]', '"blacklist":{"list":["Quuxbar"]')
        page = (self.form_page(bad, self.EMPTY)
                .replace('<input type="text" name="sujet" value="%s" />' % A.MPSTORAGE_SUBJECT,
                         "<input value='%s' type='text' name='sujet' />" % A.MPSTORAGE_SUBJECT)
                .replace('name="content_form"', "name='content_form'"))
        self.assertIn("name='content_form'", page)
        with self.assertRaises(A.MPStorageDocumentError):
            anon(page, private=True)
        self.assertIn("MPStorage document copy not vouched for", self.reasons(page))

    def test_tag_shaped_text_in_the_textarea_is_document_text(self):
        # CodeRabbit on #259: stripping tags from the textarea would drop `<Quuxbar>` and vouch for the rest.
        bad = self.EMPTY.replace('"sourceName":"iOS"', '"sourceName":"iOS<Quuxbar>"', 1)
        page = self.form_page(bad, self.EMPTY)
        with self.assertRaises(A.MPStorageDocumentError):
            anon(page, private=True)
        self.assertIn("MPStorage document copy not vouched for", self.reasons(page))

    def test_form_of_another_thread_is_not_checked_as_a_document(self):
        page = self.form_page("plain text", "plain text", subject="fixture-test-1")
        self.assertIn("plain text", anon(page, private=True))
        self.assertNotIn("MPStorage document copy not vouched for", self.reasons(page))

    def test_number_bool_or_null_outside_timestamps_stops_the_run(self):
        # CodeRabbit on #259: a number under another key may be an id; booleans and null are not vouched for either.
        for value in ("123456", "true", "null"):
            doc = self.EMPTY.replace('"version":"0.1"', '"version":%s' % value)
            with self.assertRaises(A.MPStorageDocumentError, msg=value):
                anon(storage_page(doc), private=True)
            self.assertIn("private message body not replaced", self.reasons(storage_page(doc)), value)
        doc = self.EMPTY.replace('"lastUpdate":1700000000001}],', '"lastUpdate":true}],')
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page(doc), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page(doc)))

    def test_duplicate_key_stops_the_run(self):
        # CodeRabbit on #259: json.loads keeps the last `list`, so a first one holding a pseudo went unchecked.
        doc = self.EMPTY.replace('"blacklist":{"list":[]', '"blacklist":{"list":["Quuxbar"],"list":[]')
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page(doc), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page(doc)))

    def test_malformed_document_stops_the_run(self):
        with self.assertRaises(A.MPStorageDocumentError):
            anon(storage_page('{"data":[}'), private=True)
        self.assertIn("private message body not replaced", self.reasons(storage_page('{"data":[}')))


class CheckTests(unittest.TestCase):
    def reasons(self, html):
        return [r for _l, _c, r in leaks(html)]

    def test_clean_page_passes(self):
        clean = (post("user1") + '<input name="hash_check" value="REDACTED">'
                 '<a class="%s">x</a>' % obf("md_cryptlink", "/forum2.php?cat=13&hash_check=REDACTED&pseudo=user2"))
        self.assertEqual(leaks(clean), [])

    def test_catches_real_pseudo(self):
        self.assertIn("real pseudo", self.reasons("<p>hello %s</p>" % REAL2.lower()))

    def test_catches_other_member_pseudo(self):
        self.assertIn("member pseudo not anonymized", self.reasons(post(OTHER)))

    def test_catches_hash_check(self):
        self.assertIn("hash_check value not REDACTED", self.reasons("/x.php?hash_check=abcdef123456&p=1"))
        self.assertTrue(self.reasons('<input name="hash_check" value="abcdef123456">'))

    def test_catches_hash_check_in_obfuscated_url_with_line(self):
        page = "line1\nline2\n<a class=\"%s\">x</a>\n" % obf("md_noclass_cryptlink", "/a.php?hash_check=abcdef123456")
        found = leaks(page)
        self.assertEqual([(l, r) for l, _c, r in found],
                         [(3, "hash_check value not REDACTED (in obfuscated link)")])

    def test_catches_pseudo_in_obfuscated_url(self):
        page = '<a class="%s">x</a>' % obf("md_cryptlink", "/profil.php?pseudo=%s&x=1" % REAL1)
        self.assertTrue(any("obfuscated" in r for r in self.reasons(page)))

    def test_catches_cookie_email_ip_profile_id(self):
        self.assertTrue(any("cookie" in r for r in self.reasons("md_pass=hunter2hunter2")))
        self.assertIn("e-mail address", self.reasons("x@somewhere.example"))
        self.assertIn("operator e-mail", self.reasons("ME@EXAMPLE.ORG"))
        self.assertIn("IP address", self.reasons("from 198.51.100.7"))
        self.assertIn("operator profile id", self.reasons("/profil-4343.htm"))
        self.assertIn("hidden token input not REDACTED",
                      self.reasons('<input type="hidden" name="a" value="Ab12Cd34Ef56Gh78Ij90Kl12">'))


def _absent(test, out, *names):
    for n in names:
        test.assertNotRegex(out, "(?i)" + n.replace(" ", r"(?:\s|&nbsp;|\+|%20)"), n)


class PositionTests(unittest.TestCase):
    """One test per member position found in the live corpus (review round of PR #38, findings 1-2)."""

    def check_page(self, html, *names, private=False):
        out = anon(html, private=private)
        _absent(self, out, *names)
        self.assertEqual(leaks(out, private=private), [])
        # The independent verifier reports the raw page on its own (without DISCOVER).
        self.assertTrue(A.verify_structure(html), "verifier misses: %s" % (names,))
        return out

    def test_mp_list_unread_by_list(self):
        html = '<span class="red" title="Ce message n\'a pas été lu par : Alpha Membre, Bravo, Charlie">[non lu]</span>'
        out = self.check_page(html, "Alpha Membre", "Bravo", "Charlie")
        self.assertIn('lu par : user3, user4, user5">[non lu]', out)

    def test_mp_list_multiple_correspondents(self):
        html = ('<td class="sujetCase6 cBackCouleurTab2 "><span title="Alpha Membre,Bravo,Charlie">'
                'Interlocuteurs multiples</span></td>')
        out = self.check_page(html, "Alpha Membre", "Bravo", "Charlie")
        self.assertIn('title="user3,user4,user5">Interlocuteurs multiples</span>', out)

    def test_mp_list_recipients_lock_and_ignore_titles(self):
        html = ('<img src="/x/closedbp.gif" title="Nouveau message. Message privé pour Alpha Membre, Bravo,Charlie" />'
                '<img src="/x/lock.gif" title="Ce message privé à Delta" alt="closed" />'
                '<a href="/user/ignore.php?config=hfr.inc&amp;auteur=Foxtrot+Golf&amp;page=1">'
                '<img src="/x/ignore0.gif" title="Mettre Foxtrot Golf en ignore list" alt="On" /></a>')
        self.check_page(html, "Alpha Membre", "Bravo", "Charlie", "Delta", "Foxtrot Golf")

    # Two-letter names are never replaced in free text: these tests isolate one position each.
    def test_ignore_list_title_alone(self):
        out = self.check_page('<img src="/x/ignore0.gif" title="Mettre Fo en ignore list" alt="On" />', "Fo")
        self.assertIn('title="Mettre user3 en ignore list"', out)

    def test_lock_title_alone(self):
        out = self.check_page('<img src="/x/lock.gif" title="Ce message privé à De" alt="closed" />', "De")
        self.assertIn('title="Ce message privé à user3"', out)

    def test_moderator_link_text_alone(self):
        out = self.check_page('<a href="/message.php?cat=prive&amp;dest=Mo&amp;subcatgroup=0" class="Tableau">Mo</a>',
                              "Mo")
        self.assertIn('dest=user3&amp;subcatgroup=0" class="Tableau">user3</a>', out)
        # A link whose text is not its dest is not a name.
        self.assertIn(">Envoyer</a>", anon('<a href="/message.php?dest=Mo" class="Tableau">Envoyer</a>'))

    def test_contact_list_title_alone(self):
        out = self.check_page('<img src="/c.gif" title="Ajouter  Pq à votre liste de contacts" />', "Pq")
        self.assertIn('title="Ajouter  user3 à votre liste de contacts"', out)

    def test_list_author_and_last_poster(self):
        html = ('<td class="sujetCase6 cBackCouleurTab2 ">Hotel​India</td>'
                '<td class="sujetCase9 cBackCouleurTab2 "><a href="/hfr/x/y-sujet_1_2.htm#bas" class="Tableau">'
                '26-10-2026&nbsp;à&nbsp;01:08<br /><b>Juliet Kilo</b></a></td>')
        out = self.check_page(html, "Hotel", "Juliet Kilo")
        self.assertIn("<br /><b>user4</b>", out)

    def test_home_last_poster_and_moderator_links(self):
        html = ('<td class="catCase3">26-10-2026&nbsp;à&nbsp;01:08<br /><b>par Lima</b></td><td class="catCase4">'
                '<a rel="nofollow" href="/message.php?config=hfr.inc&amp;cat=prive&amp;dest=Mike+Oscar&amp;subcatgroup=0"'
                ' class="Tableau">Mike Oscar</a></td>')
        out = self.check_page(html, "Lima", "Mike Oscar")
        self.assertIn("<b>par user3</b>", out)
        self.assertIn('dest=user4&amp;subcatgroup=0" class="Tableau">user4</a>', out)

    def test_send_mp_and_contact_titles(self):
        html = (post("Papa Quebec") +
                '<a href="/message.php?config=hfr.inc&amp;cat=prive&amp;dest=Papa+Quebec"><img src="/pv.gif" '
                'title="Envoyer un message privé à Papa Quebec" alt="MP" /></a><a href="/user/contactlist.php?'
                'adduser=777001&amp;comeback=1"><img src="/c.gif" title="Ajouter  Papa Quebec à votre liste de contacts" '
                'alt="Ajouter  Papa Quebec à votre liste de contacts" /></a>')
        out = self.check_page(html, "Papa Quebec", "777001")
        self.assertIn("adduser=910001", out)

    def test_form_review_author_and_description_author(self):
        html = ('<meta name="Description" content="Sujet [...] - Auteur : Romeo - Page : 3 - Pages : 9" />'
                '<td class="messCase1bis" width="160" valign="top">Sierra Tango</td>')
        self.check_page(html, "Romeo", "Sierra Tango")

    def test_personal_smileys_code_and_image(self):
        html = ('<img src="https://forum-images.hardware.fr/images/perso/1/uniform victor.gif" alt="[:uniform victor:1]"'
                ' title="[:uniform victor:1]" /><img src="https://forum-images.hardware.fr/images/perso/whiskey.gif"'
                ' alt="[:whiskey]" /><textarea name="content_form">hi [:whiskey] [:uniform victor:1]</textarea>'
                '<img src="https://forum-images.hardware.fr/icones/smilies/sol.gif" alt=":sol:" />')
        out = self.check_page(html, "uniform victor", "whiskey")
        self.assertIn('images/perso/1/user3.gif" alt="[:user3:1]"', out)
        self.assertIn("hi [:user4] [:user3:1]", out)
        self.assertIn("smilies/sol.gif", out)  # site smileys are not member names

    def test_personal_smiley_with_apostrophe(self):
        html = ('<img src="https://forum-images.hardware.fr/images/perso/2/l\'echo bravo.gif" '
                'alt="[:l&#039;echo bravo:2]" title="[:l&#039;echo bravo:2]" />')
        out = self.check_page(html, "echo bravo")
        self.assertIn('images/perso/2/user3.gif" alt="[:user3:2]"', out)

    def test_pseudo_inputs_with_apostrophe_either_attribute_order(self):
        html = ('<input type="text" name="pseudo" value="l\'Oncle Bravo" />'
                '<input value="l\'Oncle Bravo" type="hidden" name="dest" />')
        out = self.check_page(html, "Oncle Bravo")
        self.assertEqual(out.count('value="user3"'), 2)

    def test_personal_smiley_code_percent_encoded_in_url(self):
        # Adversarial pass: the wiki detail URL carries the code as detail=%5B%3Acode%5D.
        html = ('<a href="/wikismilies.php?config=hfr.inc&amp;detail=%5B%3Avictor+echo%3A2%5D">x</a>'
                '<img src="/images/perso/2/victor echo.gif" alt="[:victor echo:2]" />')
        out = self.check_page(html, "victor echo", "victor\\+echo")
        self.assertIn("detail=%5B%3Auser3%3A2%5D", out)
        meta = A.Anonymizer(CFG)
        meta.anonymize(html)
        self.assertEqual(meta.anonymize_meta({"url": "/wikismilies.php?detail=%5B%3Avictor+echo%5D"})["url"],
                         "/wikismilies.php?detail=%5B%3Auser3%5D")

    def test_signature_and_mood_are_replaced(self):
        # Adversarial pass: signatures and mood statuses hold real names, handles and links.
        html = (post("Bravo") + '<span class="MoodStatus">PSN: Kilo_Lima</span>'
                '<span class="signature">Jean Exemple <a href="https://example.org/c/JeanExemple" class="cLink">'
                'ma <span>chaine</span></a></span><div id="after">kept</div>')
        self.assertTrue(A.verify_structure('<span class="signature">Jean Exemple</span>'))
        self.assertTrue(A.verify_structure('<span class="MoodStatus">PSN: Kilo_Lima</span>'))
        out = anon(html)
        _absent(self, out, "Kilo_Lima", "Jean Exemple", "JeanExemple", "chaine")
        self.assertIn('<span class="MoodStatus">Mood removed.</span>', out)
        self.assertIn('<span class="signature">Signature removed.</span><div id="after">kept</div>', out)
        self.assertEqual(leaks(out), [])

    def test_redacted_signature_allows_only_br_and_one_clear_div(self):
        sig = '<span class="signature">%s</span>'
        for ok in ("Signature removed.", "Signature removed.<br />", "Signature removed.<br /><div style=\"clear: both;\"></div>",
                   "<br />Signature removed.<div style=\"clear: both;\"></div>"):
            self.assertEqual(A.verify_structure(sig % ok), [], ok)
        for bad in ('Signature removed.<img src="https://example.org/x.png" alt="handle" />',
                    '<a href="https://example.org/">Signature removed.</a>',
                    'Signature removed.<b>x</b>', 'Signature removed.<div>x</div>',
                    'Signature removed.<div style="clear: both;"></div><div style="clear: both;"></div>',
                    'Signature removed.<br class="x" />'):
            self.assertTrue(A.verify_structure(sig % bad), bad)
        for bad in ('<!-- Real Handle -->', '<?Real Handle>', '<![CDATA[Real Handle]]>', '<!DOCTYPE RealHandle>',
                    '</img src="https://example.org/h.png">', '</br title="Real Handle">'):
            self.assertTrue(A.verify_structure(sig % ("Signature removed." + bad)), bad)
        self.assertTrue(A.verify_structure(
            '<span class="signature" title="Real Handle">Signature removed.</span>'))
        for bad in ('<span class="signature">Signature removed.</span title="Real Handle">',
                    '<span class="signature">Signature removed.<div style="clear: both;"></div title="Real Handle"></span>',
                    '<span class="signature" class="x">Real Handle<img src="https://example.org/h.png" /></span>'):
            self.assertTrue(A.verify_structure(bad), bad)
        self.assertEqual(A.verify_structure('<span class="signature">Signature removed.<div style="CLEAR: BOTH;"></div></span>'), [])
        for bad in ('<span class="signature">Signature removed.<div style="background:url(https://example.org/h.png)" '
                    'style="clear: both;"></div></span>',
                    '<div><table><tr><td><span class="signature">Signature removed.</div>'
                    '<img src="https://example.org/h.png" alt=""></span></td></tr></table></div>',
                    '<span class="signature"/><img src="https://example.org/h.png" alt=""></span>',
                    '<div><table><tr><td><span class="signature">Signature removed.<div style="clear: both;"/></span>'
                    '<img src="https://example.org/h.png" alt=""></td></tr></table></div>',
                    '<div><table><tr><td><span class="signature">Signature removed.<div/style="clear: both;"/></span>'
                    '<img src="https://example.org/h.png" alt=""></td></tr></table></div>',
                    '<span class="signature">Signature removed.<div style="clear: both;" '
                    'style="background:url(https://example.org/h.png)"></div></span>'):
            self.assertTrue(A.verify_structure(bad), bad)
        for bad in ('<img src="x.png" alt="" />', '<a href="https://example.org/">Mood removed.</a>',
                    '<div style="clear: both;"></div><div style="clear: both;"></div>', '<!-- Real Handle -->'):
            self.assertTrue(A.verify_structure('<span class="MoodStatus">Mood removed.%s</span>' % bad), bad)

    def test_signature_keeps_hfrs_separator_and_clear_div(self):
        # #267 (`R267a`): HFR opens the span with fifteen dashes and `<br />` and closes it with its clear div.
        html = (post("Bravo") + '<span class="signature"> ---------------\n\t\t\t<br /><strong> <a href="https://example.org/c/'
                'JeanExemple">Jean Exemple</a> </strong> <br /><div style="clear: both;"> </div></span><div id="after">kept</div>')
        out = anon(html)
        _absent(self, out, "Jean Exemple", "JeanExemple", "example.org")
        self.assertIn('<span class="signature"> ---------------\n\t\t\t<br />Signature removed.<div style="clear: both;"> </div>'
                      '</span><div id="after">kept</div>', out)
        self.assertEqual(leaks(out), [])

    def test_signature_dashes_typed_by_the_member_are_not_kept(self):
        # Sixteen dashes, or dashes not followed by `<br />`, are the member's text: replaced like the rest.
        for inner in ("----------------<br />Jean Exemple", "--------------- Jean Exemple<br />"):
            out = anon(post("Bravo") + '<span class="signature">%s</span>' % inner)
            self.assertIn('<span class="signature">Signature removed.</span>', out)
            _absent(self, out, "Jean Exemple")

    def test_signature_check_accepts_only_the_separator_before_the_placeholder(self):
        self.assertEqual(leaks('<span class="signature"> ---------------\n<br />Signature removed.</span>'), [])
        self.assertNotEqual(leaks('<span class="signature"> ---------------\n<br />Jean Exemple</span>'), [])
        self.assertNotEqual(leaks('<span class="signature">Signature removed. Jean</span>'), [])

    # #763: a signature or mood is member input; an unbalanced tag inside it must not end the redaction early. Both are
    # followed by HFR markup a member cannot write (`R267a`, `R63a`): the next message table, the page footer, the avatar.
    PAGES = '<table cellspacing="0" cellpadding="4" width="100%"><tr class="cBackHeader fondForum2PagesBas"><td>1</td></tr></table>'
    # HFR's author-cell tail after a mood, the one shape the corpus prints (#797).
    LINK = ('<a href="/transactions_reports.php?config=hfr.inc&amp;cat=13&amp;id_user=12345678"  onclick="window.open(this.href,'
            '\'TransactionsReports\',\'toolbar=no,scrollbars=yes,resizable=yes,width=600,height=400,left=10,top=10\'); return false" >')
    TRANSACTIONS = '<br/><span class="TransactionsReportsLink">' + LINK + 'Transactions (3)</a></span>'
    AVATAR = ('<div class="avatar_center" style="clear:both"><img src="https://forum-images.hardware.fr/images/'
              'mesdiscussions-12345678.jpg" alt="" /></div>')

    @staticmethod
    def message(sig, mood='<span class="MoodStatus">Kilo Lima</span>', n=1, after_mood='<div class="avatar_center" style="clear:both"></div>'):
        """A message row the way topic pages print it (`R267a`): mood in the author cell, signature last in the para div."""
        return ('<table cellspacing="0" cellpadding="4" width="100%%" class="messagetable"><tr class="message"><td class="messCase1" '
                'width="180"><div><b class="s2">user%d</b></div>%s%s</td><td class="messCase2" valign="top"><div id="para%d">'
                '<p>Corps du message<div style="clear: both;"> </div></p><br /><span class="signature">%s</span></div>'
                '</td></tr></table>' % (n, mood, after_mood, n, sig))

    def page(self, *sigs, mood='<span class="MoodStatus">Mood removed.</span>', tail=None):
        return "".join(self.message(s, mood, i + 1) for i, s in enumerate(sigs)) + (self.PAGES if tail is None else tail)

    def reasons(self, html):
        return " ".join(r for _l, _c, r in A.verify_structure(html))

    def test_unbalanced_span_end_in_a_signature_does_not_end_the_redaction(self):
        sig = (' ---------------\n\t\t\t<br /><b>Jean Exemple</SPAN >Secret Handle<span class="x">Other Words'
               '<div style="clear: both;"> </div>')
        out = anon(self.page(sig, mood='<span class="MoodStatus">Kilo Lima</span>'))
        _absent(self, out, "Jean Exemple", "Secret Handle", "Other Words", "Kilo Lima")
        self.assertIn('<span class="signature"> ---------------\n\t\t\t<br />Signature removed.<div style="clear: both;"> </div>'
                      '</span></div></td></tr></table>' + self.PAGES, out)
        self.assertEqual(leaks(out), [])

    def test_signature_end_tag_case_does_not_matter(self):
        html = self.page('Jean Exemple</span>Secret Handle<div style="clear: both;"> </div>').replace(
            '</span></div></td>', '</SPAN ></div></td>')
        _absent(self, anon(html), "Jean Exemple", "Secret Handle")

    def test_unbalanced_ends_in_a_signature_are_redacted_too(self):
        for sig in ('Jean Exemple</span>Secret Handle</div>Other Words<div style="clear: both;"> </div>',
                    'Jean Exemple</span></div>Secret Handle</td>Other Words<div style="clear: both;"> </div>',
                    'Jean Exemple</span></div></td></tr></table>Secret Handle<div>Other Words<div style="clear: both;"> </div>'):
            for tail in (None, '<br /><script type="text/javascript">var x=1;</script>'):
                out = anon(self.page(sig, tail=tail))
                _absent(self, out, "Jean Exemple", "Secret Handle", "Other Words")
                self.assertEqual(leaks(out), [], sig)

    def test_unbalanced_start_in_a_signature_stops_at_the_next_message(self):
        # An unclosed <span>, <div> or <td> in a signature must not swallow the next message.
        for sig in ('<span>Jean Exemple', '<div>Jean Exemple', '<td>Jean Exemple'):
            out = anon(self.page(sig, "Second signature"))
            _absent(self, out, "Jean Exemple", "Second signature")
            self.assertEqual(out.count('class="messagetable"'), 2, sig)
            self.assertIn("Corps du message", out.split('<div id="para2">')[1], sig)
            self.assertEqual(leaks(out), [], sig)

    def test_unbalanced_span_end_in_a_mood_does_not_end_the_redaction(self):
        for after in ('<div class="avatar_center" style="clear:both"></div>',
                      self.TRANSACTIONS, ''):
            mood = '<span class="MoodStatus">Kilo</span>Secret Handle<span class="x">Lima</span></span>'
            out = anon(self.message("Signature removed.", mood, after_mood=after) + self.PAGES)
            _absent(self, out, "Kilo", "Secret Handle", "Lima")
            self.assertIn(_ids('<span class="MoodStatus">Mood removed.</span>' + after + '</td>'), _ids(out))
            self.assertEqual(leaks(out), [], after)

    def test_check_refuses_content_after_a_signature(self):
        self.assertEqual(A.verify_structure(self.page("Signature removed.", "Signature removed.")), [])
        self.assertEqual(A.verify_structure(self.page("Signature removed.", tail='<br /><script>var x=1;</script>')), [])
        for sig in ('Signature removed.</span>Secret Handle<span class="x">',
                    'Signature removed.</span><img src="https://example.org/h.png" alt="" />',
                    'Signature removed.</span><a href="https://example.org/c/handle"></a><span>',
                    'Signature removed.</span></div>Secret Handle</td>',
                    'Signature removed.</span></div></td></tr>Secret Handle'):
            self.assertIn("after a signature", self.reasons(self.page(sig)), sig)
            self.assertTrue(leaks(self.page(sig)), sig)

    def test_check_refuses_content_after_a_mood(self):
        for after in ('<div class="avatar_center" style="clear:both"></div>', '<br/><span class="TransactionsReportsLink"></span>', ''):
            self.assertEqual(A.verify_structure(self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>',
                                                             after_mood=after) + self.PAGES), [], after)
        for bad in ('Secret Handle', '<span class="x"></span>', '<img src="https://example.org/h.png" alt="" />', '</div>Secret Handle'):
            html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>' + bad) + self.PAGES
            self.assertIn("after a mood", self.reasons(html), bad)

    def test_check_refuses_a_member_value_in_a_signature_attribute(self):
        for bad in ('<span class="signature" title="Real Handle">Signature removed.</span>',
                    '<span class="signature">Signature removed.<a href="https://example.org/c/handle"></a></span>',
                    '<span class="signature">Signature removed.<img src="https://example.org/h.png" alt="Real Handle" /></span>',
                    '<span class="signature RealHandle">Signature removed.</span>',
                    '<span class="signature" class="RealHandle">Signature removed.</span>',
                    '<span class="signature" class="signature">Signature removed.</span>',
                    '<span class="MoodStatus RealHandle">Mood removed.</span>'):
            self.assertIn("signature or mood", self.reasons(bad), bad)

    def test_check_refuses_svg_math_and_cdata(self):
        # #768: html.parser reads <style>/<script> as raw text everywhere, a browser not inside svg or math; it also reads
        # `<![CDATA[ … ]]>` as one declaration where a browser ends that bogus comment at the first `>`.
        for bad in ('<p><svg><style><span class="signature">Real Handle</span></style></svg></p>',
                    '<p><math><style><span class="signature">Real Handle</span></style></math></p>',
                    '<p><SVG/></p>', '<p><Math></Math></p>',
                    '<td class="messCase1"><![CDATA[ <b class="s2">Real Handle</b> ]]></td>'):
            self.assertTrue(A.verify_structure(bad), bad)
            self.assertTrue(leaks(bad), bad)

    # #797: the shapes #794 does not cover fail loudly, in the redactor and in check, never pass silently.
    def test_forged_boundary_in_a_signature_fails_loudly(self):
        # A member able to print HFR's next element inside the signature, its message cell still open.
        for forged in ('<table class="messagetable"><tr><td>Secret Handle</td></tr></table><span>',
                       '<script>var x = "Secret Handle";</script><span>',
                       '<table cellspacing="0"><tr class="cBackHeader"><td>Secret Handle</td></tr></table><span>'):
            with self.assertRaises(A.AnonymizeError, msg=forged):
                anon(self.page("Jean Exemple</span>" + forged))
            html = self.page("Signature removed.</span>" + forged)
            self.assertIn("signature cell still open", self.reasons(html), forged)
            self.assertTrue(leaks(html), forged)

    def test_forged_boundary_in_a_mood_fails_loudly(self):
        for forged in ('<div class="avatar_center">x</div>Secret Handle<span>',
                       '<div class="avatar_center"></div><span>',
                       '<span class="TransactionsReportsLink">Secret Handle</span><span>',
                       '</td><td class="messCase2">Secret Handle</td><td><span>'):
            for after in ('', '<div class="avatar_center" style="clear:both"></div>'):
                mood = '<span class="MoodStatus">Kilo</span>' + forged + '</span>'
                with self.assertRaises(A.AnonymizeError, msg=forged + after):
                    anon(self.message("Signature removed.", mood, after_mood=after) + self.PAGES)
                html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>' + forged + '</span>',
                                    after_mood=after) + self.PAGES
                self.assertTrue(A.verify_structure(html), forged + after)
                self.assertTrue(leaks(html), forged + after)
        html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span><td class="messCase2">x</td>',
                            after_mood='') + self.PAGES
        self.assertIn("mood cell still open", self.reasons(html))

    def test_check_accepts_hfrs_tail_after_a_mood(self):
        tail = self.TRANSACTIONS + self.AVATAR
        html = self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>', after_mood=tail) + self.PAGES
        out = anon(html)
        self.assertIn(_ids('<span class="MoodStatus">Mood removed.</span>' + tail + '</td>'), _ids(out))
        self.assertEqual(A.verify_structure(out), [])
        link, img = self.LINK, '<img src="https://forum-images.hardware.fr/images/mesdiscussions-12345678.jpg" alt="" />'
        div = '<div class="avatar_center" style="clear:both">'
        span = '<br/><span class="TransactionsReportsLink">'
        for bad in (span + link + 'Secret Handle</a></span>',
                    span + '<b>Transactions (3)</b></span>',
                    span + 'Transactions (3)</span>',
                    span + link.replace('id_user=12345678', 'id_user=Secret') + 'Transactions (3)</a></span>',
                    span + link.replace('return false', 'Secret Handle') + 'Transactions (3)</a></span>',
                    span + link.replace('<a ', '<a title="Secret Handle" ') + 'Transactions (3)</a></span>',
                    span + '<a href="/transactions_reports.php?config=hfr.inc&amp;cat=13&amp;id_user=1">Transactions (3)</a></span>',
                    span + link + 'Transactions (3)</a>' + link + '</a></span>',
                    '<br/><span class="TransactionsReportsLink" title="Secret Handle"></span>',
                    div + 'Secret Handle</div>',
                    div + '<b></b></div>',
                    div + img + img + '</div>',
                    div + img.replace('alt=""', 'alt="Secret Handle"') + '</div>',
                    div + img.replace('alt=""', 'alt="" title="Secret Handle"') + '</div>',
                    div + img.replace('forum-images.hardware.fr', 'example.org') + '</div>',
                    '<div class="avatar_center" style="clear:both" title="Secret Handle"></div>',
                    '<div class="avatar_center" style="background:url(https://example.org/h.png)"></div>',
                    div + '</div><span class="TransactionsReportsLink"></span>',
                    div + '</div><div class="avatar_center"></div>'):
            out = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>', after_mood=bad) + self.PAGES
            self.assertIn("after a mood", self.reasons(out), bad)

    def test_forged_tail_in_a_mood_fails_loudly(self):
        # #797 review: a forged transactions link or avatar inside the mood, closed by HFR's own `</span>`.
        link = '<br/><span class="TransactionsReportsLink"><a href="/Secret-Handle">Transactions (1)</a>'
        avatar = '<div class="avatar_center" style="clear:both"><img src="https://example.org/Secret-Handle.png" alt="" /></div><span>'
        for forged in (link, self.TRANSACTIONS.replace('return false', 'Secret Handle')[:-len('</span>')], avatar):
            for after in ('', self.AVATAR):
                with self.assertRaises(A.AnonymizeError, msg=forged + after):
                    anon(self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>' + forged + '</span>',
                                      after_mood=after) + self.PAGES)
                html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>' + forged + '</span>',
                                    after_mood=after) + self.PAGES
                self.assertIn("after a mood", self.reasons(html), forged + after)

    def test_check_refuses_a_second_message_cell_after_a_mood(self):
        # The member closes the author cell, then prints a message cell, even in a row of its own (#797 review).
        for forged in ('</td><td class="messCase2">Secret Handle</td><td><span>',
                       '</td><td class="messCase2">Secret Handle</td></tr><tr><td><span>'):
            html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>' + forged + '</span>',
                                after_mood='') + self.PAGES
            self.assertIn("second message cell after a mood", self.reasons(html), forged)
            with self.assertRaises(A.AnonymizeError, msg=forged):
                anon(self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>' + forged + '</span>',
                                  after_mood='') + self.PAGES)
        self.assertEqual(A.verify_structure(self.page("Signature removed.", "Signature removed.")), [])

    def test_check_requires_hfrs_closing_sequence_before_the_boundary(self):
        # #797 review round 2: the member closes the block's cell (and more) before printing HFR's next element.
        for html in (self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span></td></tr></table>'
                                  '<td class="messCase2">Secret Handle</td><span>', after_mood='') + self.PAGES,
                     self.page('Signature removed.</span></div></td><table class="messagetable"><tr><td>Secret Handle<div><span>'),
                     self.page('Signature removed.</span></div></td></tr><script>var x = "Secret Handle";</script><tr><td><div>'
                               '<span>')):
            self.assertIn("closing", self.reasons(html), html)
        self.assertEqual(A.verify_structure(anon(self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>',
                                                              after_mood=self.TRANSACTIONS + self.AVATAR) + self.PAGES)), [])

    def test_mood_tail_pins_fail_loudly_one_by_one(self):
        # Each pin of HFR's author-cell tail on its own: the rest of the tail is HFR-exact.
        img = '<img src="https://forum-images.hardware.fr/images/mesdiscussions-12345678.jpg" alt="" />'
        redactor = (self.TRANSACTIONS.replace('/transactions_reports.php?config=hfr.inc&amp;cat=13&amp;id_user=12345678',
                                              '/Secret-Handle'),
                    self.AVATAR.replace('forum-images.hardware.fr', 'example.org'),
                    self.AVATAR.replace('clear:both', 'clear:both;background:url(https://example.org/h.png)'),
                    self.AVATAR.replace('.jpg', '.svg'))
        for tail in redactor:
            with self.assertRaises(A.AnonymizeError, msg=tail):
                anon(self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>', after_mood=tail) + self.PAGES)
        check = redactor + ('<div class="avatar_center" style="clear:both"></div>' * 2,
                            '<br/>' + self.LINK + 'Transactions (3)</a>',
                            img,
                            self.AVATAR.replace('alt=""', 'alt="Secret Handle" alt=""'),  # a browser keeps the first
                            self.TRANSACTIONS.replace('<a href=', '<a href="/transactions_reports.php?config=hfr.inc&amp;cat=1'
                                                                   '&amp;id_user=1" href='))
        # HFR serves jpg, png and gif avatars (corpus: `mesdiscussions-N.gif` in R57b, R335b).
        for ext in ('.jpg', '.png', '.gif'):
            out = anon(self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>',
                                    after_mood=self.AVATAR.replace('.jpg', ext)) + self.PAGES)
            self.assertEqual(A.verify_structure(out), [], ext)
        for tail in check:
            html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>', after_mood=tail) + self.PAGES
            self.assertIn("after a mood", self.reasons(html), tail)

    def test_check_refuses_a_second_message_cell_in_a_row_outside_a_message_table(self):
        html = ('<html><body><table><tr><td class="messCase1"><span class="MoodStatus">Mood removed.</span></td>'
                '<td class="messCase2">x</td><td class="messCase2">Secret Handle</td></tr></table></body></html>')
        self.assertIn("second message cell after a mood", self.reasons(html))

    def test_unclosed_or_unbounded_blocks_in_a_page_fail_loudly(self):
        # A signature never closed before the next message, a mood with no message cell after its avatar, and a message
        # table with no html or body around it: each is a page, so none falls back to the depth count.
        for html in (self.page("Jean Exemple", "Signature removed.").replace('Jean Exemple</span>', 'Jean Exemple', 1),
                     '<html><body><table><tr><td class="messCase1"><span class="MoodStatus">Kilo</span>'
                     '<div class="avatar_center" style="clear:both"></div></td></tr></table></body></html>',
                     '<html><body><table><tr><td class="messCase1"><span class="MoodStatus">Kilo</span>'
                     '<div class="avatar_center" style="clear:both"></div></td>',
                     '<table class="messagetable"><tr><td class="messCase2"><span class="signature">Jean Exemple</span>'
                     '</td></tr></table>'):
            with self.assertRaises(A.AnonymizeError, msg=html):
                anon(html)

    def test_no_boundary_after_a_personal_block_fails_loudly(self):
        # A page whose signature or mood is followed by none of HFR's next elements.
        page = '<html><body><div><span class="signature">Jean Exemple</span></div></body></html>'
        with self.assertRaises(A.AnonymizeError):
            anon(page)
        with self.assertRaises(A.AnonymizeError):
            anon('<html><body><td class="messCase1"><span class="MoodStatus">Kilo</span></td></body></html>')
        self.assertIn("no HFR element after a signature",
                      self.reasons('<html><body><div><span class="signature">Signature removed.</span></div></body></html>'))
        self.assertIn("no HFR element after a mood",
                      self.reasons('<html><body><td class="messCase1"><span class="MoodStatus">Mood removed.</span></td></body></html>'))

    def test_check_refuses_non_elements_after_a_personal_block(self):
        for bad in ('<!-- Secret Handle -->', '<!DOCTYPE Secret Handle>', '<?Secret Handle>', '</b title="Secret Handle">',
                    '<![if Secret Handle]>'):
            html = self.page("Signature removed.", tail=bad + self.PAGES)
            self.assertIn("after a signature", self.reasons(html), bad)
            html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span>' + bad) + self.PAGES
            self.assertIn("after a mood", self.reasons(html), bad)

    def test_unknown_markup_before_the_boundary_fails_loudly(self):
        # An HFR element the boundary list does not know (invented `span.MDStatus`) must not be cut silently. Right before
        # a boundary it reads like a member's unbalanced `</span>` (#763), which is redacted: what follows it must be HFR's.
        for after in ('<br/><span class="MDStatus">Online</span><br/>', '<br/><span class="MDStatus">Online</span><b>x</b>',
                      '<span class="MDStatus">Online</span><br/><img src="https://example.org/a.png" />'):
            with self.assertRaises(A.AnonymizeError, msg=after):
                anon(self.message("Signature removed.", '<span class="MoodStatus">Kilo</span>', after_mood=after) + self.PAGES)
        for tail in ('<div><p>Bas de page</p></div>' + self.PAGES, '<div><div class="x"></div></div>' + self.PAGES,
                     '<br class="x" />' + self.PAGES, self.PAGES.replace('cellspacing="0"', 'border="0"'),
                     self.PAGES.replace('cellspacing="0"', 'cellspacing="0" title="Secret Handle"')):
            with self.assertRaises(A.AnonymizeError, msg=tail):
                anon(self.page("Jean Exemple", tail=tail))
        # HFR's own closing, a bare <br> and the footer table stay accepted.
        for tail in (None, '<br /><script>var x=1;</script>', ' \n<br/>\n' + self.PAGES):
            self.assertNotIn("Jean Exemple", anon(self.page("Jean Exemple", tail=tail)), tail)

    def test_check_refuses_a_br_or_table_with_attributes_after_a_signature(self):
        for bad in ('<br title="Secret Handle" />', '<br class="x">'):
            self.assertIn("after a signature", self.reasons(self.page("Signature removed.", tail=bad + self.PAGES)), bad)
        for bad in ('<table title="Secret Handle">', '<table class="x">', '<table width="Secret">', '<table>'):
            html = self.page("Signature removed.", tail=bad + '<tr class="cBackHeader"><td>1</td></tr></table>')
            self.assertIn("after a signature", self.reasons(html), bad)
        html = self.page("Signature removed.", tail='<table border="0">' + '<tr class="cBackHeader"><td>1</td></tr></table>')
        self.assertIn("after a signature", self.reasons(html))
        html = self.message("Signature removed.", '<span class="MoodStatus">Mood removed.</span><table cellspacing="0"></table>') \
            + self.PAGES
        self.assertIn("after a mood", self.reasons(html))

    def test_check_accepts_cdata_in_an_xml_document_only(self):
        xml = '<?xml version="1.0" encoding="UTF-8"?><alertes><alerte id="1"><![CDATA[texte]]></alerte></alertes>'
        self.assertEqual(A.verify_structure(xml), [])
        for bad in ('<html>' + xml[38:] + '</html>', xml.replace('<?xml version="1.0" encoding="UTF-8"?>', '')):
            self.assertIn("<![CDATA", self.reasons(bad), bad)

    def test_quotemsg_third_value_uses_the_id_table(self):
        html = ('<a href="/hfr/profil-555123.htm">x</a><a href="/hfr/profil-555124.htm">y</a>'
                '<textarea name="content_form">[quotemsg=99,1,555124]q[/quotemsg]</textarea>'
                '<img src="https://forum-images.hardware.fr/images/mesdiscussions-555124.jpg" alt="" />')
        out = self.check_page(html, "555123", "555124")
        self.assertIn("[quotemsg=99,1,910002]", out)
        self.assertIn("profil-910002.htm", out)
        self.assertIn("mesdiscussions-910002.jpg", out)

    def test_smiley_search_member_id_uses_the_id_table(self):
        # Live R60b: the composer's smiley search passes the logged-in member's id; alone in the page here,
        # so neither a profile link nor the operator ids of the config can hide a missing position.
        html = ('<input type="text" value="" name="search_smilies" id="search_smilies" size="10" '
                'onkeyup="find_smilies_timer(\'hfr.inc\',55512)"/>')
        out = self.check_page(html, "55512")
        self.assertIn("find_smilies_timer('hfr.inc',910001)", out)

    def test_rest_api_authors(self):
        doc = ('{"resource":{"resources":[{"title":"Topic of X-ray","links":{"last_author":{"type":"link",'
               '"href":null,"title":"X-ray Yankee","tns3":"mesdiscussions-555200.jpg"},"author":{"type":"link",'
               '"href":null,"title":"Zul\\u00fc"}}}]}}')
        out = anon(doc)
        _absent(self, out, "X-ray Yankee", "555200", "Zul")
        self.assertIn('"title":"Topic of X-ray"', out)  # a topic title is not an author
        self.assertIn('"title":"user3","tns3":"mesdiscussions-910001.jpg"', out)
        self.assertEqual(leaks(out), [])
        self.assertTrue(A.verify_structure(doc))
        self.assertEqual(A.markup_signature(out), A.markup_signature(doc))

    def test_multi_word_pseudo_is_matched_whole(self):
        # Both "Alpha" and "Alpha de Bravo" are members: the longer name is never split.
        html = post("Alpha") + post("Alpha de Bravo") + '<div id="para1"><p>merci Alpha de Bravo et Alpha</p></div>'
        out = anon(html)
        self.assertIn("merci user4 et user3", out)
        self.assertNotIn("de Bravo", out)

    def test_poll_question_in_s2_is_not_a_member(self):
        # Nit: a short poll question printed in `b.s2` was aliased as a member.
        question = "Votre carburant ?"
        html = ('<form action="/user/vote.php"><input type="hidden" name="hash_check" value="" />'
                '<b class="s2">%s</b></form>' % question)
        self.assertIn(question, anon(html))
        self.assertEqual(leaks(html), [])

    def test_operator_listed_extra_pseudos(self):
        # Operator-local list (never committed): names seen only in public prose or titles, even short ones.
        cfg = A.Config(pseudos=[REAL1], extra_pseudos=["Zed", "Oxo"])
        out = A.Anonymizer(cfg).anonymize('<a class="cCatTopic" href="/hfr/x/zed-sujet_1_1.htm">[MAJ / Zed] Oxo</a>')
        self.assertEqual(out, '<a class="cCatTopic" href="/hfr/x/user2-sujet_1_1.htm">[MAJ / user2] user3</a>')

    def test_name_known_from_another_file(self):
        html = '<div id="para1"><p>Salut Quintette, ta photo</p></div>'
        out = A.Anonymizer(CFG, known_names=["Quintette"]).anonymize(html)
        self.assertIn("Salut user3, ta photo", out)


class FreeTextTests(unittest.TestCase):
    """Finding 3: free-text replacement never touches markup, short names or common words."""

    def test_ordinary_noun_pseudo_is_replaced_in_prose(self):
        # Adversarial pass: a too broad common-word list let prose name a member ("tu l'as faite Tomate ?").
        out = anon(post("Tomate") + '<div id="para1"><p>comment tu l\'as faite tomate ?</p></div>')
        self.assertIn("faite user3 ?", out)

    def test_short_and_common_names_only_in_their_positions(self):
        html = ('<head><meta name="Robots" content="index, follow" /></head>' + post("p") + post("Le") +
                post("follow") + '<div id="para1"><p>Le chat dort, p 3.</p><a rel="nofollow" href="/a">x</a></div>')
        out = anon(html)
        self.assertIn('content="index, follow"', out)
        self.assertIn("<p>Le chat dort, p 3.</p>", out)
        self.assertIn(post("user3") + post("user4") + post("user5"), out)
        self.assertEqual(A.markup_signature(out), A.markup_signature(html))

    def test_never_inside_tag_or_attribute_names(self):
        html = post("tablette") + post("hrefx") + '<table><tr><td><a hrefx="/x">tablette hrefx</a></td></tr></table>'
        out = anon(html)
        self.assertIn('<table><tr><td><a hrefx="/x">user3 user4</a>', out)

    def test_slug_and_meta_final_url_stay_consistent(self):
        a = A.Anonymizer(A.Config())
        page = (post("Margarita") + '<a href="/hfr/Discussions/Cuisine/margarita-maison-sujet_28563_1.htm">'
                "Margarita maison</a>")
        out = a.anonymize(page)
        meta = a.anonymize_meta({"final_url": "https://forum.hardware.fr/hfr/Discussions/Cuisine/"
                                              "margarita-maison-sujet_28563_1.htm", "note": "Margarita"})
        self.assertIn("/hfr/Discussions/Cuisine/user1-maison-sujet_28563_1.htm", out)
        self.assertTrue(meta["final_url"].endswith("/hfr/Discussions/Cuisine/user1-maison-sujet_28563_1.htm"))
        self.assertEqual(meta["note"], "user1")

    def test_slug_keeps_one_word_of_a_name_aliased_in_the_title(self):
        # Live R07: title `[Ab Cdef ] colo en cours 10-2018`, slug `cdef-cours-2018` (HFR keeps 3 title words).
        # The title was aliased, the slug kept the name's second word (in hrefs and in the meta URLs).
        a = A.Anonymizer(A.Config(), known_names=["Rhubarbe Tagada"])
        page = ('<td class="sujetCase3"><a href="/hfr/Graphisme/Galerie/tagada-cours-2018-sujet_21064_1.htm" '
                'class="cCatTopic">[Rhubarbe Tagada ] colo en cours 10-2018</a></td>'
                '<a href="/hfr/Graphisme/Galerie/tagada-cours-2018-sujet_21064_109.htm#bas">x</a>')
        out = a.anonymize(page)
        meta = a.anonymize_meta({"final_url": "https://forum.hardware.fr/hfr/Graphisme/Galerie/"
                                              "tagada-cours-2018-sujet_21064_1.htm"})
        self.assertNotIn("tagada", out.lower())
        self.assertIn(">[user1 ] colo en cours 10-2018<", out)
        self.assertIn("/user1-cours-2018-sujet_21064_1.htm", out)
        self.assertIn("/user1-cours-2018-sujet_21064_109.htm#bas", out)
        self.assertTrue(meta["final_url"].endswith("/user1-cours-2018-sujet_21064_1.htm"))
        # A corpus-wide name not printed in this file keeps the whole-form rule only (no collateral).
        other = A.Anonymizer(A.Config(), known_names=["Rhubarbe Tagada"]).anonymize(
            '<a href="/hfr/Cuisine/tarte-rhubarbe-sujet_1_1.htm">Tarte</a>')
        self.assertIn("/tarte-rhubarbe-sujet_1_1.htm", other)

    def test_slug_words_follow_hfr_rules(self):
        # Measured on the LOT-001 title/slug pairs: `_` and non-ASCII punctuation join, other characters split.
        self.assertEqual(A.slug_words("Écureuil_Fou’x l'Ami"), ["ecureuilfoux", "l", "ami"])
        a = A.Anonymizer(A.Config(), known_names=["Grand_Manitou"])
        out = a.anonymize('<a href="/hfr/A/B/grandmanitou-retour-sujet_5_1.htm">Grand_Manitou retour</a>')
        self.assertIn("/user1-retour-sujet_5_1.htm", out)

    def test_internal_paths_and_scripts_keep_their_words(self):
        html = (post("Discussions") + '<a href="/hfr/Discussions/liste_sujet-1.htm">x</a>'
                "<script>var Discussions = 1;</script>")
        out = anon(html)
        self.assertIn('href="/hfr/Discussions/liste_sujet-1.htm"', out)
        self.assertIn("var Discussions = 1;", out)

    def test_markup_change_is_refused(self):
        a = A.Anonymizer(A.Config())
        original = a._per_segment
        a._per_segment = lambda text: original(text).replace("<td", "<user1", 1)
        with self.assertRaises(A.AnonymizeError):
            a.anonymize(post("Bravo"))


class VerifierTests(unittest.TestCase):
    """The structural verifier is independent of DISCOVER: a missing selector is still caught."""

    def test_check_catches_a_position_missing_from_discover(self):
        page = '<td class="sujetCase6 cBackCouleurTab2 ">Bravo Charlie</td>'
        saved = A.DISCOVER
        try:
            A.DISCOVER = tuple(d for d in saved if d[0] != "list author")
            out = anon(page)
            self.assertIn("Bravo Charlie", out)  # the anonymizer missed it...
            self.assertTrue(any(r.startswith("structural check") for _l, _c, r in leaks(out)))  # ...check did not
        finally:
            A.DISCOVER = saved

    def test_aliases_and_fake_ids_pass(self):
        page = (post("user3") + '<a href="/hfr/profil-910001.htm">user3</a>'
                '<img src="/images/perso/user3.gif" alt="[:user3]" /><b class="s2">Poll question here</b>')
        self.assertEqual(A.verify_structure(page), [])

    def test_real_member_id_is_reported(self):
        self.assertTrue(A.verify_structure('<a href="/user/contactlist.php?adduser=123456">x</a>'))

    def test_findings_never_print_values_or_neighbours(self):
        # Two adjacent leaks: printing context around one would show the other (CI logs are public).
        page = ('<td class="sujetCase6 x">Firstleak</td><td class="sujetCase6 x">Secondleak</td>\n'
                'x hash_check=fakehashvaluetest&amp;pseudo=Thirdleak')
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "page.html")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(page)
            out = io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
                self.assertEqual(A.main(["check", path]), 1)
        printed = out.getvalue()
        self.assertIn("page.html:1:", printed)
        self.assertIn("page.html:2:", printed)
        for value in ("Firstleak", "Secondleak", "Thirdleak", "fakehashvaluetest"):
            self.assertNotIn(value, printed)
        self.assertTrue(all(isinstance(c, int) for _l, c, _r in leaks(page)))


class CookieTests(unittest.TestCase):
    def test_md_data_cookie(self):
        # Finding 7: bddpost.php answers set md_data (live W14).
        text = "Set-Cookie: md_data=fake-data-value-for-test; path=/"
        self.assertTrue(leaks(text))
        out = anon(text)
        self.assertNotIn("fake-data-value-for-test", out)
        self.assertEqual(leaks(out), [])


class CliTests(unittest.TestCase):
    def test_check_without_config_and_corpus_mode(self):
        # Finding 5: CI checks the committed corpus without the operator config.
        import json
        with tempfile.TemporaryDirectory() as d:
            def write(name, text):
                with open(os.path.join(d, name), "w", encoding="utf-8") as fh:
                    fh.write(text)
            write("X1.meta.json", json.dumps({"id": "X1", "file": "X1-a.html", "private": True}))
            write("X1-a.html", post("user3") + '<div id="para1">%s</div>' % A.PRIVATE_PLACEHOLDER)
            write("X2.meta.json", json.dumps({"id": "X2", "url": "/m.php?dest=user3"}))
            write("MANIFEST.md", "notes")
            self.assertEqual(A.main(["check", "--corpus", d]), 0)
            write("X1-a.html", post("user3") + '<div id="para1">private words</div>')  # meta says private
            self.assertEqual(A.main(["check", "--corpus", d]), 1)
            write("X1-a.html", post("user3") + '<div id="para1">%s</div>' % A.PRIVATE_PLACEHOLDER)
            write("X2.meta.json", json.dumps({"id": "X2", "url": "/m.php?dest=Bravo"}))  # leak in a meta
            self.assertEqual(A.main(["check", "--corpus", d]), 1)
            write("X2.meta.json", json.dumps({"id": "X2"}))
            write("X3-orphan.html", "<p>x</p>")  # a file no meta describes is not silently skipped
            self.assertEqual(A.main(["check", "--corpus", d]), 1)
            os.remove(os.path.join(d, "X3-orphan.html"))
            self.assertEqual(A.main(["check", os.path.join(d, "X1-a.html")]), 0)

    def test_cli_end_to_end_and_check_exit_codes(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            cfg = os.path.join(d, "local.json")
            with open(cfg, "w") as fh:
                json.dump({"pseudos": [REAL1], "emails": [], "profile_ids": []}, fh)
            src, dst = os.path.join(d, "in.html"), os.path.join(d, "out.html")
            with open(src, "w", encoding="latin-1") as fh:
                fh.write(post(REAL1) + ' é <input name="hash_check" value="abcdefabcdef">')
            self.assertEqual(A.main(["--config", cfg, src, dst]), 0)
            with open(dst, encoding="latin-1") as fh:
                self.assertEqual(fh.read(), post("user1") + ' é <input name="hash_check" value="REDACTED">')
            self.assertEqual(A.main(["check", "--config", cfg, dst]), 0)
            self.assertNotEqual(A.main(["check", "--config", cfg, src]), 0)

    def test_cli_slug_word_of_operator_and_extra_pseudos(self):
        # CodeRabbit on PR #49: the configured pseudos never entered the per-word slug rule (they are not
        # corpus-known names), so the direct CLI, with no known names, left one word of them in a slug.
        import json
        with tempfile.TemporaryDirectory() as d:
            cfg = os.path.join(d, "local.json")
            with open(cfg, "w") as fh:
                json.dump({"pseudos": ["Rhubarbe Tagada"], "extra_pseudos": ["Myrtille Gelee"]}, fh)
            src, dst = os.path.join(d, "in.html"), os.path.join(d, "out.html")
            with open(src, "w", encoding="utf-8") as fh:
                fh.write('<a href="/hfr/A/B/tagada-cours-2018-sujet_1_1.htm">[Rhubarbe Tagada] colo en cours</a>'
                         '<a href="/hfr/A/B/gelee-photos-sujet_2_1.htm">Myrtille Gelee photos</a>')
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(A.main(["--config", cfg, src, dst]), 0)
            with open(dst, encoding="utf-8") as fh:
                out = fh.read()
            self.assertIn('href="/hfr/A/B/user1-cours-2018-sujet_1_1.htm">[user1] colo en cours<', out)
            self.assertIn('href="/hfr/A/B/user2-photos-sujet_2_1.htm">user2 photos<', out)


class PrivateFormCopyTests(unittest.TestCase):
    """Composer and edit-form pages repeat MP text in `content_form` and in the review cell (#401)."""
    SECRET = "Secret words of a real conversation"

    @staticmethod
    def page(subject, text, header=True):
        head = ('<table><tr><th class="padding">Sujet : <h3>%s</h3></th></tr></table>' % subject) if header else ""
        return ('<html><body>%s<form><input type="hidden" name="sujet" value="%s" />'
                '<textarea name="content_form" rows="1">%s</textarea></form>'
                '<table><tr><td class="messCase1bis">user1</td><td class="messCase2"><div>%s<br />more</div></td></tr>'
                '</table></body></html>' % (head, subject, text, text))

    def reasons(self, html):
        return [r for _l, _c, r in leaks(html, private=True)]

    def test_real_thread_composer_leaks_without_the_change_and_is_replaced_with_it(self):
        page = self.page("Real conversation", self.SECRET)
        self.assertIn("private form copy not replaced", self.reasons(page))
        out = anon(page, private=True)
        self.assertNotIn(self.SECRET, out)
        self.assertEqual(out.count(A.PRIVATE_PLACEHOLDER), 2)
        self.assertEqual(self.reasons(out), [])

    def test_fixture_thread_is_left_unchanged_and_not_flagged(self):
        page = self.page("fixture-test-3", self.SECRET)
        self.assertEqual(anon(page, private=True), page)
        self.assertEqual(self.reasons(page), [])

    def test_mixed_names_are_not_a_fixture_thread(self):
        page = self.page("fixture-test-3", self.SECRET).replace("Sujet : <h3>fixture-test-3", "Sujet : <h3>Real")
        self.assertNotIn(self.SECRET, anon(page, private=True))
        self.assertIn("private form copy not replaced", self.reasons(page))

    def test_page_without_thread_name_fails_closed(self):
        page = self.page("x", self.SECRET, header=False).replace('<input type="hidden" name="sujet" value="x" />', "")
        self.assertNotIn(self.SECRET, anon(page, private=True))
        self.assertIn("private form copy not replaced", self.reasons(page))

    def test_quote_attribute_order_and_empty_textarea(self):
        page = self.page("Real", "").replace('type="hidden" name="sujet" value="Real"', 'value="Real" name="sujet"')
        out = anon(page, private=True)
        self.assertIn('<textarea name="content_form" rows="1"></textarea>', out)
        self.assertEqual(self.reasons(out), [])

    QUOTED = ('<table class="citation"><tr class="none"><td><p>quoted</p></td></tr></table><p>TAILSECRET</p>')

    def quote_page(self, author):
        return ('<html><body><input type="hidden" name="sujet" value="Real" /><table><tr><td class="messCase1bis">%s</td>'
                '<td class="messCase2"><div>%s</div></td></tr></table></body></html>' % (author, self.QUOTED))

    def test_quote_table_in_review_cell_is_replaced_to_the_end(self):
        out = anon(self.quote_page("user1"), private=True)
        self.assertNotIn("TAILSECRET", out)
        self.assertNotIn("quoted", out)
        self.assertEqual(self.reasons(out), [])

    def test_dom_verifier_flags_quote_tail_and_markup_author(self):
        for author in ("user1", "<b>user1</b>"):
            found = A.verify_structure(self.quote_page(author), private=True)
            self.assertTrue([f for f in found if "private form copy" in f[2]], author)
            out = anon(self.quote_page(author), private=True)
            self.assertNotIn("TAILSECRET", out)
            self.assertEqual(A.verify_structure(out, private=True), [])

    def test_dom_verifier_skips_fixture_thread(self):
        page = self.quote_page("user1").replace('value="Real"', 'value="fixture-test-2"')
        self.assertEqual(A.verify_structure(page, private=True), [])

    def test_unquoted_sujet_attributes_fail_closed(self):
        page = self.page("fixture-test-3", self.SECRET, header=False).replace(
            'type="hidden" name="sujet" value="fixture-test-3"', 'type=hidden name=sujet value=fixture-test-3')
        self.assertNotIn(self.SECRET, anon(page, private=True))

    def test_not_private_mode_keeps_copies(self):
        page = self.page("Real conversation", self.SECRET)
        self.assertEqual(anon(page), page)


class ApiKeyTests(unittest.TestCase):
    def test_a_real_value_is_found_a_placeholder_is_not(self):
        for text in ("https://api.example/v1?q=a&api_key=abc123", '{"u": "x?api_key%3Dabc123&b=1"}',
                     '{"api_key": "abc123"}'):
            self.assertEqual(len(A.api_key_matches(text)), 1, text)
        for text in ("https://api.example/v1?api_key=REDACTED&q=a", "no key here", "x?api_key=",
                     '{"api_key": "REDACTED"}', '{"api_key": ""}'):
            self.assertEqual(A.api_key_matches(text), [], text)

    def test_findings_refuse_it_on_any_file(self):
        reasons = [f[2] for f in A.Anonymizer(CFG).findings('{"url": "https://h/v1?api_key=abc123"}')]
        self.assertIn("api_key value not replaced", reasons)


if __name__ == "__main__":
    unittest.main()


def thread_page(subject):
    """A thread page and a reply form page printing the thread subject in every header position (live R123b-R123e)."""
    return ('<html><head><title>%(s)s - Messages privés - FORUM HardWare.fr</title></head><body>'
            '<h1 id="md_arbo_tree_2"><img src="/open.gif" alt="" />&nbsp;&nbsp;Messages privés</h1><h1 id="md_arbo_tree_3"><img src="/tline3.gif" alt="" /><img src="/open.gif" alt="" />&nbsp;&nbsp;%(s)s</h1>'
            '<h1 id="md_arbo_tree_b_3"><img src="/open.gif" alt="" />&nbsp;&nbsp;<a href="/f" class="Ext">%(s)s</a></h1>'
            '<table><tr><th scope="col" class="padding">&nbsp;Sujet : <h3>%(s)s</h3></th></tr></table>'
            '<table><tr class="reponse"><th colspan="2">\n\t\tSujet : %(s)s</th></tr></table></body></html>' % {"s": subject})


class ThreadSubjectTests(unittest.TestCase):
    """--private replaces the thread subject in the header positions of thread and form pages, for any subject."""

    def test_any_subject_is_replaced_in_every_position(self):
        for subject in ("Weekend chez Paul", "12345", "fixture-test-group-1", "R&amp;D"):
            out = anon(thread_page(subject), private=True)
            self.assertNotIn(subject, out)
            self.assertEqual(out.count(A.PRIVATE_SUBJECT), 5)
            self.assertEqual(leaks(out, private=True), [])

    def test_kept_subjects_stay(self):
        for subject in ("fixture-test-1", A.MPSTORAGE_SUBJECT):
            page = thread_page(subject)
            self.assertEqual(anon(page, private=True).count(subject), 5)
            self.assertEqual(leaks(page, private=True), [])

    def test_check_flags_each_position_alone(self):
        keep = thread_page(A.PRIVATE_SUBJECT)
        bad = thread_page("Weekend chez Paul")
        positions = [
            ("<title>", "<title>Weekend chez Paul - Messages privés - FORUM HardWare.fr</title>"),
            ("open.gif\" alt=\"\" />&nbsp;&nbsp;%s</h1>" % A.PRIVATE_SUBJECT,
             "open.gif\" alt=\"\" />&nbsp;&nbsp;Weekend chez Paul</h1>"),
            ("class=\"Ext\">%s</a>" % A.PRIVATE_SUBJECT, "class=\"Ext\">Weekend chez Paul</a>"),
            ("<h3>%s</h3>" % A.PRIVATE_SUBJECT, "<h3>Weekend chez Paul</h3>"),
            ("Sujet : %s</th></tr></table></body>" % A.PRIVATE_SUBJECT, "Sujet : Weekend chez Paul</th></tr></table></body>")]
        self.assertEqual(leaks(keep, private=True), [])
        self.assertTrue(any("private" in r for _l, _c, r in leaks(bad, private=True)))
        for clean, dirty in positions:
            if clean.startswith("<title>"):
                page = keep.replace("<title>%s - Messages" % A.PRIVATE_SUBJECT, dirty[:-len("</title>")].replace(
                    " - Messages privés - FORUM HardWare.fr", " - Messages"), 1)
            else:
                self.assertIn(clean, keep)
                page = keep.replace(clean, dirty, 1)
            self.assertNotEqual(page, keep)
            self.assertTrue(any("private" in r for _l, _c, r in leaks(page, private=True)), dirty)


class DestListTests(unittest.TestCase):
    """`dest` holds several recipients separated by commas: each one is aliased on its own."""

    def test_request_body_dest_is_split(self):
        body = "a=1&dest=%s%%2C%s%%2C+%s&sujet=x" % (REAL2, OTHER, "Third One")
        anonymizer = A.Anonymizer(CFG)
        anonymizer._reset()
        out = anonymizer.redact_text(body)
        self.assertEqual(out.split("&")[1].count("%2C"), 2)
        self.assertTrue(out.split("&")[1].startswith("dest=user2%2C"))
        for real in (REAL2, OTHER, "Third One"):
            self.assertNotIn(real, out)
        self.assertEqual(leaks(out), [])

    def test_dest_input_and_link_with_commas(self):
        page = ('<input name="dest" value="%s, %s" />' % (REAL1, OTHER))
        out = anon(page)
        self.assertRegex(out, r'value="user1, user\d+"')
        self.assertNotIn(OTHER, out)
        self.assertEqual(leaks(out), [])
        self.assertTrue(leaks(page))


class RequestSubjectTests(unittest.TestCase):
    def test_body_subject_replaced_unless_kept(self):
        self.assertEqual(A.private_request_subject("a=1&sujet=Weekend+chez+Paul&b=2"), "a=1&sujet=Private+subject&b=2")
        self.assertEqual(A.private_request_subject("sujet=fixture-test-1&b=2"), "sujet=fixture-test-1&b=2")
        self.assertEqual(A.private_request_subject("a=1&sujet=fixture-test-group-1"), "a=1&sujet=Private+subject")
        self.assertEqual(A.private_request_subject("a=1&xsujet=Weekend"), "a=1&xsujet=Weekend")


class SubjectPositionTests(unittest.TestCase):
    """Isolated positions: the `sujet` input, an h1 with another icon, the meta request body, `cat=prive` pages."""
    SUBJECTS = ("Weekend chez Marie", "98765", "R&amp;D d'été", 'a "b" c')

    def test_sujet_input_shapes_are_replaced(self):
        for subject in self.SUBJECTS:
            for page in ('<input type="hidden" name="sujet" value="%s" />' % subject.replace('"', "&quot;"),
                         '<input value="%s" name="sujet" type="text" />' % subject.replace('"', "&quot;"),
                         "<input type='hidden' name='sujet' value='%s' />" % subject.replace("'", "&#039;")):
                out = anon(page, private=True)
                self.assertIn(A.PRIVATE_SUBJECT, out, page)
                self.assertEqual(leaks(out, private=True), [], page)
                self.assertTrue(any("subject" in r for _l, _c, r in leaks(page, private=True)), page)

    def test_sujet_input_kept_or_empty(self):
        for value in ("", A.PRIVATE_SUBJECT, "fixture-test-3", A.MPSTORAGE_SUBJECT):
            page = '<input type="hidden" name="sujet" value="%s" />' % value
            self.assertEqual(leaks(page, private=True), [], value)
            self.assertEqual(anon(page, private=True), page)

    def test_h1_without_open_icon_is_checked_and_replaced(self):
        page = ('<h1 id="md_arbo_tree_3"><img src="/other.gif" alt="" />&nbsp;&nbsp;Weekend chez Marie</h1>'
                '<h1 id="md_arbo_tree_b_3">Weekend chez Marie</h1>')
        self.assertTrue(any("subject" in r for _l, _c, r in leaks(page, private=True)))
        out = anon(page, private=True)
        self.assertNotIn("Marie", out)
        self.assertEqual(leaks(out, private=True), [])

    def test_meta_request_body_subject_is_checked(self):
        import json
        meta = {"url": "https://forum.hardware.fr/bddpost.php?config=hfr.inc", "private": False,
                "request_body": "cat=prive&sujet=Weekend+chez+Marie&dest=user2"}
        self.assertTrue(any("subject" in r for _l, _c, r in leaks(json.dumps(meta, indent=2))))
        meta["request_body"] = "cat=prive&sujet=Private+subject&dest=user2"
        self.assertEqual(leaks(json.dumps(meta, indent=2)), [])
        meta["request_body"] = "cat=13&sujet=Public+topic+title"  # a public topic's title is public
        self.assertEqual(leaks(json.dumps(meta, indent=2)), [])

    def test_cat_prive_url_makes_a_capture_private_whatever_the_flag(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            page = ('<html><head><title>Weekend chez Marie - Messages privés - FORUM HardWare.fr</title></head>'
                    '<body><div id="para1"><p>secret</p></div></body></html>')
            with open(os.path.join(d, "X-a.html"), "w", encoding="utf-8") as fh:
                fh.write(page)
            with open(os.path.join(d, "X.meta.json"), "w", encoding="utf-8") as fh:
                json.dump({"id": "X", "file": "X-a.html", "private": False,
                           "url": "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=1"}, fh)
            self.assertEqual([p for _f, p, _a in A.corpus_entries(d) if _f.endswith(".html")], [True])
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(A.main(["check", "--corpus", d]), 1)


class MPWriteSignalTests(unittest.TestCase):
    REPLAY = ('<div class="hop"><form><input type="hidden" name="cat" value="prive" />'
              '<input type="hidden" name="sujet" value="Weekend chez Marie" />'
              '<textarea name="content_form">words of Marie</textarea></form></div>')

    def test_page_with_hidden_cat_prive_is_private_whatever_the_flag(self):
        out = anon(self.REPLAY)  # private=False
        self.assertNotIn("Marie", out)
        self.assertIn(A.PRIVATE_SUBJECT, out)
        self.assertIn(A.PRIVATE_PLACEHOLDER, out)
        self.assertEqual(leaks(out), [])
        reasons = [r for _l, _c, r in leaks(self.REPLAY)]  # the verifier derives it from the page too
        self.assertTrue(any("subject" in r for r in reasons), reasons)
        self.assertTrue(any("private form copy" in r for r in reasons), reasons)

    def test_page_without_cat_prive_is_not_private(self):
        public = self.REPLAY.replace('value="prive"', 'value="13"')
        self.assertIn("Marie", anon(public))
        self.assertEqual(leaks(public), [])

    def test_mp_body_signals(self):
        for body in ("cat=prive&x=1", "CAT=Prive", "a=1&dest=Bravo", "Dest=a%2Cb"):
            self.assertTrue(A.body_is_mp(body), body)
            self.assertTrue(A.meta_is_private({"request_body": body}), body)
        for body in ("cat=13&sujet=x", "pseudo=a", "", None):
            self.assertFalse(A.body_is_mp(body), body)

    def test_meta_subject_checked_for_dest_only_and_mixed_case_body(self):
        import json
        for body in ("dest=user2&sujet=Weekend+chez+Marie", "CAT=Prive&Sujet=Weekend+chez+Marie"):
            meta = {"url": "https://forum.hardware.fr/bddpost.php?config=hfr.inc", "private": False,
                    "request_body": body}
            self.assertTrue(any("subject" in r for _l, _c, r in leaks(json.dumps(meta, indent=2))), body)

    def test_committed_style_mp_meta_is_classed_private_in_a_corpus(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "X-a.html"), "w", encoding="utf-8") as fh:
                fh.write("<html></html>")
            with open(os.path.join(d, "X.meta.json"), "w", encoding="utf-8") as fh:
                json.dump({"id": "X", "file": "X-a.html", "private": False,
                           "url": "https://forum.hardware.fr/bddpost.php?config=hfr.inc",
                           "request_body": "cat=prive&sujet=fixture-test-1"}, fh)
            self.assertEqual([p for f, p, _a in A.corpus_entries(d) if f.endswith(".html")], [True])


class NewDestTests(unittest.TestCase):
    """`newdest` (the owner's recipient list of a group MP reply form) is a recipient position, comma-separated."""

    def test_input_url_and_body_are_aliased_for_unconfigured_names(self):
        page = ('<input size="25" name="newdest" value="%s, %s" id="newdest" />'
                '<a href="/x?newdest=%s%%2C%s&amp;a=1">l</a>' % (OTHER, "Thirdy", OTHER, "Thirdy"))
        out = anon(page)
        for real in (OTHER, "Thirdy"):
            self.assertNotIn(real, out)
        self.assertRegex(out, r'value="user\d+, user\d+"')
        self.assertEqual(leaks(out), [])
        reasons = [r for _l, _c, r in leaks(page)]
        self.assertTrue(reasons, "the verifier must see an un-aliased newdest")

    def test_body_with_newdest_is_an_mp_write(self):
        self.assertTrue(A.body_is_mp("newdest=a%2Cb&x=1"))

    def test_request_body_message_text(self):
        import json
        real = "cat=prive&sujet=Weekend+chez+Marie&content_form=words+of+Marie&dest=a"
        out = A.private_request_body(real)
        self.assertNotIn("Marie", out)
        self.assertIn("content_form=Private+message+content+removed.", out)
        kept = "cat=prive&sujet=fixture-test-1&content_form=fixture-test+1%2C+text"
        self.assertEqual(A.private_request_body(kept), kept)
        public = "cat=13&sujet=Public+title&content_form=public+words"
        self.assertEqual(A.private_request_body(public), public)
        for body, bad in ((real, True), (out, False), (kept, False), ("cat=prive&sujet=Private+subject&content_form=neutral", True),
                          ("CAT=prive&SUJET=Weekend&Content_Form=x", True)):
            meta = {"url": "https://forum.hardware.fr/bddpost.php?config=hfr.inc", "request_body": body}
            found = [r for _l, _c, r in leaks(json.dumps(meta, indent=2)) if "message text" in r]
            self.assertEqual(bool(found), bad, body)
