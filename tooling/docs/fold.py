"""Fold the GAP and CHANGELOG-LEGACY fragments into their shared files (#612). Python standard library only.

A PR never edits `docs/CHANGELOG-LEGACY.md` or `docs/migration/GAP-LEGACY-VS-SWIFT.md`: it adds one fragment,
a file with a unique name, so two PRs cannot conflict. This script owns everything that used to conflict:
the row order, the H.1 lists and the Counts table.

  python3 tooling/docs/fold.py             # fold the fragments into the two files, regenerate the tallies, delete the fragments
  python3 tooling/docs/fold.py --dry-run   # print what folding would do, change nothing
  python3 tooling/docs/fold.py --check     # CI: fragments well formed, IDs unique, tallies of the files are the generated ones

Fragment formats are in the README of each fragment folder. Rows already in the files are never rewritten,
fragments are appended after them in ID order, so folding twice is a no-op.
"""
import argparse
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Gap values in the order of the Counts table, and the ones the H.1 list covers (a row that changes something).
GAPS = ('same', 'ported with changes', 'ported with changes (engine only)', 'UX change', 'new', 'dropped', 'not planned')
H1_GAPS = ('ported with changes', 'UX change', 'new')
H1_CLASSES = ('a', 'a·master', 'b·needed', 'b·operator', 'b')  # order of the H.1 list; '—' rows are not in it
H1_ALL = H1_CLASSES + ('—',)
GAP_COLUMNS = 9
GAP_ROW = re.compile(r'^\| (GAP-(\d+)) \|')
SECTIONS = ('T', 'UX')
CELLS = re.compile(r'(?<!\\)\|')


class FoldError(Exception):
    """A fragment or a shared file breaks its format; the message names the file and the line."""


def cells(line):
    """Cells of a Markdown table row; `\\|` inside a cell does not split it."""
    return [c.strip() for c in CELLS.split(line.strip())[1:-1]]


def is_row(line):
    s = line.strip()
    return s.startswith('|') and s.endswith('|') and len(s) > 1


class Layout:
    """The files of a repository checkout (a temporary directory in the tests)."""

    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.changelog = self.root / 'docs' / 'CHANGELOG-LEGACY.md'
        self.changelog_dir = self.root / 'docs' / 'changelog-legacy.d'
        self.gap = self.root / 'docs' / 'migration' / 'GAP-LEGACY-VS-SWIFT.md'
        self.gap_dir = self.root / 'docs' / 'migration' / 'gap.d'

    def rel(self, path):
        return path.relative_to(self.root).as_posix()


def read(path):
    return path.read_text(encoding='utf-8')


def fragments(directory):
    """Fragment files of a folder (README excluded), sorted by name."""
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.iterdir() if p.is_file() and p.name != 'README.md')


# ---------------------------------------------------------------- changelog

CL_HEAD = re.compile(r'^\| # \| Section \|')


def parse_changelog(text):
    """-> (lines before the first row, [(number, line)], lines after the table). Rows keep their text."""
    lines = text.split('\n')
    head = next((i for i, l in enumerate(lines) if CL_HEAD.match(l)), None)
    if head is None:
        raise FoldError('CHANGELOG-LEGACY.md: no table with the header "| # | Section |"')
    start = head + 2  # header and delimiter row
    end = start
    rows = []
    while end < len(lines) and is_row(lines[end]):
        c = cells(lines[end])
        if len(c) != 5 or not c[0].isdigit() or c[1] not in SECTIONS:
            raise FoldError(f'CHANGELOG-LEGACY.md:{end + 1}: a row has 5 cells, a numeric # and a section T or UX')
        rows.append((int(c[0]), lines[end]))
        end += 1
    return lines[:start], rows, lines[end:]


def read_changelog_fragment(path):
    """-> (number, row line). The file is `<issue>.md` with one line `| T | résumé | lot / PR | preuve |`."""
    m = re.fullmatch(r'(\d+)\.md', path.name)
    if not m:
        raise FoldError(f'{path.name}: a changelog fragment is named <issue>.md')
    body = [l for l in read(path).split('\n') if l.strip()]
    if len(body) != 1 or not is_row(body[0]):
        raise FoldError(f'{path.name}: one table row `| T | résumé | lot / PR | preuve |` and nothing else')
    c = cells(body[0])
    if len(c) != 4 or c[0] not in SECTIONS or not all(c[1:]):
        raise FoldError(f'{path.name}: 4 non-empty cells (section T or UX, résumé, lot / PR, preuve)')
    n = int(m.group(1))
    return n, '| ' + ' | '.join([str(n)] + c) + ' |'


def render_changelog(before, rows, after):
    return '\n'.join(before + [l for _, l in rows] + after)


def fold_changelog(layout):
    """-> (new text, folded fragment paths)."""
    before, rows, after = parse_changelog(read(layout.changelog))
    seen = {n for n, _ in rows}
    new = []
    for p in fragments(layout.changelog_dir):
        n, line = read_changelog_fragment(p)
        if n in seen:
            raise FoldError(f'{layout.rel(p)}: #{n} is already a row of CHANGELOG-LEGACY.md or another fragment')
        seen.add(n)
        new.append((n, line))
    rows = sorted(rows + new, key=lambda r: r[0])
    return render_changelog(before, rows, after), fragments(layout.changelog_dir)


def check_changelog(layout, errors):
    try:
        _, rows, _ = parse_changelog(read(layout.changelog))
    except FoldError as e:
        errors.append(str(e))
        return
    nums = [n for n, _ in rows]
    for n in sorted({n for n in nums if nums.count(n) > 1}):
        errors.append(f'CHANGELOG-LEGACY.md: row #{n} appears more than once')
    if nums != sorted(nums):
        errors.append('CHANGELOG-LEGACY.md: rows are not in number order (run tooling/docs/fold.py)')
    seen = set()
    for p in fragments(layout.changelog_dir):
        try:
            n, _ = read_changelog_fragment(p)
        except FoldError as e:
            errors.append(str(e))
            continue
        if n in nums:
            errors.append(f'{layout.rel(p)}: #{n} is already a row of CHANGELOG-LEGACY.md (direct edit and fragment for the same issue)')
        seen.add(n)


# ---------------------------------------------------------------------- GAP

GAP_HEAD = re.compile(r'^\| Id \| Feature \|')
H1_HEADING = re.compile(r'^(### GAP rows of type `ported with changes`, `UX change` or `new` \()\d+(\))$')


def parse_gap_row(line, where):
    c = cells(line)
    m = GAP_ROW.match(line)
    if not m or len(c) != GAP_COLUMNS:
        raise FoldError(f'{where}: a GAP row has {GAP_COLUMNS} cells and starts with `| GAP-<number> |`')
    if c[6] not in GAPS:
        raise FoldError(f'{where}: Gap column "{c[6]}" is none of: {", ".join(GAPS)}')
    if c[8] not in H1_ALL:
        raise FoldError(f'{where}: H.1 column "{c[8]}" is none of: {", ".join(H1_ALL)}')
    if not all(c):
        raise FoldError(f'{where}: an empty cell (write — for none)')
    return m.group(1), int(m.group(2)), c[6], c[8]


def gap_rows(lines):
    """Every GAP row of the file as (line index, section title, id, number, gap, h1)."""
    out, section = [], None
    for i, line in enumerate(lines):
        if line.startswith('## '):
            section = line[3:].strip()
        elif GAP_ROW.match(line):
            out.append((i, section) + parse_gap_row(line, f'GAP-LEGACY-VS-SWIFT.md:{i + 1}'))
    return out


def read_gap_fragment(path):
    """-> (id, number, section, row line, gap, h1). The file is `GAP-<issue>.md`: `Section: <title>` then the row."""
    m = re.fullmatch(r'GAP-(\d+)\.md', path.name)
    if not m:
        raise FoldError(f'{path.name}: a GAP fragment is named GAP-<issue>.md')
    body = [l for l in read(path).split('\n') if l.strip()]
    sec = re.fullmatch(r'Section: (.+?)\s*', body[0]) if body else None
    if len(body) != 2 or not sec or not is_row(body[1]):
        raise FoldError(f'{path.name}: two lines, `Section: <title of a GAP section>` then one table row')
    gid, num, gap, h1 = parse_gap_row(body[1], path.name)
    if gid != f'GAP-{m.group(1)}':
        raise FoldError(f'{path.name}: the row is {gid}, the file name says GAP-{m.group(1)}')
    return gid, num, sec.group(1), body[1].strip(), gap, h1


def gap_sections(lines):
    """Titles of the H2 sections that hold a GAP table."""
    out, section = [], None
    for line in lines:
        if line.startswith('## '):
            section = line[3:].strip()
        elif GAP_HEAD.match(line) and section not in out:
            out.append(section)
    return out


def section_end(lines, section):
    """Index right after the last row of the section's first GAP table (where a new row goes)."""
    i = next(k for k, l in enumerate(lines) if l.startswith('## ') and l[3:].strip() == section)
    h = next(k for k in range(i, len(lines)) if GAP_HEAD.match(lines[k]))
    e = h + 2  # header and delimiter row
    while e < len(lines) and is_row(lines[e]):
        e += 1
    return e


def h1_lines(rows):
    by_class = {k: [] for k in H1_CLASSES}
    for _, _, _, num, gap, h1 in rows:
        if gap in H1_GAPS and h1 in by_class:
            by_class[h1].append(num)
    total = sum(len(v) for v in by_class.values())
    table = ['| H.1 | Rows | Count |', '|---|---|---|']
    for k in H1_CLASSES:
        nums = sorted(by_class[k])
        table.append(f'| {k} | {", ".join(f"{n:03d}" for n in nums)} | {len(nums)} |')
    return total, table


def counts_lines(rows):
    tally = {g: 0 for g in GAPS}
    for r in rows:
        tally[r[4]] += 1
    table = ['| Gap | Rows |', '|---|---|']
    table += [f'| {g} | {tally[g]} |' for g in GAPS if tally[g]]
    table.append(f'| **Total** | **{len(rows)}** |')
    return table


def replace_block(lines, start_pred, new_table, what):
    """Replace the first table that follows the line matching `start_pred` (a heading) with `new_table`."""
    i = next((k for k, l in enumerate(lines) if start_pred(l)), None)
    if i is None:
        raise FoldError(f'GAP-LEGACY-VS-SWIFT.md: no section for {what}')
    s = next((k for k in range(i + 1, len(lines)) if is_row(lines[k])), None)
    if s is None:
        raise FoldError(f'GAP-LEGACY-VS-SWIFT.md: no table under {what}')
    e = s
    while e < len(lines) and is_row(lines[e]):
        e += 1
    return lines[:s] + new_table + lines[e:]


def regenerate_tallies(lines):
    """The H.1 heading and list and the Counts table, recomputed from the rows of `lines`."""
    rows = gap_rows(lines)
    total, h1 = h1_lines(rows)
    lines = [H1_HEADING.sub(lambda m: f'{m.group(1)}{total}{m.group(2)}', l) for l in lines]
    lines = replace_block(lines, lambda l: l == '## Counts', counts_lines(rows), 'the Counts table')
    return replace_block(lines, lambda l: bool(H1_HEADING.match(l)), h1, 'the H.1 list')


def fold_gap(layout):
    """-> (new text, folded fragment paths)."""
    lines = read(layout.gap).split('\n')
    known = {r[2] for r in gap_rows(lines)}
    sections = gap_sections(lines)
    new = []
    for p in fragments(layout.gap_dir):
        gid, num, section, row, _, _ = read_gap_fragment(p)
        if gid in known:
            raise FoldError(f'{layout.rel(p)}: {gid} is already a row of GAP-LEGACY-VS-SWIFT.md or another fragment')
        if section not in sections:
            raise FoldError(f'{layout.rel(p)}: no GAP section "{section}" (sections: {"; ".join(sections)})')
        known.add(gid)
        new.append((num, section, row))
    for num, section, row in sorted(new):
        lines.insert(section_end(lines, section), row)
    return '\n'.join(regenerate_tallies(lines)), fragments(layout.gap_dir)


def check_gap(layout, errors):
    text = read(layout.gap)
    try:
        lines = text.split('\n')
        rows = gap_rows(lines)
        ids = [r[2] for r in rows]
        for g in sorted({g for g in ids if ids.count(g) > 1}):
            errors.append(f'GAP-LEGACY-VS-SWIFT.md: {g} appears more than once')
        if '\n'.join(regenerate_tallies(lines)) != text:
            errors.append('GAP-LEGACY-VS-SWIFT.md: the H.1 list or the Counts table is not the generated one (run tooling/docs/fold.py)')
        sections = gap_sections(lines)
    except FoldError as e:
        errors.append(str(e))
        return
    for p in fragments(layout.gap_dir):
        try:
            gid, _, section, _, _, _ = read_gap_fragment(p)
        except FoldError as e:
            errors.append(str(e))
            continue
        if gid in ids:
            errors.append(f'{layout.rel(p)}: {gid} is already a row of GAP-LEGACY-VS-SWIFT.md (direct edit and fragment for the same issue)')
        if section not in sections:
            errors.append(f'{layout.rel(p)}: no GAP section "{section}"')


# ---------------------------------------------------------------------- CLI

def check(layout):
    errors = []
    check_changelog(layout, errors)
    check_gap(layout, errors)
    return errors


def fold(layout, write=True):
    """Fold both families. Nothing is written unless both fold cleanly. -> the fragments folded (or to fold)."""
    cl_text, cl_frags = fold_changelog(layout)
    gap_text, gap_frags = fold_gap(layout)
    done = [f'changelog: {p.name}' for p in cl_frags] + [f'gap: {p.name}' for p in gap_frags]
    if write:
        layout.changelog.write_text(cl_text, encoding='utf-8')
        layout.gap.write_text(gap_text, encoding='utf-8')
        for p in cl_frags + gap_frags:
            p.unlink()
    return done


def main(argv=None, layout=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--check', action='store_true', help='validate fragments and tallies, change nothing (CI)')
    ap.add_argument('--dry-run', action='store_true', help='print what folding would do, change nothing')
    args = ap.parse_args(argv)
    layout = layout or Layout()
    if args.check:
        errors = check(layout)
        for e in errors:
            print(f'::error::{e}' if 'GITHUB_ACTIONS' in os.environ else f'ERROR {e}')
        print('docs fold check: ' + ('FAILED' if errors else 'ok'))
        return 1 if errors else 0
    try:
        done = fold(layout, write=not args.dry_run)
    except FoldError as e:
        print(f'ERROR {e}')
        return 1
    verb = 'would fold' if args.dry_run else 'folded'
    print(f'{verb} {len(done)} fragment(s)')
    for d in done:
        print(' ', d)
    return 0


if __name__ == '__main__':
    sys.exit(main())
