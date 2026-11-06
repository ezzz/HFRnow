"""Aliased list rows (`owntopic=1|2|3` or a flag cell): one test per aliased position, synthetic rows only.

Each position is checked on both layers on its own:
- the anonymizer replaces the real value there (and the output passes `verify_followed_lists`);
- the independent verifier reports the position when only that value is put back in the anonymized page.
A second group covers the general rule: no alias in a member position next to a real id.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402

TOPIC, MSG, CAT, SUBCAT = "4242", "5555555", "7", "321"
LAST, READ, REPLIES, VIEWS = "777", "333", "8888", "999999"
DATE, HOUR, TITLE = "15-03-2024", "12:34", "Secret Title Qzwx"
TAIL = "&amp;p=1&amp;sondage=0&amp;owntopic=1&amp;trash=0&amp;trash_post=0&amp;print=0&amp;quote_only=0&amp;new=0&amp;nojs=0"


def url(page="1", numreponse="0", cat=CAT, subcat=SUBCAT, post=TOPIC, extra=""):
    return ("/forum2.php?config=hfr.inc&amp;cat=%s&amp;subcat=%s&amp;post=%s&amp;page=%s&amp;numreponse=%s%s%s"
            % (cat, subcat, post, page, numreponse, extra, TAIL))


def header(cat=CAT, name="Hardware"):
    return ('<tr class="cBackHeader fondForum1fCat" ondblclick="location.href=\'/forum1.php?config=hfr.inc&amp;cat=%s'
            '&amp;page=1&amp;owntopic=1\'"><th class="padding" colspan="10"><a href="#1" onclick="x(\'/user/suppressflag.php'
            '?id_user=900001&amp;config=hfr.inc&amp;owntopic=1&amp;cat=%s&amp;codehex=REDACTED\')"><img src="https://forum-images.hardware.fr/x/a.gif" /></a>'
            '<a href="/forum1.php?config=hfr.inc&amp;cat=%s&amp;page=1&amp;owntopic=1" class="cHeader">%s</a></th></tr>'
            % (cat, cat, cat, name))


def row(owntopic="1", **kw):
    tail = TAIL.replace("owntopic=1", "owntopic=" + owntopic)
    u = url(**kw).replace(TAIL, tail)
    return (
        '<tr class="sujet ligne_booleen cBackCouleurTab1 " >'
        '<td class="sujetCase1"><img src="https://forum-images.hardware.fr/x/closedb_new.gif" title="Nouveau message" alt="On" /></td>'
        '<td class="sujetCase2"><img src="https://forum-images.hardware.fr/x/icon2.gif" alt="" /></td>'
        '<td scope="row" class="sujetCase3" ondblclick="location.href=\'%s\'">'
        '<a href="%s" class="cCatTopic" title="Sujet n°%s">%s</a></td>'
        '<td class="sujetCase4"><a href="%s" class="cCatTopic">%s</a></td>'
        '<td class="sujetCase5"><a href="%s#t%s"><img src="https://forum-images.hardware.fr/x/flag1.gif" title="Aller au dernier message lu sur ce '
        'sujet (p.%s)" alt="flag" /></a></td>'
        '<td class="sujetCase6"><a rel="nofollow" href="/profilebdd.php?config=hfr.inc&amp;pseudo=user3" class="Tableau">'
        'user3</a></td><td class="sujetCase7">%s</td><td class="sujetCase8">%s</td>'
        '<td class="sujetCase9"><a href="%s#bas" class="Tableau">%s&nbsp;à&nbsp;%s<br /><b>user4</b></a></td>'
        '<td class="sujetCase10"><input type="checkbox" name="topic0"  value="%s" />'
        '<input type="hidden" name="valuecat0" value="%s" /><input type="hidden" name="valueforum0" value="hardwarefr" />'
        '</td></tr>' % (
            url(page="1").replace(TAIL, tail), url(page="1").replace(TAIL, tail), TOPIC, TITLE,
            url(page=LAST).replace(TAIL, tail), LAST,
            url(page=READ).replace(TAIL, tail), MSG, READ, REPLIES, VIEWS,
            u.replace("page=1", "page=" + LAST), DATE, HOUR, TOPIC, CAT))


def page(*parts):
    return ('<html><body><table class="main"><form name="form1">' + "".join(parts) + "</form></table></body></html>")


def anonymize(text):
    return A.Anonymizer(A.Config()).anonymize(text)


def labels(text):
    return {reason for _l, _c, reason in A.verify_followed_lists(text)}


T1, M1 = str(A.FOLLOWED_TOPIC_FIRST), str(A.FOLLOWED_MESSAGE_FIRST)
CAT1, SUB1 = str(A.FOLLOWED_CAT_FIRST), str(A.FOLLOWED_SUBCAT_FIRST)
DAY, HOUR1 = A.followed_date(1)
LAST1, READ1 = str(A.FOLLOWED_LAST_PAGE_BASE + 1), str(A.FOLLOWED_READ_PAGE_BASE + 1)
REPLIES1, VIEWS1 = str(A.FOLLOWED_REPLIES_BASE + 1), str(A.FOLLOWED_VIEWS_BASE + 1)


class Followed(unittest.TestCase):
    def setUp(self):
        self.raw = page(header(), row())
        self.out = anonymize(self.raw)

    def test_clean_output_passes_and_hides_every_real_value(self):
        self.assertEqual(labels(self.out), set())
        for real in (TOPIC, MSG, SUBCAT, LAST, READ, REPLIES, VIEWS, DATE, HOUR, "Qzwx", "Hardware", "cat=" + CAT + "&"):
            self.assertNotIn(real, self.out)

    def test_alias_forms(self):
        for kept in ("post=" + T1, "n°" + T1, "#t" + M1, "subcat=" + SUB1, "cat=" + CAT1, "Followed topic 1",
                     "Category 1", "(p.%s)" % READ1, '"sujetCase7">' + REPLIES1, '"sujetCase8">' + VIEWS1,
                     DAY + "&nbsp;à&nbsp;" + HOUR1, 'name="topic0"  value="%s"' % T1, 'value="%s" /><input type="hidden" '
                     'name="valueforum0"' % CAT1, "page=1&amp;", "numreponse=0", "flag1.gif", "icon2.gif"):
            self.assertIn(kept, self.out, kept)

    def test_dates_and_ids_differ_per_row(self):
        out = anonymize(page(header(), row(), row()))
        self.assertEqual(labels(out), set())
        self.assertIn("post=%d&" % (A.FOLLOWED_TOPIC_FIRST + 1), out)
        self.assertEqual(len(set(A.followed_date(i) for i in range(1, 200))), 199)

    # (test id, text to find in the anonymized page, real text put back, finding)
    POSITIONS = (
        ("topic_in_title_link", 'cCatTopic" title="Sujet n°%s"' % T1, None, "link parameter post"),
        ("topic_in_dblclick", "ondblclick=\"location.href='/forum2.php?config=hfr.inc&amp;cat=%s&amp;subcat=%s&amp;post=%s"
         % (CAT1, SUB1, T1), "ondblclick=\"location.href='/forum2.php?config=hfr.inc&amp;cat=%s&amp;subcat=%s&amp;post=%s"
         % (CAT1, SUB1, TOPIC), "link parameter post"),
        ("topic_number_title", "Sujet n°" + T1, "Sujet n°" + TOPIC, "topic number"),
        ("title_text", "Followed topic 1", TITLE, "title"),
        ("checkbox_value", 'name="topic0"  value="%s"' % T1, 'name="topic0"  value="%s"' % TOPIC, "form value"),
        ("message_fragment", "#t" + M1, "#t" + MSG, "message id"),
        ("cat_in_row", "ondblclick=\"location.href='/forum2.php?config=hfr.inc&amp;cat=" + CAT1,
         "ondblclick=\"location.href='/forum2.php?config=hfr.inc&amp;cat=" + CAT, "link parameter cat"),
        ("valuecat", 'name="valuecat0" value="%s"' % CAT1, 'name="valuecat0" value="%s"' % CAT, "form value"),
        ("subcat", "subcat=" + SUB1 + "&amp;post=" + T1 + "&amp;page=1&amp;numreponse=0&amp;p=1&amp;sondage=0&amp;owntopic=1"
         "&amp;trash=0&amp;trash_post=0&amp;print=0&amp;quote_only=0&amp;new=0&amp;nojs=0'\"",
         "subcat=" + SUBCAT + "&amp;post=" + T1 + "&amp;page=1&amp;numreponse=0&amp;p=1&amp;sondage=0&amp;owntopic=1"
         "&amp;trash=0&amp;trash_post=0&amp;print=0&amp;quote_only=0&amp;new=0&amp;nojs=0'\"", "link parameter subcat"),
        ("last_page_text", ">%s</a></td>" % LAST1, ">%s</a></td>" % LAST, "number"),
        ("last_page_param", "page=" + LAST1 + "&amp;numreponse=0&amp;p=1&amp;sondage=0&amp;owntopic=1&amp;trash=0&amp;trash_post=0"
         "&amp;print=0&amp;quote_only=0&amp;new=0&amp;nojs=0\" class=\"cCatTopic\">",
         "page=" + LAST + "&amp;numreponse=0&amp;p=1&amp;sondage=0&amp;owntopic=1&amp;trash=0&amp;trash_post=0"
         "&amp;print=0&amp;quote_only=0&amp;new=0&amp;nojs=0\" class=\"cCatTopic\">", "link parameter page"),
        ("read_page_param", "page=" + READ1 + "&amp;numreponse=0", "page=" + READ + "&amp;numreponse=0",
         "link parameter page"),
        ("read_page_title", "(p.%s)" % READ1, "(p.%s)" % READ, "read page"),
        ("replies", '"sujetCase7">' + REPLIES1, '"sujetCase7">' + REPLIES, "number"),
        ("views", '"sujetCase8">' + VIEWS1, '"sujetCase8">' + VIEWS, "number"),
        ("date", DAY + "&nbsp;à&nbsp;" + HOUR1, DATE + "&nbsp;à&nbsp;" + HOUR, "date"),
        ("date_hour_only", DAY + "&nbsp;à&nbsp;" + HOUR1, DAY + "&nbsp;à&nbsp;" + HOUR, "date"),
        ("header_cat_link", "forum1.php?config=hfr.inc&amp;cat=%s&amp;page=1&amp;owntopic=1\" class=\"cHeader\"" % CAT1,
         "forum1.php?config=hfr.inc&amp;cat=%s&amp;page=1&amp;owntopic=1\" class=\"cHeader\"" % CAT,
         "link parameter cat"),
        ("header_suppressflag_cat", "owntopic=1&amp;cat=%s&amp;codehex" % CAT1, "owntopic=1&amp;cat=%s&amp;codehex" % CAT,
         "link parameter cat"),
    )

    def test_each_position_is_aliased_and_checked_on_its_own(self):
        for name, aliased, real, finding in self.POSITIONS:
            with self.subTest(name):
                self.assertIn(aliased, self.out)
                if real is None:
                    continue
                broken = self.out.replace(aliased, real, 1)
                self.assertNotEqual(broken, self.out)
                found = labels(broken)
                self.assertIn("list-row check: %s not aliased" % finding, found, found)

    def test_title_with_a_real_number_is_reported(self):
        broken = self.out.replace("Followed topic 1", "Followed topic 99")
        self.assertIn("list-row check: title not aliased", labels(broken))

    def test_unknown_parameter_with_a_number_is_reported(self):
        broken = self.out.replace("&amp;nojs=0", "&amp;extra=42&amp;nojs=0", 1)
        self.assertIn("list-row check: link parameter extra not aliased", labels(broken))

    def test_ref_parameter_is_aliased(self):
        raw = page(header(), row()).replace("numreponse=0", "numreponse=0&amp;ref=9876")
        out = anonymize(raw)
        self.assertNotIn("9876", out)
        self.assertEqual(labels(out), set())

    def test_category_header_names_are_numbered_in_order(self):
        out = anonymize(page(header("7", "Hardware"), row(), header("9", "Emploi"), row(cat="9", subcat="654")))
        self.assertEqual(labels(out), set())
        self.assertIn(">Category 1<", out)
        self.assertIn(">Category 2<", out)
        self.assertNotIn("Emploi", out)
        self.assertIn("cat=%d&amp;" % (A.FOLLOWED_CAT_FIRST + 1), out)

    def test_row_id_scope_is_per_row(self):
        out = anonymize(page(header(), row(), row(post="4243")))
        self.assertIn("post=%d&" % (A.FOLLOWED_TOPIC_FIRST + 1), out)
        self.assertNotIn("4243", out)
        # a row's aliases in another row's position are reported
        broken = out.replace("post=%d&" % (A.FOLLOWED_TOPIC_FIRST + 1), "post=%d&" % A.FOLLOWED_TOPIC_FIRST, 1)
        self.assertIn("list-row check: link parameter post not aliased", labels(broken))

    def test_single_category_page_keeps_the_browsed_category_only(self):
        out = anonymize(page(row(), row(post="4243", subcat="654")))
        self.assertEqual(labels(out), set())
        self.assertIn("cat=%s&amp;" % CAT, out)
        self.assertNotIn("subcat=" + SUBCAT, out)
        mixed = out.replace("cat=%s&amp;" % CAT, "cat=8&amp;", 1)
        self.assertIn("list-row check: several real categories on a page without category headers", labels(mixed))

    def test_owntopic_two_and_three_are_followed_lists_too(self):
        for n in ("2", "3"):
            out = anonymize(page(row(owntopic=n)))
            self.assertNotIn(TOPIC, out)
            self.assertEqual(labels(out), set())

    def test_a_page_without_owntopic_rows_or_flags_is_untouched(self):
        raw = page(row(owntopic="0"))
        raw = raw[:raw.index('<td class="sujetCase5">')] + '<td class="sujetCase5">&nbsp;</td>' + raw[
            raw.index("</td>", raw.index('<td class="sujetCase5">')) + 5:]
        self.assertEqual(anonymize(raw).count(TOPIC), raw.count(TOPIC))
        self.assertEqual(labels(raw), set())

    def test_real_page_is_refused(self):
        self.assertTrue(labels(self.raw))

    def test_read_page_one_stays_consistent_with_its_link(self):
        raw = page(header(), row()).replace("page=%s&amp;numreponse=0" % READ, "page=1&amp;numreponse=0").replace(
            "(p.%s)" % READ, "(p.1)")
        out = anonymize(raw)
        self.assertIn("(p.1)", out)
        self.assertEqual(labels(out), set())

    def test_zero_counts_and_empty_cells_keep_their_shape(self):
        raw = page(header(), row()).replace('"sujetCase7">' + REPLIES, '"sujetCase7">0').replace(
            '<td class="sujetCase4"><a href="%s" class="cCatTopic">%s</a></td>' % (
                url(page=LAST).replace(TAIL, TAIL), LAST), '<td class="sujetCase4">&nbsp;</td>')
        out = anonymize(raw)
        self.assertIn('"sujetCase7">0<', out)
        self.assertIn('<td class="sujetCase4">&nbsp;</td>', out)
        self.assertEqual(labels(out), set())


def rewritten_row(flag=True, post=TOPIC, extra_tr=""):
    """A list row in the rewritten link form (no `owntopic=`, no `post=`), flagged or not."""
    base = "/hfr/cat/Sub/secret-title-qzwx-sujet_%s_%%s.htm" % post
    flag_cell = ('<a href="%s#t%s"><img src="https://forum-images.hardware.fr/x/favoris.gif" title="Aller au dernier '
                 'message lu sur ce sujet (p.%s)" alt="flag" /></a>' % (base % READ, MSG, READ)) if flag else "&nbsp;"
    return (
        '<tr class="sujet ligne_booleen cBackCouleurTab1 "%s><td class="sujetCase1"><img src="https://forum-images.'
        'hardware.fr/x/closedb_new.gif" title="Nouveau message" alt="On" /></td><td class="sujetCase2"></td>'
        '<td scope="row" class="sujetCase3" ondblclick="location.href=\'%s\'"><a href="%s" class="cCatTopic" '
        'title="Sujet n°%s">%s</a></td><td class="sujetCase4"><a href="%s" class="cCatTopic">%s</a></td>'
        '<td class="sujetCase5">%s</td><td class="sujetCase6"><a href="/profilebdd.php?config=hfr.inc&amp;pseudo=user3" '
        'class="Tableau">user3</a></td><td class="sujetCase7">%s</td><td class="sujetCase8">%s</td>'
        '<td class="sujetCase9"><a href="%s#bas" class="Tableau">%s&nbsp;à&nbsp;%s<br /><b>user4</b></a></td></tr>'
        % (extra_tr, base % 1, base % 1, post, TITLE, base % LAST, LAST, flag_cell, REPLIES, VIEWS, base % LAST, DATE,
           HOUR))


class RewrittenRows(unittest.TestCase):
    def test_a_flagged_row_in_rewritten_links_is_aliased_slug_included(self):
        out = anonymize(page(rewritten_row()))
        self.assertEqual(labels(out), set())
        for real in (TOPIC, MSG, "secret", "Qzwx", "Sub", LAST, READ, REPLIES, VIEWS, DATE):
            self.assertNotIn(real, out)
        self.assertIn("/hfr/cat/subcategory-1/followed-topic-1-sujet_%s_1.htm" % T1, out)
        self.assertIn("sujet_%s_%s.htm#t%s" % (T1, READ1, M1), out)

    def test_an_unflagged_row_in_rewritten_links_is_untouched(self):
        raw = page(rewritten_row(flag=False))
        self.assertEqual(anonymize(raw).count(TOPIC), raw.count(TOPIC))
        self.assertEqual(labels(raw), set())

    def test_one_flagged_row_makes_every_row_of_the_page_aliased(self):
        raw = page(rewritten_row(flag=False, post="4243"), rewritten_row(), rewritten_row(flag=False, post="4244"))
        out = anonymize(raw)
        self.assertEqual(labels(out), set())
        for real in ("4243", "4244", TOPIC):
            self.assertNotIn(real, out)
        for i in (1, 2, 3):
            self.assertIn("followed-topic-%d-sujet_%d_" % (i, A.FOLLOWED_TOPIC_FIRST + i - 1), out)

    def test_the_verifier_rejects_a_real_row_beside_aliased_ones(self):
        out = anonymize(page(rewritten_row(), rewritten_row(post="4243")))
        real_row = rewritten_row(flag=False, post="4243")
        broken = out[:out.rindex("<tr ")] + real_row + out[out.rindex("</tr>") + 5:]
        self.assertTrue(labels(broken))

    def test_a_flag_image_without_a_link_is_a_flagged_row(self):
        raw = page(rewritten_row(flag=False)).replace(
            '<td class="sujetCase5">&nbsp;</td>',
            '<td class="sujetCase5"><img src="https://forum-images.hardware.fr/x/flag0.gif" alt="flag" /></td>')
        self.assertTrue(labels(raw))
        out = anonymize(raw)
        self.assertNotIn(TOPIC, out)
        self.assertEqual(labels(out), set())

    def test_the_verifier_reports_each_position_of_a_rewritten_row(self):
        out = anonymize(page(rewritten_row()))
        for name, aliased, real, finding in (
            ("topic_in_path", "sujet_%s_1.htm\'" % T1, "sujet_%s_1.htm\'" % TOPIC, "topic id in path"),
            ("slug", "followed-topic-1-sujet_%s_1.htm\'" % T1, "secret-sujet_%s_1.htm\'" % T1, "slug"),
            ("subcategory", "/subcategory-1/", "/Sub/", "sub-category path"),
            ("page_in_path", "sujet_%s_%s.htm#bas" % (T1, LAST1), "sujet_%s_%s.htm#bas" % (T1, LAST), "page in path"),
        ):
            with self.subTest(name):
                self.assertIn(aliased, out)
                self.assertIn("list-row check: %s not aliased" % finding, labels(out.replace(aliased, real, 1)))

    def test_flag_cell_is_enough_for_the_verifier_to_vouch_a_row(self):
        self.assertTrue(labels(page(rewritten_row())))


class VerifierAttributes(unittest.TestCase):
    def setUp(self):
        self.out = anonymize(page(header(), row()))

    def reported(self, broken):
        return labels(broken)

    def test_tr_attributes_are_carriers(self):
        broken = self.out.replace('<tr class="sujet ligne_booleen cBackCouleurTab1 " >',
                                  '<tr class="sujet ligne_booleen cBackCouleurTab1 " id="t%s" >' % TOPIC, 1)
        self.assertNotEqual(broken, self.out)
        self.assertIn("list-row check: number not aliased", self.reported(broken))

    def test_header_ondblclick_cat_is_checked(self):
        broken = self.out.replace("forum1.php?config=hfr.inc&amp;cat=%s&amp;page=1&amp;owntopic=1'" % CAT1,
                                  "forum1.php?config=hfr.inc&amp;cat=%s&amp;page=1&amp;owntopic=1'" % CAT, 1)
        self.assertNotEqual(broken, self.out)
        self.assertIn("list-row check: link parameter cat not aliased", self.reported(broken))

    def test_digits_in_any_attribute_are_reported(self):
        broken = self.out.replace('<td class="sujetCase7">', '<td class="sujetCase7" data-x="4711">', 1)
        self.assertIn("list-row check: number not aliased", self.reported(broken))

    def test_title_must_fit_a_known_form(self):
        broken = self.out.replace('title="Nouveau message"', 'title="Secret words"', 1)
        self.assertIn("list-row check: title attribute not aliased", self.reported(broken))

    def test_alt_comes_from_a_whitelist(self):
        broken = self.out.replace('alt="On"', 'alt="Secret words"', 1)
        self.assertIn("list-row check: alt text not aliased", self.reported(broken))

    def test_row_links_go_to_known_pages_only(self):
        broken = self.out.replace('<a rel="nofollow" href="/profilebdd.php?config=hfr.inc&amp;pseudo=user3"',
                                  '<a rel="nofollow" href="/other.php?config=hfr.inc&amp;pseudo=user3"', 1)
        self.assertNotEqual(broken, self.out)
        self.assertIn("list-row check: link form not aliased", self.reported(broken))

    def test_images_come_from_the_forum_image_host(self):
        broken = self.out.replace("https://forum-images.hardware.fr/x/closedb_new.gif", "https://example.org/a1.gif", 1)
        self.assertIn("list-row check: image link not aliased", self.reported(broken))


def member_row(topic, author, cat=CAT, last="user4"):
    return (
        '<tr class="sujet"><td class="sujetCase3"><a href="/forum2.php?config=hfr.inc&amp;cat=%s&amp;post=%s&amp;page=1" '
        'class="cCatTopic">t</a></td><td class="sujetCase6"><a href="/profilebdd.php?config=hfr.inc&amp;pseudo=%s" '
        'class="Tableau">%s</a></td><td class="sujetCase9"><a href="/x#bas">x<br /><b>%s</b></a></td></tr>'
        % (cat, topic, author, author, last))


class OperatorMembers(unittest.TestCase):
    def found(self, text, account="user2"):
        return [r for _l, _c, r in A.verify_operator_members(text, account)]

    def test_author_alias_next_to_a_real_topic_is_reported(self):
        self.assertEqual(self.found(page(member_row("4242", "user2"))),
                         ["alias in a member position next to a real id"])
        self.assertEqual(len(self.found(page(member_row("4242", "user1")))), 1)

    def test_last_poster_position_alone(self):
        self.assertEqual(len(self.found(page(member_row("4242", "user5", last="user1")))), 1)

    def test_zero_width_and_case_do_not_hide_an_alias(self):
        self.assertEqual(len(self.found(page(member_row("4242", "Us\u200ber2")))), 1)
        self.assertEqual(A.pseudo_key("Us\u200ber-2 "), "user2")

    def test_other_member_aliases_are_fine(self):
        self.assertEqual(self.found(page(member_row("4242", "user3"))), [])

    def test_fake_topic_ids_are_fine(self):
        self.assertEqual(self.found(page(member_row(str(A.FOLLOWED_TOPIC_FIRST), "user2"))), [])
        self.assertEqual(self.found(page(member_row("9900001", "user2"))), [])

    def test_rewritten_link_form_counts_as_a_real_id(self):
        row_text = ('<tr class="sujet"><td class="sujetCase3"><a href="/hfr/cat/slug-sujet_4242_1.htm" class="cCatTopic">t'
                    '</a></td><td class="sujetCase6"><a href="/profilebdd.php?config=hfr.inc&amp;pseudo=user2">user2</a>'
                    '</td></tr>')
        self.assertEqual(len(self.found(page(row_text))), 1)

    def test_a_row_is_exempt_only_if_all_its_links_are_private(self):
        mixed = member_row("3207033", "user2", cat="prive").replace(
            "</td><td class=\"sujetCase6\">",
            "</td><td class=\"sujetCase4\"><a href=\"/forum2.php?config=hfr.inc&amp;cat=13&amp;post=4242\">2</a></td>"
            "<td class=\"sujetCase6\">", 1)
        self.assertEqual(len(self.found(page(mixed))), 1)

    def test_private_threads_are_exempt(self):
        self.assertEqual(self.found(page(member_row("3207033", "user2", cat="prive"))), [])

    def test_only_operator_labelled_pages_are_checked(self):
        for account in ("anon", None, ""):
            self.assertEqual(self.found(page(member_row("4242", "user2")), account), [])
        self.assertEqual(len(self.found(page(member_row("4242", "user2")), "user1|user2")), 1)

    def test_findings_reach_the_public_check(self):
        text = page(member_row("4242", "user2"))
        anon = A.Anonymizer(A.Config())
        self.assertTrue(any("alias in a member" in r for _l, _c, r in anon.findings(text, account="user2")))
        self.assertFalse(any("alias in a member" in r for _l, _c, r in anon.findings(text)))


if __name__ == "__main__":
    unittest.main()
