#!/usr/bin/env python3
"""Anonymize captured HFR pages before they are committed as fixtures (docs/FIXTURES.md).

    anonymize.py --config local.json [--private] in.html out.html
    anonymize.py check [--config local.json] [--private] file.html [...]
    anonymize.py check --corpus DIR        # every <id>.meta.json and its file, --private from the meta

Member pseudos are replaced where HFR prints them (structural positions, DISCOVER), then in free
text when the name is long and specific enough (never in tag or attribute names, URLs or scripts).
`check` runs a second, independent verifier (StructuralVerifier, html.parser based) over the same
positions, so a position missing from DISCOVER is reported instead of silently kept.

Python 3 stdlib only. Output is English; colors are disabled without a TTY or with NO_COLOR.
"""
import argparse
import html
import html.entities
import html.parser
import json
import os
import re
import sys
import unicodedata
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _ui  # noqa: E402

REDACTED = "REDACTED"
PRIVATE_PLACEHOLDER = "Private message content removed."
EMAIL_PLACEHOLDER = "redacted@example.invalid"
IP_PLACEHOLDER = "192.0.2.1"  # RFC 5737 documentation range
FAKE_ID_OPERATOR = 900001
FAKE_ID_OTHER = 910001

# Alphabet of the HFR link obfuscation: index in this string == nibble value.
ALPHABET = "0A12B34C56D78E9F"
# Legacy: RangeOfCharacters.m:92-114 (decodeSpanUrlFromString, prefix 20) and :117+ (…2, prefix 12);
# prefix names and lengths: docs/HFR-PROTOCOL.md §7 row E7.
PREFIXES = ("md_noclass_cryptlink", "md_blank_cryptlink", "md_cryptlink")
TOKEN_RE = re.compile(
    r"(?<![\w-])(%s)([0-9A-F]{2,})(?![0-9A-Za-z])" % "|".join(PREFIXES))

# md_passs / md_id: the cookie names HFR actually sets on login (live, LOT-001 fixture W03);
# md_data: set by bddpost.php answers (live, W14).
COOKIE_NAMES = r"md_user|md_passs|md_pass|md_id|md_data|md_forum|md_session|PHPSESSID|session_?id|sessid|sid"
COOKIE_RE = re.compile(r"(?<![\w])(%s)=([^;&\s\"'<>]+)" % COOKIE_NAMES, re.I)
COOKIE_OK = {"", REDACTED.lower(), "deleted"}
# codehex: per-session logout token of the authenticated `unlog.php` link (live, fixture R21).
HASH_RE = re.compile(
    r"((?:hash_check|codehex)(?:%3D|=|[\"']?\s*:\s*[\"']?))([^&\"'\s<>;)\\,]+)", re.I)
EMAIL_RE = re.compile(
    r"[A-Za-z0-9._+-]+(?:@|%40)[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
_OCTET = r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
IP_RE = re.compile(r"(?<![\d.])%s(?:\.%s){3}(?!\d|\.\d)" % (_OCTET, _OCTET))
INPUT_RE = re.compile(r"<input\b[^>]*>", re.I | re.S)
VALUE_RE = re.compile(r"(\bvalue\s*=\s*)(?:([\"'])(.*?)\2|([^\s>\"']+))", re.I | re.S)
PROFIL_RE = re.compile(r"(profil-)(\d+)", re.I)
TOKEN_NAME_RE = re.compile(r"hash|token|csrf|nonce|sess|secret|pass|auth|sid|key", re.I)
TOKEN_VALUE_RE = re.compile(r"[A-Za-z0-9+/=_-]{20,}")
FIXED_INPUT_NAMES = {"hash_check", "md_user", "md_pass"}
# Personal fields of the profile edit form (editprofil.php page 1, fixture R55-p1).
PERSONAL_INPUT_NAMES = {"email", "emailconfirm", "homepage", "custom_ville", "custom_occupation", "custom_hobby"}
PERSONAL_SELECT_RE = re.compile(
    r"(<select\b[^>]*\bname=[\"'](?:bday|bmonth|byear|custom_sexe)[\"'][^>]*>)(.*?)(</select>)", re.I | re.S)
SELECTED_RE = re.compile(r"\s+selected(?:\s*=\s*(?:[\"'][^\"']*[\"']|[^\s>]+))?", re.I)
# Operator ids also appear as bare numbers ([quotemsg=…,…,<id>], md_id, user_id=): ids this long only.
MIN_BARE_ID_DIGITS = 5

# MP list subjects are private too (live R13u1); fixture threads, MPStorage title and page numbers stay.
SUBJECT_RE = re.compile(r"(<a\b[^>]*\bclass=[\"']cCatTopic[\"'][^>]*>)(.*?)(</a>)", re.I | re.S)
KEEP_SUBJECT_RE = re.compile(r"\s*(?:\d+|fixture-test[\w -]*|[0-9a-f]{32}|%s)\s*$" % re.escape("Private subject"))
PRIVATE_SUBJECT = "Private subject"
# Signatures and mood statuses are a member's own words (names, handles, links): always replaced.
PERSONAL_BLOCKS = (
    (re.compile(r"<(span)\b[^>]*\bclass=[\"']signature[\"'][^>]*>", re.I), "Signature removed."),
    (re.compile(r"<(span)\b[^>]*\bclass=[\"']MoodStatus[\"'][^>]*>", re.I), "Mood removed."),
)
PARA_OPEN_RE = re.compile(r"<(\w+)\b[^>]*\bid=([\"'])para[^\"']*\2[^>]*>", re.I)

# Member pseudos other than the operator's: every position where HFR prints one (live, LOT-001
# corpus; legacy selectors: ParseMessagesOperation.m:149 author `b.s2`, :380 profile link, :200-220
# quotes). Entry: (label, regex, group, mode). Modes say how the group holds the name:
#   name   the group is the (HTML-escaped) name        inner  names are the text nodes of the group
#   param  %-encoded URL parameter value               list   comma-separated names
#   same   link text, a name only when it equals the URL parameter in group 1
#   smiley personal smiley code, smileypath its image  json   JSON string value
_E = r"(?:é|&eacute;|&#0*233;)"
_AGRAVE = r"(?:à|&agrave;|&#0*224;)"
_Q = r"[\"']"
_PARAMS = r"(?:spseudo|pseudo|dest|auteur)"
DISCOVER = tuple((label, re.compile(rx, re.I | re.S), group, mode) for label, rx, group, mode in (
    # Topic and MP pages: the author cell; `b.s2` elsewhere (poll question) is not a member.
    ("post author", r"<td\b[^>]*\bclass=%smessCase1%s[^>]*>(?:(?!</td>).)*?<b\b[^>]*\bclass=%ss2%s[^>]*>(.*?)</b>"
     % (_Q, _Q, _Q, _Q), 1, "inner"),
    ("quote header", r">\s*([^<>]{1,80}?)\s+a\s+%scrit\s*:" % _E, 1, "name"),
    ("edit notice", r"%sdit%s\s+par\s+([^<>]{1,80}?)\s+le\b" % (_E, _E), 1, "name"),
    # HFR writes raw spaces and apostrophes in these values (live R10, R13u1, a pseudo may even end with
    # `'`): the value runs to `&`, `"`, `<`, `#` or a line end; inside a JS single-quoted string it also
    # stops at the closing `'` (param_value trims it).
    ("url parameter", r"(?<![\w-])%s=((?:[^&\"<>#;\n]|&(?!amp;)#?\w+;){1,120})" % _PARAMS, 1, "param"),
    ("pseudo input", r"<input\b[^>]*\bname=%s%s%s[^>]*\bvalue=([\"'])((?:(?!\1)[^<>])*)\1" % (_Q, _PARAMS, _Q), 2,
     "name"),
    ("pseudo input (value first)", r"<input\b[^>]*\bvalue=([\"'])((?:(?!\1)[^<>])*)\1[^>]*\bname=%s%s%s" % (_Q, _PARAMS, _Q), 2,
     "name"),
    ("profile link", r"<a\b[^>]*\bhref=%s[^\"']*profil-\d+[^\"']*%s[^>]*>([^<]+)</a>" % (_Q, _Q), 1, "name"),
    ("MP link text", r"<a\b[^>]*\bhref=%s[^\"']*?(?:dest|pseudo)=([^&\"'#]*)[^\"']*%s[^>]*>([^<]+)</a>" % (_Q, _Q),
     2, "same"),
    # MP list (R13*): unread-by list, multi-correspondent list, recipients, ignore and lock titles.
    ("unread by", r"\btitle=\"[^\"]*?lu par\s*:\s*([^\"]*)\"", 1, "list"),
    ("MP recipients", r"\btitle=\"[^\"]*?Message priv%s pour\s+([^\"]*)\"" % _E, 1, "list"),
    ("MP correspondents", r"<span\b[^>]*\btitle=\"([^\"]*)\"[^>]*>\s*Interlocuteurs multiples", 1, "list"),
    ("ignore list", r"\b(?:title|alt)=\"(?:Mettre|Enlever)\s+([^\"]+?)\s+(?:en\s+|de\s+l(?:'|&#0*39;|&apos;))ignore list",
     1, "name"),
    ("MP to", r"\b(?:title|alt)=\"[^\"]*?message priv%s\s+%s\s+([^\"]+?)\s*\"" % (_E, _AGRAVE), 1, "name"),
    ("contact list", r"\b(?:title|alt)=\"Ajouter\s+([^\"]+?)\s+%s votre liste de contacts" % _AGRAVE, 1, "name"),
    # Topic lists, favourites, search results, MP list: author column and last poster.
    ("list author", r"<td\b[^>]*\bclass=%ssujetCase6\b[^\"']*%s[^>]*>(.*?)</td>" % (_Q, _Q), 1, "inner"),
    ("last poster", r"\bclass=%sTableau%s[^>]*>[^<]*<br\s*/?>\s*<b>(.*?)</b>" % (_Q, _Q), 1, "inner"),
    ("home last poster", r"\bclass=%scatCase3%s[^>]*>(?:(?!</td>).)*?<br\s*/?>\s*<b>par\s+(.*?)</b>" % (_Q, _Q),
     1, "inner"),
    # Reply / quote forms: the review of the last posts under the form.
    ("form review author", r"<td\b[^>]*\bclass=%smessCase1bis%s[^>]*>(.*?)</td>" % (_Q, _Q), 1, "inner"),
    ("description author", r"\bAuteur\s*:\s*([^\"<>]{1,80}?)\s+-\s+Page\b", 1, "name"),
    # Personal smileys are named after a member: [:code] / [:code:N] and /images/perso/[N/]code.gif.
    ("personal smiley", r"\[:([^\[\]:<>\"]{1,80}?)(?::\d+)?\]", 1, "smiley"),
    # Codes may hold an apostrophe, kept raw in the double-quoted src (live R53b).
    ("personal smiley in URL", r"%5B%3A((?:(?!%5D|%3A\d)[^&\"'\s<>#]){1,240}?)(?:%3A\d+)?%5D", 1, "smileyparam"),
    ("personal smiley image", r"/images/perso/(?:\d+/)?([^\"<>/?#]+?)\.(?:gif|png|jpe?g)\b", 1, "smileypath"),
    # REST API (R57*): author objects.
    ("REST author", r"\"(?:last_)?author\"\s*:\s*\{[^{}]*?\"title\"\s*:\s*\"((?:[^\"\\]|\\.)*)\"", 1, "json"),
))
SMILEY_MODES = {"smiley", "smileypath", "smileyparam"}
NOT_A_MEMBER = {"", "publicité", "publicite", "anonyme", REDACTED.lower(), "interlocuteurs multiples"}
FAKE_NAME_RE = re.compile(r"user\d+$")

# Member ids, mapped through one table per file (operators -> 9000NN, others -> 9100NN): profile
# links, contact-list links, the logged-in header, avatars (also REST `tns3`), quote prefills.
ID_POSITIONS = tuple(re.compile(rx, re.I) for rx in (
    r"(profil-)(\d+)", r"(\badduser=)(\d+)", r"(\bid_user=)(\d+)", r"(mesdiscussions-)(\d+)",
    r"(\[quotemsg=\d+,\d+,)(\d+)(?=\])", r"(%5Bquotemsg%3D\d+%2C\d+%2C)(\d+)(?=%5D)"))
FAKE_ID_RE = re.compile(r"9[01]\d{4}$")

# Free-text replacement skips short names and common words (a member called "Le" or "follow" must
# not rewrite prose or `noindex, follow`); those are replaced in structural positions only.
MIN_FREE_TEXT_LEN = 3
COMMON_WORDS = frozenset("""
a à ai au aux avec ce ces cet cette ci comme dans de des du elle elles en est et être eu il ils je la le les leur
leurs lui ma mais me mes moi mon ne ni nos notre nous on ou où par pas peu plus pour qu que qui sa sans se ses si
son sur ta te tes toi ton tous tout toute toutes très tu un une vos votre vous y ça oui non bon bien merci
salut bonjour bonsoir ok lol mdr alors donc car quand comment pourquoi aussi encore jamais toujours ici déjà
the and for are but not you all any can had her was one our out has him his how now see who did its let say
she too use yes no of to in is it on at be by or as an we he if my me so up do go us am hello hi hey thanks
follow nofollow index noindex http https www com net org html htm php gif jpg png css js
var function return this document window new class style script div span table body head title
user users anonymous private content removed subject redacted signature mood
hardware hardwarefr forum hfr prive config inc cat post page sujet topic message messages
""".split())
# Zero-width characters HFR keeps inside some printed pseudos (live R21) but not in their links.
ZERO_WIDTH = "\u200b\u200c\u200d\ufeff"
_ZW_TOKEN = r"(?:[%s]|&#0*(?:8203|8204|8205|65279);|&#x0*(?:200b|200c|200d|feff);)" % ZERO_WIDTH
ZW_TOKEN_RE = re.compile(_ZW_TOKEN, re.I)


def name_key(name):
    """Alias lookup key: lower case, zero-width characters removed."""
    return re.sub("[%s]" % ZERO_WIDTH, "", name).lower()


def encode_payload(text):
    """Obfuscate text: each byte becomes two characters of ALPHABET (high nibble first)."""
    out = []
    for b in text.encode("utf-8", "surrogateescape"):
        out.append(ALPHABET[b >> 4] + ALPHABET[b & 15])
    return "".join(out)


def decode_payload(payload):
    """Reverse of encode_payload; None when the payload is not a printable ASCII string."""
    if len(payload) % 2:
        return None
    raw = bytearray()
    for i in range(0, len(payload), 2):
        hi, lo = ALPHABET.find(payload[i]), ALPHABET.find(payload[i + 1])
        if hi < 0 or lo < 0:
            return None
        raw.append(hi * 16 + lo)
    if not all(0x20 <= b <= 0x7E for b in raw):
        return None
    return raw.decode("ascii")


def iter_tokens(text):
    """Yield (position, prefix, payload, decoded-or-None) for every obfuscated class token.

    Mirrors the legacy guard (ObjCMessageActionsBuilder.m:80-89): only strings longer than 20
    characters are decoded, and a decoded value must look like a URL part (printable ASCII).
    """
    for m in TOKEN_RE.finditer(text):
        prefix, payload = m.group(1), m.group(2)
        decoded = decode_payload(payload) if len(prefix) + len(payload) > 20 else None
        yield m.start(), prefix, payload, decoded, m


def _char_alts(ch):
    # Entities and %-escapes are not covered by re.I, so enumerate both letter cases explicitly.
    alts = [re.escape(ch)]
    for c in sorted({ch, ch.lower(), ch.upper()}):
        if len(c) != 1:
            continue
        cp = ord(c)
        if c == " ":
            alts += [r"\+", "&nbsp;"]
        alts.append("".join("%%%02X" % b for b in c.encode("utf-8")))
        if cp < 256:
            alts.append("%%%02X" % cp)
        alts += ["&#0*%d;" % cp, "&#x0*%x;" % cp]
        if cp > 127:
            alts.append(r"\\u%04x" % cp)  # JSON escape (REST answers)
        # HFR also %-encodes an already entity-escaped pseudo in URLs (dest=a%26%23039%3Bb, live R01).
        alts += ["%%26%%23(?:0*%d|x0*%x)%%3B" % (cp, cp)]
        name = html.entities.codepoint2name.get(cp)
        if name:
            alts += ["&%s;" % name, "%%26%s%%3B" % name]
        if c == "'":
            alts += ["&apos;", "%26apos%3B"]
    return "(?:%s)" % "|".join(dict.fromkeys(alts))


def pseudo_regex(pseudo):
    """Regex matching a pseudo in any mix of raw, %-encoded and HTML-entity forms, case-insensitively."""
    zw = _ZW_TOKEN + "*"
    body = zw.join(_char_alts(c) for c in name_key(pseudo))
    return re.compile(
        r"(?:(?<!\w)|(?<=%[0-9A-Fa-f]{2}))" + body + r"(?!\w)", re.I)


def _attr(tag, name):
    m = re.search(r"\b%s\s*=\s*(?:([\"'])(.*?)\1|([^\s>\"']+))" % name, tag, re.I | re.S)
    if not m:
        return None
    return m.group(2) if m.group(1) else m.group(3)


def _sensitive_input(tag):
    name = (_attr(tag, "name") or "").lower()
    typ = (_attr(tag, "type") or "").lower()
    value = _attr(tag, "value")
    if value is None or value in ("", REDACTED):
        return False
    if name in FIXED_INPUT_NAMES or name in PERSONAL_INPUT_NAMES:
        return True
    if typ == "hidden":
        return bool(TOKEN_NAME_RE.search(name) or TOKEN_VALUE_RE.fullmatch(value))
    return False


def _find_para_blocks(text, open_re=None):
    """Yield (inner_start, inner_end) of every element whose id starts with `para` (message body),
    or of every element whose start tag matches open_re."""
    open_re = open_re or PARA_OPEN_RE
    pos = 0
    while True:
        m = open_re.search(text, pos)
        if not m:
            return
        tag = m.group(1)
        tag_re = re.compile(r"<(/?)%s\b[^>]*>" % re.escape(tag), re.I)
        depth, end = 1, None
        for t in tag_re.finditer(text, m.end()):
            depth += -1 if t.group(1) else 1
            if depth == 0:
                end = t.start()
                break
        if end is None:
            end = len(text)
        yield m.end(), end
        pos = max(end, m.end())


def _strip_tags(s):
    return html.unescape(re.sub(r"<[^>]*>", "", s)).strip()


def line_of(text, pos):
    """1-based line number of a character offset."""
    return text.count("\n", 0, pos) + 1


def column_of(text, pos):
    """1-based column of a character offset."""
    return pos - text.rfind("\n", 0, pos)


def slug_form(name):
    """How HFR would print a name in a topic slug: no accents, lower case, `-` between words."""
    plain = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode("ascii")
    return re.sub(r"[^a-z0-9]+", "-", plain.lower()).strip("-")


def _free_text_name(key):
    """True when a name is specific enough to be replaced in free text, not only in its positions."""
    return len(key) >= MIN_FREE_TEXT_LEN and not key.isdigit() and key not in COMMON_WORDS \
        and key not in NOT_A_MEMBER and not FAKE_NAME_RE.match(key)


def known_member_names(texts):
    """Member names in the structural positions of these pages (not smiley codes), for known_names."""
    probe, names = Anonymizer(Config()), set()
    for text in texts:
        for name, _pos, mode in probe.discover(text):
            if mode not in SMILEY_MODES:
                names.add(name)
        for _pos, _p, _pl, decoded, _m in iter_tokens(text):
            if decoded:
                names.update(n for n, _q, m in probe.discover(decoded) if m not in SMILEY_MODES)
    return names


class AnonymizeError(Exception):
    """The anonymized page would not keep the structure of the original."""


def decode_name(raw, mode):
    """Printed form of a name captured by a DISCOVER group in the given mode."""
    if mode == "json":
        try:
            return json.loads('"%s"' % raw).strip()
        except ValueError:
            return raw.strip()
    if mode == "param":
        return html.unescape(urllib.parse.unquote_plus(html.unescape(raw))).strip()
    if mode == "smileyparam":
        return html.unescape(urllib.parse.unquote_plus(raw)).strip()
    if mode == "smileypath":
        return html.unescape(urllib.parse.unquote(raw)).strip()
    if mode == "inner":
        return _strip_tags(raw)
    return html.unescape(raw).replace("\xa0", " ").strip()


def in_js_string(prefix):
    """True when text ending with prefix is inside a JS single-quoted string of the current attribute."""
    start = max(prefix.rfind('"'), prefix.rfind("<"), prefix.rfind(">"), prefix.rfind("\n"))
    return re.sub(r"\\'", "", prefix[start + 1:]).count("'") % 2 == 1


def param_value(raw, prefix):
    """The parameter value in raw: cut at a closing JS quote when inside a JS string, trailing spaces kept out."""
    if in_js_string(prefix):
        m = re.match(r"(?:\\'|[^'])*", raw)
        raw = m.group(0)
    return raw.rstrip()


def split_list(raw):
    """[(start, end)] of the comma-separated items of raw, item whitespace and trailing ellipsis excluded."""
    out, pos = [], 0
    for part in raw.split(","):
        m = re.match(r"\s*(.*?)\s*(?:…|\.\.\.)?\s*$", part, re.S)
        if m.group(1):
            out.append((pos + m.start(1), pos + m.end(1)))
        pos += len(part) + 1
    return out


def looks_json(text):
    """True for a JSON document (REST answers, meta files)."""
    if text.lstrip()[:1] not in ("{", "["):
        return False
    try:
        json.loads(text)
    except ValueError:
        return False
    return True


# Markup tokens: comments, doctype, tags. Script and style contents are raw text.
TAG_RE = re.compile(r"<!--.*?-->|<![^>]*>|</?[A-Za-z][^<>]*>", re.S)
ATTR_RE = re.compile(r"([^\s\"'<>/=]+)(\s*=\s*)(\"[^\"]*\"|'[^']*'|[^\s\"'>]+)")
RAW_TEXT_TAGS = ("script", "style")
# Attributes whose value is human-readable text (names in it are replaced like in text nodes).
TEXT_ATTRS = {"title", "alt", "value", "placeholder", "content", "label", "summary", "aria-label"}
URL_IN_TEXT_RE = re.compile(r"(?:https?://|www\.)[^\s<>\"']+", re.I)
# In URLs, free-text names are replaced only in internal topic slugs (a topic titled after a member)
# and in external URLs; internal paths and queries keep their words (category paths, parameters are
# structural). The meta files get the same treatment, so final_url keeps matching the page.
SLUG_RE = re.compile(r"(/hfr/(?:[^/\s\"'<>?#]+/)+)([^/\s\"'<>?#]+?)(-sujet_\d+_\d+\.htm)")
EXT_URL_RE = re.compile(r"(?:https?:)?//(?![\w.-]*hardware\.fr(?![\w.-]))[^\s\"'<>]+", re.I)
JSON_STR_RE = re.compile(r"\"((?:[^\"\\]|\\.)*)\"(\s*:)?")


def iter_segments(text):
    """Yield (kind, start, end): kind is "text", "tag" or "raw" (script/style body, comment)."""
    pos = 0
    while True:
        m = TAG_RE.search(text, pos)
        if not m:
            break
        if m.start() > pos:
            yield "text", pos, m.start()
        tag = m.group(0)
        if tag.startswith("<!"):
            yield "raw", m.start(), m.end()
            pos = m.end()
            continue
        yield "tag", m.start(), m.end()
        pos = m.end()
        name = re.match(r"</?([A-Za-z][\w:-]*)", tag).group(1).lower()
        if name in RAW_TEXT_TAGS and not tag.startswith("</"):
            close = re.compile(r"</%s\s*>" % name, re.I).search(text, pos)
            end = close.start() if close else len(text)
            if end > pos:
                yield "raw", pos, end
            pos = end
    if pos < len(text):
        yield "text", pos, len(text)


def markup_signature(text):
    """Tag names with their attribute names, in order (JSON: the key sequence). Anonymization keeps it."""
    if looks_json(text):
        return [m.group(1) for m in JSON_STR_RE.finditer(text) if m.group(2)]
    sig = []
    for kind, start, end in iter_segments(text):
        if kind == "tag":
            tag = text[start:end]
            name = re.match(r"</?([A-Za-z][\w:-]*)", tag).group(0).lower()
            sig.append((name, tuple(a.group(1).lower() for a in ATTR_RE.finditer(tag, len(name)))))
    return sig


class Config:
    """Operator-local settings: real pseudos (→ user1…), e-mails and profile ids to hide."""

    def __init__(self, pseudos=(), emails=(), profile_ids=(), extra_pseudos=()):
        self.pseudos = [p for p in pseudos if p]
        # Other members' names the operator listed by hand (seen in public prose or titles): replaced
        # in free text of every file like corpus-wide names, without the length/common-word filter.
        self.extra_pseudos = [p for p in extra_pseudos if p and p.strip()]
        self.emails = [e for e in emails if e]
        # A null entry keeps the position (user1 -> 900001, user2 -> 900002) for an unknown id.
        self.profile_ids = ["" if i is None else str(i) for i in profile_ids]

    @classmethod
    def load(cls, path):
        """Load and validate a JSON config file."""
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        for key in ("pseudos", "emails", "profile_ids", "extra_pseudos"):
            if key in data and not isinstance(data[key], list):
                raise ValueError("config key %r must be a list" % key)
        return cls(data.get("pseudos", []), data.get("emails", []), data.get("profile_ids", []),
                   data.get("extra_pseudos", []))


class Anonymizer:
    """Stateless across files for the operator's identity, fresh per call for other members."""

    def __init__(self, config, known_names=()):
        """known_names: member names seen anywhere in the corpus, replaced in free text of every file."""
        self.config = config
        self.known = {name_key(n) for n in known_names if _free_text_name(name_key(n))}
        self.known |= {name_key(n) for n in config.extra_pseudos}
        self.names = {}      # name key -> fake name for the current file
        self.free = set()    # name keys also replaced in free text
        self.ids = {}        # real member id -> fake id for the current file
        self.stats = {}
        self._regex_cache = {}
        self._free_rx = None

    # -- state ----------------------------------------------------------------
    def _reset(self):
        self.names = {name_key(p): "user%d" % (i + 1) for i, p in enumerate(self.config.pseudos)}
        self.free = set(self.known)
        self.ids = {pid: str(FAKE_ID_OPERATOR + i) for i, pid in enumerate(self.config.profile_ids) if pid}
        self.stats = {"tokens": 0, "undecoded_tokens": 0, "others": 0, "private_blocks": 0}
        self._free_rx = None

    def _rx(self, pseudo):
        if pseudo not in self._regex_cache:
            self._regex_cache[pseudo] = pseudo_regex(pseudo)
        return self._regex_cache[pseudo]

    def _alias(self, name, free_text=False):
        """Fake name for a member name (assigned on first sight), or None when it is not a member."""
        key = name_key(name)
        if key in NOT_A_MEMBER or FAKE_NAME_RE.match(key) or re.search(r"[<>=]", name) or len(name) > 80:
            return None
        if key not in self.names:
            # An operator pseudo in another spelling (entities, %-escapes) keeps the operator alias.
            own = [i for i, p in enumerate(self.config.pseudos) if self._rx(name_key(p)).fullmatch(name)]
            if own:
                self.names[key] = "user%d" % (own[0] + 1)
                return self.names[key]
            self.names[key] = "user%d" % (len(set(self.names.values())) + 1)
            self.stats["others"] += 1
        if free_text and _free_text_name(key) and key not in self.free:
            self.free.add(key)
            self._free_rx = None
        return self.names[key]

    # -- discovery of other members --------------------------------------------
    def discover(self, text, base=0):
        """Return [(name, pos, mode)] of member names in structural positions, in document order."""
        found = []
        for _label, rx, group, mode in DISCOVER:
            for m in rx.finditer(text):
                raw = m.group(group)
                if mode == "list":
                    for a, b in split_list(raw):
                        found.append((decode_name(raw[a:b], "name"), base + m.start(group) + a, mode))
                    continue
                if mode == "same":
                    if name_key(decode_name(m.group(1), "param")) != name_key(decode_name(raw, "name")):
                        continue
                    mode = "name"
                if mode == "param":
                    raw = param_value(raw, text[max(0, m.start(group) - 400):m.start(group)])
                found.append((decode_name(raw, mode), base + m.start(group), mode))
        return sorted((f for f in found if f[0]), key=lambda f: f[1])

    def learn(self, text, extra=()):
        """Assign aliases and fake ids in document order (page, then decoded links at their position)."""
        found = list(self.discover(text))
        id_hits = self._id_hits(text)
        for pos, decoded in extra:
            found += [(n, pos, m) for n, _p, m in self.discover(decoded)]
            id_hits += [(pos, i) for _p, i in self._id_hits(decoded)]
        for name, _pos, mode in sorted(found, key=lambda f: f[1]):
            self._alias(name, free_text=mode not in SMILEY_MODES)
        own = len(self.ids)
        for _pos, rid in sorted(id_hits):
            if rid not in self.ids and rid not in self.ids.values():
                self.ids[rid] = str(FAKE_ID_OTHER + len(self.ids) - own)

    @staticmethod
    def _id_hits(text):
        return [(m.start(2), m.group(2)) for rx in ID_POSITIONS for m in rx.finditer(text)]

    # -- rewriting --------------------------------------------------------------
    def _rewrite(self, raw, mode):
        """New text for a DISCOVER group (raw) holding a name in the given mode."""
        if mode == "list":
            out, last = [], 0
            for a, b in split_list(raw):
                out += [raw[last:a], self._rewrite(raw[a:b], "name")]
                last = b
            return "".join(out) + raw[last:]
        if mode == "inner":
            alias = self._alias(decode_name(raw, "inner"))
            if alias is None:
                return raw
            parts, done = re.split(r"(<[^>]*>)", raw), False
            for i, part in enumerate(parts):
                if part.startswith("<") or not part.strip():
                    continue
                lead, trail = re.match(r"\s*", part).group(0), re.search(r"\s*$", part).group(0)
                parts[i] = "" if done else lead + alias + "".join(ZW_TOKEN_RE.findall(part)) + trail
                done = True
            return "".join(parts)
        alias = self._alias(decode_name(raw, mode))
        if alias is None:
            return raw
        if mode in ("name", "smiley"):
            # The alias is shared; zero-width characters of the original stay, right after it.
            return alias + "".join(ZW_TOKEN_RE.findall(raw))
        return alias

    def _structural(self, s):
        """Replace the names of every DISCOVER position."""
        for _label, rx, group, mode in DISCOVER:
            def sub(m, group=group, mode=mode):
                raw = m.group(group)
                if mode == "same":
                    param, text = decode_name(m.group(1), "param"), decode_name(raw, "name")
                    if name_key(param) != name_key(text) and self.names.get(name_key(text)) != name_key(param):
                        return m.group(0)
                    mode = "name"
                start, end = m.start(group) - m.start(), m.end(group) - m.start()
                if mode == "param":
                    raw = param_value(raw, m.string[max(0, m.start(group) - 400):m.start(group)])
                    end = start + len(raw)
                return m.group(0)[:start] + self._rewrite(raw, mode) + m.group(0)[end:]
            s = rx.sub(sub, s)
        return s

    def _operators(self, s):
        for i, p in enumerate(self.config.pseudos):
            fake = "user%d" % (i + 1)
            s = self._rx(name_key(p)).sub(lambda m, f=fake: f + "".join(ZW_TOKEN_RE.findall(m.group(0))), s)
        return s

    def _free_sub(self, s):
        """Replace the free-text names in s (no URL handling)."""
        if not self.free:
            return s
        if self._free_rx is None:
            self._free_rx = self._regex_cache.get(frozenset(self.free))
        if self._free_rx is None:
            keys = sorted(self.free, key=len, reverse=True)
            bodies = [(_ZW_TOKEN + "*").join(_char_alts(c) for c in k) for k in keys]
            self._free_rx = re.compile(r"(?:(?<!\w)|(?<=%[0-9A-Fa-f]{2}))(?:" + "|".join(bodies)
                                       + r")(?!\w)", re.I)
            self._regex_cache[frozenset(self.free)] = self._free_rx

        def sub(m):
            got = m.group(0)
            norm = re.sub(r"\\u([0-9a-fA-F]{4})", lambda u: chr(int(u.group(1), 16)), got)
            key = name_key(html.unescape(urllib.parse.unquote_plus(norm)).replace("\xa0", " "))
            if key not in self.free:
                key = next(k for k in self.free if self._rx(k).fullmatch(got))
            fake = self._alias(key) if key not in self.names else self.names[key]
            return fake + "".join(ZW_TOKEN_RE.findall(got))
        return self._free_rx.sub(sub, s)

    def _free_text(self, s):
        """Replace the free-text names in a text node or text attribute; URLs in it as _free_urls."""
        out, pos = [], 0
        for u in URL_IN_TEXT_RE.finditer(s):
            out += [self._free_sub(s[pos:u.start()]), self._free_urls(u.group(0))]
            pos = u.end()
        return "".join(out) + self._free_sub(s[pos:])

    def _slug_sub(self, s):
        """Replace free-text names in a topic slug, where they are lower case with `-` separators."""
        key = ("slug", frozenset(self.free))
        if key not in self._regex_cache:
            forms = {}
            for k in self.free:
                form = slug_form(k)
                if len(form) >= MIN_FREE_TEXT_LEN:
                    forms.setdefault(form, k)
            rx = re.compile(r"(?<![a-z0-9])(%s)(?![a-z0-9])" % "|".join(
                re.escape(f) for f in sorted(forms, key=len, reverse=True)), re.I) if forms else None
            self._regex_cache[key] = (rx, forms)
        rx, forms = self._regex_cache[key]
        if rx is None:
            return s
        return rx.sub(lambda m: self.names.get(forms[m.group(1).lower()]) or self._alias(forms[m.group(1).lower()]), s)

    def _free_urls(self, s):
        """Free-text names inside internal topic slugs and external URLs of s."""
        if not self.free:
            return s
        s = SLUG_RE.sub(lambda m: m.group(1) + self._slug_sub(self._free_sub(m.group(2))) + m.group(3), s)
        return EXT_URL_RE.sub(lambda m: self._free_sub(m.group(0)), s)

    def _per_segment(self, text):
        """Operator pseudos in every value and text; free-text names in text nodes and text attributes."""
        if looks_json(text):
            key = [None]

            def jsub(m):
                if m.group(2):
                    key[0] = m.group(1)
                    return m.group(0)
                val = self._operators(m.group(1))
                val = self._free_urls(val) if key[0] in ("href", "tns3") else self._free_text(val)
                return '"%s"' % val
            return JSON_STR_RE.sub(jsub, text)
        out = []
        for kind, start, end in iter_segments(text):
            seg = text[start:end]
            if kind == "text":
                seg = self._free_text(self._operators(seg))
            elif kind == "raw":
                seg = self._operators(seg)
            else:
                name = re.match(r"</?[A-Za-z][\w:-]*", seg).group(0)

                def asub(a):
                    val = a.group(3)
                    q = val[0] if val[:1] in ("'", '"') else ""
                    inner = val[1:-1] if q else val
                    inner = self._operators(inner)
                    if a.group(1).lower() in TEXT_ATTRS:
                        inner = self._free_text(inner)
                    else:
                        inner = self._free_urls(inner)
                    return a.group(1) + a.group(2) + q + inner + q
                seg = name + ATTR_RE.sub(asub, seg[len(name):])
            out.append(seg)
        return "".join(out)

    def _secrets(self, s):
        """Tokens, cookies, e-mails, IPs, member ids and personal profile fields."""
        def inp(m):
            tag = m.group(0)
            if not _sensitive_input(tag):
                return tag
            return VALUE_RE.sub(lambda v: v.group(1) + (v.group(2) or "") + REDACTED + (v.group(2) or ""), tag, count=1)
        s = INPUT_RE.sub(inp, s)
        s = HASH_RE.sub(lambda m: m.group(1) + REDACTED if m.group(2) != REDACTED else m.group(0), s)
        s = COOKIE_RE.sub(
            lambda m: m.group(0) if m.group(2).lower() in COOKIE_OK else m.group(1) + "=" + REDACTED, s)
        for e in self.config.emails:
            s = re.sub(re.escape(e), EMAIL_PLACEHOLDER, s, flags=re.I)
        s = EMAIL_RE.sub(EMAIL_PLACEHOLDER, s)
        s = IP_RE.sub(lambda m: m.group(0) if m.group(0).startswith("192.0.2.") else IP_PLACEHOLDER, s)

        def fake_id(m):
            rid = m.group(2)
            if rid in self.ids.values():
                return m.group(0)
            if rid not in self.ids:
                own = len([p for p in self.config.profile_ids if p])
                self.ids[rid] = str(FAKE_ID_OTHER + len(self.ids) - own)
            return m.group(1) + self.ids[rid]
        for rx in ID_POSITIONS:
            s = rx.sub(fake_id, s)
        for i, pid in enumerate(self.config.profile_ids):
            if len(pid) >= MIN_BARE_ID_DIGITS:
                s = re.sub(r"(?<!\d)%s(?!\d)" % pid, str(FAKE_ID_OPERATOR + i), s)
        s = PERSONAL_SELECT_RE.sub(lambda m: m.group(1) + SELECTED_RE.sub("", m.group(2)) + m.group(3), s)
        return s

    def redact_text(self, s, free_text=False):
        """Redact a URL, a request body or a short text with the current tables (no markup handling)."""
        s = self._structural(s)
        s = self._operators(s)
        s = self._free_text(s) if free_text else self._free_urls(s)
        return self._secrets(s)

    def anonymize(self, text, private=False):
        """Return the anonymized page. Mapping of other members is consistent within this call."""
        self._reset()
        if private:
            parts, last = [], 0
            for start, end in _find_para_blocks(text):
                if start < last:
                    continue
                parts += [text[last:start], PRIVATE_PLACEHOLDER]
                last = end
                self.stats["private_blocks"] += 1
            text = "".join(parts) + text[last:]
            text = SUBJECT_RE.sub(lambda m: m.group(0) if KEEP_SUBJECT_RE.match(_strip_tags(m.group(2)))
                                  else m.group(1) + PRIVATE_SUBJECT + m.group(3), text)
        for open_re, placeholder in PERSONAL_BLOCKS:
            parts, last = [], 0
            for start, end in _find_para_blocks(text, open_re):
                if start < last:
                    continue
                parts += [text[last:start], placeholder]
                last = end
            text = "".join(parts) + text[last:]
        # Dropping `selected` from personal fields is an intended markup change too: do it first.
        text = PERSONAL_SELECT_RE.sub(lambda m: m.group(1) + SELECTED_RE.sub("", m.group(2)) + m.group(3), text)
        before = markup_signature(text)
        tokens = list(iter_tokens(text))
        self.learn(text, [(pos, dec) for pos, _p, _pl, dec, _m in tokens if dec is not None])
        # Obfuscated links: decode, redact, re-encode with the same prefix.
        out, last = [], 0
        for _pos, prefix, _payload, decoded, m in tokens:
            if decoded is None:
                self.stats["undecoded_tokens"] += 1
                continue
            out += [text[last:m.start()], prefix, encode_payload(self.redact_text(decoded))]
            last = m.end()
            self.stats["tokens"] += 1
        text = "".join(out) + text[last:]
        text = self._secrets(self._per_segment(self._structural(text)))
        after = markup_signature(text)
        if after != before:
            diff = next((i for i, (a, b) in enumerate(zip(before, after)) if a != b), min(len(before), len(after)))
            raise AnonymizeError("markup changed at tag #%d (%d tags before, %d after)" % (diff, len(before), len(after)))
        return text

    def anonymize_meta(self, meta):
        """Anonymize capture metadata with the tables of the page anonymized last (same aliases)."""
        def walk(v, key=None):
            if isinstance(v, dict):
                return {k: walk(x, k) for k, x in v.items()}
            if isinstance(v, list):
                return [walk(x, key) for x in v]
            if isinstance(v, str):
                return self.redact_text(v, free_text=key == "note")
            return v
        return walk(meta)

    # -- verification -----------------------------------------------------------
    def findings(self, text, private=False):
        """Return [(line, column, reason)] for every leak left in text (including decoded links).

        Never the offending value or its neighbourhood: CI logs are public and a neighbour may leak too."""
        self._reset()
        res = []

        def scan(chunk, base, where):
            def add(pos, reason, length=0):
                at = base + pos if where == "" else base
                res.append((line_of(text, at), column_of(text, at), reason + where))
            for p in self.config.pseudos:
                for m in self._rx(p).finditer(chunk):
                    add(m.start(), "real pseudo", len(m.group(0)))
            for e in self.config.emails:
                for m in re.finditer(re.escape(e), chunk, re.I):
                    add(m.start(), "operator e-mail")
            for m in EMAIL_RE.finditer(chunk):
                if m.group(0) != EMAIL_PLACEHOLDER:
                    add(m.start(), "e-mail address")
            for m in IP_RE.finditer(chunk):
                if not m.group(0).startswith("192.0.2."):
                    add(m.start(), "IP address")
            for m in HASH_RE.finditer(chunk):
                if m.group(2) != REDACTED:
                    add(m.start(), "hash_check value not REDACTED")
            for m in COOKIE_RE.finditer(chunk):
                if m.group(2).lower() not in COOKIE_OK:
                    add(m.start(), "cookie/session value (%s)" % m.group(1))
            for m in INPUT_RE.finditer(chunk):
                if _sensitive_input(m.group(0)):
                    add(m.start(), "hidden token input not REDACTED")
            for m in PROFIL_RE.finditer(chunk):
                if m.group(2) in self.config.profile_ids:
                    add(m.start(), "operator profile id")
            for pid in self.config.profile_ids:
                if len(pid) >= MIN_BARE_ID_DIGITS:
                    for m in re.finditer(r"(?<!\d)%s(?!\d)" % pid, chunk):
                        add(m.start(), "operator profile id (bare number)")
            for m in PERSONAL_SELECT_RE.finditer(chunk):
                if SELECTED_RE.search(m.group(2)):
                    add(m.start(), "personal profile field still selected")
            for name, pos, _mode in self.discover(chunk):
                key = name_key(name)
                if key not in NOT_A_MEMBER and not FAKE_NAME_RE.match(key) and len(name) <= 80:
                    add(pos, "member pseudo not anonymized", len(name))
        scan(text, 0, "")
        res += verify_structure(text)
        for pos, _prefix, _payload, decoded, _m in iter_tokens(text):
            if decoded is not None:
                scan(decoded, pos, " (in obfuscated link)")
        if private:
            for m in SUBJECT_RE.finditer(text):
                if not KEEP_SUBJECT_RE.match(_strip_tags(m.group(2))):
                    res.append((line_of(text, m.start()), column_of(text, m.start()), "private MP subject not replaced"))
            for start, end in _find_para_blocks(text):
                if _strip_tags(text[start:end]) != PRIVATE_PLACEHOLDER:
                    res.append((line_of(text, start), column_of(text, start), "private message body not replaced"))
        return sorted(set(res))

# -- independent structural verifier --------------------------------------------------------------
# Written apart from DISCOVER on purpose (DOM walk with html.parser, its own patterns): a member
# position the anonymizer misses is reported here. Every name found must be an alias (`userN`) or
# a known placeholder, every member id a fake one (9000NN / 9100NN).
# Each rule has its own label, reported in the finding ("structural check: <label> not aliased").
_V_IDS = {label: re.compile(rx) for label, rx in (
    ("member id profil-", r"profil-(\d+)"), ("member id adduser=", r"adduser=(\d+)"),
    ("member id id_user=", r"id_user=(\d+)"), ("member id avatar", r"mesdiscussions-(\d+)"),
    ("member id quotemsg", r"quotemsg=\d+,\d+,(\d+)\]"))}
_V_PARAM = re.compile(r"(?:^|[?&;/])(pseudo|spseudo|dest|auteur)=([^&#\"<>\n]{0,120})", re.I)
_V_SMILEY = re.compile(r"\[:([^\]\[]+?)(?::\d+)?\]")
_V_PERSO = re.compile(r"/images/perso/(?:\d+/)?([^/?#\"<>]+?)\.(?:gif|png|jpe?g)", re.I)
_V_ATTR_ONE = {label: re.compile(rx, re.I | re.S) for label, rx in (
    ("ignore list title", r"(?:Mettre|Enlever)\s+(.+?)\s+(?:en|de l')\s*ignore list"),
    ("MP to title", r"message privé à\s+(.+?)\s*$"),
    ("contact list title", r"Ajouter\s+(.+?)\s+à votre liste de contacts"),
    ("description author", r"Auteur\s*:\s*(.+?)\s+-\s+Page"))}
_V_ATTR_LIST = {label: re.compile(rx, re.I | re.S) for label, rx in (
    ("unread-by list", r"lu par\s*:\s*(.+)$"), ("recipients list", r"Message privé pour\s+(.+)$"))}
_V_TEXT_ONE = {label: re.compile(rx, re.I | re.S) for label, rx in (
    ("quote header", r"^\s*(.+?)\s+a écrit\s*:"), ("edit notice", r"édité par\s+(.+?)\s+le\s+\d"))}
_V_VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source",
           "track", "wbr"}


def allowed_name(name):
    """True for an alias (`user12`, zero-width characters allowed) or a placeholder."""
    key = name_key(name.replace("\xa0", " ").strip().rstrip("…").rstrip(".").strip())
    # `<target>` / `{dest}`: placeholders of a meta url_template.
    return key in NOT_A_MEMBER or bool(FAKE_NAME_RE.match(key) or re.fullmatch(r"<[\w-]+>|\{[\w-]+\}", key))


class StructuralVerifier(html.parser.HTMLParser):
    """Collects (line, column, reason) for every non-aliased name or real id in member positions."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.found = []
        self.stack = []

    # -- reporting
    def _bad(self, where, value, line=None):
        here = self.getpos()
        self.found.append((line or here[0], here[1] + 1 if line is None else 0, "structural check: %s not aliased" % where))

    def _name(self, where, value, line=None):
        if not allowed_name(value):
            self._bad(where, value, line)

    def check_value(self, s, line=None):
        """URL parameters, member ids and personal smileys in any attribute value or text."""
        for label, rx in _V_IDS.items():
            for m in rx.finditer(s):
                if not FAKE_ID_RE.match(m.group(1)):
                    self._bad(label, m.group(1), line)
        for m in _V_PARAM.finditer(s):
            value = m.group(2)
            if s[:m.start(2)].count("'") % 2:  # inside a JS single-quoted string
                value = value.split("'")[0]
            value = html.unescape(urllib.parse.unquote_plus(value))
            if value:
                self._name("URL parameter %s=" % m.group(1).lower(), value, line)
        for m in _V_SMILEY.finditer(s):
            self._name("personal smiley code", m.group(1), line)
        if "%5B%3A" in s.upper():
            for m in _V_SMILEY.finditer(urllib.parse.unquote_plus(s)):
                self._name("personal smiley code in URL", m.group(1), line)
        for m in _V_PERSO.finditer(s):
            self._name("personal smiley image", urllib.parse.unquote(m.group(1)), line)

    def _check_attr_text(self, s):
        for label, rx in _V_ATTR_ONE.items():
            for m in rx.finditer(s):
                self._name(label, m.group(1))
        for label, rx in _V_ATTR_LIST.items():
            for m in rx.finditer(s):
                for item in m.group(1).split(","):
                    if item.strip():
                        self._name(label, item)

    # -- DOM walk
    def _ctx(self, tag, cls):
        return any(e["tag"] == tag and cls in e["cls"] for e in self.stack)

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        cls = set(a.get("class", "").split())
        for k, v in a.items():
            self.check_value(v)
            if k in ("title", "alt", "content"):
                self._check_attr_text(v)
        for c in cls:
            for prefix in PREFIXES:
                if c.startswith(prefix):
                    decoded = decode_payload(c[len(prefix):])
                    if decoded:
                        self.check_value(decoded)
        if tag == "input" and a.get("name", "").lower() in ("pseudo", "spseudo", "dest", "auteur") and a.get("value"):
            self._name("pseudo input", a["value"])
        if tag in _V_VOID:
            return
        where = None
        href = a.get("href", "")
        if tag == "b" and "s2" in cls and self._ctx("td", "messCase1"):
            where = "post author"
        elif tag == "td" and cls & {"sujetCase6", "messCase1bis"}:
            where = "list author" if "sujetCase6" in cls else "form review author"
        elif tag == "b" and (self._ctx("a", "Tableau") or self._ctx("td", "sujetCase9")):
            where = "last poster"
        elif tag == "b" and self._ctx("td", "catCase3"):
            where = "home last poster"
        elif tag == "a" and "profil-" in href:
            where = "profile link text"
        elif tag == "a" and "Tableau" in cls and "dest=" in href:
            where = "MP link text"
        elif tag == "span" and cls & {"signature", "MoodStatus"}:
            where = "signature or mood"
        elif tag == "span" and "title" in a and self._ctx("td", "sujetCase6"):
            for item in a["title"].split(","):
                if item.strip():
                    self._name("MP correspondents", item)
        params = []
        if tag == "a":
            # A link to a member (profile, MP) whose text is an alias must carry the same alias.
            for m in _V_PARAM.finditer(href):
                value = m.group(2).split("'")[0] if href[:m.start(2)].count("'") % 2 else m.group(2)
                params.append(name_key(html.unescape(urllib.parse.unquote_plus(value)).strip()))
        self.stack.append({"tag": tag, "cls": cls, "where": where, "text": [], "line": self.getpos()[0],
                           "params": params})

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in _V_VOID and self.stack and self.stack[-1]["tag"] == tag:
            self._close(self.stack.pop())

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i]["tag"] == tag:
                while len(self.stack) > i:
                    self._close(self.stack.pop())
                return

    def _close(self, e):
        if e.get("params"):
            text = name_key("".join(e["text"]).strip())
            aliases = [m.group(0) for m in (re.match(r"user\d+", p) for p in e["params"]) if m]
            if FAKE_NAME_RE.match(text) and any(alias != text for alias in aliases):
                self.found.append((e["line"], 0, "structural check: link text alias differs from its parameter"))
        if e["where"]:
            text = "".join(e["text"]).strip()
            if e["where"] == "home last poster":
                text = re.sub(r"^par\s+", "", text)
            if e["where"] == "signature or mood":
                if text not in ("", "Signature removed.", "Mood removed."):
                    self._bad("signature or mood text", text, e["line"])
            elif text:
                self._name(e["where"], text, e["line"])

    def handle_data(self, data):
        for e in self.stack:
            if e["where"] or e.get("params"):
                e["text"].append(data)
        self.check_value(data)
        for label, rx in _V_TEXT_ONE.items():
            for m in rx.finditer(data):
                self._name(label, m.group(1))

    def close(self):
        super().close()
        while self.stack:
            self._close(self.stack.pop())


def _verify_json(text):
    try:
        doc = json.loads(text)
    except ValueError:
        return [(1, 0, "structural check: invalid JSON")]
    v = StructuralVerifier()

    def walk(o, key=None):
        if isinstance(o, dict):
            if key in ("author", "last_author") and isinstance(o.get("title"), str):
                v._name("REST %s" % key, o["title"], 1)
            for k, x in o.items():
                walk(x, k)
        elif isinstance(o, list):
            for x in o:
                walk(x, key)
        elif isinstance(o, str):
            v.check_value(o, 1)
    walk(doc)
    return v.found


def verify_structure(text):
    """Independent check of every member position (HTML or JSON); [] when clean."""
    if looks_json(text):
        return _verify_json(text)
    v = StructuralVerifier()
    v.feed(text)
    v.close()
    return v.found


def read_text(path):
    """Read a page as UTF-8, falling back to ISO-8859-1 (legacy: LoginService.swift:137-140)."""
    with open(path, "rb") as fh:
        raw = fh.read()
    try:
        return raw.decode("utf-8"), "utf-8"
    except UnicodeDecodeError:
        return raw.decode("latin-1"), "latin-1"


def cmd_anonymize(args):
    """CLI: anonymize one file, then verify the output."""
    anon = Anonymizer(Config.load(args.config))
    text, enc = read_text(args.input)
    try:
        out = anon.anonymize(text, private=args.private)
    except AnonymizeError as exc:
        _ui.ko("%s: %s; output NOT written" % (args.input, exc))
        return 1
    leaks = anon.findings(out, private=args.private)
    if leaks:
        for line, col, reason in leaks:
            _ui.ko("%s:%d:%d: %s" % (args.output, line, col, reason))
        _ui.ko("output NOT written: anonymization is incomplete")
        return 1
    with open(args.output, "w", encoding=enc, newline="") as fh:
        fh.write(out)
    s = anon.stats
    _ui.ok("%s -> %s (%d obfuscated links re-encoded, %d other members, %d private bodies)" % (
        args.input, args.output, s["tokens"], s["others"], s["private_blocks"]))
    if s["undecoded_tokens"]:
        _ui.warn("%d obfuscated token(s) could not be decoded and were left as is" % s["undecoded_tokens"])
    return 0


def corpus_entries(folder):
    """[(path, private)] for every capture of a corpus folder, from its <id>.meta.json files.

    Raises ValueError for a meta without a matching file or a capture file no meta describes."""
    entries, described = [], set()
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".meta.json"):
            continue
        meta_path = os.path.join(folder, name)
        with open(meta_path, encoding="utf-8") as fh:
            meta = json.load(fh)
        entries.append((meta_path, False))
        described.add(name)
        if meta.get("file"):
            path = os.path.join(folder, meta["file"])
            if not os.path.isfile(path):
                raise ValueError("%s: file %s is missing" % (name, meta["file"]))
            entries.append((path, bool(meta.get("private"))))
            described.add(meta["file"])
    orphans = [n for n in sorted(os.listdir(folder)) if n not in described and not n.endswith(".md")]
    if orphans:
        raise ValueError("files without a meta: %s" % ", ".join(orphans))
    return entries


def cmd_check(args):
    """CLI: verify files (or a whole corpus); exit non-zero when any file leaks."""
    anon = Anonymizer(Config.load(args.config) if args.config else Config())
    try:
        entries = corpus_entries(args.corpus) if args.corpus else [(f, args.private) for f in args.files]
    except (OSError, ValueError) as exc:
        _ui.ko(str(exc))
        return 1
    bad = 0
    for path, private in entries:
        try:
            text, _enc = read_text(path)
        except OSError as exc:
            _ui.ko("%s: %s" % (path, exc.strerror))
            bad += 1
            continue
        leaks = anon.findings(text, private=private)
        for line, col, reason in leaks:
            _ui.ko("%s:%d:%d: %s" % (path, line, col, reason))
        if leaks:
            bad += 1
        elif not args.quiet:
            _ui.ok("%s: clean" % path)
    if args.corpus:
        (_ui.ko if bad else _ui.ok)("%d of %d corpus files clean" % (len(entries) - bad, len(entries)))
    return 1 if bad else 0


def main(argv=None):
    """Entry point."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "check":
        p = argparse.ArgumentParser(prog="anonymize.py check", description="Verify anonymized files.")
        p.add_argument("--config", help="local JSON config: also look for the operator pseudos, e-mails, ids")
        p.add_argument("--private", action="store_true", help="also require message bodies to be replaced")
        p.add_argument("--corpus", help="check every capture of this folder (--private read from each meta)")
        p.add_argument("--quiet", action="store_true", help="print failures only")
        p.add_argument("files", nargs="*")
        args = p.parse_args(argv[1:])
        if bool(args.corpus) == bool(args.files):
            p.error("give either --corpus DIR or files")
        return cmd_check(args)
    p = argparse.ArgumentParser(prog="anonymize.py", description="Anonymize a captured HFR page.")
    p.add_argument("--config", required=True, help="local JSON config (git-ignored)")
    p.add_argument("--private", action="store_true", help="replace message bodies (private messages)")
    p.add_argument("input")
    p.add_argument("output")
    args = p.parse_args(argv)
    if os.path.abspath(args.input) == os.path.abspath(args.output):
        _ui.ko("input and output must differ")
        return 2
    return cmd_anonymize(args)


if __name__ == "__main__":
    sys.exit(main())
