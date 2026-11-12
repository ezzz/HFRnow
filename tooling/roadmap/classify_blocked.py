"""Dry-run classification of every open `status: blocked` issue (#835 part 3). Reads the tracker, writes nothing to it.

  python3 tooling/roadmap/classify_blocked.py --fetch [--json PLAN.json] [--md TABLE.md]
  python3 tooling/roadmap/classify_blocked.py ISSUES.json PULLS.json COMMENTS.json [--json …] [--md …]
      (offline: `gh api` or `list_issues` dumps; COMMENTS.json maps an issue number to its comments)

One outcome per issue (AGENTS.md §7, harness METHODOLOGY §4):
  on-hold         held by a decision: an M5 lot (or M5 item) while m5.M5_OPEN is False, or an operator's call cited on
                  the issue (HOLD below); the plan carries the decision sentence and its link
  blocked         a blocker is still open: the plan carries the exact `### Blocked by` lines (`#n …` or free text)
  ready           every blocker found is closed, no decision holds it
  needs-decision  cannot tell: the plan carries the question for the operator
Blockers are read from the issue's own `### Blocked by` and `### Depends on` sections, its "Blocked by" sentences, its
lot's `Depends on` cell (lots.json) and the open captures that want it; FREE lists the external blockers read by hand.
The JSON plan is what the apply step (#835 part 4) runs after the operator's go; it is never committed.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / 'scripts'))
import m5  # noqa: E402
from hygiene import FILLER, blockers_of, numeric_deps  # noqa: E402
from sync_state import REPO, build, gh_pages, labels  # noqa: E402
import issue_claims  # noqa: E402

BLOCKED = 'status: blocked'
URL = f'https://github.com/{REPO}/issues/'
M5_DECISION = ('Held by the M5_OPEN decision: M5 opens after the M4 parity is validated, and the orchestrator opens it '
               '(operator decisions of 2026-11-02 on #379).', URL + '379#issuecomment-6573879240')
# Decisions cited on the issue itself (read by hand on 2026-11-11): the issue waits on a call, not on a dependency.
HOLD = {
    251: ('Held by the operator\'s decision of 2026-11-11: LOT-161 is launched when the M4 lots are at 100 %; the '
          'version/build and signing questions stay with the operator (comment of 2026-11-09).',
          URL + '251#issuecomment-6806628944'),
    326: ('Held by the operator\'s schedule (decision of 2026-10-29, this issue\'s "When"): the audit runs after every '
          'other lot of the M4 board (#324) and before LOT-164 (#254).', URL + '326'),
    774: ('Held by the operator\'s schedule (request of 2026-11-10, this issue\'s "When"): the review starts when the M4 '
          'lots are merged; the orchestrator starts it.', URL + '774'),
}
# External blockers (not an issue of this tracker), read by hand; each line goes to `### Blocked by` as written.
FREE = {
    143: ['ezzz\'s owner actions of EZZZ-CUTOVER step 9 (ADR 0010)'],
    144: ['A CodeQL-compatible Xcode 27 runner on GitHub Actions (ADR 0012)'],
    310: ['Contact with the Android app\'s maintainer: a message outside GitHub, on the operator\'s go (AGENTS.md §0)'],
    447: ['The iCloud key-value storage capability on the App ID and the `com.apple.developer.ubiquity-kvstore-identifier` '
          'entitlement in the app (ADR 0013 §9: a developer-portal action by the maintainer; no `.entitlements` file in `App/` yet)'],
    635: ['The sub-domain choice of the PO'],
    708: ['The in-place update shipped on the App Store, plus the delay the operator sets (users who skip versions must still be imported)'],
}
# Issue numbers named in prose rather than as `#n` (read by hand): number -> blockers to add.
EXTRA_REFS = {160: [237], 286: [285], 310: [272], 571: [567], 632: [631], 708: [255], 765: [760], 338: [255, 326], 775: [774]}
# Numbers an issue names that are not its blockers (read by hand): number -> refs to leave out, with the reason in NOTES.
EXCLUDE = {94: {285, 286, 449, 531}}
# Cannot tell from the tracker: the exact question for the operator.
ASK = {
    272: ('#272 (capture of a non-empty MPStorage document) needs a **write** to an MPStorage document shared with the '
          'user\'s other clients (its own note: "only with the operator\'s go"). Do you give that go, and on which account '
          '(→ `ready`), or do you hold it (→ `on-hold`, with your decision sentence)? #310 waits on it.'),
    379: ('#379 (the M5 roadmap) waits on "the contributors\' agreement on M5 (ezzz, moust4ki aka Bybifok, the operator)". '
          'The UXD decisions are recorded (2026-11-02). Is that agreement recorded? If yes, #379 is held by the M5_OPEN '
          'decision like its lots (→ `on-hold`); if not, it stays `blocked` on that agreement (a free-text line).'),
    731: ('#731 (LOT-190, icon art) has an active `/claim mac/i731` (2026-11-11, art phase "parallel to #730") while its '
          'dependency LOT-189 (#730) is open. Does the art start now (→ `status: claimed`, the dependency is soft) or does '
          'it wait for #730 (→ `blocked` by #730, and the claim is released)?'),
}
NOTES = {
    94: 'Its section asks the operator whether LOT-168 (#286, with its capture #285) and LOT-184 (#449) gate the engine '
        'parity; they are left out here (#286 is a completeness gap legacy also has, #449 is M5): say so if either gates it.',
    254: 'Its body\'s old `Depends on` list still names LOT-110 (#201), which left LOT-164 for M5 (LOTS.md); the plan is used.',
    105: 'LOT-028 (#56) and the AQ capture #133 are closed: the check can run.',
    108: 'LOT-083 (#101) is closed, and the verification comment of 2026-10-28 says the bug is already fixed in SwiftHFR: '
         'the next step is that check and the closure.',
    447: 'LOT-172 (#311) and LOT-160 (#250) are closed, but the iCloud entitlement LOT-160 was to carry is not in `App/` '
         '(ADR 0013 §9): the portal action is the real blocker.',
    272: 'Its prerequisite #132 is closed; what holds it is the go for a write.',
}
REF = re.compile(r'(?<![\w/])#(\d+)\b')
LOT = re.compile(r'\bLOT-(\d{3})\b')


# The lines earlier steward runs generated: their refs and lots say everything they hold.
GENERATED = re.compile(r'^(?:dependencies not done(?: \(\d+\))?:|none\b.*$)', re.I)


def says_more(line):
    """True when a blocker line holds text beyond refs, lots, id notes and a generated prefix: a blocker of its own."""
    rest = re.sub(r'\([^()]*\)', lambda m: '' if REF.search(m.group(0)) or LOT.search(m.group(0)) else m.group(0),
                  GENERATED.sub('', line))  # a note that names the ref, such as `(#81, blocked)`, says nothing more
    return bool(FILLER.sub('', REF.sub('', LOT.sub('', rest))))


def section(body, name):
    m = re.search(r'(?ims)^#{2,4}[ \t]*' + name + r'[ \t]*\n(.*?)(?=^#{1,6}[ \t]|\Z)', re.sub(r'\r\n?', '\n', body or ''))
    return m.group(1) if m else ''


def milestone(lot, ms):
    if lot is None:
        return None
    for k, v in ms.items():
        if lot in v:
            return k
    import generate  # noqa: E402  (a lot added after milestones.json was written)
    for k in ('M1', 'M2', 'M3', 'M4', 'M5'):
        if lot in getattr(generate, k):
            return k
    return None


def classify(issues, pulls, lots, comments, ms):
    real = {i['number']: i for i in issues if 'pull_request' not in i}
    prs = {i['number']: i for i in issues if 'pull_request' in i}
    by_lot = {r['lot']: r for r in lots}
    lot_of = {r['issue']: r for r in lots}
    st = build(issues, pulls, lots)
    capture = {int(k): [int(x[1:]) for x in v.split(', ')] for k, v in st['capture'].items()}

    def state(n):
        if n in real:
            i = real[n]
            if i['state'].lower() == 'open':
                return 'open'
            return 'closed' if i.get('state_reason') in (None, 'completed') else f"closed {i['state_reason']}"
        if n in prs:
            if (prs[n].get('pull_request') or {}).get('merged_at'):
                return 'merged'
            return 'open' if prs[n]['state'].lower() == 'open' else 'closed unmerged'
        return 'unknown'

    def title(n):
        i = real.get(n) or prs.get(n) or {}
        r = lot_of.get(n)
        t = re.sub(r'^\[SwiftHFR\]\s*', '', i.get('title') or '')
        return (t if not r or t.startswith(r['lot']) else f"{r['lot']}: {t}")[:70]

    rows = []
    for n, i in sorted(real.items()):
        if i['state'].lower() != 'open' or BLOCKED not in labels(i):
            continue
        body = i.get('body') or ''
        r = lot_of.get(n)
        lot = r['lot'] if r else None
        mile = milestone(lot, ms) or ((i.get('milestone') or {}).get('title'))
        m5_item = (r is not None and m5.is_m5(r)) or (r is None and re.search(r'\bM5\b', i['title']) is not None)
        if m5_item:
            mile = 'M5'
        found, sources = [], {}

        def add(x, src):
            if x != n and x not in found and x not in EXCLUDE.get(n, ()):
                found.append(x)
                sources[x] = src
        for name in ('Blocked by',) if r is not None else ('Blocked by', 'Depends on'):  # a lot's plan is lots.json
            text = LOT.sub(lambda m: f"#{by_lot['LOT-' + m.group(1)]['issue']}" if 'LOT-' + m.group(1) in by_lot else m.group(0),
                           section(body, name))
            for x in REF.findall(text):
                add(int(x), name)
        for x in re.findall(r'(?im)^\s*blocked (?:by|on)[: ]+#?(\d+)', body):
            add(int(x), 'sentence')
        if r is not None:
            for d in numeric_deps(r['deps']) or []:
                if d in by_lot:
                    add(by_lot[d]['issue'], 'lot deps')
        for x in capture.get(n, []):
            add(x, 'capture')
        for x in EXTRA_REFS.get(n, []):
            add(x, 'read by hand')
        blockers = [{'ref': x, 'state': state(x), 'title': title(x), 'from': sources[x]} for x in found]
        open_b = [b for b in blockers if b['state'] in ('open', 'unknown')]
        dropped = [b for b in blockers if b['state'].startswith('closed ') and b['state'] != 'closed']
        free = list(FREE.get(n, []))
        read_by_hand = n in FREE or n in EXTRA_REFS or n in NOTES or n in EXCLUDE
        # a free-text line of the section that names no issue or lot is a blocker of its own unless it was read by hand
        unread = [] if read_by_hand else [x for x in blockers_of(body) or [] if says_more(x)]
        holder = issue_claims.replay(comments.get(n, comments.get(str(n), []))).holder
        row = {'issue': n, 'title': title(n), 'lot': lot, 'milestone': mile, 'blockers': blockers, 'free': free,
               'claim': holder, 'note': NOTES.get(n)}
        if n in ASK:
            row.update(outcome='needs-decision', question=ASK[n])
        elif m5_item and not m5.M5_OPEN:
            row.update(outcome='on-hold', decision=M5_DECISION[0], link=M5_DECISION[1])
        elif n in HOLD:
            row.update(outcome='on-hold', decision=HOLD[n][0], link=HOLD[n][1])
        elif dropped:
            row.update(outcome='needs-decision', question=f"#{n}: its blocker(s) " + ', '.join(f"#{b['ref']} ({b['state']})" for b in dropped)
                       + ' were closed without being done. Is the work still wanted (→ say what it waits on now) or is it dropped too?')
        elif open_b or free:  # bare `#n` lines: the only shape hygiene.py reads as closable
            row.update(outcome='blocked', blocked_by=[f"#{b['ref']}" for b in open_b] + free + unread)
        elif unread:
            row.update(outcome='needs-decision', question=f"#{n}: every issue it names is closed, but its `### Blocked by` "
                       'section also says: ' + '; '.join(f'"{x[:160]}"' for x in unread) + '. Is that still pending (→ `blocked`, '
                       'the line kept) or done (→ `ready`)?')
        elif blockers:
            row.update(outcome='ready')
        else:
            row.update(outcome='needs-decision', question=f'#{n} names no blocker and no decision: what does it wait on?')
        rows.append(row)
    return rows


ORDER = ('needs-decision', 'on-hold', 'blocked', 'ready')


def markdown(rows):
    count = {o: sum(1 for r in rows if r['outcome'] == o) for o in ORDER}
    out = [f"**{len(rows)} open `status: blocked` issues**, counted live. Proposed: " +
           ' · '.join(f"`{o}` {count[o]}" for o in ORDER) + '. Dry run: nothing was relabelled or edited.', '']
    asks = [r for r in rows if r['outcome'] == 'needs-decision']
    if asks:
        out += ['### Questions for the operator (cannot tell)', '']
        out += [f"{k}. {r['question']}" for k, r in enumerate(asks, 1)] + ['']
    out += ['### Table', '', '| # | Issue | M | Blockers found (state) | Proposed | To write |', '|---|---|---|---|---|---|']
    for r in sorted(rows, key=lambda r: (ORDER.index(r['outcome']), r['issue'])):
        shut = [b for b in r['blockers'] if b['state'] in ('closed', 'merged')]
        found = [f"#{b['ref']} {b['state']}" for b in r['blockers'] if b not in shut]
        found += [f"#{b['ref']} {b['state']}" for b in shut] if len(shut) <= 4 else [f"{len(shut)} more closed"]
        found = '<br>'.join(found) or '—'
        if r['outcome'] == 'blocked':
            names = {f"#{b['ref']}": f"#{b['ref']} ({b['title']})" for b in r['blockers']}
            todo = '`### Blocked by`<br>' + '<br>'.join(names.get(x, x).replace('|', '/') for x in r['blocked_by'])
        elif r['outcome'] == 'on-hold' and (r['decision'], r['link']) == M5_DECISION:
            todo = 'the M5_OPEN decision sentence (below)'
        elif r['outcome'] == 'on-hold':
            todo = f"{r['decision']} ([decision]({r['link']}))"
        elif r['outcome'] == 'ready':
            todo = 'every blocker closed, no decision on the issue'
        else:
            todo = 'see the question above'
        extra = []
        if r['claim']:
            extra.append(f"active claim `{r['claim']}`")
        if r['note']:
            extra.append(r['note'])
        if extra:
            todo += '<br>_' + ' '.join(extra) + '_'
        out.append(f"| #{r['issue']} | {r['title'].replace('|', '/')} | {r['milestone'] or '—'} | {found} | **{r['outcome']}** | {todo} |")
    if any(r.get('link') == M5_DECISION[1] for r in rows):
        out += ['', f"**M5_OPEN decision sentence**, written on each M5 item set `on-hold`: {M5_DECISION[0]} ([decision]({M5_DECISION[1]}))"]
    return '\n'.join(out) + '\n'


def plan(rows):
    """What #835 part 4 applies after the operator's go: one status per issue, the section or sentence to write."""
    out = []
    for r in rows:
        p = {'issue': r['issue'], 'from': BLOCKED, 'to': 'status: ' + r['outcome']}
        if r['outcome'] == 'blocked':
            p['blocked_by'] = r['blocked_by']
        elif r['outcome'] == 'on-hold':
            p['decision'] = {'sentence': r['decision'], 'link': r['link']}
        elif r['outcome'] == 'needs-decision':
            p['question'] = r['question']
        out.append(p)
    return out


def main(argv):
    args, opts = [], {}
    it = iter(argv)
    for a in it:
        if a in ('--json', '--md'):
            opts[a] = next(it)
        else:
            args.append(a)
    lots = json.loads((HERE / 'lots.json').read_text(encoding='utf-8'))
    ms = json.loads((HERE / 'milestones.json').read_text(encoding='utf-8'))
    if args == ['--fetch']:
        issues = gh_pages(f'repos/{REPO}/issues?state=all')
        pulls = gh_pages(f'repos/{REPO}/pulls?state=all&base=dev-swift')
        blocked = [i['number'] for i in issues if 'pull_request' not in i and i['state'] == 'open' and BLOCKED in labels(i)]
        comments = {n: gh_pages(f'repos/{REPO}/issues/{n}/comments') for n in blocked}
    elif len(args) == 3:
        issues, pulls, comments = (json.loads(Path(p).read_text(encoding='utf-8')) for p in args)
    else:
        raise SystemExit(__doc__)
    rows = classify(issues, pulls, lots, comments, ms)
    md = markdown(rows)
    if '--md' in opts:
        Path(opts['--md']).write_text(md, encoding='utf-8')
    else:
        print(md)
    if '--json' in opts:
        Path(opts['--json']).write_text(json.dumps(plan(rows), indent=1, ensure_ascii=False) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main(sys.argv[1:])
