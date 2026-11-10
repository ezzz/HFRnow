"""Weekly deck (HTML slides, French) from the tracker, the docs and git. Delivered to the maintainer only, never posted.

  python3 tooling/roadmap/weekly/build.py OUTDIR [--since 2026-11-03]   # needs `gh` (GH_TOKEN), full git history
  node tooling/roadmap/weekly/shot.js OUTDIR                             # slides/*.html -> 2880x1620 JPEG, checks

Slides: 1 vue d'ensemble · 2 indicateurs (KPIs, progress model) · 3 jalons M1 to M5 · 4-7 M1, M2, M3, M4 (feature
cards) · 8 l'app au quotidien (feedback, current app, backport) · 9 M5 · 10 aujourd'hui (difference with the baseline
date, organisation). The legacy app is « l'app courante » on every slide. Nothing names or ranks a person.

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

G = progress = None  # loaded by load_engine() once the fresh state is in place (generate reads it at import time)

TOTAL = 10
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
# Open Mac checks that gate a milestone but are not lots (shown in its « reste à faire » card while open)
EXTRA_MAC = {'M1': [344, 322]}

# Feature cards: (icon, title, one-liner, lots of the card). Written from docs/ROADMAP.md and the lot scopes of
# lots.json; the pill of each card is computed from its lots.
FEATURES = {
    'M1': [
        ('lock', 'Comptes et connexion', "Plusieurs comptes ; la session est validée avant de remplacer les cookies, puis rafraîchie.", [13, 42, 43, 44, 65, 81]),
        ('compass', 'Navigation adaptative', "Une seule app pour iPhone, iPad et pliables : catégories, favoris, messages, plus.", [21, 22, 24, 82, 170]),
        ('book', 'Lecteur de sujet', "Messages normalisés, liens internes ouverts dans l'app, aucun script de page exécuté.", [30, 33, 34, 83, 137]),
        ('pencil', 'Réponse', "Rédiger, envoyer, brouillons ; un succès n'est affiché que si HFR le confirme.", [36, 37, 48, 84]),
        ('beaker', "Oracle de l'app courante", "Audit, fixtures anonymisées et oracle : chaque parser est comparé à l'app courante.", [0, 1, 2, 3, 4, 5, 71]),
    ],
    'M2': [
        ('quote', 'Citer, éditer, créer', "Citation et multi-citation, édition et suppression de ses messages, nouveau sujet.", [85, 86, 87, 88, 89]),
        ('smile', 'Smileys, images, GIF', "Sélecteur de smileys avec recherche, envoi d'images, historique, GIF.", [102, 103, 104, 105, 155]),
        ('photo', 'Médias dans le lecteur', "Réglages d'affichage et d'images, vidéos au tap, visionneuse plein écran.", [106, 107, 108, 109, 111]),
        ('search', 'Recherche et filtres', "Recherche du forum et dans un sujet, filtre des messages, profils, listes.", [113, 114, 115, 116, 117]),
        ('envelope', 'MP, sondages, hors ligne', "Liste des MP et badge, actions, nouveau MP ; vote aux sondages, lecture hors ligne.", [124, 125, 126, 127, 128, 136, 139, 171]),
    ],
    'M3': [
        ('puzzle', 'Parsers', "MP, sondages, profils, citations, vidéos, liens entrants : chaque page lue comme l'app courante.", [23, 26, 27, 28, 31, 32, 35, 38, 95, 97]),
        ('arrows', 'Flux du client', "Recherche, alerte modérateur, drapeaux et favoris, vote, MP, smileys, Giphy.", [46, 47, 49, 50, 51, 53, 54, 58, 92, 93, 94, 98]),
        ('db', 'Stockage', "Réglages, listes noire et blanche, brouillons, caches, import des données, hors ligne.", [60, 61, 63, 64, 66, 67, 68, 72, 90, 91]),
        ('cloud', 'Synchronisation', "Fil MPStorage et iCloud clé-valeur, sans perte en cas de conflit.", [52, 62, 73, 172]),
    ],
    'M4': [
        ('palette', 'Apparence', "Thèmes, sombre OLED, icônes alternatives, Liquid Glass hors lecteur et dans le lecteur.", [121, 122, 123, 185, 186]),
        ('access', 'Accessibilité', "Passe complète sur les listes, la navigation, le lecteur et la rédaction.", [162, 163]),
        ('cloud', 'Synchro et import', "Synchro MPStorage, trousseau iCloud en option, import au premier lancement.", [130, 131, 158, 173]),
        ('shield', 'Modération et comptes', "Alerte modérateur, listes noire et blanche, suppression de compte, À propos.", [118, 120, 135, 156, 157]),
    ],
    'M5': [
        ('compass', 'Navigation', None, [110, 112, 148, 149, 145]),
        ('home', 'Accueil et suivi', None, [143, 144, 154, 178, 142]),
        ('pencil', 'Rédaction', None, [152, 153, 151, 184, 175]),
        ('envelope', 'MP et listes', None, [181, 182, 177, 180]),
        ('phone', 'Système', None, [138, 150, 141, 187]),
    ],
}
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
    return {'M1': G.M1, 'M2': G.M2, 'M3': G.M3, 'M4': G.M4, 'M5': G.M5}


def gather(since, issues, pulls_all):
    now_dt = datetime.now(timezone.utc)
    pulls = [p for p in pulls_all if p.get('merged_at')]
    byn = {i['number']: i for i in issues}
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
        'since': since, 'planned': len(G.rows), 'state_at': G.GENERATED_AT,
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
        'titles': {i['number']: i['title'] for i in issues if i['state'] == 'open'},
    }


def day_label(d):
    y, m, dd = map(int, d[:10].split('-'))
    return f'{dd} {MONTHS[m - 1]}'


def dependents():
    c = Counter()
    for l, r in G.rows.items():
        if not G.done(l):
            for d in G.deps(r):
                c[d] += 1
    return c


def lot_label(l):
    n = lot_n(l)
    return LOT_FR.get(n) or G.short(re.sub(r'`|\*', '', G.rows[l]['scope']), 40)


def milestone_view(ms, D):
    """Blockers and levers of a milestone: captures waited on, ready engine lots (cloud), ready app lots (Mac)."""
    cap = Counter()
    ready_cloud, ready_mac = [], []
    dep = dependents()
    for l in ms:
        if G.done(l):
            continue
        r = G.rows[l]
        n = r['issue']
        if n in G.CAPTURE:
            for c in re.findall(r'#\d+', G.CAPTURE[n]):
                cap[c] += 1
        elif n in G.READY or n in G.CLAIMED:
            (ready_mac if r['module'] == 'App' else ready_cloud).append((dep[l], l))
    pick = lambda xs: [(l[4:], lot_label(l), u) for u, l in sorted(xs, key=lambda x: (-x[0], x[1]))[:3]]
    caps = [(k, v, C.clean_title(re.sub(r'^(\[[^\]]*\]\s*)*Capture( \(Mac\))?:\s*', '', D['titles'].get(int(k[1:]), '')), 40)) for k, v in cap.most_common(3)]
    return {'caps': caps, 'cloud': pick(ready_cloud), 'n_cloud': len(ready_cloud), 'mac': pick(ready_mac), 'n_mac': len(ready_mac)}


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
.hero{border-radius:var(--r);padding:36px 38px;background:linear-gradient(140deg,#eef2ff 0%,#f1ebff 60%,#f8f0ff 100%);border:1px solid rgba(139,92,246,.14);
 display:flex;flex-direction:column;gap:18px;position:relative;overflow:hidden}
.hero:after{content:"";position:absolute;right:-90px;top:-90px;width:300px;height:300px;border-radius:50%;background:radial-gradient(closest-side,rgba(139,92,246,.18),transparent)}
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
.feat{display:grid;grid-template-columns:540px 1fr;gap:24px;flex:none}
.feat .cards .span2{grid-column:span 2}
.feat .cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));grid-auto-rows:1fr;gap:20px}
.feat .cards.c2{grid-template-columns:repeat(2,1fr)}
.lev{display:grid;grid-template-columns:repeat(3,1fr);gap:20px}
.lev h4{font-size:20px;letter-spacing:.06em;text-transform:uppercase;font-weight:600;margin-bottom:8px}
.lev .b h4{color:#d0503f}.lev .c h4{color:#0f8a7d}.lev .m h4{color:var(--a2)}
.lev li{list-style:none;font-size:20px;line-height:1.35;padding:3px 0;display:flex;gap:12px;white-space:nowrap}
.lev li u{text-decoration:none;color:var(--faint);min-width:52px}.lev li span{overflow:hidden;text-overflow:ellipsis}
.lev li em{font-style:normal;color:var(--mute);margin-left:auto}
.lev p{color:var(--mute);font-size:20px}
.msr{display:grid;grid-template-columns:48px 430px 1fr 130px 330px;align-items:center;gap:24px;padding:20px 28px}
.msr .nm b{display:block;font-size:24px;font-weight:600}.msr .nm small{display:block;color:var(--mute);font-size:20px;margin-top:4px;line-height:1.3}
.msr .ct{font-size:34px;font-weight:300;text-align:right;letter-spacing:-.02em}.msr .ct small{font-size:20px;color:var(--mute)}
.msr .ch{grid-column:3 / 4;display:flex;gap:16px;flex-wrap:wrap;color:var(--mute);font-size:20px;margin-top:10px}
.msr .ch i{display:inline-block;width:12px;height:12px;border-radius:4px;margin-right:7px}
.ch{font-size:20px;letter-spacing:.06em;text-transform:uppercase;color:var(--faint);font-weight:600;margin-bottom:10px}
.cells{display:grid;grid-template-columns:repeat(6,1fr);gap:20px}
.cell b{display:block;font-size:44px;font-weight:300;letter-spacing:-.02em;line-height:1.05}
.cell em{font-style:normal;font-weight:600;color:#0f8a7d;font-size:22px;margin-left:8px}
.cell span{display:block;color:var(--mute);font-size:20px;margin-top:6px}
.cell s{display:block;color:var(--faint);text-decoration:none;font-size:20px;margin-top:2px}
.orch{display:grid;grid-template-columns:repeat(5,1fr);gap:20px}
.orch .card{display:flex;flex-direction:column;gap:12px}
.orch b{font-size:22px;font-weight:600;line-height:1.25}.orch p{color:var(--mute);font-size:20px;line-height:1.4}
.pm.donuts{display:grid;grid-template-columns:repeat(6,1fr);gap:22px;padding:22px 26px}
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


def ms_pill(D, m):
    s = D['ms'][m]
    if s['total'] and s['done'] == s['total']:
        return f'<span class="pill ok">✓ Terminé · {s["done"]}/{s["total"]} · {day_label(s["last"])}</span>'
    if not s['done']:
        return f'<span class="pill todo">À venir · 0/{s["total"]}</span>'
    return f'<span class="pill">En cours · {s["done"]}/{s["total"]}</span>'


def card_pill(lots):
    ls = [f'LOT-{x:03d}' for x in lots if f'LOT-{x:03d}' in G.rows]
    d = sum(G.done(l) for l in ls)
    if ls and d == len(ls):
        return '<span class="pill ok">✓ Livré</span>'
    if d:
        return f'<span class="pill">En cours · {d}/{len(ls)}</span>'
    return f'<span class="pill todo">À faire · {len(ls)} lots</span>'


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
    kh = ''.join(f'<div class="card kpi"><b class="{c}">{v}</b><span><u>{a}</u><br>{b}</span></div>' for v, a, b, c in kp)
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
        ('ci', f"{C.fmt_ci(ci['failure'])} · {C.fmt_ci(ci['cancelled'])}", 'en échec · annulés'),
    ]
    kg = ''.join(f'<div class="card kpi"><b>{v}</b><span>{t}</span></div>' for _, v, t in tiles)
    line, bars = progress.charts(D)
    inner = (f'<div class="k2"><div class="kg">{kg}</div>{line}{bars}</div>'
             f'<div><div class="lbl">État des lots de chaque étape · fait › en cours › bloqué › humain › macOS › basse prio. › prêt</div>{progress.donuts(D)}</div>')
    return page(2, "Les <b>indicateurs</b>", f"Rythme du chantier, CI et état de chaque étape · tracker lu le {D['state_at']}.", inner)


def slide_milestones(D):
    rows = ''
    for m in MS:
        s = D['ms'][m]
        b = s['buckets']
        chips = ''.join(f'<span><i style="background:{progress.BUCKET_COLORS[k]}"></i>{b[k]} {progress.SHORT_BUCKET[k]}</span>' for k in progress.BUCKETS if b.get(k) and k != 'done')
        if s['done'] == s['total']:
            date = f'<span class="pill ok">✓ Terminé le {day_label(s["last"])}</span>'
        elif s['last']:
            date = f'<span class="pill">En cours · lot fermé le {day_label(s["last"])}</span>'
        else:
            date = '<span class="pill todo">Pas encore ouvert</span>'
        rows += (f'<div class="card msr">{icon(MS_ICON[m])}<div class="nm"><b>{MS_NAMES[m]}</b><small>{MS_GOALS[m]}</small></div>'
                 f'<div><div class="bar"><i style="width:{100 * s["done"] / max(1, s["total"]):.1f}%"></i></div>'
                 f'<div class="ch" style="text-transform:none;letter-spacing:0;margin:10px 0 0;font-weight:400">{chips or "<span>tous les lots sont faits</span>"}</div></div>'
                 f'<div class="ct">{s["done"]}<small> / {s["total"]}</small></div><div>{date}</div></div>')
    return page(3, "Les <b>jalons</b> M1 à M5", "Lots faits sur le total de chaque jalon ; la date est la fermeture du dernier lot.", f'<div style="display:flex;flex-direction:column;gap:16px">{rows}</div>')


def left_card(m, D):
    """The dashed « reste à faire » card of a milestone: its lots not done, then the open Mac checks that gate it."""
    ls = sorted((l for l in ms_lots()[m] if not G.done(l)), key=lambda l: (G.state(l)[0] != 'ongoing', lot_n(l)))
    extra = [n for n in EXTRA_MAC.get(m, []) if n in D['titles']]
    items = [f'<li><u>{l[4:]}</u>{esc(lot_label(l))}</li>' for l in ls[:5]]
    items += [f'<li><u>#{n}</u>vérification sur le Mac</li>' for n in extra]
    more = len(ls) - 5
    if more > 0:
        items.append(f'<li class="more">+ {more} autres lots</li>')
    if not items:
        return '<div class="card dash fc"><div class="t">' + icon('ci') + '<b>Reste à faire</b></div><p>Rien : le jalon est fermé. La suite est dans les jalons suivants.</p></div>'
    return f'<div class="card dash fc"><div class="t">{icon("list")}<b>Reste à faire · {len(ls)}</b></div><ul>{"".join(items)}</ul></div>'


def levers(m, D):
    v = milestone_view(ms_lots()[m], D)
    if not (v['caps'] or v['cloud'] or v['mac']):
        return ''
    li = lambda xs, f, empty: ''.join(f(*x) for x in xs) or f'<p>{empty}</p>'
    caps = li(v['caps'], lambda c, n, t: f'<li><u>{c}</u><span>{esc(t)}</span><em>{n} lot{"s" if n > 1 else ""}</em></li>', 'Aucune capture attendue.')
    cloud = li(v['cloud'], lambda l, s, u: f'<li><u>{l}</u><span>{esc(s)}</span><em>{"débloque " + str(u) if u else ""}</em></li>', 'Aucun lot moteur prêt.')
    mac = li(v['mac'], lambda l, s, u: f'<li><u>{l}</u><span>{esc(s)}</span><em>{"débloque " + str(u) if u else ""}</em></li>', 'Aucun lot écran prêt.')
    return (f'<div class="lev"><div class="card grey b"><h4>Blocages · captures</h4><ul>{caps}</ul></div>'
            f'<div class="card grey c"><h4>Leviers cloud · {v["n_cloud"]} prêts</h4><ul>{cloud}</ul></div>'
            f'<div class="card grey m"><h4>Lots écran · {v["n_mac"]} prêts</h4><ul>{mac}</ul></div></div>')


def hero(m, D, text=None):
    s = D['ms'][m]
    return (f'<div class="hero">{icon(MS_ICON[m])}<h2>{MS_NAMES[m]}</h2><p>{text or MS_GOALS[m]}</p>'
            f'<div class="big g">{pct(s["done"], s["total"])} %</div><div class="bar" style="background:rgba(255,255,255,.7)"><i style="width:{100 * s["done"] / max(1, s["total"]):.1f}%"></i></div>'
            f'{ms_pill(D, m)}</div>')


def slide_feature(n, m, D, title, sub):
    cards = ''.join(f'<div class="card fc"><div class="t">{icon(ic)}<b>{t}</b></div><p>{p}</p><div style="margin-top:auto">{card_pill(ls)}</div></div>'
                    for ic, t, p, ls in FEATURES[m])
    left = left_card(m, D)
    if len(FEATURES[m]) % 3 == 1:  # 4 cards + the dashed one: it takes two cells, no hole in the 3-column grid
        left = left.replace('class="card dash fc"', 'class="card dash fc span2"', 1)
    inner = f'<div class="feat">{hero(m, D)}<div class="cards">{cards}{left}</div></div>{levers(m, D)}'
    return page(n, title, sub, inner)


def slide_daily(D):
    Y = D['daily']

    def lst(items, k=7, extra=()):
        rows = [f'<li><u>#{n}</u>{esc(t)}</li>' for n, t in items[:k]]
        rows += [f'<li><u>PR {n}</u>{esc(t)}</li>' for n, t in extra]
        if len(items) > k:
            rows.append(f'<li class="more">+ {len(items) - k} autres</li>')
        return ''.join(rows) or '<li class="more">Aucune issue ouverte.</li>'
    mp = D['master_prs']
    cards = [
        ('bug', 'Feedback de test', Y['feedback'], 'retours de test sur appareil', lst(Y['feedback']['items'], 13)),
        ('wrench', "L'app courante", Y['current'], f"correctifs · {len(mp)} PR ouvertes vers master", lst(Y['current']['items'], 4, mp[:5])),
        ('merge', 'Backport dans Swift', Y['backport'], "évolutions de l'app courante à porter", lst(Y['backport']['items'], 13)),
    ]
    h = ''.join(f'<div class="card fc"><div class="t">{icon(ic)}<b>{t}</b></div><div class="n"><b>{g["open"]}</b><span>ouvertes · {g["closed"]} fermées</span></div>'
                f'<p>{s}</p><ul>{l}</ul></div>' for ic, t, g, s, l in cards)
    return page(8, "L'app <b>au quotidien</b>", "Ce qui arrive en continu à côté des jalons : les retours de test, l'app courante et ce qu'il faut reporter dans Swift.",
                f'<div class="tri" style="flex:1;max-height:720px">{h}</div>')


def slide_m5(D):
    cards = ''
    for ic, t, _, ls in FEATURES['M5']:
        lots = [f'LOT-{x:03d}' for x in ls if f'LOT-{x:03d}' in G.rows]
        li = ''.join(f'<li>{"✓ " if G.done(l) else ""}{esc(lot_label(l))}</li>' for l in lots)
        cards += f'<div class="card fc"><div class="t">{icon(ic)}<b>{t}</b></div><ul>{li}</ul><div style="margin-top:auto">{card_pill(ls)}</div></div>'
    listed = {f'LOT-{x:03d}' for *_, ls in FEATURES['M5'] for x in ls}
    rest = sorted(l for l in G.M5 if l not in listed)
    cards += (f'<div class="card dash fc"><div class="t">{icon("list")}<b>Aussi dans M5 · {len(rest)}</b></div>'
              f'<ul>{"".join(f"<li><u>{l[4:]}</u>{esc(lot_label(l))}</li>" for l in rest[:5])}</ul></div>')
    text = "Les évolutions que la parité n'exige pas : décisions UX, propositions de fonctions, secondes moitiés des lots scindés. Ouvert par l'orchestrateur après M4."
    inner = f'<div class="feat">{hero("M5", D, text)}<div class="cards">{cards}</div></div>'
    return page(9, "<b>M5</b> · les évolutions", "Planifié après la parité de M4, jamais abandonné.", inner)


def slide_today(D):
    N, T = D['now'], D['then']

    def cell(label, a, b, fmt=str):
        return f'<div class="card cell"><b>{fmt(a)}<em>+{fmt(a - b)}</em></b><span>{label}</span><s>le {day_label(D["since"])} : {fmt(b)}</s></div>'
    cells = ''.join([cell('lots terminés', N['done'], T['done']), cell('PR fusionnées', N['prs'], T['prs'], C.fr_num), cell('commits', N['commits'], T['commits'], C.fr_num),
                     cell('tests', N['tests'], T['tests'], C.fr_num), cell('lignes de Swift', N['lines'], T['lines'], C.fr_num), cell('issues de suivi', N['issues'], T['issues'])])
    rows = ''
    for m in MS[:4]:
        s = D['ms'][m]
        rows += (f'<div style="display:grid;grid-template-columns:330px 1fr 190px;gap:24px;align-items:center"><b style="font-size:22px">{MS_NAMES[m]}</b>'
                 f'<div class="bar"><i class="then" style="width:{100 * s["then"] / s["total"]:.1f}%;z-index:0"></i><i style="width:{100 * s["done"] / s["total"]:.1f}%;opacity:.9;z-index:1"></i></div>'
                 f'<span style="text-align:right;font-size:22px">{pct(s["done"], s["total"])} % <em style="font-style:normal;color:#0f8a7d;font-weight:600">+{pct(s["done"], s["total"]) - pct(s["then"], s["total"])} pts</em></span></div>')
    oh = ''.join(f'<div class="card">{icon(ic)}<b>{t}</b><p>{p}</p></div>' for ic, t, p in ORCH)
    inner = (f'<div><div class="lbl">Depuis le {day_label(D["since"])}</div><div class="cells">{cells}</div></div>'
             f'<div class="card" style="display:flex;flex-direction:column;gap:16px;padding:24px 30px">{rows}</div>'
             f'<div><div class="lbl">Organisation du travail</div><div class="orch">{oh}</div></div>')
    return page(10, "<b>Aujourd'hui</b>", f"Ce qui a changé depuis le {day_label(D['since'])} (barre claire : l'état de départ) et comment le chantier est mené.", inner)


def slides(D):
    return {
        1: slide_overview(D),
        2: slide_kpis(D),
        3: slide_milestones(D),
        4: slide_feature(4, 'M1', D, "<b>M1</b> · le MVP", "La première build utilisable, sur iPhone, iPad et pliables."),
        5: slide_feature(5, 'M2', D, "<b>M2</b> · lecture et réponse", "Tout ce que l'app courante sait faire pour lire et répondre."),
        6: slide_feature(6, 'M3', D, "<b>M3</b> · le moteur", "HFRKit, sans interface : parsers, réseau, flux et stockage, testés contre l'app courante."),
        7: slide_feature(7, 'M4', D, "<b>M4</b> · la version finale", "La parité avec l'app courante, l'accessibilité et l'App Store."),
        8: slide_daily(D),
        9: slide_m5(D),
        10: slide_today(D),
    }


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
