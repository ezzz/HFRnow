"""Weekly deck (HTML slides, French) from the tracker, the docs and git. Delivered to the maintainer only, never posted.

  python3 tooling/roadmap/weekly/build.py OUTDIR [--since 2026-11-03]   # needs `gh` (GH_TOKEN), full git history
  node tooling/roadmap/weekly/shot.js OUTDIR                             # slides/*.html -> 2880x1620 JPEG, checks

Slides (#892): 1 où en est SwiftHFR · 2 indicateurs (KPIs, progress model) · 3 aujourd'hui (M1 to M5 and the work
outside every milestone against the baseline date, organisation) · 4 M1 · M2 · M3 (one tile per main feature) · 5 M4 en
détail (lots, test feedback and its radar, end-of-M4 review tiles) · 6 M5 en détail (tiles and radar by category, band of
the open issues outside every milestone). The legacy app is « l'app courante » on every slide. Nothing names or ranks a person.

The tracker state is fetched first and written to OUTDIR/state.json (never to tooling/roadmap/state.json, whose
committed snapshot is stale); `--state FILE` reuses a saved one, refused when older than 6 h.
"""
import html
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))
import counts as C  # noqa: E402
import sync_state  # noqa: E402
from sync_state import REPO, gh_pages  # noqa: E402

DROPPED = set()  # issue numbers closed not planned or duplicate (set by gather): their lots leave every count
G = progress = None  # loaded by load_engine() once the fresh state is in place (generate reads it at import time)

TOTAL = 6
START = '2026-10-24'  # first commit of SwiftHFR (Phase 0 done that day, ROADMAP)
MONTHS = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']
MS = ['M1', 'M2', 'M3', 'M4', 'M5']
MS_NAMES = {'M1': 'M1 · MVP', 'M2': 'M2 · Lecture et réponse', 'M3': 'M3 · Moteur HFRKit', 'M4': 'M4 · Version finale', 'M5': 'M5 · Évolutions'}
MS_GOALS = {  # docs/ROADMAP.md, Milestones table
    'M1': "Première build utilisable : se connecter, naviguer, lire, répondre.",
    'M2': "Toutes les fonctions de lecture et de réponse de l'app courante.",
    'M3': "Tous les lots du moteur HFRKit hors M1, parité vérifiée.",
    'M4': "La parité validée avec l'app courante, puis l'App Store.",
    'M5': "Ce que la parité n'exige pas, jamais abandonné : après M4.",
}
MS_ICON = {'M1': 'rocket', 'M2': 'book', 'M3': 'gear', 'M4': 'flag', 'M5': 'sparkle'}

# Tiles of the « M1 · M2 · M3 » slide: (icon, title, one-liner, lots of the tile). Written from docs/ROADMAP.md and the
# lot scopes of lots.json; the status line of each tile is computed from its lots. One-liners stay under 80 characters
# (two lines in a tile).
FEATURES = {
    'M1': [
        ('lock', 'Comptes et connexion', "Plusieurs comptes ; session validée avant de remplacer les cookies.", [13, 42, 43, 44, 65, 81]),
        ('compass', 'Navigation adaptative', "Une app pour iPhone, iPad et pliables : catégories, favoris, MP.", [21, 22, 24, 82, 170]),
        ('book', 'Lecteur de sujet', "Messages normalisés, liens internes dans l'app, aucun script de page.", [30, 33, 34, 83, 137]),
        ('pencil', 'Réponse', "Rédiger, envoyer, brouillons ; un succès seulement si HFR le confirme.", [36, 37, 48, 84]),
        ('beaker', "Oracle de l'app courante", "Fixtures anonymisées : chaque parser comparé à l'app courante.", [0, 1, 2, 3, 4, 5, 71]),
    ],
    'M2': [
        ('quote', 'Citer, éditer, créer', "Citation et multi-citation, édition, suppression, nouveau sujet.", [85, 86, 87, 88, 89]),
        ('smile', 'Smileys, images, GIF', "Sélecteur de smileys avec recherche, envoi d'images, GIF.", [102, 103, 104, 105, 155]),
        ('photo', 'Médias dans le lecteur', "Réglages d'images, vidéos au tap, visionneuse plein écran.", [106, 107, 108, 109, 111]),
        ('search', 'Recherche et filtres', "Recherche du forum et dans un sujet, filtres, profils.", [113, 114, 115, 116, 117]),
        ('envelope', 'MP, sondages, hors ligne', "MP et badge, nouveau MP, vote aux sondages, lecture hors ligne.", [124, 125, 126, 127, 128, 136, 139, 171]),
    ],
    'M3': [
        ('puzzle', 'Parsers', "MP, sondages, profils, citations, vidéos : lus comme l'app courante.", [23, 26, 27, 28, 31, 32, 35, 38, 95, 97]),
        ('arrows', 'Flux du client', "Recherche, alerte modérateur, drapeaux, vote, MP, smileys, Giphy.", [46, 47, 49, 50, 51, 53, 54, 58, 92, 93, 94, 98]),
        ('db', 'Stockage', "Réglages, listes noire et blanche, brouillons, caches, hors ligne.", [60, 61, 63, 64, 66, 67, 68, 72, 90, 91]),
        ('cloud', 'Synchronisation', "MPStorage et iCloud clé-valeur, sans perte en cas de conflit.", [52, 62, 73, 172]),
    ],
}
# End-of-M4 reviews (#892, operator 2026-11-13): issue, tile title, goal, label of the issues each one opens (AGENTS.md §7).
REVIEWS = [
    (774, 'Vitesse & réactivité', 'Calcul, temps de réponse, fluidité.', 'performance'),
    (775, 'Refacto & qualité', 'Fiabilité, cohérence, maintenabilité.', 'quality'),
    (836, 'Doublons & factorisation', 'Une seule implémentation par comportement.', 'duplicates'),
    (326, 'Audit externe', 'Les lots livrés par des contributeurs extérieurs.', 'external-audit'),
    (866, 'HIG & WWDC', "L'interface face aux guides et sessions 2024–2026.", 'hig-wwdc'),
]
AXIS_ICON = {'lecteur': 'book', 'listes': 'list', 'composer': 'pencil', 'MP': 'envelope', 'navigation': 'compass',
             'réglages et thèmes': 'palette', 'performance': 'clock', 'autre': 'puzzle'}
# Short French labels of the lots that can show in a « reste à faire » card or on the M5 slide; another lot falls
# back to its scope, shortened.
LOT_FR = {
    55: 'Alertes Qualitaÿ : vérification, création, flux', 57: 'Client REST de navigation', 70: 'Portes de parité du moteur',
    168: 'Liste complète des sous-forums', 100: 'Création de sondage', 101: 'Brouillons archivés par sujet',
    131: 'Liste noire synchronisée', 132: 'Signets', 133: 'Flux Alertes Qualitaÿ et badge', 134: 'Alerte Qualitaÿ depuis un message',
    140: 'MP en arrière-plan, notification', 146: 'iPad : plusieurs fenêtres', 147: 'iPhone Duo : écran intérieur en colonnes',
    156: 'Cohérence multi-comptes', 157: 'Suppression de compte', 159: 'Conformité App Review', 161: 'Pipeline TestFlight',
    164: "Porte de parité avec l'app courante", 165: 'Soumission App Store', 166: 'Moteur saisonnier', 174: 'Barre de mise en forme',
    179: 'Taille des caches', 188: 'Moteur de thèmes et galerie', 189: "Choix d'icône par pack", 190: 'Illustrations des icônes',
    191: 'Thèmes Samain', 192: 'Thèmes Swift et Rétro 5250', 193: 'Thèmes OG clair et OG gris', 194: 'Fête nationale',
    110: 'Navigateur de pages', 112: 'Curseur de pages', 138: 'Liens universels, partage', 141: 'Raccourci « Vérifier HFR »',
    142: 'Feuille « session expirée »', 143: 'Accueil « À suivre »', 144: 'Accueil : Alertes Qualitaÿ', 145: "Restauration de l'état",
    148: 'Défilement continu', 149: 'Raccourcis clavier', 150: 'Spotlight des sujets lus', 151: 'Emoji refusé, smiley proposé',
    152: 'Aperçu avant envoi', 153: 'Plateau de citations', 154: '« On t’a cité »', 175: 'Supprimer un sujet', 176: 'Galerie HD',
    177: 'Gestes uniformes des listes', 178: 'Bandeau « Nouveau »', 180: "Couleur d'accent unique", 181: 'Membres des MP de groupe',
    182: 'MP à plusieurs', 183: 'Avis Alertes Qualitaÿ', 184: '« Aperçu HFR » (moteur)', 187: 'Vider le cache',
}
# Slide 10, organisation (edit when it changes; describe functions, never people)
ORCH = [
    ('cloud', "Orchestrateur dans le cloud", "Une session persistante pilote la file ; sa mémoire est une issue du dépôt (#368)."),
    ('laptop', "Sessions Mac sans surveillance", "Captures par lots, un PR à la fois avec contrôle de fuite, et vérifications d'appareil."),
    ('archive', "Archive du miroir", "Commits miroités chaque heure, issues, PR et revues archivées chaque jour."),
    ('phone', "Piste de l'app courante", "L'iPhone Duo et les retours de bêta passent d'abord par l'app courante, puis dans Swift."),
    ('compare', "Écart app courante / Swift", "Un registre des écarts et un changelog des correctifs, rangés après chaque fusion."),
]

# Inline line icons, 24x24, stroke only (drawn for this deck: no external asset)
ICONS = {
    'rocket': '<path d="M12 3c3 2 4.5 5 4.5 8.5L14 17h-4l-2.5-5.5C7.5 8 9 5 12 3z"/><circle cx="12" cy="10" r="1.6"/><path d="M8 14l-3 2 1 3 3-1M16 14l3 2-1 3-3-1M10.5 19.5L12 22l1.5-2.5"/>',
    'book': '<path d="M4 5.5C6 4.5 9 4.5 12 6c3-1.5 6-1.5 8-.5V19c-2-1-5-1-8 .5-3-1.5-6-1.5-8-.5z"/><path d="M12 6v13.5"/>',
    'gear': '<circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.6M12 18.6v2.6M2.8 12h2.6M18.6 12h2.6M5.5 5.5l1.8 1.8M16.7 16.7l1.8 1.8M5.5 18.5l1.8-1.8M16.7 7.3l1.8-1.8"/><circle cx="12" cy="12" r="6.4"/>',
    'flag': '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
    'sparkle': '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/>',
    'lock': '<rect x="5" y="10.5" width="14" height="10" rx="3"/><path d="M8.5 10.5V7.5a3.5 3.5 0 017 0v3"/><path d="M12 14.5v2.5"/>',
    'compass': '<circle cx="12" cy="12" r="9"/><path d="M15.5 8.5l-2 5-5 2 2-5z"/>',
    'pencil': '<path d="M4 20l1-4.5L15.5 5a2.1 2.1 0 013 3L8 18.5z"/><path d="M13.5 7l3 3"/>',
    'beaker': '<path d="M9 3h6M10 3v6l-5 9.5A2 2 0 006.8 21h10.4a2 2 0 001.8-2.5L14 9V3"/><path d="M7.5 15h9"/>',
    'quote': '<path d="M4 6.5A2.5 2.5 0 016.5 4h11A2.5 2.5 0 0120 6.5v7a2.5 2.5 0 01-2.5 2.5H10l-4.5 4v-4A2.5 2.5 0 014 13.5z"/><path d="M9 8.5v3M13 8.5v3"/>',
    'smile': '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5c1.8 2 5.2 2 7 0"/><path d="M9 9.5h.01M15 9.5h.01" stroke-width="2.6"/>',
    'photo': '<rect x="3.5" y="5" width="17" height="14" rx="3"/><circle cx="9" cy="10" r="1.6"/><path d="M4 17l5-4.5 4 3.5 2.5-2 4.5 3.5"/>',
    'search': '<circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/>',
    'envelope': '<rect x="3.5" y="5.5" width="17" height="13" rx="3"/><path d="M4.5 7.5L12 13l7.5-5.5"/>',
    'puzzle': '<path d="M5 8h3a2 2 0 114 0h3v3a2 2 0 110 4v3H12a2 2 0 10-4 0H5v-3a2 2 0 100-4z"/>',
    'arrows': '<path d="M4 8h13M14 4.5L17.5 8 14 11.5M20 16H7M10 12.5L6.5 16l3.5 3.5"/>',
    'db': '<ellipse cx="12" cy="6" rx="7" ry="2.8"/><path d="M5 6v12c0 1.5 3 2.8 7 2.8s7-1.3 7-2.8V6M5 12c0 1.5 3 2.8 7 2.8s7-1.3 7-2.8"/>',
    'cloud': '<path d="M7 18.5a4.5 4.5 0 01-.6-9A6 6 0 0118 9.5a4.5 4.5 0 01-.5 9z"/>',
    'palette': '<path d="M12 3.5a8.5 8.5 0 100 17c1.3 0 1.8-1 1.3-2-.6-1.2.2-2.5 1.6-2.5H17a3.5 3.5 0 003.5-3.5c0-5-3.8-9-8.5-9z"/><circle cx="7.8" cy="11" r="1.1"/><circle cx="10.5" cy="7.5" r="1.1"/><circle cx="15" cy="8" r="1.1"/>',
    'access': '<circle cx="12" cy="4.8" r="1.8"/><path d="M5 8.5l7 1.5 7-1.5M12 10v4.5M12 14.5l-3 6M12 14.5l3 6"/>',
    'shield': '<path d="M12 3l7.5 3v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6z"/><path d="M8.8 12l2.2 2.2 4.2-4.4"/>',
    'home': '<path d="M4 11l8-6.5 8 6.5M6 9.5V20h12V9.5"/><path d="M10 20v-5h4v5"/>',
    'phone': '<rect x="6.5" y="2.8" width="11" height="18.4" rx="3"/><path d="M10.5 18h3"/>',
    'bug': '<rect x="7" y="7.5" width="10" height="12" rx="5"/><path d="M9.5 7.5a2.5 2.5 0 015 0M3.5 13H7M17 13h3.5M4.5 8.5L7.5 10M19.5 8.5L16.5 10M4.5 18.5L7.5 16.5M19.5 18.5l-3-2M12 11v8"/>',
    'wrench': '<path d="M14.5 4a5 5 0 00-4.8 6.4L3.8 16.3a2 2 0 002.9 2.9l5.9-5.9A5 5 0 0019 8.5l-2.8 2.8-3-.5-.5-3L15.5 5z"/>',
    'merge': '<circle cx="6.5" cy="5.5" r="2"/><circle cx="6.5" cy="18.5" r="2"/><circle cx="17.5" cy="11" r="2"/><path d="M6.5 7.5v9M6.5 9c0 2 2 2 4.5 2h4.5"/>',
    'chart': '<path d="M4 20h16M7 16.5V11M12 16.5V6.5M17 16.5v-4"/>',
    'tag': '<path d="M3.5 12.5V4.5a1 1 0 011-1h8l8 8a1.5 1.5 0 010 2.1l-6.9 6.9a1.5 1.5 0 01-2.1 0z"/><circle cx="8" cy="8" r="1.4"/>',
    'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',
    'pr': '<circle cx="6.5" cy="5.5" r="2"/><circle cx="6.5" cy="18.5" r="2"/><circle cx="17.5" cy="18.5" r="2"/><path d="M6.5 7.5v9M17.5 16.5V9.5a3 3 0 00-3-3H11M13 4l-2.5 2.5L13 9"/>',
    'ci': '<circle cx="12" cy="12" r="9"/><path d="M8 12.2l2.7 2.7L16.2 9.4"/>',
    'test': '<path d="M5 12.5l4 4L19 6.5"/><path d="M5 20h14" opacity=".5"/>',
    'laptop': '<rect x="5" y="5" width="14" height="10" rx="2"/><path d="M3 19h18"/>',
    'archive': '<rect x="3.5" y="4.5" width="17" height="4.5" rx="1.5"/><path d="M5 9v9.5A1.5 1.5 0 006.5 20h11a1.5 1.5 0 001.5-1.5V9M10 12.5h4"/>',
    'compare': '<rect x="3.5" y="5" width="7" height="14" rx="2"/><rect x="13.5" y="5" width="7" height="14" rx="2"/><path d="M6 9h2M16 9h2M6 12.5h2M16 12.5h2"/>',
    'list': '<path d="M9 6.5h11M9 12h11M9 17.5h11"/><path d="M4.5 6.5h.01M4.5 12h.01M4.5 17.5h.01" stroke-width="2.6"/>',
}


def icon(name, cls='ic'):
    return f'<span class="{cls}"><svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{ICONS[name]}</svg></span>'


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=ROOT).stdout  # repo root: pathspecs are relative


def esc(s):
    return html.escape(str(s), quote=False)


def no_legacy(s):
    """The operator's rule: the legacy app is « l'app courante » on every slide."""
    return re.sub(r'\blegacy\b', "app courante", s, flags=re.I)


# ---------------------------------------------------------------- data

def fetch_state(outdir, state_file=None):
    """Fresh tracker state for generate.py, outside the tree. Returns (issues, pulls) when fetched, (None, None) when
    a saved state is reused (then the deck refuses one older than STATE_MAX_AGE_H)."""
    if state_file:
        st = json.loads(Path(state_file).read_text(encoding='utf-8'))
        age = C.state_age_hours(st.get('generated_at'))
        if age > C.STATE_MAX_AGE_H:
            raise SystemExit(f"state {state_file} is {age:.0f} h old (generated_at {st.get('generated_at')!r}): "
                             f"over {C.STATE_MAX_AGE_H} h, run without --state to fetch the tracker")
        os.environ['ROADMAP_STATE'] = str(Path(state_file).resolve())
        return None, None
    issues = gh_pages(f'repos/{REPO}/issues?state=all')
    pulls = gh_pages(f'repos/{REPO}/pulls?state=all&base=dev-swift')
    lots = json.loads((HERE.parent / 'lots.json').read_text(encoding='utf-8'))
    path = Path(outdir) / 'state.json'
    path.write_text(json.dumps(sync_state.build(issues, pulls, lots), indent=1, sort_keys=True) + '\n')
    os.environ['ROADMAP_STATE'] = str(path.resolve())
    return issues, pulls


def load_engine():
    global G, progress
    import generate as _g  # noqa: E402  (reads ROADMAP_STATE)
    import progress as _p  # noqa: E402
    G, progress = _g, _p
    age = C.state_age_hours(G.GENERATED_AT)
    if age > C.STATE_MAX_AGE_H:
        raise SystemExit(f'state.json is {age:.0f} h old ({G.GENERATED_AT}): refresh it first')


def rev_before(day):
    return sh(f"git rev-list -1 --before='{day} 23:59:59 +0000' origin/dev-swift || git rev-list -1 --before='{day} 23:59:59 +0000' HEAD").strip()


def code_stats(rev):
    tests = sum(int(x.rsplit(':', 1)[1]) for x in sh(f"git grep -c -E '^[[:space:]]*@Test' {rev} -- '*.swift'").split() if ':' in x)
    lines = sum(int(x.rsplit(':', 1)[1]) for x in sh(f"git grep -c '' {rev} -- '*.swift'").split() if ':' in x)
    return tests, lines


def ci_runs(since_day):
    def count(extra=''):
        out = subprocess.run(['gh', 'api', '-X', 'GET', f'repos/{REPO}/actions/runs?created=>={since_day}{extra}&per_page=1', '--jq', '.total_count'],
                             capture_output=True, text=True)
        if out.returncode:
            raise SystemExit(f'gh api actions/runs failed: {out.stderr.strip()[:200]}')
        return int(out.stdout.strip() or 0)
    return {'total': count(), 'failure': count('&status=failure'), 'cancelled': count('&status=cancelled'), 'since': since_day}


def lot_n(l):
    return int(l[4:])


def ms_lots():
    return {m: C.live_lots(ls, G.rows, DROPPED) for m, ls in (('M1', G.M1), ('M2', G.M2), ('M3', G.M3), ('M4', G.M4), ('M5', G.M5))}


def gather(since, issues, pulls_all):
    now_dt = datetime.now(timezone.utc)
    pulls = [p for p in pulls_all if p.get('merged_at')]
    byn = {i['number']: i for i in issues}
    DROPPED.clear()
    DROPPED.update(C.dropped_issues(issues))
    end = since + 'T23:59:59Z'

    def done_by(i, t):
        return i['state'] == 'closed' and i.get('state_reason') in (None, 'completed') and i['closed_at'] <= t
    lot_issues = {r['issue'] for r in G.rows.values()}
    lots_done = lambda t: sum(1 for i in issues if i['number'] in lot_issues and done_by(i, t))
    base_rev = rev_before(since)
    t1, l1 = code_stats('origin/dev-swift')
    t0, l0 = code_stats(base_rev) if base_rev else (0, 0)
    commits = lambda r: int(sh(f'git rev-list --count {r}').strip() or 0)
    per_ms = {}
    for m, ls in ms_lots().items():
        ids = [G.rows[l]['issue'] for l in ls]
        closed = [byn[n]['closed_at'] for n in ids if byn.get(n) and done_by(byn[n], '9999')]
        buckets = Counter(progress.bucket(l, set(x['name'] for x in byn.get(G.rows[l]['issue'], {}).get('labels', []))) for l in ls
                          if not (byn.get(G.rows[l]['issue']) and byn[G.rows[l]['issue']]['state'] == 'closed' and byn[G.rows[l]['issue']].get('state_reason') not in (None, 'completed')))
        per_ms[m] = {'done': len(closed), 'then': sum(1 for n in ids if byn.get(n) and done_by(byn[n], end)), 'total': sum(buckets.values()),
                     'last': max(closed)[:10] if closed else None, 'buckets': dict(buckets)}
    days = Counter(sh("TZ=UTC git log origin/dev-swift --format=%cd --date=format-local:%Y-%m-%d").split())
    groups = C.daily_groups(issues)
    master_prs = gh_pages(f'repos/{REPO}/pulls?state=open&base=master')
    root = ROOT
    gap = C.gap_total((root / 'docs/migration/GAP-LEGACY-VS-SWIFT.md').read_text(encoding='utf-8'))
    chg = C.changelog_rows((root / 'docs/CHANGELOG-LEGACY.md').read_text(encoding='utf-8'))
    ver = C.marketing_version((root / 'App/SwiftHFR.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))
    week = (now_dt - timedelta(days=7)).strftime('%Y-%m-%dT%H:%M:%SZ')
    day = (now_dt - timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
    return {
        'since': since, 'planned': len(C.live_lots(G.rows, G.rows, DROPPED)), 'state_at': G.GENERATED_AT,
        'now': {'done': lots_done('9999'), 'prs': len(pulls), 'commits': commits('origin/dev-swift'), 'tests': t1, 'lines': l1,
                'issues': len(issues), 'open': sum(i['state'] == 'open' for i in issues)},
        'then': {'done': lots_done(end), 'prs': sum(p['merged_at'] <= end for p in pulls), 'commits': commits(base_rev) if base_rev else 0,
                 'tests': t0, 'lines': l0, 'issues': sum(i['created_at'] <= end for i in issues),
                 'open': sum(i['created_at'] <= end and not (i['state'] == 'closed' and i['closed_at'] <= end) for i in issues)},
        'kpi': {'version': ver, 'days': (now_dt.date() - datetime.fromisoformat(START).date()).days,
                'prs_7d': sum(p['merged_at'] >= week for p in pulls), 'prs_24h': sum(p['merged_at'] >= day for p in pulls),
                'ci': ci_runs((now_dt - timedelta(days=7)).date().isoformat())},
        'daily': {k: {'open': C.open_closed(v)[0], 'closed': C.open_closed(v)[1],
                      'items': [(i['number'], C.clean_title(i['title'])) for i in sorted(v, key=lambda x: -x['number']) if i['state'] == 'open']}
                  for k, v in groups.items()},
        'master_prs': [(p['number'], C.clean_title(p['title'])) for p in sorted(master_prs, key=lambda x: -x['number'])],
        'gap': gap, 'changelog': chg,
        'ms': per_ms, 'days': dict(sorted(days.items())), 'progress': progress.data(pulls, issues),
        **gather_892(issues, end),
    }


def day_label(d):
    y, m, dd = map(int, d[:10].split('-'))
    return f'{dd} {MONTHS[m - 1]}'


def lot_label(l):
    n = lot_n(l)
    return LOT_FR.get(n) or G.short(re.sub(r'`|\*', '', G.rows[l]['scope']), 40)


def issue_label(i, lot_of_issue):
    """A lot shows its short French label, any other issue its cleaned title."""
    l = lot_of_issue.get(i['number'])
    return lot_label(l) if l else C.clean_title(i['title'], 48)


def gather_892(issues, end):
    """Slides 3, 5 and 6 (#892): milestone of every SwiftHFR issue, M4 detail, test feedback, reviews, M5 contents."""
    lots = ms_lots()
    lot_ms = {G.rows[l]['issue']: m for m, ls in lots.items() for l in ls}
    lot_of_issue = {G.rows[l]['issue']: l for l in G.rows}
    lot_of_number = {lot_n(l): G.rows[l]['issue'] for l in G.rows}
    from m5 import FOLLOWUPS
    swift = [i for i in issues if C.is_swift_issue(i)]
    ms_of = {i['number']: C.issue_milestone(i, lot_ms, FOLLOWUPS, lot_of_number) for i in swift}
    done_by = lambda i, t: i['state'] == 'closed' and (i.get('closed_at') or '') <= t
    # work outside every milestone: done / total now and at the baseline, and the open issues for the band of slide 6
    out = [i for i in swift if ms_of[i['number']] is None]
    out_open = sorted((i for i in out if i['state'] == 'open'), key=lambda i: -i['number'])
    kind = lambda i: ('captures' if re.search(r'\b(capture|re-capture)\b', i['title'], re.I) else
                      next((x[6:] for x in C.labels(i) if x.startswith('type: ')), 'autre'))
    outside = {'done': sum(done_by(i, '9999') for i in out), 'total': len(out),
               'then_done': sum(done_by(i, end) for i in out), 'then_total': sum(i['created_at'] <= end for i in out),
               'kinds': dict(Counter(kind(i) for i in out_open).most_common()),
               'open': [(i['number'], C.clean_title(i['title'], 56)) for i in out_open]}
    # M4: lots by state, what changed since the baseline, test feedback, end-of-M4 reviews
    byn = {i['number']: i for i in issues}
    b = Counter()
    for l in lots['M4']:
        k = progress.bucket(l, C.labels(byn.get(G.rows[l]['issue'], {})))
        b['fait' if k == 'done' else 'en cours' if k == 'progress' else 'à faire'] += 1
    closed_since = lambda i: i['state'] == 'closed' and (i.get('closed_at') or '') > end
    m4_lots_since = sorted((l for l in lots['M4'] if byn.get(G.rows[l]['issue']) and closed_since(byn[G.rows[l]['issue']])), key=lot_n)
    m4_issues = [i for i in swift if ms_of[i['number']] == 'M4' and i['number'] not in lot_of_issue]
    fb = C.feedback(issues)  # every `beta-test finding` issue, as on slide 1 (dropped ones show as « écarté »)
    fb_open = [i for i in fb if i['state'] == 'open']
    added = sorted((i for i in fb if i['created_at'] > end), key=lambda i: -i['number'])
    review_label = lambda x: C.REVIEW_PREFIX + x
    reviews = [{'n': n, 'title': t, 'goal': g, 'state': C.issue_status(byn[n]) if n in byn else 'ouvert',
                'found': sum(1 for i in swift if review_label(lab) in C.labels(i)),
                'found_open': sum(1 for i in swift if review_label(lab) in C.labels(i) and i['state'] == 'open')}
               for n, t, g, lab in REVIEWS]
    m4 = {'lots': {k: b.get(k, 0) for k in ('fait', 'en cours', 'à faire')},
          'lots_since': [lot_label(l) for l in m4_lots_since],
          'issues': {'total': len(m4_issues), 'done': sum(i['state'] == 'closed' for i in m4_issues),
                     'since': sum(closed_since(i) for i in m4_issues), 'new': sum(i['created_at'] > end for i in m4_issues)},
          'fb': {'status': dict(Counter(C.issue_status(i) for i in fb)), 'total': len(fb),
                 'added': [(i['number'], C.clean_title(i['title'], 52), C.issue_status(i)) for i in added],
                 'axes': C.axis_counts(fb), 'axes_open': C.axis_counts(fb_open)},
          'reviews': reviews}
    # M5: its lots and issues, by category (the radar axes)
    # a FEAT-0xx intake issue is M5 for the out-of-milestone count, but its lot already stands for it on slide 6
    feat_intake = lambda i: i['number'] not in lot_of_issue and C.FEAT_TAG.search(i.get('title') or '')
    m5 = [i for i in swift if ms_of[i['number']] == 'M5' and not feat_intake(i)]
    cats = {a: [] for a in C.AXES}
    for i in sorted(m5, key=lambda i: (i['number'] not in lot_of_issue, i['number'])):
        cats[C.axis_of(i['title'])].append((issue_label(i, lot_of_issue), i['state'] == 'closed'))
    m5d = {'cats': {a: v for a, v in cats.items() if v}, 'axes': {a: len(v) for a, v in cats.items()},
           'total': len(m5), 'done': sum(i['state'] == 'closed' for i in m5)}
    return {'outside': outside, 'm4': m4, 'm5': m5d}


# ---------------------------------------------------------------- rendering

CSS = """
:root{--ink:#0f1720;--mute:#5f6b7a;--faint:#8a95a5;--line:#eceef2;--soft:#f4f5f8;--a1:#4f7cff;--a2:#8b5cf6;--a3:#14b8a6;--warm:#f59e0b;
--grad:linear-gradient(90deg,var(--a1),var(--a2));--r:24px;--shadow:0 1px 2px rgba(15,23,32,.05),0 8px 28px rgba(15,23,32,.06)}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1920px;height:1080px;background:#fff;overflow:hidden}
body{font-family:Inter,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--ink);font-size:20px;padding:60px 96px 40px;
 display:flex;flex-direction:column;position:relative}
body:before{content:"";position:absolute;inset:0;pointer-events:none;
 background:radial-gradient(55% 45% at 100% 0%,rgba(139,92,246,.08),transparent 70%),radial-gradient(50% 40% at 0% 100%,rgba(79,124,255,.07),transparent 70%)}
h1{font-size:46px;font-weight:300;letter-spacing:-.025em;line-height:1.1}
h1 b{font-weight:600;background:var(--grad);-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{color:var(--mute);font-size:22px;margin-top:12px}
.lbl{font-size:20px;letter-spacing:.06em;text-transform:uppercase;color:var(--faint);font-weight:600;margin-bottom:12px}
.body{flex:1;display:flex;flex-direction:column;justify-content:center;gap:28px;position:relative;min-height:0}
.foot{display:flex;justify-content:space-between;color:var(--faint);font-size:20px;border-top:1px solid var(--line);padding-top:14px;position:relative}
.g{background:var(--grad);-webkit-background-clip:text;background-clip:text;color:transparent}
.card{background:#fff;border-radius:var(--r);box-shadow:var(--shadow);border:1px solid rgba(15,23,32,.04);padding:24px 26px;position:relative}
.card.dash{background:transparent;box-shadow:none;border:2px dashed #d6dbe3}
.card.grey{background:var(--soft);box-shadow:none;border:none}
.hero{border-radius:var(--r);padding:36px 38px;background:radial-gradient(300px 300px at 100% 0%,rgba(139,92,246,.18),transparent 70%),linear-gradient(140deg,#eef2ff 0%,#f1ebff 60%,#f8f0ff 100%);border:1px solid rgba(139,92,246,.14);
 display:flex;flex-direction:column;gap:18px;position:relative;overflow:hidden}
.hero h2{font-size:40px;font-weight:600;letter-spacing:-.02em;line-height:1.1}
.hero p{font-size:22px;line-height:1.4;color:var(--mute)}
.hero .big{font-size:84px;font-weight:300;letter-spacing:-.04em;line-height:1}
.ic{display:inline-flex;width:48px;height:48px;border-radius:14px;align-items:center;justify-content:center;flex:none;
 background:linear-gradient(140deg,rgba(79,124,255,.12),rgba(139,92,246,.14));color:#5b63f0}
.hero .ic{width:60px;height:60px;border-radius:18px;background:#fff;box-shadow:var(--shadow)}
.hero .ic svg{width:34px;height:34px}
.pill{display:inline-flex;align-items:center;gap:8px;border-radius:999px;padding:6px 16px;font-size:20px;font-weight:600;white-space:nowrap;
 background:rgba(79,124,255,.1);color:#3d5bd9;width:max-content}
.pill.ok{background:rgba(20,184,166,.12);color:#0f8a7d}
.pill.todo{background:var(--soft);color:var(--mute)}
.bar{height:14px;border-radius:14px;background:#eef0f4;overflow:hidden;position:relative}
.bar i{display:block;height:100%;background:var(--grad);border-radius:14px;position:absolute;left:0;top:0}
.bar i.then{background:rgba(79,124,255,.25)}
.ic.sm{position:absolute;top:16px;right:16px;width:40px;height:40px;border-radius:12px}.ic.sm svg{width:24px;height:24px}
.cell{position:relative}
.kpi b,.cell b{padding-right:48px}.cell em{display:block;margin:6px 0 0 0}
.kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:20px}
.kpi{padding:22px 24px}
.kpi b{display:block;font-size:60px;font-weight:300;letter-spacing:-.03em;line-height:1}
.kpi b.g{font-weight:500}
.kpi span{display:block;margin-top:10px;color:var(--mute);font-size:20px;line-height:1.3}
.kpi span u{text-decoration:none;color:var(--ink);font-weight:600}
.tri{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}
.fc{min-width:0}
.fc{display:flex;flex-direction:column;gap:12px}
.fc .t{display:flex;align-items:center;gap:14px}
.fc .t b{font-size:24px;font-weight:600;line-height:1.2}
.fc p{font-size:20px;line-height:1.4;color:var(--mute)}
.fc .n{display:flex;align-items:baseline;gap:14px}.fc .n b{font-size:48px;font-weight:300;letter-spacing:-.03em;line-height:1}
.fc .n span{color:var(--mute)}
.fc ul{list-style:none;display:flex;flex-direction:column;gap:6px}
.fc li{font-size:20px;line-height:1.3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:var(--ink)}
.fc li u{text-decoration:none;color:var(--faint);margin-right:10px}
.fc li.more{color:var(--faint)}
.note{color:var(--mute);font-size:20px;display:flex;gap:36px;flex-wrap:wrap}
.note b{color:var(--ink);font-weight:600}
.ch{font-size:20px;letter-spacing:.06em;text-transform:uppercase;color:var(--faint);font-weight:600;margin-bottom:10px}
.cells{display:grid;grid-template-columns:repeat(6,1fr);gap:20px}
.cell b{display:block;font-size:44px;font-weight:300;letter-spacing:-.02em;line-height:1.05}
.cell em{font-style:normal;font-weight:600;color:#0f8a7d;font-size:22px}
.cell span{display:block;color:var(--mute);font-size:20px;margin-top:6px}
.cell s{display:block;color:var(--faint);text-decoration:none;font-size:20px;margin-top:2px}
.orch{display:grid;grid-template-columns:repeat(5,1fr);gap:20px}
.orch .card{display:flex;flex-direction:column;gap:12px}
.orch b{font-size:22px;font-weight:600;line-height:1.25}.orch p{color:var(--mute);font-size:20px;line-height:1.4}
.pm.donuts{display:grid;grid-template-columns:repeat(6,1fr);gap:22px;padding:22px 26px}
/* mah-jong tiles (#892): solid blue → violet gradient, a visible edge drawn by two offset shadows, piled with a slight overlap */
.tile{--t1:#5b7cfa;--t2:#4f63e6;--te:#3c49b8;position:relative;border-radius:26px;padding:20px 24px 24px;color:#fff;min-width:0;
 background:linear-gradient(155deg,var(--t1),var(--t2));
 box-shadow:inset 0 1px 0 rgba(255,255,255,.28),inset 0 0 0 1px rgba(255,255,255,.1),4px 6px 0 var(--te),8px 12px 0 rgba(40,36,120,.22),0 18px 34px rgba(40,36,120,.16)}
.tile.v1{--t1:#5b7cfa;--t2:#4f63e6;--te:#3c49b8}.tile.v2{--t1:#6f6cf6;--t2:#5d55e6;--te:#4339b6}
.tile.v3{--t1:#8b6cf7;--t2:#7651e8;--te:#5835b9}.tile.v4{--t1:#9d5cf2;--t2:#8243dc;--te:#6229ad}
.tile.pale{--t1:#f3f2ff;--t2:#e9e6ff;--te:#cfc9f5;color:var(--ink)}
.tile b.tt{display:block;font-size:26px;font-weight:700;letter-spacing:-.01em;line-height:1.15}
.tile p{font-size:20px;line-height:1.35;opacity:.92;margin-top:6px}
.tile .ic{background:rgba(255,255,255,.18);color:#fff;width:44px;height:44px;border-radius:13px}
.tile.pale .ic{background:#fff;color:#5b63f0}
.tile .hd{display:flex;align-items:center;gap:14px}.tile .hd .st{margin:0 0 0 auto}
.tile .st{display:inline-block;margin-top:10px;font-size:20px;font-weight:600;padding:3px 14px;border-radius:999px;background:rgba(255,255,255,.2);white-space:nowrap}
.tile.pale .st{background:#fff;color:#4a3fc9}
.pile{display:flex;flex-direction:column;padding:0 12px 14px 0}
.pile > .tile + .tile{margin-top:-12px}
.pile > .tile:nth-child(even){margin-left:10px;margin-right:-10px}
.row3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:30px;align-items:start}
.big{font-size:64px;font-weight:300;letter-spacing:-.03em;line-height:1}
.nums{display:flex;gap:26px;margin-top:12px;font-size:20px}.nums b{display:block;font-size:34px;font-weight:600;line-height:1.1}
.m4{display:grid;grid-template-columns:480px minmax(0,1fr) 610px;grid-template-rows:auto auto;gap:26px 28px}
.m4 .left{grid-row:1 / 3;display:flex;flex-direction:column;gap:26px}
.revs{grid-column:2 / 4;display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:0 0;padding:0 12px 14px 0}
.revs .tile{padding:16px 18px 20px}.revs .tile + .tile{margin-left:-6px}.revs .tile:nth-child(even){transform:translateY(8px)}
.revs .tile b.tt{font-size:22px}.revs .tile .st{white-space:normal}.revs .tile u{text-decoration:none;font-size:20px;opacity:.85}
.fl{list-style:none;display:flex;flex-direction:column;gap:6px;margin-top:10px}
.fl li{display:flex;gap:12px;align-items:baseline;font-size:20px;line-height:1.3;white-space:nowrap}
.fl li u{text-decoration:none;color:var(--faint);min-width:52px}.fl li span{overflow:hidden;text-overflow:ellipsis;flex:1;min-width:0}
.fl li i{font-style:normal;font-size:20px;font-weight:600;border-radius:999px;padding:0 10px;flex:none}
.s-ouvert{background:var(--soft);color:var(--mute)}.s-réclamé{background:rgba(79,124,255,.12);color:#3d5bd9}
.s-fait{background:rgba(20,184,166,.12);color:#0f8a7d}.s-écarté{background:var(--soft);color:var(--faint)}
.leg2{display:flex;gap:22px;font-size:20px;color:var(--mute);justify-content:center}.leg2 i{display:inline-block;width:14px;height:14px;border-radius:4px;margin-right:8px;vertical-align:-1px}
.m5{display:grid;grid-template-columns:minmax(0,1fr) 600px;gap:28px;align-items:start}
.cats{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px 22px;padding:0 12px 14px 0}
.cats .tile ul{list-style:none;margin-top:8px}.cats .tile li{font-size:20px;line-height:1.35;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.cats .tile li.more{opacity:.75}
.band{display:flex;gap:28px;align-items:center;padding:18px 26px}
.band b.n{font-size:44px;font-weight:300;letter-spacing:-.02em}
.band .k{color:var(--mute);font-size:20px;line-height:1.4}.band .k b{color:var(--ink)}
.band ul{list-style:none;flex:1;min-width:0;display:grid;grid-template-columns:1fr 1fr;gap:2px 24px}
.band li{font-size:20px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.band li u{text-decoration:none;color:var(--faint);margin-right:10px}
.k2{display:grid;grid-template-columns:520px 1fr 1fr;gap:20px}
.k2 .kg{display:grid;grid-template-columns:1fr 1fr;grid-auto-rows:1fr;gap:16px}
.k2 .kpi{padding:16px 20px}.k2 .kpi b{font-size:44px}.k2 .kpi span{margin-top:6px}
"""


def page(n, title, sub, inner):
    d = datetime.now(timezone.utc)
    return no_legacy(f"""<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>SwiftHFR · semaine {n}</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet"><style>{CSS}</style></head><body>
<div><h1>{title}</h1><p class="sub">{sub}</p></div>
<div class="body">{inner}</div>
<div class="foot"><span><b>SwiftHFR</b> · réécriture native Swift / SwiftUI de HFR+ · point du {d.day} {MONTHS[d.month - 1]} {d.year}</span><span>{n} / {TOTAL}</span></div></body></html>""")


def pct(a, b):
    return round(100 * a / b) if b else 0


def slide_overview(D):
    N = D['now']
    days = D['days']
    mx = max(days.values())
    W = 1728
    slot = W / len(days)
    bw = min(56, slot * 0.66)
    H, base = 190, 160
    bars = ''
    for k, (d, v) in enumerate(days.items()):
        h = (base - 30) * v / mx
        x = k * slot + (slot - bw) / 2
        bars += (f'<rect x="{x:.1f}" y="{base - h:.1f}" width="{bw:.1f}" height="{h:.1f}" rx="8" fill="url(#g)"/>'
                 f'<text x="{x + bw / 2:.1f}" y="{base - h - 8:.1f}" text-anchor="middle" fill="#0f1720" font-weight="600" font-size="20">{v}</text>'
                 f'<text x="{x + bw / 2:.1f}" y="{base + 26}" text-anchor="middle" fill="#8a95a5" font-size="20">{int(d[8:])}</text>')
    svg = (f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}"><defs><linearGradient id="g" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#4f7cff"/>'
           f'<stop offset="1" stop-color="#8b5cf6"/></linearGradient></defs><line x1="0" y1="{base}" x2="{W}" y2="{base}" stroke="#eceef2"/>{bars}</svg>')
    kp = [(D['planned'], 'lots planifiés', "issus de l'audit", ''), (N['done'], f"lots terminés · {pct(N['done'], D['planned'])} %", f"{D['planned'] - N['done']} restants", 'g'),
          (C.fr_num(N['prs']), 'PR fusionnées', 'une PR relue par lot', ''), (C.fr_num(N['commits']), 'commits', 'sur dev-swift', ''),
          (C.fr_num(N['tests']), 'tests automatisés', f"{C.fr_num(N['lines'])} lignes de Swift", ''), (N['issues'], 'issues de suivi', f"{N['open']} ouvertes", '')]
    kic = ['list', 'ci', 'pr', 'chart', 'test', 'tag']
    kh = ''.join(f'<div class="card kpi">{icon(ic, "ic sm")}<b class="{c}">{v}</b><span><u>{a}</u><br>{b}</span></div>' for ic, (v, a, b, c) in zip(kic, kp))
    Y = D['daily']
    mp = len(D['master_prs'])
    tri = [('bug', 'Feedback de test', Y['feedback'], 'retours de test sur appareil'),
           ('wrench', "Fixing de l'app courante", Y['current'], f"issues de l'app courante · {mp} PR ouverte{'s' if mp > 1 else ''} vers master"),
           ('merge', 'Backport dans Swift', Y['backport'], "évolutions de l'app courante à porter")]
    th = ''.join(f'<div class="card fc"><div class="t">{icon(ic)}<b>{t}</b></div><div class="n"><b>{g["open"]}</b><span>ouvertes · {g["closed"]} fermées</span></div><p>{s}</p></div>'
                 for ic, t, g, s in tri)
    note = (f'<div class="note" style="align-items:center"><span>Écarts recensés app courante / Swift : <b>{D["gap"]}</b></span>'
            f'<span>·</span><span>Problèmes de l\'app courante corrigés, au changelog : <b>{D["changelog"]}</b></span></div>')
    first = day_label(next(iter(days)))
    inner = f'<div class="kpis">{kh}</div><div><div class="lbl">Commits par jour sur dev-swift (UTC)</div>{svg}</div><div class="tri">{th}</div>{note}'
    return page(1, "Où en est <b>SwiftHFR</b>", f"Depuis le {first} : un moteur testé, une app qui lit et répond.", inner)


def slide_kpis(D):
    K = D['kpi']
    ci = K['ci']
    tiles = [
        ('tag', K['version'], 'version de l\'app'),
        ('clock', f"{K['days']} j", f"depuis le {day_label(START)}"),
        ('pr', K['prs_7d'], 'PR fusionnées · 7 j'),
        ('pr', K['prs_24h'], 'PR fusionnées · 24 h'),
        ('ci', C.fmt_ci(ci['total']), 'runs CI · 7 j'),
        ('ci', C.fmt_ci(ci['failure']), f"en échec · {C.fmt_ci(ci['cancelled'])} annulés"),
    ]
    kg = ''.join(f'<div class="card kpi">{icon(ic, "ic sm")}<b>{v}</b><span>{t}</span></div>' for ic, v, t in tiles)
    line, bars = progress.charts(D)
    inner = (f'<div class="k2"><div class="kg">{kg}</div>{line}{bars}</div>'
             f'<div><div class="lbl">État des lots de chaque étape · fait › en cours › bloqué › humain › macOS › basse prio. › prêt</div>{progress.donuts(D)}</div>')
    return page(2, "Les <b>indicateurs</b>", f"Rythme du chantier, CI et état de chaque étape · tracker lu le {D['state_at']}.", inner)


def tile_status(lots):
    ls = sorted(C.live_lots({f'LOT-{x:03d}' for x in lots} & set(G.rows), G.rows, DROPPED))
    d = sum(G.done(l) for l in ls)
    if ls and d == len(ls):
        return f'<span class="st">✓ {d} lot{"s" if d > 1 else ""}</span>'
    return f'<span class="st">{d} / {len(ls)} lots</span>'


def slide_done(D):
    """Slide 4: one pile per finished milestone, one tile per main feature."""
    cols = ''
    for k, m in enumerate(('M1', 'M2', 'M3')):
        s = D['ms'][m]
        when = f'terminé le {day_label(s["last"])}' if s['done'] == s['total'] else f'{s["total"] - s["done"]} lot{"s" if s["total"] - s["done"] > 1 else ""} restant{"s" if s["total"] - s["done"] > 1 else ""}'
        head = (f'<div class="tile pale"><div class="hd">{icon(MS_ICON[m])}<b class="tt">{MS_NAMES[m]}</b></div>'
                f'<span class="st">{s["done"]} / {s["total"]} lots · {when}</span></div>')
        tiles = ''.join(f'<div class="tile v{1 + (k + j) % 4}"><div class="hd">{icon(ic)}<b class="tt">{t}</b>{tile_status(ls)}</div><p>{p}</p></div>'
                        for j, (ic, t, p, ls) in enumerate(FEATURES[m]))
        cols += f'<div class="pile">{head}{tiles}</div>'
    done = all(D['ms'][m]['done'] == D['ms'][m]['total'] for m in ('M1', 'M2', 'M3'))
    title = "<b>M1 · M2 · M3</b>, terminés" if done else "<b>M1 · M2 · M3</b>, ce qui est livré"
    return page(4, title, "Ce que les premiers jalons ont livré : une tuile par fonction principale.", f'<div class="row3">{cols}</div>')


RADAR_LINES = {'réglages et thèmes': ['réglages', 'et thèmes']}


def radar(series, W=560, H=380, R=120, label='Radar'):
    """An 8-axis radar of C.AXES at 1:1 (every label 20 px or more). `series`: (counts, fill, stroke), drawn in order."""
    import math
    cx, cy = W / 2, 188
    mx = max([1] + [v for c, *_ in series for v in c.values()])
    ang = [math.radians(-90 + 360 * k / len(C.AXES)) for k in range(len(C.AXES))]
    pt = lambda k, r: (cx + r * math.cos(ang[k]), cy + r * math.sin(ang[k]))
    poly = lambda rs: ' '.join(f'{x:.1f},{y:.1f}' for x, y in (pt(k, r) for k, r in enumerate(rs)))
    s = f'<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="{esc(label)}">'
    for f in (.25, .5, .75, 1):
        s += f'<polygon points="{poly([R * f] * len(C.AXES))}" fill="none" stroke="#e6e8ef"/>'
    for k in range(len(C.AXES)):
        x, y = pt(k, R)
        s += f'<line x1="{cx}" y1="{cy}" x2="{x:.1f}" y2="{y:.1f}" stroke="#e6e8ef"/>'
    for c, fill, stroke in series:
        s += f'<polygon points="{poly([R * c[a] / mx for a in C.AXES])}" fill="{fill}" stroke="{stroke}" stroke-width="3" stroke-linejoin="round"/>'
    main = series[0][0]
    for k, a in enumerate(C.AXES):
        cs, sn = math.cos(ang[k]), math.sin(ang[k])
        x, y = pt(k, R + 22)
        anchor = 'middle' if abs(cs) < .3 else ('start' if cs > 0 else 'end')
        lines = RADAR_LINES.get(a, [a])
        n = len(lines) + 1
        y0 = y - 24 * (n - 1) - 4 if sn < -.3 else (y + 20 if sn > .3 else y - 24 * (n - 1) / 2 + 7)
        tsp = ''.join(f'<tspan x="{x:.1f}" dy="{0 if j == 0 else 24}">{esc(t)}</tspan>' for j, t in enumerate(lines))
        s += (f'<text x="{x:.1f}" y="{y0:.1f}" text-anchor="{anchor}" font-size="20" fill="#5f6b7a">{tsp}'
              f'<tspan x="{x:.1f}" dy="24" font-weight="600" fill="#0f1720">{main[a]}</tspan></text>')
    return s + '</svg>'


STATUS_ORDER = ['ouvert', 'réclamé', 'fait', 'écarté']


def slide_m4(D):
    """Slide 5: M4 lots, what changed, test feedback with its radar, the end-of-M4 review tiles (bottom right)."""
    M, s = D['m4'], D['ms']['M4']
    L = M['lots']
    lots = (f'<div class="tile v2"><div class="hd">{icon("flag")}<b class="tt">{MS_NAMES["M4"]}</b></div>'
            f'<div class="big" style="margin-top:14px">{s["done"]}<span style="font-size:30px;opacity:.8"> / {s["total"]} lots</span></div>'
            f'<div class="nums"><span><b>{L["fait"]}</b>faits</span><span><b>{L["en cours"]}</b>en cours</span><span><b>{L["à faire"]}</b>à faire</span></div>'
            f'<p>Hors lots : {M["issues"]["done"]} / {M["issues"]["total"]} issues M4 fermées.</p></div>')
    since = M['lots_since']
    li = ''.join(f'<li><span>✓ {esc(x)}</span></li>' for x in since[:4])
    if len(since) > 4:
        li += f'<li><span>+ {len(since) - 4} autres lots</span></li>'
    li = li or '<li><span>Aucun lot M4 fermé.</span></li>'
    changes = (f'<div class="card"><div class="ch">Depuis le {day_label(D["since"])}</div><ul class="fl">{li}</ul>'
               f'<p style="color:var(--mute);margin-top:10px">Issues M4 : {M["issues"]["since"]} fermées, {M["issues"]["new"]} nouvelles.</p></div>')
    F = M['fb']
    st = ' · '.join(f'<b>{F["status"].get(k, 0)}</b> {k}s' for k in STATUS_ORDER if F['status'].get(k) or k != 'écarté')
    added = F['added']
    rows = ''.join(f'<li><u>#{n}</u><span>{esc(t)}</span><i class="s-{stt}">{stt}</i></li>' for n, t, stt in added[:6])
    if len(added) > 6:
        rows += f'<li><span style="color:var(--faint)">+ {len(added) - 6} autres</span></li>'
    rows = rows or '<li><span style="color:var(--faint)">Aucun nouveau retour.</span></li>'
    fb = (f'<div class="card"><div class="ch">Feedback de test · {F["total"]}</div><div style="font-size:22px">{st}</div>'
          f'<div class="ch" style="margin-top:18px">Ajoutés depuis le {day_label(D["since"])} · {len(added)}</div><ul class="fl">{rows}</ul></div>')
    rad = (f'<div class="card"><div class="ch">Où se concentrent les retours</div>'
           f'{radar([(F["axes"], "rgba(139,92,246,.16)", "#8b5cf6"), (F["axes_open"], "rgba(79,124,255,.18)", "#4f7cff")], W=556, label="Retours de test par domaine")}'
           f'<div class="leg2"><span><i style="background:#8b5cf6"></i>tous ({F["total"]})</span><span><i style="background:#4f7cff"></i>ouverts ({sum(F["axes_open"].values())})</span></div></div>')
    rv = ''
    for k, r in enumerate(M['reviews']):
        found = (f'{r["found"]} constat{"s" if r["found"] > 1 else ""} · {r["found_open"]} ouvert{"s" if r["found_open"] > 1 else ""}'
                 if r['found'] else 'aucun constat')
        rv += (f'<div class="tile v{1 + k % 4}"><u>#{r["n"]} · {r["state"]}</u><b class="tt">{esc(r["title"])}</b>'
               f'<p>{esc(r["goal"])}</p><span class="st">{found}</span></div>')
    inner = (f'<div class="m4"><div class="left">{lots}{changes}</div>{fb}{rad}'
             f'<div class="revs">{rv}</div></div>')
    return page(5, "<b>M4</b> en détail", "Les lots, les retours de test et les revues de fin de M4.", inner)


def faites(n):
    """French past participle agreeing with a count: one item (or none) is « faite », more are « faites »."""
    return "faites" if n > 1 else "faite"


def slide_m5(D):
    """Slide 6: M5 contents as tiles by category, the category radar, and the band of the issues outside every milestone."""
    M = D['m5']
    tiles = ''
    cats = sorted(M['cats'].items(), key=lambda x: (-len(x[1]), C.AXES.index(x[0])))
    if len(cats) > 6:  # never drop a category: the smallest ones share the last tile, one line each
        rest = cats[5:]
        cats = cats[:5] + [('et aussi', [(f'{a[0].upper() + a[1:]} · {len(v)}', False) for a, v in rest])]
    for k, (a, items) in enumerate(cats):
        li = ''.join(f'<li>{"✓ " if d else ""}{esc(t)}</li>' for t, d in items[:5])
        if len(items) > 5:
            li += f'<li class="more">+ {len(items) - 5} autres</li>'
        n = len(items) if a in M['cats'] else sum(len(v) for _, v in rest)
        tiles += (f'<div class="tile v{1 + k % 4}"><div class="hd">{icon(AXIS_ICON.get(a, "list"))}<b class="tt">{a[0].upper() + a[1:]} · {n}</b></div>'
                  f'<ul>{li}</ul></div>')
    rad = (f'<div class="card"><div class="ch">Les catégories de M5 · {M["total"]}</div>'
           f'{radar([(M["axes"], "rgba(139,92,246,.18)", "#8b5cf6")], W=548, label="Contenu de M5 par catégorie")}</div>')
    O = D['outside']
    band = ''
    if O['open']:
        kinds = ' · '.join(f'<b>{v}</b> {KIND_FR.get(k, k)}' for k, v in O['kinds'].items())
        li = ''.join(f'<li><u>#{n}</u>{esc(t)}</li>' for n, t in O['open'][:4])
        band = (f'<div class="card band"><div><b class="n">{len(O["open"])}</b></div><div class="k"><b>Issues hors jalon, ouvertes</b><br>{kinds}</div>'
                f'<ul>{li}</ul></div>')
    inner = f'<div class="m5"><div class="cats">{tiles}</div>{rad}</div>{band}'
    return page(6, "<b>M5</b> en détail", f"Les évolutions après M4, par catégorie : {M['done']} {faites(M['done'])} sur {M['total']}.", inner)


KIND_FR = {'captures': 'captures', 'bug': 'bugs', 'feature': 'fonctions', 'chore': 'tâches', 'docs': 'docs', 'security': 'sécurité', 'lot': 'lots', 'autre': 'autres'}


def slide_today(D):
    N, T = D['now'], D['then']

    def cell(label, a, b, fmt=str, ic='chart'):
        return f'<div class="card cell">{icon(ic, "ic sm")}<b>{fmt(a)}<em>+{fmt(a - b)}</em></b><span>{label}</span><s>le {day_label(D["since"])} : {fmt(b)}</s></div>'
    cells = ''.join([cell('lots terminés', N['done'], T['done'], ic='ci'), cell('PR fusionnées', N['prs'], T['prs'], C.fr_num, 'pr'), cell('commits', N['commits'], T['commits'], C.fr_num),
                     cell('tests', N['tests'], T['tests'], C.fr_num, 'test'), cell('lignes de Swift', N['lines'], T['lines'], C.fr_num, 'list'), cell('issues de suivi', N['issues'], T['issues'], ic='tag')])
    rows = ''
    bar = lambda label, then, done, total, right: (
        f'<div style="display:grid;grid-template-columns:330px 1fr 380px;gap:24px;align-items:center"><b style="font-size:22px">{label}</b>'
        f'<div class="bar"><i class="then" style="width:{100 * then / max(1, total):.1f}%;z-index:0"></i><i style="width:{100 * done / max(1, total):.1f}%;opacity:.9;z-index:1"></i></div>'
        f'<span style="text-align:right;font-size:22px">{right}</span></div>')
    plus = lambda x, unit: f'<em style="font-style:normal;color:#0f8a7d;font-weight:600">+{x} {unit}</em>'
    for m in MS:
        s = D['ms'][m]
        rows += bar(MS_NAMES[m], s['then'], s['done'], s['total'], f'{pct(s["done"], s["total"])} % {plus(pct(s["done"], s["total"]) - pct(s["then"], s["total"]), "pts")}')
    O = D['outside']
    rows += bar('Hors jalon (issues)', O['then_done'], O['done'], O['total'],
                f'{O["done"]} / {O["total"]} {plus(O["done"] - O["then_done"], faites(O["done"] - O["then_done"]))} · +{O["total"] - O["then_total"]} créées')
    oh = ''.join(f'<div class="card">{icon(ic)}<b>{t}</b><p>{p}</p></div>' for ic, t, p in ORCH)
    inner = (f'<div><div class="lbl">Depuis le {day_label(D["since"])}</div><div class="cells">{cells}</div></div>'
             f'<div class="card" style="display:flex;flex-direction:column;gap:12px;padding:20px 30px">{rows}</div>'
             f'<div><div class="lbl">Organisation du travail</div><div class="orch">{oh}</div></div>')
    return page(3, "<b>Aujourd'hui</b>", f"Ce qui a changé depuis le {day_label(D['since'])} (barre claire : l'état de départ) et comment le chantier est mené.", inner)


def slides(D):
    return {1: slide_overview(D), 2: slide_kpis(D), 3: slide_today(D), 4: slide_done(D), 5: slide_m4(D), 6: slide_m5(D)}


if __name__ == '__main__':
    args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith('--') and sys.argv[i - 1] not in ('--since', '--state')]
    if not args:
        raise SystemExit(__doc__)
    out = Path(args[0])
    (out / 'slides').mkdir(parents=True, exist_ok=True)
    default_since = (datetime.now(timezone.utc) - timedelta(days=7)).date().isoformat()
    since = sys.argv[sys.argv.index('--since') + 1] if '--since' in sys.argv else default_since
    state_file = sys.argv[sys.argv.index('--state') + 1] if '--state' in sys.argv else None
    issues, pulls = fetch_state(out, state_file)
    load_engine()
    if issues is None:
        issues = [i for i in gh_pages(f'repos/{REPO}/issues?state=all') if 'pull_request' not in i]
        pulls = gh_pages(f'repos/{REPO}/pulls?state=all&base=dev-swift')
    issues = [i for i in issues if 'pull_request' not in i]
    D = gather(since, issues, pulls)
    (out / 'deck.json').write_text(json.dumps({k: v for k, v in D.items() if k != 'titles'}, indent=1, ensure_ascii=False))
    for n, h in slides(D).items():
        (out / 'slides' / f'slide-{n:02d}.html').write_text(h, encoding='utf-8')
    print('slides ->', out / 'slides', 'state', G.GENERATED_AT, {m: (D['ms'][m]['done'], D['ms'][m]['total']) for m in MS})
