"""M5 · UX evolutions membership (operator decisions 2026-11-02, #379): the lots moved whole out of M2 and M4.

The (b) halves of the splits are the lots of the `## M5 · UX evolutions` section of docs/LOTS.md (sec starts with 'M5').
"""
MOVED = [100, 101, 110, 112, 138, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154]


def moved_ids():
    return {'LOT-%03d' % n for n in MOVED}


def is_m5(row):
    return row['lot'] in moved_ids() or row['sec'].startswith('M5')
