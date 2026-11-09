"""Doc ledger (#620). Python standard library only.

A feature PR never touches `docs/CHANGELOG-LEGACY.md`, `docs/migration/GAP-LEGACY-VS-SWIFT.md` or their fragment folders.
It writes its entries in a `### Ledger` section of its body (label `ledger`); after the merge a steward turns them into the docs
with one docs-only PR on a branch `docs/ledger-<date>`. No entry: no section, no label.

  python3 tooling/docs/ledger.py check-body --pr N [--labels 'a|b'] [--file BODY.md]   # CI: label and section agree, the section parses
  python3 tooling/docs/ledger.py guard --base REF --head-ref NAME                       # CI: ledger paths only on docs/ledger-*, and nothing else there
  python3 tooling/docs/ledger.py fold [--prs N [N...]] [--apply [--commit]] [--strict] [--from-json F]   # steward (dry run by default)
  python3 tooling/docs/ledger.py done N [N...] [--apply]                                # steward, after the docs PR merged: `ledger` -> `ledger: done`

Section format: one fenced block per entry, info string = kind.

  ```changelog     the 4 cells of a changelog row, one row per line. The `#` of the row is the PR number.
  ```gap-new       `Section: <title>` then the 9-cell row; its id is GAP-<issue> (or GAP-<PR> for a second row)
  ```gap-edit      `GAP-NNN`, then one line `<Column>: <new text>` per cell to replace (column names of the report: Feature,
                   Legacy behaviour, Legacy ref, SwiftHFR final, Lot/Feat, Gap, Source, H.1); the other cells stay
  ```ledger-note   free text for an edit that is not a row (listed for the steward to apply by hand, never folded)

A bad PR is reported (PR, block, reason) and skipped; the others still fold. `fold` is idempotent: an entry already in the docs
(same text) is skipped, one that clashes with different text skips its PR. `fold` exits non-zero only when nothing was folded
although PRs were pending, or with `--strict` when any PR was skipped.
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
KINDS = ('changelog', 'gap-new', 'gap-edit', 'ledger-note')
GAP_COLUMNS = ('Id', 'Feature', 'Legacy behaviour', 'Legacy ref', 'SwiftHFR final', 'Lot/Feat', 'Gap', 'Source', 'H.1')
# Spellings the first bodies used (#604); everything else is the column name of the report, case and spaces ignored.
ALIASES = {'whattheswiftappdoes': 'SwiftHFR final', 'lotpr': 'Lot/Feat'}
HEADING = re.compile(r'(?im)^###[ \t]+Ledger[ \t]*$')
FENCE = re.compile(r'^```([\w-]*)[ \t]*\n(.*?)^```[ \t]*$', re.S | re.M)
ISSUE = re.compile(r'(?im)^[ \t]*(?:closes|refs)[ \t]+#(\d+)\b')


class LedgerError(Exception):
    """An entry or a PR body breaks the format; the message says which block and why."""


def norm(name):
    """Column and block names compared without case, spaces or punctuation."""
    return re.sub(r'[^a-z0-9]', '', name.lower())


def section(body):
    """Text of the `### Ledger` section (up to the next heading of level 1-3), or None."""
    body = (body or '').replace('\r\n', '\n').replace('\r', '\n')  # the web editor stores CRLF
    m = HEADING.search(body)
    if not m:
        return None
    rest = body[m.end():]
    end = re.search(r'(?m)^#{1,3}[ \t]+\S', rest)
    return rest[:end.start()] if end else rest


def parse_body(body):
    """-> [(kind, text)] in order. Raises LedgerError on an unknown kind, an unclosed fence or a section with no block."""
    sec = section(body)
    if sec is None:
        raise LedgerError('no `### Ledger` section')
    entries = []
    for m in FENCE.finditer(sec):
        if m.group(1) not in KINDS:
            raise LedgerError(f'block {len(entries) + 1}: unknown kind "{m.group(1)}" (one of: {", ".join(KINDS)})')
        entries.append((m.group(1), m.group(2).strip('\n')))
    if '```' in FENCE.sub('', sec):
        raise LedgerError('an unclosed or malformed fenced block')
    if not entries:
        raise LedgerError('the Ledger section has no block (no entry: no section, no label)')
    return entries


def issue_number(body, pr):
    """The issue the PR closes or refs (first one), else the PR number."""
    m = ISSUE.search(body or '')
    return int(m.group(1)) if m else int(pr)


def parse_edit(lines):
    """-> (gap id, number, {column: text}) of a `gap-edit` block."""
    if len(lines) < 2 or not re.fullmatch(r'GAP-\d+', lines[0].strip()):
        raise fold.FoldError('`GAP-NNN` alone on the first line, then one `<Column>: <text>` line per cell to replace')
    cols = {}
    for l in lines[1:]:
        name, sep, text = l.partition(':')
        col = next((c for c in GAP_COLUMNS if norm(c) == norm(name)), None) or ALIASES.get(norm(name))
        if not sep or col is None or col == 'Id' or not text.strip():
            raise fold.FoldError(f'"{l[:50]}": expected `<Column>: <text>`, Column one of {", ".join(GAP_COLUMNS[1:])}')
        if col in cols:
            raise fold.FoldError(f'column {col} twice')
        cols[col] = text.strip()
    gid = lines[0].strip()
    return gid, int(gid[4:]), cols


def build(entries, pr, issue):
    """Validate the entries of one PR with fold's own parsers.

    -> (changelog rows [4-cell line], gap-new [(id, number, section, row)], gap-edit [(id, number, {column: text})], notes [text]).
    `pr` None skips the check that a new id is the issue or PR number."""
    cl, new, edit, notes = [], [], [], []
    for i, (kind, text) in enumerate(entries, 1):
        lines = [l for l in text.split('\n') if l.strip()]
        where = f'{kind} block {i}'
        try:
            if kind == 'ledger-note':
                if not lines:
                    raise fold.FoldError('empty')
                notes.append(text.strip())
            elif kind == 'changelog':
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
                if pr is not None and num not in (int(pr), issue):
                    raise fold.FoldError(f'{gid}: the id of a new row is its issue (#{issue}) or, for a second row, the PR (#{pr})')
                new.append((gid, num, sec.group(1), lines[1].strip()))
            else:
                gid, num, cols = parse_edit(lines)
                if any(e[0] == gid for e in edit):
                    raise fold.FoldError(f'{gid} is edited by two blocks of one body')
                edit.append((gid, num, cols))
        except fold.FoldError as e:
            raise LedgerError(f'{where}: {e}') from None
    return cl, new, edit, notes


def check_body(body, pr=None):
    """CI check of a PR body: -> number of blocks. LedgerError when the section does not parse."""
    entries = parse_body(body)
    build(entries, pr, issue_number(body, pr or 0))
    return len(entries)


def check_pr(body, labels, pr=None):
    """CI check: the label `ledger` and the section agree (no entry: no section, no label), and the section parses. -> message."""
    labelled = bool({LABEL, DONE} & set(labels))
    has = section(body) is not None
    if has and not labelled:
        raise LedgerError('the body has a `### Ledger` section but the PR lacks the label `ledger`')
    if labelled and not has:
        raise LedgerError('the PR is labelled `ledger` but its body has no `### Ledger` section (no entry: no section, no label)')
    return f'ledger body: {check_body(body, pr)} block(s) ok' if has else 'ledger: no entry'


def guard(changed, head_ref):
    """-> the changed paths that break the rule. A feature PR touches no ledger path; a `docs/ledger-*` branch touches nothing else.

    The READMEs of the fragment folders are documentation, not entries."""
    def ledger_path(p):
        return p in LEDGER_FILES or p.startswith(LEDGER_DIRS)
    if head_ref.startswith(BRANCH_PREFIX):
        return [p for p in changed if not ledger_path(p)]
    return [p for p in changed if ledger_path(p) and not p.endswith('/README.md')]


# ------------------------------------------------------------------ steward

class Result:
    """What one run did: report lines, PRs folded, PRs skipped [(number, reason)], notes [(number, text)],
    conflicts [(PR, row id, column, earlier PR, its text, this PR's text)]: two PRs of one batch set one cell differently."""

    def __init__(self):
        self.lines, self.folded, self.skipped, self.notes, self.conflicts = [], [], [], [], []


def order(pr):
    """Merge order of a PR dict (then number): the earliest merge wins a cell two PRs of a batch both set."""
    return (pr.get('merged_at') or '', pr['number'])


def apply_prs(prs, layout):
    """Write the entries of `prs` ([{number, body}], PR order) into the files of `layout`. -> Result.

    A bad PR is skipped whole (nothing of it is written). Fragments feed `fold.fold`; in-place edits run after it, so an
    edit may target a row a PR of the same batch added."""
    res = Result()
    gap_lines = fold.read(layout.gap).split('\n')
    rows = {r[3]: gap_lines[r[0]] for r in fold.gap_rows(gap_lines)}
    _, have, _ = fold.parse_changelog(fold.read(layout.changelog))
    sections = fold.gap_sections(gap_lines)
    staged, edited = {}, {}  # edited: row number -> its new text, applied after the fold

    def taken(path):
        """A path already used on disk or staged by an earlier PR of the batch."""
        return path in staged or path.exists()

    set_by = {}  # (row number, column) -> (PR, text) of the earliest merged PR of the batch that set it
    for pr in sorted(prs, key=order):
        n, body = pr['number'], pr.get('body') or ''
        mine, mine_rows, mine_edits, mine_set, clash, lines = {}, {}, {}, {}, [], []
        try:
            cl, new, edit, notes = build(parse_body(body), n, issue_number(body, n))
            if cl:
                wanted = sorted('| ' + ' | '.join([str(n)] + fold.cells(l)) + ' |' for l in cl)
                same = sorted(l for k, l in have if k == n)
                if same and same == wanted:
                    lines.append(f'changelog #{n} already folded')
                elif same or taken(layout.changelog_dir / f'{n}.md'):
                    raise LedgerError(f'changelog #{n} is already a row or a fragment with other text')
                else:
                    mine[layout.changelog_dir / f'{n}.md'] = '\n'.join(cl) + '\n'
                    lines.append(f'changelog #{n} ({len(cl)} row(s))')
            for gid, num, sec, row in new:
                if sec not in sections:
                    raise LedgerError(f'{gid}: no GAP section "{sec}" (sections: {"; ".join(sections)})')
                frag = layout.gap_dir / f'GAP-{num}.md'
                if num in rows or num in mine_rows:
                    if fold.cells(row) != fold.cells(rows.get(num) or mine_rows[num]):
                        raise LedgerError(f'{gid} is already a row with other text')
                    lines.append(f'{gid} already folded')
                elif taken(frag):
                    raise LedgerError(f'{gid} is already a fragment')
                else:
                    mine[frag] = f'Section: {sec}\n{row}\n'
                    mine_rows[num] = row
                    lines.append(f'{gid} new')
            for gid, num, cols in edit:
                current = mine_edits.get(num) or mine_rows.get(num) or rows.get(num)
                if current is None:
                    raise LedgerError(f'{gid} is not a row of the gap report')
                cells = fold.cells(current)
                applied = []
                for col, text in cols.items():
                    prev = set_by.get((num, col))
                    if prev and prev[1] != text:  # the earlier merge wins: never overwrite silently, the steward decides
                        clash.append((n, gid, col) + prev + (text,))
                        continue
                    if cells[GAP_COLUMNS.index(col)] != text:
                        cells[GAP_COLUMNS.index(col)] = text
                        applied.append(col)
                    mine_set.setdefault((num, col), (n, text))
                row = '| ' + ' | '.join(cells) + ' |'
                try:
                    fold.parse_gap_row(row, gid)
                except fold.FoldError as e:
                    raise LedgerError(f'{gid}: the edited row is not valid: {e}') from None
                if applied:
                    mine_edits[num] = row
                    lines.append(f'{gid} edited in place ({", ".join(applied)})')
                elif not any(c[1] == gid for c in clash):
                    lines.append(f'{gid} edit already applied')
        except LedgerError as e:
            res.skipped.append((n, str(e)))
            continue
        staged.update(mine)
        rows.update(mine_rows)
        rows.update(mine_edits)
        edited.update(mine_edits)
        set_by.update(mine_set)
        res.conflicts.extend(clash)
        res.folded.append(n)
        res.lines.extend(f'#{n}: {l}' for l in lines)
        res.notes.extend((n, t) for t in notes)
    if not staged and not edited:
        return res
    layout.changelog_dir.mkdir(parents=True, exist_ok=True)
    layout.gap_dir.mkdir(parents=True, exist_ok=True)
    for path, text in staged.items():
        path.write_text(text, encoding='utf-8')
    fold.fold(layout)
    lines = fold.read(layout.gap).split('\n')
    for r in fold.gap_rows(lines):
        if r[3] in edited:
            lines[r[0]] = edited[r[3]]
    layout.gap.write_text('\n'.join(fold.regenerate_tallies(lines)), encoding='utf-8')
    errors, _ = fold.check(layout)
    if errors:
        raise LedgerError('fold.py --check fails on the result: ' + '; '.join(errors))
    return res


def _apply(prs, layout):
    """`apply_prs` with the errors of fold.py's shared-file reads and checks reported as LedgerError."""
    try:
        return apply_prs(prs, layout)
    except fold.FoldError as e:
        raise LedgerError(str(e)) from None


def plan(prs, layout=None, write=False):
    """Dry run in a temporary copy unless `write`. -> Result."""
    layout = layout or fold.Layout()
    if write:
        plan(prs, layout)  # dry run in a copy first: a failure leaves the tree untouched
        return _apply(prs, layout)
    tmp = Path(tempfile.mkdtemp())
    try:
        for p in (layout.changelog, layout.gap):
            (tmp / layout.rel(p)).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(p, tmp / layout.rel(p))
        for d in (layout.changelog_dir, layout.gap_dir):
            (tmp / layout.rel(d)).mkdir(parents=True, exist_ok=True)
            for f in fold.fragments(d):
                shutil.copy(f, tmp / layout.rel(d) / f.name)
        return _apply(prs, fold.Layout(tmp))
    finally:
        shutil.rmtree(tmp)


def gh(*args):
    """Run `gh api` (REST) and return its output; a failure is a LedgerError."""
    r = subprocess.run(['gh', 'api', *args], capture_output=True, text=True)
    if r.returncode:
        raise LedgerError(f'gh api {" ".join(args)[:80]}: {r.stderr.strip()[:200]}')
    return r.stdout


def merged(issue):
    """True when a REST issue object is a merged PR."""
    return bool((issue.get('pull_request') or {}).get('merged_at'))


def labels_of(issue):
    """Label names of a REST issue object."""
    return {l['name'] for l in issue.get('labels', [])}


def pending(issues, numbers=None):
    """Merged PRs from REST issue objects. -> [{number, body}]. Without `numbers`: those labelled `ledger` and not `ledger: done`;
    with them: exactly those, whatever their label, and a number that is absent or not merged is an error."""
    if numbers:
        by = {i['number']: i for i in issues}
        for n in numbers:
            if n not in by or not merged(by[n]):
                raise LedgerError(f'#{n} is not a merged PR')
        chosen = [by[n] for n in numbers]
    else:
        chosen = [i for i in issues if merged(i) and LABEL in labels_of(i) and DONE not in labels_of(i)]
    return sorted(({'number': i['number'], 'body': i.get('body') or '', 'merged_at': (i.get('pull_request') or {}).get('merged_at')}
                   for i in chosen), key=order)


def fetch_pending(numbers=None):
    """REST only (GraphQL is blocked in cloud sessions)."""
    if numbers:
        return pending([json.loads(gh(f'repos/{REPO}/issues/{n}')) for n in numbers], numbers)
    out, page = [], 1
    while True:
        batch = json.loads(gh('-X', 'GET', f'repos/{REPO}/issues', '-f', f'labels={LABEL}', '-f', 'state=closed',
                              '-f', 'per_page=100', '-f', f'page={page}'))
        out += batch
        if len(batch) < 100:
            return pending(out)
        page += 1


def git(*args, **kw):
    """Run git and return its output; a failure is a LedgerError carrying git's own message."""
    r = subprocess.run(['git', *args], capture_output=True, text=True, **kw)
    if r.returncode:
        raise LedgerError(f'git {" ".join(args)[:60]}: {(r.stderr or r.stdout).strip()[:300]}')
    return r.stdout


def branch_exists(name):
    """True when `name` exists locally or on origin."""
    return any(subprocess.run(['git', 'rev-parse', '--verify', '--quiet', ref], capture_output=True).returncode == 0
               for ref in (f'refs/heads/{name}', f'refs/remotes/origin/{name}'))


def precheck_commit(today):
    """`--commit` starts from a clean tree at origin/dev-swift, so the commit holds the ledger paths and nothing else.

    -> the branch to create: `docs/ledger-<date>`, or with a `-2`, `-3`... suffix when that name is taken (checked before any file is written)."""
    if git('status', '--porcelain').strip():
        raise LedgerError('--commit: the working tree is not clean')
    if git('rev-parse', 'HEAD').strip() != git('rev-parse', 'origin/dev-swift').strip():
        raise LedgerError('--commit: HEAD is not origin/dev-swift (git fetch origin dev-swift && git switch --detach origin/dev-swift)')
    branch, k = BRANCH_PREFIX + today, 1
    while branch_exists(branch):
        k += 1
        branch = f'{BRANCH_PREFIX}{today}-{k}'
    return branch


def run_commit(nums, branch, today):
    """Create `branch`, stage the ledger paths only, commit with the reproduction command. -> the branch."""
    git('switch', '-c', branch)
    git('add', '-A', '--', *LEDGER_FILES, *LEDGER_DIRS)
    cmd = f'python3 tooling/docs/ledger.py fold --apply --prs {" ".join(map(str, nums))}'
    git('commit', '-m', f'Ledger {today}: fold the entries of ' + ', '.join(f'#{n}' for n in nums) +
        f'\n\nReproduce on the base: {cmd} && git diff --exit-code <head>')
    return branch


def report(res):
    """Print what a run did: lines, notes for the steward, skipped PRs."""
    for l in res.lines:
        print(' ', l)
    for n, t in res.notes:
        print(f'  BY HAND #{n} (ledger-note): {t[:300]}')
    for n, row, col, earlier, was, now in res.conflicts:
        print(f'  BY HAND CONFLICT #{n} {row} {col}: #{earlier} set "{was[:200]}", #{n} wants "{now[:200]}"; the earlier one is kept')
    for n, why in res.skipped:
        print(f'::error::PR #{n} skipped: {why}' if 'GITHUB_ACTIONS' in os.environ else f'  SKIPPED PR #{n}: {why}')


def relabel(n, apply):
    """`ledger` -> `ledger: done` on one PR; idempotent. -> message."""
    issue = json.loads(gh(f'repos/{REPO}/issues/{n}'))
    names = labels_of(issue)
    if DONE in names and LABEL not in names:
        return f'#{n}: already done'
    if not merged(issue):
        raise LedgerError(f'#{n} is not a merged PR')
    if not apply:
        return f'#{n}: would relabel {LABEL} -> {DONE}'
    if DONE not in names:
        gh('-X', 'POST', f'repos/{REPO}/issues/{n}/labels', '-f', f'labels[]={DONE}')
    if LABEL in names:
        try:
            gh('-X', 'DELETE', f'repos/{REPO}/issues/{n}/labels/{LABEL}')
        except LedgerError as e:
            if '404' not in str(e):  # already removed by someone else
                raise
    return f'#{n}: relabelled {LABEL} -> {DONE}'


def main(argv=None, layout=None):
    """CLI entry; returns the exit code."""
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('check-body')
    c.add_argument('--file')
    c.add_argument('--pr', type=int)
    c.add_argument('--labels', help='labels of the PR, `|`-separated: the label and the section must agree')
    g = sub.add_parser('guard')
    g.add_argument('--base', required=True)
    g.add_argument('--head-ref', required=True)
    f = sub.add_parser('fold')
    f.add_argument('--prs', nargs='+', help='exactly these merged PRs (numbers, space or comma separated), whatever their label')
    f.add_argument('--apply', action='store_true')
    f.add_argument('--commit', action='store_true', help='with --apply: clean tree at origin/dev-swift, branch docs/ledger-<date>, one commit')
    f.add_argument('--strict', action='store_true', help='exit non-zero when any PR is skipped')
    f.add_argument('--from-json', help='REST issue objects instead of `gh api` (tests, offline)')
    d = sub.add_parser('done')
    d.add_argument('numbers', nargs='+', type=int)
    d.add_argument('--apply', action='store_true')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'check-body':
            body = Path(a.file).read_text(encoding='utf-8') if a.file else sys.stdin.read()
            print(check_pr(body, a.labels.split('|'), a.pr) if a.labels is not None else f'ledger body: {check_body(body, a.pr)} block(s) ok')
        elif a.cmd == 'guard':
            names = git('diff', '--no-renames', '--name-only', f'{a.base}...HEAD').split('\n')
            bad = guard([n for n in names if n], a.head_ref)
            for p in bad:
                print(f'::error::{p}: ' + ('a ledger PR (docs/ledger-*) touches only the ledger paths' if a.head_ref.startswith(BRANCH_PREFIX)
                                           else 'a PR never edits the ledger files; write the entry in a `### Ledger` section of the PR body (AGENTS.md §8)'))
            print('ledger guard: ' + ('FAILED' if bad else 'ok'))
            return 1 if bad else 0
        elif a.cmd == 'fold':
            if a.commit and not a.apply:
                raise LedgerError('--commit needs --apply')
            if a.commit:
                today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
                branch = precheck_commit(today)
            numbers = [int(x) for t in a.prs or [] for x in t.split(',') if x]
            if a.from_json:
                prs = pending(json.loads(Path(a.from_json).read_text(encoding='utf-8')), numbers)
            else:
                prs = fetch_pending(numbers)
            if not prs:
                print('ledger: nothing pending')
                return 0
            res = plan(prs, layout, write=a.apply)
            report(res)
            nums = ' '.join(map(str, res.folded))
            if a.apply and a.commit and res.folded:
                print('branch', run_commit(res.folded, branch, today))
            print(f'ledger: {"applied" if a.apply else "dry run"}: folded {len(res.folded)}, skipped {len(res.skipped)}'
                  + (f'; after the docs PR merged: ledger.py done {nums} --apply' if res.folded else ''))
            return 1 if (not res.folded or (a.strict and res.skipped)) else 0
        else:
            failed = 0
            for n in a.numbers:
                try:
                    print(relabel(n, a.apply))
                except LedgerError as e:  # the other PRs still get their label
                    failed += 1
                    print(f'ERROR {e}')
            return 1 if failed else 0
    except LedgerError as e:
        print(f'::error::{e}' if 'GITHUB_ACTIONS' in os.environ else f'ERROR {e}')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
