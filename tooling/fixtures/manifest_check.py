#!/usr/bin/env python3
"""Check that the corpus manifest and the capture MANIFEST.md name the same captures (#773).

    manifest_check.py [--corpus corpus.json|corpus.d] [--manifest .../captures/MANIFEST.md]

Every corpus id must be named in the capture table of MANIFEST.md (a grouped row such as `| T11, T11h |` names
each id), and every id of that table must exist in the corpus. Only the table whose header starts with `Id` is
read: the "Store" tables, the "Not captured" table and the prose are not capture rows, and a row whose first
cell is in parentheses (`(oracles)`) points to oracle files, it is not a capture. Exit 0 when they agree.
"""
import argparse
import collections
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import publish  # noqa: E402

DEFAULT_CORPUS = publish.DEFAULT_MANIFEST  # follows the corpus layout
DEFAULT_MANIFEST = os.path.join(HERE, "..", "..", "Packages", "HFRKit", "Tests", "HFRParsingTests", "Fixtures",
                                "captures", "MANIFEST.md")


def first_cell(line):
    """First cell of a table row, stripped."""
    return line.strip().strip("|").split("|", 1)[0].strip()


def manifest_ids(text):
    """Capture ids of the MANIFEST capture table (header `| Id |`), in order; grouped rows give several ids."""
    ids, in_table = [], False
    for line in text.splitlines():
        if not line.lstrip().startswith("|"):
            if in_table:
                break
            continue
        cell = first_cell(line)
        if not in_table:
            in_table = cell == "Id"
            continue
        if re.fullmatch(r"[-:\s]*", cell):
            continue
        if cell.startswith("("):  # a pointer row such as `(oracles)`, not a capture
            continue
        ids.extend(t.strip("` ") for t in cell.split(",") if t.strip("` "))
    if not in_table:
        raise ValueError("no capture table (header `| Id |`) in the manifest")
    return ids


def duplicates(ids):
    return sorted(k for k, n in collections.Counter(ids).items() if n > 1)


def problems(corpus, manifest):
    """Sorted human-readable problems between a list of corpus ids and a list of MANIFEST ids."""
    out = ["%s: duplicate id in the corpus" % i for i in duplicates(corpus)]
    out += ["%s: named twice in MANIFEST.md" % i for i in duplicates(manifest)]
    out += ["%s: in the corpus but no row of MANIFEST.md names it" % i for i in sorted(set(corpus) - set(manifest))]
    out += ["%s: in MANIFEST.md but not in the corpus" % i for i in sorted(set(manifest) - set(corpus))]
    return sorted(out)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--corpus", default=DEFAULT_CORPUS)
    p.add_argument("--manifest", default=DEFAULT_MANIFEST)
    args = p.parse_args(argv)
    try:
        with open(args.manifest, encoding="utf-8") as fh:
            text = fh.read()
        found = problems([e["id"] for e in publish.load_manifest(args.corpus)], manifest_ids(text))
    except (OSError, ValueError) as exc:
        print("FAIL", exc, file=sys.stderr)
        return 1
    for line in found:
        print("FAIL", line, file=sys.stderr)
    if found:
        return 1
    print("OK: corpus and MANIFEST.md name the same captures")
    return 0


if __name__ == "__main__":
    sys.exit(main())
