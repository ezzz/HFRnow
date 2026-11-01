"""Build state.json (the tracker state the board generator reads) from GitHub data.

  python3 sync_state.py --fetch                      # via `gh api` (pages by hand: the proxy refuses Link URLs)
  python3 sync_state.py issues.json pulls.json       # offline: JSON saved from list_issues / list_pull_requests / gh api

Rules (all derived, nothing hand-written):
  closed   = closed issues             ready    = open + `status: ready`
  claimed  = open + `status: claimed`  external = open + `external: ready`
  open PRs naming LOT-XXX (title or body) -> ongoing (draft or review, reviewer from the lot's routing)
  merged PRs on dev-swift naming LOT-XXX (title) -> merged_pr
  capture  = lot issues waiting on an open capture: their `### Captures needed` section, or an open `host: mac`
             issue whose `### Wanted by` names them
"""
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = 'ezzz/HFRnow'
LOT_RE = re.compile(r'\bLOT-(\d{3})\b')


def labels(i):
    return {(x['name'] if isinstance(x, dict) else x) for x in i.get('labels') or []}


def gh_pages(path):
    out, page = [], 1
    while True:
        sep = '&' if '?' in path else '?'
        r = subprocess.run(['gh', 'api', '-X', 'GET', f'{path}{sep}per_page=100&page={page}'], capture_output=True, text=True)
        if r.returncode:
            raise SystemExit(f'gh api failed: {r.stderr.strip()[:200]}')
        chunk = json.loads(r.stdout)
        out += chunk
        if len(chunk) < 100:
            return out
        page += 1


def load(p):
    d = json.loads(Path(p).read_text(encoding='utf-8'))
    return d.get('issues') or d.get('pull_requests') or d.get('items') or [] if isinstance(d, dict) else d


def build(issues, pulls, lots):
    issues = [i for i in issues if 'pull_request' not in i]  # the issues API also lists PRs
    by_lot = {r['lot']: r for r in lots}
    lot_issues = {r['issue'] for r in lots}
    closed, ready, claimed, external = set(), set(), set(), set()
    for i in issues:
        n, lb = i['number'], labels(i)
        if i['state'].lower() == 'closed':
            if i.get('state_reason') in (None, 'completed'):  # not planned / duplicate is not done
                closed.add(n)
            continue
        if 'status: ready' in lb:
            ready.add(n)
        if 'status: claimed' in lb:
            claimed.add(n)
        if 'external: ready' in lb:
            external.add(n)
    capture = {}
    for i in issues:
        if i['state'].lower() != 'open' or i['number'] not in lot_issues:
            continue
        sec = re.search(r'### Captures needed\s*\n(.*?)(?=\n###|\Z)', i.get('body') or '', re.S)
        for m in re.findall(r'#(\d+)', sec.group(1) if sec else ''):
            if int(m) not in closed and int(m) != i['number']:
                capture.setdefault(i['number'], set()).add(f'#{m}')
    for i in issues:  # the other direction: an open capture issue's `### Wanted by` names the lots it blocks
        if i['state'].lower() != 'open' or 'host: mac' not in labels(i) or i['number'] in lot_issues:
            continue
        sec = re.search(r'### Wanted by\s*\n(.*?)(?=\n###|\Z)', i.get('body') or '', re.S)
        text = sec.group(1) if sec else ''
        wanted = {int(m) for m in re.findall(r'#(\d+)', text)} | {by_lot[f'LOT-{m}']['issue'] for m in LOT_RE.findall(text) if f'LOT-{m}' in by_lot}
        for m in wanted & lot_issues:
            if m not in closed:
                capture.setdefault(m, set()).add(f"#{i['number']}")
    prs, merged = {}, {}
    for p in pulls:
        if (p.get('base') or {}).get('ref', 'dev-swift') != 'dev-swift':
            continue
        text = f"{p.get('title') or ''}\n{p.get('body') or ''}"
        if p.get('merged') or p.get('merged_at'):
            for m in LOT_RE.finditer(p.get('title') or ''):
                merged.setdefault(f'LOT-{m.group(1)}', p['number'])
        elif p['state'].lower() == 'open':
            for m in set(LOT_RE.findall(text)):
                lot = f'LOT-{m}'
                if lot not in by_lot:
                    continue
                rev = by_lot[lot]['model'].split('→')[-1].strip()
                prs[lot] = [p['number'], 'draft' if p.get('draft') else 'review', rev]
    return {
        # a lot waiting on an open capture is not ready on the board, whatever its label says
        'closed': sorted(closed), 'ready': sorted(ready - set(capture)), 'claimed': sorted(claimed), 'external': sorted(external),
        'generated_at': datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC'),
        'prs': prs, 'merged_pr': merged,
        'capture': {str(k): ', '.join(sorted(v, key=lambda x: int(x[1:]))) for k, v in sorted(capture.items())},
    }


if __name__ == '__main__':
    lots = json.loads((HERE / 'lots.json').read_text(encoding='utf-8'))
    if sys.argv[1:] == ['--fetch']:
        issues, pulls = gh_pages(f'repos/{REPO}/issues?state=all'), gh_pages(f'repos/{REPO}/pulls?state=all&base=dev-swift')
    elif len(sys.argv) == 3:
        issues, pulls = load(sys.argv[1]), load(sys.argv[2])
    else:
        raise SystemExit(__doc__)
    st = build(issues, pulls, lots)
    (HERE / 'state.json').write_text(json.dumps(st, indent=1, sort_keys=True) + '\n')
    print({k: len(v) for k, v in st.items()})
