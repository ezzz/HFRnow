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
            "REST author": "rest_author"}
        self.assertEqual(sorted(d[0] for d in A.DISCOVER), sorted(covered))
        ids = {c[0] for c in CASES}
        self.assertTrue(set(covered.values()) <= ids)


if __name__ == "__main__":
    unittest.main()
