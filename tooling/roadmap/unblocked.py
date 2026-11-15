"""After a merge: which lots just became unblocked?
Usage: python3 unblocked.py LOT-084 [LOT-126 ...]   (lots just closed; run `sync_state.py --fetch` first so that state.json knows the closure)"""
import sys
import m5
from generate import rows, deps, done, ON_HOLD, NEEDS_DECISION, M1, M2, M3, M4, M5
just = set(sys.argv[1:])
ms = {l: m for m, s in (('M1', M1), ('M2', M2), ('M3', M3), ('M4', M4), ('M5', M5)) for l in s}
for l, r in sorted(rows.items()):
    if done(l) or (l in M5 and not m5.M5_OPEN): continue  # M5 lots open by the orchestrator's decision
    if r['issue'] in ON_HOLD | NEEDS_DECISION: continue  # a decision holds it or is missing: a merge never moves it (#835)
    d = [x for x in deps(r) if x in rows]
    if just & set(d) and all(done(x) for x in d):
        print(f"{l} #{r['issue']} [{ms[l]}] now unblocked (deps {', '.join(x[4:] for x in d)}) → check captures, relabel status: ready, refresh #324/#166")
