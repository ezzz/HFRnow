"""The progress model of the weekly KPI slide: commits, PRs by step, state of each step (`data`, `charts`, `donuts`).

Called by build.py (`data` while gathering, `charts` and `donuts` while rendering). Charts are inline SVG: no script, no network.
Nothing names or ranks a person.
"""
import html
import re
import subprocess
from collections import Counter, OrderedDict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
import generate as G  # noqa: E402  (build.py puts tooling/roadmap on sys.path)

STEPS = ['Audit', 'M1', 'M2', 'M3', 'M4', 'M5']
OTHER = 'Infra / docs / captures'
STEP_COLORS = {'Audit': '#6b7685', 'M1': '#4f7cff', 'M2': '#8b5cf6', 'M3': '#14b8a6', 'M4': '#f59e0b', 'M5': '#ec4899', OTHER: '#cbd2dc'}
STEP_NAMES = {'Audit': 'Audit initial', 'M1': 'M1 · MVP', 'M2': 'M2 · Lecture et réponse', 'M3': 'M3 · Moteur', 'M4': 'M4 · Version finale', 'M5': 'M5 · Évolutions'}
# Priority order of the buckets: a lot counts in exactly the first one that fits.
BUCKETS = ['done', 'progress', 'blocked', 'human', 'mac', 'low', 'ready']
BUCKET_COLORS = {'done': '#14b8a6', 'progress': '#7dd3fc', 'blocked': '#dc5a4a', 'human': '#f59e0b', 'mac': '#8b5cf6', 'low': '#cbd2dc', 'ready': '#4f7cff'}
BUCKET_NAMES = {'done': 'fait', 'progress': 'en cours (réclamé ou PR ouverte)', 'blocked': 'bloqué (autres lots)', 'human': 'décision humaine requise', 'mac': 'macOS / Xcode requis (capture ou Mac seul)',
                'low': 'basse priorité / hors parité', 'ready': 'prêt'}
LOT = re.compile(r'\bLOT-(\d{3})\b')
MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']


def step_of_lot(lot):
    """Audit is LOT-000..005 (the audit and tooling lots of Phase 0, ROADMAP); they leave M1 here, every other lot keeps its milestone."""
    if G.n(lot) <= 5:
        return 'Audit'
    for m, ms in (('M1', G.M1), ('M2', G.M2), ('M3', G.M3), ('M4', G.M4), ('M5', G.M5)):
        if lot in ms:
            return m
    return None


def step_of_pr(p):
    """The first LOT-XXX of the title, else of the body; no lot means infra, docs or captures."""
    for text in (p.get('title') or '', p.get('body') or ''):
        for m in LOT.finditer(text):
            if f'LOT-{m.group(1)}' in G.rows:  # a number that is not a lot of the plan is skipped
                return step_of_lot(f'LOT-{m.group(1)}') or OTHER
    return OTHER


def bucket(lot, labels):
    """The first bucket that fits, in the order of BUCKETS (operator decisions 2026-11-06, #368)."""
    r = G.rows[lot]
    if G.done(lot):
        return 'done'
    n = r['issue']
    if n in G.CLAIMED or lot in G.PRS:  # claimed, or an open PR names the lot: it is being worked on, whatever its host
        return 'progress'
    capture = n in G.CAPTURE
    if 'status: blocked' in labels and G.miss0(r) and not capture:  # waits on a lot of the plan that is not done
        return 'blocked'
    # a triage, or a block with no lot left to wait for (gate sentence, M5 not open, a decision, a key or a setting) needs a human
    if 'status: needs-triage' in labels or ('status: blocked' in labels and not capture):
        return 'human'
    # only the Mac can do it: a capture, or a `host: mac` lot the cloud may not code (the cloud codes the App lots of M2, 2026-11-05)
    if capture or ('host: mac' in labels and not (r['module'] == 'App' and step_of_lot(lot) == 'M2')):
        return 'mac'
    if lot in G.M5 or 'priority: low' in labels:
        return 'low'
    return 'ready'


def git_days():
    out = subprocess.run("TZ=UTC git log origin/dev-swift --format=%cd --date=format-local:%Y-%m-%d", shell=True, capture_output=True, text=True,
                         cwd=HERE.parents[2]).stdout.split()  # UTC days, like the PR timestamps
    return Counter(out)


WEEKLY_FROM_DAYS = 21  # daily bars up to three weeks of history, weekly bars after


def data(pulls, issues, per_day=None, today=None):
    """Numbers of the slide. `pulls`: merged PRs of dev-swift; `issues`: every issue (not PR) with its labels.
    `per_day` (commits per UTC day) and `today` are injectable for the tests."""
    by_n = {i['number']: i for i in issues}
    per_day = git_days() if per_day is None else per_day
    merged = [(date.fromisoformat(p['merged_at'][:10]), step_of_pr(p)) for p in pulls if p.get('merged_at')]
    # today is the UTC day, never before the last commit or merge seen (a runner behind UTC must not drop them)
    today = today or datetime.now(timezone.utc).date()
    seen = [date.fromisoformat(d) for d in per_day] + [x for x, _ in merged]
    today = max([today] + seen)
    # 1. commits per day, cumulative, from the first commit to today
    cum = []
    if per_day:
        total, d = 0, date.fromisoformat(min(per_day))
        while d <= today:
            total += per_day.get(d.isoformat(), 0)
            cum.append((d.isoformat(), total))
            d += timedelta(days=1)
    # 2. merged PRs per bin (a day while the project is young, a week after), stacked by step
    bins = OrderedDict()
    weekly = False
    if merged:
        start = min(x for x, _ in merged)
        weekly = (today - start).days >= WEEKLY_FROM_DAYS
        key = (lambda x: x - timedelta(days=x.weekday())) if weekly else (lambda x: x)
        step = timedelta(days=7 if weekly else 1)
        b = key(start)
        while b <= today:
            bins[b.isoformat()] = Counter()
            b += step
        for x, s in merged:
            bins.setdefault(key(x).isoformat(), Counter())[s] += 1
    # 3. state of each step: lots counted in exactly one bucket (dropped lots, closed not planned, are left out)
    steps = {s: Counter() for s in STEPS}
    for lot in G.rows:
        i = by_n.get(G.rows[lot]['issue'])
        if i and i['state'] == 'closed' and i.get('state_reason') not in (None, 'completed'):
            continue
        s = step_of_lot(lot)
        if s:
            labels = {x['name'] for x in (i or {}).get('labels', [])}
            steps[s][bucket(lot, labels)] += 1
    return {'cum': cum, 'weekly': weekly, 'bins': {k: dict(v) for k, v in bins.items()}, 'steps': {s: dict(v) for s, v in steps.items()}}


def _day(s):
    y, m, d = map(int, s.split('-'))
    return f'{d} {MONTHS[m - 1]}'


def _ticks(mx, n=4):
    step = max(1, -(-mx // n))
    mag = 10 ** (len(str(step)) - 1)
    step = -(-step // mag) * mag
    return list(range(0, mx + step, step))


FS = 20  # smallest text of the deck, in px at the 1920 base (operator, 2026-11-10): the charts are drawn at 1:1


def _empty(msg, W=520, H=250):
    return f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}"><text x="{W / 2}" y="{H / 2}" text-anchor="middle" font-size="{FS}" fill="#9aa4b2">{msg}</text></svg>'


def _grid(ys, py, L, W):
    return ''.join(f'<line x1="{L}" x2="{W - 4}" y1="{py(v):.1f}" y2="{py(v):.1f}" stroke="#eceef2"/><text x="{L - 10}" y="{py(v) + 7:.1f}" text-anchor="end" font-size="{FS}" fill="#6b7685">{v}</text>' for v in ys)


def _line_chart(cum, W=520, H=250):
    if not cum:
        return _empty('Aucun commit', W, H)
    L, B, T = 58, 38, 14
    ys = _ticks(cum[-1][1])
    top = ys[-1]
    px = lambda i: L + (W - L - 8) * i / max(1, len(cum) - 1)
    py = lambda v: T + (H - T - B) * (1 - v / top)
    s = f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Commits cumulés sur dev-swift">' + _grid(ys, py, L, W)
    every = max(1, -(-len(cum) // 4))
    for i, (d, _) in enumerate(cum):
        if (i % every == 0 and len(cum) - 1 - i >= every * 0.7) or i == len(cum) - 1:
            anchor = 'end' if i == len(cum) - 1 else ('start' if i == 0 else 'middle')
            s += f'<text x="{px(i):.1f}" y="{H - 6}" text-anchor="{anchor}" font-size="{FS}" fill="#6b7685">{_day(d)}</text>'
    pts = ' '.join(f'{px(i):.1f},{py(v):.1f}' for i, (_, v) in enumerate(cum))
    area = f'{L},{py(0):.1f} ' + pts + f' {px(len(cum) - 1):.1f},{py(0):.1f}'
    s += f'<defs><linearGradient id="la" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4f7cff" stop-opacity=".18"/><stop offset="1" stop-color="#4f7cff" stop-opacity="0"/></linearGradient></defs><polygon points="{area}" fill="url(#la)"/>'
    s += f'<polyline points="{pts}" fill="none" stroke="#4f7cff" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/>'
    s += f'<circle cx="{px(len(cum) - 1):.1f}" cy="{py(cum[-1][1]):.1f}" r="6" fill="#4f7cff"/><text x="{px(len(cum) - 1) - 12:.1f}" y="{py(cum[-1][1]) + 6:.1f}" text-anchor="end" font-size="24" font-weight="600" fill="#0f1720">{cum[-1][1]}</text></svg>'
    return s


def _stacked(bins, weekly, W=520, H=250):
    if not bins:
        return _empty('Aucune PR fusionnée', W, H)
    L, B, T = 50, 38, 26
    order = STEPS + [OTHER]
    tot = {k: sum(v.values()) for k, v in bins.items()}
    ys = _ticks(max(tot.values()))
    top = ys[-1]
    py = lambda v: T + (H - T - B) * (1 - v / top)
    n = len(bins)
    slot = (W - L - 4) / n
    bw = min(40, slot * 0.72)
    lab_every = max(1, -(-60 // int(slot)))  # a « 24/10 » label is about 55 px wide at 20 px
    s = f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="PR fusionnées par {"semaine" if weekly else "jour"}, par étape">' + _grid(ys, py, L, W)
    for k, (b, c) in enumerate(bins.items()):
        x = L + slot * k + (slot - bw) / 2
        acc = 0
        for st in order:
            v = c.get(st, 0)
            if v:
                s += f'<rect x="{x:.1f}" y="{py(acc + v):.1f}" width="{bw:.1f}" height="{py(acc) - py(acc + v):.1f}" fill="{STEP_COLORS[st]}"/>'
                acc += v
        if tot[b] and (slot >= 26 or tot[b] == max(tot.values())):
            s += f'<text x="{x + bw / 2:.1f}" y="{py(acc) - 6:.1f}" text-anchor="middle" font-size="{FS}" font-weight="600" fill="#0f1720">{tot[b]}</text>'
        if (n - 1 - k) % lab_every == 0:
            s += f'<text x="{x + bw / 2:.1f}" y="{H - 6}" text-anchor="middle" font-size="{FS}" fill="#6b7685">{int(b[8:10])}/{int(b[5:7])}</text>'
    return s + '</svg>'


SHORT_BUCKET = {'done': 'fait', 'progress': 'en cours', 'blocked': 'bloqué', 'human': 'humain', 'mac': 'macOS', 'low': 'basse prio.', 'ready': 'prêt'}


def _donut(step, counts):
    total = sum(counts.values())
    r, sw, c = 43, 15, 2 * 3.14159265 * 43
    s = f'<svg viewBox="0 0 108 108" width="108" height="108" role="img" aria-label="{html.escape(STEP_NAMES[step])}"><g transform="rotate(-90 54 54)"><circle cx="54" cy="54" r="{r}" fill="none" stroke="#f1f3f6" stroke-width="{sw}"/>'
    off = 0.0
    for bk in BUCKETS:
        v = counts.get(bk, 0)
        if v:
            ln = c * v / total
            s += f'<circle cx="54" cy="54" r="{r}" fill="none" stroke="{BUCKET_COLORS[bk]}" stroke-width="{sw}" stroke-dasharray="{ln:.2f} {c - ln:.2f}" stroke-dashoffset="{-off:.2f}"/>'
            off += ln
    done = counts.get('done', 0)
    s += f'</g><text x="54" y="61" text-anchor="middle" font-size="21" font-weight="500" fill="#0f1720">{round(100 * done / total) if total else 0} %</text></svg>'
    lines = ''.join(f'<li><i style="background:{BUCKET_COLORS[bk]}"></i><b>{counts[bk]}</b> {SHORT_BUCKET[bk]}</li>' for bk in BUCKETS if counts.get(bk))
    return f'<div class="dn"><div class="dh"><b>{html.escape(step if step != "Audit" else "Audit")}</b><span>{done} / {total}</span></div>{s}<ul>{lines}</ul></div>'


CSS = """
.pm .dn{display:grid;grid-template-columns:108px 1fr;grid-template-rows:auto 1fr;gap:4px 16px;align-items:start}
.pm .dn .dh{grid-column:1 / 3;display:flex;justify-content:space-between;align-items:baseline;font-size:22px}
.pm .dn .dh b{font-weight:600}.pm .dn .dh span{color:var(--mute);font-size:20px}
.pm .dn ul{list-style:none;font-size:20px;line-height:1.3;color:var(--mute);align-self:center;white-space:nowrap}
.pm .dn li b{color:var(--ink);font-weight:600}
.pm .leg{display:flex;flex-wrap:wrap;gap:4px 18px;font-size:20px;color:var(--mute);margin-top:8px}
.pm i{display:inline-block;width:14px;height:14px;border-radius:4px;margin-right:8px;vertical-align:-1px}
"""


def charts(D):
    """The two charts of the KPI slide, each in its card: cumulative commits and merged PRs per bin, by step."""
    P = D['progress']
    short = {'Audit': 'Audit', 'M1': 'M1', 'M2': 'M2', 'M3': 'M3', 'M4': 'M4', 'M5': 'M5', OTHER: 'infra, docs'}
    legend = ''.join(f'<span><i style="background:{STEP_COLORS[s]}"></i>{short[s]}</span>' for s in STEPS + [OTHER] if any(s in b for b in P['bins'].values()))
    line = f'<div class="card pm"><div class="ch">Commits cumulés</div>{_line_chart(P["cum"])}</div>'
    bars = f'<div class="card pm"><div class="ch">PR fusionnées par {"semaine" if P["weekly"] else "jour"}, par étape</div>{_stacked(P["bins"], P["weekly"])}<div class="leg">{legend}</div></div>'
    return line, bars


def donuts(D):
    """One donut per step: a lot counts in exactly one bucket (done > in progress > blocked > human > macOS > low > ready)."""
    P = D['progress']
    return f'<style>{CSS}</style><div class="card pm donuts">{"".join(_donut(s, P["steps"][s]) for s in STEPS)}</div>'
