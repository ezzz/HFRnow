"""One test per member position: the page holds the name in that position only (synthetic names).

Each test checks both layers on its own:
- the independent verifier reports the raw page under that position's label;
- the anonymizer replaces the name and its output passes every check.
So dropping one DISCOVER entry or one verifier rule fails exactly the tests of that position.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import anonymize as A  # noqa: E402

N = "Wxyz Qrst"  # a synthetic two-word pseudo
# (test id, verifier label, page, values that must disappear, text the output must contain)
CASES = (
    ("post_author", "post author",
     '<td class="messCase1" width="180"><div><b class="s2">%s</b></div></td>' % N, [N], ['class="s2">user1<']),
    ("quote_header", "quote header",
     '<table class="citation"><tr><td><b class="s1"><a href="/forum2.php?config=hfr.inc&amp;post=1#t2" '
     'class="Topic">%s a écrit :</a></b><br /><p>q</p></td></tr></table>' % N, [N], [">user1 a écrit :<"]),
    ("edit_notice", "edit notice",
     '<div class="edited"><br />Message édité par %s le 11-11-2018&nbsp;à&nbsp;18:24:51</div>' % N, [N],
     ["édité par user1 le"]),
    ("param_pseudo_raw_space", "URL parameter pseudo=",
     '<a href="/profilebdd.php?config=hfr.inc&amp;pseudo=%s">profil</a>' % N, [N, "Qrst"], ['pseudo=user1"']),
    ("param_pseudo_inner_apostrophe", "URL parameter pseudo=",
     '<a href="/profilebdd.php?config=hfr.inc&amp;pseudo=l\'Wxyz Qrst&amp;x=1">profil</a>', ["Wxyz", "Qrst"],
     ['pseudo=user1&amp;x=1"']),
    ("param_pseudo_js_string", "URL parameter pseudo=",
     '<a href="#" onclick="window.open(\'/profilebdd.php?pseudo=%s\', \'p\')">x</a>' % N, [N, "Qrst"],
     ["pseudo=user1', 'p')"]),
    # Round-2 adversarial pass: a pseudo may end with an apostrophe, inside a double-quoted href.
    ("param_pseudo_trailing_apostrophe", "URL parameter pseudo=",
     '<a href="/profilebdd.php?config=hfr.inc&amp;pseudo=Wxyz99\'">Wxyz99\'</a>', ["Wxyz99"],
     ['pseudo=user1">user1</a>']),
    ("param_dest", "URL parameter dest=",
     '<a href="/message.php?cat=prive&amp;dest=Wxyz+Qrst">MP</a>', ["Wxyz", "Qrst"], ["dest=user1"]),
    ("param_auteur", "URL parameter auteur=",
     '<a href="/user/ignore.php?auteur=Wxyz%20Qrst&amp;p=1">x</a>', ["Wxyz", "Qrst"], ["auteur=user1&amp;p=1"]),
    ("param_spseudo", "URL parameter spseudo=",
     '<a href="/forum2.php?word=&amp;spseudo=Wxyz+Qrst">x</a>', ["Wxyz", "Qrst"], ["spseudo=user1"]),
    ("pseudo_input", "pseudo input",
     '<input type="hidden" name="pseudo" value="%s" />' % N, [N], ['value="user1"']),
    ("pseudo_input_value_first", "pseudo input",
     '<input value="%s" type="hidden" name="dest" />' % N, [N], ['value="user1"']),
    ("profile_link_text", "profile link text",
     '<a href="/hfr/profil-910001.htm">%s</a>' % N, [N], [">user1</a>"]),
    # Two letters: never replaced in free text, so only the link-text position can alias the text.
    ("mp_link_text", "MP link text",
     '<a href="/message.php?cat=prive&amp;dest=Mo" class="Tableau">Mo</a>', [">Mo<"], ['class="Tableau">user1</a>']),
    ("unread_by_list", "unread-by list",
     '<span class="red" title="Ce message n\'a pas été lu par : %s, Vwxy">[non lu]</span>' % N, [N, "Vwxy"],
     ["lu par : user1, user2"]),
    ("recipients_list", "recipients list",
     '<img src="/x.gif" title="Nouveau message. Message privé pour %s,Vwxy" />' % N, [N, "Vwxy"],
     ["pour user1,user2"]),
    ("mp_correspondents", "MP correspondents",
     '<td class="sujetCase6 x"><span title="%s,Vwxy">Interlocuteurs multiples</span></td>' % N, [N, "Vwxy"],
     ['title="user1,user2">Interlocuteurs multiples']),
    ("ignore_list_title", "ignore list title",
     '<img src="/i.gif" title="Mettre %s en ignore list" />' % N, [N], ["Mettre user1 en ignore list"]),
    ("mp_to_title", "MP to title",
     '<img src="/lock.gif" title="Ce message privé à %s" />' % N, [N], ["privé à user1"]),
    ("contact_list_title", "contact list title",
     '<img src="/c.gif" title="Ajouter  %s à votre liste de contacts" />' % N, [N], ["Ajouter  user1 à"]),
    ("list_author", "list author",
     '<td class="sujetCase6 cBackCouleurTab2 ">%s</td>' % N, [N], ['">user1</td>']),
    ("last_poster", "last poster",
     '<td class="sujetCase9 x"><a href="/a.htm#bas" class="Tableau">26-10-2026<br /><b>%s</b></a></td>' % N, [N],
     ["<b>user1</b>"]),
    ("home_last_poster", "home last poster",
     '<td class="catCase3">26-10-2026<br /><b>par %s</b></td>' % N, [N], ["<b>par user1</b>"]),
    ("form_review_author", "form review author",
     '<td class="messCase1bis" width="160">%s</td>' % N, [N], ['">user1</td>']),
    ("description_author", "description author",
     '<meta name="Description" content="Sujet - Auteur : %s - Page : 3" />' % N, [N], ["Auteur : user1 - Page"]),
    ("smiley_code", "personal smiley code",
     '<textarea name="content_form">hi [:wxyz qrst:2]</textarea>', ["wxyz"], ["hi [:user1:2]"]),
    ("smiley_code_in_url", "personal smiley code in URL",
     '<a href="/wikismilies.php?detail=%5B%3Awxyz+qrst%5D">x</a>', ["wxyz"], ["detail=%5B%3Auser1%5D"]),
    ("smiley_image", "personal smiley image",
     '<img src="/images/perso/wxyz qrst.gif" alt="" />', ["wxyz"], ["/images/perso/user1.gif"]),
    # Public profile page and profile edit page (R56, R55-p5u1): the code printed again in alt/title.
    ("smiley_alt", "personal smiley alt",
     '<img src="/images/perso/1/user7.gif" alt="%s:1" />' % N, [N], ['alt="user1:1"']),
    ("smiley_title", "personal smiley title",
     '<img src="/images/perso/user7.gif" title="%s" />' % N, [N], ['title="user1"']),
    ("avatar_alt", "avatar alt",
     '<img src="https://forum-images.hardware.fr/images/mesdiscussions-910001.jpg" alt="%s" />' % N, [N],
     ['alt="user1"']),
    ("profile_page_title", "profile page title",
     '<html><head><title>%s - FORUM HardWare.fr</title></head>'
     '<body id="unique__user_page__view_user_profile"><p>x</p></body></html>' % N, [N],
     ["<title>user1 - FORUM HardWare.fr</title>"]),
    ("profile_header", "profile header",
     '<h4 class="Ext">Informations sur :  %s</h4>' % N, [N], ["Informations sur :  user1</h4>"]),
    ("profile_pseudo", "profile pseudo",
     '<tr class="profil"><td class="profilCase2">Pseudo&nbsp;: </td><td class="profilCase3"> %s\t</td></tr>' % N,
     [N], ['class="profilCase3"> user1\t</td>']),
    ("posts_by_pseudo_path", "posts by pseudo path",
     '<a href="/hfr/recherche/pseudo-Wxyz%20Qrst.htm" class="cLink">x</a>', ["Wxyz", "Qrst"],
     ['href="/hfr/recherche/pseudo-user1.htm"']),
    # Two letters: never replaced in free text, so only these text positions can alias them (R56 a.cLink).
    ("mp_to_text", "MP to text",
     '<a rel="nofollow" href="/message.php?config=hfr.inc&amp;cat=prive" class="cLink">Envoyer un message privé à Mo</a>',
     [" Mo<"], ["Envoyer un message privé à user1</a>"]),
    ("contact_list_text", "contact list text",
     '<a href="/user/contactlist.php?config=hfr.inc" class="cLink">Ajouter Mo à votre liste de contacts</a>',
     ["Ajouter Mo "], ["Ajouter user1 à votre liste de contacts"]),
    ("id_profil", "member id profil-",
     '<a href="/hfr/profil-555001.htm"><img src="/p.gif" alt="" /></a>', ["555001"], ["profil-910001"]),
    ("id_adduser", "member id adduser=",
     '<a href="/user/contactlist.php?adduser=555001&amp;comeback=1">c</a>', ["555001"], ["adduser=910001"]),
    ("id_user", "member id id_user=",
     '<a href="/user/allread.php?id_user=555001&amp;config=hfr.inc">r</a>', ["555001"], ["id_user=910001"]),
    ("id_avatar", "member id avatar",
     '<img src="https://forum-images.hardware.fr/images/mesdiscussions-555001.jpg" alt="" />', ["555001"],
     ["mesdiscussions-910001.jpg"]),
    ("id_quotemsg", "member id quotemsg",
     '<textarea name="content_form">[quotemsg=7,2,555001]x[/quotemsg]</textarea>', ["555001"],
     ["[quotemsg=7,2,910001]"]),
    ("signature", "signature or mood text",
     '<span class="signature">%s, https://example.org/c/WxyzQrst</span>' % N, [N, "WxyzQrst"],
     ['<span class="signature">Signature removed.</span>']),
    ("mood", "signature or mood text",
     '<span class="MoodStatus">PSN: %s</span>' % N, [N], ['<span class="MoodStatus">Mood removed.</span>']),
    # The same parameter inside an obfuscated link (decoded, redacted, re-encoded with its prefix).
    ("obfuscated_link_param", "URL parameter pseudo=",
     '<span class="md_noclass_cryptlink%s">x</span>' % A.encode_payload("/profilebdd.php?config=hfr.inc&pseudo=Wxyz Qrst"),
     [A.encode_payload("Wxyz")], [A.encode_payload("/profilebdd.php?config=hfr.inc&pseudo=user1")]),
    ("rest_author", "REST author",
     '{"links":{"author":{"type":"link","href":null,"title":"%s"}}}' % N, [N], ['"title":"user1"']),
    ("rest_last_author", "REST last_author",
     '{"links":{"last_author":{"type":"link","href":null,"title":"%s"}}}' % N, [N], ['"title":"user1"']),
)


class PositionOnlyTests(unittest.TestCase):
    """Generated below: test_<id> for every row of CASES."""


def _make(label, page, gone, kept):
    def test(self):
        reasons = [r for _l, _c, r in A.verify_structure(page)]
        self.assertIn("structural check: %s not aliased" % label, reasons)
        out = A.Anonymizer(A.Config()).anonymize(page)
        for value in gone:
            self.assertNotIn(value, out)
        for text in kept:
            self.assertIn(text, out)
        self.assertEqual(A.Anonymizer(A.Config()).findings(out), [])
    return test


for _id, _label, _page, _gone, _kept in CASES:
    setattr(PositionOnlyTests, "test_" + _id, _make(_label, _page, _gone, _kept))


class PartialAliasTests(unittest.TestCase):
    """Review round 2: the first word aliased and the tail left in clear must still fail the verifier."""

    def test_raw_space_tail_after_alias(self):
        page = '<a href="/profilebdd.php?config=hfr.inc&amp;pseudo=user5 Qrst">p</a>'
        self.assertIn("structural check: URL parameter pseudo= not aliased",
                      [r for _l, _c, r in A.verify_structure(page)])

    def test_apostrophe_tail_after_alias(self):
        page = '<a href="/profilebdd.php?config=hfr.inc&amp;pseudo=user5\'Qrst">p</a>'
        self.assertIn("structural check: URL parameter pseudo= not aliased",
                      [r for _l, _c, r in A.verify_structure(page)])

    def test_link_text_and_parameter_with_different_aliases(self):
        page = '<a href="/profilebdd.php?config=hfr.inc&amp;pseudo=user122\'">user110</a>'
        reasons = [r for _l, _c, r in A.verify_structure(page)]
        self.assertIn("structural check: link text alias differs from its parameter", reasons)
        self.assertIn("structural check: URL parameter pseudo= not aliased", reasons)  # the leftover '
        self.assertEqual(A.verify_structure('<a href="/profilebdd.php?pseudo=user5">user5</a>'), [])

    def test_js_string_terminator_is_not_part_of_the_name(self):
        self.assertEqual(A.verify_structure('<a onclick="go(\'/p.php?pseudo=user5\', 1)">p</a>'), [])


PROFILE_BODY = '<body id="unique__user_page__view_user_profile"><table>%s</table></body>'


def _row(label, value):
    return PROFILE_BODY % ('<tr class="profil"><td class="profilCase2">%s&nbsp;: </td><td class="profilCase3">%s</td></tr>'
                           % (label, value))


class ProfileFieldTests(unittest.TestCase):
    """Public profile rows (R56): each value cell is the member's own data, checked by both layers."""

    def _both(self, page, label, gone, kept, scan="public profile field not replaced"):
        self.assertIn("structural check: %s not aliased" % label, [r for _l, _c, r in A.verify_structure(page)])
        self.assertIn(scan, [r for _l, _c, r in A.Anonymizer(A.Config()).findings(page)])
        out = A.Anonymizer(A.Config()).anonymize(page)
        for value in gone:
            self.assertNotIn(value, out)
        for text in kept:
            self.assertIn(text, out)
        self.assertEqual(A.Anonymizer(A.Config()).findings(out), [])
        return out

    def test_personal_rows_get_a_placeholder(self):
        for label, value in (("Ville", "Qrstville"), ("Profession", "Wxyz at Qrst"), ("Loisirs", "Qrst"),
                             ("Sexe", "Qrst"), ("Citation personnelle associée au pseudo", "Qrst"),
                             ("Signature des messages", ' <br /><div style="clear: both;"> </div>Qrst https://q.example/'),
                             ("Email", "<i>wxyz.qrst@example.org</i>"), ("Date de naissance", "Qrst")):
            with self.subTest(label=label):
                self._both(_row(label, value), "public profile field", ["Qrst"], [A.PROFILE_PLACEHOLDER])

    def test_markup_only_values_get_a_placeholder(self):
        # No text at all: the value is in the markup (CodeRabbit on PR #50).
        for label, value in (("Signature des messages", '<img src="https://q.example/wxyz.png" alt="" />'),
                             ("Site web", '<a href="https://wxyz.example/"><img src="/w.gif" /></a>'),
                             ("Loisirs", '<span title="Wxyz Qrst"></span>'),
                             ("Citation personnelle associée au pseudo", '<div style="background:url(/wxyz.png)"></div>')):
            with self.subTest(label=label):
                self._both(_row(label, value), "public profile field markup", ["wxyz", "Wxyz"],
                           [A.PROFILE_PLACEHOLDER])

    def test_layout_only_empty_value_is_kept(self):
        page = _row("Signature des messages", ' <br /><div style="clear: both;"> </div>&nbsp;')
        self.assertEqual(A.verify_structure(page), [])
        self.assertEqual(A.Anonymizer(A.Config()).anonymize(page), page)

    def test_birth_date_keeps_its_format(self):
        self._both(_row("Date de naissance", "17/06/1983"), "public profile field", ["17/06", "1983"],
                   ["01/01/2000"])

    def test_logged_out_email_notice_is_kept(self):
        page = _row("Email", "\n<i>%s</i>\t" % A.PROFILE_NO_ACCESS)
        self.assertEqual(A.verify_structure(page), [])
        self.assertEqual(A.Anonymizer(A.Config()).anonymize(page), page)

    def test_counters_and_dates_get_fixed_values(self):
        for label, value, kept in (("Nombre de messages postés", "6123", ">100<"),
                                   ("Date d'arrivée sur le forum", "17/06/2003", ">01/01/2000<"),
                                   ("Date du dernier message", "\n26-10-2026&nbsp;à&nbsp;15:34\t",
                                    "01-01-2000&nbsp;à&nbsp;00:00")):
            with self.subTest(label=label):
                self._both(_row(label, value), "public profile counter or date", [value.strip()], [kept])

    def test_profile_edit_form_rows_are_left_alone(self):
        # The edit form (R55-p1) has the same labels around its inputs: only the public page is rewritten.
        page = ('<body id="unique__user_page__edit_profile"><table><tr><td class="profilCase2">Ville&nbsp;: </td>'
                '<td class="profilCase3"><input type="text" name="custom_ville" value="" /></td></tr></table></body>')
        self.assertEqual(A.Anonymizer(A.Config()).anonymize(page), page)
        self.assertEqual(A.verify_structure(page), [])

    def test_transaction_count(self):
        page = PROFILE_BODY % '<tr><td class="profilCase3"><a href="/t.php">Transactions (28)</a></td></tr>'
        self._both(page, "public profile transaction count", ["(28)"], ["Transactions (0)"],
                   scan="public profile transaction count not replaced")


class CategoryLabelTests(unittest.TestCase):
    """A member named like a word of a category is aliased everywhere but in the sub-forum labels."""

    BAR = ('<td class="padding" align="center" colspan="9">'
           '<a href="/hfr/Programmation/Big-Wxyz/liste_sujet-1.htm" class="cHeader">BI/Big Wxyz </a> | '
           '<a href="/forum1.php?config=hfr.inc&amp;cat=10&amp;subcat=1" class="cHeader">Big Wxyz</a></td>')

    def test_sub_forum_label_is_kept(self):
        page = self.BAR + '<p>Une pensée pour Wxyz</p>'
        out = A.Anonymizer(A.Config(), known_names=["Wxyz"]).anonymize(page)
        self.assertIn('class="cHeader">BI/Big Wxyz </a>', out)
        self.assertIn('class="cHeader">Big Wxyz</a>', out)
        self.assertIn("<p>Une pensée pour user1</p>", out)
        self.assertEqual(A.Anonymizer(A.Config(), known_names=["Wxyz"]).findings(out), [])

    def test_list_link_outside_the_bar_is_not_a_label(self):
        # A list URL alone does not make a category label: "Message de X" linking to a forum list.
        page = ('<td class="sujetCase3"><a href="/hfr/Discussions/Cuisine/liste_sujet-1.htm" class="cHeader">'
                'Message de Wxyz</a></td>')
        anon = A.Anonymizer(A.Config(), known_names=["Wxyz"])
        self.assertIn("known member name in a list link text", [r for _l, _c, r in anon.findings(page)])
        out = anon.anonymize(page)
        self.assertIn(">Message de user1</a>", out)
        self.assertEqual(anon.findings(out), [])

    def test_member_link_to_a_list_is_not_a_category(self):
        page = '<td class="padding"><a href="/forum1.php?config=hfr.inc&amp;cat=13&amp;spseudo=x" class="cHeader">Wxyz</a></td>'
        out = A.Anonymizer(A.Config(), known_names=["Wxyz"]).anonymize(page)
        self.assertNotIn(">Wxyz<", out)


class ScopedPhraseTests(unittest.TestCase):
    """Profile and action-link phrases are checked in their element only, not in prose."""

    def test_prose_is_not_a_profile_header_or_action_link(self):
        for page in ("<p>Informations sur : le processeur</p>",
                     "<div id=\"para1\"><p>Envoyer un message privé à la modération</p></div>",
                     "<p>Ajouter le topic à votre liste de contacts ?</p>"):
            with self.subTest(page=page):
                self.assertEqual(A.verify_structure(page), [])
                self.assertEqual(A.Anonymizer(A.Config()).anonymize(page), page)

    def test_elements_are_still_checked(self):
        for page, label in (("<h4 class=\"Ext\">Informations sur :  Wxyz</h4>", "profile header"),
                            ("<a href=\"/m.php\" class=\"cLink\">Envoyer un message privé à Mo</a>", "MP to text"),
                            ("<a href=\"/c.php\">Ajouter Mo à votre liste de contacts</a>", "contact list text")):
            with self.subTest(label=label):
                self.assertIn("structural check: %s not aliased" % label,
                              [r for _l, _c, r in A.verify_structure(page)])


class CoverageTests(unittest.TestCase):
    def test_every_discover_entry_has_a_position_test(self):
        # A new DISCOVER entry without a row here would go untested.
        covered = {
            "post author": "post_author", "quote header": "quote_header", "edit notice": "edit_notice",
            "url parameter": "param_pseudo_raw_space", "pseudo input": "pseudo_input",
            "pseudo input (value first)": "pseudo_input_value_first", "profile link": "profile_link_text",
            "MP link text": "mp_link_text", "unread by": "unread_by_list", "MP recipients": "recipients_list",
            "MP correspondents": "mp_correspondents", "ignore list": "ignore_list_title", "MP to": "mp_to_title",
            "contact list": "contact_list_title", "list author": "list_author", "last poster": "last_poster",
            "home last poster": "home_last_poster", "form review author": "form_review_author",
            "description author": "description_author", "personal smiley": "smiley_code",
            "personal smiley in URL": "smiley_code_in_url", "personal smiley image": "smiley_image",
            "REST author": "rest_author", "personal smiley alt": "smiley_alt",
            "personal smiley title": "smiley_title", "avatar alt": "avatar_alt",
            "profile page title": "profile_page_title", "profile header": "profile_header",
            "profile pseudo": "profile_pseudo", "posts by pseudo path": "posts_by_pseudo_path",
            "MP to text": "mp_to_text", "contact list text": "contact_list_text"}
        self.assertEqual(sorted(d[0] for d in A.DISCOVER), sorted(covered))
        ids = {c[0] for c in CASES}
        self.assertTrue(set(covered.values()) <= ids)


if __name__ == "__main__":
    unittest.main()
