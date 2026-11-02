"""Weekly deck: 5 slides (HTML) from the tracker and git. Never posted anywhere; delivered to the maintainer only.

  python3 tooling/roadmap/weekly/build.py OUTDIR [--since 2026-10-28]   # needs `gh`, git history (not shallow), state.json
  node tooling/roadmap/weekly/shot.js OUTDIR                             # slides/*.html -> 2880x1620 JPEG

Slides: 1 progress + commits per day · 2 difference with the baseline date · 3 orchestration changes (text below)
· 4 and 5 state of M1..M4: blockers, cloud enablers, Mac bottlenecks. Nothing names or ranks a person.
"""
import html
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import generate as G  # noqa: E402  (loads lots.json and state.json)
from sync_state import REPO, gh_pages  # noqa: E402

MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']
# Open Mac checks that gate a milestone but are not lots
EXTRA_MAC = {'M1': [344, 322]}
# Slide 3 text for this first issue (edit each week; describe functions, never people)
ORCH = [
    ('☁️', "Orchestrateur dans le cloud", "Une session persistante pilote la file de travail ; sa mémoire est une issue du dépôt (#368), pas un contexte de conversation."),
    ('🍎', "Prompts prêts à coller pour le Mac", "Deux sessions sans surveillance : captures par lots (ordre #337, un PR à la fois, contrôle de fuite) et vérification des fusions (#344 et assimilés)."),
    ('🗄️', "Archive du miroir", "Commits miroités chaque heure, plus issues, PR, reviews et têtes de PR archivées chaque jour : le suivi survit à un changement de dépôt."),
    ('📱', "Piste legacy pour l'iPhone Duo", "L'ancienne app prépare l'écran ouvert (UI iPad) et l'écran de couverture sans bande noire ; seule cette piste ouvre des PR sur master."),
    ('🔍', "Analyse d'écart legacy / dev-swift", "Rapport .md + une image haute résolution : 2 colonnes × 6 appareils (iPhone 16, 18 Pro Max, Duo fermé, Duo ouvert)."),
]


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=HERE.parents[2]).stdout  # repo root: pathspecs are relative


def rev_before(day):
    return sh(f"git rev-list -1 --before='{day} 23:59:59 +0000' origin/dev-swift || git rev-list -1 --before='{day} 23:59:59 +0000' HEAD").strip()


def code_stats(rev):
    tests = sum(int(x.rsplit(':', 1)[1]) for x in sh(f"git grep -c -E '^[[:space:]]*@Test' {rev} -- '*.swift'").split() if ':' in x)
    lines = sum(int(x.rsplit(':', 1)[1]) for x in sh(f"git grep -c '' {rev} -- '*.swift'").split() if ':' in x)
    return tests, lines


def day_key(s):
    return (s or '')[:10]


def gather(since):
    issues = [i for i in gh_pages(f'repos/{REPO}/issues?state=all') if 'pull_request' not in i]
    pulls = [p for p in gh_pages(f'repos/{REPO}/pulls?state=all&base=dev-swift') if p.get('merged_at')]
    lot_issues = {r['issue']: r for r in G.rows.values()}
    end = since + 'T23:59:59Z'

    def done_at(i):
        return i['state'] == 'closed' and i.get('state_reason') in (None, 'completed')

    def done_by(i, t):
        return done_at(i) and i['closed_at'] <= t
    lots_done = lambda t: sum(1 for i in issues if i['number'] in lot_issues and done_by(i, t))
    now = '9999'
    base_rev = rev_before(since)
    t1, l1 = code_stats('origin/dev-swift')
    t0, l0 = code_stats(base_rev) if base_rev else (0, 0)
    commits = lambda r: int(sh(f'git rev-list --count {r}').strip() or 0)
    per_ms = {}
    for m, ms in (('M1', G.M1), ('M2', G.M2), ('M3', G.M3), ('M4', G.M4)):
        ids = {G.rows[l]['issue'] for l in ms}
        byn = {i['number']: i for i in issues}
        per_ms[m] = (sum(1 for n in ids if byn.get(n) and done_by(byn[n], now)), sum(1 for n in ids if byn.get(n) and done_by(byn[n], end)), len(ids))
    days = Counter(sh("git log origin/dev-swift --format=%cd --date=format:%Y-%m-%d").split())
    return {
        'since': since, 'planned': len(G.rows),
        'now': {'done': lots_done(now), 'prs': len(pulls), 'commits': commits('origin/dev-swift'), 'tests': t1, 'lines': l1,
                'issues': len(issues), 'open': sum(i['state'] == 'open' for i in issues)},
        'then': {'done': lots_done(end), 'prs': sum(p['merged_at'] <= end for p in pulls), 'commits': commits(base_rev) if base_rev else 0,
                 'tests': t0, 'lines': l0, 'issues': sum(i['created_at'] <= end for i in issues),
                 'open': sum(i['created_at'] <= end and not (i['state'] == 'closed' and i['closed_at'] <= end) for i in issues)},
        'ms': per_ms, 'days': dict(sorted(days.items())),
        'titles': {i['number']: i['title'] for i in issues if i['state'] == 'open'},
        'labels': {i['number']: [x['name'] for x in i['labels']] for i in issues if i['state'] == 'open'},
    }


def fr_num(n):
    return f'{n:,}'.replace(',', ' ')


def day_label(d):
    y, m, dd = map(int, d.split('-'))
    return f'{dd} {MONTHS[m - 1]}'


def dependents():
    """lot -> number of not-done lots that list it as a dependency."""
    c = Counter()
    for l, r in G.rows.items():
        if not G.done(l):
            for d in G.deps(r):
                c[d] += 1
    return c


def milestone_view(ms, D):
    cap = Counter()
    ready_cloud, ready_mac, waiting, blocked = [], [], 0, 0
    dep = dependents()
    for l in ms:
        if G.done(l):
            continue
        r = G.rows[l]
        n = r['issue']
        mac = r['module'] == 'App'
        if n in G.CAPTURE:
            waiting += 1
            for c in re.findall(r'#\d+', G.CAPTURE[n]):
                cap[c] += 1
        elif n in G.READY or n in G.CLAIMED:
            (ready_mac if mac else ready_cloud).append((dep[l], l, n, r['scope']))
        else:
            blocked += 1
    short = lambda s, k=58: (re.sub(r'`|\*', '', s) if len(s) <= k else re.sub(r'`|\*', '', s)[:k - 1].rsplit(' ', 1)[0] + '…')
    caps = [(k, v, short(re.sub(r'^Capture \(Mac\):\s*', '', D['titles'].get(int(k[1:]), '')), 52)) for k, v in cap.most_common(4)]
    return {
        'waiting_cap': waiting, 'blocked': blocked, 'caps': caps,
        'cloud': [(f'{l[4:]}', short(s, 52), u) for u, l, n, s in sorted(ready_cloud, key=lambda x: (-x[0], x[1]))[:4]], 'n_cloud': len(ready_cloud),
        'mac': [(f'{l[4:]}', short(s, 52), u) for u, l, n, s in sorted(ready_mac, key=lambda x: (-x[0], x[1]))[:4]], 'n_mac': len(ready_mac),
    }


CSS = """
:root{--ink:#0f1720;--mute:#6b7685;--faint:#9aa4b2;--line:#eceef2;--soft:#f5f6f8;--a1:#4f7cff;--a2:#8b5cf6;--a3:#14b8a6;--warm:#f59e0b;
--grad:linear-gradient(90deg,var(--a1),var(--a2))}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1920px;height:1080px;background:#fff;overflow:hidden}
body{font-family:Inter,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--ink);font-size:16px;padding:72px 96px 56px;
 display:flex;flex-direction:column;position:relative}
body:before{content:"";position:absolute;inset:0;pointer-events:none;
 background:radial-gradient(55% 45% at 100% 0%,rgba(139,92,246,.08),transparent 70%),radial-gradient(50% 40% at 0% 100%,rgba(79,124,255,.07),transparent 70%)}
h1{font-size:46px;font-weight:300;letter-spacing:-.025em;line-height:1.1}
h1 b{font-weight:600;background:var(--grad);-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{color:var(--mute);font-size:20px;margin-top:14px}
.lbl{font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--faint);font-weight:600;margin-bottom:20px}
.body{flex:1;display:flex;flex-direction:column;justify-content:center;gap:64px;position:relative}
.foot{display:flex;justify-content:space-between;color:var(--faint);font-size:13px;border-top:1px solid var(--line);padding-top:16px;position:relative}
.kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:44px}
.kpi{border-top:1px solid var(--line);padding-top:20px}
.kpi b{display:block;font-size:72px;font-weight:300;letter-spacing:-.03em;line-height:1}
.kpi b.g{background:var(--grad);-webkit-background-clip:text;background-clip:text;color:transparent;font-weight:500}
.kpi span{display:block;margin-top:12px;color:var(--mute);font-size:17px;line-height:1.35}
.kpi em{display:inline-block;margin-top:10px;font-style:normal;font-weight:600;font-size:16px;color:var(--a3)}
.bar{height:12px;border-radius:12px;background:var(--soft);overflow:hidden;position:relative}
.bar i{display:block;height:100%;background:var(--grad);border-radius:12px;position:absolute;left:0;top:0}
.bar i.then{background:rgba(79,124,255,.25);z-index:0}.bar i.now{z-index:1}
.row{display:grid;grid-template-columns:300px 1fr 150px;align-items:center;gap:28px;margin:26px 0}
.row b{font-weight:600;font-size:20px}.row small{display:block;color:var(--faint);font-size:14px;margin-top:3px}
.row .pc{text-align:right;font-size:36px;font-weight:300;letter-spacing:-.02em}
.row .pc em{display:block;font-style:normal;font-size:15px;color:var(--a3);font-weight:600}
.tbl{display:grid;grid-template-columns:repeat(3,1fr);gap:56px 64px}
.cell b{display:block;font-size:46px;font-weight:300;letter-spacing:-.02em}
.cell span{color:var(--mute);font-size:17px}
.cell s{display:block;color:var(--faint);text-decoration:none;font-size:15px;margin-top:6px}
.cell em{font-style:normal;font-weight:600;color:var(--a3);font-size:18px;margin-left:10px}
.orch{display:grid;grid-template-columns:repeat(5,1fr);gap:40px}
.orch div{border-top:2px solid transparent;border-image:linear-gradient(90deg,var(--a1),var(--a2)) 1;padding-top:22px}
.orch i{font-style:normal;font-size:34px}.orch b{display:block;font-size:22px;font-weight:600;margin:14px 0 10px;line-height:1.2}
.orch p{color:var(--mute);font-size:16px;line-height:1.5}
.ms2{display:grid;grid-template-columns:1fr 1fr;gap:96px}
.card .hd{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:14px}
.card .hd b{font-size:28px;font-weight:600}.card .hd span{font-size:44px;font-weight:300;letter-spacing:-.02em}
.card .goal{color:var(--mute);font-size:16px;margin-bottom:18px}
.sec{margin-top:26px}.sec h4{font-size:12px;letter-spacing:.14em;text-transform:uppercase;font-weight:600;margin-bottom:10px}
.sec.b h4{color:#dc5a4a}.sec.c h4{color:var(--a3)}.sec.m h4{color:var(--a2)}
.sec li{list-style:none;font-size:16px;line-height:1.35;padding:5px 0;color:var(--ink);display:flex;gap:10px}
.sec li u{text-decoration:none;color:var(--faint);min-width:56px}.sec li em{font-style:normal;color:var(--mute);margin-left:auto;white-space:nowrap;font-size:14px}
.sec p{color:var(--mute);font-size:15px}
"""


def page(n, title, sub, inner, D):
    d = datetime.now(timezone.utc)
    return f"""<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>SwiftHFR · semaine {n}</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet"><style>{CSS}</style></head><body>
<div><h1>{title}</h1><p class="sub">{sub}</p></div>
<div class="body">{inner}</div>
<div class="foot"><span><b>SwiftHFR</b> · réécriture native Swift / SwiftUI de HFR+ · point du {d.day} {MONTHS[d.month - 1]} {d.year}</span><span>{n} / 5</span></div></body></html>"""


def slides(D):
    N, T = D['now'], D['then']
    pct = lambda a, b: round(100 * a / b) if b else 0
    out = {}
    # 1
    days = D['days']
    mx = max(days.values())
    bars = ''
    for k, (d, v) in enumerate(days.items()):
        h = 200 * v / mx
        bars += f'<rect x="{k * 78 + 6}" y="{230 - h}" width="52" height="{h}" rx="7" fill="url(#g)"/><text x="{k * 78 + 32}" y="{218 - h}" text-anchor="middle" fill="#0f1720" font-weight="600" font-size="15">{v}</text><text x="{k * 78 + 32}" y="256" text-anchor="middle" fill="#9aa4b2" font-size="14">{int(d[8:])}</text>'
    kp = [(D['planned'], 'lots planifiés', 'issus de l\'audit complet', ''), (N['done'], f"lots terminés ({pct(N['done'], D['planned'])} %)", f"{D['planned'] - N['done']} restants", 'g'),
          (N['prs'], 'PR fusionnées', 'une PR relue par lot, squash', ''), (N['commits'], 'commits', 'sur dev-swift', ''),
          (fr_num(N['tests']), 'tests automatisés', f"{fr_num(N['lines'])} lignes de Swift", ''), (N['issues'], 'issues de suivi', f"{N['issues'] - N['open']} fermées · {N['open']} ouvertes", '')]
    kh = ''.join(f'<div class="kpi"><b class="{c}">{v}</b><span>{a}<br>{b}</span></div>' for v, a, b, c in kp)
    svg = f'<svg viewBox="0 0 {len(days) * 78} 270" width="100%" height="270" style="overflow:visible"><defs><linearGradient id="g" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#4f7cff"/><stop offset="1" stop-color="#8b5cf6"/></linearGradient></defs><line x1="0" y1="230" x2="{len(days) * 78}" y2="230" stroke="#eceef2"/>{bars}</svg>'
    first = day_label(next(iter(days)))
    out[1] = page(1, "Où en est <b>SwiftHFR</b>", f"Depuis le {first} : un moteur testé, une app qui lit et répond.", f'<div class="kpis">{kh}</div><div><div class="lbl">Commits par jour sur dev-swift (octobre – novembre 2026)</div>{svg}</div>', D)
    # 2
    def cell(label, a, b, fmt=lambda x: str(x)):
        return f'<div class="cell"><b>{fmt(a)}<em>+{fmt(a - b)}</em></b><span>{label}</span><s>le {day_label(D["since"])} : {fmt(b)}</s></div>'
    cells = ''.join([cell('lots terminés', N['done'], T['done']), cell('PR fusionnées', N['prs'], T['prs']), cell('commits', N['commits'], T['commits']),
                     cell('tests automatisés', N['tests'], T['tests'], fr_num), cell('lignes de Swift', N['lines'], T['lines'], fr_num), cell('issues de suivi', N['issues'], T['issues'])])
    rows = ''
    names = {'M1': ('M1 · MVP', 'connexion, lecture, réponse'), 'M2': ('M2 · Lecture et réponse', 'toutes les fonctions du legacy côté écran'), 'M3': ('M3 · Moteur', 'parsers, réseau, flux, stockage'), 'M4': ('M4 · Version finale', 'parité, App Store')}
    for m, (a, b, t) in D['ms'].items():
        rows += f'<div class="row"><div><b>{names[m][0]}</b><small>{names[m][1]}</small></div><div class="bar"><i class="then" style="width:{100 * b / t}%"></i><i class="now" style="width:{100 * a / t}%;opacity:.9"></i></div><div class="pc">{pct(a, t)} %<em>+{pct(a, t) - pct(b, t)} pts</em></div></div>'
    out[2] = page(2, f"Ce qui a changé <b>en une semaine</b>", f"Comparaison avec le {day_label(D['since'])} (barre claire : l'état de départ).", f'<div class="tbl">{cells}</div><div>{rows}</div>', D)
    # 3
    oh = ''.join(f'<div><i>{e}</i><b>{t}</b><p>{p}</p></div>' for e, t, p in ORCH)
    out[3] = page(3, "L'organisation du travail <b>change</b>", "Cinq évolutions de cette semaine, pour que le chantier tienne sans surveillance continue.", f'<div class="orch">{oh}</div>', D)
    # 4, 5
    goals = {'M1': 'Se connecter, naviguer, lire, répondre ; première build TestFlight', 'M2': 'Toutes les fonctions de lecture et de réponse du legacy',
             'M3': 'Tous les lots du moteur HFRKit, parité vérifiée', 'M4': 'Parité complète, notifications, conformité, App Store'}

    def card(m):
        a, _, t = D['ms'][m]
        v = milestone_view({'M1': G.M1, 'M2': G.M2, 'M3': G.M3, 'M4': G.M4}[m], D)
        li = lambda items, f: ''.join(f(*x) for x in items) or '<p>Rien en attente.</p>'
        blockers = (f'<li><u>{v["waiting_cap"]}</u> lots attendent une capture sur le Mac</li>' if v['waiting_cap'] else '') + (f'<li><u>{v["blocked"]}</u> lots attendent d\'autres lots</li>' if v['blocked'] else '')
        caps = ''.join(f'<li><u>{c}</u>{html.escape(ti)}<em>{n} lot{"s" if n > 1 else ""}</em></li>' for c, n, ti in v['caps'])
        cloud = li(v['cloud'], lambda l, s, u: f'<li><u>{l}</u>{html.escape(s)}<em>débloque {u}</em></li>') if v['cloud'] else '<p>Aucun lot moteur prêt dans ce jalon.</p>'
        extra = ''.join(f'<li><u>#{n}</u>{html.escape(re.sub(r"^Capture \(Mac\):\s*", "", D["titles"][n])[:52])}<em>vérification</em></li>' for n in EXTRA_MAC.get(m, []) if n in D['titles'])
        mac = extra + (li(v['mac'], lambda l, s, u: f'<li><u>{l}</u>{html.escape(s)}<em>débloque {u}</em></li>') if v['mac'] else '<p>Aucun lot écran prêt dans ce jalon.</p>')
        return f"""<div class="card"><div class="hd"><b>{names[m][0]}</b><span>{pct(a, t)} %</span></div><div class="bar"><i class="now" style="width:{100 * a / t}%"></i></div>
<p class="goal" style="margin-top:14px">{goals[m]} · {a} / {t} lots</p>
<div class="sec b"><h4>Blocages</h4><ul>{blockers}{caps}</ul></div>
<div class="sec c"><h4>Leviers cloud ({v['n_cloud']} prêts)</h4><ul>{cloud}</ul></div>
<div class="sec m"><h4>Goulots Mac ({v['n_mac']} lots prêts)</h4><ul>{mac}</ul></div></div>"""
    out[4] = page(4, "Jalons <b>M1 et M2</b> : blocages et leviers", "Les captures sur le Mac et les lots écran sont ce qui retient le plus ; le cloud avance le moteur en parallèle.", f'<div class="ms2">{card("M1")}{card("M2")}</div>', D)
    out[5] = page(5, "Jalons <b>M3 et M4</b> : blocages et leviers", "Le moteur (M3) tourne dans le cloud ; la version finale (M4) dépend de l'écran et de la parité.", f'<div class="ms2">{card("M3")}{card("M4")}</div>', D)
    return out


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        raise SystemExit(__doc__)
    outdir = Path(args[0]) / 'slides'
    outdir.mkdir(parents=True, exist_ok=True)
    since = sys.argv[sys.argv.index('--since') + 1] if '--since' in sys.argv else '2026-10-28'  # last Wednesday: weekly cadence
    D = gather(since)
    (Path(args[0]) / 'deck.json').write_text(json.dumps({k: v for k, v in D.items() if k not in ('titles', 'labels')}, indent=1))
    for n, h in slides(D).items():
        (outdir / f'slide-{n}.html').write_text(h, encoding='utf-8')
    print('slides ->', outdir, {k: D[k] for k in ('now', 'then', 'ms')})
