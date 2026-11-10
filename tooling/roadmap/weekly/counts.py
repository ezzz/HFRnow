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
