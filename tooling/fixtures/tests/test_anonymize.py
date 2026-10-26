"""Tests for anonymize.py. All HTML here is synthetic: no real pseudo, cookie or token."""
import contextlib
import io
import os
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
        html = ('<a class="cCatTopic" href="/a">Weekend chez Paul</a><a class="cCatTopic" href="/b">fixture-test-1</a>'
                '<a class="cCatTopic" href="/c">a2bcc09b796b8c6fab77058ff8446c34</a><a class="cCatTopic" href="/d">12</a>')
        self.assertTrue(leaks(html, private=True))
        self.assertFalse(leaks(html))  # public topic titles are not private
        out = anon(html, private=True)
        self.assertNotIn("Paul", out)
        for kept in ("fixture-test-1", "a2bcc09b796b8c6fab77058ff8446c34", ">12<", ">Private subject<"):
            self.assertIn(kept, out)
        self.assertEqual(leaks(out, private=True), [])

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

    def test_quotemsg_third_value_uses_the_id_table(self):
        html = ('<a href="/hfr/profil-555123.htm">x</a><a href="/hfr/profil-555124.htm">y</a>'
                '<textarea name="content_form">[quotemsg=99,1,555124]q[/quotemsg]</textarea>'
                '<img src="https://forum-images.hardware.fr/images/mesdiscussions-555124.jpg" alt="" />')
        out = self.check_page(html, "555123", "555124")
        self.assertIn("[quotemsg=99,1,910002]", out)
        self.assertIn("profil-910002.htm", out)
        self.assertIn("mesdiscussions-910002.jpg", out)

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


if __name__ == "__main__":
    unittest.main()
