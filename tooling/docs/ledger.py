"""Doc ledger (#620). Python standard library only.

A feature PR never touches `docs/CHANGELOG-LEGACY.md`, `docs/migration/GAP-LEGACY-VS-SWIFT.md` or their fragment folders.
It writes its entries in a `### Ledger` section of its body (label `ledger`); after the merge a steward turns them into the docs
with one docs-only PR on a branch `docs/ledger-<date>`.

  python3 tooling/docs/ledger.py check-body [--file BODY.md]        # CI: the section parses (body on stdin otherwise)
  python3 tooling/docs/ledger.py guard --base REF --head-ref NAME   # CI: no ledger file changed unless the branch is docs/ledger-*
  python3 tooling/docs/ledger.py fold [--apply] [--commit] [--from-json F]   # steward: merged `ledger` PRs -> docs (dry run by default)
  python3 tooling/docs/ledger.py done N [N...] [--apply]            # steward, after the docs PR merged: label `ledger` -> `ledger: done`

Section format: one fenced block per entry, info string = kind.

  ```changelog                  the 4 cells of a changelog row, one row per line; # = the PR's issue (`Closes`/`Refs #N`, else the PR number)
  | T | Résumé. | LOT-XXX #N | `File.swift:1-2` @ `2440d79` |
  ```
  ```gap-new                    `Section: <title>` then the 9-cell row; its id is GAP-<issue>
  ```
  ```gap-edit                   `GAP-NNN` then the whole new row of that id (replaces the row in place)
  ```

`fold` is idempotent: an entry already in the docs (same text) is skipped, one that clashes with different text is an error.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fold  # noqa: E402  (tooling/docs/fold.py)

REPO = 'ezzz/HFRnow'
BRANCH_PREFIX = 'docs/ledger-'
LEDGER_FILES = ('docs/CHANGELOG-LEGACY.md', 'docs/migration/GAP-LEGACY-VS-SWIFT.md')
LEDGER_DIRS = ('docs/changelog-legacy.d/', 'docs/migration/gap.d/')
LABEL, DONE = 'ledger', 'ledger: done'
KINDS = ('changelog', 'gap-new', 'gap-edit')
HEADING = re.compile(r'(?im)^###[ \t]+Ledger[ \t]*$')
FENCE = re.compile(r'^```([\w-]*)[ \t]*\n(.*?)^```[ \t]*$', re.S | re.M)
ISSUE = re.compile(r'(?im)^[ \t]*(?:closes|refs)[ \t]+#(\d+)\b')


class LedgerError(Exception):
    """An entry or a PR body breaks the format; the message says which."""


def section(body):
    """Text of the `### Ledger` section (up to the next heading of level 1-3), or None."""
    m = HEADING.search(body or '')
    if not m:
        return None
    rest = body[m.end():]
    end = re.search(r'(?m)^#{1,3}[ \t]+\S', rest)
    return rest[:end.start()] if end else rest


def parse_body(body):
    """-> [(kind, text)] in order. Raises LedgerError on an unknown kind, an unclosed fence, prose or an empty section."""
    sec = section(body)
    if sec is None:
        raise LedgerError('no `### Ledger` section')
    entries = []
    for m in FENCE.finditer(sec):
        if m.group(1) not in KINDS:
            raise LedgerError(f'unknown block kind "{m.group(1)}" (one of: {", ".join(KINDS)})')
        entries.append((m.group(1), m.group(2).strip('\n')))
    leftover = [l for l in FENCE.sub('', sec).split('\n') if l.strip() and not l.strip().startswith('<!--')]
    if '```' in ''.join(leftover):
        raise LedgerError('an unclosed or malformed fenced block')
    if not entries:
        raise LedgerError('the Ledger section has no block')
    return entries


def issue_number(body, pr):
    """The issue the PR closes or refs (first one), else the PR number: the `#` of its changelog rows."""
    m = ISSUE.search(body or '')
    return int(m.group(1)) if m else int(pr)


def build(entries, issue, where):
    """Validate the entries of one PR with fold's own parsers.

    -> (changelog rows [4-cell line], gap-new [(id, number, section, row)], gap-edit [(id, number, row)])."""
    cl, new, edit = [], [], []
    for kind, text in entries:
        lines = [l for l in text.split('\n') if l.strip()]
        try:
            if kind == 'changelog':
                if not lines or not all(fold.is_row(l) for l in lines):
                    raise fold.FoldError('one or more rows `| T | résumé | lot / PR | preuve |` and nothing else')
                for l in lines:
                    c = fold.cells(l)
                    if len(c) != 4 or c[0] not in fold.SECTIONS or not all(c[1:]):
                        raise fold.FoldError('4 non-empty cells per row (section T or UX, résumé, lot / PR, preuve)')
                    cl.append('| ' + ' | '.join(c) + ' |')
            elif kind == 'gap-new':
                sec = re.fullmatch(r'Section: (.+?)\s*', lines[0]) if lines else None
                if len(lines) != 2 or not sec or not fold.is_row(lines[1]):
                    raise fold.FoldError('two lines, `Section: <title>` then one GAP row')
                gid, num, _, _ = fold.parse_gap_row(lines[1], where)
                new.append((gid, num, sec.group(1), lines[1].strip()))
            else:
                if len(lines) != 2 or not re.fullmatch(r'GAP-\d+', lines[0].strip()) or not fold.is_row(lines[1]):
                    raise fold.FoldError('two lines, `GAP-NNN` then the whole new row')
                gid, num, _, _ = fold.parse_gap_row(lines[1], where)
                if gid != lines[0].strip():
                    raise fold.FoldError(f'the row is {gid}, the first line says {lines[0].strip()}')
                edit.append((gid, num, lines[1].strip()))
        except fold.FoldError as e:
            raise LedgerError(f'{where}: {kind}: {e}') from None
    return cl, new, edit


def check_body(body):
    """CI check of a PR body: -> number of entries. LedgerError when the section does not parse."""
    entries = parse_body(body)
    build(entries, 0, 'PR body')
    return len(entries)


def guard(changed, head_ref):
    """-> the changed paths a PR may not touch (empty for the steward's `docs/ledger-*` branch).

    The READMEs of the fragment folders are documentation, not ledger entries."""
    if head_ref.startswith(BRANCH_PREFIX):
        return []
    return [p for p in changed if p in LEDGER_FILES or (p.startswith(LEDGER_DIRS) and not p.endswith('/README.md'))]


# ------------------------------------------------------------------ steward

def apply_prs(prs, layout):
    """Write the entries of `prs` ([{number, body}], PR order) into the files of `layout`. -> report lines.

    Fragments feed `fold.fold`; in-place edits run after it, so an edit may target a row a PR of the same batch added."""
    gap_lines = fold.read(layout.gap).split('\n')
    rows = {r[3]: r for r in fold.gap_rows(gap_lines)}
    cl_text = fold.read(layout.changelog)
    out, edits = [], []
    layout.changelog_dir.mkdir(parents=True, exist_ok=True)
    layout.gap_dir.mkdir(parents=True, exist_ok=True)
    for pr in sorted(prs, key=lambda p: p['number']):
        n, body = pr['number'], pr.get('body') or ''
        issue = issue_number(body, n)
        try:
            cl, new, edit = build(parse_body(body), issue, f'#{n}')
        except LedgerError as e:
            raise LedgerError(f'PR #{n}: {e}') from None
        _, have, _ = fold.parse_changelog(cl_text)
        if cl:
            wanted = sorted('| ' + ' | '.join([str(issue)] + fold.cells(l)) + ' |' for l in cl)
            same = sorted(l for k, l in have if k == issue)
            frag = layout.changelog_dir / f'{issue}.md'
            if same and same == wanted:
                out.append(f'#{n}: changelog #{issue} already folded')
            elif same or frag.exists():
                raise LedgerError(f'PR #{n}: changelog #{issue} is already a row or a fragment with other text')
            else:
                frag.write_text('\n'.join(cl) + '\n', encoding='utf-8')
                out.append(f'#{n}: changelog #{issue} ({len(cl)} row(s))')
        for gid, num, sec, row in new:
            frag = layout.gap_dir / f'GAP-{num}.md'
            if num in rows:
                if fold.cells(row) != fold.cells(gap_lines[rows[num][0]]):
                    raise LedgerError(f'PR #{n}: {gid} is already a row with other text')
                out.append(f'#{n}: {gid} already folded')
            elif frag.exists():
                raise LedgerError(f'PR #{n}: {gid} is already a fragment')
            else:
                frag.write_text(f'Section: {sec}\n{row}\n', encoding='utf-8')
                out.append(f'#{n}: {gid} new')
        edits.extend((n,) + e for e in edit)
    fold.fold(layout)
    lines = fold.read(layout.gap).split('\n')
    for n, gid, num, row in edits:
        idx = [r[0] for r in fold.gap_rows(lines) if r[3] == num]
        if not idx:
            raise LedgerError(f'PR #{n}: {gid} is not a row of the gap report')
        lines[idx[0]] = row
        out.append(f'#{n}: {gid} edited in place')
    layout.gap.write_text('\n'.join(fold.regenerate_tallies(lines)), encoding='utf-8')
    errors, _ = fold.check(layout)
    if errors:
        raise LedgerError('fold.py --check fails on the result: ' + '; '.join(errors))
    return out


def plan(prs, layout=None, write=False):
    """Dry run in a temporary copy unless `write`. -> report lines."""
    layout = layout or fold.Layout()
    if write:
        return apply_prs(prs, layout)
    tmp = Path(tempfile.mkdtemp())
    try:
        for p in (layout.changelog, layout.gap):
            (tmp / layout.rel(p)).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(p, tmp / layout.rel(p))
        for d in (layout.changelog_dir, layout.gap_dir):
            (tmp / layout.rel(d)).mkdir(parents=True, exist_ok=True)
            for f in fold.fragments(d):
                shutil.copy(f, tmp / layout.rel(d) / f.name)
        return apply_prs(prs, fold.Layout(tmp))
    finally:
        shutil.rmtree(tmp)


def gh(*args):
    r = subprocess.run(['gh', 'api', *args], capture_output=True, text=True)
    if r.returncode:
        raise LedgerError(f'gh api {" ".join(args)[:80]}: {r.stderr.strip()[:200]}')
    return r.stdout


def pending(issues):
    """Merged PRs labelled `ledger`, not `ledger: done`, from REST issue objects. -> [{number, body}]."""
    out = []
    for i in issues:
        names = {l['name'] for l in i.get('labels', [])}
        if (i.get('pull_request') or {}).get('merged_at') and LABEL in names and DONE not in names:
            out.append({'number': i['number'], 'body': i.get('body') or ''})
    return sorted(out, key=lambda p: p['number'])


def fetch_pending():
    """REST only (GraphQL is blocked in cloud sessions): closed issues+PRs carrying the label, paginated."""
    out, page = [], 1
    while True:
        batch = json.loads(gh('-X', 'GET', f'repos/{REPO}/issues', '-f', f'labels={LABEL}', '-f', 'state=closed',
                              '-f', 'per_page=100', '-f', f'page={page}'))
        out += batch
        if len(batch) < 100:
            return pending(out)
        page += 1


def run_commit(prs, today):
    branch = BRANCH_PREFIX + today
    subprocess.run(['git', 'switch', '-c', branch], check=True)
    subprocess.run(['git', 'add', 'docs'], check=True)
    msg = f'Ledger {today}: fold the entries of ' + ', '.join(f'#{p["number"]}' for p in prs)
    subprocess.run(['git', 'commit', '-m', msg], check=True)
    return branch


def main(argv=None, layout=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('check-body')
    c.add_argument('--file')
    g = sub.add_parser('guard')
    g.add_argument('--base', required=True)
    g.add_argument('--head-ref', required=True)
    f = sub.add_parser('fold')
    f.add_argument('--apply', action='store_true')
    f.add_argument('--commit', action='store_true')
    f.add_argument('--from-json', help='REST issue objects instead of `gh api` (tests, offline)')
    d = sub.add_parser('done')
    d.add_argument('numbers', nargs='+', type=int)
    d.add_argument('--apply', action='store_true')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'check-body':
            body = Path(a.file).read_text(encoding='utf-8') if a.file else sys.stdin.read()
            print(f'ledger body: {check_body(body)} entr(ies) ok')
        elif a.cmd == 'guard':
            names = subprocess.run(['git', 'diff', '--name-only', f'{a.base}...HEAD'], capture_output=True, text=True, check=True).stdout.split('\n')
            bad = guard([n for n in names if n], a.head_ref)
            for p in bad:
                print(f'::error::{p}: a PR never edits the ledger files; write the entry in a `### Ledger` section of the PR body (AGENTS.md §8)')
            print('ledger guard: ' + ('FAILED' if bad else 'ok'))
            return 1 if bad else 0
        elif a.cmd == 'fold':
            prs = pending(json.loads(Path(a.from_json).read_text(encoding='utf-8'))) if a.from_json else fetch_pending()
            if not prs:
                print('ledger: nothing pending')
                return 0
            for line in plan(prs, layout, write=a.apply):
                print(' ', line)
            nums = ' '.join(str(p['number']) for p in prs)
            if a.apply and a.commit:
                print('branch', run_commit(prs, datetime.now(timezone.utc).strftime('%Y-%m-%d')))
            print(f'ledger: {"applied" if a.apply else "dry run"} for PRs {nums}; after the docs PR merged: ledger.py done {nums} --apply')
        else:
            for n in a.numbers:
                print(('relabel' if a.apply else 'would relabel'), f'#{n}: {LABEL} -> {DONE}')
                if a.apply:
                    gh('-X', 'POST', f'repos/{REPO}/issues/{n}/labels', '-f', f'labels[]={DONE}')
                    gh('-X', 'DELETE', f'repos/{REPO}/issues/{n}/labels/{LABEL}')
    except LedgerError as e:
        print(f'::error::{e}' if 'GITHUB_ACTIONS' in os.environ else f'ERROR {e}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
