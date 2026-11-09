"""M5 · UX evolutions membership (operator decisions 2026-11-02, #379): the lots moved whole out of M2 and M4.

The (b) halves of the splits are the lots of the `## M5 · UX evolutions` section of docs/LOTS.md (sec starts with 'M5').
LOT-100, 101, 146 and 147 came back to M4 on 2026-11-09 (operator, #655): the legacy reference `2fe43da3` has them,
so they are backports of legacy evolution, not evolutions. LOT-179 (cache sizes) left the M5 section for the same
reason; cache clearing, which legacy cannot reach, is LOT-187 there.
"""
MOVED = [110, 112, 138, 141, 142, 143, 144, 145, 148, 149, 150, 151, 152, 153, 154]


def moved_ids():
    return {'LOT-%03d' % n for n in MOVED}


def is_m5(row):
    return row['lot'] in moved_ids() or row['sec'].startswith('M5')

# False while M5 is closed: the sweep leaves M5 lots blocked and the boards show them as "not opened". The
# orchestrator sets it to True to open M5 (operator decisions 2026-11-02, #379).
M5_OPEN = False

# Standalone (a) follow-ups of the UXD decisions: issues that are not lots, with the milestone whose completion
# they gate (#413). The boards list them under their milestone.
FOLLOWUPS = {
    424: ('M1', 'Reader: hide the tab bar while a topic is open (UXD-02)'),
    425: ('M2', 'Account menu: avatar in every list toolbar (UXD-03)'),
    426: ('M2', 'Reselecting a tab refreshes it, with a haptic (UXD-04)'),
    427: ('M2', 'Restore the legacy Catégories list and the Tous / Favoris / Suivis / Lus filter (UXD-05, 06)'),
    428: ('M4', 'Reader page controls: the legacy layout (UXD-10), M4, absorbed by LOT-186 (operator decision 2026-11-07, #545)'),
    429: ('M2', 'Composer: swipe-down saves the draft (UXD-15)'),
    430: ('M2', 'Account menu: restore "Déconnexion" (UXD-21)'),
    431: ('M2', 'Large iPhone in landscape: full-width reader (UXD-24)'),
    437: ('M2', 'Composer: block keyboard emoji while typing (UXD-16)'),
    432: ('M4', 'iPhone Duo: the cover screen is filled (UXD-25)'),
}
