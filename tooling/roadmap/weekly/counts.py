"""Pure helpers of the weekly deck: counts read from the docs and the tracker, and their French formatting.

No network, no import of `generate` (which reads state.json at import time): the tests import this module directly.
"""
import re
from datetime import datetime, timezone

CI_CAP = 2500  # the Actions runs API stops counting here (total_count of `actions/runs` is capped, seen 2026-11-10)
STATE_MAX_AGE_H = 6  # an older state.json makes the donuts lie (M2 shown 2/28 when it was 28/28): refuse it
# Issue labels and title prefixes of the « app au quotidien » counts (operator, 2026-11-10). The credit label
# `moust4ki aka bybifok finding` credits planned lots: it is never counted as test feedback.
FEEDBACK_LABEL = 'beta-test finding'
BACKPORT_LABEL = 'origin: legacy-evolution'
CURRENT_APP_PREFIX = '[Legacy'


def fr_num(n):
    return f'{n:,}'.replace(',', ' ')


def fmt_ci(n, cap=CI_CAP):
    """A count of the Actions API in French; at the cap the real number is unknown, so « 2 500+ »."""
    return f'{fr_num(cap)}+' if n >= cap else fr_num(n)


def gap_total(text):
    """The Total row of the `## Counts` table of GAP-LEGACY-VS-SWIFT.md (`| **Total** | **172** |`)."""
    sec = re.search(r'^## Counts\s*\n(.*?)(?=^## |\Z)', text, re.S | re.M)
    m = re.search(r'^\|\s*\**Total\**\s*\|\s*\**(\d+)\**\s*\|', sec.group(1) if sec else '', re.M)
    if not m:
        raise ValueError('GAP report: no Total row in its ## Counts table')
    return int(m.group(1))


def changelog_rows(text):
    """Entries of CHANGELOG-LEGACY.md: the table rows whose first cell is a number (header and separator excluded)."""
    return len(re.findall(r'^\|\s*\d+\s*\|', text, re.M))


def marketing_version(pbxproj):
    """MARKETING_VERSION of the app target (every build configuration carries the same one)."""
    found = sorted(set(re.findall(r'MARKETING_VERSION = ([^;]+);', pbxproj)))
    return ' / '.join(v.strip().strip('"') for v in found) or '?'


def state_age_hours(generated_at, now=None):
    """Age of a state.json snapshot (`2026-11-10 22:40 UTC`); an unreadable stamp counts as infinitely old."""
    try:
        t = datetime.strptime(generated_at, '%Y-%m-%d %H:%M UTC').replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return float('inf')
    return ((now or datetime.now(timezone.utc)) - t).total_seconds() / 3600


def labels(i):
    return {x['name'] if isinstance(x, dict) else x for x in i.get('labels') or []}


def daily_groups(issues):
    """Issues of the three « app au quotidien » cards: test feedback, fixes of the current app, backports into Swift."""
    return {
        'feedback': [i for i in issues if FEEDBACK_LABEL in labels(i)],
        'current': [i for i in issues if (i.get('title') or '').startswith(CURRENT_APP_PREFIX)],
        'backport': [i for i in issues if BACKPORT_LABEL in labels(i)],
    }


def open_closed(items):
    o = sum(1 for i in items if i['state'] == 'open')
    return o, len(items) - o


def clean_title(t, k=64):
    """A tracker title made short for a slide: no `[SwiftHFR]`-style prefix, no trailing parenthesis (milestone, who
    reported it, dates), no « as legacy … » tail, and the legacy app named « l'app courante » (operator, 2026-11-10)."""
    t = re.sub(r'^(\[[^\]]*\]\s*)+', '', t or '')
    t = re.sub(r'^(LOT-\d{3}|M\d):\s*', '', t)
    t = re.sub(r'(\s*\([^()]*\))+\s*$', '', t)
    t = re.sub(r',?\s+as (in )?legacy\b[^,;:]*', '', t, flags=re.I)
    t = re.sub(r'^legacy\b', "App courante", t, flags=re.I)
    t = re.sub(r'\blegacy\b', "app courante", t, flags=re.I)
    t = t.strip(' ,;:')
    return t if len(t) <= k else t[:k - 1].rsplit(' ', 1)[0].rstrip(' ,;:') + '…'


def dropped_issues(issues):
    """Issues closed as not planned or duplicate: their lots leave every count of the deck (a dropped lot is not planned)."""
    return {i['number'] for i in issues if i['state'] == 'closed' and i.get('state_reason') not in (None, 'completed')}


def live_lots(lots, rows, dropped):
    """The lots of `lots` whose issue is not in `dropped` (closed not planned or duplicate): the only ones any slide counts or lists."""
    return {l for l in lots if rows[l]['issue'] not in dropped}


# ---------------------------------------------------------------- slides 3, 5 and 6 (#892)

# Axes of the two radars (where test feedback concentrates, slide 5; the M5 categories, slide 6), in drawing order.
AXES = ['lecteur', 'listes', 'composer', 'MP', 'navigation', 'réglages et thèmes', 'performance', 'autre']
# Performance is read on the whole title first (« Reader: messages load very slowly » is a speed problem, not a reader
# one). Otherwise the axis is the one whose pattern matches earliest in the subject, the text before the first « : »
# (« MP list: … », « Réglages › Stockage MP: … »), then in the whole title when the subject says nothing; on a tie the
# first rule of AXIS_RULES wins.
PERF = re.compile(r'\b(slow\w*|freez\w*|hangs?|hang reports?|crash\w*|instabilit\w*|performance|speed|stuck|timeouts?|latency)\b', re.I)
AXIS_RULES = [
    ('MP', r'\b(mps?|private messages?|dark topics)\b'),
    ('composer', r'\b(composer|repl(y|ies)|r[ée]ponse|smileys?|gifs?|emoji|formatting|reply button|quote (selection|tray)|preview before send|drafts?)\b'),
    ('réglages et thèmes', r'\b(r[ée]glages|settings?|th[eè]mes?|app icon|icons?|contrast|density|text size|appearance|accent|colou?rs?|tints?|cache clearing)\b'),
    ('navigation', r'\b(tab bar|top bar|navigation|ipad|iphone duo|cover screen|account menu|home|universal links?|state restoration|'
                   r'keyboard shortcuts|page (navigator|scrubber)|app intent|spotlight|session expiry|widgets?|live activities|macos)\b'),
    ('listes', r'\b(lists?|topic rows?|cat[ée]gories|filters?|favou?rites?|pager|paged|swipes?|bookmarks|nouveau)\b'),
    ('lecteur', r'\b(reader|signatures?|images?|vid[ée]os?|polls?|quotes?|posts?|gallery|offline|scrolling)\b'),
]
PREFIX = re.compile(r'^\s*(\[[^\]]*\]\s*|(LOT-\d{3}|M[1-5]( study)?|Experimental|Fix|check and fix)\s*[:·]\s*)', re.I)


def subject(title):
    """The title without its `[SwiftHFR]`, `LOT-123:`, `M5:` or `Experimental:` prefixes."""
    t = title or ''
    while (m := PREFIX.match(t)):
        t = t[m.end():]
    return t.strip()


def axis_of(title):
    """The radar axis of an issue, from its title (AXIS_RULES); `autre` when nothing matches."""
    t = subject(title)
    if PERF.search(t):
        return 'performance'
    for text in (t.split(':', 1)[0], t):
        hits = [(m.start(), k) for k, (_, rx) in enumerate(AXIS_RULES) if (m := re.search(rx, text, re.I))]
        if hits:
            return AXIS_RULES[min(hits)[1]][0]
    return 'autre'


MS_TAG = re.compile(r'^M([1-5])\b|\((?:[^()]*,\s*)?M([1-5])\)')
LOT_TAG = re.compile(r'\bLOT-(\d{3})\b')
REVIEW_PREFIX = 'm4-review: '
EXPERIMENTAL = 'experimental'


def is_swift_issue(i):
    """A SwiftHFR issue: not a pull request, not an issue of the current app alone (`[Legacy …]` without SwiftHFR in the
    title), not a `type: roadmap` tracker, and not closed as not planned or duplicate."""
    t = i.get('title') or ''
    if 'pull_request' in i or 'type: roadmap' in labels(i):
        return False
    if t.startswith(CURRENT_APP_PREFIX) and 'SwiftHFR' not in t:
        return False
    return not (i['state'] == 'closed' and i.get('state_reason') not in (None, 'completed'))


def issue_milestone(i, lot_ms, followups=None, lot_of_number=None):
    """The milestone of an issue, or None: the first rule that applies.
    1. a lot issue: its lot's milestone (`lot_ms`, issue number -> M1..M5);
    2. a follow-up of the UX decisions (`followups`, m5.FOLLOWUPS): its milestone;
    3. the title names one: `M4: …`, `(M4)`, `(UXD-03, M2)`;
    4. the title names a lot of the plan (`LOT-097 renderer: …`): that lot's milestone (`lot_of_number`, 97 -> issue);
    5. labels: an end-of-M4 review finding (`m4-review: …`) or test feedback (`beta-test finding`) is M4, an
       `experimental` option is M5 (AGENTS.md §7)."""
    n = i['number']
    if n in lot_ms:
        return lot_ms[n]
    if followups and n in followups:
        return followups[n][0]
    t = re.sub(r'^(\[[^\]]*\]\s*)+', '', i.get('title') or '')
    m = MS_TAG.search(t)
    if m:
        return 'M' + (m.group(1) or m.group(2))
    for x in LOT_TAG.finditer(t):
        k = (lot_of_number or {}).get(int(x.group(1)))
        if k in lot_ms:
            return lot_ms[k]
    ls = labels(i)
    if FEEDBACK_LABEL in ls or any(x.startswith(REVIEW_PREFIX) for x in ls):
        return 'M4'
    if EXPERIMENTAL in ls:
        return 'M5'
    return None


def issue_status(i):
    """`fait` (closed as completed), `écarté` (closed otherwise), `réclamé` (open, `status: claimed`) or `ouvert`."""
    if i['state'] == 'closed':
        return 'fait' if i.get('state_reason') in (None, 'completed') else 'écarté'
    return 'réclamé' if 'status: claimed' in labels(i) else 'ouvert'


def feedback(issues):
    """Test feedback only: the `beta-test finding` label, never the credit label (README, counts)."""
    return [i for i in issues if FEEDBACK_LABEL in labels(i)]


def axis_counts(issues):
    c = {a: 0 for a in AXES}
    for i in issues:
        c[axis_of(i.get('title'))] += 1
    return c
