"""Slide 6 of the weekly deck, "progress model": commits, PRs by step, state of each step.

Called by build.py (`data` while gathering, `slide` while rendering). Charts are inline SVG: no script, no network.
Nothing names or ranks a person.
"""
import html
import re
import subprocess
from collections import Counter, OrderedDict
from datetime import date, datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
import generate as G  # noqa: E402  (build.py puts tooling/roadmap on sys.path)

STEPS = ['Audit', 'M1', 'M2', 'M3', 'M4', 'M5']
OTHER = 'Infra / docs / captures'
STEP_COLORS = {'Audit': '#6b7685', 'M1': '#4f7cff', 'M2': '#8b5cf6', 'M3': '#14b8a6', 'M4': '#f59e0b', 'M5': '#ec4899', OTHER: '#cbd2dc'}
STEP_NAMES = {'Audit': 'Audit initial', 'M1': 'M1 · MVP', 'M2': 'M2 · Lecture et réponse', 'M3': 'M3 · Moteur', 'M4': 'M4 · Version finale', 'M5': 'M5 · Évolutions'}
# Priority order of the buckets: a lot counts in exactly the first one that fits.
BUCKETS = ['done', 'blocked', 'human', 'mac', 'low', 'ready']
BUCKET_COLORS = {'done': '#14b8a6', 'blocked': '#dc5a4a', 'human': '#f59e0b', 'mac': '#8b5cf6', 'low': '#cbd2dc', 'ready': '#4f7cff'}
BUCKET_NAMES = {'done': 'fait', 'blocked': 'bloqué (autres lots)', 'human': 'décision ou capture humaine', 'mac': 'macOS / Xcode requis',
                'low': 'basse priorité / hors parité', 'ready': 'prêt'}
LOT = re.compile(r'\bLOT-(\d{3})\b')
MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']


def step_of_lot(lot):
    """Audit is LOT-000..005 (Phase 0 of the ROADMAP: audit and tooling); every other lot has its milestone."""
    if G.n(lot) <= 5:
        return 'Audit'
    for m, ms in (('M1', G.M1), ('M2', G.M2), ('M3', G.M3), ('M4', G.M4), ('M5', G.M5)):
        if lot in ms:
            return m
    return None


def step_of_pr(p):
    """The first LOT-XXX of the title, else of the body; no lot means infra, docs or captures."""
    for text in (p.get('title') or '', p.get('body') or ''):
        m = LOT.search(text)
        if m and f'LOT-{m.group(1)}' in G.rows:
            return step_of_lot(f'LOT-{m.group(1)}') or OTHER
    return OTHER


def bucket(lot, labels):
    r = G.rows[lot]
    if G.done(lot):
        return 'done'
    n = r['issue']
    has_numeric_deps = bool(G.deps(r))
    capture = n in G.CAPTURE
    if 'status: blocked' in labels and has_numeric_deps and not capture:
        return 'blocked'
    if capture or 'status: needs-triage' in labels or ('status: blocked' in labels and not has_numeric_deps):
        return 'human'
    if 'host: mac' in labels:
        return 'mac'
    if lot in G.M5 or 'priority: low' in labels:
        return 'low'
    return 'ready'


def git_days():
    out = subprocess.run("git log origin/dev-swift --format=%cd --date=format:%Y-%m-%d", shell=True, capture_output=True, text=True,
                         cwd=HERE.parents[2]).stdout.split()
    return Counter(out)


def data(pulls, issues):
    """Numbers of the slide. `pulls`: merged PRs of dev-swift; `issues`: every issue (not PR) with its labels."""
    by_n = {i['number']: i for i in issues}
    # 1. commits per day, cumulative, from the first commit to today
    per_day = git_days()
    first = date.fromisoformat(min(per_day))
    today = datetime.now().date()
    cum, total, d = [], 0, first
    while d <= today:
        total += per_day.get(d.isoformat(), 0)
        cum.append((d.isoformat(), total))
        d += timedelta(days=1)
    # 2. merged PRs per bin (a day while the project is young, a week from 6 weeks on), stacked by step
    merged = [(date.fromisoformat(p['merged_at'][:10]), step_of_pr(p)) for p in pulls if p.get('merged_at')]
    start = min(x for x, _ in merged)
    weekly = (today - start).days >= 42
    key = (lambda x: x - timedelta(days=x.weekday())) if weekly else (lambda x: x)
    step = timedelta(days=7 if weekly else 1)
    bins = OrderedDict()
    b = key(start)
    while b <= today:
        bins[b.isoformat()] = Counter()
        b += step
    for x, s in merged:
        bins[key(x).isoformat()][s] += 1
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


def _line_chart(cum):
    W, H, L, B, T = 880, 300, 64, 44, 14
    ys = _ticks(cum[-1][1])
    top = ys[-1]
    px = lambda i: L + (W - L - 12) * i / max(1, len(cum) - 1)
    py = lambda v: T + (H - T - B) * (1 - v / top)
    s = f'<svg viewBox="0 0 {W} {H}" width="100%" role="img" aria-label="Commits cumulés sur dev-swift">'
    for v in ys:
        s += f'<line x1="{L}" x2="{W - 12}" y1="{py(v)}" y2="{py(v)}" stroke="#eceef2"/><text x="{L - 10}" y="{py(v) + 5}" text-anchor="end" font-size="14" fill="#6b7685">{v}</text>'
    every = max(1, len(cum) // 6)
    for i, (d, _) in enumerate(cum):
        if i % every == 0 and len(cum) - 1 - i >= every * 0.6 or i == len(cum) - 1:
            anchor = 'end' if i == len(cum) - 1 else 'middle'
            s += f'<text x="{px(i)}" y="{H - 20}" text-anchor="{anchor}" font-size="14" fill="#6b7685">{_day(d)}</text>'
    pts = ' '.join(f'{px(i):.1f},{py(v):.1f}' for i, (_, v) in enumerate(cum))
    s += f'<polyline points="{pts}" fill="none" stroke="#4f7cff" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/>'
    s += f'<circle cx="{px(len(cum) - 1)}" cy="{py(cum[-1][1])}" r="6" fill="#4f7cff"/><text x="{px(len(cum) - 1) - 10}" y="{py(cum[-1][1]) - 14}" text-anchor="end" font-size="20" font-weight="600" fill="#0f1720">{cum[-1][1]}</text>'
    s += f'<text x="{L + (W - L) / 2}" y="{H - 2}" text-anchor="middle" font-size="13" fill="#9aa4b2">date (jour du dernier commit de dev-swift)</text></svg>'
    return s


def _stacked(bins, weekly):
    W, H, L, B, T = 880, 300, 64, 44, 14
    order = STEPS + [OTHER]
    tot = {k: sum(v.values()) for k, v in bins.items()}
    ys = _ticks(max(tot.values()))
    top = ys[-1]
    py = lambda v: T + (H - T - B) * (1 - v / top)
    n = len(bins)
    slot = (W - L - 12) / n
    bw = min(46, slot * 0.7)
    s = f'<svg viewBox="0 0 {W} {H}" width="100%" role="img" aria-label="PR fusionnées par {"semaine" if weekly else "jour"}, par étape">'
    for v in ys:
        s += f'<line x1="{L}" x2="{W - 12}" y1="{py(v)}" y2="{py(v)}" stroke="#eceef2"/><text x="{L - 10}" y="{py(v) + 5}" text-anchor="end" font-size="14" fill="#6b7685">{v}</text>'
    for k, (b, c) in enumerate(bins.items()):
        x = L + slot * k + (slot - bw) / 2
        acc = 0
        for st in order:
            v = c.get(st, 0)
            if v:
                s += f'<rect x="{x:.1f}" y="{py(acc + v):.1f}" width="{bw:.1f}" height="{py(acc) - py(acc + v):.1f}" fill="{STEP_COLORS[st]}"/>'
                acc += v
        if tot[b]:
            s += f'<text x="{x + bw / 2:.1f}" y="{py(acc) - 6:.1f}" text-anchor="middle" font-size="13" font-weight="600" fill="#0f1720">{tot[b]}</text>'
        if n <= 16 or k % 2 == 0:
            s += f'<text x="{x + bw / 2:.1f}" y="{H - 22}" text-anchor="middle" font-size="13" fill="#6b7685">{b[8:10]}/{b[5:7]}</text>'
    s += f'<text x="{L + (W - L) / 2}" y="{H - 2}" text-anchor="middle" font-size="13" fill="#9aa4b2">{"semaine (lundi)" if weekly else "jour de fusion"}</text></svg>'
    return s


def _donut(step, counts):
    total = sum(counts.values())
    r, sw, c = 68, 30, 2 * 3.14159265 * 68
    s = f'<svg viewBox="0 0 180 180" width="170" height="170" role="img" aria-label="{html.escape(STEP_NAMES[step])}"><g transform="rotate(-90 90 90)">'
    off = 0.0
    for bk in BUCKETS:
        v = counts.get(bk, 0)
        if v:
            ln = c * v / total
            s += f'<circle cx="90" cy="90" r="{r}" fill="none" stroke="{BUCKET_COLORS[bk]}" stroke-width="{sw}" stroke-dasharray="{ln:.2f} {c - ln:.2f}" stroke-dashoffset="{-off:.2f}"/>'
            off += ln
    done = counts.get('done', 0)
    s += f'</g><text x="90" y="92" text-anchor="middle" font-size="28" font-weight="300" fill="#0f1720">{round(100 * done / total) if total else 0} %</text>'
    s += f'<text x="90" y="114" text-anchor="middle" font-size="14" fill="#6b7685">{done} / {total}</text></svg>'
    lines = ''.join(f'<li><i style="background:{BUCKET_COLORS[bk]}"></i>{counts[bk]}<span>{BUCKET_NAMES[bk].split(" (")[0].split(" /")[0]}</span></li>' for bk in BUCKETS if counts.get(bk))
    return f'<div class="dn"><b>{html.escape(STEP_NAMES[step])}</b>{s}<ul>{lines}</ul></div>'


CSS = """
.pm{display:flex;flex-direction:column;gap:22px;justify-content:center}
.pm .two{display:grid;grid-template-columns:1fr 1fr;gap:72px}
.pm .lbl{margin-bottom:6px}
.pm .leg{display:flex;flex-wrap:wrap;gap:6px 18px;font-size:13px;color:var(--mute);margin-top:2px}
.pm .leg i,.pm .dn li i{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:6px;vertical-align:-1px}
.pm .donuts{display:grid;grid-template-columns:repeat(6,1fr);gap:16px;margin-top:4px}
.pm .dn{text-align:center}.pm .dn b{display:block;font-size:16px;font-weight:600;margin-bottom:2px}
.pm .dn ul{list-style:none;text-align:left;margin:0 auto;width:max-content;max-width:100%}
.pm .dn li{font-size:13px;line-height:1.35;color:var(--ink)}.pm .dn li span{color:var(--mute);margin-left:6px}
.pm .note{font-size:12.5px;line-height:1.45;color:var(--faint);border-top:1px solid var(--line);padding-top:10px}
"""


def slide(D, page):
    P = D['progress']
    legend_steps = ''.join(f'<span><i style="background:{STEP_COLORS[s]}"></i>{html.escape(STEP_NAMES.get(s, s))}</span>' for s in STEPS + [OTHER])
    legend_buckets = ''.join(f'<span><i style="background:{BUCKET_COLORS[b]}"></i>{BUCKET_NAMES[b]}</span>' for b in BUCKETS)
    inner = f"""<style>{CSS}</style><div class="pm">
<div class="two">
<div><div class="lbl">Commits cumulés sur dev-swift</div>{_line_chart(P['cum'])}</div>
<div><div class="lbl">PR fusionnées par {'semaine' if P['weekly'] else 'jour'}, par étape</div>{_stacked(P['bins'], P['weekly'])}<div class="leg">{legend_steps}</div></div>
</div>
<div><div class="lbl">État des lots de chaque étape</div>
<div class="donuts">{''.join(_donut(s, P['steps'][s]) for s in STEPS)}</div><div class="leg" style="justify-content:center;margin-top:8px">{legend_buckets}</div></div>
<p class="note">Lecture : un lot compte dans une seule catégorie, la première qui convient dans l'ordre fait &gt; bloqué &gt; humain &gt; macOS &gt; basse priorité &gt; prêt.
Bloqué : <code>status: blocked</code> avec des dépendances numériques, hors capture. Humain : attend une capture, une décision (phrase-barrière, <code>needs-triage</code>), une clé ou un réglage.
macOS : <code>host: mac</code>. Basse priorité : lot de M5 ou <code>priority: low</code>. Les lots fermés « not planned » sont exclus. L'étape Audit regroupe LOT-000 à 005 ; une PR va à l'étape du premier LOT-XXX de son titre (sinon de son corps), et sans lot à « {OTHER} ».</p>
</div>"""
    return page(6, "Le <b>modèle de progression</b>", "Le rythme du chantier et l'état de chaque grande étape, de l'audit initial à M5.", inner, D)
