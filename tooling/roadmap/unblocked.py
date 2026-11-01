"""After a merge: which lots just became unblocked?
Usage: python3 unblocked.py LOT-084 [LOT-126 ...]   (lots just closed; run `sync_state.py --fetch` first so that state.json knows the closure)"""
import sys
from generate import rows, deps, done, M1, M2, M3, M4
just = set(sys.argv[1:])
ms = {l: m for m, s in (('M1', M1), ('M2', M2), ('M3', M3), ('M4', M4)) for l in s}
for l, r in sorted(rows.items()):
    if done(l): continue
    d = [x for x in deps(r) if x in rows]
    if just & set(d) and all(done(x) for x in d):
        print(f"{l} #{r['issue']} [{ms[l]}] now unblocked (deps {', '.join(x[4:] for x in d)}) → check captures, relabel status: ready, refresh #324/#166")
