"""Derive lots.json from docs/LOTS.md (the plan). Usage: python3 lots_from_md.py [LOTS.md] [out.json]"""
import json
import re
import sys
from pathlib import Path

COLS = ['lot', 'scope', 'module', 'diff', 'model', 'deps', 'audit', 'prio', 'issue']


def split_row(line):
    """Split a markdown table row on unescaped pipes outside backtick spans."""
    cells, cur, tick, esc = [], '', False, False
    for ch in line.strip()[1:-1]:
        if esc:
            cur += ch; esc = False
        elif ch == '\\':
            cur += ch; esc = True
        elif ch == '`':
            tick = not tick; cur += ch
        elif ch == '|' and not tick:
            cells.append(cur.strip()); cur = ''
        else:
            cur += ch
    cells.append(cur.strip())
    return cells


def parse(text):
    rows, sec, sub = [], None, None
    for line in text.splitlines():
        if line.startswith('## '):
            sec, sub = line[3:].strip(), None
        elif line.startswith('### '):
            sub = line[4:].strip()
        elif line.startswith('| LOT-'):
            c = split_row(line)
            if len(c) != len(COLS):
                raise ValueError(f'{len(c)} cells, want {len(COLS)}: {line[:80]}')
            r = dict(zip(COLS, c))
            r['star'] = r['lot'].endswith('★')
            r['lot'] = r['lot'].split()[0]
            m = re.search(r'/issues/(\d+)', r['issue'])
            if not m:
                raise ValueError(f'no issue link: {line[:80]}')
            r['issue'] = int(m.group(1))
            r['sec'], r['sub'] = sec, sub
            rows.append(r)
    ids = [r['lot'] for r in rows]
    if len(ids) != len(set(ids)):
        raise ValueError('duplicate lot ids')
    return [{k: r[k] for k in ('lot', 'star', 'scope', 'module', 'diff', 'model', 'deps', 'audit', 'prio', 'issue', 'sec', 'sub')} for r in rows]


if __name__ == '__main__':
    here = Path(__file__).resolve().parent
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent.parent / 'docs' / 'LOTS.md'
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else here / 'lots.json'
    rows = parse(src.read_text(encoding='utf-8'))
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=0) + '\n', encoding='utf-8')
    print(f'{len(rows)} lots -> {out}')
